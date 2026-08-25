// Build script — never ships. Dart compiles lib/ plus declared assets; nothing
// in tool/ reaches an APK.
//
// Part 1 of 2. Downloads Scryfall's bulk card data and every usable card image
// into a local cache. Part 2 (`build_hash_index.dart`) turns that cache into the
// shipped hash index.
//
//   dart run tool/fetch_card_images.dart
//   dart run tool/fetch_card_images.dart --refresh-bulk
//   dart run tool/fetch_card_images.dart --limit 200      # smoke test
//
// Resumable: anything already on disk is skipped, so an interrupted run picks up
// where it stopped. Downloads land on a `.part` file and are renamed only once
// complete, so a kill mid-write can never leave a truncated file that a later
// run mistakes for a finished one.

import 'dart:convert';
import 'dart:io';

import '_paths.dart';

/// Scryfall asks for a descriptive User-Agent so they can identify traffic.
///
/// It also **requires** an explicit Accept header: a request without one is
/// answered with HTTP 400, not a default representation.
const _userAgent = 'MtgHomunculus/1.0 (hash-index build script)';
const _acceptJson  = 'application/json';
const _acceptImage = 'image/*';

void _headers(HttpClientRequest req, String accept) {
  req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
  req.headers.set(HttpHeaders.acceptHeader, accept);
}

/// `*.scryfall.io` has no documented rate limit, so this is politeness rather
/// than a requirement — ~97k requests is a lot of a free service's bandwidth.
/// Raise it if the run is slower than you want to sit through.
const _concurrency = 8;

/// Image statuses worth fetching.
///
/// `missing` has nothing to fetch. `placeholder` is the dangerous one: an image
/// exists, but it is a stand-in rather than the card, so hashing them would give
/// every placeholder card a near-identical hash — they would match each other
/// *and* incoming scans. Worse than having no hash at all.
///
/// `lowres` is kept: it is real art, and everything is downsampled to an 8 x 11
/// grid regardless.
const _usableStatuses = {'lowres', 'highres_scan'};

void main(List<String> args) async {
  final refreshBulk = args.contains('--refresh-bulk');
  final limit = _intArg(args, '--limit');

  await Directory(imageDir).create(recursive: true);

  final bulk = await _ensureBulkFile(refresh: refreshBulk);
  if (bulk == null) exit(1);

  final targets = await _collectTargets(bulk, limit: limit);
  if (targets.isEmpty) {
    stdout.writeln('Nothing to fetch.');
    return;
  }

  await _download(targets);
}

// ---------------------------------------------------------------------------
// Step 0 — bulk data
// ---------------------------------------------------------------------------

/// Fetch `default_cards` if it is not already cached.
///
/// `default_cards` rather than `unique_artwork`: we hash the **whole card**, so
/// two printings sharing an illustration still hash differently — different
/// frames, set symbols and borders. `unique_artwork` would collapse exactly the
/// distinctions we are trying to make.
Future<File?> _ensureBulkFile({required bool refresh}) async {
  final file = File(bulkPath);

  if (!refresh && await file.exists()) {
    final mb = (await file.length()) / (1024 * 1024);
    stdout.writeln('bulk    cached  ${mb.toStringAsFixed(1)} MB  '
        '($bulkPath)  — pass --refresh-bulk to re-download');
    return file;
  }

  stdout.writeln('bulk    looking up download_uri...');
  final client = HttpClient();
  try {
    final meta = await _getJson(client, Uri.https('api.scryfall.com', '/bulk-data'));
    if (meta == null) return null;

    final entry = (meta['data'] as List?)
        ?.cast<Map<String, dynamic>>()
        .where((e) => e['type'] == 'default_cards')
        .firstOrNull;
    if (entry == null) {
      stderr.writeln('bulk    ERROR: no default_cards entry in /bulk-data');
      return null;
    }

    // Scryfall serves JSONL now: the field is `jsonl_download_uri`, and the
    // older `download_uri` (a wrapped JSON array) is no longer listed. Fall back
    // to it anyway so an older API shape does not break the script.
    final uriStr = (entry['jsonl_download_uri'] ?? entry['download_uri']) as String?;
    if (uriStr == null) {
      stderr.writeln('bulk    ERROR: no download uri on the default_cards entry');
      return null;
    }
    final uri   = Uri.parse(uriStr);
    final total = ((entry['compressed_size'] ?? entry['size']) as num?)?.toInt() ?? 0;
    stdout.writeln('bulk    downloading ${entry['updated_at']}  '
        '(${(total / (1024 * 1024)).toStringAsFixed(1)} MB compressed)');

    final part = File('$bulkPath.part');
    final req  = await client.getUrl(uri);
    _headers(req, _acceptJson);
    final res = await req.close();
    if (res.statusCode != 200) {
      stderr.writeln('bulk    ERROR: HTTP ${res.statusCode}');
      return null;
    }

    final sink = part.openWrite();
    var written = 0;
    var lastTick = DateTime.now();
    await res.forEach((chunk) {
      sink.add(chunk);
      written += chunk.length;
      if (DateTime.now().difference(lastTick).inMilliseconds > 250) {
        lastTick = DateTime.now();
        stdout.write('\rbulk    ${(written / (1024 * 1024)).toStringAsFixed(1)} MB written   ');
      }
    });
    await sink.close();
    stdout.writeln('\rbulk    ${(written / (1024 * 1024)).toStringAsFixed(1)} MB downloaded'
        '                    ');

    // Scryfall serves the bulk file as a gzip *file*, not with
    // `Content-Encoding: gzip`, so HttpClient.autoUncompress never fires and
    // what landed on disk is still compressed. Sniff for it rather than trusting
    // either behaviour — this works whichever way it is served.
    await _decompressIfNeeded(part, File(bulkPath));
    stdout.writeln('bulk    done  '
        '${((await file.length()) / (1024 * 1024)).toStringAsFixed(1)} MB on disk');
    return file;
  } catch (e) {
    stderr.writeln('bulk    ERROR: $e');
    return null;
  } finally {
    client.close();
  }
}

