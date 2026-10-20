// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'external_dao.dart';

// ignore_for_file: type=lint
mixin _$ExternalDaoMixin on DatabaseAccessor<CollectionDatabase> {
  $ExternalAccountsTable get externalAccounts =>
      attachedDatabase.externalAccounts;
  $ExternalListsTable get externalLists => attachedDatabase.externalLists;
  $ExternalEntriesTable get externalEntries => attachedDatabase.externalEntries;
  $StagedChangesTable get stagedChanges => attachedDatabase.stagedChanges;
  ExternalDaoManager get managers => ExternalDaoManager(this);
}

class ExternalDaoManager {
  final _$ExternalDaoMixin _db;
  ExternalDaoManager(this._db);
  $$ExternalAccountsTableTableManager get externalAccounts =>
      $$ExternalAccountsTableTableManager(
        _db.attachedDatabase,
        _db.externalAccounts,
      );
  $$ExternalListsTableTableManager get externalLists =>
      $$ExternalListsTableTableManager(_db.attachedDatabase, _db.externalLists);
  $$ExternalEntriesTableTableManager get externalEntries =>
      $$ExternalEntriesTableTableManager(
        _db.attachedDatabase,
        _db.externalEntries,
      );
  $$StagedChangesTableTableManager get stagedChanges =>
      $$StagedChangesTableTableManager(_db.attachedDatabase, _db.stagedChanges);
}
