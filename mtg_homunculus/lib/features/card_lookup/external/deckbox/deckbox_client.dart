import 'dart:convert';
import 'dart:io';

/// Talks to deckbox.org the way its own pages do: a form login, then ordinary
/// page requests carrying the session cookie.
///
/// **Pure Dart — no Flutter imports.** `dart:io` and `dart:convert` only, so the
/// same client can run from the PC with `dart run` if that is ever wanted. The
/// app supplies anything Flutter-shaped (storage, logging) from outside.
///
/// **All Deckbox-specific knowledge lives under `deckbox/`.** When the site
/// changes, this folder is the repair surface. Anything the client does not
/// recognise is a [DeckboxException] naming the step — never a quiet guess.
class DeckboxClient {
  DeckboxClient({
    Map<String, String>? cookies,
    this.onLog,
    this.userAgent = defaultUserAgent,
  }) : _cookies = {...?cookies} {
    _http.userAgent = userAgent;
  }

  static const host = 'deckbox.org';
  static const sessionCookie = '_tcg_session';

  /// Honest by decision — see the plan's ground rules.
  static const defaultUserAgent = 'MtgHomunculus/1.0.0';

  static const _maxRedirects = 6;
  static const _redirectCodes = {301, 302, 303, 307, 308};

  final Map<String, String> _cookies;

  /// Set-Cookie attributes by cookie name — `path`, `expires`, `secure` and so
  /// on, **without the value**. Kept for the D1 record of how long a session
  /// lives; never sent anywhere.
  final Map<String, String> cookieAttributes = {};

  /// One line per request: method, path, status. Never headers, bodies or
  /// cookie values.
  final void Function(String message)? onLog;

  final String userAgent;
  final HttpClient _http = HttpClient();

  Map<String, String> get cookies => Map.unmodifiable(_cookies);
  bool get hasSession => _cookies.containsKey(sessionCookie);

  void close() => _http.close(force: true);

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  /// Logs in with the site's own form.
  ///
  /// The password is used for the one POST and not kept — not on the client,
  /// not in the result, not in a log line.
  Future<DeckboxLoginResult> login(String login, String password) async {
    final form = await get('/accounts/login');
    final token = _formToken(form.body);
    if (token == null) {
      throw const DeckboxException(
        'login',
        'the login page has no authenticity_token field',
      );
    }

    final landed = await _request(
      'POST',
      _uri('/accounts/login'),
      form: {
        'authenticity_token': token,
        'return_to': '',
        'login': login,
        'password': password,
      },
    );

    // A rejected login does not re-render the form: seen 2026-10-14, it
    // redirects to `/` like a good one, and `/` then bounces on to
    // `/accounts/resend_activation` — the "log in with an email link" page.
    // A login page at the end means the same thing.
    if (landed.url.path.startsWith('/accounts/') || _hasLoginForm(landed.body)) {
      return DeckboxLoginResult(DeckboxSessionState.signedOut, null, landed);
    }
    final state = readSessionState(landed.body);
    return DeckboxLoginResult(state.$1, state.$2, landed);
  }

  /// Fetches the home page and reads whether the stored cookies still sign in,
  /// and as whom.
  Future<DeckboxLoginResult> checkSession() async {
    final page = await get('/');
    final state = readSessionState(page.body);
    return DeckboxLoginResult(state.$1, state.$2, page);
  }

  /// Whether a page is signed in, and the username if the page names it.
  ///
  /// Read from the `#nav` block. Signed out shows a link to `/accounts/login`
  /// (seen 2026-10-13). Signed in shows a *My Account* menu (seen 2026-10-14)
  /// holding a logout call, `postToURL('/accounts/logout')`, and the only link
  /// that carries the username: **Friends**, `/users/<name>/friends`. The menu's
  /// other `/users/` link is `/users/settings`, which is why the username is
  /// taken from Friends and nowhere else. Anything else is
  /// [DeckboxSessionState.unknown] rather than a guess.
  static (DeckboxSessionState, String?) readSessionState(String html) {
    final nav = _navBlock(html);
    if (nav == null) {
      // The login page has a bare layout with no #nav at all.
      return (
        _hasLoginForm(html)
            ? DeckboxSessionState.signedOut
            : DeckboxSessionState.unknown,
        null,
      );
    }
    if (nav.contains('/accounts/login')) {
      return (DeckboxSessionState.signedOut, null);
    }

    final username = RegExp(r'''href=["']/users/([^/"']+)/friends["']''')
        .firstMatch(nav)
        ?.group(1);

    if (nav.contains('/accounts/logout')) {
      return (DeckboxSessionState.signedIn, username);
    }
    return (DeckboxSessionState.unknown, null);
  }

