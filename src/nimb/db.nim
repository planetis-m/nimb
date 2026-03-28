import std/[options, strutils]

import nimb/raw/libsql

type
  DbValueKind* = enum
    dvInteger
    dvReal
    dvText
    dvBlob
    dvNull

  DbValue* = object
    case kind*: DbValueKind
    of dvInteger:
      intValue*: int64
    of dvReal:
      realValue*: float64
    of dvText:
      textValue*: string
    of dvBlob:
      blobValue*: seq[byte]
    of dvNull:
      discard

  DatabaseConfig* = object
    path*: string

  DbError* = object of CatchableError

  Database* = object
    handle*: LibsqlDatabaseHandle

  Connection* = object
    handle*: LibsqlConnectionHandle

  Transaction* = object
    handle*: LibsqlTransactionHandle
    connHandle*: LibsqlConnectionHandle
    finished*: bool

  Statement* = object
    handle*: LibsqlStatementHandle
    connHandle*: LibsqlConnectionHandle
    boundValues*: seq[DbValue]

  Rows* = object
    handle*: LibsqlRowsHandle
    columnNames*: seq[string]

  Row* = object
    columnNames*: seq[string]
    values*: seq[DbValue]

  ExecResult* = object
    rowsChanged*: uint64
    lastInsertRowid*: int64
    totalChanges*: uint64

var libsqlInitialized = false

proc toDbValue*(value: DbValue): DbValue
proc toDbValue*(value: int): DbValue
proc toDbValue*(value: int64): DbValue
proc toDbValue*(value: int32): DbValue
proc toDbValue*(value: uint64): DbValue
proc toDbValue*(value: float64): DbValue
proc toDbValue*(value: bool): DbValue
proc toDbValue*(value: string): DbValue
proc toDbValue*(value: seq[byte]): DbValue
proc toDbValue*[T](value: Option[T]): DbValue

proc raiseIfError(err: LibsqlError) =
  if err != nil:
    let message = $libsqlErrorMessage(err)
    libsqlErrorDeinit(err)
    raise newException(DbError, message)

proc ensureLibsqlSetup() =
  if not libsqlInitialized:
    let err = libsqlSetup(LibsqlConfig(logger: nil, version: nil))
    raiseIfError(err)
    libsqlInitialized = true

proc sliceToString(value: LibsqlSlice): string =
  if value.len == 0:
    return ""
  result = newString(int(value.len))
  copyMem(addr result[0], value.data, value.len)
  if result.len > 0 and result[^1] == '\0':
    result.setLen(result.len - 1)

proc sliceToBytes(value: LibsqlSlice): seq[byte] =
  result = newSeq[byte](int(value.len))
  if result.len > 0:
    copyMem(addr result[0], value.data, value.len)

proc toRawValue(value: DbValue): LibsqlValue =
  case value.kind
  of dvInteger:
    result = libsqlInteger(value.intValue)
  of dvReal:
    result = libsqlReal(value.realValue)
  of dvText:
    result = libsqlText(value.textValue.cstring, value.textValue.len.csize_t)
  of dvBlob:
    if value.blobValue.len == 0:
      result = libsqlBlob(nil, 0)
    else:
      result = libsqlBlob(cast[ptr uint8](unsafeAddr value.blobValue[0]),
        value.blobValue.len.csize_t)
  of dvNull:
    result = libsqlNull()

proc fromRawValue(value: LibsqlValue): DbValue =
  case value.valueType
  of libsqlTypeInteger:
    result = DbValue(kind: dvInteger, intValue: value.value.integer)
  of libsqlTypeReal:
    result = DbValue(kind: dvReal, realValue: value.value.real)
  of libsqlTypeText:
    result = DbValue(kind: dvText, textValue: sliceToString(value.value.text))
  of libsqlTypeBlob:
    result = DbValue(kind: dvBlob, blobValue: sliceToBytes(value.value.blob))
  of libsqlTypeNull:
    result = DbValue(kind: dvNull)
  else:
    raise newException(DbError, "unsupported libSQL value type: " &
      $value.valueType)

