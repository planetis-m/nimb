import nimb
import std/[strformat, with]

type
  Account {.dbTable: "accounts".} = object
    id {.dbPk, dbAutoInc.}: int64
    name: string
    plan: string
    status: string
    monthlySpendCents {.dbColumn: "monthly_spend_cents".}: int

  Invoice {.dbTable: "invoices".} = object
    id {.dbPk, dbAutoInc.}: int64
    accountId {.dbColumn: "account_id".}: int64
    description: string
    totalCents {.dbColumn: "total_cents".}: int
    paid: bool

var db = openDatabase(memoryDatabase())
var conn = connect(db)

discard exec(conn, initCreateTable[Account]())
discard exec(conn, initCreateTable[Invoice]())

discard insert(conn, Account(
  name: "Acme Logistics",
  plan: "growth",
  status: "active",
  monthlySpendCents: 18900
))
discard insert(conn, Account(
  name: "Northwind Research",
  plan: "starter",
  status: "trial",
  monthlySpendCents: 0
))

let invoiceId = insert(conn, Invoice(
  accountId: 1,
  description: "March usage overage",
  totalCents: 4900,
  paid: false
)).lastInsertRowid

var activeAccounts = initSelect[Account]()
with activeAccounts:
  where "status = ?", "active"
  orderBy "\"name\" ASC"

echo "Active accounts:"
for account in all[Account](conn, activeAccounts):
  echo &"  {account.name} [{account.plan}] spend=${account.monthlySpendCents / 100.0:.2f}"

var acme = getByPk[Account, int64](conn, 1)
with acme:
  plan = "scale"
  monthlySpendCents = 23800
discard update(conn, acme)

var tx = beginTransaction(conn)
try:
  with tx:
    exec "UPDATE invoices SET paid = ? WHERE id = ?", true, invoiceId
    exec """
      UPDATE accounts
      SET monthly_spend_cents = monthly_spend_cents + ?
      WHERE id = ?
    """, 4900, 1
  commit(tx)
except CatchableError:
  rollback(tx)
  raise

var revenueReport = initSelectRaw()
with revenueReport:
  tableExpr """
    invoices i
    join accounts a on a.id = i.account_id
  """
  columnExpr "a.name"
  columnExpr "sum(i.total_cents) as recognized_revenue_cents"
  where "i.paid = ?", true
  groupBy "a.name"
  orderBy "recognized_revenue_cents DESC"

echo "Recognized revenue:"
for row in rows(conn, revenueReport):
  let revenue = row["recognized_revenue_cents"].getInt
  echo &"  {row["name"].getString}: ${revenue.float / 100.0:.2f}"

close(conn)
close(db)