  // ---------------------------------------------------------------------------
  // Lists
  // ---------------------------------------------------------------------------

  /// The signed-in user's collection lists, read from the home page.
  Future<(List<DeckboxListRef>, DeckboxPage)> findLists() async {
    final page = await get('/');
    return (readLists(page.body), page);
  }

  /// Reads the left menu's **MTG COLLECTION** section, `#section_mtg` (seen
  /// 2026-10-14): one `/sets/<id>` link each for Inventory, Tradelist and
  /// Wishlist. The section continues into *MTG DATABASE* and *MTG DECKS*, so
  /// reading stops at the database heading — decks are a later feature.
  ///
  /// The kind comes from the link text. Inventory and Wishlist also carry
  /// `t_inv` / `t_wish` classes, but Tradelist has no class of its own, so the
  /// text is the one signal all three share.
  static List<DeckboxListRef> readLists(String html) {
    final start = html.indexOf('id="section_mtg"');
    if (start < 0) {
      throw const DeckboxException('lists', 'no #section_mtg menu on the page');
    }
    final stop = html.indexOf('MTG DATABASE', start);
    final section = html.substring(start, stop < 0 ? html.length : stop);

    final lists = [
      for (final m in RegExp(
        r'''<a\s+href=["']/sets/(\d+)["'][^>]*>(.*?)</a>''',
        dotAll: true,
      ).allMatches(section))
        DeckboxListRef(
          setId: int.parse(m.group(1)!),
          name: m.group(2)!.replaceAll(RegExp(r'<[^>]*>'), '').trim(),
        ),
    ];
    if (lists.isEmpty) {
      throw const DeckboxException('lists', '#section_mtg has no /sets/ links');
    }
    return lists;
  }

  // ---------------------------------------------------------------------------
  // Exports
  // ---------------------------------------------------------------------------

  /// A list as CSV — the site's own *Export* link.
  ///
  /// [columns] is the extra-column selection the export dialog offers; empty
  /// gives the default set. No filter: the whole list.
  ///
  /// [sort] is **always explicit** — `n` name, `e` edition and number. Left
  /// empty, the export follows the account's saved sort preference, and the
  /// export's order is what locates a row on a list page; both must use the
  /// same sort, so neither may follow a preference the user can change.
  Future<DeckboxPage> exportCsv(
    int setId, {
    String columns = '',
    String sort = 'n',
  }) =>
      get(
        '/sets/export/$setId?format=csv&f=&s=$sort&o='
        '&columns=${Uri.encodeQueryComponent(columns)}',
      );

