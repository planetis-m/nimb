# nimb

`nimb` is a SQL-first Nim ORM for libSQL. It keeps SQL visible, model mapping
small, and query composition procedural.

It takes architectural inspiration from Bun, but the public surface is adapted
to Nim: `std/with`, explicit query objects, prepared statements when you want
them, and no fluent method chains.

## Why Try It?

- SQL stays in charge. You can build typed CRUD queries, drop to raw SQL, and
  mix both in the same workflow.
- Nim code stays readable. Query composition works naturally with `std/with`
  and small procedural blocks.
- Model mapping stays light. Table names, columns, and keys come from pragmas,
  not a heavy schema DSL.
- Public vararg APIs accept normal Nim values directly. `exec`, `where`,
  `tableExpr`, `run`, and `fetch` all call `toDbValue` through the `!?`
  adapter internally, so you usually do not write conversions by hand.
- Prepared statements are less noisy now. Reusable statements support
  `bindParams`, `run`, and `fetch` instead of repeated `bindParam` calls.
- libSQL-native features still fit. Vector search, `vector_top_k`, and
  `libsql_vector_idx` are exposed through a small typed helper layer.
- This repo is self-contained for local use. The required libSQL header and
  shared library are vendored under `third_party/libsql-c`.

## Install

Requirements:

- Nim 2.3+
- Linux `x86_64` for the currently vendored `liblibsql.so`

Package metadata is already included in [nimb.nimble](/home/ageralis/Projects/nimb/nimb.nimble).
This repository also includes an MIT [LICENSE](/home/ageralis/Projects/nimb/LICENSE)
under Antonis Geralis, with attribution for the MIT-licensed Nim libSQL
binding used as a reference during implementation.

The libSQL C header and shared object are vendored locally, so the examples and
tests do not depend on `../../libsql-c` or a separate system install step.

From the repo root:

```bash
nim c -r examples/basic.nim
```

## Quick Start

```nim
import nimb
import std/[strformat, with]

type
  Account {.dbTable: "accounts".} = object
    id {.dbPk, dbAutoInc.}: int64
    name: string
    plan: string
    status: string

var db = openDatabase(localDatabase("ops.db"))
var conn = connect(db)

discard exec(conn, initCreateTable[Account]())
discard insert(conn, Account(
  name: "Acme Logistics",
  plan: "growth",
  status: "active"
))

var q = initSelect[Account]()
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

[examples/basic.nim](/home/ageralis/Projects/nimb/examples/basic.nim) shows a
more realistic account and invoice flow:

- schema creation from Nim models
- typed inserts and `getByPk`
- object updates with `with model:`
- explicit transaction handling
- revenue reporting with an ad hoc query

```nim
var activeAccounts = initSelect[Account]()
with activeAccounts:
  where "status = ?", "active"
  orderBy "\"name\" ASC"

var acme = getByPk[Account, int64](conn, 1)
with acme:
  plan = "scale"
  monthlySpendCents = 23800
discard update(conn, acme)
```

### Operational Reporting

[examples/incidents.nim](/home/ageralis/Projects/nimb/examples/incidents.nim)
shows how `nimb` handles read-heavy operational workflows:

- reusable prepared statements
- positional bulk binding with `run`
- report-style joins using `initSelectRaw()`
- typed incident updates after triage

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
covers Turso/libSQL vector search with a typed helper layer on top of the same
connection and query APIs:

- typed `Vector32` values
- explicit `initInsertRaw()` + `valuesExpr(...)` for vector writes
- explicit `F32_BLOB` table DDL
- `createVectorIndex(...)` and `VectorIndexOptions`
- `vectorTopK(...)` and `vectorDistanceCos(...)`
- typed retrieval results mapped back into Nim objects

```nim
type
  RetrievalRequest = object
    product: string
    audience: string
    question: string
    embedding: Vector32

let request = RetrievalRequest(
  product: "database",
  audience: "developers",
  question: "How should I set up a local replica for low-latency reads?",
  embedding: vector32([0.93, 0.07, 0.04, 0.01])
)

var insertChunk = initInsertRaw()
with insertChunk:
  table "support_chunks"
  column "doc_id", "product", "audience", "section", "body", "embedding"
  valuesExpr(
    raw("?", chunk.docId),
    raw("?", chunk.product),
    raw("?", chunk.audience),
    raw("?", chunk.section),
    raw("?", chunk.body),
    vector32Expr(chunk.embedding)
  )

var q = initSelectRaw()
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

This example follows Turso’s AI and Embeddings feature set:
https://docs.turso.tech/features/ai-and-embeddings

## API Cheat Sheet

- Database lifecycle:
  `openDatabase`, `localDatabase`, `memoryDatabase`, `connect`, `close`, `sync`
- Model pragmas:
  `dbTable`, `dbColumn`, `dbPk`, `dbAutoInc`, `dbNull`, `dbDefault`, `dbIgnore`
- Query constructors:
  `initSelect[T]`, `initSelectRaw`, `initInsert`, `initInsertRaw`, `initUpdate`,
  `initDelete`, `initCreateTable`, `initDropTable`
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
- Values and conversion:
  `DbValue`, `toDbValue`, `!?value`, `nullValue`
- Vector support:
  `Vector32`, `vector32`, `vectorColumnType`, `VectorIndexOptions`,
  `createVectorIndex`, `vectorTopK`, `vectorDistanceCos`, `vectorDistanceL2`,
  `vectorExtract`

## Notes

- The explicit `!?` operator exists for places where you want an obvious manual
  conversion to `DbValue`.
- In normal use, you usually do not need to write it. Public vararg APIs call
  `toDbValue` for you.
- The current scope is intentionally lean:
  local and in-memory databases, minimal raw bindings over libSQL C, explicit
  query builders, pragma-based model metadata, CRUD helpers, typed vector
  helpers, and raw access to libSQL-specific SQL features.

## Run Examples and Tests

```bash
nim c -r examples/basic.nim
nim c -r examples/incidents.nim
nim c -r examples/embeddings.nim
nim c tests/test_nimb.nim && ./tests/test_nimb
```

## Inspiration

`nimb` is architecturally inspired by Bun’s SQL-first ORM design, adapted to
Nim’s procedural style and libSQL.
