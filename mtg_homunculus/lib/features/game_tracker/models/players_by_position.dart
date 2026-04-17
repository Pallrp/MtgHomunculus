import 'player.dart';

/// Groups a list of any seat-positioned items into the four grid buckets.
///
/// Generic over [T] so it works with both [Player] (live game) and
/// [_DraftPlayer] (setup sheet) without requiring a shared base class.
class PlayersByPosition<T> {
  final List<T> topEdge;
  final List<T> bottomEdge;
  final List<T> leftSide;
  final List<T> rightSide;

  const PlayersByPosition({
    required this.topEdge,
    required this.bottomEdge,
    required this.leftSide,
    required this.rightSide,
  });

  factory PlayersByPosition.from(
    List<T> items,
    SeatPosition Function(T) seatOf,
  ) =>
      PlayersByPosition(
        topEdge:    items.where((p) => seatOf(p) == SeatPosition.topEdge).toList(),
        bottomEdge: items.where((p) => seatOf(p) == SeatPosition.bottomEdge).toList(),
        leftSide:   items.where((p) => seatOf(p) == SeatPosition.leftSide).toList(),
        rightSide:  items.where((p) => seatOf(p) == SeatPosition.rightSide).toList(),
      );

  int get sideCount => leftSide.length + rightSide.length;
}
