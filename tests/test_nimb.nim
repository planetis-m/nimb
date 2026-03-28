import std/[options, unittest]

import nimb

type
  User {.dbTable: "users".} = object
    id {.dbPk, dbAutoInc.}: int64
    name: string
    email {.dbColumn: "email_address".}: string
    age: Option[int]
    active: bool

  SearchChunk {.dbTable: "search_chunks".} = object
    id {.dbPk, dbAutoInc.}: int64
    body: string
    embedding {.dbType: "F32_BLOB(4)", dbValueExpr: "vector32(?)".}: Vector32

suite "nimb integration":
  var db: Database
  var conn: Connection

  setup:
    db = openDatabase(memoryDatabase())
    conn = connect(db)
    discard exec(conn, initCreateTable[User]())

  teardown:
    close(conn)
    close(db)

  test "model metadata":
    let info = modelInfo(User)
    check info.tableName == "users"
    check info.primaryKeyField.columnName == "id"
    check info.fieldByName("email").columnName == "email_address"

  test "insert and select with typed mapping":
    discard insert(conn, User(
      name: "Ada",
      email: "ada@example.com",
      age: some(37),
      active: true
    ))

    var q = initSelect[User]()
    where(q, "name = ?", "Ada")
    let user = one[User](conn, q)

    check user.name == "Ada"
    check user.email == "ada@example.com"
    check user.age == some(37)
    check user.active

  test "get by primary key":
    let inserted = insert(conn, User(
      name: "Grace",
      email: "grace@example.com",
      age: none(int),
      active: false
    ))

    let user = getByPk[User, int64](conn, inserted.lastInsertRowid)
    check user.name == "Grace"
    check user.age.isNone

  test "update by primary key":
    let inserted = insert(conn, User(
      name: "Linus",
      email: "linus@example.com",
      age: some(55),
      active: true
    ))

    let current = getByPk[User, int64](conn, inserted.lastInsertRowid)
    var updated = current
    updated.name = "Linus T"
    updated.active = false
    discard update(conn, updated)

    let fetched = getByPk[User, int64](conn, inserted.lastInsertRowid)
    check fetched.name == "Linus T"
    check not fetched.active

  test "delete by primary key":
    let inserted = insert(conn, User(
      name: "Delete Me",
      email: "delete@example.com",
      age: some(1),
      active: true
    ))

    let current = getByPk[User, int64](conn, inserted.lastInsertRowid)
    discard delete(conn, current)

    var q = initSelect[User]()
    where(q, "id = ?", inserted.lastInsertRowid)
    let remaining = all[User](conn, q)
    check remaining.len == 0

  test "explicit query builder rendering":
    var q = initSelect[User]()
    column(q, "id", "name")
    where(q, "active = ?", true)
    orderBy(q, "\"id\" DESC")
    limit(q, 5)

    let rendered = render(q)
    check rendered.sql ==
      "SELECT \"id\", \"name\" FROM \"users\" WHERE active = ? ORDER BY \"id\" DESC LIMIT ?"
    check rendered.params.len == 2

  test "statement lifecycle":
    var stmt = prepare(conn,
      "INSERT INTO users (name, email_address, age, active) VALUES (?, ?, ?, ?)")
    try:
      let execResult = run(stmt,
        "Manual",
        "manual@example.com",
        12,
        true)
      check execResult.rowsChanged == 1
    finally:
      finalize(stmt)

    let rows = query(conn, "SELECT name FROM users WHERE email_address = ?",
      "manual@example.com")
    check rows.len == 1
    check rows[0]["name"].getString == "Manual"

  test "custom write expressions render in insert queries":
    let chunk = SearchChunk(
      body: "Local replicas reduce tail latency.",
      embedding: vector32([0.91, 0.09, 0.05, 0.01])
    )
    let rendered = render(initInsert(chunk))
    check rendered.sql ==
      "INSERT INTO \"search_chunks\" (\"body\", \"embedding\") VALUES (?, vector32(?))"
    check rendered.params.len == 2
