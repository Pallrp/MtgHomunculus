import 'package:flutter/material.dart';
import '../models/players_by_position.dart';

/// Generic board-layout grid — Column of edge rows + two-column side area.
///
/// Works for any [T] that has been bucketed into a [PlayersByPosition].
/// [slotBuilder] returns the widget for a single item.
/// [edgeFlex] and [sideFlex] tune the relative height of edge rows vs the
/// side area — callers set these to match the original per-usage flex values.
///
/// **Flat edge layout** — when [flatOrder] is provided, the widget renders a
/// compact two-row layout suited for short-edge cards:
///   • a horizontal row of the [flatOrder] items (opponents, in caller-defined
///     order) sized at flex 2
///   • the self cell pulled from [positions] (topEdge or bottomEdge) at flex 1
/// [selfAtTop] controls whether the self cell appears above the opponent row
/// (use `true` for a top-edge invoker who reads their card upside-down).
class PlayerGridLayout<T> extends StatelessWidget {
  final PlayersByPosition<T> positions;
  final Widget Function(T) slotBuilder;
  final int edgeFlex;
  final int sideFlex;
  /// When non-null, activates the flat edge layout (see class doc).
  final List<T>? flatOrder;
  /// Puts the self cell above the opponent row when true (top-edge invoker).
  final bool selfAtTop;

  const PlayerGridLayout({
    super.key,
    required this.positions,
    required this.slotBuilder,
    this.edgeFlex = 2,
    this.sideFlex = 1,
    this.flatOrder,
    this.selfAtTop = false,
  });

  @override
  Widget build(BuildContext context) {
    if (flatOrder != null) {
      final selfItem = selfAtTop
          ? positions.topEdge.first
          : positions.bottomEdge.first;

      final opponentRow = Expanded(
        flex: 2,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: flatOrder!
              .map((item) => Expanded(child: slotBuilder(item)))
              .toList(),
        ),
      );
      final selfCell = Expanded(flex: 1, child: slotBuilder(selfItem));

      return Column(
        children: selfAtTop
            ? [selfCell, opponentRow]
            : [opponentRow, selfCell],
      );
    }

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
