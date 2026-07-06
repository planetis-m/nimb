import std/[macros, options, strutils]

import nimb/db

type
  FieldInfo* = object
    fieldName*: string
    columnName*: string
    sqlType*: string
    primaryKey*: bool
    autoIncrement*: bool
    nullable*: bool
    defaultExpr*: string
    ignored*: bool

  ModelInfo* = object
    typeName*: string
    tableName*: string
    fields*: seq[FieldInfo]

  Model*[T] = object
    info*: ModelInfo

proc snakeCase(text: string): string =
  for index, ch in text:
    if ch.isUpperAscii:
      if index > 0:
        result.add('_')
      result.add(ch.toLowerAscii)
    else:
      result.add(ch)

proc sqlTypeFor*[T](): string =
  when T is bool:
    result = "INTEGER"
  elif T is SomeInteger:
    result = "INTEGER"
  elif T is SomeFloat:
    result = "REAL"
  elif T is string:
    result = "TEXT"
  elif T is seq[byte]:
    result = "BLOB"
  else:
    {.error: "unsupported model field type".}

proc unwrapOption(fieldType: NimNode): NimNode =
  if fieldType.kind == nnkBracketExpr and $fieldType[0] == "Option":
    return fieldType[1]
  result = fieldType

macro defaultModelInfo*(T: typedesc): untyped =
  var target = T
  let typeInst = T.getTypeInst
  if typeInst.kind == nnkBracketExpr and $typeInst[0] == "typeDesc":
    target = typeInst[1]
  elif T.kind == nnkBracketExpr and $T[0] == "typeDesc":
    target = T[1]

  var typeDef = target.getImpl
  if typeDef.kind == nnkSym:
    typeDef = typeDef.getImpl
  if typeDef.kind != nnkTypeDef:
    error("modelInfo expects a named object type", T)

  let typePragmaExpr = typeDef[0]
  let objectTy = typeDef[2]
  if objectTy.kind != nnkObjectTy:
    error("modelInfo only supports object types", T)

  var typeName = ""
  if typePragmaExpr.kind == nnkPragmaExpr:
    typeName = $typePragmaExpr[0]
  else:
    typeName = $typePragmaExpr
  let tableName = snakeCase(typeName)

  let fieldsNode = newNimNode(nnkBracket)
  let recList = objectTy[2]
  for identDefs in recList:
    if identDefs.kind != nnkIdentDefs:
      continue

    let fieldExpr = identDefs[0]
    let fieldType = identDefs[1]

    var fieldNameNode = fieldExpr
    if fieldExpr.kind == nnkPragmaExpr:
      fieldNameNode = fieldExpr[0]

    var fieldName = $fieldNameNode
    var columnName = snakeCase(fieldName)
    var primaryKey = false
    var autoIncrement = false
    var nullable = false
    var defaultExpr = ""
    var ignored = false

    let unwrappedType = unwrapOption(fieldType)
    if unwrappedType != fieldType:
      nullable = true

    let fieldNameLit = newLit(fieldName)
    let columnNameLit = newLit(columnName)
    let primaryKeyLit = newLit(primaryKey)
    let autoIncrementLit = newLit(autoIncrement)
    let nullableLit = newLit(nullable)
    let defaultExprLit = newLit(defaultExpr)
    let ignoredLit = newLit(ignored)

    fieldsNode.add quote do:
      FieldInfo(
        fieldName: `fieldNameLit`,
        columnName: `columnNameLit`,
        sqlType: sqlTypeFor[`unwrappedType`](),
        primaryKey: `primaryKeyLit`,
        autoIncrement: `autoIncrementLit`,
        nullable: `nullableLit`,
        defaultExpr: `defaultExprLit`,
        ignored: `ignoredLit`
      )

  let typeNameLit = newLit(typeName)
  let tableNameLit = newLit(tableName)

  result = quote do:
    ModelInfo(
      typeName: `typeNameLit`,
      tableName: `tableNameLit`,
      fields: @`fieldsNode`
    )

proc initModel*[T](modelType: typedesc[T]): Model[T] =
  result.info = defaultModelInfo(modelType)

