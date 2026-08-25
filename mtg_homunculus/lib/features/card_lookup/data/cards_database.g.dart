// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cards_database.dart';

// ignore_for_file: type=lint
class $MetaTable extends Meta with TableInfo<$MetaTable, MetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  MetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetaData(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $MetaTable createAlias(String alias) {
    return $MetaTable(attachedDatabase, alias);
  }
}

class MetaData extends DataClass implements Insertable<MetaData> {
  final String key;
  final String value;
  const MetaData({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  MetaCompanion toCompanion(bool nullToAbsent) {
    return MetaCompanion(key: Value(key), value: Value(value));
  }

  factory MetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetaData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  MetaData copyWith({String? key, String? value}) =>
      MetaData(key: key ?? this.key, value: value ?? this.value);
  MetaData copyWithCompanion(MetaCompanion data) {
    return MetaData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetaData(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaData && other.key == this.key && other.value == this.value);
}

class MetaCompanion extends UpdateCompanion<MetaData> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const MetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<MetaData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return MetaCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SetsTable extends Sets with TableInfo<$SetsTable, CardSet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
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
  static const VerificationMeta _releasedAtMeta = const VerificationMeta(
    'releasedAt',
  );
  @override
  late final GeneratedColumn<int> releasedAt = GeneratedColumn<int>(
    'released_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _setTypeMeta = const VerificationMeta(
    'setType',
  );
  @override
  late final GeneratedColumn<String> setType = GeneratedColumn<String>(
    'set_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [code, name, releasedAt, setType];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sets';
  @override
  VerificationContext validateIntegrity(
    Insertable<CardSet> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('released_at')) {
      context.handle(
        _releasedAtMeta,
        releasedAt.isAcceptableOrUnknown(data['released_at']!, _releasedAtMeta),
      );
    }
    if (data.containsKey('set_type')) {
      context.handle(
        _setTypeMeta,
        setType.isAcceptableOrUnknown(data['set_type']!, _setTypeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  CardSet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardSet(
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      releasedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}released_at'],
      ),
      setType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}set_type'],
      ),
    );
  }

  @override
  $SetsTable createAlias(String alias) {
    return $SetsTable(attachedDatabase, alias);
  }
}

class CardSet extends DataClass implements Insertable<CardSet> {
  /// Scryfall set code, lowercase: `xln`, `lci`.
  final String code;
  final String name;

  /// Unix seconds. Null when Scryfall has no release date.
  final int? releasedAt;
  final String? setType;
  const CardSet({
    required this.code,
    required this.name,
    this.releasedAt,
    this.setType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || releasedAt != null) {
      map['released_at'] = Variable<int>(releasedAt);
    }
    if (!nullToAbsent || setType != null) {
      map['set_type'] = Variable<String>(setType);
    }
    return map;
  }

  SetsCompanion toCompanion(bool nullToAbsent) {
    return SetsCompanion(
      code: Value(code),
      name: Value(name),
      releasedAt: releasedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(releasedAt),
      setType: setType == null && nullToAbsent
          ? const Value.absent()
          : Value(setType),
    );
  }

