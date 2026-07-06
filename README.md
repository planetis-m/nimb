# nimb

`nimb` is a SQL-first Nim ORM for libSQL. It keeps SQL visible, model mapping
explicit, and query composition procedural.

The project is architecturally inspired by Bun, but the API is shaped for Nim:
`std/with`, explicit query objects, reusable prepared statements, and no fluent
method chaining.

## Why It Exists

- SQL stays in charge. You can use typed CRUD helpers, raw SQL, or both in the
  same flow.
- Model metadata is explicit. There are no user-defined pragmas. When you need
  custom table or column names, you build a `Model[T]` descriptor and pass it.
- Nim code stays procedural. `initSelect`, `where`, `columnExpr`, `run`, and
  `fetch` are ordinary procs that read cleanly with `std/with`.
- Vector search stays first-class. `Vector32`, `vectorTopK`, `vectorDistanceCos`,
  and `createVectorIndex` cover libSQL/Turso embeddings features without hiding
  the SQL underneath.
- The repo is self-contained. The required `libsql.h` and `liblibsql.so` are
  vendored under `third_party/libsql-c`.

## Install

Requirements:

- Nim 2.3+
- Linux `x86_64` for the currently vendored `liblibsql.so`

Package metadata is in [nimb.nimble](/home/ageralis/Projects/nimb/nimb.nimble).
The project is MIT licensed in [LICENSE](/home/ageralis/Projects/nimb/LICENSE).

From the repo root:

```bash
nim c -r examples/basic.nim
```

## Metadata Model

If your table and column names follow the defaults, you can use the typed APIs
directly:

- table name: `snake_case(TypeName)`
- column name: `snake_case(fieldName)`
- nullable fields: inferred from `Option[T]`

When you need custom metadata, define a `Model[T]` descriptor:

```nim
import nimb

type
  User = object
    id: int64
    name: string
    email: string

proc initUserModel(): Model[User] =
  result = initModel(User)
  useTable(result, "users")
  mapField(result, "id", primaryKey = true, autoIncrement = true)
  mapField(result, "email", columnName = "email_address")
```

That descriptor is then passed to schema creation, CRUD helpers, and typed
select builders.

## Quick Start

```nim
import nimb
import std/[strformat, with]

type
  Account = object
    id: int64
    name: string
    plan: string
    status: string

proc initAccountModel(): Model[Account] =
  result = initModel(Account)
  useTable(result, "accounts")
  mapField(result, "id", primaryKey = true, autoIncrement = true)

let accountModel = initAccountModel()

var db = openDatabase(localDatabase("ops.db"))
var conn = connect(db)

discard exec(conn, initCreateTable(accountModel))
discard insert(conn, accountModel, Account(
  name: "Acme Logistics",
  plan: "growth",
  status: "active"
))

var q = initSelect(accountModel)
with q:
  where "status = ?", "active"
  orderBy "\"name\" ASC"

for account in all[Account](conn, q):
  echo &"{account.name} [{account.plan}]"

close(conn)
close(db)
```

## Workflows

### Billing and CRUD

[examples/basic.nim](/home/ageralis/Projects/nimb/examples/basic.nim) shows:

- explicit `Model[T]` descriptors for `Account` and `Invoice`
- typed inserts and `getByPk`
- procedural updates with `with model:`
- transaction handling with raw SQL where it is clearer
- ad hoc reporting with `initSelectRaw()`

```nim
var activeAccounts = initSelect(accountModel)
with activeAccounts:
  where "status = ?", "active"
  orderBy "\"name\" ASC"

var acme = getByPk(conn, accountModel, 1'i64)
with acme:
  plan = "scale"
  monthlySpendCents = 23800
discard update(conn, accountModel, acme)
```

### Operational Reporting

[examples/incidents.nim](/home/ageralis/Projects/nimb/examples/incidents.nim)
shows how explicit models and prepared statements fit together:

- model-backed schema creation for `Service` and `Incident`
- reusable prepared inserts with `run`
- report queries built with `initSelectRaw()`
- typed update flow after triage

