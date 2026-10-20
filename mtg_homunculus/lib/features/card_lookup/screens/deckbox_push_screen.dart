import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/collection_database.dart';
import '../external/deckbox_sync.dart';
import '../theme/picker_tokens.dart';

/// A push, step by step (M3). It watches a [PushRun] that [DeckboxSync] owns,
/// so **leaving does not stop the push** — the list's *Push* button brings
/// this back while it runs, and anything not sent stays staged with its reason.
///
/// **A clean push goes back to the list by itself**, two seconds after it
/// ends (decided 2026-10-16): nothing stopped, refused, skipped or left
/// staged. Anything else stays up to be read.
class DeckboxPushScreen extends StatefulWidget {
  const DeckboxPushScreen({super.key, required this.run, this.accountName});

  final PushRun run;
  final String? accountName;

  static Future<void> open(BuildContext context, PushRun run, {String? accountName}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DeckboxPushScreen(run: run, accountName: accountName),
      ));

  @override
  State<DeckboxPushScreen> createState() => _DeckboxPushScreenState();
}

class _DeckboxPushScreenState extends State<DeckboxPushScreen> {
  PushRun get run => widget.run;
  String? get accountName => widget.accountName;

  static const _autoBack = Duration(seconds: 2);
  Timer? _back;

  @override
  void initState() {
    super.initState();
    run.addListener(_onRun);
    _onRun();
  }

  @override
  void dispose() {
    run.removeListener(_onRun);
    _back?.cancel();
    super.dispose();
  }

  static bool _clean(PushReport r) =>
      r.stoppedAt == null && r.refusals.isEmpty && r.skipped == 0 && r.leftStaged == 0;

  void _onRun() {
    if (_back != null || !run.finished || !_clean(run.report)) return;
    _back = Timer(_autoBack, () {
      // Only if this screen is still the one showing — not if the user has
      // already gone back, or opened something over it.
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    return Scaffold(
      backgroundColor: t.ground,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pushing to Deckbox'),
            Text(
              [?accountName, run.list.name].join(' · '),
              style: PickerTokens.mono(context, size: 11),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: run,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
            children: [
              _Checklist(run: run),
              const SizedBox(height: 8),
              if (!run.finished)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'You can leave. The push keeps going. Anything not sent stays staged.',
                    style: TextStyle(fontSize: 12.5, color: t.textDim),
                  ),
                )
              else
                _Outcome(run: run),
            ],
          ),
        ),
      ),
    );
  }
}

class _Checklist extends StatelessWidget {
  const _Checklist({required this.run});

  final PushRun run;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final r = run.report;
    final current = run.stage;
    final stoppedIn = r.stoppedIn;

    String? note(PushStage s) => switch (s) {
          PushStage.remove => r.removed == 0 ? null : '${r.removed}',
          PushStage.lower => r.lowered == 0 ? null : '${r.lowered}',
          PushStage.add => r.added == 0 && r.refused == 0
              ? null
              : r.refused == 0
                  ? '${r.added}'
                  : '${r.added} · ${r.refused} refused',
          _ => null,
        };

    _StepState stateOf(PushStage s) {
      if (stoppedIn != null) {
        if (s.index < stoppedIn.index) return _StepState.done;
        return s == stoppedIn ? _StepState.failed : _StepState.todo;
      }
      if (run.finished) return _StepState.done;
      if (current == null) return _StepState.todo;
      if (s.index < current.index) return _StepState.done;
      return s == current ? _StepState.now : _StepState.todo;
    }

    // A stage of many requests says how far it is.
    final p = run.progress;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: [
        for (final s in PushStage.values)
          if (s == current && p != null)
            _Step(label: s.label, state: _StepState.now, note: '${p.done} / ${p.total}', fraction: p.done / p.total)
          else
            _Step(label: s.label, state: stateOf(s), note: note(s)),
        if (r.skipped > 0) _Step(label: 'Skipped: flagged', state: _StepState.skipped, note: '${r.skipped}'),
      ]),
    );
  }
}

enum _StepState { done, now, todo, failed, skipped }

class _Step extends StatelessWidget {
  const _Step({required this.label, required this.state, this.note, this.fraction});