  factory CardSet.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardSet(
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      releasedAt: serializer.fromJson<int?>(json['releasedAt']),
      setType: serializer.fromJson<String?>(json['setType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'releasedAt': serializer.toJson<int?>(releasedAt),
      'setType': serializer.toJson<String?>(setType),
    };
  }

  CardSet copyWith({
    String? code,
    String? name,
    Value<int?> releasedAt = const Value.absent(),
    Value<String?> setType = const Value.absent(),
  }) => CardSet(
    code: code ?? this.code,
    name: name ?? this.name,
    releasedAt: releasedAt.present ? releasedAt.value : this.releasedAt,
    setType: setType.present ? setType.value : this.setType,
  );
  CardSet copyWithCompanion(SetsCompanion data) {
    return CardSet(
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      releasedAt: data.releasedAt.present
          ? data.releasedAt.value
          : this.releasedAt,
      setType: data.setType.present ? data.setType.value : this.setType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardSet(')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('releasedAt: $releasedAt, ')
          ..write('setType: $setType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(code, name, releasedAt, setType);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardSet &&
          other.code == this.code &&
          other.name == this.name &&
          other.releasedAt == this.releasedAt &&
          other.setType == this.setType);
}

class SetsCompanion extends UpdateCompanion<CardSet> {
  final Value<String> code;
  final Value<String> name;
  final Value<int?> releasedAt;
  final Value<String?> setType;
  final Value<int> rowid;
  const SetsCompanion({
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.releasedAt = const Value.absent(),
    this.setType = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SetsCompanion.insert({
    required String code,
    required String name,
    this.releasedAt = const Value.absent(),
    this.setType = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : code = Value(code),
       name = Value(name);
  static Insertable<CardSet> custom({
    Expression<String>? code,
    Expression<String>? name,
    Expression<int>? releasedAt,
    Expression<String>? setType,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (releasedAt != null) 'released_at': releasedAt,
      if (setType != null) 'set_type': setType,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SetsCompanion copyWith({
    Value<String>? code,
    Value<String>? name,
    Value<int?>? releasedAt,
    Value<String?>? setType,
    Value<int>? rowid,
  }) {
    return SetsCompanion(
      code: code ?? this.code,
      name: name ?? this.name,
      releasedAt: releasedAt ?? this.releasedAt,
      setType: setType ?? this.setType,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (releasedAt.present) {
      map['released_at'] = Variable<int>(releasedAt.value);
    }
    if (setType.present) {
      map['set_type'] = Variable<String>(setType.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SetsCompanion(')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('releasedAt: $releasedAt, ')
          ..write('setType: $setType, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardsTable extends Cards with TableInfo<$CardsTable, Card> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _oracleIdMeta = const VerificationMeta(
    'oracleId',
  );
  @override
  late final GeneratedColumn<String> oracleId = GeneratedColumn<String>(
    'oracle_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _illustrationIdMeta = const VerificationMeta(
    'illustrationId',
  );
  @override
  late final GeneratedColumn<String> illustrationId = GeneratedColumn<String>(
    'illustration_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _setCodeMeta = const VerificationMeta(
    'setCode',
  );
  @override
  late final GeneratedColumn<String> setCode = GeneratedColumn<String>(
    'set_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sets (code)',
    ),
  );
  static const VerificationMeta _collectorNumberMeta = const VerificationMeta(
    'collectorNumber',
  );
  @override
  late final GeneratedColumn<String> collectorNumber = GeneratedColumn<String>(
    'collector_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _langMeta = const VerificationMeta('lang');
  @override
  late final GeneratedColumn<String> lang = GeneratedColumn<String>(
    'lang',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('en'),
  );
  static const VerificationMeta _rarityMeta = const VerificationMeta('rarity');
  @override
  late final GeneratedColumn<int> rarity = GeneratedColumn<int>(
    'rarity',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _releasedAtMeta = const VerificationMeta(
    'releasedAt',
  );
  @override
  late final GeneratedColumn<int> releasedAt = GeneratedColumn<int>(
    'released_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cmcMeta = const VerificationMeta('cmc');
  @override
  late final GeneratedColumn<double> cmc = GeneratedColumn<double>(
    'cmc',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorsMeta = const VerificationMeta('colors');
  @override
  late final GeneratedColumn<String> colors = GeneratedColumn<String>(
    'colors',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorIdentityMeta = const VerificationMeta(
    'colorIdentity',
  );
  @override
  late final GeneratedColumn<String> colorIdentity = GeneratedColumn<String>(
    'color_identity',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _watermarkMeta = const VerificationMeta(
    'watermark',
  );
  @override
  late final GeneratedColumn<String> watermark = GeneratedColumn<String>(
    'watermark',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _layoutMeta = const VerificationMeta('layout');
  @override
  late final GeneratedColumn<String> layout = GeneratedColumn<String>(
    'layout',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fullArtMeta = const VerificationMeta(
    'fullArt',
  );
  @override
  late final GeneratedColumn<bool> fullArt = GeneratedColumn<bool>(
    'full_art',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("full_art" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hasBackMeta = const VerificationMeta(
    'hasBack',
  );
  @override
  late final GeneratedColumn<bool> hasBack = GeneratedColumn<bool>(
    'has_back',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_back" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _imageUpdatedAtMeta = const VerificationMeta(
    'imageUpdatedAt',
  );
  @override
  late final GeneratedColumn<int> imageUpdatedAt = GeneratedColumn<int>(
    'image_updated_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageStatusMeta = const VerificationMeta(
    'imageStatus',
  );
  @override
  late final GeneratedColumn<int> imageStatus = GeneratedColumn<int>(
    'image_status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _finishesMeta = const VerificationMeta(
    'finishes',
  );
  @override
  late final GeneratedColumn<int> finishes = GeneratedColumn<int>(
    'finishes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    oracleId,
    illustrationId,
    name,
    setCode,
    collectorNumber,
    lang,
    rarity,
    releasedAt,
    cmc,
    colors,
    colorIdentity,
    watermark,
    layout,
    fullArt,
    hasBack,
    imageUpdatedAt,
    imageStatus,
    finishes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<Card> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('oracle_id')) {
      context.handle(
        _oracleIdMeta,
        oracleId.isAcceptableOrUnknown(data['oracle_id']!, _oracleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_oracleIdMeta);
    }
    if (data.containsKey('illustration_id')) {
      context.handle(
        _illustrationIdMeta,
        illustrationId.isAcceptableOrUnknown(
          data['illustration_id']!,
          _illustrationIdMeta,
        ),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('set_code')) {
      context.handle(
        _setCodeMeta,
        setCode.isAcceptableOrUnknown(data['set_code']!, _setCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_setCodeMeta);
    }
    if (data.containsKey('collector_number')) {
      context.handle(
        _collectorNumberMeta,
        collectorNumber.isAcceptableOrUnknown(
          data['collector_number']!,
          _collectorNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectorNumberMeta);
    }
    if (data.containsKey('lang')) {
      context.handle(
        _langMeta,
        lang.isAcceptableOrUnknown(data['lang']!, _langMeta),
      );
    }
    if (data.containsKey('rarity')) {
      context.handle(
        _rarityMeta,
        rarity.isAcceptableOrUnknown(data['rarity']!, _rarityMeta),
      );
    }
    if (data.containsKey('released_at')) {
      context.handle(
        _releasedAtMeta,
        releasedAt.isAcceptableOrUnknown(data['released_at']!, _releasedAtMeta),
      );
    }
    if (data.containsKey('cmc')) {
      context.handle(
        _cmcMeta,
        cmc.isAcceptableOrUnknown(data['cmc']!, _cmcMeta),
      );
    }
    if (data.containsKey('colors')) {
      context.handle(
        _colorsMeta,
        colors.isAcceptableOrUnknown(data['colors']!, _colorsMeta),
      );
    }
    if (data.containsKey('color_identity')) {
      context.handle(
        _colorIdentityMeta,
        colorIdentity.isAcceptableOrUnknown(
          data['color_identity']!,
          _colorIdentityMeta,
        ),
      );
    }
    if (data.containsKey('watermark')) {
      context.handle(
        _watermarkMeta,
        watermark.isAcceptableOrUnknown(data['watermark']!, _watermarkMeta),
      );
    }
    if (data.containsKey('layout')) {
      context.handle(
        _layoutMeta,
        layout.isAcceptableOrUnknown(data['layout']!, _layoutMeta),
      );
    }
    if (data.containsKey('full_art')) {
      context.handle(
        _fullArtMeta,
        fullArt.isAcceptableOrUnknown(data['full_art']!, _fullArtMeta),
      );
    }
    if (data.containsKey('has_back')) {
      context.handle(
        _hasBackMeta,
        hasBack.isAcceptableOrUnknown(data['has_back']!, _hasBackMeta),
      );
    }
    if (data.containsKey('image_updated_at')) {
      context.handle(
        _imageUpdatedAtMeta,
        imageUpdatedAt.isAcceptableOrUnknown(
          data['image_updated_at']!,
          _imageUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('image_status')) {
      context.handle(
        _imageStatusMeta,
        imageStatus.isAcceptableOrUnknown(
          data['image_status']!,
          _imageStatusMeta,
        ),
      );
    }
    if (data.containsKey('finishes')) {
      context.handle(
        _finishesMeta,
        finishes.isAcceptableOrUnknown(data['finishes']!, _finishesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Card map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Card(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      oracleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}oracle_id'],
      )!,
      illustrationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}illustration_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      setCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}set_code'],
      )!,
      collectorNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collector_number'],
      )!,
      lang: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lang'],
      )!,
      rarity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rarity'],
      ),
      releasedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}released_at'],
      ),
      cmc: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cmc'],
      ),
      colors: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}colors'],
      ),
      colorIdentity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_identity'],
      ),
      watermark: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}watermark'],
      ),
      layout: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}layout'],
      ),
      fullArt: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}full_art'],
      )!,
      hasBack: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_back'],
      )!,
      imageUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}image_updated_at'],
      ),
      imageStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}image_status'],
      )!,
      finishes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}finishes'],
      )!,
    );
  }

  @override
  $CardsTable createAlias(String alias) {
    return $CardsTable(attachedDatabase, alias);
  }
}

class Card extends DataClass implements Insertable<Card> {
  final String id;
  final String oracleId;
  final String? illustrationId;
  final String name;
  final String setCode;
  final String collectorNumber;
  final String lang;
  final int? rarity;
  final int? releasedAt;
  final double? cmc;
  final String? colors;
  final String? colorIdentity;
  final String? watermark;
  final String? layout;
  final bool fullArt;
  final bool hasBack;

  /// Unix seconds — the image cache-buster. Image URLs are derived, never stored.
  final int? imageUpdatedAt;

  /// 0 missing · 1 placeholder · 2 lowres · 3 highres_scan.
  final int imageStatus;

  /// Bitmask: 1 nonfoil · 2 foil · 4 etched.
  final int finishes;
  const Card({
    required this.id,
    required this.oracleId,
    this.illustrationId,
    required this.name,
    required this.setCode,
    required this.collectorNumber,
    required this.lang,
    this.rarity,
    this.releasedAt,
    this.cmc,
    this.colors,
    this.colorIdentity,
    this.watermark,
    this.layout,
    required this.fullArt,
    required this.hasBack,
    this.imageUpdatedAt,
    required this.imageStatus,
    required this.finishes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['oracle_id'] = Variable<String>(oracleId);
    if (!nullToAbsent || illustrationId != null) {
      map['illustration_id'] = Variable<String>(illustrationId);
    }
    map['name'] = Variable<String>(name);
    map['set_code'] = Variable<String>(setCode);
    map['collector_number'] = Variable<String>(collectorNumber);
    map['lang'] = Variable<String>(lang);
    if (!nullToAbsent || rarity != null) {
      map['rarity'] = Variable<int>(rarity);
    }
    if (!nullToAbsent || releasedAt != null) {
      map['released_at'] = Variable<int>(releasedAt);
    }
    if (!nullToAbsent || cmc != null) {
      map['cmc'] = Variable<double>(cmc);
    }
    if (!nullToAbsent || colors != null) {
      map['colors'] = Variable<String>(colors);
    }
    if (!nullToAbsent || colorIdentity != null) {
      map['color_identity'] = Variable<String>(colorIdentity);
    }
    if (!nullToAbsent || watermark != null) {
      map['watermark'] = Variable<String>(watermark);
    }
    if (!nullToAbsent || layout != null) {
      map['layout'] = Variable<String>(layout);
    }
    map['full_art'] = Variable<bool>(fullArt);
    map['has_back'] = Variable<bool>(hasBack);
    if (!nullToAbsent || imageUpdatedAt != null) {
      map['image_updated_at'] = Variable<int>(imageUpdatedAt);
    }
    map['image_status'] = Variable<int>(imageStatus);
    map['finishes'] = Variable<int>(finishes);
    return map;
  }

  CardsCompanion toCompanion(bool nullToAbsent) {
    return CardsCompanion(
      id: Value(id),
      oracleId: Value(oracleId),
      illustrationId: illustrationId == null && nullToAbsent
          ? const Value.absent()
          : Value(illustrationId),
      name: Value(name),
      setCode: Value(setCode),
      collectorNumber: Value(collectorNumber),
      lang: Value(lang),
      rarity: rarity == null && nullToAbsent
          ? const Value.absent()
          : Value(rarity),
      releasedAt: releasedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(releasedAt),
      cmc: cmc == null && nullToAbsent ? const Value.absent() : Value(cmc),
      colors: colors == null && nullToAbsent
          ? const Value.absent()
          : Value(colors),
      colorIdentity: colorIdentity == null && nullToAbsent
          ? const Value.absent()
          : Value(colorIdentity),
      watermark: watermark == null && nullToAbsent
          ? const Value.absent()
          : Value(watermark),
      layout: layout == null && nullToAbsent
          ? const Value.absent()
          : Value(layout),
      fullArt: Value(fullArt),
      hasBack: Value(hasBack),
      imageUpdatedAt: imageUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUpdatedAt),
      imageStatus: Value(imageStatus),
      finishes: Value(finishes),
    );
  }

  factory Card.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Card(
      id: serializer.fromJson<String>(json['id']),
      oracleId: serializer.fromJson<String>(json['oracleId']),
      illustrationId: serializer.fromJson<String?>(json['illustrationId']),
      name: serializer.fromJson<String>(json['name']),
      setCode: serializer.fromJson<String>(json['setCode']),
      collectorNumber: serializer.fromJson<String>(json['collectorNumber']),
      lang: serializer.fromJson<String>(json['lang']),
      rarity: serializer.fromJson<int?>(json['rarity']),
      releasedAt: serializer.fromJson<int?>(json['releasedAt']),
      cmc: serializer.fromJson<double?>(json['cmc']),
      colors: serializer.fromJson<String?>(json['colors']),
      colorIdentity: serializer.fromJson<String?>(json['colorIdentity']),
      watermark: serializer.fromJson<String?>(json['watermark']),
      layout: serializer.fromJson<String?>(json['layout']),
      fullArt: serializer.fromJson<bool>(json['fullArt']),
      hasBack: serializer.fromJson<bool>(json['hasBack']),
      imageUpdatedAt: serializer.fromJson<int?>(json['imageUpdatedAt']),
      imageStatus: serializer.fromJson<int>(json['imageStatus']),
      finishes: serializer.fromJson<int>(json['finishes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'oracleId': serializer.toJson<String>(oracleId),
      'illustrationId': serializer.toJson<String?>(illustrationId),
      'name': serializer.toJson<String>(name),
      'setCode': serializer.toJson<String>(setCode),
      'collectorNumber': serializer.toJson<String>(collectorNumber),
      'lang': serializer.toJson<String>(lang),
      'rarity': serializer.toJson<int?>(rarity),
      'releasedAt': serializer.toJson<int?>(releasedAt),
      'cmc': serializer.toJson<double?>(cmc),
      'colors': serializer.toJson<String?>(colors),
      'colorIdentity': serializer.toJson<String?>(colorIdentity),
      'watermark': serializer.toJson<String?>(watermark),
      'layout': serializer.toJson<String?>(layout),
      'fullArt': serializer.toJson<bool>(fullArt),
      'hasBack': serializer.toJson<bool>(hasBack),
      'imageUpdatedAt': serializer.toJson<int?>(imageUpdatedAt),
      'imageStatus': serializer.toJson<int>(imageStatus),
      'finishes': serializer.toJson<int>(finishes),
    };
  }

  Card copyWith({
    String? id,
    String? oracleId,
    Value<String?> illustrationId = const Value.absent(),
    String? name,
    String? setCode,
    String? collectorNumber,
    String? lang,
    Value<int?> rarity = const Value.absent(),
    Value<int?> releasedAt = const Value.absent(),
    Value<double?> cmc = const Value.absent(),
    Value<String?> colors = const Value.absent(),
    Value<String?> colorIdentity = const Value.absent(),
    Value<String?> watermark = const Value.absent(),
    Value<String?> layout = const Value.absent(),
    bool? fullArt,
    bool? hasBack,
    Value<int?> imageUpdatedAt = const Value.absent(),
    int? imageStatus,
    int? finishes,
  }) => Card(
    id: id ?? this.id,
    oracleId: oracleId ?? this.oracleId,
    illustrationId: illustrationId.present
        ? illustrationId.value
        : this.illustrationId,
    name: name ?? this.name,
    setCode: setCode ?? this.setCode,
    collectorNumber: collectorNumber ?? this.collectorNumber,
    lang: lang ?? this.lang,
    rarity: rarity.present ? rarity.value : this.rarity,
    releasedAt: releasedAt.present ? releasedAt.value : this.releasedAt,
    cmc: cmc.present ? cmc.value : this.cmc,
    colors: colors.present ? colors.value : this.colors,
    colorIdentity: colorIdentity.present
        ? colorIdentity.value
        : this.colorIdentity,
    watermark: watermark.present ? watermark.value : this.watermark,
    layout: layout.present ? layout.value : this.layout,
    fullArt: fullArt ?? this.fullArt,
    hasBack: hasBack ?? this.hasBack,
    imageUpdatedAt: imageUpdatedAt.present
        ? imageUpdatedAt.value
        : this.imageUpdatedAt,
    imageStatus: imageStatus ?? this.imageStatus,
    finishes: finishes ?? this.finishes,
  );
  Card copyWithCompanion(CardsCompanion data) {
    return Card(
      id: data.id.present ? data.id.value : this.id,
      oracleId: data.oracleId.present ? data.oracleId.value : this.oracleId,
      illustrationId: data.illustrationId.present
          ? data.illustrationId.value
          : this.illustrationId,
      name: data.name.present ? data.name.value : this.name,
      setCode: data.setCode.present ? data.setCode.value : this.setCode,
      collectorNumber: data.collectorNumber.present
          ? data.collectorNumber.value
          : this.collectorNumber,
      lang: data.lang.present ? data.lang.value : this.lang,
      rarity: data.rarity.present ? data.rarity.value : this.rarity,
      releasedAt: data.releasedAt.present
          ? data.releasedAt.value
          : this.releasedAt,
      cmc: data.cmc.present ? data.cmc.value : this.cmc,
      colors: data.colors.present ? data.colors.value : this.colors,
      colorIdentity: data.colorIdentity.present
          ? data.colorIdentity.value
          : this.colorIdentity,
      watermark: data.watermark.present ? data.watermark.value : this.watermark,
      layout: data.layout.present ? data.layout.value : this.layout,
      fullArt: data.fullArt.present ? data.fullArt.value : this.fullArt,
      hasBack: data.hasBack.present ? data.hasBack.value : this.hasBack,
      imageUpdatedAt: data.imageUpdatedAt.present
          ? data.imageUpdatedAt.value
          : this.imageUpdatedAt,
      imageStatus: data.imageStatus.present
          ? data.imageStatus.value
          : this.imageStatus,
      finishes: data.finishes.present ? data.finishes.value : this.finishes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Card(')
          ..write('id: $id, ')
          ..write('oracleId: $oracleId, ')
          ..write('illustrationId: $illustrationId, ')
          ..write('name: $name, ')
          ..write('setCode: $setCode, ')
          ..write('collectorNumber: $collectorNumber, ')
          ..write('lang: $lang, ')
          ..write('rarity: $rarity, ')
          ..write('releasedAt: $releasedAt, ')
          ..write('cmc: $cmc, ')
          ..write('colors: $colors, ')
          ..write('colorIdentity: $colorIdentity, ')
          ..write('watermark: $watermark, ')
          ..write('layout: $layout, ')
          ..write('fullArt: $fullArt, ')
          ..write('hasBack: $hasBack, ')
          ..write('imageUpdatedAt: $imageUpdatedAt, ')
          ..write('imageStatus: $imageStatus, ')
          ..write('finishes: $finishes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    oracleId,
    illustrationId,
    name,
    setCode,
    collectorNumber,
    lang,
    rarity,
    releasedAt,
    cmc,
    colors,
    colorIdentity,
    watermark,
    layout,
    fullArt,
    hasBack,
    imageUpdatedAt,
    imageStatus,
    finishes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Card &&
          other.id == this.id &&
          other.oracleId == this.oracleId &&
          other.illustrationId == this.illustrationId &&
          other.name == this.name &&
          other.setCode == this.setCode &&
          other.collectorNumber == this.collectorNumber &&
          other.lang == this.lang &&
          other.rarity == this.rarity &&
          other.releasedAt == this.releasedAt &&
          other.cmc == this.cmc &&
          other.colors == this.colors &&
          other.colorIdentity == this.colorIdentity &&
          other.watermark == this.watermark &&
          other.layout == this.layout &&
          other.fullArt == this.fullArt &&
          other.hasBack == this.hasBack &&
          other.imageUpdatedAt == this.imageUpdatedAt &&
          other.imageStatus == this.imageStatus &&
          other.finishes == this.finishes);
}

class CardsCompanion extends UpdateCompanion<Card> {
  final Value<String> id;
  final Value<String> oracleId;
  final Value<String?> illustrationId;
  final Value<String> name;
  final Value<String> setCode;
  final Value<String> collectorNumber;
  final Value<String> lang;
  final Value<int?> rarity;
  final Value<int?> releasedAt;
  final Value<double?> cmc;
  final Value<String?> colors;
  final Value<String?> colorIdentity;
  final Value<String?> watermark;
  final Value<String?> layout;
  final Value<bool> fullArt;
  final Value<bool> hasBack;
  final Value<int?> imageUpdatedAt;
  final Value<int> imageStatus;
  final Value<int> finishes;
  final Value<int> rowid;
  const CardsCompanion({
    this.id = const Value.absent(),
    this.oracleId = const Value.absent(),
    this.illustrationId = const Value.absent(),
    this.name = const Value.absent(),
    this.setCode = const Value.absent(),
    this.collectorNumber = const Value.absent(),
    this.lang = const Value.absent(),
    this.rarity = const Value.absent(),
    this.releasedAt = const Value.absent(),
    this.cmc = const Value.absent(),
    this.colors = const Value.absent(),
    this.colorIdentity = const Value.absent(),
    this.watermark = const Value.absent(),
    this.layout = const Value.absent(),
    this.fullArt = const Value.absent(),
    this.hasBack = const Value.absent(),
    this.imageUpdatedAt = const Value.absent(),
    this.imageStatus = const Value.absent(),
    this.finishes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardsCompanion.insert({
    required String id,
    required String oracleId,
    this.illustrationId = const Value.absent(),
    required String name,
    required String setCode,
    required String collectorNumber,
    this.lang = const Value.absent(),
    this.rarity = const Value.absent(),
    this.releasedAt = const Value.absent(),
    this.cmc = const Value.absent(),
    this.colors = const Value.absent(),
    this.colorIdentity = const Value.absent(),
    this.watermark = const Value.absent(),
    this.layout = const Value.absent(),
    this.fullArt = const Value.absent(),
    this.hasBack = const Value.absent(),
    this.imageUpdatedAt = const Value.absent(),
    this.imageStatus = const Value.absent(),
    this.finishes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       oracleId = Value(oracleId),
       name = Value(name),
       setCode = Value(setCode),
       collectorNumber = Value(collectorNumber);
  static Insertable<Card> custom({
    Expression<String>? id,
    Expression<String>? oracleId,
    Expression<String>? illustrationId,
    Expression<String>? name,
    Expression<String>? setCode,
    Expression<String>? collectorNumber,
    Expression<String>? lang,
    Expression<int>? rarity,
    Expression<int>? releasedAt,
    Expression<double>? cmc,
    Expression<String>? colors,
    Expression<String>? colorIdentity,
    Expression<String>? watermark,
    Expression<String>? layout,
    Expression<bool>? fullArt,
    Expression<bool>? hasBack,
    Expression<int>? imageUpdatedAt,
    Expression<int>? imageStatus,
    Expression<int>? finishes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (oracleId != null) 'oracle_id': oracleId,
      if (illustrationId != null) 'illustration_id': illustrationId,
      if (name != null) 'name': name,
      if (setCode != null) 'set_code': setCode,
      if (collectorNumber != null) 'collector_number': collectorNumber,
      if (lang != null) 'lang': lang,
      if (rarity != null) 'rarity': rarity,
      if (releasedAt != null) 'released_at': releasedAt,
      if (cmc != null) 'cmc': cmc,
      if (colors != null) 'colors': colors,
      if (colorIdentity != null) 'color_identity': colorIdentity,
      if (watermark != null) 'watermark': watermark,
      if (layout != null) 'layout': layout,
      if (fullArt != null) 'full_art': fullArt,
      if (hasBack != null) 'has_back': hasBack,
      if (imageUpdatedAt != null) 'image_updated_at': imageUpdatedAt,
      if (imageStatus != null) 'image_status': imageStatus,
      if (finishes != null) 'finishes': finishes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardsCompanion copyWith({
    Value<String>? id,
    Value<String>? oracleId,
    Value<String?>? illustrationId,
    Value<String>? name,
    Value<String>? setCode,
    Value<String>? collectorNumber,
    Value<String>? lang,
    Value<int?>? rarity,
    Value<int?>? releasedAt,
    Value<double?>? cmc,
    Value<String?>? colors,
    Value<String?>? colorIdentity,
    Value<String?>? watermark,
    Value<String?>? layout,
    Value<bool>? fullArt,
    Value<bool>? hasBack,
    Value<int?>? imageUpdatedAt,
    Value<int>? imageStatus,
    Value<int>? finishes,
    Value<int>? rowid,
  }) {
    return CardsCompanion(
      id: id ?? this.id,
      oracleId: oracleId ?? this.oracleId,
      illustrationId: illustrationId ?? this.illustrationId,
      name: name ?? this.name,
      setCode: setCode ?? this.setCode,
      collectorNumber: collectorNumber ?? this.collectorNumber,
      lang: lang ?? this.lang,
      rarity: rarity ?? this.rarity,
      releasedAt: releasedAt ?? this.releasedAt,
      cmc: cmc ?? this.cmc,
      colors: colors ?? this.colors,
      colorIdentity: colorIdentity ?? this.colorIdentity,
      watermark: watermark ?? this.watermark,
      layout: layout ?? this.layout,
      fullArt: fullArt ?? this.fullArt,
      hasBack: hasBack ?? this.hasBack,
      imageUpdatedAt: imageUpdatedAt ?? this.imageUpdatedAt,
      imageStatus: imageStatus ?? this.imageStatus,
      finishes: finishes ?? this.finishes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (oracleId.present) {
      map['oracle_id'] = Variable<String>(oracleId.value);
    }
    if (illustrationId.present) {
      map['illustration_id'] = Variable<String>(illustrationId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (setCode.present) {
      map['set_code'] = Variable<String>(setCode.value);
    }
    if (collectorNumber.present) {
      map['collector_number'] = Variable<String>(collectorNumber.value);
    }
    if (lang.present) {
      map['lang'] = Variable<String>(lang.value);
    }
    if (rarity.present) {
      map['rarity'] = Variable<int>(rarity.value);
    }
    if (releasedAt.present) {
      map['released_at'] = Variable<int>(releasedAt.value);
    }
    if (cmc.present) {
      map['cmc'] = Variable<double>(cmc.value);
    }
    if (colors.present) {
      map['colors'] = Variable<String>(colors.value);
    }
    if (colorIdentity.present) {
      map['color_identity'] = Variable<String>(colorIdentity.value);
    }
    if (watermark.present) {
      map['watermark'] = Variable<String>(watermark.value);
    }
    if (layout.present) {
      map['layout'] = Variable<String>(layout.value);
    }
    if (fullArt.present) {
      map['full_art'] = Variable<bool>(fullArt.value);
    }
    if (hasBack.present) {
      map['has_back'] = Variable<bool>(hasBack.value);
    }
    if (imageUpdatedAt.present) {
      map['image_updated_at'] = Variable<int>(imageUpdatedAt.value);
    }
    if (imageStatus.present) {
      map['image_status'] = Variable<int>(imageStatus.value);
    }
    if (finishes.present) {
      map['finishes'] = Variable<int>(finishes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardsCompanion(')
          ..write('id: $id, ')
          ..write('oracleId: $oracleId, ')
          ..write('illustrationId: $illustrationId, ')
          ..write('name: $name, ')
          ..write('setCode: $setCode, ')
          ..write('collectorNumber: $collectorNumber, ')
          ..write('lang: $lang, ')
          ..write('rarity: $rarity, ')
          ..write('releasedAt: $releasedAt, ')
          ..write('cmc: $cmc, ')
          ..write('colors: $colors, ')
          ..write('colorIdentity: $colorIdentity, ')
          ..write('watermark: $watermark, ')
          ..write('layout: $layout, ')
          ..write('fullArt: $fullArt, ')
          ..write('hasBack: $hasBack, ')
          ..write('imageUpdatedAt: $imageUpdatedAt, ')
          ..write('imageStatus: $imageStatus, ')
          ..write('finishes: $finishes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$CardsDatabase extends GeneratedDatabase {
  _$CardsDatabase(QueryExecutor e) : super(e);
  $CardsDatabaseManager get managers => $CardsDatabaseManager(this);
  late final $MetaTable meta = $MetaTable(this);
  late final $SetsTable sets = $SetsTable(this);
  late final $CardsTable cards = $CardsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [meta, sets, cards];
}

typedef $$MetaTableCreateCompanionBuilder =
    MetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$MetaTableUpdateCompanionBuilder =
    MetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$MetaTableFilterComposer extends Composer<_$CardsDatabase, $MetaTable> {
  $$MetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MetaTableOrderingComposer
    extends Composer<_$CardsDatabase, $MetaTable> {
  $$MetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MetaTableAnnotationComposer
    extends Composer<_$CardsDatabase, $MetaTable> {
  $$MetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$MetaTableTableManager
    extends
        RootTableManager<
          _$CardsDatabase,
          $MetaTable,
          MetaData,
          $$MetaTableFilterComposer,
          $$MetaTableOrderingComposer,
          $$MetaTableAnnotationComposer,
          $$MetaTableCreateCompanionBuilder,
          $$MetaTableUpdateCompanionBuilder,
          (MetaData, BaseReferences<_$CardsDatabase, $MetaTable, MetaData>),
          MetaData,
          PrefetchHooks Function()
        > {
  $$MetaTableTableManager(_$CardsDatabase db, $MetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => MetaCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MetaTableProcessedTableManager =
    ProcessedTableManager<
      _$CardsDatabase,
      $MetaTable,
      MetaData,
      $$MetaTableFilterComposer,
      $$MetaTableOrderingComposer,
      $$MetaTableAnnotationComposer,
      $$MetaTableCreateCompanionBuilder,
      $$MetaTableUpdateCompanionBuilder,
      (MetaData, BaseReferences<_$CardsDatabase, $MetaTable, MetaData>),
      MetaData,
      PrefetchHooks Function()
    >;
typedef $$SetsTableCreateCompanionBuilder =
    SetsCompanion Function({
      required String code,
      required String name,
      Value<int?> releasedAt,
      Value<String?> setType,
      Value<int> rowid,
    });
typedef $$SetsTableUpdateCompanionBuilder =
    SetsCompanion Function({
      Value<String> code,
      Value<String> name,
      Value<int?> releasedAt,
      Value<String?> setType,
      Value<int> rowid,
    });

final class $$SetsTableReferences
    extends BaseReferences<_$CardsDatabase, $SetsTable, CardSet> {
  $$SetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CardsTable, List<Card>> _cardsRefsTable(
    _$CardsDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.cards,
    aliasName: 'sets__code__cards__set_code',
  );

  $$CardsTableProcessedTableManager get cardsRefs {
    final manager = $$CardsTableTableManager(
      $_db,
      $_db.cards,
    ).filter((f) => f.setCode.code.sqlEquals($_itemColumn<String>('code')!));

    final cache = $_typedResult.readTableOrNull(_cardsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SetsTableFilterComposer extends Composer<_$CardsDatabase, $SetsTable> {
  $$SetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get setType => $composableBuilder(
    column: $table.setType,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> cardsRefs(
    Expression<bool> Function($$CardsTableFilterComposer f) f,
  ) {
    final $$CardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.code,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.setCode,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableFilterComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SetsTableOrderingComposer
    extends Composer<_$CardsDatabase, $SetsTable> {
  $$SetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get setType => $composableBuilder(
    column: $table.setType,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SetsTableAnnotationComposer
    extends Composer<_$CardsDatabase, $SetsTable> {
  $$SetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get setType =>
      $composableBuilder(column: $table.setType, builder: (column) => column);

  Expression<T> cardsRefs<T extends Object>(
    Expression<T> Function($$CardsTableAnnotationComposer a) f,
  ) {
    final $$CardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.code,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.setCode,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableAnnotationComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SetsTableTableManager
    extends
        RootTableManager<
          _$CardsDatabase,
          $SetsTable,
          CardSet,
          $$SetsTableFilterComposer,
          $$SetsTableOrderingComposer,
          $$SetsTableAnnotationComposer,
          $$SetsTableCreateCompanionBuilder,
          $$SetsTableUpdateCompanionBuilder,
          (CardSet, $$SetsTableReferences),
          CardSet,
          PrefetchHooks Function({bool cardsRefs})
        > {
  $$SetsTableTableManager(_$CardsDatabase db, $SetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int?> releasedAt = const Value.absent(),
                Value<String?> setType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SetsCompanion(
                code: code,
                name: name,
                releasedAt: releasedAt,
                setType: setType,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String code,
                required String name,
                Value<int?> releasedAt = const Value.absent(),
                Value<String?> setType = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SetsCompanion.insert(
                code: code,
                name: name,
                releasedAt: releasedAt,
                setType: setType,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$SetsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({cardsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (cardsRefs) db.cards],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (cardsRefs)
                    await $_getPrefetchedData<CardSet, $SetsTable, Card>(
                      currentTable: table,
                      referencedTable: $$SetsTableReferences._cardsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$SetsTableReferences(db, table, p0).cardsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.setCode == item.code),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SetsTableProcessedTableManager =
    ProcessedTableManager<
      _$CardsDatabase,
      $SetsTable,
      CardSet,
      $$SetsTableFilterComposer,
      $$SetsTableOrderingComposer,
      $$SetsTableAnnotationComposer,
      $$SetsTableCreateCompanionBuilder,
      $$SetsTableUpdateCompanionBuilder,
      (CardSet, $$SetsTableReferences),
      CardSet,
      PrefetchHooks Function({bool cardsRefs})
    >;
typedef $$CardsTableCreateCompanionBuilder =
    CardsCompanion Function({
      required String id,
      required String oracleId,
      Value<String?> illustrationId,
      required String name,
      required String setCode,
      required String collectorNumber,
      Value<String> lang,
      Value<int?> rarity,
      Value<int?> releasedAt,
      Value<double?> cmc,
      Value<String?> colors,
      Value<String?> colorIdentity,
      Value<String?> watermark,
      Value<String?> layout,
      Value<bool> fullArt,
      Value<bool> hasBack,
      Value<int?> imageUpdatedAt,
      Value<int> imageStatus,
      Value<int> finishes,
      Value<int> rowid,
    });
typedef $$CardsTableUpdateCompanionBuilder =
    CardsCompanion Function({
      Value<String> id,
      Value<String> oracleId,
      Value<String?> illustrationId,
      Value<String> name,
      Value<String> setCode,
      Value<String> collectorNumber,
      Value<String> lang,
      Value<int?> rarity,
      Value<int?> releasedAt,
      Value<double?> cmc,
      Value<String?> colors,
      Value<String?> colorIdentity,
      Value<String?> watermark,
      Value<String?> layout,
      Value<bool> fullArt,
      Value<bool> hasBack,
      Value<int?> imageUpdatedAt,
      Value<int> imageStatus,
      Value<int> finishes,
      Value<int> rowid,
    });

final class $$CardsTableReferences
    extends BaseReferences<_$CardsDatabase, $CardsTable, Card> {
  $$CardsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SetsTable _setCodeTable(_$CardsDatabase db) =>
      db.sets.createAlias('cards__set_code__sets__code');

  $$SetsTableProcessedTableManager get setCode {
    final $_column = $_itemColumn<String>('set_code')!;

    final manager = $$SetsTableTableManager(
      $_db,
      $_db.sets,
    ).filter((f) => f.code.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_setCodeTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CardsTableFilterComposer
    extends Composer<_$CardsDatabase, $CardsTable> {
  $$CardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get oracleId => $composableBuilder(
    column: $table.oracleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get illustrationId => $composableBuilder(
    column: $table.illustrationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectorNumber => $composableBuilder(
    column: $table.collectorNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lang => $composableBuilder(
    column: $table.lang,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rarity => $composableBuilder(
    column: $table.rarity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cmc => $composableBuilder(
    column: $table.cmc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colors => $composableBuilder(
    column: $table.colors,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorIdentity => $composableBuilder(
    column: $table.colorIdentity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get watermark => $composableBuilder(
    column: $table.watermark,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get layout => $composableBuilder(
    column: $table.layout,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get fullArt => $composableBuilder(
    column: $table.fullArt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasBack => $composableBuilder(
    column: $table.hasBack,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get imageUpdatedAt => $composableBuilder(
    column: $table.imageUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get imageStatus => $composableBuilder(
    column: $table.imageStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finishes => $composableBuilder(
    column: $table.finishes,
    builder: (column) => ColumnFilters(column),
  );

  $$SetsTableFilterComposer get setCode {
    final $$SetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setCode,
      referencedTable: $db.sets,
      getReferencedColumn: (t) => t.code,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SetsTableFilterComposer(
            $db: $db,
            $table: $db.sets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardsTableOrderingComposer
    extends Composer<_$CardsDatabase, $CardsTable> {
  $$CardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get oracleId => $composableBuilder(
    column: $table.oracleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get illustrationId => $composableBuilder(
    column: $table.illustrationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectorNumber => $composableBuilder(
    column: $table.collectorNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lang => $composableBuilder(
    column: $table.lang,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rarity => $composableBuilder(
    column: $table.rarity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cmc => $composableBuilder(
    column: $table.cmc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colors => $composableBuilder(
    column: $table.colors,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorIdentity => $composableBuilder(
    column: $table.colorIdentity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get watermark => $composableBuilder(
    column: $table.watermark,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get layout => $composableBuilder(
    column: $table.layout,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get fullArt => $composableBuilder(
    column: $table.fullArt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasBack => $composableBuilder(
    column: $table.hasBack,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get imageUpdatedAt => $composableBuilder(
    column: $table.imageUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get imageStatus => $composableBuilder(
    column: $table.imageStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finishes => $composableBuilder(
    column: $table.finishes,
    builder: (column) => ColumnOrderings(column),
  );

  $$SetsTableOrderingComposer get setCode {
    final $$SetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setCode,
      referencedTable: $db.sets,
      getReferencedColumn: (t) => t.code,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SetsTableOrderingComposer(
            $db: $db,
            $table: $db.sets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardsTableAnnotationComposer
    extends Composer<_$CardsDatabase, $CardsTable> {
  $$CardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get oracleId =>
      $composableBuilder(column: $table.oracleId, builder: (column) => column);

  GeneratedColumn<String> get illustrationId => $composableBuilder(
    column: $table.illustrationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get collectorNumber => $composableBuilder(
    column: $table.collectorNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lang =>
      $composableBuilder(column: $table.lang, builder: (column) => column);

  GeneratedColumn<int> get rarity =>
      $composableBuilder(column: $table.rarity, builder: (column) => column);

  GeneratedColumn<int> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get cmc =>
      $composableBuilder(column: $table.cmc, builder: (column) => column);

  GeneratedColumn<String> get colors =>
      $composableBuilder(column: $table.colors, builder: (column) => column);

  GeneratedColumn<String> get colorIdentity => $composableBuilder(
    column: $table.colorIdentity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get watermark =>
      $composableBuilder(column: $table.watermark, builder: (column) => column);

  GeneratedColumn<String> get layout =>
      $composableBuilder(column: $table.layout, builder: (column) => column);

  GeneratedColumn<bool> get fullArt =>
      $composableBuilder(column: $table.fullArt, builder: (column) => column);

  GeneratedColumn<bool> get hasBack =>
      $composableBuilder(column: $table.hasBack, builder: (column) => column);

  GeneratedColumn<int> get imageUpdatedAt => $composableBuilder(
    column: $table.imageUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get imageStatus => $composableBuilder(
    column: $table.imageStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get finishes =>
      $composableBuilder(column: $table.finishes, builder: (column) => column);

  $$SetsTableAnnotationComposer get setCode {
    final $$SetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setCode,
      referencedTable: $db.sets,
      getReferencedColumn: (t) => t.code,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SetsTableAnnotationComposer(
            $db: $db,
            $table: $db.sets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardsTableTableManager
    extends
        RootTableManager<
          _$CardsDatabase,
          $CardsTable,
          Card,
          $$CardsTableFilterComposer,
          $$CardsTableOrderingComposer,
          $$CardsTableAnnotationComposer,
          $$CardsTableCreateCompanionBuilder,
          $$CardsTableUpdateCompanionBuilder,
          (Card, $$CardsTableReferences),
          Card,
          PrefetchHooks Function({bool setCode})
        > {
  $$CardsTableTableManager(_$CardsDatabase db, $CardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> oracleId = const Value.absent(),
                Value<String?> illustrationId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> setCode = const Value.absent(),
                Value<String> collectorNumber = const Value.absent(),
                Value<String> lang = const Value.absent(),
                Value<int?> rarity = const Value.absent(),
                Value<int?> releasedAt = const Value.absent(),
                Value<double?> cmc = const Value.absent(),
                Value<String?> colors = const Value.absent(),
                Value<String?> colorIdentity = const Value.absent(),
                Value<String?> watermark = const Value.absent(),
                Value<String?> layout = const Value.absent(),
                Value<bool> fullArt = const Value.absent(),
                Value<bool> hasBack = const Value.absent(),
                Value<int?> imageUpdatedAt = const Value.absent(),
                Value<int> imageStatus = const Value.absent(),
                Value<int> finishes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion(
                id: id,
                oracleId: oracleId,
                illustrationId: illustrationId,
                name: name,
                setCode: setCode,
                collectorNumber: collectorNumber,
                lang: lang,
                rarity: rarity,
                releasedAt: releasedAt,
                cmc: cmc,
                colors: colors,
                colorIdentity: colorIdentity,
                watermark: watermark,
                layout: layout,
                fullArt: fullArt,
                hasBack: hasBack,
                imageUpdatedAt: imageUpdatedAt,
                imageStatus: imageStatus,
                finishes: finishes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String oracleId,
                Value<String?> illustrationId = const Value.absent(),
                required String name,
                required String setCode,
                required String collectorNumber,
                Value<String> lang = const Value.absent(),
                Value<int?> rarity = const Value.absent(),
                Value<int?> releasedAt = const Value.absent(),
                Value<double?> cmc = const Value.absent(),
                Value<String?> colors = const Value.absent(),
                Value<String?> colorIdentity = const Value.absent(),
                Value<String?> watermark = const Value.absent(),
                Value<String?> layout = const Value.absent(),
                Value<bool> fullArt = const Value.absent(),
                Value<bool> hasBack = const Value.absent(),
                Value<int?> imageUpdatedAt = const Value.absent(),
                Value<int> imageStatus = const Value.absent(),
                Value<int> finishes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion.insert(
                id: id,
                oracleId: oracleId,
                illustrationId: illustrationId,
                name: name,
                setCode: setCode,
                collectorNumber: collectorNumber,
                lang: lang,
                rarity: rarity,
                releasedAt: releasedAt,
                cmc: cmc,
                colors: colors,
                colorIdentity: colorIdentity,
                watermark: watermark,
                layout: layout,
                fullArt: fullArt,
                hasBack: hasBack,
                imageUpdatedAt: imageUpdatedAt,
                imageStatus: imageStatus,
                finishes: finishes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$CardsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({setCode = false}) {
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
                    if (setCode) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.setCode,
                                referencedTable: $$CardsTableReferences
                                    ._setCodeTable(db),
                                referencedColumn: $$CardsTableReferences
                                    ._setCodeTable(db)
                                    .code,
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

typedef $$CardsTableProcessedTableManager =
    ProcessedTableManager<
      _$CardsDatabase,
      $CardsTable,
      Card,
      $$CardsTableFilterComposer,
      $$CardsTableOrderingComposer,
      $$CardsTableAnnotationComposer,
      $$CardsTableCreateCompanionBuilder,
      $$CardsTableUpdateCompanionBuilder,
      (Card, $$CardsTableReferences),
      Card,
      PrefetchHooks Function({bool setCode})
    >;

class $CardsDatabaseManager {
  final _$CardsDatabase _db;
  $CardsDatabaseManager(this._db);
  $$MetaTableTableManager get meta => $$MetaTableTableManager(_db, _db.meta);
  $$SetsTableTableManager get sets => $$SetsTableTableManager(_db, _db.sets);
  $$CardsTableTableManager get cards =>
      $$CardsTableTableManager(_db, _db.cards);
}
