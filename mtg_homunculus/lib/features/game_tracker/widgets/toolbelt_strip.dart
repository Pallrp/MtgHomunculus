import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/toolbelt_tool.dart';
import 'toolbelt_tool_item.dart';
import 'pass_diamond.dart' show kPassDiamondClearance;

// Cross-section width of the vertical strip.
const double kToolbeltStripHeight = 72.0;

/// Animated vertical toolbelt strip rendered by [GameTrackerScreen].
///
/// The parent [Positioned] widget handles the expand-from-centre animation.
/// This widget fills whatever space it is given and fades its content in once
/// the strip is more than 60 % open.
///
/// Items scroll through a single [Scrollable] whose viewport is split into two
/// windows (above and below the PassDiamond gap). Window B always reads from
/// [kPassDiamondClearance] ahead of window A — a portal with no sync logic.
/// Tapping the diamond (handled by the screen) closes the strip.
class ToolbeltStrip extends StatelessWidget {
  final Animation<double> animation;
  final List<ToolbeltTool> tools;

  const ToolbeltStrip({
    super.key,
    required this.animation,
    required this.tools,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value;
        if (v == 0) return const SizedBox.shrink();

        final showContent = v > 0.6;
        final bg = Theme.of(context).colorScheme.surfaceContainer;

        return Material(
          color: bg.withValues(alpha: 0.95),
          elevation: 4,
          child: showContent
              ? _PortalScrollable(tools: tools)
              : const SizedBox.expand(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Single-Scrollable portal layout — always vertical.
//
// One Scrollable drives two rendering windows. Window A shows list content
// from [pos] onward; window B shows content from [pos + windowA] onward —
// skipping the diamond gap. Items that leave A's far edge enter B's near edge
// on the same frame.

class _PortalScrollable extends StatefulWidget {
  final List<ToolbeltTool> tools;

  const _PortalScrollable({required this.tools});

  @override
  State<_PortalScrollable> createState() => _PortalScrollableState();
}

class _PortalScrollableState extends State<_PortalScrollable> {
  late final ScrollController _ctrl;

  @override
  void initState() {
    super.initState();
    final bigN = widget.tools.length * 10000;
    _ctrl = ScrollController(
      initialScrollOffset: (bigN ~/ 2) * kToolbeltStripHeight,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gap = kPassDiamondClearance;

    return LayoutBuilder(builder: (ctx, constraints) {
      final totalExtent = constraints.maxHeight;
      final windowA = max(0.0, (totalExtent - gap) / 2);
      final windowB = max(0.0, totalExtent - gap - windowA);
      final viewportExtent = windowA + windowB;
      final bigN = widget.tools.length * 10000;
      final contentExtent = bigN * kToolbeltStripHeight;
      final maxScroll = max(0.0, contentExtent - viewportExtent);

      return Scrollable(
        controller: _ctrl,
        axisDirection: AxisDirection.down,
        physics: const ClampingScrollPhysics(),
        viewportBuilder: (ctx, offset) {
          return _ViewportDimSetter(
            offset: offset,
            viewportExtent: viewportExtent,
            contentExtent: contentExtent,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) {
                final pos = _ctrl.hasClients
                    ? _ctrl.offset.clamp(0.0, maxScroll)
                    : 0.0;
                return Stack(children: [
                  // Window A — content before the diamond gap.
                  _Window(
                    mainStart: 0,
                    mainSize: windowA,
                    child: _ListWindow(
                      tools: widget.tools,
                      scrollOffset: pos,
                      windowSize: windowA,
                    ),
                  ),
                  // Window B — content after the gap (portal exit).
                  _Window(
                    mainStart: windowA + gap,
                    mainSize: windowB,
                    child: _ListWindow(
                      tools: widget.tools,
                      scrollOffset: pos + windowA,
                      windowSize: windowB,
                    ),
                  ),
                ]);
              },
            ),
          );
        },
      );
    });
  }
}

// ---------------------------------------------------------------------------

class _Window extends StatelessWidget {
  final double mainStart;
  final double mainSize;
  final Widget child;

  const _Window({
    required this.mainStart,
    required this.mainSize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: mainStart,
      left: 0,
      right: 0,
      height: mainSize,
      child: ClipRect(child: child),
    );
  }
}

// ---------------------------------------------------------------------------

class _ListWindow extends StatelessWidget {
  final List<ToolbeltTool> tools;
  final double scrollOffset;
  final double windowSize;

  const _ListWindow({
    required this.tools,
    required this.scrollOffset,
    required this.windowSize,
  });

  @override
  Widget build(BuildContext context) {
    const ext = kToolbeltStripHeight;
    final first = (scrollOffset / ext).floor();
    final last  = ((scrollOffset + windowSize) / ext).ceil();

    return Stack(
      children: [
        for (int i = first; i < last; i++)
          Positioned(
            top: i * ext - scrollOffset,
            left: 0,
            right: 0,
            height: ext,
            child: ToolbeltToolItem(tool: tools[i % tools.length]),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal RenderProxyBox that reports viewport and content extents to the
// Scrollable's ViewportOffset during layout.

class _ViewportDimSetter extends SingleChildRenderObjectWidget {
  final ViewportOffset offset;
  final double viewportExtent;
  final double contentExtent;

  const _ViewportDimSetter({
    required this.offset,
    required this.viewportExtent,
    required this.contentExtent,
    super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderViewportDimSetter(
        offset: offset,
        viewportExtent: viewportExtent,
        contentExtent: contentExtent,
      );

  @override
  void updateRenderObject(
      BuildContext context, _RenderViewportDimSetter renderObject) {
    renderObject
      ..offset = offset
      ..viewportExtent = viewportExtent
      ..contentExtent = contentExtent;
  }
}

class _RenderViewportDimSetter extends RenderProxyBox {
  _RenderViewportDimSetter({
    required ViewportOffset offset,
    required double viewportExtent,
    required double contentExtent,
    RenderBox? child,
  })  : _offset = offset,
        _viewportExtent = viewportExtent,
        _contentExtent = contentExtent,
        super(child);

  ViewportOffset _offset;
  double _viewportExtent;
  double _contentExtent;

  set offset(ViewportOffset v) {
    if (_offset == v) return;
    if (attached) _offset.removeListener(markNeedsPaint);
    _offset = v;
    if (attached) _offset.addListener(markNeedsPaint);
    markNeedsLayout();
  }

  set viewportExtent(double v) {
    if (_viewportExtent == v) return;
    _viewportExtent = v;
    markNeedsLayout();
  }

  set contentExtent(double v) {
    if (_contentExtent == v) return;
    _contentExtent = v;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _offset.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    _offset.applyViewportDimension(_viewportExtent);
    _offset.applyContentDimensions(
        0, max(0.0, _contentExtent - _viewportExtent));
    super.performLayout();
  }
}