  /// Uploads a CSV into a list — the list page's *Import CSV* → *Check file
  /// and Import*.
  ///
  /// The site posts it as `multipart/form-data` to
  /// `/detailed_cards_sets/import_csv` with the file, `set_id` and the
  /// anti-forgery token (seen 2026-10-14), via a plain `fetch` that treats any
  /// redirect as an error. The reply is JavaScript for the page to run; the
  /// caller reads what it can out of it.
  ///
  /// **One bad row rejects the whole file** (the owner's experience importing
  /// their collection). So a caller sends only what it has checked.
  Future<DeckboxPage> importCsv(int setId, String csv, {String filename = 'import.csv'}) {
    final token = _csrf;
    if (token == null) {
      throw const DeckboxException(
        'import',
        'no anti-forgery token yet — load the list page before importing',
      );
    }
    final boundary = '----MtgHomunculus${DateTime.now().microsecondsSinceEpoch}';
    String field(String name, String value) =>
        '--$boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n$value\r\n';
    final body = <int>[
      ...utf8.encode(field('set_id', '$setId')),
      ...utf8.encode(field('authenticity_token', token)),
      ...utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="import_csv_file"; '
        'filename="$filename"\r\nContent-Type: text/csv\r\n\r\n',
      ),
      ...utf8.encode(csv),
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];
    return _request(
      'POST',
      _uri('/detailed_cards_sets/import_csv'),
      body: body,
      contentType: ContentType('multipart', 'form-data', parameters: {'boundary': boundary}),
      referer: _uri('/sets/$setId'),
      redirectIsError: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Removing and changing counts
  // ---------------------------------------------------------------------------

  /// Removes whole rows from a list, by row id — the site's *select → Remove*
  /// on a detailed set (Inventory, Tradelist, Wishlist).
  ///
  /// **Refuses an empty selection.** To Deckbox, this request with no `cards`
  /// means *every row in the set* — the form the spike's test-account reset
  /// uses on purpose. Here, an empty list is always a bug.
  Future<DeckboxPage> removeRows(DeckboxListRef list, List<String> rowIds) {
    if (rowIds.isEmpty) {
      throw const DeckboxException(
        'remove',
        'no row ids — refusing: without them Deckbox removes every row',
      );
    }
    if (list.kind == DeckboxListKind.other) {
      throw DeckboxException('remove', '${list.name} is not a list the app manages');
    }
    return post(
      '/detailed_cards_sets/remove',
      {
        'set_id': '${list.setId}',
        // The site sends Tcg.set.data.type.underscore() — "Inventory" → "inventory".
        'render_context_name': list.kind.name,
        'cards': rowIds.join(','),
      },
      referer: '/sets/${list.setId}',
    );
  }

  /// Sets one row's count in one list — a list page's inline count cell.
  ///
  /// An Inventory row carries two counts, and each cell posts here with **its
  /// own set id**: the Inventory's for the count owned, the Tradelist's for the
  /// count for trade. [viewingSetId] is the list page the change is made from.
  Future<DeckboxPage> updateCount({
    required int setId,
    required String rowId,
    required int count,
    required int viewingSetId,
  }) =>
      post(
        '/detailed_cards_sets/update_count',
        {
          'set_id': '$setId',
          'card_set_id': rowId,
          'count': '$count',
          'viewing_set': '$viewingSetId',
          'http_referer': 'https://$host/sets/$viewingSetId',
        },
        referer: '/sets/$viewingSetId',
      );

  /// A row's edit panel — the site's *Edit this row*. A POST because that is
  /// how the site loads it; it changes nothing. Read with `DeckboxRowPanel`.
  Future<DeckboxPage> rowPanel(String rowId, {required int viewingSetId}) => post(
        '/detailed_cards_sets/panel_edit_single',
        {'detailed_card_set_id': rowId, 'render_context_action': 'edit_this_row'},
        referer: '/sets/$viewingSetId',
      );

  /// Saves a row — the edit panel's **Save**. [data] is the whole row
  /// (`DeckboxRowPanel.saveData`); [setId] is the panel's own, the
  /// Inventory's even from its Tradelist. The reply on success is a script
  /// that redraws the list (`Element.update('show_detailed_contents', …)`).
  Future<DeckboxPage> saveRow({
    required int setId,
    required String data,
    required int viewingSetId,
  }) =>
      post(
        '/detailed_cards_sets/update_single',
        {
          'set_id': '$setId',
          'data': data,
          'render_context_action': 'edit_this_row',
          'render_context_page': '',
        },
        referer: '/sets/$viewingSetId',
      );

  /// Finds the row ids of export rows — **the push-time lookup**.
  ///
  /// [export] is a fresh export of [list] in [sort]; [indices] are the rows
  /// wanted. Each row's page comes from its position (`index ÷ pageSize + 1`,
  /// the size read from the page itself), and the page row at that position
  /// must match the export row on name, printing, condition, language, foil
  /// and counts before its id is trusted. If the list moved between the export
  /// and the page, a **unique** full match on that page or a neighbour is
  /// accepted; two equal matches, or none, fail loudly. Each page is fetched
  /// once however many rows sit on it.
  ///
  /// [onProgress] hears each row found — `(found, of)` — for a push's
  /// progress: a thousand rows is dozens of pages.
  Future<Map<int, String>> locateRows(
    DeckboxListRef list,
    List<Map<String, String>> export,
    Iterable<int> indices, {
    String sort = 'n',
    void Function(int done, int total)? onProgress,
  }) =>
      _locate(list, (i) => export[i], indices, sort: sort, onProgress: onProgress);

  /// One row's id, from **the mirror** rather than a fresh export — a row
  /// edit's lookup (mirror_editing.md). [want] is the row as the export
  /// showed it at [position]; the same page check applies, so a row changed
  /// on Deckbox since the pull is not found.
  Future<String> locateRow(DeckboxListRef list, int position, Map<String, String> want) async =>
      (await _locate(list, (_) => want, [position]))[position]!;

  Future<Map<int, String>> _locate(
    DeckboxListRef list,
    Map<String, String> Function(int index) rowAt,
    Iterable<int> indices, {
    String sort = 'n',
    void Function(int done, int total)? onProgress,
  }) async {
    final total = indices.length;
    final pages = <int, DeckboxListPage>{};
    Future<DeckboxListPage> pageAt(int p) async =>
        pages[p] ??= readListPage((await listPage(list.setId, page: p, sort: sort)).body);

    var size = 30;
    final found = <int, String>{};
    for (final i in indices) {
      final want = rowAt(i);
      var p = i ~/ size + 1;
      var page = await pageAt(p);
      final reported = page.pageSize;
      if (reported != null && reported != size) {
        size = reported;
        p = i ~/ size + 1;
        page = await pageAt(p);
      }

      final offset = i - (p - 1) * size;
      String? id;
      if (offset < page.rows.length && rowMatches(page.rows[offset], want, list.kind)) {
        id = page.rows[offset].rowId;
      }
      for (final q in [p, p - 1, p + 1]) {
        if (id != null || q < 1) continue;
        final matches =
            (await pageAt(q)).rows.where((r) => rowMatches(r, want, list.kind)).toList();
        if (matches.length > 1) {
          throw DeckboxException(
            'locate',
            'two rows on page $q match ${want['Name']} — refusing to pick between them',
          );
        }
        if (matches.length == 1) id = matches.single.rowId;
      }
      if (id == null) {
        throw DeckboxException(
          'locate',
          '${want['Name']} not found on page $p or its neighbours',
        );
      }
      found[i] = id;
      onProgress?.call(found.length, total);
    }
    return found;
  }

  /// Whether a list-page row is the export row [want]: name, printing (empty
  /// for "any printing"), the counts the export carries, and — where the export
  /// sets them — condition, language and foil, which the page shows as
  /// `data-title`s.
  static bool rowMatches(
    DeckboxPageRow row,
    Map<String, String> want,
    DeckboxListKind kind,
  ) {
    final countKey = kind == DeckboxListKind.wishlist ? 'Wishlist' : 'Inventory';
    final condition = want['Condition'] ?? '';
    final language = want['Language'] ?? '';
    return row.name == want['Name'] &&
        (row.printingId ?? '') == (want['Printing Id'] ?? '') &&
        '${row.counts[countKey]}' == want['Count'] &&
        (!want.containsKey('Tradelist Count') ||
            '${row.counts['Tradelist']}' == want['Tradelist Count']) &&
        (condition.isEmpty || row.titles.contains(condition)) &&
        (language.isEmpty || row.titles.contains(language)) &&
        (want['Foil'] == 'foil') == row.titles.contains('Foil');
  }

  /// One page of a list, in the same explicit [sort] as [exportCsv].
  Future<DeckboxPage> listPage(int setId, {int page = 1, String sort = 'n'}) =>
      get('/sets/$setId?s=$sort&p=$page');

  /// The rows on a list page, with their ids, and where the page sits.
  ///
  /// Seen 2026-10-14. Each row is a `<tr id="<rowId>">`; its card link carries
  /// the printing (`?printing=<Printing Id>`, absent on a wishlist row that
  /// means "any printing"); each editable count is a cell
  /// `card_count_<Inventory|Tradelist|Wishlist>_<rowId>`; condition, language
  /// and foil are `data-title`s on the row's icons. The page size is read from
  /// the *Cards Per Page* dropdown's initial value — a saved preference, 30 on
  /// a free account — never assumed.
  static DeckboxListPage readListPage(String html) {
    final starts = RegExp(r'''<tr[^>]*\bid=["'](\d+)["']''').allMatches(html).toList();
    final rows = <DeckboxPageRow>[];

    for (var i = 0; i < starts.length; i++) {
      final rowId = starts[i].group(1)!;
      final end = i + 1 < starts.length ? starts[i + 1].start : html.indexOf('</table>', starts[i].start);
      final block = html.substring(starts[i].start, end < 0 ? html.length : end);

      final link = RegExp(r'''<a class=['"]simple['"] href=['"]([^'"]*/mtg/[^'"]*)['"][^>]*>([^<]+)</a>''')
          .firstMatch(block);
      final counts = {
        for (final m in RegExp('card_count_(\\w+?)_$rowId["\'][^>]*>\\s*(\\d+)\\s*<')
            .allMatches(block))
          m.group(1)!: int.parse(m.group(2)!),
      };
      final titles = [
        for (final m in RegExp(r'''data-title=['"]([^'"]*)['"]''').allMatches(block))
          if (m.group(1)!.isNotEmpty && m.group(1) != 'Click to edit') _unescape(m.group(1)!),
      ];

      // A wishlist row meaning "any printing" still links to *some* printing
      // — only its "[Unspecified Edition]" title says the link is not the row's.
      final anyPrinting = titles.contains('[Unspecified Edition]');

      rows.add(DeckboxPageRow(
        rowId: rowId,
        name: link == null ? null : _unescape(link.group(2)!.trim()),
        printingId: link == null || anyPrinting
            ? null
            : RegExp(r'printing=(\d+)').firstMatch(link.group(1)!)?.group(1),
        counts: counts,
        titles: titles,
      ));
    }

    final pageOf = RegExp(r'Page (\d+) of (\d+)').firstMatch(html);
    final size = RegExp(r'''buttonId:\s*['"]per_page_button['"],\s*initial:\s*\[(\d+)\]''')
        .firstMatch(html);
    return DeckboxListPage(
      rows: rows,
      page: int.tryParse(pageOf?.group(1) ?? ''),
      pageCount: int.tryParse(pageOf?.group(2) ?? ''),
      pageSize: int.tryParse(size?.group(1) ?? ''),
    );
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  /// The export dialog's HTML, which is where the extra columns are offered.
  /// A POST because that is how the site loads it; it changes nothing.
  Future<DeckboxPage> exportDialog(int setId) => post(
        '/sets/export_dialog',
        {'id': '$setId', 'f': '', 's': '', 'o': ''},
        referer: '/sets/$setId',
      );

  // ---------------------------------------------------------------------------
  // Requests
  // ---------------------------------------------------------------------------

  /// GET a path on deckbox.org, following redirects within the site.
  Future<DeckboxPage> get(String pathAndQuery) =>
      _request('GET', _uri(pathAndQuery));

  /// POST the way the site's own scripts do: form-encoded, with the page's
  /// anti-forgery token as an `authenticity_token` **parameter** — Deckbox has
  /// no `<meta>` token and its scripts send no token header — and marked as an
  /// XHR, which is what Prototype's `Ajax.Request` sends.
  ///
  /// The token is the one from the latest page this client loaded, so a page
  /// must have been loaded first.
  Future<DeckboxPage> post(
    String path,
    Map<String, String> params, {
    String? referer,
  }) {
    final token = _csrf;
    if (token == null) {
      throw DeckboxException(
        'post $path',
        'no anti-forgery token yet — load a page before posting',
      );
    }
    return _request(
      'POST',
      _uri(path),
      form: {...params, 'authenticity_token': token},
      referer: referer == null ? null : _uri(referer),
      xhr: true,
    );
  }

  /// The anti-forgery token from the latest page that carried one. Every
  /// Deckbox page sets it with an inline `Tcg.setCsrf("…")`.
  String? _csrf;

  static final _csrfCall = RegExp(r'''setCsrf\(\s*["']([^"']+)["']''');

  Uri _uri(String pathAndQuery) => Uri.parse('https://$host$pathAndQuery');

  /// Redirects are followed **by hand**, because `dart:io` does not follow a
  /// POST's redirect, and because every hop can set a cookie that has to be
  /// caught — the login's session cookie arrives on the 302, not the page after.
  Future<DeckboxPage> _request(
    String method,
    Uri uri, {
    Map<String, String>? form,
    List<int>? body,
    ContentType? contentType,
    Uri? referer,
    bool xhr = false,
    bool redirectIsError = false,
  }) async {
    final hops = <DeckboxHop>[];
    var currentMethod = method;
    var currentUri = uri;
    var currentForm = form;
    var currentBody = body;

    for (var i = 0; i <= _maxRedirects; i++) {
      // Cookies only ever go to deckbox.org. A redirect off the site is a
      // change worth knowing about, so it stops rather than follows.
      if (currentUri.host != host || currentUri.scheme != 'https') {
        throw DeckboxException(
          'request',
          'redirected off the site, to ${currentUri.scheme}://${currentUri.host}',
        );
      }

      final req = await _http.openUrl(currentMethod, currentUri);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.acceptHeader, 'text/html,*/*;q=0.8');
      if (_cookies.isNotEmpty) {
        req.headers.set(
          HttpHeaders.cookieHeader,
          _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
        );
      }
      if (currentForm != null || currentBody != null) {
        // What a browser sends with a form post; Rails may check the origin
        // alongside the token.
        req.headers.set('Origin', 'https://$host');
        req.headers.set(
          HttpHeaders.refererHeader,
          (referer ?? currentUri).toString(),
        );
        if (xhr) req.headers.set('X-Requested-With', 'XMLHttpRequest');
        if (currentBody != null) {
          req.headers.contentType = contentType;
          req.add(currentBody);
        } else {
          req.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
            charset: 'utf-8',
          );
          req.write(Uri(queryParameters: currentForm).query);
        }
      }

      final resp = await req.close();
      final setCookies = _absorbCookies(resp.headers[HttpHeaders.setCookieHeader]);
      final body = await resp.transform(const Utf8Decoder(allowMalformed: true)).join();
      final location = resp.headers.value(HttpHeaders.locationHeader);
      final token = _csrfCall.firstMatch(body)?.group(1);
      if (token != null) _csrf = token;

      hops.add(DeckboxHop(
        method: currentMethod,
        path: currentUri.path,
        status: resp.statusCode,
        location: location,
        setCookies: setCookies,
      ));
      onLog?.call(
        'Deckbox $currentMethod ${currentUri.path} → ${resp.statusCode}'
        '${location != null ? ' → ${Uri.parse(location).path}' : ''}',
      );

      // Not `resp.isRedirect`: dart:io answers false for a POST's 302 — it
      // only counts 303 after a POST — which is exactly the login's redirect.
      if (_redirectCodes.contains(resp.statusCode) && location != null) {
        // The site's own upload treats a redirect as failure (`redirect:
        // "error"`); a redirect there most likely means signed out.
        if (redirectIsError) {
          throw DeckboxException(
            '$method ${uri.path}',
            'redirected to ${Uri.parse(location).path} — signed out?',
          );
        }
        currentUri = currentUri.resolve(location);
        // After a redirect a form post becomes a plain GET, as in a browser.
        if (resp.statusCode != 307 && resp.statusCode != 308) {
          currentMethod = 'GET';
          currentForm = null;
          currentBody = null;
        }
        continue;
      }

      return DeckboxPage(
        url: currentUri,
        status: resp.statusCode,
        body: body,
        hops: hops,
        contentType: resp.headers.value(HttpHeaders.contentTypeHeader),
        contentDisposition: resp.headers.value('content-disposition'),
      );
    }
    throw DeckboxException('request', 'more than $_maxRedirects redirects');
  }

