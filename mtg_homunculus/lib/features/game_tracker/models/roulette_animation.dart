import 'dart:async';
import 'dart:math';

/// Drives a decelerating roulette animation over a fixed list of items.
///
/// Cycles through [items] in the given order, calling [onHighlight] each tick.
/// After 3–4 full loops it lands on a randomly chosen item and calls [onComplete].
///
/// Items should be pre-ordered to match the intended sweep direction — e.g.
/// sorted into clockwise board order so the highlight travels around the table.
///
/// Call [cancel] to abort early (safe from dispose). Call [start] again to
/// restart; any in-progress animation is cancelled first.
class RouletteAnimation {
  Timer? _timer;

  /// Start a new roulette over [items].
  ///
  /// - [onHighlight] fires on every tick with the currently featured item.
  /// - [onComplete]  fires once with the winner when the animation finishes.
  /// - [isMounted]   is checked before every tick; returns false → abort.
  ///   Prevents setState-after-dispose crashes when the widget is gone.
  void start<T>({
    required List<T> items,
    void Function(T item)? onHighlight,
    required void Function(T winner) onComplete,
    required bool Function() isMounted,
  }) {
    assert(items.isNotEmpty, 'RouletteAnimation.start: items must not be empty');
    cancel();

    final n          = items.length;
    final rng        = Random();
    final pickIndex  = rng.nextInt(n);
    final totalCycles = 3 + rng.nextInt(2); // 3–4 full loops before landing
    // +1 so the last tick highlights the winner before onComplete fires.
    final totalSteps = totalCycles * n + pickIndex + 1;
    int step = 0;

    void tick() {
      if (!isMounted()) { cancel(); return; }
      onHighlight?.call(items[step % n]);
      step++;
      if (step >= totalSteps) {
        cancel();
        onComplete(items[pickIndex]);
        return;
      }
      // Decelerate over the last 40% of steps: 80 ms → ~500 ms per tick.
      final progress = step / totalSteps;
      final ms = progress < 0.6
          ? 80
          : (80 + ((progress - 0.6) / 0.4) * 420).round();
      _timer = Timer(Duration(milliseconds: ms), tick);
    }

    _timer = Timer(const Duration(milliseconds: 100), tick);
  }

  /// Abort any in-progress animation. Safe to call multiple times.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