template initModel*[T](): Model[T] =
  initModel(T)

template modelInfo*(T: typedesc): ModelInfo =
  defaultModelInfo(T)

proc modelInfo*[T](model: Model[T]): ModelInfo =
  result = model.info

proc field*(info: var ModelInfo; fieldName: string): var FieldInfo =
  for index in 0..<info.fields.len:
    if info.fields[index].fieldName == fieldName:
      return info.fields[index]
  raise newException(DbError, "unknown model field: " & fieldName)

proc field*[T](model: var Model[T]; fieldName: string): var FieldInfo =
  result = field(model.info, fieldName)

proc useTable*(info: var ModelInfo; tableName: string) =
  info.tableName = tableName

proc useTable*[T](model: var Model[T]; tableName: string) =
  useTable(model.info, tableName)

proc fieldIndex(info: ModelInfo; fieldName: string): int =
  for index in 0..<info.fields.len:
    if info.fields[index].fieldName == fieldName:
      return index
  raise newException(DbError, "unknown model field: " & fieldName)

proc mapField*(info: var ModelInfo; fieldName: string; columnName = "";
    sqlType = ""; primaryKey = false; autoIncrement = false;
    nullable = false; defaultExpr = ""; ignored = false) =
  let index = fieldIndex(info, fieldName)
  if columnName.len > 0:
    info.fields[index].columnName = columnName
  if sqlType.len > 0:
    info.fields[index].sqlType = sqlType
  if primaryKey:
    info.fields[index].primaryKey = true
  if autoIncrement:
    info.fields[index].autoIncrement = true
  if nullable:
    info.fields[index].nullable = true
  if defaultExpr.len > 0:
    info.fields[index].defaultExpr = defaultExpr
  if ignored:
    info.fields[index].ignored = true

proc mapField*[T](model: var Model[T]; fieldName: string; columnName = "";
    sqlType = ""; primaryKey = false; autoIncrement = false;
    nullable = false; defaultExpr = ""; ignored = false) =
  mapField(model.info, fieldName, columnName, sqlType, primaryKey,
    autoIncrement, nullable, defaultExpr, ignored)

proc fieldByName*(info: ModelInfo; fieldName: string): FieldInfo =
  for field in info.fields:
    if field.fieldName == fieldName:
      return field
  raise newException(DbError, "unknown model field: " & fieldName)

proc primaryKeyField*(info: ModelInfo): FieldInfo =
  var primaryKeys: seq[FieldInfo]
  for field in info.fields:
    if field.primaryKey and not field.ignored:
      primaryKeys.add(field)
  if primaryKeys.len != 1:
    raise newException(DbError, info.typeName &
      " must define exactly one primary key for this operation")
  primaryKeys[0]

proc insertableFields*(info: ModelInfo): seq[FieldInfo] =
  for field in info.fields:
    if not field.ignored and not field.autoIncrement:
      result.add(field)

proc updateableFields*(info: ModelInfo): seq[FieldInfo] =
  for field in info.fields:
    if not field.ignored and not field.primaryKey and not field.autoIncrement:
      result.add(field)

proc selectableFields*(info: ModelInfo): seq[FieldInfo] =
  for field in info.fields:
    if not field.ignored:
      result.add(field)

proc toDbValues*[T](value: T; fields: openArray[FieldInfo]): seq[DbValue] =
  for fieldInfo in fields:
    var matched = false
    for modelFieldName, modelFieldValue in fieldPairs(value):
      if modelFieldName == fieldInfo.fieldName:
        result.add(toDbValue(modelFieldValue))
        matched = true
    if not matched:
      raise newException(DbError, "missing model field: " & fieldInfo.fieldName)

proc fromRow*[T](row: Row; info: ModelInfo): T =
  result = default(T)
  for modelFieldName, modelFieldValue in fieldPairs(result):
    let fieldInfo = fieldByName(info, modelFieldName)
    if not fieldInfo.ignored and row.hasColumn(fieldInfo.columnName):
      assignDbValue(modelFieldValue, row[fieldInfo.columnName])

proc fromRow*[T](row: Row): T =
  result = fromRow[T](row, modelInfo(T))