  /// Stores each Set-Cookie and returns them for the record, **values masked**.
  List<String> _absorbCookies(List<String>? headers) {
    if (headers == null) return const [];
    final recorded = <String>[];
    for (final header in headers) {
      final semi = header.indexOf(';');
      final pair = semi < 0 ? header : header.substring(0, semi);
      final attrs = semi < 0 ? '' : header.substring(semi + 1).trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final name = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();

      final cleared = value.isEmpty ||
          RegExp(r'max-age=0\b', caseSensitive: false).hasMatch(attrs);
      if (cleared) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
      cookieAttributes[name] = attrs;
      recorded.add('$name=[${cleared ? 'cleared' : 'value'}]; $attrs');
    }
    return recorded;
  }

  // ---------------------------------------------------------------------------
  // Page reading
  // ---------------------------------------------------------------------------

  /// The login form's hidden token. Deckbox writes it single-quoted with a
  /// space before the `=` — `name='authenticity_token' value ='…'` — so the
  /// pattern allows either quote and stray spaces.
  static String? _formToken(String html) => RegExp(
        r'''name\s*=\s*['"]authenticity_token['"]\s+value\s*=\s*['"]([^'"]+)['"]''',
      ).firstMatch(html)?.group(1);

  static bool _hasLoginForm(String html) =>
      RegExp(r'''action\s*=\s*["']/accounts/login["']''').hasMatch(html) &&
      RegExp(r'''name\s*=\s*["']password["']''').hasMatch(html);

