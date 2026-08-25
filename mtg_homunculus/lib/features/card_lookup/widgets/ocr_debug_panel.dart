import 'dart:typed_data';

import 'package:flutter/material.dart';

/// One candidate from a hash scan, resolved to something readable.
class HashCandidate {
  /// `Colossal Dreadmaw · XLN 180`, or the raw id if the card is not in the
  /// database.
  final String label;

  /// Differing bits out of 157.
  final int distance;

  const HashCandidate(this.label, this.distance);
}

/// [dev-tool] Live OCR readout overlaid on the scanner.
///
/// Toggled from the tuning panel. Shows what the identification pipeline
/// actually sees — the perspective-corrected card, the collector-number band
/// blown up, and whatever ML Kit made of it — so tuning can be judged against
/// the OCR result rather than against the border overlay alone.
///
/// Deliberately shows no history: the log file already keeps that.
class OcrDebugPanel extends StatelessWidget {
  /// Perspective-corrected card, PNG bytes.
  final Uint8List? card;

  /// Collector-number band, PNG bytes — rendered at 3× so glyph damage is
  /// visible at a glance.
  final Uint8List? band;

  /// Raw ML Kit output.
  final String text;

  /// Pixels per millimetre across the card's long edge.
  ///
  /// Spike S1 put the OCR floor near 6 px/mm, so this is colour-coded against
  /// that: it explains an empty read faster than the text does.
  final double pxPerMm;

  /// True while a pass is in flight.
  final bool busy;

  /// Nearest cards to this capture's hash, nearest first.
  ///
  /// This is the calibration readout: the threshold in `HashIndex` is a guess
  /// until a real camera capture has been measured against the real index.
  /// Point the scanner at a card you can name and read the top distance.
  final List<HashCandidate> hashes;

  /// Null until the index has loaded — matching is unavailable, not failing.
  final int? indexCount;

  const OcrDebugPanel({
    super.key,
    required this.card,
    required this.band,
    required this.text,
    required this.pxPerMm,
    required this.busy,
    this.hashes = const [],
    this.indexCount,
  });

  static const double _okPxPerMm = 6.0;

  /// The whole point of this panel now: what the index says about this capture.
  Widget _hashRow(TextStyle mono) {
    if (indexCount == null) {
      return Text('dHash  index not loaded',
          style: mono.copyWith(color: Colors.white38));
    }
    if (hashes.isEmpty) {
      return Text('dHash  no match  ($indexCount cards)',
          style: mono.copyWith(color: Colors.orangeAccent));
    }

    final best = hashes.first;
    // Green only when it is both close AND unambiguous — several candidates is
    // the Choose Version path, not a clean identification.
    final clean = best.distance <= 8 && hashes.length == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('dHash', style: mono.copyWith(
              color: Colors.lightBlueAccent,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            )),
            const SizedBox(width: 8),
            Text('${best.distance}/157',
                style: mono.copyWith(
                  color: clean ? Colors.greenAccent : Colors.orangeAccent,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(width: 8),
            Text('${hashes.length} within threshold',
                style: mono.copyWith(color: Colors.white38)),
          ],
        ),
        for (final h in hashes.take(3))
          Padding(
            padding: const EdgeInsets.only(left: 2, top: 2),
            child: Text(
              '${h.distance.toString().padLeft(3)}  ${h.label}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                color: h == best ? Colors.white : Colors.white54,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final good = pxPerMm >= _okPxPerMm;
    final mono = const TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: Colors.white,
      height: 1.35,
    );

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── header ───────────────────────────────────────────────
            Row(
              children: [
                Text('OCR', style: mono.copyWith(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                )),
                const SizedBox(width: 8),
                Text(
                  '${pxPerMm.toStringAsFixed(1)} px/mm',
                  style: mono.copyWith(
                    color: good ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                ),
                if (!good) ...[
                  const SizedBox(width: 4),
                  Text('(needs ~6)', style: mono.copyWith(color: Colors.white38)),
                ],
                const Spacer(),
                if (busy)
                  const SizedBox(
                    width: 10, height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Colors.white54,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            _hashRow(mono),
            const SizedBox(height: 8),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── corrected card ──────────────────────────────────
                if (card != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Image.memory(
                      card!, height: 84, filterQuality: FilterQuality.medium,
                    ),
                  )
                else
                  Container(
                    width: 60, height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(
                      child: Text('no\ncard', textAlign: TextAlign.center,
                          style: mono.copyWith(color: Colors.white38)),
                    ),
                  ),
                const SizedBox(width: 10),

                // ── band + text ─────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 42,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: band == null
                            ? Center(child: Text('no crop',
                                style: mono.copyWith(color: Colors.white38)))
                            : Image.memory(
                                band!,
                                fit: BoxFit.contain,
                                alignment: Alignment.centerLeft,
                                filterQuality: FilterQuality.none, // show the pixels
                              ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        text.isEmpty ? '— empty —' : text.replaceAll('\n', '  /  '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: mono.copyWith(
                          color: text.isEmpty ? Colors.orangeAccent : Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
