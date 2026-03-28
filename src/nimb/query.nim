import std/[options, strutils]

import nimb/[db, model, sql]

type
  SelectQuery* = object
    modelInfo*: Option[ModelInfo]
    fromClause*: SqlFragment
    columns*: seq[SqlFragment]
    joins*: seq[SqlFragment]
    whereClauses*: seq[SqlFragment]
    groupClauses*: seq[string]
    havingClauses*: seq[SqlFragment]
    orderClauses*: seq[string]
    limitValue*: int
    offsetValue*: int

  InsertQuery* = object
    modelInfo*: Option[ModelInfo]
    intoClause*: SqlFragment
    columns*: seq[string]
    rows*: seq[seq[DbValue]]
    returningClauses*: seq[string]

  UpdateQuery* = object
    modelInfo*: Option[ModelInfo]
    tableClause*: SqlFragment
    setClauses*: seq[SqlFragment]
    whereClauses*: seq[SqlFragment]
    returningClauses*: seq[string]

  DeleteQuery* = object
    modelInfo*: Option[ModelInfo]
    fromClause*: SqlFragment
    whereClauses*: seq[SqlFragment]
    returningClauses*: seq[string]

  CreateTableQuery* = object
    info*: ModelInfo
    includeIfNotExists*: bool

  DropTableQuery* = object
    tableName*: string
    includeIfExists*: bool

proc addParams(target: var seq[DbValue]; fragment: SqlFragment) =
  for param in fragment.params:
    target.add(param)

proc joinFragmentSql(fragments: openArray[SqlFragment]; separator: string): string =
  for index, fragment in fragments:
    if index > 0:
      result.add(separator)
    result.add(fragment.sql)

proc quotedColumnNames(fields: openArray[FieldInfo]): seq[string] =
  for field in fields:
    result.add(quoteIdent(field.columnName))

proc primaryKeyFields(fields: openArray[FieldInfo]): seq[FieldInfo] =
  for field in fields:
    if field.primaryKey:
      result.add(field)

proc initSelectRaw*(): SelectQuery =
  SelectQuery(
    fromClause: raw(""),
    limitValue: -1,
    offsetValue: -1
  )

proc initSelect*[T](modelType: typedesc[T]): SelectQuery =
  let info = modelInfo(modelType)
  result = SelectQuery(
    fromClause: raw(""),
    limitValue: -1,
    offsetValue: -1
  )
  result.modelInfo = some(info)
  result.fromClause = ident(info.tableName)

template initSelect*[T](): SelectQuery =
  initSelect(T)

proc initInsert*[T](value: T): InsertQuery =
  let info = modelInfo(T)
  result.modelInfo = some(info)
  result.intoClause = ident(info.tableName)
  let fields = insertableFields(info)
  result.columns = quotedColumnNames(fields)
  result.rows = @[toDbValues(value, fields)]

proc initUpdate*[T](value: T): UpdateQuery =
  let info = modelInfo(T)
  result.modelInfo = some(info)
  result.tableClause = ident(info.tableName)
  let updateFields = updateableFields(info)
  let updateValues = toDbValues(value, updateFields)
  for index, field in updateFields:
    result.setClauses.add(raw(quoteIdent(field.columnName) & " = ?",
      updateValues[index]))
  let pkField = primaryKeyField(info)
  let pkValue = toDbValues(value, [pkField])[0]
  result.whereClauses.add(raw(quoteIdent(pkField.columnName) & " = ?", pkValue))

proc initDelete*[T](value: T): DeleteQuery =
  let info = modelInfo(T)
  result.modelInfo = some(info)
  result.fromClause = ident(info.tableName)
  let pkField = primaryKeyField(info)
  let pkValue = toDbValues(value, [pkField])[0]
  result.whereClauses.add(raw(quoteIdent(pkField.columnName) & " = ?", pkValue))

proc initDelete*[T](modelType: typedesc[T]): DeleteQuery =
  let info = modelInfo(modelType)
  result.modelInfo = some(info)
  result.fromClause = ident(info.tableName)

template initDelete*[T](): DeleteQuery =
  initDelete(T)

proc initCreateTable*[T](modelType: typedesc[T]): CreateTableQuery =
  CreateTableQuery(info: modelInfo(modelType))

template initCreateTable*[T](): CreateTableQuery =
  initCreateTable(T)

proc initDropTable*[T](modelType: typedesc[T]): DropTableQuery =
  DropTableQuery(tableName: modelInfo(modelType).tableName)

template initDropTable*[T](): DropTableQuery =
  initDropTable(T)

proc table*(q: var SelectQuery; name: string) =
  q.fromClause = ident(name)

