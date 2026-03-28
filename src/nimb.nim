import std/options

import nimb/[db, model, query, sql]

export db, model, query, sql

proc execRendered(conn: Connection; rendered: RenderedQuery): ExecResult =
  if rendered.params.len == 0:
    result = db.exec(conn, rendered.sql)
  else:
    var stmt = prepare(conn, rendered.sql)
    try:
      for value in rendered.params:
        bindParam(stmt, value)
      result = execute(stmt)
    finally:
      finalize(stmt)

proc queryRendered(conn: Connection; rendered: RenderedQuery): seq[Row] =
  if rendered.params.len == 0:
    result = db.query(conn, rendered.sql)
  else:
    var stmt = prepare(conn, rendered.sql)
    try:
      for value in rendered.params:
        bindParam(stmt, value)
      var rows = query(stmt)
      try:
        for row in rows:
          result.add(row)
      finally:
        close(rows)
    finally:
      finalize(stmt)

proc exec*(conn: Connection; q: InsertQuery): ExecResult =
  let rendered = render(q)
  execRendered(conn, rendered)

proc exec*(conn: Connection; q: UpdateQuery): ExecResult =
  let rendered = render(q)
  execRendered(conn, rendered)

proc exec*(conn: Connection; q: DeleteQuery): ExecResult =
  let rendered = render(q)
  execRendered(conn, rendered)

proc exec*(conn: Connection; q: CreateTableQuery): ExecResult =
  let rendered = render(q)
  execRendered(conn, rendered)

proc exec*(conn: Connection; q: DropTableQuery): ExecResult =
  let rendered = render(q)
  execRendered(conn, rendered)

proc rows*(conn: Connection; q: SelectQuery): seq[Row] =
  let rendered = render(q)
  queryRendered(conn, rendered)

proc all*[T](conn: Connection; q: SelectQuery): seq[T] =
  for row in rows(conn, q):
    result.add(fromRow[T](row))

proc one*[T](conn: Connection; q: SelectQuery): T =
  let values = all[T](conn, q)
  if values.len == 0:
    raise newException(DbError, "query returned no rows")
  result = values[0]

proc scanOne*[T](conn: Connection; q: SelectQuery; dest: var T) =
  dest = one[T](conn, q)

proc scanAll*[T](conn: Connection; q: SelectQuery; dest: var seq[T]) =
  dest = all[T](conn, q)

proc insert*[T](conn: Connection; value: T): ExecResult =
  var q = initInsert(value)
  result = exec(conn, q)

proc update*[T](conn: Connection; value: T): ExecResult =
  var q = initUpdate(value)
  result = exec(conn, q)

proc delete*[T](conn: Connection; value: T): ExecResult =
  var q = initDelete(value)
  result = exec(conn, q)

proc getByPk*[T, K](conn: Connection; primaryKey: K): T =
  let info = modelInfo(T)
  let pkField = primaryKeyField(info)
  var q = initSelect[T]()
  where(q, quoteIdent(pkField.columnName) & " = ?", primaryKey)
  limit(q, 1)
  result = one[T](conn, q)
