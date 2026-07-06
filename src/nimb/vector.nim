import std/[strformat, strutils]

import nimb/[db, sql]

type
  Vector32* = object
    values*: seq[float32]

  VectorMetric* = enum
    vmCosine
    vmL2

  VectorIndexOptions* = object
    metric*: VectorMetric
    maxNeighbors*: int
    compressNeighbors*: string
    alpha*: float64
    searchL*: int
    insertL*: int

proc initVectorIndexOptions*(): VectorIndexOptions =
  VectorIndexOptions(metric: vmCosine)

proc vector32*(values: openArray[SomeFloat]): Vector32 =
  result.values = newSeq[float32](values.len)
  for index, value in values:
    result.values[index] = float32(value)

proc dimensions*(value: Vector32): int =
  value.values.len

proc `$`*(value: Vector32): string =
  result = "["
  for index, item in value.values:
    if index > 0:
      result.add(", ")
    result.add(formatFloat(item, ffDecimal, 6))
  result.add("]")

proc toDbValue*(value: Vector32): DbValue =
  DbValue(kind: dvText, textValue: $value)

proc vectorColumnType*(dimensions: int): string =
  &"F32_BLOB({dimensions})"

proc vector32Expr*(value: Vector32): SqlFragment =
  raw("vector32(?)", value)

proc vectorExtract*(columnExpr: string): SqlFragment =
  raw("vector_extract(" & columnExpr & ")")

proc vectorDistanceCos*(columnExpr: string; queryVector: Vector32): SqlFragment =
  raw("vector_distance_cos(" & columnExpr & ", ?)", queryVector)

proc vectorDistanceL2*(columnExpr: string; queryVector: Vector32): SqlFragment =
  raw("vector_distance_l2(" & columnExpr & ", ?)", queryVector)

proc vectorTopK*(indexName: string; queryVector: Vector32; k: int;
    alias = "hits"): SqlFragment =
  raw("vector_top_k(?, ?, ?) AS " & quoteIdent(alias), indexName, queryVector, k)

proc metricName(metric: VectorMetric): string =
  case metric
  of vmCosine:
    result = "cosine"
  of vmL2:
    result = "l2"

proc vectorIndexExpr*(columnExpr: string;
    options = initVectorIndexOptions()): string =
  var settings: seq[string]
  if options.metric != vmCosine:
    settings.add("'metric=" & metricName(options.metric) & "'")
  if options.maxNeighbors > 0:
    settings.add("'max_neighbors=" & $options.maxNeighbors & "'")
  if options.compressNeighbors.len > 0:
    settings.add("'compress_neighbors=" & options.compressNeighbors & "'")
  if options.alpha > 0:
    settings.add("'alpha=" & $options.alpha & "'")
  if options.searchL > 0:
    settings.add("'search_l=" & $options.searchL & "'")
  if options.insertL > 0:
    settings.add("'insert_l=" & $options.insertL & "'")

  result = "libsql_vector_idx(" & columnExpr
  if settings.len > 0:
    result.add(", ")
    result.add(settings.join(", "))
  result.add(")")

proc createVectorIndex*(conn: Connection; indexName, tableName, columnExpr: string;
    options = initVectorIndexOptions()): ExecResult =
  let sql = "CREATE INDEX " & quoteIdent(indexName) & " ON " &
    quoteIdent(tableName) & " (" & vectorIndexExpr(columnExpr, options) & ")"
  result = exec(conn, sql)