proc tableExpr*(q: var SelectQuery; sql: string; params: varargs[DbValue, `!?`]) =
  q.fromClause = raw(sql, params)

proc tableExpr*(q: var SelectQuery; fragment: SqlFragment) =
  q.fromClause = fragment

proc table*(q: var InsertQuery; name: string) =
  q.intoClause = ident(name)

proc tableExpr*(q: var InsertQuery; sql: string; params: varargs[DbValue, `!?`]) =
  q.intoClause = raw(sql, params)

proc table*(q: var UpdateQuery; name: string) =
  q.tableClause = ident(name)

proc tableExpr*(q: var UpdateQuery; sql: string; params: varargs[DbValue, `!?`]) =
  q.tableClause = raw(sql, params)

proc table*(q: var DeleteQuery; name: string) =
  q.fromClause = ident(name)

proc tableExpr*(q: var DeleteQuery; sql: string; params: varargs[DbValue, `!?`]) =
  q.fromClause = raw(sql, params)

proc tableExpr*(q: var DeleteQuery; fragment: SqlFragment) =
  q.fromClause = fragment

proc column*(q: var SelectQuery; names: varargs[string]) =
  for name in names:
    q.columns.add(ident(name))

proc columnExpr*(q: var SelectQuery; sql: string; params: varargs[DbValue, `!?`]) =
  q.columns.add(raw(sql, params))

proc columnExpr*(q: var SelectQuery; fragment: SqlFragment) =
  q.columns.add(fragment)

proc join*(q: var SelectQuery; sql: string; params: varargs[DbValue, `!?`]) =
  q.joins.add(raw(sql, params))

proc join*(q: var SelectQuery; fragment: SqlFragment) =
  q.joins.add(fragment)

proc where*(q: var SelectQuery; sql: string; params: varargs[DbValue, `!?`]) =
  q.whereClauses.add(raw(sql, params))

proc where*(q: var UpdateQuery; sql: string; params: varargs[DbValue, `!?`]) =
  q.whereClauses.add(raw(sql, params))

proc where*(q: var DeleteQuery; sql: string; params: varargs[DbValue, `!?`]) =
  q.whereClauses.add(raw(sql, params))

proc groupBy*(q: var SelectQuery; expressions: varargs[string]) =
  for expression in expressions:
    q.groupClauses.add(expression)

proc having*(q: var SelectQuery; sql: string; params: varargs[DbValue, `!?`]) =
  q.havingClauses.add(raw(sql, params))

proc having*(q: var SelectQuery; fragment: SqlFragment) =
  q.havingClauses.add(fragment)

proc orderBy*(q: var SelectQuery; expressions: varargs[string]) =
  for expression in expressions:
    q.orderClauses.add(expression)

proc limit*(q: var SelectQuery; value: int) =
  q.limitValue = value

proc offset*(q: var SelectQuery; value: int) =
  q.offsetValue = value

proc column*(q: var InsertQuery; names: varargs[string]) =
  q.columns.setLen(0)
  for name in names:
    q.columns.add(quoteIdent(name))

proc values*(q: var InsertQuery; params: varargs[DbValue, `!?`]) =
  if q.columns.len > 0 and params.len != q.columns.len:
    raise newException(DbError, "insert values do not match insert columns")
  q.rows.add(@params)

proc returning*(q: var InsertQuery; expressions: varargs[string]) =
  for expression in expressions:
    q.returningClauses.add(expression)

proc set*(q: var UpdateQuery; columnName: string; value: DbValue) =
  q.setClauses.add(raw(quoteIdent(columnName) & " = ?", value))

proc setExpr*(q: var UpdateQuery; sql: string; params: varargs[DbValue, `!?`]) =
  q.setClauses.add(raw(sql, params))

proc returning*(q: var UpdateQuery; expressions: varargs[string]) =
  for expression in expressions:
    q.returningClauses.add(expression)

proc returning*(q: var DeleteQuery; expressions: varargs[string]) =
  for expression in expressions:
    q.returningClauses.add(expression)

proc ifNotExists*(q: var CreateTableQuery) =
  q.includeIfNotExists = true

proc ifExists*(q: var DropTableQuery) =
  q.includeIfExists = true