/// Move [src] to [dst], decompressing on the way if it is gzip.
Future<void> _decompressIfNeeded(File src, File dst) async {
  final head = await src.openRead(0, 2).expand((c) => c).toList();
  final isGzip = head.length >= 2 && head[0] == 0x1f && head[1] == 0x8b;

  if (!isGzip) {
    await src.rename(dst.path);
    return;
  }

  stdout.write('bulk    decompressing...');
  final sink = dst.openWrite();
  await src.openRead().transform(gzip.decoder).forEach(sink.add);
  await sink.close();
  await src.delete();
  stdout.writeln('');
}

Future<Map<String, dynamic>?> _getJson(HttpClient client, Uri uri) async {
  final req = await client.getUrl(uri);
  _headers(req, _acceptJson);
  final res = await req.close();
  if (res.statusCode != 200) {
    stderr.writeln('        ERROR: HTTP ${res.statusCode} for $uri');
    return null;
  }
  return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
}

// ---------------------------------------------------------------------------
// Step 1 — decide what to fetch
// ---------------------------------------------------------------------------

class _Target {
  final String id;
  final String url;
  const _Target(this.id, this.url);

  String get path => '$imageDir/$id.jpg';
}

/// Stream the bulk file and pick out cards worth hashing.
///
/// The bulk file is JSONL — one card object per line — so it is read line by
/// line rather than held in memory; uncompressed it is ~400 MB. Anything that is
/// not a card object (a stray bracket from the older array format) fails the
/// leading-brace check or the parse, and is skipped.
Future<List<_Target>> _collectTargets(File bulk, {int? limit}) async {
  final targets = <_Target>[];
  var seen = 0, skippedNoUrl = 0;
  final statusCounts = <String, int>{};

  final lines = bulk
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final raw in lines) {
    var line = raw.trim();
    if (line.endsWith(',')) line = line.substring(0, line.length - 1);
    if (line.length < 2 || line[0] != '{') continue;

    Map<String, dynamic> card;
    try {
      card = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    seen++;

    final status = card['image_status'] as String? ?? 'missing';
    statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    if (!_usableStatuses.contains(status)) continue;

    final url = _normalUrl(card);
    if (url == null) {
      skippedNoUrl++;
      continue;
    }

    targets.add(_Target(card['id'] as String, url));
    if (limit != null && targets.length >= limit) break;
  }

  stdout.writeln('cards   $seen parsed');
  final order = ['highres_scan', 'lowres', 'placeholder', 'missing'];
  for (final s in order) {
    if (statusCounts[s] case final n?) {
      final mark = _usableStatuses.contains(s) ? 'keep' : 'SKIP';
      stdout.writeln('        ${s.padRight(13)} ${n.toString().padLeft(7)}  $mark');
    }
  }
  if (skippedNoUrl > 0) {
    stdout.writeln('        no image_uris ${skippedNoUrl.toString().padLeft(5)}  SKIP');
  }
  stdout.writeln('        ${targets.length} to fetch'
      '${limit != null ? '  (--limit $limit)' : ''}');
  return targets;
}

