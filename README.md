# nimb

`nimb` is a SQL-first Nim ORM for libSQL that keeps the SQL visible, the model
mapping small, and the query composition procedural.

It takes architectural inspiration from Bun, but the surface is adapted to
idiomatic Nim: `std/with`, explicit query objects, explicit parameter values,
and no fluent method chains.

## Why Try It?

- SQL stays in charge. You can build typed CRUD queries, drop to raw SQL, and
  mix both in the same workflow without fighting the library.
- Nim code stays readable. Query building works well with `std/with`, so query
  setup reads like a short block instead of a chain of calls.
- Model mapping is lightweight. Use pragmas for table names, columns, and keys,
  then let `insert`, `update`, `delete`, and `getByPk` handle the routine work.
- Parameter binding is explicit. Public vararg APIs use `%!` to turn values into
  `DbValue`, so parameter conversion is visible at the call site.
- libSQL-native features still fit. You can use vector search, `vector_top_k`,
  and `libsql_vector_idx` directly without waiting for a special ORM abstraction.
- Native dependency setup is simple in this repo. The required libSQL header and
  shared library are vendored under `third_party/libsql-c`.

## Install

Requirements:

- Nim 2.3+
- Linux `x86_64` for the currently vendored `liblibsql.so`

This repository already vendors the libSQL C header and shared object, so there
is no separate system install step for the included examples and tests.

For local use from the repo root:

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
more realistic account + invoice flow:

- schema creation from Nim models
- typed inserts and `getByPk`
- object updates with `with model:`
- transactional SQL for state changes
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

- prepared statement seeding
- explicit binding with `%!`
- report-style joins using `initSelectRaw()`
- typed incident update after triage

```nim
with incidentStmt:
  reset()
  bindParam (%!incident[0])
  bindParam (%!incident[1])
  bindParam (%!incident[2])
  bindParam (%!incident[3])
  bindParam (%!incident[4])
discard execute(incidentStmt)
```

### AI and Embeddings

[examples/embeddings.nim](/home/ageralis/Projects/nimb/examples/embeddings.nim)
covers Turso/libSQL vector search directly on top of the same connection and
query APIs:

- `F32_BLOB` vector column
- `vector32(...)` inserts
- `libsql_vector_idx(...)` index creation
- `vector_top_k(...)` nearest-neighbor lookup

```nim
var nearest = initSelectRaw()
with nearest:
  tableExpr """
    vector_top_k('support_chunks_idx', ?, 3) hits
    JOIN support_chunks c ON c.rowid = hits.id
  """, "[0.90, 0.08, 0.06, 0.01]"
  columnExpr "c.doc_id"
  columnExpr "c.section"
  columnExpr "c.body"
  columnExpr "vector_distance_cos(c.embedding, vector32('[0.90, 0.08, 0.06, 0.01]')) AS distance"
  orderBy "distance ASC"
```

This example matches Turso’s AI & Embeddings feature set:
https://docs.turso.tech/features/ai-and-embeddings

## API Cheat Sheet

- Database lifecycle:
  `openDatabase`, `localDatabase`, `memoryDatabase`, `connect`, `close`
- Model pragmas:
  `dbTable`, `dbColumn`, `dbPk`, `dbAutoInc`, `dbNull`, `dbDefault`, `dbIgnore`
- Query constructors:
  `initSelect[T]`, `initSelectRaw`, `initInsert`, `initUpdate`, `initDelete`,
  `initCreateTable`, `initDropTable`
- Query composition:
  `tableExpr`, `column`, `columnExpr`, `where`, `join`, `groupBy`, `having`,
  `orderBy`, `limit`, `offset`
- Typed helpers:
  `insert`, `update`, `delete`, `getByPk`, `all`, `one`, `rows`
- Lower-level execution:
  `prepare`, `bindParam`, `execute`, `query`, `beginTransaction`,
  `commit`, `rollback`
- Parameter conversion:
  `%!value` or `toDbValue(value)`

## Run Examples and Tests

```bash
nim c -r examples/basic.nim
nim c -r examples/incidents.nim
nim c -r examples/embeddings.nim
nim c tests/test_nimb.nim && ./tests/test_nimb
```

## Status

Current scope is intentionally lean:

- local file and in-memory databases
- minimal raw bindings over libSQL C
- explicit query builders
- pragma-based model metadata
- CRUD helpers and row mapping
- raw access to libSQL-specific SQL features like vector search

## Inspiration

`nimb` is architecturally inspired by Bun’s SQL-first ORM design, adapted to
Nim’s procedural style and libSQL.