proc localDatabase*(path: string): DatabaseConfig =
  DatabaseConfig(path: path)

proc memoryDatabase*(): DatabaseConfig =
  DatabaseConfig(path: ":memory:")

proc openDatabase*(config: DatabaseConfig): Database =
  ensureLibsqlSetup()
  let desc = LibsqlDatabaseDesc(
    path: config.path.cstring,
    cypher: libsqlCypherDefault
  )
  result.handle = libsqlDatabaseInit(desc)
  raiseIfError(result.handle.err)

proc close*(db: var Database) =
  if db.handle.inner != nil:
    libsqlDatabaseDeinit(db.handle)
    db.handle = default(LibsqlDatabaseHandle)

proc sync*(db: Database) =
  let syncResult = libsqlDatabaseSync(db.handle)
  raiseIfError(syncResult.err)

proc connect*(db: Database): Connection =
  result.handle = libsqlDatabaseConnect(db.handle)
  raiseIfError(result.handle.err)

proc close*(conn: var Connection) =
  if conn.handle.inner != nil:
    libsqlConnectionDeinit(conn.handle)
    conn.handle = default(LibsqlConnectionHandle)

proc connectionInfo(connHandle: LibsqlConnectionHandle): ExecResult =
  let info = libsqlConnectionInfoGet(connHandle)
  raiseIfError(info.err)
  result.lastInsertRowid = info.lastInsertedRowid
  result.totalChanges = info.totalChanges

proc beginTransaction*(conn: Connection): Transaction =
  result.handle = libsqlConnectionTransaction(conn.handle)
  raiseIfError(result.handle.err)
  result.connHandle = conn.handle

proc commit*(tx: var Transaction) =
  if not tx.finished and tx.handle.inner != nil:
    libsqlTransactionCommit(tx.handle)
    tx.finished = true
    tx.handle = default(LibsqlTransactionHandle)

proc rollback*(tx: var Transaction) =
  if not tx.finished and tx.handle.inner != nil:
    libsqlTransactionRollback(tx.handle)
    tx.finished = true
    tx.handle = default(LibsqlTransactionHandle)

proc prepare*(conn: Connection; sql: string): Statement =
  result.handle = libsqlConnectionPrepare(conn.handle, sql.cstring)
  raiseIfError(result.handle.err)
  result.connHandle = conn.handle

proc prepare*(tx: Transaction; sql: string): Statement =
  result.handle = libsqlTransactionPrepare(tx.handle, sql.cstring)
  raiseIfError(result.handle.err)
  result.connHandle = tx.connHandle

proc finalize*(stmt: var Statement) =
  if stmt.handle.inner != nil:
    libsqlStatementDeinit(stmt.handle)
    stmt.handle = default(LibsqlStatementHandle)
    stmt.boundValues.setLen(0)

proc reset*(stmt: var Statement) =
  libsqlStatementReset(stmt.handle)
  stmt.boundValues.setLen(0)

proc columnCount*(stmt: Statement): int =
  int(libsqlStatementColumnCount(stmt.handle))

proc bindParam*(stmt: var Statement; value: DbValue) =
  stmt.boundValues.add(value)
  let bindResult = libsqlStatementBindValue(stmt.handle,
    toRawValue(stmt.boundValues[^1]))
  raiseIfError(bindResult.err)

proc bindParam*(stmt: var Statement; name: string; value: DbValue) =
  stmt.boundValues.add(value)
  let bindResult = libsqlStatementBindNamed(stmt.handle, name.cstring,
    toRawValue(stmt.boundValues[^1]))
  raiseIfError(bindResult.err)

proc bindParam*[T](stmt: var Statement; value: T) =
  bindParam(stmt, toDbValue(value))

proc bindParam*[T](stmt: var Statement; name: string; value: T) =
  bindParam(stmt, name, toDbValue(value))