/// The `normal` image is 488 x 680 for **every** card and layout, which is
/// exactly what DHash expects and what CardWarp produces on the app side.
///
/// Double-faced cards carry their images on `card_faces` instead; the front face
/// is the one a scan sees.
String? _normalUrl(Map<String, dynamic> card) {
  final direct = (card['image_uris'] as Map?)?['normal'] as String?;
  if (direct != null) return direct;
  final faces = card['card_faces'] as List?;
  if (faces == null || faces.isEmpty) return null;
  return ((faces.first as Map)['image_uris'] as Map?)?['normal'] as String?;
}

// ---------------------------------------------------------------------------
// Step 2 — fetch
// ---------------------------------------------------------------------------

Future<void> _download(List<_Target> targets) async {
  var cached = 0, fetched = 0, failed = 0, bytes = 0;
  final failures = <String>[];
  final started = DateTime.now();

  // Resumability: what is already on disk is done.
  final pending = <_Target>[];
  for (final t in targets) {
    if (await File(t.path).exists()) {
      cached++;
    } else {
      pending.add(t);
    }
  }

  stdout.writeln('images  $cached already cached, ${pending.length} to download'
      '  (concurrency $_concurrency)');
  if (pending.isEmpty) {
    _summary(cached, fetched, failed, bytes, failures, started);
    return;
  }

  var next = 0;
  var lastTick = DateTime.now();

  void tick({bool force = false}) {
    if (!force && DateTime.now().difference(lastTick).inMilliseconds < 250) return;
    lastTick = DateTime.now();
    final done = fetched + failed;
    final left = pending.length - done;
    final secs = DateTime.now().difference(started).inMilliseconds / 1000;
    final rate = secs > 0 ? done / secs : 0;
    final eta  = rate > 0 ? (left / rate).round() : 0;
    stdout.write('\r        fetched ${fetched.toString().padLeft(6)}  '
        'cached ${cached.toString().padLeft(6)}  '
        'failed ${failed.toString().padLeft(4)}  '
        'left ${left.toString().padLeft(6)}  '
        '${rate.toStringAsFixed(0).padLeft(3)}/s  '
        'eta ${_dur(eta)}   ');
  }

  Future<void> worker(HttpClient client) async {
    while (true) {
      final i = next++;
      if (i >= pending.length) return;
      final t = pending[i];
      try {
        final n = await _fetchOne(client, t);
        bytes += n;
        fetched++;
      } catch (e) {
        failed++;
        if (failures.length < 20) failures.add('${t.id}: $e');
      }
      tick();
    }
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  client.maxConnectionsPerHost = _concurrency;
  await Future.wait([for (var i = 0; i < _concurrency; i++) worker(client)]);
  client.close();

  tick(force: true);
  stdout.writeln();
  _summary(cached, fetched, failed, bytes, failures, started);
}

Future<int> _fetchOne(HttpClient client, _Target t) async {
  final req = await client.getUrl(Uri.parse(t.url));
  _headers(req, _acceptImage);
  final res = await req.close();
  if (res.statusCode != 200) {
    await res.drain<void>();
    throw 'HTTP ${res.statusCode}';
  }

  // Write to .part first: a kill mid-write must not leave a truncated file that
  // the next run counts as cached.
  final part = File('${t.path}.part');
  final sink = part.openWrite();
  var n = 0;
  await res.forEach((chunk) {
    sink.add(chunk);
    n += chunk.length;
  });
  await sink.close();
  await part.rename(t.path);
  return n;
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

void _summary(int cached, int fetched, int failed, int bytes,
    List<String> failures, DateTime started) {
  final mb   = bytes / (1024 * 1024);
  final secs = DateTime.now().difference(started).inSeconds;
  stdout.writeln('');
  stdout.writeln('done    cached  ${cached.toString().padLeft(7)}');
  stdout.writeln('        fetched ${fetched.toString().padLeft(7)}  '
      '${mb.toStringAsFixed(1)} MB in ${_dur(secs)}');
  stdout.writeln('        failed  ${failed.toString().padLeft(7)}');
  stdout.writeln('        on disk ${(cached + fetched).toString().padLeft(7)}  ($imageDir)');

  if (failures.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('first ${failures.length} failure(s):');
    for (final f in failures) {
      stdout.writeln('  $f');
    }
    stdout.writeln('');
    stdout.writeln('Re-run to retry — anything already on disk is skipped.');
  }
}

String _dur(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  if (m < 60) return '${m}m${(seconds % 60).toString().padLeft(2, '0')}s';
  return '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}m';
}

int? _intArg(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return int.tryParse(args[i + 1]);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
