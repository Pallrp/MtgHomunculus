import 'dart:async';
import 'package:flutter/material.dart';
import '../models/toolbelt_tool.dart';
import 'gt_game_scope.dart';
import 'toolbelt_strip.dart' show kToolbeltStripHeight;

class ToolbeltToolItem extends StatefulWidget {
  final ToolbeltTool tool;
  const ToolbeltToolItem({super.key, required this.tool});

  @override
  State<ToolbeltToolItem> createState() => _ToolbeltToolItemState();
}

class _ToolbeltToolItemState extends State<ToolbeltToolItem> {
  Timer? _repeatTimer;

  void _onLongPressStart(LongPressStartDetails _) {
    widget.tool.onLongPress(context);
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (mounted) widget.tool.onLongPress(context);
    });
  }

  void _stopRepeat([dynamic _]) {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = GtGameScope.of(context).game;
    final borderColor = widget.tool.activeBorderColor(game);

    Widget inner = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        widget.tool.buildIcon(game),
        const SizedBox(height: 4),
        Text(
          widget.tool.label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(fontSize: 11),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    if (borderColor != null) {
      inner = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor.withValues(alpha: 0.7),
            width: 1.5,
          ),
        ),
        child: inner,
      );
    }

    return GestureDetector(
      onTap: () => widget.tool.onTap(context),
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _stopRepeat,
      onLongPressCancel: _stopRepeat,
      child: SizedBox.square(
        dimension: kToolbeltStripHeight,
        child: Center(child: inner),
      ),
    );
  }
}