proc execute*(stmt: var Statement): ExecResult =
  let executeResult = libsqlStatementExecute(stmt.handle)
  raiseIfError(executeResult.err)
  result.rowsChanged = executeResult.rowsChanged
  let info = connectionInfo(stmt.connHandle)
  result.lastInsertRowid = info.lastInsertRowid
  result.totalChanges = info.totalChanges

proc query*(stmt: var Statement): Rows =
  result.handle = libsqlStatementQuery(stmt.handle)
  raiseIfError(result.handle.err)
  let count = int(libsqlRowsColumnCount(result.handle))
  result.columnNames = newSeq[string](count)
  for index in 0..<count:
    let nameSlice = libsqlRowsColumnName(result.handle, int32(index))
    result.columnNames[index] = sliceToString(nameSlice)
    libsqlSliceDeinit(nameSlice)

proc close*(rows: var Rows) =
  if rows.handle.inner != nil:
    libsqlRowsDeinit(rows.handle)
    rows.handle = default(LibsqlRowsHandle)
    rows.columnNames.setLen(0)

proc next*(rows: var Rows): Option[Row] =
  let rowHandle = libsqlRowsNext(rows.handle)
  raiseIfError(rowHandle.err)
  if rowHandle.inner == nil:
    return none(Row)
  if libsqlRowEmpty(rowHandle):
    return none(Row)

  var row = Row(columnNames: rows.columnNames, values: @[])
  let count = int(libsqlRowLength(rowHandle))
  row.values = newSeq[DbValue](count)
  for index in 0..<count:
    let valueResult = libsqlRowValue(rowHandle, int32(index))
    if valueResult.err != nil:
      libsqlRowDeinit(rowHandle)
      raiseIfError(valueResult.err)
    row.values[index] = fromRawValue(valueResult.ok)
  libsqlRowDeinit(rowHandle)
  result = some(row)

iterator items*(rows: var Rows): Row =
  var maybeRow = next(rows)
  while maybeRow.isSome:
    yield maybeRow.get
    maybeRow = next(rows)

proc toDbValue*(value: DbValue): DbValue =
  value

proc toDbValue*(value: int): DbValue =
  DbValue(kind: dvInteger, intValue: int64(value))
proc toDbValue*(value: int64): DbValue =
  DbValue(kind: dvInteger, intValue: value)
proc toDbValue*(value: int32): DbValue =
  DbValue(kind: dvInteger, intValue: int64(value))
proc toDbValue*(value: uint64): DbValue =
  DbValue(kind: dvInteger, intValue: int64(value))
proc toDbValue*(value: float64): DbValue =
  DbValue(kind: dvReal, realValue: value)
proc toDbValue*(value: bool): DbValue =
  DbValue(kind: dvInteger, intValue: (if value: 1 else: 0))
proc toDbValue*(value: string): DbValue =
  DbValue(kind: dvText, textValue: value)
proc toDbValue*(value: seq[byte]): DbValue =
  DbValue(kind: dvBlob, blobValue: value)
proc toDbValue*[T](value: Option[T]): DbValue =
  if value.isSome:
    result = toDbValue(value.get)
  else:
    result = DbValue(kind: dvNull)

template `%!`*(value: untyped): DbValue =
  toDbValue(value)

template dbValue*(value: untyped): DbValue =
  toDbValue(value)

proc nullValue*(): DbValue =
  DbValue(kind: dvNull)

proc exec*(conn: Connection; sql: string; params: varargs[DbValue, `%!`]): ExecResult =
  if params.len == 0:
    let batchResult = libsqlConnectionBatch(conn.handle, sql.cstring)
    raiseIfError(batchResult.err)
    result = connectionInfo(conn.handle)
  else:
    var stmt = prepare(conn, sql)
    try:
      for value in params:
        bindParam(stmt, value)
      result = execute(stmt)
    finally:
      finalize(stmt)

proc exec*(tx: Transaction; sql: string; params: varargs[DbValue, `%!`]): ExecResult =
  if params.len == 0:
    let batchResult = libsqlTransactionBatch(tx.handle, sql.cstring)
    raiseIfError(batchResult.err)
    result = connectionInfo(tx.connHandle)
  else:
    var stmt = prepare(tx, sql)
    try:
      for value in params:
        bindParam(stmt, value)
      result = execute(stmt)
    finally:
      finalize(stmt)

