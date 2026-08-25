import 'dart:typed_data';

/// Perceptual hash of a canonical card image.
///
/// **One implementation, two callers.** The build script in `tool/` hashes ~97k
/// Scryfall reference images; the app hashes camera captures at runtime. If those
/// two disagree by a single bit of arithmetic, every runtime hash is
/// incompatible with the shipped index — silently, with no error, just matches
/// that never happen.
///
/// So this file takes **grayscale bytes** and does its own downsampling. Nothing
/// about the hash depends on which imaging library the caller used: OpenCV in the
/// app, the `image` package in the script, anything else later. The only code
/// that touches pixels on the way to a bit is here.
///
/// (The two callers decode *different images* anyway — reference art versus a
/// camera capture. Tolerating that is what a perceptual hash is for. What must
/// not differ is the algorithm.)
class DHash {
  DHash._();

  // ---------------------------------------------------------------------------
  // Parameters — deliberately constants, not arguments
  // ---------------------------------------------------------------------------

  /// Sampling grid. **Do not make these configurable.**
  ///
  /// A flag would let `tool/build_hash_index.dart` and the app's fetcher drift
  /// apart, which is the exact failure this file exists to prevent. Changing the
  /// grid means changing it here, for everyone, and bumping [version].
  ///
  /// The grid is chosen to **match the card's proportions**: `8/11 = 0.727`
  /// against a card's `488/680 = 0.718`. Each cell therefore covers 61 × 61.8
  /// source pixels — aspect 0.99, near-square — so a horizontal comparison spans
  /// the same physical distance as a vertical one and the two are comparable.
  ///
  /// Contrast 16 × 8, which scored worst of everything tried (2026-08-21): its
  /// cells are 30.5 × 85 px, aspect 0.36, so its horizontal and vertical bits
  /// measure different scales. See `local_data_store.md` → Perceptual Hashing.
  ///
  /// **Invariant: callers must supply a canonically-framed card.** The grid is
  /// relative to whatever image it is handed, so a differently-proportioned
  /// input yields non-square cells and a hash that is not comparable with the
  /// index. `CardWarp` guarantees 488 × 680 on the app side; Scryfall's `normal`
  /// image is 488 × 680 for every card and layout. Nothing here re-crops or
  /// re-scales to enforce it.
  static const int gridWidth  = 8;
  static const int gridHeight = 11;

  /// Horizontal comparisons within each row, plus vertical within each column.
  ///
  /// `(8-1) × 11 = 77` horizontal and `8 × (11-1) = 80` vertical = **157 bits**.
  /// Horizontal-only throws away every vertical gradient, which on a card means
  /// throwing away the frame lines, type line and text-box boundaries — the most
  /// stable structure it has.
  static const int horizontalBits = (gridWidth - 1) * gridHeight;
  static const int verticalBits   = gridWidth * (gridHeight - 1);
  static const int bitCount       = horizontalBits + verticalBits;

  /// 157 bits rounded up to whole bytes. The 3 spare bits are always zero.
  static const int byteLength = (bitCount + 7) ~/ 8;

  /// Stamp stored alongside a built index.
  ///
  /// The app must refuse an index whose version does not match, because a
  /// mismatched index produces no error — only silent non-matching. Bump this
  /// whenever anything above changes.
  static const String version = 'dhash-8x11-hv-v1';

  // ---------------------------------------------------------------------------
  // Hashing
  // ---------------------------------------------------------------------------

  /// Hash [gray], a single-channel 8-bit image of [width] × [height].
  ///
  /// [rowStride] is the byte offset between rows; pass it when the buffer is
  /// padded (an OpenCV `Mat` often is). Defaults to [width].
  ///
  /// Returns [byteLength] bytes, or all-zero if the input is unusable.
  static Uint8List compute(
    Uint8List gray,
    int width,
    int height, {
    int? rowStride,
  }) {
    final out = Uint8List(byteLength);
    if (width <= 0 || height <= 0) return out;

    final cells = _downsample(gray, width, height, rowStride ?? width);
    if (cells == null) return out;

    var bit = 0;
    void push(bool set) {
      if (set) out[bit >> 3] |= 0x80 >> (bit & 7);
      bit++;
    }

    // Horizontal gradients: is each cell darker than the one to its right.
    for (var y = 0; y < gridHeight; y++) {
      for (var x = 0; x < gridWidth - 1; x++) {
        push(cells[y * gridWidth + x] < cells[y * gridWidth + x + 1]);
      }
    }

    // Vertical gradients: is each cell darker than the one below it.
    for (var x = 0; x < gridWidth; x++) {
      for (var y = 0; y < gridHeight - 1; y++) {
        push(cells[y * gridWidth + x] < cells[(y + 1) * gridWidth + x]);
      }
    }

    return out;
  }

  /// Average [gray] down to a [gridWidth] × [gridHeight] grid.
  ///
  /// Box average over each cell's full source footprint, not point sampling.
  /// Averaging is what makes the result robust to noise, focus and small
  /// misalignment — sampling single pixels would make the hash depend on which
  /// pixel happened to land under the grid.
  ///
  /// Returns null when the source is smaller than the grid.
  static Float64List? _downsample(
    Uint8List gray,
    int width,
    int height,
    int rowStride,
  ) {
    if (width < gridWidth || height < gridHeight) return null;
    if (gray.length < (height - 1) * rowStride + width) return null;

    final cells = Float64List(gridWidth * gridHeight);

    for (var gy = 0; gy < gridHeight; gy++) {
      final y0 = (gy * height) ~/ gridHeight;
      final y1 = (((gy + 1) * height) ~/ gridHeight).clamp(y0 + 1, height);

      for (var gx = 0; gx < gridWidth; gx++) {
        final x0 = (gx * width) ~/ gridWidth;
        final x1 = (((gx + 1) * width) ~/ gridWidth).clamp(x0 + 1, width);

        var sum = 0;
        for (var y = y0; y < y1; y++) {
          final row = y * rowStride;
          for (var x = x0; x < x1; x++) {
            sum += gray[row + x];
          }
        }
        cells[gy * gridWidth + gx] = sum / ((y1 - y0) * (x1 - x0));
      }
    }
    return cells;
  }

  // ---------------------------------------------------------------------------
  // Matching
  // ---------------------------------------------------------------------------

  /// Number of differing bits between two hashes.
  ///
  /// **This is a distance, not a probability.** A dHash cannot say "87% sure" —
  /// it says "12 of 157 bits differ", and what counts as a match is a threshold
  /// calibrated against real data, not a confidence score. Scanning all 97k
  /// hashes is a linear pass over ~1.9 MB; no index structure is needed.
  ///
  /// Returns [bitCount] (maximum distance) if the lengths disagree, so a
  /// malformed hash can never look like a good match.
  static int distance(Uint8List a, Uint8List b) {
    if (a.length != b.length || a.length != byteLength) return bitCount;
    var d = 0;
    for (var i = 0; i < byteLength; i++) {
      var x = a[i] ^ b[i];
      while (x != 0) {
        x &= x - 1; // clear the lowest set bit
        d++;
      }
    }
    return d;
  }

  /// Lowercase hex, for logs and debugging. Not a storage format — the index
  /// stores raw bytes.
  static String toHex(Uint8List hash) =>
      hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
