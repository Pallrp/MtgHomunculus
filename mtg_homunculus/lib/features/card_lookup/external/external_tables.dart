import 'package:drift/drift.dart';

/// Tables for lists that live on another service — Deckbox, for now.
///
/// **A separate world from `Lists` and `Entries`.** App lists are the user's
/// own; these are a *mirror* of somewhere else, replaced wholesale on every
/// pull. Keeping them apart keeps app lists simple and means a pull can never
/// touch a list the user made. `provider` leaves room for another service
/// without designing for one now.
///
/// Staged changes — what the user wants to send back — live in their own
/// table ([StagedChanges], M3), untouched by pulls.

/// One signed-in (or once signed-in) account.
///
/// The session cookie is **not** here. It lives in secure storage, keyed by
/// this row's id (`SessionStore`), so the database file never holds anything
/// that signs in.
@DataClassName('ExternalAccount')
class ExternalAccounts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `'deckbox'`.
  TextColumn get provider => text()();

  /// As the service's own page reports it — on Deckbox, from the Friends link
  /// (D1). What the account group is titled with.
  TextColumn get username => text()();

  /// Last known state, so the lists folder can say *Signed out* without a
  /// request. False after an expired session or a log out.
  BoolColumn get sessionValid => boolean().withDefault(const Constant(true))();

  /// Unix seconds.
  IntColumn get createdAt => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {provider, username},
      ];
}

/// One list on the service — a Deckbox *set*: Inventory, Tradelist or
/// Wishlist. Decks are skipped for now (D2).
@DataClassName('ExternalList')
class ExternalLists extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get accountId =>
      integer().references(ExternalAccounts, #id, onDelete: KeyAction.cascade)();

  /// The service's id for it — Deckbox's set id.
  IntColumn get remoteId => integer()();

  /// `inventory`, `tradelist` or `wishlist`.
  TextColumn get kind => text()();
  TextColumn get name => text()();

  /// Unix seconds; null until the first pull. Drives the pull-on-open cooldown.
  IntColumn get lastPulledAt => integer().nullable()();

  /// Set when a push to a linked list may have changed this one — Deckbox
  /// keeps Inventory and Tradelist counts consistent on its side (D8). The next
  /// open pulls whatever the cooldown says.
  BoolColumn get stale => boolean().withDefault(const Constant(false))();

  /// The last pull's failure, shown rather than swallowed; null after a
  /// successful pull.
  TextColumn get lastPullError => text().nullable()();

  /// Wishlist only: the *Any printing* chip, which starts on and is remembered
  /// per list across visits and restarts.
  BoolColumn get anyPrinting => boolean().withDefault(const Constant(true))();

  @override
  List<Set<Column>> get uniqueKeys => [
        {accountId, remoteId},
      ];
}

/// One row of a list as the service has it — **the mirror**.
///
/// Replaced wholesale per list, in one transaction, on every successful pull,
/// so nothing outside may hold on to [id]. A row is known instead by its
/// **identity** — the raw fields that make it a row on Deckbox ([identityKey]).
/// Its row id is never stored: the export does not carry one, and it is looked
/// up at push time instead (D3, D5).
@DataClassName('ExternalEntry')
class ExternalEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get listId =>
      integer().references(ExternalLists, #id, onDelete: KeyAction.cascade)();

  /// The row's place in the export (sorted by name) — the mirror's own order.
  IntColumn get position => integer()();

  IntColumn get count => integer()();

  /// Inventory and Tradelist rows; 0 when not for trade.
  IntColumn get tradeCount => integer().withDefault(const Constant(0))();

  // ── identity: exactly as the export has it ─────────────────────────────────

  /// Deckbox's printing id. **Empty means "any printing"** — a generic row.
  TextColumn get printingId => text()();
  TextColumn get condition => text()();
  TextColumn get language => text()();

  /// `foil` or empty. Etched is an edition on Deckbox, not a foil value (D4).
  TextColumn get foil => text()();

  /// The per-row flags that are set, comma-joined — *Signed, Artist Proof,
  /// Altered Art, Misprint, Promo, Textless*. Empty for an ordinary row.
  TextColumn get rowFlags => text()();

  /// The fields above, joined — what a staged removal points at, and what a
  /// pull is matched by.
  TextColumn get identityKey => text()();

  // ── display ────────────────────────────────────────────────────────────────

  TextColumn get name => text()();
  TextColumn get edition => text()();
  TextColumn get editionCode => text()();
  TextColumn get cardNumber => text()();
  TextColumn get printingNote => text()();

  /// The export's *Last Updated*, as Unix seconds; null if absent.
  IntColumn get lastUpdated => integer().nullable()();

  // ── mapped to the app's own terms ──────────────────────────────────────────

  /// Scryfall printing id — from the export's *Scryfall ID*, or for an etched
  /// edition, resolved through the card cache. **Null for a generic row and for
  /// a row the app cannot map**; [anyPrinting] tells the two apart.
  TextColumn get cardId => text().nullable()();

  /// A printing of this card, for art and for matching scans by card.
  ///
  /// The same as [cardId] on a mapped row; on a generic row, the export's
  /// stand-in Scryfall id. **Never written back** — a generic row sent with it
  /// lands as that printing (D9 w5).
  TextColumn get cardRef => text().nullable()();

  BoolColumn get anyPrinting => boolean()();

  /// The app's finish, language and condition, where they map — for display.
  /// *Mint* shows as NM; *Proxy* has no app condition and stays null (D7); a
  /// generic row may leave any of them unset. The raw fields above are what
  /// identify the row.
  IntColumn get finish => integer().nullable()();
  TextColumn get languageCode => text().nullable()();
  IntColumn get conditionCode => integer().nullable()();
}