  static String? _navBlock(String html) {
    final start = html.indexOf('<div id="nav">');
    if (start < 0) return null;
    final end = html.indexOf('</ul>', start);
    return html.substring(start, end < 0 ? html.length : end);
  }

  /// Masks what must never be written down: the anti-forgery token, wherever
  /// the page carries it, and the value of every cookie this client holds.
  ///
  /// For saving pages to disk during the spikes. The token appears twice on a
  /// Deckbox page — the form field and a `Tcg.setCsrf("…")` call that the
  /// site's scripts read it back from.
  String redact(String text) {
    var out = text
        .replaceAllMapped(
          RegExp(r'''(authenticity_token['"]\s+value\s*=\s*['"])[^'"]+'''),
          (m) => '${m[1]}[redacted]',
        )
        .replaceAllMapped(
          RegExp(r'''(setCsrf\(\s*["'])[^"']+'''),
          (m) => '${m[1]}[redacted]',
        );
    for (final value in _cookies.values) {
      if (value.length >= 8) out = out.replaceAll(value, '[redacted]');
    }
    return out;
  }
}

// -----------------------------------------------------------------------------

enum DeckboxSessionState { signedIn, signedOut, unknown }

enum DeckboxListKind { inventory, tradelist, wishlist, other }

/// One of the user's lists on Deckbox — a "set", in the site's own terms.
class DeckboxListRef {
  const DeckboxListRef({required this.setId, required this.name});