proc render*(q: SelectQuery): RenderedQuery =
  var parts = @["SELECT"]
  if q.columns.len > 0:
    parts.add(joinFragmentSql(q.columns, ", "))
    for columnExpr in q.columns:
      addParams(result.params, columnExpr)
  elif q.modelInfo.isSome:
    let fields = selectableFields(q.modelInfo.get)
    parts.add(quotedColumnNames(fields).join(", "))
  else:
    parts.add("*")

  if q.fromClause.sql.len > 0:
    parts.add("FROM " & q.fromClause.sql)
    addParams(result.params, q.fromClause)

  for joinClause in q.joins:
    parts.add(joinClause.sql)
    addParams(result.params, joinClause)

  if q.whereClauses.len > 0:
    parts.add("WHERE " & joinFragmentSql(q.whereClauses, " AND "))
    for clause in q.whereClauses:
      addParams(result.params, clause)

  if q.groupClauses.len > 0:
    parts.add("GROUP BY " & q.groupClauses.join(", "))

  if q.havingClauses.len > 0:
    parts.add("HAVING " & joinFragmentSql(q.havingClauses, " AND "))
    for clause in q.havingClauses:
      addParams(result.params, clause)

  if q.orderClauses.len > 0:
    parts.add("ORDER BY " & q.orderClauses.join(", "))

  if q.limitValue >= 0:
    parts.add("LIMIT ?")
    result.params.add(dbValue(q.limitValue))

  if q.offsetValue >= 0:
    parts.add("OFFSET ?")
    result.params.add(dbValue(q.offsetValue))

  result.sql = parts.join(" ")

proc render*(q: InsertQuery): RenderedQuery =
  if q.rows.len == 0:
    raise newException(DbError, "insert query has no rows")
  if q.columns.len == 0:
    raise newException(DbError, "insert query has no columns")

  var parts = @["INSERT INTO", q.intoClause.sql,
    "(" & q.columns.join(", ") & ")", "VALUES"]
  addParams(result.params, q.intoClause)

  var rowSql: seq[string] = @[]
  for row in q.rows:
    var placeholders: seq[string] = @[]
    for value in row:
      placeholders.add("?")
      result.params.add(value)
    rowSql.add("(" & placeholders.join(", ") & ")")
  parts.add(rowSql.join(", "))

  if q.returningClauses.len > 0:
    parts.add("RETURNING " & q.returningClauses.join(", "))

  result.sql = parts.join(" ")

proc render*(q: UpdateQuery): RenderedQuery =
  if q.setClauses.len == 0:
    raise newException(DbError, "update query has no SET clauses")

  var parts = @["UPDATE", q.tableClause.sql,
    "SET " & joinFragmentSql(q.setClauses, ", ")]
  addParams(result.params, q.tableClause)
  for clause in q.setClauses:
    addParams(result.params, clause)

  if q.whereClauses.len > 0:
    parts.add("WHERE " & joinFragmentSql(q.whereClauses, " AND "))
    for clause in q.whereClauses:
      addParams(result.params, clause)

  if q.returningClauses.len > 0:
    parts.add("RETURNING " & q.returningClauses.join(", "))

  result.sql = parts.join(" ")

proc render*(q: DeleteQuery): RenderedQuery =
  var parts = @["DELETE FROM", q.fromClause.sql]
  addParams(result.params, q.fromClause)

  if q.whereClauses.len > 0:
    parts.add("WHERE " & joinFragmentSql(q.whereClauses, " AND "))
    for clause in q.whereClauses:
      addParams(result.params, clause)

  if q.returningClauses.len > 0:
    parts.add("RETURNING " & q.returningClauses.join(", "))

  result.sql = parts.join(" ")

proc render*(q: CreateTableQuery): RenderedQuery =
  let fields = selectableFields(q.info)
  let primaryKeys = primaryKeyFields(fields)
  if primaryKeys.len > 1:
    raise newException(DbError,
      q.info.typeName & " has multiple primary keys, which v1 does not support")

  var columnDefs: seq[string] = @[]
  for field in fields:
    var parts = @[quoteIdent(field.columnName)]
    if field.autoIncrement:
      if not field.primaryKey or field.sqlType != "INTEGER":
        raise newException(DbError,
          field.fieldName & " must be INTEGER PRIMARY KEY for AUTOINCREMENT")
      parts.add("INTEGER PRIMARY KEY AUTOINCREMENT")
    else:
      parts.add(field.sqlType)
      if field.primaryKey:
        parts.add("PRIMARY KEY")
      elif not field.nullable:
        parts.add("NOT NULL")
    if field.defaultExpr.len > 0:
      parts.add("DEFAULT " & field.defaultExpr)
    columnDefs.add(parts.join(" "))

  result.sql = "CREATE TABLE "
  if q.includeIfNotExists:
    result.sql.add("IF NOT EXISTS ")
  result.sql.add(quoteIdent(q.info.tableName))
  result.sql.add(" (" & columnDefs.join(", ") & ")")

proc render*(q: DropTableQuery): RenderedQuery =
  result.sql = "DROP TABLE "
  if q.includeIfExists:
    result.sql.add("IF EXISTS ")
  result.sql.add(quoteIdent(q.tableName))
