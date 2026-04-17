import 'package:flutter/material.dart';
import '../models/players_by_position.dart';

/// Generic board-layout grid — Column of edge rows + two-column side area.
///
/// Works for any [T] that has been bucketed into a [PlayersByPosition].
/// [slotBuilder] returns the widget for a single item.
/// [edgeFlex] and [sideFlex] tune the relative height of edge rows vs the
/// side area — callers set these to match the original per-usage flex values.
class PlayerGridLayout<T> extends StatelessWidget {
  final PlayersByPosition<T> positions;
  final Widget Function(T) slotBuilder;
  final int edgeFlex;
  final int sideFlex;

  const PlayerGridLayout({
    super.key,
    required this.positions,
    required this.slotBuilder,
    this.edgeFlex = 2,
    this.sideFlex = 1,
  });

  @override
  Widget build(BuildContext context) {
    final pos = positions;
    return Column(
      children: [
        if (pos.topEdge.isNotEmpty)
          Expanded(
            flex: edgeFlex,
            child: slotBuilder(pos.topEdge.first),
          ),
        if (pos.sideCount > 0)
          Expanded(
            flex: pos.sideCount * sideFlex,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (pos.leftSide.isNotEmpty)
                  Expanded(
                    child: Column(
                      children: pos.leftSide
                          .map((p) => Expanded(child: slotBuilder(p)))
                          .toList(),
                    ),
                  ),
                if (pos.rightSide.isNotEmpty)
                  Expanded(
                    child: Column(
                      children: pos.rightSide
                          .map((p) => Expanded(child: slotBuilder(p)))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        if (pos.bottomEdge.isNotEmpty)
          Expanded(
            flex: edgeFlex,
            child: slotBuilder(pos.bottomEdge.first),
          ),
      ],
    );
  }
}