```nim
var incidentStmt = prepare(conn, """
  INSERT INTO incidents (service_id, summary, severity, status, owner)
  VALUES (?, ?, ?, ?, ?)
""")
try:
  for incident in seedIncidents:
    discard run(incidentStmt,
      incident[0],
      incident[1],
      incident[2],
      incident[3],
      incident[4])
finally:
  finalize(incidentStmt)
```

### AI and Embeddings

[examples/embeddings.nim](/home/ageralis/Projects/nimb/examples/embeddings.nim)
covers libSQL/Turso vector search:

- typed `Vector32` values
- explicit `F32_BLOB` schema
- vector writes through `initInsertRaw()` and `vector32Expr(...)`
- `createVectorIndex(...)` with `VectorIndexOptions`
- nearest-neighbor search via `vectorTopK(...)`
- typed result mapping with a `Model[RetrievedChunk]`

```nim
proc initRetrievedChunkModel(): Model[RetrievedChunk] =
  result = initModel(RetrievedChunk)
  mapField(result, "docId", columnName = "doc_id")

var q = initSelect(retrievedChunkModel)
with q:
  tableExpr vectorTopK("support_chunks_embedding_idx", request.embedding, 4, "hits")
  join "JOIN support_chunks c ON c.rowid = hits.id"
  columnExpr "c.doc_id"
  columnExpr "c.section"
  columnExpr alias(vectorDistanceCos("c.embedding", request.embedding), "distance")
  where "c.product = ?", request.product
  where "c.audience = ?", request.audience
  orderBy "distance ASC"
```

This example follows Turso’s AI and embeddings feature set:
https://docs.turso.tech/features/ai-and-embeddings

## Prepared Statements

You do not need `bindParam` one field at a time unless you want that level of
control. The public lower-level API is:

- `bindParam(stmt, value)`
- `bindParams(stmt, a, b, c)`
- `run(stmt, a, b, c)` for `reset + bind + execute`
- `fetch(stmt, a, b, c)` for `reset + bind + query`

`bindParam` is generic and calls `toDbValue` internally. Public vararg APIs use
the `!?` adapter, so normal Nim values work directly in `exec`, `where`,
`tableExpr`, `run`, and `fetch`.

## API Cheat Sheet

- Database lifecycle:
  `openDatabase`, `localDatabase`, `memoryDatabase`, `connect`, `close`, `sync`
- Model metadata:
  `Model[T]`, `initModel`, `useTable`, `field`, `mapField`
- Query constructors:
  `initSelect[T]`, `initSelect(model)`, `initSelectRaw`, `initInsert`,
  `initInsertRaw`, `initUpdate`, `initDelete`, `initCreateTable`,
  `initDropTable`
- Query composition:
  `tableExpr`, `column`, `columnExpr`, `where`, `join`, `groupBy`, `having`,
  `orderBy`, `limit`, `offset`, `returning`, `values`, `valuesExpr`
- Typed helpers:
  `insert`, `update`, `delete`, `getByPk`, `all`, `one`, `rows`
- Prepared statements:
  `prepare`, `bindParam`, `bindParams`, `run`, `fetch`, `execute`, `query`,
  `finalize`, `reset`
- Transactions:
  `beginTransaction`, `commit`, `rollback`
- Values:
  `DbValue`, `toDbValue`, `!?value`, `nullValue`
- Vector support:
  `Vector32`, `vector32`, `vector32Expr`, `vectorColumnType`,
  `VectorIndexOptions`, `createVectorIndex`, `vectorTopK`,
  `vectorDistanceCos`, `vectorDistanceL2`, `vectorExtract`

## Run Examples and Tests

```bash
nim c -r examples/basic.nim
nim c -r examples/incidents.nim
nim c -r examples/embeddings.nim
nim c -r tests/test_nimb.nim
```

## Inspiration

`nimb` is architecturally inspired by Bun’s SQL-first ORM design, adapted to
Nim’s procedural style and libSQL.
