// Build script — never ships.
//
//   dart run tool/fuzzy_experiment.dart
//   dart run tool/fuzzy_experiment.dart --queries 80
//
// Does edit-distance matching rescue a garbled OCR card name, or does it just
// return a pile of equally-plausible wrong answers?
//
// Garbles real Scryfall names with the substitutions ML Kit actually makes, then
// searches every unique name. Reports how often the right card wins, and by how
// much — the margin matters more than the hit rate, because a win by one
// character is a coin flip on the next frame.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '_paths.dart';

/// Character confusions observed in ML Kit output on card scans.
const _confusions = {
  'o': '0', '0': 'o', 'l': '1', '1': 'l', 'i': 'l', 'I': 'l',
  'e': 'c', 'c': 'e', 's': '5', '5': 's', 'a': 'o', 'n': 'r',
  'm': 'n', 'u': 'v', 'v': 'u', 'g': 'q', 'b': 'h', 't': 'f',
};

void main(List<String> args) async {
  final queryCount = _intArg(args, '--queries') ?? 80;

  // ── unique card names ─────────────────────────────────────────────────────
  stdout.write('loading names...');
  final names = <String>{};
  await for (final raw in File(bulkPath)
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    final line = raw.trim();
    if (line.length < 2 || line[0] != '{') continue;
    try {
      final n = (jsonDecode(line) as Map<String, dynamic>)['name'] as String?;
      if (n != null) names.add(n);
    } catch (_) {}
  }
  final unique = names.toList()..sort();
  final normalised = [for (final n in unique) _normalise(n)];
  stdout.writeln('\r${unique.length} unique names '
      '(${(names.join().length / 1024).round()} KB)      ');

  final rng = Random(4242);
  final picks = [
    for (var i = 0; i < queryCount; i++) rng.nextInt(unique.length),
  ];

  stdout.writeln('');
  stdout.writeln('${'garble'.padRight(9)}${'rank-1'.padLeft(8)}'
      '${'mean dist'.padLeft(11)}${'mean margin'.padLeft(13)}'
      '${'margin<=1'.padLeft(11)}${'ms/query'.padLeft(10)}');
  stdout.writeln('-' * 62);

  for (final rate in [0.0, 0.05, 0.10, 0.20]) {
    var hits = 0, distSum = 0, marginSum = 0, thin = 0;
    final times = <int>[];

    for (final idx in picks) {
      final query = _normalise(_garble(unique[idx], rate, rng));

      final sw = Stopwatch()..start();
      // A FIXED cutoff, not `best`. Passing the running best makes every losing
      // comparison return best+1 -- the runner-up then looks one away from the
      // winner no matter what, which is an artifact of the early exit rather
      // than a measurement.
      const cutoff = 12;
      var best = 99, bestIdx = -1, second = 99;
      for (var i = 0; i < normalised.length; i++) {
        final d = _editDistance(query, normalised[i], cutoff);
        if (d < best) {
          second = best;
          best = d;
          bestIdx = i;
        } else if (d < second) {
          second = d;
        }
      }
      sw.stop();
      times.add(sw.elapsedMicroseconds);

      if (bestIdx == idx) hits++;
      distSum += best;
      final margin = second - best;
      marginSum += margin;
      if (margin <= 1) thin++;
    }

    times.sort();
    stdout.writeln(
      '${'${(rate * 100).round()}%'.padRight(9)}'
      '${'${(100 * hits / picks.length).toStringAsFixed(0)}%'.padLeft(8)}'
      '${(distSum / picks.length).toStringAsFixed(1).padLeft(11)}'
      '${(marginSum / picks.length).toStringAsFixed(1).padLeft(13)}'
      '${'${(100 * thin / picks.length).toStringAsFixed(0)}%'.padLeft(11)}'
      '${(times[times.length ~/ 2] / 1000).toStringAsFixed(1).padLeft(10)}',
    );
  }

  stdout.writeln('');
  stdout.writeln('rank-1     = the correct name scored best');
  stdout.writeln('margin     = gap to the runner-up; <=1 means a coin flip');
}

// ---------------------------------------------------------------------------

/// Strip everything OCR gets wrong for reasons that are not the letters.
///
/// Punctuation and case carry no identifying information here, and ML Kit
/// invents commas and apostrophes constantly. Removing them before comparing
/// deletes a whole class of mismatch for free.
String _normalise(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    if ((r >= 97 && r <= 122) || (r >= 48 && r <= 57)) {
      b.write(c);
    } else if (c == ' ' && b.isNotEmpty) {
      b.write(' ');
    }
  }
  return b.toString().trim();
}

/// Levenshtein with an early exit.
///
/// [cutoff] is the best distance found so far; once every cell in a row exceeds
/// it this pair cannot win, so it bails. Across 30k names most comparisons stop
/// after two or three rows, which is what makes a full scan affordable.
int _editDistance(String a, String b, int cutoff) {
  if ((a.length - b.length).abs() > cutoff) return cutoff + 1;
  final n = b.length;
  var prev = List<int>.generate(n + 1, (i) => i);
  var curr = List<int>.filled(n + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    var rowMin = i;
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= n; j++) {
      final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j - 1] + cost;
      final del = prev[j] + 1;
      final ins = curr[j - 1] + 1;
      if (del < v) v = del;
      if (ins < v) v = ins;
      curr[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > cutoff) return cutoff + 1;
    final t = prev;
    prev = curr;
    curr = t;
  }
  return prev[n];
}

/// Damage a name the way OCR does: confusable letters, drops, doubles.
String _garble(String s, double rate, Random rng) {
  if (rate <= 0) return s;
  final b = StringBuffer();
  for (final c in s.split('')) {
    if (rng.nextDouble() >= rate) {
      b.write(c);
      continue;
    }
    switch (rng.nextInt(3)) {
      case 0:
        b.write(_confusions[c.toLowerCase()] ?? c);
      case 1:
        break; // dropped
      case 2:
        b..write(c)..write(c);
    }
  }
  return b.toString();
}

int? _intArg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return int.tryParse(args[i + 1]);
}
