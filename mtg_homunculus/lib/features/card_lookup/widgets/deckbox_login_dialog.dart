import 'package:flutter/material.dart';

import '../../../core/logging/app_logger.dart';
import '../data/collection_database.dart';
import '../external/deckbox/deckbox_client.dart';
import '../external/deckbox_sync.dart';

/// What a successful login hands back: the account it saved, and the login's
/// own result for a caller that wants the details.
typedef DeckboxLogin = ({DeckboxLoginResult result, ExternalAccount account});

/// "Add Deckbox account" — the login bubble, shaped like *New listing*.
///
/// UI only: [DeckboxSync.login] signs in, saves the session and records the
/// account and its lists. The dialog pops with them on success; null means
/// cancelled.
///
/// **The password lives in the text field and the one request, nowhere else.**
/// It is not logged, not stored, not part of the result.
class DeckboxLoginDialog extends StatefulWidget {
  const DeckboxLoginDialog({super.key});

  static Future<DeckboxLogin?> show(BuildContext context) =>
      showDialog<DeckboxLogin>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const DeckboxLoginDialog(),
      );

  @override
  State<DeckboxLoginDialog> createState() => _DeckboxLoginDialogState();
}

class _DeckboxLoginDialogState extends State<DeckboxLoginDialog> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      !_busy && _login.text.trim().isNotEmpty && _password.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final (:result, :account) =
          await DeckboxSync.instance.login(_login.text.trim(), _password.text);
      if (!mounted) return;

      if (account == null) {
        // Where it ended up, for the log: nothing else survives this path.
        AppLogger.w(
          'Deckbox login ended ${result.state.name} at '
          '${result.page.status} ${result.page.url.path}',
        );
        setState(() {
          _busy = false;
          _error = switch (result.state) {
            DeckboxSessionState.signedOut => "Deckbox didn't accept that login.",
            DeckboxSessionState.signedIn =>
              "Signed in, but Deckbox didn't show the username. Nothing saved.",
            DeckboxSessionState.unknown =>
              "Logged in, but the page didn't look signed in. Nothing saved.",
          };
        });
        return;
      }
      Navigator.pop(context, (result: result, account: account));
    } on DeckboxException catch (e) {
      AppLogger.w('$e');
      if (mounted) setState(() { _busy = false; _error = '$e'; });
    } catch (e) {
      // Network and TLS failures. Type only: a message could quote the request.
      AppLogger.w('Deckbox login failed: ${e.runtimeType}');
      if (mounted) {
        setState(() { _busy = false; _error = "Couldn't reach Deckbox."; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).textTheme.bodySmall;

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Add Deckbox account'),
        content: SingleChildScrollView(
          // Room for the Email field's floated label, which rides above the
          // field's top edge — the scroll view clips at its bounds (M2 bug #2).
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _login,
                enabled: !_busy,
                autofocus: true,
                autocorrect: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                onChanged: (_) => setState(() {}),
                // Email only: a username was turned away on 2026-10-14, despite
                // the site's own "Email / Login" label.
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Your password goes to deckbox.org and is never saved.',
                  style: dim),
              const SizedBox(height: 4),
              Text(
                'Signed up with Google or Apple? Set a password on deckbox.org first.',
                style: dim,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Log in'),
          ),
        ],
      ),
    );
  }
}
