import nimb
import std/[strformat, with]

type
  Service {.dbTable: "services".} = object
    id {.dbPk, dbAutoInc.}: int64
    name: string
    tier: string
    owner: string

  Incident {.dbTable: "incidents".} = object
    id {.dbPk, dbAutoInc.}: int64
    serviceId {.dbColumn: "service_id".}: int64
    summary: string
    severity: string
    status: string
    owner: string

var db = openDatabase(memoryDatabase())
var conn = connect(db)

discard exec(conn, initCreateTable[Service]())
discard exec(conn, initCreateTable[Incident]())

discard insert(conn, Service(name: "api-gateway", tier: "critical", owner: "platform"))
discard insert(conn, Service(name: "search-indexer", tier: "standard", owner: "data"))

var incidentStmt = prepare(conn, """
  INSERT INTO incidents (service_id, summary, severity, status, owner)
  VALUES (?, ?, ?, ?, ?)
""")
try:
  let seedIncidents = [
    (1'i64, "Elevated 502s on public API", "sev1", "open", "alice"),
    (1'i64, "Retry queue saturation", "sev2", "open", "bob"),
    (2'i64, "Lagging indexing workers", "sev3", "investigating", "carol")
  ]

  for incident in seedIncidents:
    with incidentStmt:
      reset()
      bindParam incident[0]
      bindParam incident[1]
      bindParam incident[2]
      bindParam incident[3]
      bindParam incident[4]
    discard execute(incidentStmt)
finally:
  finalize(incidentStmt)

var openCritical = initSelectRaw()
with openCritical:
  tableExpr """
    incidents i
    join services s on s.id = i.service_id
  """
  columnExpr "i.id"
  columnExpr "s.name as service_name"
  columnExpr "i.summary"
  columnExpr "i.severity"
  columnExpr "i.owner"
  where "i.status in (?, ?)", "open", "investigating"
  where "s.tier = ?", "critical"
  orderBy "i.severity ASC, i.id ASC"

echo "Open incidents on critical services:"
for row in rows(conn, openCritical):
  let id = row["id"].getInt
  let serviceName = row["service_name"].getString
  let summary = row["summary"].getString
  echo &"  #{id} {serviceName}: {summary}"

var incident = getByPk[Incident, int64](conn, 1)
with incident:
  status = "mitigated"
  owner = "incident-commander"
discard update(conn, incident)

var rollup = initSelectRaw()
with rollup:
  tableExpr "incidents"
  columnExpr "status"
  columnExpr "count(*) as total"
  groupBy "status"
  orderBy "total DESC"

echo ""
echo "Incident rollup:"
for row in rows(conn, rollup):
  let status = row["status"].getString
  let total = row["total"].getInt
  echo &"  {status}: {total}"

close(conn)
close(db)