  final String label;
  final _StepState state;
  final String? note;

  /// A stage of many requests: how far, under its line.
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final Widget mark = switch (state) {
      _StepState.done => _circle(t.accent, t.accent, const Icon(Icons.check_rounded, size: 14, color: Colors.white)),
      _StepState.now => SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: t.sync),
        ),
      _StepState.todo => _circle(Colors.transparent, t.line, null),
      _StepState.failed => _circle(t.warning, t.warning, const Icon(Icons.close_rounded, size: 14, color: Colors.white)),
      _StepState.skipped => _circle(Colors.transparent, t.warning, Icon(Icons.remove_rounded, size: 14, color: t.warning)),
    };
    final color = switch (state) {
      _StepState.todo => t.textDim,
      _StepState.skipped || _StepState.failed => t.warning,
      _ => t.text,
    };
    final line = Row(children: [
      mark,
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: color))),
      if (note != null) Text(note!, style: PickerTokens.mono(context, size: 12, color: t.textDim)),
    ]);
    final f = fraction;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: f == null
          ? line
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              line,
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(value: f, minHeight: 3, color: t.sync, backgroundColor: t.syncSoft),
                ),
              ),
            ]),
    );
  }

  static Widget _circle(Color fill, Color border, Widget? child) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 1.5),
        ),
        alignment: Alignment.center,
        child: child,
      );
}

/// What landed, what is still staged, and why — or where it stopped.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.run});

  final PushRun run;

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final r = run.report;

    Widget banner({
      required bool warn,
      required IconData icon,
      required List<InlineSpan> text,
      Widget? action,
    }) =>
        Container(
          color: warn ? t.warningBg : t.syncSoft,
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: warn ? t.warning : t.syncInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(children: text),
                style: TextStyle(fontSize: 13, color: warn ? t.text : t.syncInk),
              ),
            ),
            ?action,
          ]),
        );

    final stopped = r.stoppedAt;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (stopped == null)
            banner(
              warn: false,
              icon: Icons.check_rounded,
              text: [
                TextSpan(text: '${r.pushed} pushed. ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(
              text: r.leftStaged == 0
                  ? 'Nothing left staged — back to the list in a moment.'
                  : '${r.leftStaged} still staged.',
            ),
              ],
              action: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back to list')),
            )
          else
            banner(
              warn: true,
              icon: Icons.warning_amber_rounded,
              text: [
                TextSpan(
                  text: 'Stopped at “${r.stoppedIn?.label ?? 'the start'}”. ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: r.pushed == 0
                      ? 'Nothing was sent. Everything is still staged.'
                      : '${r.pushed} went through. The rest is still staged.',
                ),
              ],
            ),
          for (final x in r.refusals)
            banner(
              warn: true,
              icon: Icons.block_rounded,
              text: [
                TextSpan(text: x.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' — ${x.reason}. Still staged.'),
              ],
            ),
          if (r.skipped > 0)
            banner(
              warn: true,
              icon: Icons.flag_outlined,
              text: [
                TextSpan(
                  text: '${r.skipped} flagged ${r.skipped == 1 ? 'removal' : 'removals'} not sent. ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: "Deckbox no longer matches what was staged — check them in To remove."),
              ],
            ),
          if (stopped != null)
            Container(
              color: t.surface,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: t.surface2, borderRadius: BorderRadius.circular(8)),
                  child: Text(stopped, style: PickerTokens.mono(context, size: 11, color: t.textDim)),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Clipboard.setData(ClipboardData(text: _details(run))),
                      child: const Text('Copy details'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: t.sync),
                      onPressed: () => _tryAgain(context, run.list),
                      child: const Text('Try again'),
                    ),
                  ),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }

  static String _details(PushRun run) => [
        'Deckbox push — ${run.list.name}',
        ...run.report.steps,
        'stopped: ${run.report.stoppedAt}',
      ].join('\n');

  /// A fresh push of the same list, on this same screen's route.
  Future<void> _tryAgain(BuildContext context, ExternalList list) async {
    final again = DeckboxSync.instance.startPush(list);
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => DeckboxPushScreen(run: again),
    ));
  }
}
