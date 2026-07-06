import std/[options, unittest]

import nimb

type
  User = object
    id: int64
    name: string
    email: string
    age: Option[int]
    active: bool

proc initUserModel(): Model[User] =
  result = initModel(User)
  useTable(result, "users")
  mapField(result, "id", primaryKey = true, autoIncrement = true)
  mapField(result, "email", columnName = "email_address")

let userModel = initUserModel()

suite "nimb integration":
  var db: Database
  var conn: Connection

  setup:
    db = openDatabase(memoryDatabase())
    conn = connect(db)
    discard exec(conn, initCreateTable(userModel))

  teardown:
    close(conn)
    close(db)

  test "model metadata":
    let info = userModel.info
    check info.tableName == "users"
    check info.primaryKeyField.columnName == "id"
    check info.fieldByName("email").columnName == "email_address"

  test "insert and select with typed mapping":
    discard insert(conn, userModel, User(
      name: "Ada",
      email: "ada@example.com",
      age: some(37),
      active: true
    ))

    var q = initSelect(userModel)
    where(q, "name = ?", "Ada")
    let user = one[User](conn, q)

    check user.name == "Ada"
    check user.email == "ada@example.com"
    check user.age == some(37)
    check user.active

  test "get by primary key":
    let inserted = insert(conn, userModel, User(
      name: "Grace",
      email: "grace@example.com",
      age: none(int),
      active: false
    ))

    let user = getByPk(conn, userModel, inserted.lastInsertRowid)
    check user.name == "Grace"
    check user.age.isNone

  test "update by primary key":
    let inserted = insert(conn, userModel, User(
      name: "Linus",
      email: "linus@example.com",
      age: some(55),
      active: true
    ))

    let current = getByPk(conn, userModel, inserted.lastInsertRowid)
    var updated = current
    updated.name = "Linus T"
    updated.active = false
    discard update(conn, userModel, updated)

    let fetched = getByPk(conn, userModel, inserted.lastInsertRowid)
    check fetched.name == "Linus T"
    check not fetched.active

  test "delete by primary key":
    let inserted = insert(conn, userModel, User(
      name: "Delete Me",
      email: "delete@example.com",
      age: some(1),
      active: true
    ))

    let current = getByPk(conn, userModel, inserted.lastInsertRowid)
    discard delete(conn, userModel, current)

    var q = initSelect(userModel)
    where(q, "id = ?", inserted.lastInsertRowid)
    let remaining = all[User](conn, q)
    check remaining.len == 0

  test "explicit query builder rendering":
    var q = initSelect(userModel)
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

  test "insert expressions render in raw insert queries":
    var q = initInsertRaw()
    table(q, "search_chunks")
    column(q, "body", "embedding")
    valuesExpr(q,
      raw("?", "Local replicas reduce tail latency."),
      vector32Expr(vector32([0.91, 0.09, 0.05, 0.01]))
    )
    let rendered = render(q)
    check rendered.sql ==
      "INSERT INTO \"search_chunks\" (\"body\", \"embedding\") VALUES (?, vector32(?))"
    check rendered.params.len == 2
