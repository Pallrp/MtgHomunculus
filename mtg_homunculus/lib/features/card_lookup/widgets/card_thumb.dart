import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../theme/picker_tokens.dart';

/// Disk-cached card thumbnail.
///
/// **`small` only.** Thumbnails are fetched *in bulk and repeatedly* — every
/// row of every list, re-requested on each scroll — while detail art is fetched
/// *singly and once*, for a screen that is already online when it opens. So
/// this caches and `Image.network` stays where a full-size image is wanted.
/// Caching 488 × 680 art for a 500-card list would be hundreds of megabytes to
/// serve one screen.
///
/// **Entries are immutable, which is why the lifetime can be long.** The URL
/// carries `?{unix(image_updated_at)}`, so it is content-addressed: when
/// Scryfall replaces a printing's art the URL changes and the old entry is
/// simply never requested again. There is no such thing as a cached image that
/// is *wrong* — only entries that have become unreachable, which LRU and the
/// object cap clear in due course. Nothing is ever revalidated against the
/// server.
class CardThumb extends StatelessWidget {
  /// Long, because nothing rots. It exists so a thumbnail viewed once in March
  /// is not still holding a slot in September — housekeeping, not correctness.
  static const _stalePeriod = Duration(days: 120);

  /// `flutter_cache_manager` caps on *count*, not bytes. At ~15 KB a `small`
  /// JPEG this lands near 45 MB, inside the 30-60 MB the device can spare next
  /// to a 42 MB card database. The count is chosen to hit that band.
  static const _maxObjects = 3000;

  static final manager = CacheManager(
    Config(
      'mtg_card_thumbs',
      stalePeriod: _stalePeriod,
      maxNrOfCacheObjects: _maxObjects,
    ),
  );

  final String? url;
  final BoxFit fit;

  const CardThumb({super.key, required this.url, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final t = PickerTokens.of(context);
    final u = url;
    if (u == null) return _blank(t);

    return CachedNetworkImage(
      imageUrl: u,
      cacheManager: manager,
      fit: fit,
      // No cross-fade: these appear a dozen at a time in a scrolling list, and
      // a dozen simultaneous fades reads as the list lurching.
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, _) => ColoredBox(color: t.surface2),
      errorWidget: (_, _, _) => ColoredBox(
        color: t.surface2,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 14,
          color: t.textFaint,
        ),
      ),
    );
  }

  Widget _blank(PickerTokens t) => ColoredBox(color: t.surface2);
}
