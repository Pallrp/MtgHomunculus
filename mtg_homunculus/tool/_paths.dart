// Shared locations for the two build scripts. Never ships.

import 'dart:io';

/// Package root, derived from this file's own location — **not** the working
/// directory.
///
/// CWD-relative paths silently put the cache wherever the script happened to be
/// invoked from, which on 2026-08-24 meant an 11.5 GB download landing outside
/// the package and outside its .gitignore. Anchoring to the script means
/// `dart run mtg_homunculus/tool/...` from the repo root and
/// `dart run tool/...` from the package both use the same cache.
final String packageRoot =
    File(Platform.script.toFilePath()).parent.parent.path;

String _p(List<String> parts) =>
    [packageRoot, ...parts].join(Platform.pathSeparator);

/// Gitignored. Holds the bulk file and ~11.5 GB of card images.
final String cacheDir = _p(['tool', '.cache']);

/// Scryfall `default_cards`, decompressed JSONL (~595 MB).
final String bulkPath = _p(['tool', '.cache', 'default_cards.json']);

/// One `{card_id}.jpg` per fetched card.
final String imageDir = _p(['tool', '.cache', 'images']);

/// The shipped index. This one **is** committed and bundled as an asset.
final String indexPath = _p(['assets', 'hash_index.bin']);
