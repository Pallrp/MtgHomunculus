import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/toolbelt_tool.dart';
import 'toolbelt_tool_item.dart';
import 'pass_diamond.dart' show kPassDiamondClearance;

// Cross-section size of the strip (height for horizontal, width for vertical).
const double kToolbeltStripHeight = 72.0;

// Width of the close-chevron buttons at each end of a strip.
const double kToolbeltChevronWidth = 44.0;

/// Animated toolbelt strip rendered by [GameTrackerScreen].
///
/// The parent [Positioned] widget handles the expand-from-centre animation.
/// This widget fills whatever space it is given and fades its content in once
/// the strip is more than 60 % open.
///
/// Items scroll through a single [Scrollable] whose viewport is split into two
/// windows (above and below the PassDiamond gap). Window B always reads from
/// [kPassDiamondClearance] ahead of window A, so whatever exits A enters B
/// simultaneously — a portal with no sync logic.
class ToolbeltStrip extends StatelessWidget {
  final Axis axis;
  final Animation<double> animation;
  final List<ToolbeltTool> tools;
  final VoidCallback onClose;

  const ToolbeltStrip({
    super.key,
    required this.axis,
    required this.animation,
    required this.tools,
    required this.onClose,
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
          child: axis == Axis.horizontal
              ? _HorizontalStrip(
                  tools: tools,
                  showContent: showContent,
                  onClose: onClose,
                )
              : _VerticalStrip(
                  tools: tools,
                  showContent: showContent,
                  onClose: onClose,
                ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _HorizontalStrip extends StatelessWidget {
  final List<ToolbeltTool> tools;
  final bool showContent;
  final VoidCallback onClose;

  const _HorizontalStrip({
    required this.tools,
    required this.showContent,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (!showContent) return const SizedBox.expand();
    return Row(
      children: [
        _Chevron(icon: Icons.chevron_left, onTap: onClose, axis: Axis.horizontal),
        Expanded(child: _PortalScrollable(tools: tools, axis: Axis.horizontal)),
        _Chevron(icon: Icons.chevron_right, onTap: onClose, axis: Axis.horizontal),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _VerticalStrip extends StatelessWidget {
  final List<ToolbeltTool> tools;
  final bool showContent;
  final VoidCallback onClose;

  const _VerticalStrip({
    required this.tools,
    required this.showContent,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    if (!showContent) return const SizedBox.expand();
    return Column(
      children: [
        _Chevron(icon: Icons.expand_less, onTap: onClose, axis: Axis.vertical),
        Expanded(child: _PortalScrollable(tools: tools, axis: Axis.vertical)),
        _Chevron(icon: Icons.expand_more, onTap: onClose, axis: Axis.vertical),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Single-Scrollable portal layout.
//
// One Scrollable (one gesture handler, one physics simulation) drives two
// rendering windows. Window A shows list content from [pos] onward; window B
// shows content from [pos + windowA] onward — skipping the diamond gap.
// Items that leave A's far edge enter B's near edge on the same frame.

class _PortalScrollable extends StatefulWidget {
  final List<ToolbeltTool> tools;
  final Axis axis;

  const _PortalScrollable({required this.tools, required this.axis});

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
    final isV = widget.axis == Axis.vertical;

    return LayoutBuilder(builder: (ctx, constraints) {
      final totalExtent = isV ? constraints.maxHeight : constraints.maxWidth;
      // Equal windows on each side of the diamond gap.
      final windowA = max(0.0, (totalExtent - gap) / 2);
      final windowB = max(0.0, totalExtent - gap - windowA);
      final viewportExtent = windowA + windowB;
      final bigN = widget.tools.length * 10000;
      final contentExtent = bigN * kToolbeltStripHeight;
      final maxScroll = max(0.0, contentExtent - viewportExtent);

      return Scrollable(
        controller: _ctrl,
        axisDirection: isV ? AxisDirection.down : AxisDirection.right,
        physics: const ClampingScrollPhysics(),
        viewportBuilder: (ctx, offset) {
          return _ViewportDimSetter(
            offset: offset,
            viewportExtent: viewportExtent,
            contentExtent: contentExtent,
            // AnimatedBuilder listens to _ctrl so items rebuild on scroll.
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) {
                final pos = _ctrl.hasClients
                    ? _ctrl.offset.clamp(0.0, maxScroll)
                    : 0.0;
                return Stack(children: [
                  // Window A — content before the diamond gap.
                  _Window(
                    axis: widget.axis,
                    mainStart: 0,
                    mainSize: windowA,
                    child: _ListWindow(
                      tools: widget.tools,
                      axis: widget.axis,
                      scrollOffset: pos,
                      windowSize: windowA,
                    ),
                  ),
                  // Window B — content after the gap (portal exit).
                  // scrollOffset is pos + windowA, so B is always reading
                  // exactly where A left off — no sync needed.
                  _Window(
                    axis: widget.axis,
                    mainStart: windowA + gap,
                    mainSize: windowB,
                    child: _ListWindow(
                      tools: widget.tools,
                      axis: widget.axis,
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
// Positions and clips one rendering window within the portal stack.

class _Window extends StatelessWidget {
  final Axis axis;
  final double mainStart;
  final double mainSize;
  final Widget child;

  const _Window({
    required this.axis,
    required this.mainStart,
    required this.mainSize,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isV = axis == Axis.vertical;
    return Positioned(
      top: isV ? mainStart : 0,
      bottom: isV ? null : 0,
      left: isV ? 0 : mainStart,
      right: isV ? 0 : null,
      height: isV ? mainSize : null,
      width: isV ? null : mainSize,
      child: ClipRect(child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// Passive renderer: places only the items that fall within the window's
// [scrollOffset, scrollOffset + windowSize] band. No scroll logic here.

class _ListWindow extends StatelessWidget {
  final List<ToolbeltTool> tools;
  final Axis axis;
  final double scrollOffset;
  final double windowSize;

  const _ListWindow({
    required this.tools,
    required this.axis,
    required this.scrollOffset,
    required this.windowSize,
  });

  @override
  Widget build(BuildContext context) {
    const ext = kToolbeltStripHeight;
    final first = (scrollOffset / ext).floor();
    final last = ((scrollOffset + windowSize) / ext).ceil();
    final isV = axis == Axis.vertical;

    return Stack(
      children: [
        for (int i = first; i < last; i++)
          Positioned(
            top: isV ? i * ext - scrollOffset : 0,
            bottom: isV ? null : 0,
            left: isV ? 0 : i * ext - scrollOffset,
            right: isV ? 0 : null,
            height: isV ? ext : null,
            width: isV ? null : ext,
            child: ToolbeltToolItem(tool: tools[i % tools.length]),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Minimal RenderProxyBox that reports viewport and content extents to the
// Scrollable's ViewportOffset during layout. Without this the scroll position
// has no concept of its extent limits, so clamping physics break.

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

// ---------------------------------------------------------------------------

class _Chevron extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Axis axis;

  const _Chevron({
    required this.icon,
    required this.onTap,
    required this.axis,
  });

  @override
  Widget build(BuildContext context) {
    final isV = axis == Axis.vertical;
    return SizedBox(
      width: isV ? kToolbeltStripHeight : kToolbeltChevronWidth,
      height: isV ? kToolbeltChevronWidth : kToolbeltStripHeight,
      child: IconButton(
        icon: Icon(icon),
        onPressed: onTap,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
