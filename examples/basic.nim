import nimb
import std/[strformat, with]

type
  Account = object
    id: int64
    name: string
    plan: string
    status: string
    monthlySpendCents: int

  Invoice = object
    id: int64
    accountId: int64
    description: string
    totalCents: int
    paid: bool

proc initAccountModel(): Model[Account] =
  result = initModel(Account)
  useTable(result, "accounts")
  mapField(result, "id", primaryKey = true, autoIncrement = true)
  mapField(result, "monthlySpendCents", columnName = "monthly_spend_cents")

proc initInvoiceModel(): Model[Invoice] =
  result = initModel(Invoice)
  useTable(result, "invoices")
  mapField(result, "id", primaryKey = true, autoIncrement = true)
  mapField(result, "accountId", columnName = "account_id")
  mapField(result, "totalCents", columnName = "total_cents")

let accountModel = initAccountModel()
let invoiceModel = initInvoiceModel()

var db = openDatabase(memoryDatabase())
var conn = connect(db)

discard exec(conn, initCreateTable(accountModel))
discard exec(conn, initCreateTable(invoiceModel))

discard insert(conn, accountModel, Account(
  name: "Acme Logistics",
  plan: "growth",
  status: "active",
  monthlySpendCents: 18900
))
discard insert(conn, accountModel, Account(
  name: "Northwind Research",
  plan: "starter",
  status: "trial",
  monthlySpendCents: 0
))

let invoiceId = insert(conn, invoiceModel, Invoice(
  accountId: 1,
  description: "March usage overage",
  totalCents: 4900,
  paid: false
)).lastInsertRowid

var activeAccounts = initSelect(accountModel)
with activeAccounts:
  where "status = ?", "active"
  orderBy "\"name\" ASC"

echo "Active accounts:"
for account in all[Account](conn, activeAccounts):
  let monthlySpend = float(account.monthlySpendCents) / 100.0
  echo &"  {account.name} [{account.plan}] spend=${monthlySpend:.2f}"

var acme = getByPk(conn, accountModel, 1'i64)
with acme:
  plan = "scale"
  monthlySpendCents = 23800
discard update(conn, accountModel, acme)

var tx = beginTransaction(conn)
try:
  discard exec(tx, "UPDATE invoices SET paid = ? WHERE id = ?", true, invoiceId)
  discard exec(tx, """
    UPDATE accounts
    SET monthly_spend_cents = monthly_spend_cents + ?
    WHERE id = ?
  """, 4900, 1)
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
  let accountName = row["name"].getString
  let revenue = row["recognized_revenue_cents"].getInt
  echo &"  {accountName}: ${revenue.float / 100.0:.2f}"

close(conn)
close(db)
