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
          ..write('snapCollector: $snapCollector')
          ..write(')'))
        .toString();
  }
}

abstract class _$CollectionDatabase extends GeneratedDatabase {
  _$CollectionDatabase(QueryExecutor e) : super(e);
  $CollectionDatabaseManager get managers => $CollectionDatabaseManager(this);
  late final $ListsTable lists = $ListsTable(this);
  late final $EntriesTable entries = $EntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [lists, entries];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'lists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('entries', kind: UpdateKind.delete)],
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

class $CollectionDatabaseManager {
  final _$CollectionDatabase _db;
  $CollectionDatabaseManager(this._db);
  $$ListsTableTableManager get lists =>
      $$ListsTableTableManager(_db, _db.lists);
  $$EntriesTableTableManager get entries =>
      $$EntriesTableTableManager(_db, _db.entries);
}