/// What the user wants Deckbox to change — **staged**, and sent only by an
/// explicit push (M3).
///
/// **A pull never touches these** beyond setting [flag] on a removal that has
/// become impossible. Each row carries everything needed to show it and to
/// send it, so it survives its Deckbox row disappearing, and a removal points
/// at that row by **identity** ([identityKey]) — never by an id a pull
/// recreates or Deckbox reassigns.
@DataClassName('StagedChange')
class StagedChanges extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get listId =>
      integer().references(ExternalLists, #id, onDelete: KeyAction.cascade)();

  /// `add` or `remove`.
  TextColumn get direction => text()();

  /// Always at least 1; the direction carries the sign.
  IntColumn get quantity => integer()();

  /// One row per thing staged: a removal's [identityKey]; an addition's
  /// printing (or card, if generic) and variant. Staging the same thing again
  /// raises [quantity].
  TextColumn get stageKey => text()();

  // ── what the card is: both directions ──────────────────────────────────────

  TextColumn get name => text()();

  /// Scryfall printing id; null for a generic addition and for a removal of a
  /// row the app could not map.
  TextColumn get cardId => text().nullable()();

  /// A printing for art and matching — the scanned one for a generic
  /// addition. Never sent.
  TextColumn get cardRef => text().nullable()();

  /// A generic ("any printing") addition, written by name only (D9).
  BoolColumn get anyPrinting => boolean().withDefault(const Constant(false))();

  IntColumn get finish => integer().nullable()();
  TextColumn get languageCode => text().nullable()();
  IntColumn get conditionCode => integer().nullable()();

  // Snapshot, for display and for the import's cosmetic columns.
  TextColumn get setCode => text().withDefault(const Constant(''))();
  TextColumn get setName => text().withDefault(const Constant(''))();
  TextColumn get collectorNumber => text().withDefault(const Constant(''))();

  /// An Inventory addition **also put up for trade** — sent with the import
  /// as *Tradelist Count* (tradelist.md, decision 3; schema 4).
  BoolColumn get forTrade => boolean().withDefault(const Constant(false))();

  // ── removals ──────────────────────────────────────────────────────────────

  /// The Deckbox row a removal is for — `ExternalEntries.identityKey`.
  TextColumn get identityKey => text().nullable()();

  /// Set by a pull when a removal can no longer be made: `gone`, `short:<n>`
  /// (only n left), or `ambiguous` (two rows match). **A flagged removal sends
  /// nothing**, not even the part that would fit.
  TextColumn get flag => text().nullable()();

  // ── an interrupted push ─────────────────────────────────────────────────────

  /// Unix seconds, set just before the request carrying this row goes out,
  /// with [expectedCount] — what the row's count should be once it lands. The
  /// next push checks a fresh pull against it before sending again, so a push
  /// cut off after sending can never send twice.
  IntColumn get sentAt => integer().nullable()();
  IntColumn get expectedCount => integer().nullable()();

  /// Why the last push did not send this row — kept with it, shown with it.
  TextColumn get lastError => text().nullable()();

  IntColumn get stagedAt => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {listId, direction, stageKey},
      ];

  @override
  List<String> get customConstraints => ['CHECK (quantity > 0)'];
}
