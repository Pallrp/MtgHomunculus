// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection_database.dart';

// ignore_for_file: type=lint
class $ListsTable extends Lists with TableInfo<$ListsTable, CardList> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ListsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    isDefault,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lists';
  @override
  VerificationContext validateIntegrity(
    Insertable<CardList> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CardList map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardList(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ListsTable createAlias(String alias) {
    return $ListsTable(attachedDatabase, alias);
  }
}

class CardList extends DataClass implements Insertable<CardList> {
  final int id;
  final String name;
  final String description;

  /// The always-present buffer list that replaces Quick Scan: scan into it,
  /// then cut or copy into a real list. Exactly one row carries this.
  final bool isDefault;
  final int createdAt;
  final int updatedAt;
  const CardList({
    required this.id,
    required this.name,
    required this.description,
    required this.isDefault,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['description'] = Variable<String>(description);
    map['is_default'] = Variable<bool>(isDefault);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ListsCompanion toCompanion(bool nullToAbsent) {
    return ListsCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      isDefault: Value(isDefault),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CardList.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardList(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String>(json['description']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String>(description),
      'isDefault': serializer.toJson<bool>(isDefault),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  CardList copyWith({
    int? id,
    String? name,
    String? description,
    bool? isDefault,
    int? createdAt,
    int? updatedAt,
  }) => CardList(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CardList copyWithCompanion(ListsCompanion data) {
    return CardList(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardList(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, description, isDefault, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardList &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.isDefault == this.isDefault &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ListsCompanion extends UpdateCompanion<CardList> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> description;
  final Value<bool> isDefault;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  const ListsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ListsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    this.isDefault = const Value.absent(),
    required int createdAt,
    required int updatedAt,
  }) : name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CardList> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<bool>? isDefault,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (isDefault != null) 'is_default': isDefault,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ListsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? description,
    Value<bool>? isDefault,
    Value<int>? createdAt,
    Value<int>? updatedAt,
  }) {
    return ListsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ListsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $EntriesTable extends Entries with TableInfo<$EntriesTable, Entry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _listIdMeta = const VerificationMeta('listId');
  @override
  late final GeneratedColumn<int> listId = GeneratedColumn<int>(
    'list_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES lists (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finishMeta = const VerificationMeta('finish');
  @override
  late final GeneratedColumn<int> finish = GeneratedColumn<int>(
    'finish',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conditionMeta = const VerificationMeta(
    'condition',
  );
  @override
  late final GeneratedColumn<int> condition = GeneratedColumn<int>(
    'condition',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapNameMeta = const VerificationMeta(
    'snapName',
  );
  @override
  late final GeneratedColumn<String> snapName = GeneratedColumn<String>(
    'snap_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapSetCodeMeta = const VerificationMeta(
    'snapSetCode',
  );
  @override
  late final GeneratedColumn<String> snapSetCode = GeneratedColumn<String>(
    'snap_set_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapSetNameMeta = const VerificationMeta(
    'snapSetName',
  );
  @override
  late final GeneratedColumn<String> snapSetName = GeneratedColumn<String>(
    'snap_set_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _snapCollectorMeta = const VerificationMeta(
    'snapCollector',
  );
  @override
  late final GeneratedColumn<String> snapCollector = GeneratedColumn<String>(
    'snap_collector',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    listId,
    cardId,
    finish,
    language,
    condition,
    quantity,
    addedAt,
    snapName,
    snapSetCode,
    snapSetName,
    snapCollector,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<Entry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('list_id')) {
      context.handle(
        _listIdMeta,
        listId.isAcceptableOrUnknown(data['list_id']!, _listIdMeta),
      );
    } else if (isInserting) {
      context.missing(_listIdMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('finish')) {
      context.handle(
        _finishMeta,
        finish.isAcceptableOrUnknown(data['finish']!, _finishMeta),
      );
    } else if (isInserting) {
      context.missing(_finishMeta);
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    } else if (isInserting) {
      context.missing(_languageMeta);
    }
    if (data.containsKey('condition')) {
      context.handle(
        _conditionMeta,
        condition.isAcceptableOrUnknown(data['condition']!, _conditionMeta),
      );
    } else if (isInserting) {
      context.missing(_conditionMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('snap_name')) {
      context.handle(
        _snapNameMeta,
        snapName.isAcceptableOrUnknown(data['snap_name']!, _snapNameMeta),
      );
    } else if (isInserting) {
      context.missing(_snapNameMeta);
    }
    if (data.containsKey('snap_set_code')) {
      context.handle(
        _snapSetCodeMeta,
        snapSetCode.isAcceptableOrUnknown(
          data['snap_set_code']!,
          _snapSetCodeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapSetCodeMeta);
    }
    if (data.containsKey('snap_set_name')) {
      context.handle(
        _snapSetNameMeta,
        snapSetName.isAcceptableOrUnknown(
          data['snap_set_name']!,
          _snapSetNameMeta,
        ),
      );
    }
    if (data.containsKey('snap_collector')) {
      context.handle(
        _snapCollectorMeta,
        snapCollector.isAcceptableOrUnknown(
          data['snap_collector']!,
          _snapCollectorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapCollectorMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {listId, cardId, finish, language, condition},
  ];
  @override
  Entry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Entry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      listId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}list_id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      finish: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}finish'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      condition: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}condition'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
      snapName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snap_name'],
      )!,
      snapSetCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snap_set_code'],
      )!,
      snapSetName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snap_set_name'],
      )!,
      snapCollector: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snap_collector'],
      )!,
    );
  }

  @override
  $EntriesTable createAlias(String alias) {
    return $EntriesTable(attachedDatabase, alias);
  }
}

class Entry extends DataClass implements Insertable<Entry> {
  final int id;
  final int listId;

  /// Scryfall printing id. Not `oracle_id`: an entry is about a specific
  /// printing, not a card.
  final String cardId;
  final int finish;
  final String language;
  final int condition;

  /// Always at least 1 — see [customConstraints]. Zero means "remove the row",
  /// which [CollectionDatabase.setQuantity] does rather than storing it.
  final int quantity;

  /// Unix seconds. Powers the "Scanned" sort order.
  final int addedAt;
  final String snapName;
  final String snapSetCode;

  /// The set's full name, stored rather than joined.
  ///
  /// It is display data with no identifying role — [snapSetCode] is what names
  /// the printing — so keeping it here rather than looking it up in `cards.db`
  /// is what lets an export and a row render with the card cache absent, which
  /// is the entire point of the snapshot. Stale if Scryfall ever renames a set,
  /// and that is correct: this records what the card was called when it was
  /// added, it is not a cache to keep fresh.
  final String snapSetName;
  final String snapCollector;
  const Entry({
    required this.id,
    required this.listId,
    required this.cardId,
    required this.finish,
    required this.language,
    required this.condition,
    required this.quantity,
    required this.addedAt,
    required this.snapName,
    required this.snapSetCode,
    required this.snapSetName,
    required this.snapCollector,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['list_id'] = Variable<int>(listId);
    map['card_id'] = Variable<String>(cardId);
    map['finish'] = Variable<int>(finish);
    map['language'] = Variable<String>(language);
    map['condition'] = Variable<int>(condition);
    map['quantity'] = Variable<int>(quantity);
    map['added_at'] = Variable<int>(addedAt);
    map['snap_name'] = Variable<String>(snapName);
    map['snap_set_code'] = Variable<String>(snapSetCode);
    map['snap_set_name'] = Variable<String>(snapSetName);
    map['snap_collector'] = Variable<String>(snapCollector);
    return map;
  }

  EntriesCompanion toCompanion(bool nullToAbsent) {
    return EntriesCompanion(
      id: Value(id),
      listId: Value(listId),
      cardId: Value(cardId),
      finish: Value(finish),
      language: Value(language),
      condition: Value(condition),
      quantity: Value(quantity),
      addedAt: Value(addedAt),
      snapName: Value(snapName),
      snapSetCode: Value(snapSetCode),
      snapSetName: Value(snapSetName),
      snapCollector: Value(snapCollector),
    );
  }

  factory Entry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Entry(
      id: serializer.fromJson<int>(json['id']),
      listId: serializer.fromJson<int>(json['listId']),
      cardId: serializer.fromJson<String>(json['cardId']),
      finish: serializer.fromJson<int>(json['finish']),
      language: serializer.fromJson<String>(json['language']),
      condition: serializer.fromJson<int>(json['condition']),
      quantity: serializer.fromJson<int>(json['quantity']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
      snapName: serializer.fromJson<String>(json['snapName']),
      snapSetCode: serializer.fromJson<String>(json['snapSetCode']),
      snapSetName: serializer.fromJson<String>(json['snapSetName']),
      snapCollector: serializer.fromJson<String>(json['snapCollector']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'listId': serializer.toJson<int>(listId),
      'cardId': serializer.toJson<String>(cardId),
      'finish': serializer.toJson<int>(finish),
      'language': serializer.toJson<String>(language),
      'condition': serializer.toJson<int>(condition),
      'quantity': serializer.toJson<int>(quantity),
      'addedAt': serializer.toJson<int>(addedAt),
      'snapName': serializer.toJson<String>(snapName),
      'snapSetCode': serializer.toJson<String>(snapSetCode),
      'snapSetName': serializer.toJson<String>(snapSetName),
      'snapCollector': serializer.toJson<String>(snapCollector),
    };
  }

  Entry copyWith({
    int? id,
    int? listId,
    String? cardId,
    int? finish,
    String? language,
    int? condition,
    int? quantity,
    int? addedAt,
    String? snapName,
    String? snapSetCode,
    String? snapSetName,
    String? snapCollector,
  }) => Entry(
    id: id ?? this.id,
    listId: listId ?? this.listId,
    cardId: cardId ?? this.cardId,
    finish: finish ?? this.finish,
    language: language ?? this.language,
    condition: condition ?? this.condition,
    quantity: quantity ?? this.quantity,
    addedAt: addedAt ?? this.addedAt,
    snapName: snapName ?? this.snapName,
    snapSetCode: snapSetCode ?? this.snapSetCode,
    snapSetName: snapSetName ?? this.snapSetName,
    snapCollector: snapCollector ?? this.snapCollector,
  );
  Entry copyWithCompanion(EntriesCompanion data) {
    return Entry(
      id: data.id.present ? data.id.value : this.id,
      listId: data.listId.present ? data.listId.value : this.listId,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      finish: data.finish.present ? data.finish.value : this.finish,
      language: data.language.present ? data.language.value : this.language,
      condition: data.condition.present ? data.condition.value : this.condition,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      snapName: data.snapName.present ? data.snapName.value : this.snapName,
      snapSetCode: data.snapSetCode.present
          ? data.snapSetCode.value
          : this.snapSetCode,
      snapSetName: data.snapSetName.present
          ? data.snapSetName.value
          : this.snapSetName,
      snapCollector: data.snapCollector.present
          ? data.snapCollector.value
          : this.snapCollector,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Entry(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('cardId: $cardId, ')
          ..write('finish: $finish, ')
          ..write('language: $language, ')
          ..write('condition: $condition, ')
          ..write('quantity: $quantity, ')
          ..write('addedAt: $addedAt, ')
          ..write('snapName: $snapName, ')
          ..write('snapSetCode: $snapSetCode, ')
          ..write('snapSetName: $snapSetName, ')
          ..write('snapCollector: $snapCollector')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    listId,
    cardId,
    finish,
    language,
    condition,
    quantity,
    addedAt,
    snapName,
    snapSetCode,
    snapSetName,
    snapCollector,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Entry &&
          other.id == this.id &&
          other.listId == this.listId &&
          other.cardId == this.cardId &&
          other.finish == this.finish &&
          other.language == this.language &&
          other.condition == this.condition &&
          other.quantity == this.quantity &&
          other.addedAt == this.addedAt &&
          other.snapName == this.snapName &&
          other.snapSetCode == this.snapSetCode &&
          other.snapSetName == this.snapSetName &&
          other.snapCollector == this.snapCollector);
}

class EntriesCompanion extends UpdateCompanion<Entry> {
  final Value<int> id;
  final Value<int> listId;
  final Value<String> cardId;
  final Value<int> finish;
  final Value<String> language;
  final Value<int> condition;
  final Value<int> quantity;
  final Value<int> addedAt;
  final Value<String> snapName;
  final Value<String> snapSetCode;
  final Value<String> snapSetName;
  final Value<String> snapCollector;
  const EntriesCompanion({
    this.id = const Value.absent(),
    this.listId = const Value.absent(),
    this.cardId = const Value.absent(),
    this.finish = const Value.absent(),
    this.language = const Value.absent(),
    this.condition = const Value.absent(),
    this.quantity = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.snapName = const Value.absent(),
    this.snapSetCode = const Value.absent(),
    this.snapSetName = const Value.absent(),
    this.snapCollector = const Value.absent(),
  });
  EntriesCompanion.insert({
    this.id = const Value.absent(),
    required int listId,
    required String cardId,
    required int finish,
    required String language,
    required int condition,
    required int quantity,
    required int addedAt,
    required String snapName,
    required String snapSetCode,
    this.snapSetName = const Value.absent(),
    required String snapCollector,
  }) : listId = Value(listId),
       cardId = Value(cardId),
       finish = Value(finish),
       language = Value(language),
       condition = Value(condition),
       quantity = Value(quantity),
       addedAt = Value(addedAt),
       snapName = Value(snapName),
       snapSetCode = Value(snapSetCode),
       snapCollector = Value(snapCollector);
  static Insertable<Entry> custom({
    Expression<int>? id,
    Expression<int>? listId,
    Expression<String>? cardId,
    Expression<int>? finish,
    Expression<String>? language,
    Expression<int>? condition,
    Expression<int>? quantity,
    Expression<int>? addedAt,
    Expression<String>? snapName,
    Expression<String>? snapSetCode,
    Expression<String>? snapSetName,
    Expression<String>? snapCollector,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (listId != null) 'list_id': listId,
      if (cardId != null) 'card_id': cardId,
      if (finish != null) 'finish': finish,
      if (language != null) 'language': language,
      if (condition != null) 'condition': condition,
      if (quantity != null) 'quantity': quantity,
      if (addedAt != null) 'added_at': addedAt,
      if (snapName != null) 'snap_name': snapName,
      if (snapSetCode != null) 'snap_set_code': snapSetCode,
      if (snapSetName != null) 'snap_set_name': snapSetName,
      if (snapCollector != null) 'snap_collector': snapCollector,
    });
  }

  EntriesCompanion copyWith({
    Value<int>? id,
    Value<int>? listId,
    Value<String>? cardId,
    Value<int>? finish,
    Value<String>? language,
    Value<int>? condition,
    Value<int>? quantity,
    Value<int>? addedAt,
    Value<String>? snapName,
    Value<String>? snapSetCode,
    Value<String>? snapSetName,
    Value<String>? snapCollector,
  }) {
    return EntriesCompanion(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      cardId: cardId ?? this.cardId,
      finish: finish ?? this.finish,
      language: language ?? this.language,
      condition: condition ?? this.condition,
      quantity: quantity ?? this.quantity,
      addedAt: addedAt ?? this.addedAt,
      snapName: snapName ?? this.snapName,
      snapSetCode: snapSetCode ?? this.snapSetCode,
      snapSetName: snapSetName ?? this.snapSetName,
      snapCollector: snapCollector ?? this.snapCollector,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (listId.present) {
      map['list_id'] = Variable<int>(listId.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (finish.present) {
      map['finish'] = Variable<int>(finish.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (condition.present) {
      map['condition'] = Variable<int>(condition.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (snapName.present) {
      map['snap_name'] = Variable<String>(snapName.value);
    }
    if (snapSetCode.present) {
      map['snap_set_code'] = Variable<String>(snapSetCode.value);
    }
    if (snapSetName.present) {
      map['snap_set_name'] = Variable<String>(snapSetName.value);
    }
    if (snapCollector.present) {
      map['snap_collector'] = Variable<String>(snapCollector.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntriesCompanion(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('cardId: $cardId, ')
          ..write('finish: $finish, ')
          ..write('language: $language, ')
          ..write('condition: $condition, ')
          ..write('quantity: $quantity, ')
          ..write('addedAt: $addedAt, ')
          ..write('snapName: $snapName, ')
          ..write('snapSetCode: $snapSetCode, ')
          ..write('snapSetName: $snapSetName, ')
          ..write('snapCollector: $snapCollector')
          ..write(')'))
        .toString();
  }
}

class $ExternalAccountsTable extends ExternalAccounts
    with TableInfo<$ExternalAccountsTable, ExternalAccount> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExternalAccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionValidMeta = const VerificationMeta(
    'sessionValid',
  );
  @override
  late final GeneratedColumn<bool> sessionValid = GeneratedColumn<bool>(
    'session_valid',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("session_valid" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    provider,
    username,
    sessionValid,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'external_accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExternalAccount> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('session_valid')) {
      context.handle(
        _sessionValidMeta,
        sessionValid.isAcceptableOrUnknown(
          data['session_valid']!,
          _sessionValidMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {provider, username},
  ];
  @override
  ExternalAccount map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExternalAccount(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      sessionValid: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}session_valid'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ExternalAccountsTable createAlias(String alias) {
    return $ExternalAccountsTable(attachedDatabase, alias);
  }
}

class ExternalAccount extends DataClass implements Insertable<ExternalAccount> {
  final int id;

  /// `'deckbox'`.
  final String provider;

  /// As the service's own page reports it — on Deckbox, from the Friends link
  /// (D1). What the account group is titled with.
  final String username;

  /// Last known state, so the lists folder can say *Signed out* without a
  /// request. False after an expired session or a log out.
  final bool sessionValid;

  /// Unix seconds.
  final int createdAt;
  const ExternalAccount({
    required this.id,
    required this.provider,
    required this.username,
    required this.sessionValid,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['provider'] = Variable<String>(provider);
    map['username'] = Variable<String>(username);
    map['session_valid'] = Variable<bool>(sessionValid);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ExternalAccountsCompanion toCompanion(bool nullToAbsent) {
    return ExternalAccountsCompanion(
      id: Value(id),
      provider: Value(provider),
      username: Value(username),
      sessionValid: Value(sessionValid),
      createdAt: Value(createdAt),
    );
  }

  factory ExternalAccount.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExternalAccount(
      id: serializer.fromJson<int>(json['id']),
      provider: serializer.fromJson<String>(json['provider']),
      username: serializer.fromJson<String>(json['username']),
      sessionValid: serializer.fromJson<bool>(json['sessionValid']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'provider': serializer.toJson<String>(provider),
      'username': serializer.toJson<String>(username),
      'sessionValid': serializer.toJson<bool>(sessionValid),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ExternalAccount copyWith({
    int? id,
    String? provider,
    String? username,
    bool? sessionValid,
    int? createdAt,
  }) => ExternalAccount(
    id: id ?? this.id,
    provider: provider ?? this.provider,
    username: username ?? this.username,
    sessionValid: sessionValid ?? this.sessionValid,
    createdAt: createdAt ?? this.createdAt,
  );
  ExternalAccount copyWithCompanion(ExternalAccountsCompanion data) {
    return ExternalAccount(
      id: data.id.present ? data.id.value : this.id,
      provider: data.provider.present ? data.provider.value : this.provider,
      username: data.username.present ? data.username.value : this.username,
      sessionValid: data.sessionValid.present
          ? data.sessionValid.value
          : this.sessionValid,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExternalAccount(')
          ..write('id: $id, ')
          ..write('provider: $provider, ')
          ..write('username: $username, ')
          ..write('sessionValid: $sessionValid, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, provider, username, sessionValid, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExternalAccount &&
          other.id == this.id &&
          other.provider == this.provider &&
          other.username == this.username &&
          other.sessionValid == this.sessionValid &&
          other.createdAt == this.createdAt);
}

class ExternalAccountsCompanion extends UpdateCompanion<ExternalAccount> {
  final Value<int> id;
  final Value<String> provider;
  final Value<String> username;
  final Value<bool> sessionValid;
  final Value<int> createdAt;
  const ExternalAccountsCompanion({
    this.id = const Value.absent(),
    this.provider = const Value.absent(),
    this.username = const Value.absent(),
    this.sessionValid = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ExternalAccountsCompanion.insert({
    this.id = const Value.absent(),
    required String provider,
    required String username,
    this.sessionValid = const Value.absent(),
    required int createdAt,
  }) : provider = Value(provider),
       username = Value(username),
       createdAt = Value(createdAt);
  static Insertable<ExternalAccount> custom({
    Expression<int>? id,
    Expression<String>? provider,
    Expression<String>? username,
    Expression<bool>? sessionValid,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (provider != null) 'provider': provider,
      if (username != null) 'username': username,
      if (sessionValid != null) 'session_valid': sessionValid,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ExternalAccountsCompanion copyWith({
    Value<int>? id,
    Value<String>? provider,
    Value<String>? username,
    Value<bool>? sessionValid,
    Value<int>? createdAt,
  }) {
    return ExternalAccountsCompanion(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      username: username ?? this.username,
      sessionValid: sessionValid ?? this.sessionValid,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (sessionValid.present) {
      map['session_valid'] = Variable<bool>(sessionValid.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExternalAccountsCompanion(')
          ..write('id: $id, ')
          ..write('provider: $provider, ')
          ..write('username: $username, ')
          ..write('sessionValid: $sessionValid, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ExternalListsTable extends ExternalLists
    with TableInfo<$ExternalListsTable, ExternalList> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExternalListsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<int> accountId = GeneratedColumn<int>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES external_accounts (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<int> remoteId = GeneratedColumn<int>(
    'remote_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastPulledAtMeta = const VerificationMeta(
    'lastPulledAt',
  );
  @override
  late final GeneratedColumn<int> lastPulledAt = GeneratedColumn<int>(
    'last_pulled_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _staleMeta = const VerificationMeta('stale');
  @override
  late final GeneratedColumn<bool> stale = GeneratedColumn<bool>(
    'stale',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("stale" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastPullErrorMeta = const VerificationMeta(
    'lastPullError',
  );
  @override
  late final GeneratedColumn<String> lastPullError = GeneratedColumn<String>(
    'last_pull_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _anyPrintingMeta = const VerificationMeta(
    'anyPrinting',
  );
  @override
  late final GeneratedColumn<bool> anyPrinting = GeneratedColumn<bool>(
    'any_printing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("any_printing" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    accountId,
    remoteId,
    kind,
    name,
    lastPulledAt,
    stale,
    lastPullError,
    anyPrinting,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'external_lists';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExternalList> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_remoteIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('last_pulled_at')) {
      context.handle(
        _lastPulledAtMeta,
        lastPulledAt.isAcceptableOrUnknown(
          data['last_pulled_at']!,
          _lastPulledAtMeta,
        ),
      );
    }
    if (data.containsKey('stale')) {
      context.handle(
        _staleMeta,
        stale.isAcceptableOrUnknown(data['stale']!, _staleMeta),
      );
    }
    if (data.containsKey('last_pull_error')) {
      context.handle(
        _lastPullErrorMeta,
        lastPullError.isAcceptableOrUnknown(
          data['last_pull_error']!,
          _lastPullErrorMeta,
        ),
      );
    }
    if (data.containsKey('any_printing')) {
      context.handle(
        _anyPrintingMeta,
        anyPrinting.isAcceptableOrUnknown(
          data['any_printing']!,
          _anyPrintingMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {accountId, remoteId},
  ];
  @override
  ExternalList map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExternalList(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}account_id'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      lastPulledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_pulled_at'],
      ),
      stale: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}stale'],
      )!,
      lastPullError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_pull_error'],
      ),
      anyPrinting: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}any_printing'],
      )!,
    );
  }

  @override
  $ExternalListsTable createAlias(String alias) {
    return $ExternalListsTable(attachedDatabase, alias);
  }
}

class ExternalList extends DataClass implements Insertable<ExternalList> {
  final int id;
  final int accountId;

  /// The service's id for it — Deckbox's set id.
  final int remoteId;

  /// `inventory`, `tradelist` or `wishlist`.
  final String kind;
  final String name;

  /// Unix seconds; null until the first pull. Drives the pull-on-open cooldown.
  final int? lastPulledAt;

  /// Set when a push to a linked list may have changed this one — Deckbox
  /// keeps Inventory and Tradelist counts consistent on its side (D8). The next
  /// open pulls whatever the cooldown says.
  final bool stale;

  /// The last pull's failure, shown rather than swallowed; null after a
  /// successful pull.
  final String? lastPullError;

  /// Wishlist only: the *Any printing* chip, which starts on and is remembered
  /// per list across visits and restarts.
  final bool anyPrinting;
  const ExternalList({
    required this.id,
    required this.accountId,
    required this.remoteId,
    required this.kind,
    required this.name,
    this.lastPulledAt,
    required this.stale,
    this.lastPullError,
    required this.anyPrinting,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['account_id'] = Variable<int>(accountId);
    map['remote_id'] = Variable<int>(remoteId);
    map['kind'] = Variable<String>(kind);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || lastPulledAt != null) {
      map['last_pulled_at'] = Variable<int>(lastPulledAt);
    }
    map['stale'] = Variable<bool>(stale);
    if (!nullToAbsent || lastPullError != null) {
      map['last_pull_error'] = Variable<String>(lastPullError);
    }
    map['any_printing'] = Variable<bool>(anyPrinting);
    return map;
  }

  ExternalListsCompanion toCompanion(bool nullToAbsent) {
    return ExternalListsCompanion(
      id: Value(id),
      accountId: Value(accountId),
      remoteId: Value(remoteId),
      kind: Value(kind),
      name: Value(name),
      lastPulledAt: lastPulledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPulledAt),
      stale: Value(stale),
      lastPullError: lastPullError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPullError),
      anyPrinting: Value(anyPrinting),
    );
  }

  factory ExternalList.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExternalList(
      id: serializer.fromJson<int>(json['id']),
      accountId: serializer.fromJson<int>(json['accountId']),
      remoteId: serializer.fromJson<int>(json['remoteId']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      lastPulledAt: serializer.fromJson<int?>(json['lastPulledAt']),
      stale: serializer.fromJson<bool>(json['stale']),
      lastPullError: serializer.fromJson<String?>(json['lastPullError']),
      anyPrinting: serializer.fromJson<bool>(json['anyPrinting']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'accountId': serializer.toJson<int>(accountId),
      'remoteId': serializer.toJson<int>(remoteId),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String>(name),
      'lastPulledAt': serializer.toJson<int?>(lastPulledAt),
      'stale': serializer.toJson<bool>(stale),
      'lastPullError': serializer.toJson<String?>(lastPullError),
      'anyPrinting': serializer.toJson<bool>(anyPrinting),
    };
  }

  ExternalList copyWith({
    int? id,
    int? accountId,
    int? remoteId,
    String? kind,
    String? name,
    Value<int?> lastPulledAt = const Value.absent(),
    bool? stale,
    Value<String?> lastPullError = const Value.absent(),
    bool? anyPrinting,
  }) => ExternalList(
    id: id ?? this.id,
    accountId: accountId ?? this.accountId,
    remoteId: remoteId ?? this.remoteId,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    lastPulledAt: lastPulledAt.present ? lastPulledAt.value : this.lastPulledAt,
    stale: stale ?? this.stale,
    lastPullError: lastPullError.present
        ? lastPullError.value
        : this.lastPullError,
    anyPrinting: anyPrinting ?? this.anyPrinting,
  );
  ExternalList copyWithCompanion(ExternalListsCompanion data) {
    return ExternalList(
      id: data.id.present ? data.id.value : this.id,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      lastPulledAt: data.lastPulledAt.present
          ? data.lastPulledAt.value
          : this.lastPulledAt,
      stale: data.stale.present ? data.stale.value : this.stale,
      lastPullError: data.lastPullError.present
          ? data.lastPullError.value
          : this.lastPullError,
      anyPrinting: data.anyPrinting.present
          ? data.anyPrinting.value
          : this.anyPrinting,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExternalList(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('remoteId: $remoteId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('lastPulledAt: $lastPulledAt, ')
          ..write('stale: $stale, ')
          ..write('lastPullError: $lastPullError, ')
          ..write('anyPrinting: $anyPrinting')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    accountId,
    remoteId,
    kind,
    name,
    lastPulledAt,
    stale,
    lastPullError,
    anyPrinting,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExternalList &&
          other.id == this.id &&
          other.accountId == this.accountId &&
          other.remoteId == this.remoteId &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.lastPulledAt == this.lastPulledAt &&
          other.stale == this.stale &&
          other.lastPullError == this.lastPullError &&
          other.anyPrinting == this.anyPrinting);
}

class ExternalListsCompanion extends UpdateCompanion<ExternalList> {
  final Value<int> id;
  final Value<int> accountId;
  final Value<int> remoteId;
  final Value<String> kind;
  final Value<String> name;
  final Value<int?> lastPulledAt;
  final Value<bool> stale;
  final Value<String?> lastPullError;
  final Value<bool> anyPrinting;
  const ExternalListsCompanion({
    this.id = const Value.absent(),
    this.accountId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.lastPulledAt = const Value.absent(),
    this.stale = const Value.absent(),
    this.lastPullError = const Value.absent(),
    this.anyPrinting = const Value.absent(),
  });
  ExternalListsCompanion.insert({
    this.id = const Value.absent(),
    required int accountId,
    required int remoteId,
    required String kind,
    required String name,
    this.lastPulledAt = const Value.absent(),
    this.stale = const Value.absent(),
    this.lastPullError = const Value.absent(),
    this.anyPrinting = const Value.absent(),
  }) : accountId = Value(accountId),
       remoteId = Value(remoteId),
       kind = Value(kind),
       name = Value(name);
  static Insertable<ExternalList> custom({
    Expression<int>? id,
    Expression<int>? accountId,
    Expression<int>? remoteId,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<int>? lastPulledAt,
    Expression<bool>? stale,
    Expression<String>? lastPullError,
    Expression<bool>? anyPrinting,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (accountId != null) 'account_id': accountId,
      if (remoteId != null) 'remote_id': remoteId,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (lastPulledAt != null) 'last_pulled_at': lastPulledAt,
      if (stale != null) 'stale': stale,
      if (lastPullError != null) 'last_pull_error': lastPullError,
      if (anyPrinting != null) 'any_printing': anyPrinting,
    });
  }

  ExternalListsCompanion copyWith({
    Value<int>? id,
    Value<int>? accountId,
    Value<int>? remoteId,
    Value<String>? kind,
    Value<String>? name,
    Value<int?>? lastPulledAt,
    Value<bool>? stale,
    Value<String?>? lastPullError,
    Value<bool>? anyPrinting,
  }) {
    return ExternalListsCompanion(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      remoteId: remoteId ?? this.remoteId,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      lastPulledAt: lastPulledAt ?? this.lastPulledAt,
      stale: stale ?? this.stale,
      lastPullError: lastPullError ?? this.lastPullError,
      anyPrinting: anyPrinting ?? this.anyPrinting,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<int>(accountId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<int>(remoteId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (lastPulledAt.present) {
      map['last_pulled_at'] = Variable<int>(lastPulledAt.value);
    }
    if (stale.present) {
      map['stale'] = Variable<bool>(stale.value);
    }
    if (lastPullError.present) {
      map['last_pull_error'] = Variable<String>(lastPullError.value);
    }
    if (anyPrinting.present) {
      map['any_printing'] = Variable<bool>(anyPrinting.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExternalListsCompanion(')
          ..write('id: $id, ')
          ..write('accountId: $accountId, ')
          ..write('remoteId: $remoteId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('lastPulledAt: $lastPulledAt, ')
          ..write('stale: $stale, ')
          ..write('lastPullError: $lastPullError, ')
          ..write('anyPrinting: $anyPrinting')
          ..write(')'))
        .toString();
  }
}

class $ExternalEntriesTable extends ExternalEntries
    with TableInfo<$ExternalEntriesTable, ExternalEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExternalEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _listIdMeta = const VerificationMeta('listId');
  @override
  late final GeneratedColumn<int> listId = GeneratedColumn<int>(
    'list_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES external_lists (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tradeCountMeta = const VerificationMeta(
    'tradeCount',
  );
  @override
  late final GeneratedColumn<int> tradeCount = GeneratedColumn<int>(
    'trade_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _printingIdMeta = const VerificationMeta(
    'printingId',
  );
  @override
  late final GeneratedColumn<String> printingId = GeneratedColumn<String>(
    'printing_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conditionMeta = const VerificationMeta(
    'condition',
  );
  @override
  late final GeneratedColumn<String> condition = GeneratedColumn<String>(
    'condition',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _foilMeta = const VerificationMeta('foil');
  @override
  late final GeneratedColumn<String> foil = GeneratedColumn<String>(
    'foil',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowFlagsMeta = const VerificationMeta(
    'rowFlags',
  );
  @override
  late final GeneratedColumn<String> rowFlags = GeneratedColumn<String>(
    'row_flags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _editionMeta = const VerificationMeta(
    'edition',
  );
  @override
  late final GeneratedColumn<String> edition = GeneratedColumn<String>(
    'edition',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _editionCodeMeta = const VerificationMeta(
    'editionCode',
  );
  @override
  late final GeneratedColumn<String> editionCode = GeneratedColumn<String>(
    'edition_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardNumberMeta = const VerificationMeta(
    'cardNumber',
  );
  @override
  late final GeneratedColumn<String> cardNumber = GeneratedColumn<String>(
    'card_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _printingNoteMeta = const VerificationMeta(
    'printingNote',
  );
  @override
  late final GeneratedColumn<String> printingNote = GeneratedColumn<String>(
    'printing_note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUpdatedMeta = const VerificationMeta(
    'lastUpdated',
  );
  @override
  late final GeneratedColumn<int> lastUpdated = GeneratedColumn<int>(
    'last_updated',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cardRefMeta = const VerificationMeta(
    'cardRef',
  );
  @override
  late final GeneratedColumn<String> cardRef = GeneratedColumn<String>(
    'card_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _anyPrintingMeta = const VerificationMeta(
    'anyPrinting',
  );
  @override
  late final GeneratedColumn<bool> anyPrinting = GeneratedColumn<bool>(
    'any_printing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("any_printing" IN (0, 1))',
    ),
  );
  static const VerificationMeta _finishMeta = const VerificationMeta('finish');
  @override
  late final GeneratedColumn<int> finish = GeneratedColumn<int>(
    'finish',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _languageCodeMeta = const VerificationMeta(
    'languageCode',
  );
  @override
  late final GeneratedColumn<String> languageCode = GeneratedColumn<String>(
    'language_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conditionCodeMeta = const VerificationMeta(
    'conditionCode',
  );
  @override
  late final GeneratedColumn<int> conditionCode = GeneratedColumn<int>(
    'condition_code',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    listId,
    position,
    count,
    tradeCount,
    printingId,
    condition,
    language,
    foil,
    rowFlags,
    identityKey,
    name,
    edition,
    editionCode,
    cardNumber,
    printingNote,
    lastUpdated,
    cardId,
    cardRef,
    anyPrinting,
    finish,
    languageCode,
    conditionCode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'external_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExternalEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('list_id')) {
      context.handle(
        _listIdMeta,
        listId.isAcceptableOrUnknown(data['list_id']!, _listIdMeta),
      );
    } else if (isInserting) {
      context.missing(_listIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    } else if (isInserting) {
      context.missing(_countMeta);
    }
    if (data.containsKey('trade_count')) {
      context.handle(
        _tradeCountMeta,
        tradeCount.isAcceptableOrUnknown(data['trade_count']!, _tradeCountMeta),
      );
    }
    if (data.containsKey('printing_id')) {
      context.handle(
        _printingIdMeta,
        printingId.isAcceptableOrUnknown(data['printing_id']!, _printingIdMeta),
      );
    } else if (isInserting) {
      context.missing(_printingIdMeta);
    }
    if (data.containsKey('condition')) {
      context.handle(
        _conditionMeta,
        condition.isAcceptableOrUnknown(data['condition']!, _conditionMeta),
      );
    } else if (isInserting) {
      context.missing(_conditionMeta);
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    } else if (isInserting) {
      context.missing(_languageMeta);
    }
    if (data.containsKey('foil')) {
      context.handle(
        _foilMeta,
        foil.isAcceptableOrUnknown(data['foil']!, _foilMeta),
      );
    } else if (isInserting) {
      context.missing(_foilMeta);
    }
    if (data.containsKey('row_flags')) {
      context.handle(
        _rowFlagsMeta,
        rowFlags.isAcceptableOrUnknown(data['row_flags']!, _rowFlagsMeta),
      );
    } else if (isInserting) {
      context.missing(_rowFlagsMeta);
    }
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('edition')) {
      context.handle(
        _editionMeta,
        edition.isAcceptableOrUnknown(data['edition']!, _editionMeta),
      );
    } else if (isInserting) {
      context.missing(_editionMeta);
    }
    if (data.containsKey('edition_code')) {
      context.handle(
        _editionCodeMeta,
        editionCode.isAcceptableOrUnknown(
          data['edition_code']!,
          _editionCodeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_editionCodeMeta);
    }
    if (data.containsKey('card_number')) {
      context.handle(
        _cardNumberMeta,
        cardNumber.isAcceptableOrUnknown(data['card_number']!, _cardNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_cardNumberMeta);
    }
    if (data.containsKey('printing_note')) {
      context.handle(
        _printingNoteMeta,
        printingNote.isAcceptableOrUnknown(
          data['printing_note']!,
          _printingNoteMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_printingNoteMeta);
    }
    if (data.containsKey('last_updated')) {
      context.handle(
        _lastUpdatedMeta,
        lastUpdated.isAcceptableOrUnknown(
          data['last_updated']!,
          _lastUpdatedMeta,
        ),
      );
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    }
    if (data.containsKey('card_ref')) {
      context.handle(
        _cardRefMeta,
        cardRef.isAcceptableOrUnknown(data['card_ref']!, _cardRefMeta),
      );
    }
    if (data.containsKey('any_printing')) {
      context.handle(
        _anyPrintingMeta,
        anyPrinting.isAcceptableOrUnknown(
          data['any_printing']!,
          _anyPrintingMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_anyPrintingMeta);
    }
    if (data.containsKey('finish')) {
      context.handle(
        _finishMeta,
        finish.isAcceptableOrUnknown(data['finish']!, _finishMeta),
      );
    }
    if (data.containsKey('language_code')) {
      context.handle(
        _languageCodeMeta,
        languageCode.isAcceptableOrUnknown(
          data['language_code']!,
          _languageCodeMeta,
        ),
      );
    }
    if (data.containsKey('condition_code')) {
      context.handle(
        _conditionCodeMeta,
        conditionCode.isAcceptableOrUnknown(
          data['condition_code']!,
          _conditionCodeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExternalEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExternalEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      listId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}list_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      tradeCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}trade_count'],
      )!,
      printingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}printing_id'],
      )!,
      condition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}condition'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      foil: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}foil'],
      )!,
      rowFlags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row_flags'],
      )!,
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      edition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}edition'],
      )!,
      editionCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}edition_code'],
      )!,
      cardNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_number'],
      )!,
      printingNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}printing_note'],
      )!,
      lastUpdated: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_updated'],
      ),
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      ),
      cardRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_ref'],
      ),
      anyPrinting: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}any_printing'],
      )!,
      finish: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}finish'],
      ),
      languageCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language_code'],
      ),
      conditionCode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}condition_code'],
      ),
    );
  }

  @override
  $ExternalEntriesTable createAlias(String alias) {
    return $ExternalEntriesTable(attachedDatabase, alias);
  }
}

class ExternalEntry extends DataClass implements Insertable<ExternalEntry> {
  final int id;
  final int listId;

  /// The row's place in the export (sorted by name) — the mirror's own order.
  final int position;
  final int count;

  /// Inventory and Tradelist rows; 0 when not for trade.
  final int tradeCount;

  /// Deckbox's printing id. **Empty means "any printing"** — a generic row.
  final String printingId;
  final String condition;
  final String language;

  /// `foil` or empty. Etched is an edition on Deckbox, not a foil value (D4).
  final String foil;

  /// The per-row flags that are set, comma-joined — *Signed, Artist Proof,
  /// Altered Art, Misprint, Promo, Textless*. Empty for an ordinary row.
  final String rowFlags;

  /// The fields above, joined — what a staged removal points at, and what a
  /// pull is matched by.
  final String identityKey;
  final String name;
  final String edition;
  final String editionCode;
  final String cardNumber;
  final String printingNote;

  /// The export's *Last Updated*, as Unix seconds; null if absent.
  final int? lastUpdated;

  /// Scryfall printing id — from the export's *Scryfall ID*, or for an etched
  /// edition, resolved through the card cache. **Null for a generic row and for
  /// a row the app cannot map**; [anyPrinting] tells the two apart.
  final String? cardId;

  /// A printing of this card, for art and for matching scans by card.
  ///
  /// The same as [cardId] on a mapped row; on a generic row, the export's
  /// stand-in Scryfall id. **Never written back** — a generic row sent with it
  /// lands as that printing (D9 w5).
  final String? cardRef;
  final bool anyPrinting;

  /// The app's finish, language and condition, where they map. Null where they
  /// do not — *Mint* and *Proxy* have no app condition (D7) — and the raw
  /// fields above are what count.
  final int? finish;
  final String? languageCode;
  final int? conditionCode;
  const ExternalEntry({
    required this.id,
    required this.listId,
    required this.position,
    required this.count,
    required this.tradeCount,
    required this.printingId,
    required this.condition,
    required this.language,
    required this.foil,
    required this.rowFlags,
    required this.identityKey,
    required this.name,
    required this.edition,
    required this.editionCode,
    required this.cardNumber,
    required this.printingNote,
    this.lastUpdated,
    this.cardId,
    this.cardRef,
    required this.anyPrinting,
    this.finish,
    this.languageCode,
    this.conditionCode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['list_id'] = Variable<int>(listId);
    map['position'] = Variable<int>(position);
    map['count'] = Variable<int>(count);
    map['trade_count'] = Variable<int>(tradeCount);
    map['printing_id'] = Variable<String>(printingId);
    map['condition'] = Variable<String>(condition);
    map['language'] = Variable<String>(language);
    map['foil'] = Variable<String>(foil);
    map['row_flags'] = Variable<String>(rowFlags);
    map['identity_key'] = Variable<String>(identityKey);
    map['name'] = Variable<String>(name);
    map['edition'] = Variable<String>(edition);
    map['edition_code'] = Variable<String>(editionCode);
    map['card_number'] = Variable<String>(cardNumber);
    map['printing_note'] = Variable<String>(printingNote);
    if (!nullToAbsent || lastUpdated != null) {
      map['last_updated'] = Variable<int>(lastUpdated);
    }
    if (!nullToAbsent || cardId != null) {
      map['card_id'] = Variable<String>(cardId);
    }
    if (!nullToAbsent || cardRef != null) {
      map['card_ref'] = Variable<String>(cardRef);
    }
    map['any_printing'] = Variable<bool>(anyPrinting);
    if (!nullToAbsent || finish != null) {
      map['finish'] = Variable<int>(finish);
    }
    if (!nullToAbsent || languageCode != null) {
      map['language_code'] = Variable<String>(languageCode);
    }
    if (!nullToAbsent || conditionCode != null) {
      map['condition_code'] = Variable<int>(conditionCode);
    }
    return map;
  }

  ExternalEntriesCompanion toCompanion(bool nullToAbsent) {
    return ExternalEntriesCompanion(
      id: Value(id),
      listId: Value(listId),
      position: Value(position),
      count: Value(count),
      tradeCount: Value(tradeCount),
      printingId: Value(printingId),
      condition: Value(condition),
      language: Value(language),
      foil: Value(foil),
      rowFlags: Value(rowFlags),
      identityKey: Value(identityKey),
      name: Value(name),
      edition: Value(edition),
      editionCode: Value(editionCode),
      cardNumber: Value(cardNumber),
      printingNote: Value(printingNote),
      lastUpdated: lastUpdated == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUpdated),
      cardId: cardId == null && nullToAbsent
          ? const Value.absent()
          : Value(cardId),
      cardRef: cardRef == null && nullToAbsent
          ? const Value.absent()
          : Value(cardRef),
      anyPrinting: Value(anyPrinting),
      finish: finish == null && nullToAbsent
          ? const Value.absent()
          : Value(finish),
      languageCode: languageCode == null && nullToAbsent
          ? const Value.absent()
          : Value(languageCode),
      conditionCode: conditionCode == null && nullToAbsent
          ? const Value.absent()
          : Value(conditionCode),
    );
  }

  factory ExternalEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExternalEntry(
      id: serializer.fromJson<int>(json['id']),
      listId: serializer.fromJson<int>(json['listId']),
      position: serializer.fromJson<int>(json['position']),
      count: serializer.fromJson<int>(json['count']),
      tradeCount: serializer.fromJson<int>(json['tradeCount']),
      printingId: serializer.fromJson<String>(json['printingId']),
      condition: serializer.fromJson<String>(json['condition']),
      language: serializer.fromJson<String>(json['language']),
      foil: serializer.fromJson<String>(json['foil']),
      rowFlags: serializer.fromJson<String>(json['rowFlags']),
      identityKey: serializer.fromJson<String>(json['identityKey']),
      name: serializer.fromJson<String>(json['name']),
      edition: serializer.fromJson<String>(json['edition']),
      editionCode: serializer.fromJson<String>(json['editionCode']),
      cardNumber: serializer.fromJson<String>(json['cardNumber']),
      printingNote: serializer.fromJson<String>(json['printingNote']),
      lastUpdated: serializer.fromJson<int?>(json['lastUpdated']),
      cardId: serializer.fromJson<String?>(json['cardId']),
      cardRef: serializer.fromJson<String?>(json['cardRef']),
      anyPrinting: serializer.fromJson<bool>(json['anyPrinting']),
      finish: serializer.fromJson<int?>(json['finish']),
      languageCode: serializer.fromJson<String?>(json['languageCode']),
      conditionCode: serializer.fromJson<int?>(json['conditionCode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'listId': serializer.toJson<int>(listId),
      'position': serializer.toJson<int>(position),
      'count': serializer.toJson<int>(count),
      'tradeCount': serializer.toJson<int>(tradeCount),
      'printingId': serializer.toJson<String>(printingId),
      'condition': serializer.toJson<String>(condition),
      'language': serializer.toJson<String>(language),
      'foil': serializer.toJson<String>(foil),
      'rowFlags': serializer.toJson<String>(rowFlags),
      'identityKey': serializer.toJson<String>(identityKey),
      'name': serializer.toJson<String>(name),
      'edition': serializer.toJson<String>(edition),
      'editionCode': serializer.toJson<String>(editionCode),
      'cardNumber': serializer.toJson<String>(cardNumber),
      'printingNote': serializer.toJson<String>(printingNote),
      'lastUpdated': serializer.toJson<int?>(lastUpdated),
      'cardId': serializer.toJson<String?>(cardId),
      'cardRef': serializer.toJson<String?>(cardRef),
      'anyPrinting': serializer.toJson<bool>(anyPrinting),
      'finish': serializer.toJson<int?>(finish),
      'languageCode': serializer.toJson<String?>(languageCode),
      'conditionCode': serializer.toJson<int?>(conditionCode),
    };
  }

  ExternalEntry copyWith({
    int? id,
    int? listId,
    int? position,
    int? count,
    int? tradeCount,
    String? printingId,
    String? condition,
    String? language,
    String? foil,
    String? rowFlags,
    String? identityKey,
    String? name,
    String? edition,
    String? editionCode,
    String? cardNumber,
    String? printingNote,
    Value<int?> lastUpdated = const Value.absent(),
    Value<String?> cardId = const Value.absent(),
    Value<String?> cardRef = const Value.absent(),
    bool? anyPrinting,
    Value<int?> finish = const Value.absent(),
    Value<String?> languageCode = const Value.absent(),
    Value<int?> conditionCode = const Value.absent(),
  }) => ExternalEntry(
    id: id ?? this.id,
    listId: listId ?? this.listId,
    position: position ?? this.position,
    count: count ?? this.count,
    tradeCount: tradeCount ?? this.tradeCount,
    printingId: printingId ?? this.printingId,
    condition: condition ?? this.condition,
    language: language ?? this.language,
    foil: foil ?? this.foil,
    rowFlags: rowFlags ?? this.rowFlags,
    identityKey: identityKey ?? this.identityKey,
    name: name ?? this.name,
    edition: edition ?? this.edition,
    editionCode: editionCode ?? this.editionCode,
    cardNumber: cardNumber ?? this.cardNumber,
    printingNote: printingNote ?? this.printingNote,
    lastUpdated: lastUpdated.present ? lastUpdated.value : this.lastUpdated,
    cardId: cardId.present ? cardId.value : this.cardId,
    cardRef: cardRef.present ? cardRef.value : this.cardRef,
    anyPrinting: anyPrinting ?? this.anyPrinting,
    finish: finish.present ? finish.value : this.finish,
    languageCode: languageCode.present ? languageCode.value : this.languageCode,
    conditionCode: conditionCode.present
        ? conditionCode.value
        : this.conditionCode,
  );
  ExternalEntry copyWithCompanion(ExternalEntriesCompanion data) {
    return ExternalEntry(
      id: data.id.present ? data.id.value : this.id,
      listId: data.listId.present ? data.listId.value : this.listId,
      position: data.position.present ? data.position.value : this.position,
      count: data.count.present ? data.count.value : this.count,
      tradeCount: data.tradeCount.present
          ? data.tradeCount.value
          : this.tradeCount,
      printingId: data.printingId.present
          ? data.printingId.value
          : this.printingId,
      condition: data.condition.present ? data.condition.value : this.condition,
      language: data.language.present ? data.language.value : this.language,
      foil: data.foil.present ? data.foil.value : this.foil,
      rowFlags: data.rowFlags.present ? data.rowFlags.value : this.rowFlags,
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      name: data.name.present ? data.name.value : this.name,
      edition: data.edition.present ? data.edition.value : this.edition,
      editionCode: data.editionCode.present
          ? data.editionCode.value
          : this.editionCode,
      cardNumber: data.cardNumber.present
          ? data.cardNumber.value
          : this.cardNumber,
      printingNote: data.printingNote.present
          ? data.printingNote.value
          : this.printingNote,
      lastUpdated: data.lastUpdated.present
          ? data.lastUpdated.value
          : this.lastUpdated,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      cardRef: data.cardRef.present ? data.cardRef.value : this.cardRef,
      anyPrinting: data.anyPrinting.present
          ? data.anyPrinting.value
          : this.anyPrinting,
      finish: data.finish.present ? data.finish.value : this.finish,
      languageCode: data.languageCode.present
          ? data.languageCode.value
          : this.languageCode,
      conditionCode: data.conditionCode.present
          ? data.conditionCode.value
          : this.conditionCode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExternalEntry(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('position: $position, ')
          ..write('count: $count, ')
          ..write('tradeCount: $tradeCount, ')
          ..write('printingId: $printingId, ')
          ..write('condition: $condition, ')
          ..write('language: $language, ')
          ..write('foil: $foil, ')
          ..write('rowFlags: $rowFlags, ')
          ..write('identityKey: $identityKey, ')
          ..write('name: $name, ')
          ..write('edition: $edition, ')
          ..write('editionCode: $editionCode, ')
          ..write('cardNumber: $cardNumber, ')
          ..write('printingNote: $printingNote, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('cardId: $cardId, ')
          ..write('cardRef: $cardRef, ')
          ..write('anyPrinting: $anyPrinting, ')
          ..write('finish: $finish, ')
          ..write('languageCode: $languageCode, ')
          ..write('conditionCode: $conditionCode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    listId,
    position,
    count,
    tradeCount,
    printingId,
    condition,
    language,
    foil,
    rowFlags,
    identityKey,
    name,
    edition,
    editionCode,
    cardNumber,
    printingNote,
    lastUpdated,
    cardId,
    cardRef,
    anyPrinting,
    finish,
    languageCode,
    conditionCode,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExternalEntry &&
          other.id == this.id &&
          other.listId == this.listId &&
          other.position == this.position &&
          other.count == this.count &&
          other.tradeCount == this.tradeCount &&
          other.printingId == this.printingId &&
          other.condition == this.condition &&
          other.language == this.language &&
          other.foil == this.foil &&
          other.rowFlags == this.rowFlags &&
          other.identityKey == this.identityKey &&
          other.name == this.name &&
          other.edition == this.edition &&
          other.editionCode == this.editionCode &&
          other.cardNumber == this.cardNumber &&
          other.printingNote == this.printingNote &&
          other.lastUpdated == this.lastUpdated &&
          other.cardId == this.cardId &&
          other.cardRef == this.cardRef &&
          other.anyPrinting == this.anyPrinting &&
          other.finish == this.finish &&
          other.languageCode == this.languageCode &&
          other.conditionCode == this.conditionCode);
}

class ExternalEntriesCompanion extends UpdateCompanion<ExternalEntry> {
  final Value<int> id;
  final Value<int> listId;
  final Value<int> position;
  final Value<int> count;
  final Value<int> tradeCount;
  final Value<String> printingId;
  final Value<String> condition;
  final Value<String> language;
  final Value<String> foil;
  final Value<String> rowFlags;
  final Value<String> identityKey;
  final Value<String> name;
  final Value<String> edition;
  final Value<String> editionCode;
  final Value<String> cardNumber;
  final Value<String> printingNote;
  final Value<int?> lastUpdated;
  final Value<String?> cardId;
  final Value<String?> cardRef;
  final Value<bool> anyPrinting;
  final Value<int?> finish;
  final Value<String?> languageCode;
  final Value<int?> conditionCode;
  const ExternalEntriesCompanion({
    this.id = const Value.absent(),
    this.listId = const Value.absent(),
    this.position = const Value.absent(),
    this.count = const Value.absent(),
    this.tradeCount = const Value.absent(),
    this.printingId = const Value.absent(),
    this.condition = const Value.absent(),
    this.language = const Value.absent(),
    this.foil = const Value.absent(),
    this.rowFlags = const Value.absent(),
    this.identityKey = const Value.absent(),
    this.name = const Value.absent(),
    this.edition = const Value.absent(),
    this.editionCode = const Value.absent(),
    this.cardNumber = const Value.absent(),
    this.printingNote = const Value.absent(),
    this.lastUpdated = const Value.absent(),
    this.cardId = const Value.absent(),
    this.cardRef = const Value.absent(),
    this.anyPrinting = const Value.absent(),
    this.finish = const Value.absent(),
    this.languageCode = const Value.absent(),
    this.conditionCode = const Value.absent(),
  });
  ExternalEntriesCompanion.insert({
    this.id = const Value.absent(),
    required int listId,
    required int position,
    required int count,
    this.tradeCount = const Value.absent(),
    required String printingId,
    required String condition,
    required String language,
    required String foil,
    required String rowFlags,
    required String identityKey,
    required String name,
    required String edition,
    required String editionCode,
    required String cardNumber,
    required String printingNote,
    this.lastUpdated = const Value.absent(),
    this.cardId = const Value.absent(),
    this.cardRef = const Value.absent(),
    required bool anyPrinting,
    this.finish = const Value.absent(),
    this.languageCode = const Value.absent(),
    this.conditionCode = const Value.absent(),
  }) : listId = Value(listId),
       position = Value(position),
       count = Value(count),
       printingId = Value(printingId),
       condition = Value(condition),
       language = Value(language),
       foil = Value(foil),
       rowFlags = Value(rowFlags),
       identityKey = Value(identityKey),
       name = Value(name),
       edition = Value(edition),
       editionCode = Value(editionCode),
       cardNumber = Value(cardNumber),
       printingNote = Value(printingNote),
       anyPrinting = Value(anyPrinting);
  static Insertable<ExternalEntry> custom({
    Expression<int>? id,
    Expression<int>? listId,
    Expression<int>? position,
    Expression<int>? count,
    Expression<int>? tradeCount,
    Expression<String>? printingId,
    Expression<String>? condition,
    Expression<String>? language,
    Expression<String>? foil,
    Expression<String>? rowFlags,
    Expression<String>? identityKey,
    Expression<String>? name,
    Expression<String>? edition,
    Expression<String>? editionCode,
    Expression<String>? cardNumber,
    Expression<String>? printingNote,
    Expression<int>? lastUpdated,
    Expression<String>? cardId,
    Expression<String>? cardRef,
    Expression<bool>? anyPrinting,
    Expression<int>? finish,
    Expression<String>? languageCode,
    Expression<int>? conditionCode,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (listId != null) 'list_id': listId,
      if (position != null) 'position': position,
      if (count != null) 'count': count,
      if (tradeCount != null) 'trade_count': tradeCount,
      if (printingId != null) 'printing_id': printingId,
      if (condition != null) 'condition': condition,
      if (language != null) 'language': language,
      if (foil != null) 'foil': foil,
      if (rowFlags != null) 'row_flags': rowFlags,
      if (identityKey != null) 'identity_key': identityKey,
      if (name != null) 'name': name,
      if (edition != null) 'edition': edition,
      if (editionCode != null) 'edition_code': editionCode,
      if (cardNumber != null) 'card_number': cardNumber,
      if (printingNote != null) 'printing_note': printingNote,
      if (lastUpdated != null) 'last_updated': lastUpdated,
      if (cardId != null) 'card_id': cardId,
      if (cardRef != null) 'card_ref': cardRef,
      if (anyPrinting != null) 'any_printing': anyPrinting,
      if (finish != null) 'finish': finish,
      if (languageCode != null) 'language_code': languageCode,
      if (conditionCode != null) 'condition_code': conditionCode,
    });
  }

  ExternalEntriesCompanion copyWith({
    Value<int>? id,
    Value<int>? listId,
    Value<int>? position,
    Value<int>? count,
    Value<int>? tradeCount,
    Value<String>? printingId,
    Value<String>? condition,
    Value<String>? language,
    Value<String>? foil,
    Value<String>? rowFlags,
    Value<String>? identityKey,
    Value<String>? name,
    Value<String>? edition,
    Value<String>? editionCode,
    Value<String>? cardNumber,
    Value<String>? printingNote,
    Value<int?>? lastUpdated,
    Value<String?>? cardId,
    Value<String?>? cardRef,
    Value<bool>? anyPrinting,
    Value<int?>? finish,
    Value<String?>? languageCode,
    Value<int?>? conditionCode,
  }) {
    return ExternalEntriesCompanion(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      position: position ?? this.position,
      count: count ?? this.count,
      tradeCount: tradeCount ?? this.tradeCount,
      printingId: printingId ?? this.printingId,
      condition: condition ?? this.condition,
      language: language ?? this.language,
      foil: foil ?? this.foil,
      rowFlags: rowFlags ?? this.rowFlags,
      identityKey: identityKey ?? this.identityKey,
      name: name ?? this.name,
      edition: edition ?? this.edition,
      editionCode: editionCode ?? this.editionCode,
      cardNumber: cardNumber ?? this.cardNumber,
      printingNote: printingNote ?? this.printingNote,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      cardId: cardId ?? this.cardId,
      cardRef: cardRef ?? this.cardRef,
      anyPrinting: anyPrinting ?? this.anyPrinting,
      finish: finish ?? this.finish,
      languageCode: languageCode ?? this.languageCode,
      conditionCode: conditionCode ?? this.conditionCode,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (listId.present) {
      map['list_id'] = Variable<int>(listId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (tradeCount.present) {
      map['trade_count'] = Variable<int>(tradeCount.value);
    }
    if (printingId.present) {
      map['printing_id'] = Variable<String>(printingId.value);
    }
    if (condition.present) {
      map['condition'] = Variable<String>(condition.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (foil.present) {
      map['foil'] = Variable<String>(foil.value);
    }
    if (rowFlags.present) {
      map['row_flags'] = Variable<String>(rowFlags.value);
    }
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (edition.present) {
      map['edition'] = Variable<String>(edition.value);
    }
    if (editionCode.present) {
      map['edition_code'] = Variable<String>(editionCode.value);
    }
    if (cardNumber.present) {
      map['card_number'] = Variable<String>(cardNumber.value);
    }
    if (printingNote.present) {
      map['printing_note'] = Variable<String>(printingNote.value);
    }
    if (lastUpdated.present) {
      map['last_updated'] = Variable<int>(lastUpdated.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (cardRef.present) {
      map['card_ref'] = Variable<String>(cardRef.value);
    }
    if (anyPrinting.present) {
      map['any_printing'] = Variable<bool>(anyPrinting.value);
    }
    if (finish.present) {
      map['finish'] = Variable<int>(finish.value);
    }
    if (languageCode.present) {
      map['language_code'] = Variable<String>(languageCode.value);
    }
    if (conditionCode.present) {
      map['condition_code'] = Variable<int>(conditionCode.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExternalEntriesCompanion(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('position: $position, ')
          ..write('count: $count, ')
          ..write('tradeCount: $tradeCount, ')
          ..write('printingId: $printingId, ')
          ..write('condition: $condition, ')
          ..write('language: $language, ')
          ..write('foil: $foil, ')
          ..write('rowFlags: $rowFlags, ')
          ..write('identityKey: $identityKey, ')
          ..write('name: $name, ')
          ..write('edition: $edition, ')
          ..write('editionCode: $editionCode, ')
          ..write('cardNumber: $cardNumber, ')
          ..write('printingNote: $printingNote, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('cardId: $cardId, ')
          ..write('cardRef: $cardRef, ')
          ..write('anyPrinting: $anyPrinting, ')
          ..write('finish: $finish, ')
          ..write('languageCode: $languageCode, ')
          ..write('conditionCode: $conditionCode')
          ..write(')'))
        .toString();
  }
}

abstract class _$CollectionDatabase extends GeneratedDatabase {
  _$CollectionDatabase(QueryExecutor e) : super(e);
  $CollectionDatabaseManager get managers => $CollectionDatabaseManager(this);
  late final $ListsTable lists = $ListsTable(this);
  late final $EntriesTable entries = $EntriesTable(this);
  late final $ExternalAccountsTable externalAccounts = $ExternalAccountsTable(
    this,
  );
  late final $ExternalListsTable externalLists = $ExternalListsTable(this);
  late final $ExternalEntriesTable externalEntries = $ExternalEntriesTable(
    this,
  );
  late final ExternalDao externalDao = ExternalDao(this as CollectionDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    lists,
    entries,
    externalAccounts,
    externalLists,
    externalEntries,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'lists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('entries', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'external_accounts',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('external_lists', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'external_lists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('external_entries', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ListsTableCreateCompanionBuilder =
    ListsCompanion Function({
      Value<int> id,
      required String name,
      Value<String> description,
      Value<bool> isDefault,
      required int createdAt,
      required int updatedAt,
    });
typedef $$ListsTableUpdateCompanionBuilder =
    ListsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> description,
      Value<bool> isDefault,
      Value<int> createdAt,
      Value<int> updatedAt,
    });

final class $$ListsTableReferences
    extends BaseReferences<_$CollectionDatabase, $ListsTable, CardList> {
  $$ListsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$EntriesTable, List<Entry>> _entriesRefsTable(
    _$CollectionDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.entries,
    aliasName: 'lists__id__entries__list_id',
  );

  $$EntriesTableProcessedTableManager get entriesRefs {
    final manager = $$EntriesTableTableManager(
      $_db,
      $_db.entries,
    ).filter((f) => f.listId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_entriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ListsTableFilterComposer
    extends Composer<_$CollectionDatabase, $ListsTable> {
  $$ListsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> entriesRefs(
    Expression<bool> Function($$EntriesTableFilterComposer f) f,
  ) {
    final $$EntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entries,
      getReferencedColumn: (t) => t.listId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntriesTableFilterComposer(
            $db: $db,
            $table: $db.entries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ListsTableOrderingComposer
    extends Composer<_$CollectionDatabase, $ListsTable> {
  $$ListsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ListsTableAnnotationComposer
    extends Composer<_$CollectionDatabase, $ListsTable> {
  $$ListsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> entriesRefs<T extends Object>(
    Expression<T> Function($$EntriesTableAnnotationComposer a) f,
  ) {
    final $$EntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entries,
      getReferencedColumn: (t) => t.listId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.entries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ListsTableTableManager
    extends
        RootTableManager<
          _$CollectionDatabase,
          $ListsTable,
          CardList,
          $$ListsTableFilterComposer,
          $$ListsTableOrderingComposer,
          $$ListsTableAnnotationComposer,
          $$ListsTableCreateCompanionBuilder,
          $$ListsTableUpdateCompanionBuilder,
          (CardList, $$ListsTableReferences),
          CardList,
          PrefetchHooks Function({bool entriesRefs})
        > {
  $$ListsTableTableManager(_$CollectionDatabase db, $ListsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ListsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ListsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ListsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => ListsCompanion(
                id: id,
                name: name,
                description: description,
                isDefault: isDefault,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String> description = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                required int createdAt,
                required int updatedAt,
              }) => ListsCompanion.insert(
                id: id,
                name: name,
                description: description,
                isDefault: isDefault,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$ListsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({entriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (entriesRefs) db.entries],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (entriesRefs)
                    await $_getPrefetchedData<CardList, $ListsTable, Entry>(
                      currentTable: table,
                      referencedTable: $$ListsTableReferences._entriesRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$ListsTableReferences(db, table, p0).entriesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.listId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ListsTableProcessedTableManager =
    ProcessedTableManager<
      _$CollectionDatabase,
      $ListsTable,
      CardList,
      $$ListsTableFilterComposer,
      $$ListsTableOrderingComposer,
      $$ListsTableAnnotationComposer,
      $$ListsTableCreateCompanionBuilder,
      $$ListsTableUpdateCompanionBuilder,
      (CardList, $$ListsTableReferences),
      CardList,
      PrefetchHooks Function({bool entriesRefs})
    >;
typedef $$EntriesTableCreateCompanionBuilder =
    EntriesCompanion Function({
      Value<int> id,
      required int listId,
      required String cardId,
      required int finish,
      required String language,
      required int condition,
      required int quantity,
      required int addedAt,
      required String snapName,
      required String snapSetCode,
      Value<String> snapSetName,
      required String snapCollector,
    });
typedef $$EntriesTableUpdateCompanionBuilder =
    EntriesCompanion Function({
      Value<int> id,
      Value<int> listId,
      Value<String> cardId,
      Value<int> finish,
      Value<String> language,
      Value<int> condition,
      Value<int> quantity,
      Value<int> addedAt,
      Value<String> snapName,
      Value<String> snapSetCode,
      Value<String> snapSetName,
      Value<String> snapCollector,
    });

final class $$EntriesTableReferences
    extends BaseReferences<_$CollectionDatabase, $EntriesTable, Entry> {
  $$EntriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ListsTable _listIdTable(_$CollectionDatabase db) =>
      db.lists.createAlias('entries__list_id__lists__id');

  $$ListsTableProcessedTableManager get listId {
    final $_column = $_itemColumn<int>('list_id')!;

    final manager = $$ListsTableTableManager(
      $_db,
      $_db.lists,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_listIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EntriesTableFilterComposer
    extends Composer<_$CollectionDatabase, $EntriesTable> {
  $$EntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finish => $composableBuilder(
    column: $table.finish,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get condition => $composableBuilder(
    column: $table.condition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapName => $composableBuilder(
    column: $table.snapName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapSetCode => $composableBuilder(
    column: $table.snapSetCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapSetName => $composableBuilder(
    column: $table.snapSetName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapCollector => $composableBuilder(
    column: $table.snapCollector,
    builder: (column) => ColumnFilters(column),
  );

  $$ListsTableFilterComposer get listId {
    final $$ListsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.listId,
      referencedTable: $db.lists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ListsTableFilterComposer(
            $db: $db,
            $table: $db.lists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntriesTableOrderingComposer
    extends Composer<_$CollectionDatabase, $EntriesTable> {
  $$EntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finish => $composableBuilder(
    column: $table.finish,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get condition => $composableBuilder(
    column: $table.condition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapName => $composableBuilder(
    column: $table.snapName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapSetCode => $composableBuilder(
    column: $table.snapSetCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapSetName => $composableBuilder(
    column: $table.snapSetName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapCollector => $composableBuilder(
    column: $table.snapCollector,
    builder: (column) => ColumnOrderings(column),
  );

  $$ListsTableOrderingComposer get listId {
    final $$ListsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.listId,
      referencedTable: $db.lists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ListsTableOrderingComposer(
            $db: $db,
            $table: $db.lists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntriesTableAnnotationComposer
    extends Composer<_$CollectionDatabase, $EntriesTable> {
  $$EntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<int> get finish =>
      $composableBuilder(column: $table.finish, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<int> get condition =>
      $composableBuilder(column: $table.condition, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<String> get snapName =>
      $composableBuilder(column: $table.snapName, builder: (column) => column);

  GeneratedColumn<String> get snapSetCode => $composableBuilder(
    column: $table.snapSetCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snapSetName => $composableBuilder(
    column: $table.snapSetName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snapCollector => $composableBuilder(
    column: $table.snapCollector,
    builder: (column) => column,
  );

  $$ListsTableAnnotationComposer get listId {
    final $$ListsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.listId,
      referencedTable: $db.lists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ListsTableAnnotationComposer(
            $db: $db,
            $table: $db.lists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntriesTableTableManager
    extends
        RootTableManager<
          _$CollectionDatabase,
          $EntriesTable,
          Entry,
          $$EntriesTableFilterComposer,
          $$EntriesTableOrderingComposer,
          $$EntriesTableAnnotationComposer,
          $$EntriesTableCreateCompanionBuilder,
          $$EntriesTableUpdateCompanionBuilder,
          (Entry, $$EntriesTableReferences),
          Entry,
          PrefetchHooks Function({bool listId})
        > {
  $$EntriesTableTableManager(_$CollectionDatabase db, $EntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> listId = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<int> finish = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<int> condition = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<String> snapName = const Value.absent(),
                Value<String> snapSetCode = const Value.absent(),
                Value<String> snapSetName = const Value.absent(),
                Value<String> snapCollector = const Value.absent(),
              }) => EntriesCompanion(
                id: id,
                listId: listId,
                cardId: cardId,
                finish: finish,
                language: language,
                condition: condition,
                quantity: quantity,
                addedAt: addedAt,
                snapName: snapName,
                snapSetCode: snapSetCode,
                snapSetName: snapSetName,
                snapCollector: snapCollector,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int listId,
                required String cardId,
                required int finish,
                required String language,
                required int condition,
                required int quantity,
                required int addedAt,
                required String snapName,
                required String snapSetCode,
                Value<String> snapSetName = const Value.absent(),
                required String snapCollector,
              }) => EntriesCompanion.insert(
                id: id,
                listId: listId,
                cardId: cardId,
                finish: finish,
                language: language,
                condition: condition,
                quantity: quantity,
                addedAt: addedAt,
                snapName: snapName,
                snapSetCode: snapSetCode,
                snapSetName: snapSetName,
                snapCollector: snapCollector,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({listId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (listId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.listId,
                                referencedTable: $$EntriesTableReferences
                                    ._listIdTable(db),
                                referencedColumn: $$EntriesTableReferences
                                    ._listIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$CollectionDatabase,
      $EntriesTable,
      Entry,
      $$EntriesTableFilterComposer,
      $$EntriesTableOrderingComposer,
      $$EntriesTableAnnotationComposer,
      $$EntriesTableCreateCompanionBuilder,
      $$EntriesTableUpdateCompanionBuilder,
      (Entry, $$EntriesTableReferences),
      Entry,
      PrefetchHooks Function({bool listId})
    >;
typedef $$ExternalAccountsTableCreateCompanionBuilder =
    ExternalAccountsCompanion Function({
      Value<int> id,
      required String provider,
      required String username,
      Value<bool> sessionValid,
      required int createdAt,
    });
typedef $$ExternalAccountsTableUpdateCompanionBuilder =
    ExternalAccountsCompanion Function({
      Value<int> id,
      Value<String> provider,
      Value<String> username,
      Value<bool> sessionValid,
      Value<int> createdAt,
    });

final class $$ExternalAccountsTableReferences
    extends
        BaseReferences<
          _$CollectionDatabase,
          $ExternalAccountsTable,
          ExternalAccount
        > {
  $$ExternalAccountsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ExternalListsTable, List<ExternalList>>
  _externalListsRefsTable(_$CollectionDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.externalLists,
        aliasName: 'external_accounts__id__external_lists__account_id',
      );

  $$ExternalListsTableProcessedTableManager get externalListsRefs {
    final manager = $$ExternalListsTableTableManager(
      $_db,
      $_db.externalLists,
    ).filter((f) => f.accountId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_externalListsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ExternalAccountsTableFilterComposer
    extends Composer<_$CollectionDatabase, $ExternalAccountsTable> {
  $$ExternalAccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get sessionValid => $composableBuilder(
    column: $table.sessionValid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> externalListsRefs(
    Expression<bool> Function($$ExternalListsTableFilterComposer f) f,
  ) {
    final $$ExternalListsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.externalLists,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalListsTableFilterComposer(
            $db: $db,
            $table: $db.externalLists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ExternalAccountsTableOrderingComposer
    extends Composer<_$CollectionDatabase, $ExternalAccountsTable> {
  $$ExternalAccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sessionValid => $composableBuilder(
    column: $table.sessionValid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExternalAccountsTableAnnotationComposer
    extends Composer<_$CollectionDatabase, $ExternalAccountsTable> {
  $$ExternalAccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<bool> get sessionValid => $composableBuilder(
    column: $table.sessionValid,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> externalListsRefs<T extends Object>(
    Expression<T> Function($$ExternalListsTableAnnotationComposer a) f,
  ) {
    final $$ExternalListsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.externalLists,
      getReferencedColumn: (t) => t.accountId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalListsTableAnnotationComposer(
            $db: $db,
            $table: $db.externalLists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ExternalAccountsTableTableManager
    extends
        RootTableManager<
          _$CollectionDatabase,
          $ExternalAccountsTable,
          ExternalAccount,
          $$ExternalAccountsTableFilterComposer,
          $$ExternalAccountsTableOrderingComposer,
          $$ExternalAccountsTableAnnotationComposer,
          $$ExternalAccountsTableCreateCompanionBuilder,
          $$ExternalAccountsTableUpdateCompanionBuilder,
          (ExternalAccount, $$ExternalAccountsTableReferences),
          ExternalAccount,
          PrefetchHooks Function({bool externalListsRefs})
        > {
  $$ExternalAccountsTableTableManager(
    _$CollectionDatabase db,
    $ExternalAccountsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExternalAccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExternalAccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExternalAccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<bool> sessionValid = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => ExternalAccountsCompanion(
                id: id,
                provider: provider,
                username: username,
                sessionValid: sessionValid,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String provider,
                required String username,
                Value<bool> sessionValid = const Value.absent(),
                required int createdAt,
              }) => ExternalAccountsCompanion.insert(
                id: id,
                provider: provider,
                username: username,
                sessionValid: sessionValid,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ExternalAccountsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({externalListsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (externalListsRefs) db.externalLists,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (externalListsRefs)
                    await $_getPrefetchedData<
                      ExternalAccount,
                      $ExternalAccountsTable,
                      ExternalList
                    >(
                      currentTable: table,
                      referencedTable: $$ExternalAccountsTableReferences
                          ._externalListsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ExternalAccountsTableReferences(
                            db,
                            table,
                            p0,
                          ).externalListsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.accountId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ExternalAccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$CollectionDatabase,
      $ExternalAccountsTable,
      ExternalAccount,
      $$ExternalAccountsTableFilterComposer,
      $$ExternalAccountsTableOrderingComposer,
      $$ExternalAccountsTableAnnotationComposer,
      $$ExternalAccountsTableCreateCompanionBuilder,
      $$ExternalAccountsTableUpdateCompanionBuilder,
      (ExternalAccount, $$ExternalAccountsTableReferences),
      ExternalAccount,
      PrefetchHooks Function({bool externalListsRefs})
    >;
typedef $$ExternalListsTableCreateCompanionBuilder =
    ExternalListsCompanion Function({
      Value<int> id,
      required int accountId,
      required int remoteId,
      required String kind,
      required String name,
      Value<int?> lastPulledAt,
      Value<bool> stale,
      Value<String?> lastPullError,
      Value<bool> anyPrinting,
    });
typedef $$ExternalListsTableUpdateCompanionBuilder =
    ExternalListsCompanion Function({
      Value<int> id,
      Value<int> accountId,
      Value<int> remoteId,
      Value<String> kind,
      Value<String> name,
      Value<int?> lastPulledAt,
      Value<bool> stale,
      Value<String?> lastPullError,
      Value<bool> anyPrinting,
    });

final class $$ExternalListsTableReferences
    extends
        BaseReferences<
          _$CollectionDatabase,
          $ExternalListsTable,
          ExternalList
        > {
  $$ExternalListsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ExternalAccountsTable _accountIdTable(_$CollectionDatabase db) => db
      .externalAccounts
      .createAlias('external_lists__account_id__external_accounts__id');

  $$ExternalAccountsTableProcessedTableManager get accountId {
    final $_column = $_itemColumn<int>('account_id')!;

    final manager = $$ExternalAccountsTableTableManager(
      $_db,
      $_db.externalAccounts,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_accountIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ExternalEntriesTable, List<ExternalEntry>>
  _externalEntriesRefsTable(_$CollectionDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.externalEntries,
        aliasName: 'external_lists__id__external_entries__list_id',
      );

  $$ExternalEntriesTableProcessedTableManager get externalEntriesRefs {
    final manager = $$ExternalEntriesTableTableManager(
      $_db,
      $_db.externalEntries,
    ).filter((f) => f.listId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _externalEntriesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ExternalListsTableFilterComposer
    extends Composer<_$CollectionDatabase, $ExternalListsTable> {
  $$ExternalListsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get stale => $composableBuilder(
    column: $table.stale,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastPullError => $composableBuilder(
    column: $table.lastPullError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get anyPrinting => $composableBuilder(
    column: $table.anyPrinting,
    builder: (column) => ColumnFilters(column),
  );

  $$ExternalAccountsTableFilterComposer get accountId {
    final $$ExternalAccountsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.externalAccounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalAccountsTableFilterComposer(
            $db: $db,
            $table: $db.externalAccounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> externalEntriesRefs(
    Expression<bool> Function($$ExternalEntriesTableFilterComposer f) f,
  ) {
    final $$ExternalEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.externalEntries,
      getReferencedColumn: (t) => t.listId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalEntriesTableFilterComposer(
            $db: $db,
            $table: $db.externalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ExternalListsTableOrderingComposer
    extends Composer<_$CollectionDatabase, $ExternalListsTable> {
  $$ExternalListsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get stale => $composableBuilder(
    column: $table.stale,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastPullError => $composableBuilder(
    column: $table.lastPullError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get anyPrinting => $composableBuilder(
    column: $table.anyPrinting,
    builder: (column) => ColumnOrderings(column),
  );

  $$ExternalAccountsTableOrderingComposer get accountId {
    final $$ExternalAccountsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.externalAccounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalAccountsTableOrderingComposer(
            $db: $db,
            $table: $db.externalAccounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExternalListsTableAnnotationComposer
    extends Composer<_$CollectionDatabase, $ExternalListsTable> {
  $$ExternalListsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get lastPulledAt => $composableBuilder(
    column: $table.lastPulledAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get stale =>
      $composableBuilder(column: $table.stale, builder: (column) => column);

  GeneratedColumn<String> get lastPullError => $composableBuilder(
    column: $table.lastPullError,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get anyPrinting => $composableBuilder(
    column: $table.anyPrinting,
    builder: (column) => column,
  );

  $$ExternalAccountsTableAnnotationComposer get accountId {
    final $$ExternalAccountsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.accountId,
      referencedTable: $db.externalAccounts,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalAccountsTableAnnotationComposer(
            $db: $db,
            $table: $db.externalAccounts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> externalEntriesRefs<T extends Object>(
    Expression<T> Function($$ExternalEntriesTableAnnotationComposer a) f,
  ) {
    final $$ExternalEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.externalEntries,
      getReferencedColumn: (t) => t.listId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.externalEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ExternalListsTableTableManager
    extends
        RootTableManager<
          _$CollectionDatabase,
          $ExternalListsTable,
          ExternalList,
          $$ExternalListsTableFilterComposer,
          $$ExternalListsTableOrderingComposer,
          $$ExternalListsTableAnnotationComposer,
          $$ExternalListsTableCreateCompanionBuilder,
          $$ExternalListsTableUpdateCompanionBuilder,
          (ExternalList, $$ExternalListsTableReferences),
          ExternalList,
          PrefetchHooks Function({bool accountId, bool externalEntriesRefs})
        > {
  $$ExternalListsTableTableManager(
    _$CollectionDatabase db,
    $ExternalListsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExternalListsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExternalListsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExternalListsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> accountId = const Value.absent(),
                Value<int> remoteId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> lastPulledAt = const Value.absent(),
                Value<bool> stale = const Value.absent(),
                Value<String?> lastPullError = const Value.absent(),
                Value<bool> anyPrinting = const Value.absent(),
              }) => ExternalListsCompanion(
                id: id,
                accountId: accountId,
                remoteId: remoteId,
                kind: kind,
                name: name,
                lastPulledAt: lastPulledAt,
                stale: stale,
                lastPullError: lastPullError,
                anyPrinting: anyPrinting,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int accountId,
                required int remoteId,
                required String kind,
                required String name,
                Value<int?> lastPulledAt = const Value.absent(),
                Value<bool> stale = const Value.absent(),
                Value<String?> lastPullError = const Value.absent(),
                Value<bool> anyPrinting = const Value.absent(),
              }) => ExternalListsCompanion.insert(
                id: id,
                accountId: accountId,
                remoteId: remoteId,
                kind: kind,
                name: name,
                lastPulledAt: lastPulledAt,
                stale: stale,
                lastPullError: lastPullError,
                anyPrinting: anyPrinting,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ExternalListsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({accountId = false, externalEntriesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (externalEntriesRefs) db.externalEntries,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (accountId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.accountId,
                                    referencedTable:
                                        $$ExternalListsTableReferences
                                            ._accountIdTable(db),
                                    referencedColumn:
                                        $$ExternalListsTableReferences
                                            ._accountIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (externalEntriesRefs)
                        await $_getPrefetchedData<
                          ExternalList,
                          $ExternalListsTable,
                          ExternalEntry
                        >(
                          currentTable: table,
                          referencedTable: $$ExternalListsTableReferences
                              ._externalEntriesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ExternalListsTableReferences(
                                db,
                                table,
                                p0,
                              ).externalEntriesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.listId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ExternalListsTableProcessedTableManager =
    ProcessedTableManager<
      _$CollectionDatabase,
      $ExternalListsTable,
      ExternalList,
      $$ExternalListsTableFilterComposer,
      $$ExternalListsTableOrderingComposer,
      $$ExternalListsTableAnnotationComposer,
      $$ExternalListsTableCreateCompanionBuilder,
      $$ExternalListsTableUpdateCompanionBuilder,
      (ExternalList, $$ExternalListsTableReferences),
      ExternalList,
      PrefetchHooks Function({bool accountId, bool externalEntriesRefs})
    >;
typedef $$ExternalEntriesTableCreateCompanionBuilder =
    ExternalEntriesCompanion Function({
      Value<int> id,
      required int listId,
      required int position,
      required int count,
      Value<int> tradeCount,
      required String printingId,
      required String condition,
      required String language,
      required String foil,
      required String rowFlags,
      required String identityKey,
      required String name,
      required String edition,
      required String editionCode,
      required String cardNumber,
      required String printingNote,
      Value<int?> lastUpdated,
      Value<String?> cardId,
      Value<String?> cardRef,
      required bool anyPrinting,
      Value<int?> finish,
      Value<String?> languageCode,
      Value<int?> conditionCode,
    });
typedef $$ExternalEntriesTableUpdateCompanionBuilder =
    ExternalEntriesCompanion Function({
      Value<int> id,
      Value<int> listId,
      Value<int> position,
      Value<int> count,
      Value<int> tradeCount,
      Value<String> printingId,
      Value<String> condition,
      Value<String> language,
      Value<String> foil,
      Value<String> rowFlags,
      Value<String> identityKey,
      Value<String> name,
      Value<String> edition,
      Value<String> editionCode,
      Value<String> cardNumber,
      Value<String> printingNote,
      Value<int?> lastUpdated,
      Value<String?> cardId,
      Value<String?> cardRef,
      Value<bool> anyPrinting,
      Value<int?> finish,
      Value<String?> languageCode,
      Value<int?> conditionCode,
    });

final class $$ExternalEntriesTableReferences
    extends
        BaseReferences<
          _$CollectionDatabase,
          $ExternalEntriesTable,
          ExternalEntry
        > {
  $$ExternalEntriesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ExternalListsTable _listIdTable(_$CollectionDatabase db) => db
      .externalLists
      .createAlias('external_entries__list_id__external_lists__id');

  $$ExternalListsTableProcessedTableManager get listId {
    final $_column = $_itemColumn<int>('list_id')!;

    final manager = $$ExternalListsTableTableManager(
      $_db,
      $_db.externalLists,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_listIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ExternalEntriesTableFilterComposer
    extends Composer<_$CollectionDatabase, $ExternalEntriesTable> {
  $$ExternalEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tradeCount => $composableBuilder(
    column: $table.tradeCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get printingId => $composableBuilder(
    column: $table.printingId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get condition => $composableBuilder(
    column: $table.condition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get foil => $composableBuilder(
    column: $table.foil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rowFlags => $composableBuilder(
    column: $table.rowFlags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get edition => $composableBuilder(
    column: $table.edition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get editionCode => $composableBuilder(
    column: $table.editionCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardNumber => $composableBuilder(
    column: $table.cardNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get printingNote => $composableBuilder(
    column: $table.printingNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardRef => $composableBuilder(
    column: $table.cardRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get anyPrinting => $composableBuilder(
    column: $table.anyPrinting,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finish => $composableBuilder(
    column: $table.finish,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get languageCode => $composableBuilder(
    column: $table.languageCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get conditionCode => $composableBuilder(
    column: $table.conditionCode,
    builder: (column) => ColumnFilters(column),
  );

  $$ExternalListsTableFilterComposer get listId {
    final $$ExternalListsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.listId,
      referencedTable: $db.externalLists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalListsTableFilterComposer(
            $db: $db,
            $table: $db.externalLists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExternalEntriesTableOrderingComposer
    extends Composer<_$CollectionDatabase, $ExternalEntriesTable> {
  $$ExternalEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tradeCount => $composableBuilder(
    column: $table.tradeCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get printingId => $composableBuilder(
    column: $table.printingId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get condition => $composableBuilder(
    column: $table.condition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get foil => $composableBuilder(
    column: $table.foil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rowFlags => $composableBuilder(
    column: $table.rowFlags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get edition => $composableBuilder(
    column: $table.edition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get editionCode => $composableBuilder(
    column: $table.editionCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardNumber => $composableBuilder(
    column: $table.cardNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get printingNote => $composableBuilder(
    column: $table.printingNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardRef => $composableBuilder(
    column: $table.cardRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get anyPrinting => $composableBuilder(
    column: $table.anyPrinting,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finish => $composableBuilder(
    column: $table.finish,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get languageCode => $composableBuilder(
    column: $table.languageCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get conditionCode => $composableBuilder(
    column: $table.conditionCode,
    builder: (column) => ColumnOrderings(column),
  );

  $$ExternalListsTableOrderingComposer get listId {
    final $$ExternalListsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.listId,
      referencedTable: $db.externalLists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalListsTableOrderingComposer(
            $db: $db,
            $table: $db.externalLists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExternalEntriesTableAnnotationComposer
    extends Composer<_$CollectionDatabase, $ExternalEntriesTable> {
  $$ExternalEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<int> get tradeCount => $composableBuilder(
    column: $table.tradeCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get printingId => $composableBuilder(
    column: $table.printingId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get condition =>
      $composableBuilder(column: $table.condition, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get foil =>
      $composableBuilder(column: $table.foil, builder: (column) => column);

  GeneratedColumn<String> get rowFlags =>
      $composableBuilder(column: $table.rowFlags, builder: (column) => column);

  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get edition =>
      $composableBuilder(column: $table.edition, builder: (column) => column);

  GeneratedColumn<String> get editionCode => $composableBuilder(
    column: $table.editionCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cardNumber => $composableBuilder(
    column: $table.cardNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get printingNote => $composableBuilder(
    column: $table.printingNote,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<String> get cardRef =>
      $composableBuilder(column: $table.cardRef, builder: (column) => column);

  GeneratedColumn<bool> get anyPrinting => $composableBuilder(
    column: $table.anyPrinting,
    builder: (column) => column,
  );

  GeneratedColumn<int> get finish =>
      $composableBuilder(column: $table.finish, builder: (column) => column);

  GeneratedColumn<String> get languageCode => $composableBuilder(
    column: $table.languageCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get conditionCode => $composableBuilder(
    column: $table.conditionCode,
    builder: (column) => column,
  );

  $$ExternalListsTableAnnotationComposer get listId {
    final $$ExternalListsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.listId,
      referencedTable: $db.externalLists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExternalListsTableAnnotationComposer(
            $db: $db,
            $table: $db.externalLists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExternalEntriesTableTableManager
    extends
        RootTableManager<
          _$CollectionDatabase,
          $ExternalEntriesTable,
          ExternalEntry,
          $$ExternalEntriesTableFilterComposer,
          $$ExternalEntriesTableOrderingComposer,
          $$ExternalEntriesTableAnnotationComposer,
          $$ExternalEntriesTableCreateCompanionBuilder,
          $$ExternalEntriesTableUpdateCompanionBuilder,
          (ExternalEntry, $$ExternalEntriesTableReferences),
          ExternalEntry,
          PrefetchHooks Function({bool listId})
        > {
  $$ExternalEntriesTableTableManager(
    _$CollectionDatabase db,
    $ExternalEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExternalEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExternalEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExternalEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> listId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<int> tradeCount = const Value.absent(),
                Value<String> printingId = const Value.absent(),
                Value<String> condition = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<String> foil = const Value.absent(),
                Value<String> rowFlags = const Value.absent(),
                Value<String> identityKey = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> edition = const Value.absent(),
                Value<String> editionCode = const Value.absent(),
                Value<String> cardNumber = const Value.absent(),
                Value<String> printingNote = const Value.absent(),
                Value<int?> lastUpdated = const Value.absent(),
                Value<String?> cardId = const Value.absent(),
                Value<String?> cardRef = const Value.absent(),
                Value<bool> anyPrinting = const Value.absent(),
                Value<int?> finish = const Value.absent(),
                Value<String?> languageCode = const Value.absent(),
                Value<int?> conditionCode = const Value.absent(),
              }) => ExternalEntriesCompanion(
                id: id,
                listId: listId,
                position: position,
                count: count,
                tradeCount: tradeCount,
                printingId: printingId,
                condition: condition,
                language: language,
                foil: foil,
                rowFlags: rowFlags,
                identityKey: identityKey,
                name: name,
                edition: edition,
                editionCode: editionCode,
                cardNumber: cardNumber,
                printingNote: printingNote,
                lastUpdated: lastUpdated,
                cardId: cardId,
                cardRef: cardRef,
                anyPrinting: anyPrinting,
                finish: finish,
                languageCode: languageCode,
                conditionCode: conditionCode,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int listId,
                required int position,
                required int count,
                Value<int> tradeCount = const Value.absent(),
                required String printingId,
                required String condition,
                required String language,
                required String foil,
                required String rowFlags,
                required String identityKey,
                required String name,
                required String edition,
                required String editionCode,
                required String cardNumber,
                required String printingNote,
                Value<int?> lastUpdated = const Value.absent(),
                Value<String?> cardId = const Value.absent(),
                Value<String?> cardRef = const Value.absent(),
                required bool anyPrinting,
                Value<int?> finish = const Value.absent(),
                Value<String?> languageCode = const Value.absent(),
                Value<int?> conditionCode = const Value.absent(),
              }) => ExternalEntriesCompanion.insert(
                id: id,
                listId: listId,
                position: position,
                count: count,
                tradeCount: tradeCount,
                printingId: printingId,
                condition: condition,
                language: language,
                foil: foil,
                rowFlags: rowFlags,
                identityKey: identityKey,
                name: name,
                edition: edition,
                editionCode: editionCode,
                cardNumber: cardNumber,
                printingNote: printingNote,
                lastUpdated: lastUpdated,
                cardId: cardId,
                cardRef: cardRef,
                anyPrinting: anyPrinting,
                finish: finish,
                languageCode: languageCode,
                conditionCode: conditionCode,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ExternalEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({listId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (listId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.listId,
                                referencedTable:
                                    $$ExternalEntriesTableReferences
                                        ._listIdTable(db),
                                referencedColumn:
                                    $$ExternalEntriesTableReferences
                                        ._listIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ExternalEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$CollectionDatabase,
      $ExternalEntriesTable,
      ExternalEntry,
      $$ExternalEntriesTableFilterComposer,
      $$ExternalEntriesTableOrderingComposer,
      $$ExternalEntriesTableAnnotationComposer,
      $$ExternalEntriesTableCreateCompanionBuilder,
      $$ExternalEntriesTableUpdateCompanionBuilder,
      (ExternalEntry, $$ExternalEntriesTableReferences),
      ExternalEntry,
      PrefetchHooks Function({bool listId})
    >;

class $CollectionDatabaseManager {
  final _$CollectionDatabase _db;
  $CollectionDatabaseManager(this._db);
  $$ListsTableTableManager get lists =>
      $$ListsTableTableManager(_db, _db.lists);
  $$EntriesTableTableManager get entries =>
      $$EntriesTableTableManager(_db, _db.entries);
  $$ExternalAccountsTableTableManager get externalAccounts =>
      $$ExternalAccountsTableTableManager(_db, _db.externalAccounts);
  $$ExternalListsTableTableManager get externalLists =>
      $$ExternalListsTableTableManager(_db, _db.externalLists);
  $$ExternalEntriesTableTableManager get externalEntries =>
      $$ExternalEntriesTableTableManager(_db, _db.externalEntries);
}