proc query*(conn: Connection; sql: string; params: varargs[DbValue, `%!`]): seq[Row] =
  var stmt = prepare(conn, sql)
  try:
    for value in params:
      bindParam(stmt, value)
    var rows = query(stmt)
    try:
      for row in rows:
        result.add(row)
    finally:
      close(rows)
  finally:
    finalize(stmt)

proc `[]`*(row: Row; index: int): DbValue =
  if index < 0 or index >= row.values.len:
    raise newException(IndexDefect, "column index out of bounds")
  row.values[index]

proc hasColumn*(row: Row; name: string): bool =
  for columnName in row.columnNames:
    if columnName == name:
      return true
  result = false

proc `[]`*(row: Row; name: string): DbValue =
  for index, columnName in row.columnNames:
    if columnName == name:
      return row.values[index]
  raise newException(KeyError, "unknown column: " & name)

proc len*(row: Row): int =
  row.values.len

proc isNull*(value: DbValue): bool =
  value.kind == dvNull

proc getInt*(value: DbValue): int64 =
  case value.kind
  of dvInteger:
    result = value.intValue
  of dvReal:
    result = int64(value.realValue)
  else:
    raise newException(DbError, "value is not numeric")

proc getFloat*(value: DbValue): float64 =
  case value.kind
  of dvInteger:
    result = float64(value.intValue)
  of dvReal:
    result = value.realValue
  else:
    raise newException(DbError, "value is not numeric")

proc getString*(value: DbValue): string =
  case value.kind
  of dvText:
    result = value.textValue
  of dvInteger:
    result = $value.intValue
  of dvReal:
    result = $value.realValue
  of dvNull:
    result = ""
  of dvBlob:
    raise newException(DbError, "value is a blob")

proc getBlob*(value: DbValue): seq[byte] =
  if value.kind != dvBlob:
    raise newException(DbError, "value is not a blob")
  value.blobValue

proc assignDbValue*[T](dest: var T; value: DbValue) =
  when T is Option:
    type Inner = typeof(default(T).get)
    if value.isNull:
      dest = none(Inner)
    else:
      var inner: Inner
      assignDbValue(inner, value)
      dest = some(inner)
  elif T is bool:
    case value.kind
    of dvInteger:
      dest = value.intValue != 0
    of dvReal:
      dest = value.realValue != 0
    of dvText:
      let normalized = value.textValue.toLowerAscii
      if normalized == "true" or normalized == "1":
        dest = true
      elif normalized == "false" or normalized == "0":
        dest = false
      else:
        raise newException(DbError, "cannot scan bool from " & value.textValue)
    of dvBlob, dvNull:
      raise newException(DbError, "cannot scan bool from database value")
  elif T is SomeInteger:
    case value.kind
    of dvInteger:
      dest = T(value.intValue)
    of dvReal:
      dest = T(int64(value.realValue))
    of dvText:
      dest = T(parseInt(value.textValue))
    of dvBlob, dvNull:
      raise newException(DbError, "cannot scan integer from database value")
  elif T is SomeFloat:
    case value.kind
    of dvInteger:
      dest = T(value.intValue)
    of dvReal:
      dest = T(value.realValue)
    of dvText:
      dest = T(parseFloat(value.textValue))
    of dvBlob, dvNull:
      raise newException(DbError, "cannot scan float from database value")
  elif T is string:
    if value.kind == dvNull:
      dest = ""
    else:
      dest = getString(value)
  elif T is seq[byte]:
    dest = getBlob(value)
  else:
    {.error: "unsupported database scan type".}

proc `$`*(value: DbValue): string =
  case value.kind
  of dvInteger:
    $value.intValue
  of dvReal:
    $value.realValue
  of dvText:
    value.textValue
  of dvBlob:
    "BLOB(" & $value.blobValue.len & " bytes)"
  of dvNull:
    "NULL"