  final int setId;
  final String name;

  DeckboxListKind get kind => switch (name.toLowerCase()) {
        'inventory' => DeckboxListKind.inventory,
        'tradelist' => DeckboxListKind.tradelist,
        'wishlist' => DeckboxListKind.wishlist,
        _ => DeckboxListKind.other,
      };

  @override
  String toString() => '$name (${kind.name}) — /sets/$setId';
}

class DeckboxListPage {
  const DeckboxListPage({
    required this.rows,
    required this.page,
    required this.pageCount,
    required this.pageSize,
  });

  final List<DeckboxPageRow> rows;

  /// Null when the page does not say — itself worth a loud failure at push time.
  final int? page;
  final int? pageCount;
  final int? pageSize;
}

/// One row of a list page — the only place a row id is to be found.
class DeckboxPageRow {
  const DeckboxPageRow({
    required this.rowId,
    required this.name,
    required this.printingId,
    required this.counts,
    required this.titles,
  });

  final String rowId;
  final String? name;

  /// Null on a wishlist row that names no printing.
  final String? printingId;

  /// By list type — `Inventory`, `Tradelist`, `Wishlist` — as the count cells
  /// name them. An Inventory or Tradelist row carries both of the first two.
  final Map<String, int> counts;

  /// The row's `data-title`s: edition and card number, condition, language,
  /// finish. Raw, for matching against the export's fields.
  final List<String> titles;
}

