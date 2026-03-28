import std/[macros, options, strutils]

import nimb/db

template dbTable*(name: static string) {.pragma.}
template dbColumn*(name: static string) {.pragma.}
template dbPk*() {.pragma.}
template dbAutoInc*() {.pragma.}
template dbNull*() {.pragma.}
template dbDefault*(value: static string) {.pragma.}
template dbIgnore*() {.pragma.}

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

proc findPragmaArg(pragmas: NimNode; pragmaName: string): NimNode =
  for pragmaNode in pragmas:
    if pragmaNode.kind == nnkSym and $pragmaNode == pragmaName:
      return newLit(true)
    if pragmaNode.kind == nnkCall and $pragmaNode[0] == pragmaName:
      return pragmaNode[1]
  result = nil

proc unwrapOption(fieldType: NimNode): NimNode =
  if fieldType.kind == nnkBracketExpr and $fieldType[0] == "Option":
    return fieldType[1]
  result = fieldType

macro modelInfo*(T: typedesc): untyped =
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
  var tableName = ""
  if typePragmaExpr.kind == nnkPragmaExpr:
    typeName = $typePragmaExpr[0]
    tableName = snakeCase(typeName)
  else:
    typeName = $typePragmaExpr
    tableName = snakeCase(typeName)

  if typePragmaExpr.kind == nnkPragmaExpr:
    let pragmaArg = findPragmaArg(typePragmaExpr[1], "dbTable")
    if pragmaArg != nil:
      tableName = pragmaArg.strVal

  let fieldsNode = newNimNode(nnkBracket)
  let recList = objectTy[2]
  for identDefs in recList:
    if identDefs.kind != nnkIdentDefs:
      continue

    let fieldExpr = identDefs[0]
    let fieldType = identDefs[1]

    var fieldNameNode = fieldExpr
    var pragmas: NimNode = nil
    if fieldExpr.kind == nnkPragmaExpr:
      fieldNameNode = fieldExpr[0]
      pragmas = fieldExpr[1]

    var fieldName = $fieldNameNode
    var columnName = snakeCase(fieldName)
    var primaryKey = false
    var autoIncrement = false
    var nullable = false
    var defaultExpr = ""
    var ignored = false

    if pragmas != nil:
      let columnPragma = findPragmaArg(pragmas, "dbColumn")
      if columnPragma != nil:
        columnName = columnPragma.strVal
      primaryKey = findPragmaArg(pragmas, "dbPk") != nil
      autoIncrement = findPragmaArg(pragmas, "dbAutoInc") != nil
      nullable = findPragmaArg(pragmas, "dbNull") != nil
      ignored = findPragmaArg(pragmas, "dbIgnore") != nil
      let defaultPragma = findPragmaArg(pragmas, "dbDefault")
      if defaultPragma != nil:
        defaultExpr = defaultPragma.strVal

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

proc fromRow*[T](row: Row): T =
  let info = modelInfo(T)
  result = default(T)
  for modelFieldName, modelFieldValue in fieldPairs(result):
    let fieldInfo = fieldByName(info, modelFieldName)
    if not fieldInfo.ignored and row.hasColumn(fieldInfo.columnName):
      assignDbValue(modelFieldValue, row[fieldInfo.columnName])
