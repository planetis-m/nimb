when defined(windows):
  const defaultLibsqlDynlib = "third_party/libsql-c/lib/liblibsql.dll"
elif defined(macosx):
  const defaultLibsqlDynlib = "third_party/libsql-c/lib/liblibsql.dylib"
else:
  const defaultLibsqlDynlib = "third_party/libsql-c/lib/liblibsql.so"

const libsqlDynlib* {.strdefine.} = defaultLibsqlDynlib

{.passc: "-Ithird_party/libsql-c/include".}
{.passl: "-Lthird_party/libsql-c/lib -llibsql -Wl,-rpath,\\$ORIGIN/../third_party/libsql-c/lib".}
{.push cdecl, dynlib: libsqlDynlib, header: "libsql.h".}

type
  LibsqlErrorObj* {.importc: "libsql_error_t", incompleteStruct.} = object
  LibsqlError* = ptr LibsqlErrorObj

  LibsqlCypher* = cint
  LibsqlType* = cint
  LibsqlTracingLevel* = cint

const
  libsqlCypherDefault* = 0.cint
  libsqlCypherAes256* = 1.cint

  libsqlTypeInteger* = 1.cint
  libsqlTypeReal* = 2.cint
  libsqlTypeText* = 3.cint
  libsqlTypeBlob* = 4.cint
  libsqlTypeNull* = 5.cint

  libsqlTracingLevelError* = 1.cint
  libsqlTracingLevelWarn* = 2.cint
  libsqlTracingLevelInfo* = 3.cint
  libsqlTracingLevelDebug* = 4.cint
  libsqlTracingLevelTrace* = 5.cint