class DeckboxLoginResult {
  const DeckboxLoginResult(this.state, this.username, this.page);

  final DeckboxSessionState state;

  /// Null when the page does not name the user — which, until D1 confirms the
  /// signed-in markup, may happen even when signed in.
  final String? username;

  final DeckboxPage page;
}

class DeckboxPage {
  const DeckboxPage({
    required this.url,
    required this.status,
    required this.body,
    required this.hops,
    this.contentType,
    this.contentDisposition,
  });

  final Uri url;
  final int status;
  final String body;
  final List<DeckboxHop> hops;

  /// Kept because an export is told apart from an error page by them — a CSV
  /// arrives as an attachment, a signed-out bounce as HTML.
  final String? contentType;
  final String? contentDisposition;
}

/// One request in a redirect chain, as recorded — cookie values masked.
class DeckboxHop {
  const DeckboxHop({
    required this.method,
    required this.path,
    required this.status,
    required this.location,
    required this.setCookies,
  });

  final String method;
  final String path;
  final int status;
  final String? location;
  final List<String> setCookies;

  @override
  String toString() => [
        '$method $path → $status${location != null ? ' → $location' : ''}',
        for (final c in setCookies) '  Set-Cookie: $c',
      ].join('\n');
}

class DeckboxException implements Exception {
  const DeckboxException(this.step, this.message);

  /// Which step failed — `login`, `request`, … — so a stale scraper says where.
  final String step;
  final String message;

  @override
  String toString() => 'Deckbox $step: $message';
}