type
  LibsqlLog* {.importc: "libsql_log_t", bycopy.} = object
    message* {.importc: "message".}: cstring
    target* {.importc: "target".}: cstring
    file* {.importc: "file".}: cstring
    timestamp* {.importc: "timestamp".}: uint64
    line* {.importc: "line".}: csize_t
    level* {.importc: "level".}: LibsqlTracingLevel

  LibsqlDatabaseHandle* {.importc: "libsql_database_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError
    inner* {.importc: "inner".}: pointer

  LibsqlConnectionHandle* {.importc: "libsql_connection_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError
    inner* {.importc: "inner".}: pointer

  LibsqlStatementHandle* {.importc: "libsql_statement_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError
    inner* {.importc: "inner".}: pointer

  LibsqlTransactionHandle* {.importc: "libsql_transaction_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError
    inner* {.importc: "inner".}: pointer

  LibsqlRowsHandle* {.importc: "libsql_rows_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError
    inner* {.importc: "inner".}: pointer

  LibsqlRowHandle* {.importc: "libsql_row_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError
    inner* {.importc: "inner".}: pointer

  LibsqlBatchResult* {.importc: "libsql_batch_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError

  LibsqlSlice* {.importc: "libsql_slice_t", bycopy.} = object
    data* {.importc: "ptr".}: pointer
    len* {.importc: "len".}: csize_t

  LibsqlValueUnion* {.importc: "libsql_value_union_t", union, bycopy.} = object
    integer* {.importc: "integer".}: int64
    real* {.importc: "real".}: cdouble
    text* {.importc: "text".}: LibsqlSlice
    blob* {.importc: "blob".}: LibsqlSlice

  LibsqlValue* {.importc: "libsql_value_t", bycopy.} = object
    value* {.importc: "value".}: LibsqlValueUnion
    valueType* {.importc: "type".}: LibsqlType

  LibsqlResultValue* {.importc: "libsql_result_value_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError
    ok* {.importc: "ok".}: LibsqlValue

  LibsqlSyncResult* {.importc: "libsql_sync_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError
    frameNo* {.importc: "frame_no".}: uint64
    framesSynced* {.importc: "frames_synced".}: uint64

  LibsqlBindResult* {.importc: "libsql_bind_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError

  LibsqlExecuteResult* {.importc: "libsql_execute_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError
    rowsChanged* {.importc: "rows_changed".}: uint64

  LibsqlConnectionInfo* {.importc: "libsql_connection_info_t", bycopy.} = object
    err* {.importc: "err".}: LibsqlError
    lastInsertedRowid* {.importc: "last_inserted_rowid".}: int64
    totalChanges* {.importc: "total_changes".}: uint64

  LibsqlDatabaseDesc* {.importc: "libsql_database_desc_t", bycopy.} = object
    url* {.importc: "url".}: cstring
    path* {.importc: "path".}: cstring
    authToken* {.importc: "auth_token".}: cstring
    encryptionKey* {.importc: "encryption_key".}: cstring
    syncInterval* {.importc: "sync_interval".}: uint64
    cypher* {.importc: "cypher".}: LibsqlCypher
    disableReadYourWrites* {.importc: "disable_read_your_writes".}: bool
    webpki* {.importc: "webpki".}: bool
    synced* {.importc: "synced".}: bool
    disableSafetyAssert* {.importc: "disable_safety_assert".}: bool
    namespaceName* {.importc: "namespace".}: cstring

  LibsqlConfig* {.importc: "libsql_config_t", bycopy.} = object
    logger* {.importc: "logger".}: proc(log: LibsqlLog) {.cdecl.}
    version* {.importc: "version".}: cstring

proc libsqlSetup*(config: LibsqlConfig): LibsqlError {.importc: "libsql_setup".}
proc libsqlErrorMessage*(self: LibsqlError): cstring {.importc: "libsql_error_message".}
proc libsqlErrorDeinit*(self: LibsqlError) {.importc: "libsql_error_deinit".}
proc libsqlDatabaseInit*(desc: LibsqlDatabaseDesc): LibsqlDatabaseHandle {.importc: "libsql_database_init".}
proc libsqlDatabaseSync*(self: LibsqlDatabaseHandle): LibsqlSyncResult {.importc: "libsql_database_sync".}
proc libsqlDatabaseConnect*(self: LibsqlDatabaseHandle): LibsqlConnectionHandle {.importc: "libsql_database_connect".}
proc libsqlDatabaseDeinit*(self: LibsqlDatabaseHandle) {.importc: "libsql_database_deinit".}
proc libsqlConnectionTransaction*(self: LibsqlConnectionHandle): LibsqlTransactionHandle {.importc: "libsql_connection_transaction".}
proc libsqlConnectionBatch*(self: LibsqlConnectionHandle; sql: cstring): LibsqlBatchResult {.importc: "libsql_connection_batch".}
proc libsqlConnectionInfoGet*(self: LibsqlConnectionHandle): LibsqlConnectionInfo {.importc: "libsql_connection_info".}
proc libsqlConnectionPrepare*(self: LibsqlConnectionHandle; sql: cstring): LibsqlStatementHandle {.importc: "libsql_connection_prepare".}
proc libsqlConnectionDeinit*(self: LibsqlConnectionHandle) {.importc: "libsql_connection_deinit".}
proc libsqlTransactionBatch*(self: LibsqlTransactionHandle; sql: cstring): LibsqlBatchResult {.importc: "libsql_transaction_batch".}
proc libsqlTransactionPrepare*(self: LibsqlTransactionHandle; sql: cstring): LibsqlStatementHandle {.importc: "libsql_transaction_prepare".}
proc libsqlTransactionCommit*(self: LibsqlTransactionHandle) {.importc: "libsql_transaction_commit".}
proc libsqlTransactionRollback*(self: LibsqlTransactionHandle) {.importc: "libsql_transaction_rollback".}
proc libsqlStatementExecute*(self: LibsqlStatementHandle): LibsqlExecuteResult {.importc: "libsql_statement_execute".}
proc libsqlStatementQuery*(self: LibsqlStatementHandle): LibsqlRowsHandle {.importc: "libsql_statement_query".}
proc libsqlStatementReset*(self: LibsqlStatementHandle) {.importc: "libsql_statement_reset".}
proc libsqlStatementColumnCount*(self: LibsqlStatementHandle): csize_t {.importc: "libsql_statement_column_count".}
proc libsqlStatementBindNamed*(self: LibsqlStatementHandle; name: cstring; value: LibsqlValue): LibsqlBindResult {.importc: "libsql_statement_bind_named".}
proc libsqlStatementBindValue*(self: LibsqlStatementHandle; value: LibsqlValue): LibsqlBindResult {.importc: "libsql_statement_bind_value".}
proc libsqlStatementDeinit*(self: LibsqlStatementHandle) {.importc: "libsql_statement_deinit".}
proc libsqlRowsNext*(self: LibsqlRowsHandle): LibsqlRowHandle {.importc: "libsql_rows_next".}
proc libsqlRowsColumnName*(self: LibsqlRowsHandle; index: int32): LibsqlSlice {.importc: "libsql_rows_column_name".}
proc libsqlRowsColumnCount*(self: LibsqlRowsHandle): int32 {.importc: "libsql_rows_column_count".}
proc libsqlRowsDeinit*(self: LibsqlRowsHandle) {.importc: "libsql_rows_deinit".}
proc libsqlRowValue*(self: LibsqlRowHandle; index: int32): LibsqlResultValue {.importc: "libsql_row_value".}
proc libsqlRowLength*(self: LibsqlRowHandle): int32 {.importc: "libsql_row_length".}
proc libsqlRowEmpty*(self: LibsqlRowHandle): bool {.importc: "libsql_row_empty".}
proc libsqlRowDeinit*(self: LibsqlRowHandle) {.importc: "libsql_row_deinit".}
proc libsqlInteger*(integer: int64): LibsqlValue {.importc: "libsql_integer".}
proc libsqlReal*(real: cdouble): LibsqlValue {.importc: "libsql_real".}
proc libsqlText*(textPtr: cstring; len: csize_t): LibsqlValue {.importc: "libsql_text".}
proc libsqlBlob*(blobPtr: ptr uint8; len: csize_t): LibsqlValue {.importc: "libsql_blob".}
proc libsqlNull*(): LibsqlValue {.importc: "libsql_null".}
proc libsqlSliceDeinit*(value: LibsqlSlice) {.importc: "libsql_slice_deinit".}

{.pop.}
