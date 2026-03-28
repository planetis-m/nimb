import nimb
import std/[strformat, with]

type
  SupportChunk {.dbTable: "support_chunks".} = object
    docId {.dbColumn: "doc_id".}: string
    product: string
    audience: string
    section: string
    body: string
    embedding {.dbType: "F32_BLOB(4)", dbValueExpr: "vector32(?)".}: Vector32

  RetrievalRequest = object
    product: string
    audience: string
    question: string
    embedding: Vector32

  RetrievedChunk = object
    docId {.dbColumn: "doc_id".}: string
    product: string
    audience: string
    section: string
    body: string
    distance: float64

proc nearestChunks(conn: Connection; request: RetrievalRequest;
    limitCount: int): seq[RetrievedChunk] =
  var q = initSelectRaw()
  with q:
    tableExpr vectorTopK("support_chunks_embedding_idx", request.embedding,
      limitCount, "hits")
    join "JOIN support_chunks c ON c.rowid = hits.id"
    columnExpr "c.doc_id"
    columnExpr "c.product"
    columnExpr "c.audience"
    columnExpr "c.section"
    columnExpr "c.body"
    columnExpr alias(vectorDistanceCos("c.embedding", request.embedding),
      "distance")
    where "c.product = ?", request.product
    where "c.audience = ?", request.audience
    orderBy "distance ASC"
  result = all[RetrievedChunk](conn, q)

let seeds = [
  SupportChunk(
    docId: "billing-guide",
    product: "billing",
    audience: "operators",
    section: "invoice-failures",
    body: "Retry invoice collection after rotating the payment provider token and " &
      "verifying webhook delivery.",
    embedding: vector32([0.96, 0.14, 0.06, 0.02])
  ),
  SupportChunk(
    docId: "billing-guide",
    product: "billing",
    audience: "operators",
    section: "refunds",
    body: "Issue partial refunds from the dashboard and include the invoice id in " &
      "the audit trail note.",
    embedding: vector32([0.74, 0.41, 0.09, 0.05])
  ),
  SupportChunk(
    docId: "platform-guide",
    product: "database",
    audience: "developers",
    section: "local-replicas",
    body: "Create a database, attach a local replica, and route reads there for " &
      "lower tail latency.",
    embedding: vector32([0.91, 0.09, 0.05, 0.01])
  ),
  SupportChunk(
    docId: "platform-guide",
    product: "database",
    audience: "developers",
    section: "auth-tokens",
    body: "Use scoped auth tokens for remote writes and rotate them independently " &
      "from application deploys.",
    embedding: vector32([0.12, 0.93, 0.07, 0.02])
  ),
  SupportChunk(
    docId: "rag-playbook",
    product: "database",
    audience: "developers",
    section: "chunking",
    body: "Keep semantic chunks small enough that nearest-neighbor retrieval " &
      "returns precise passages instead of entire documents.",
    embedding: vector32([0.88, 0.08, 0.12, 0.04])
  ),
  SupportChunk(
    docId: "rag-playbook",
    product: "database",
    audience: "developers",
    section: "freshness",
    body: "Re-embed chunks after important edits so retrieval stays aligned with " &
      "the latest docs and runbooks.",
    embedding: vector32([0.54, 0.24, 0.79, 0.05])
  )
]

let request = RetrievalRequest(
  product: "database",
  audience: "developers",
  question: "How should I set up a local replica for low-latency reads?",
  embedding: vector32([0.93, 0.07, 0.04, 0.01])
)

var db = openDatabase(memoryDatabase())
var conn = connect(db)

discard exec(conn, initCreateTable[SupportChunk]())

let indexOptions = VectorIndexOptions(
  metric: vmCosine,
  compressNeighbors: "float8",
  searchL: 64,
  insertL: 32
)
discard createVectorIndex(conn, "support_chunks_embedding_idx",
  "support_chunks", "embedding", indexOptions)

for chunk in seeds:
  discard insert(conn, chunk)

echo "Semantic retrieval request:"
echo &"  product={request.product}"
echo &"  audience={request.audience}"
echo &"  question={request.question}"

echo "Nearest support chunks:"
for chunk in nearestChunks(conn, request, 4):
  echo &"  [{chunk.docId}/{chunk.section}] distance={chunk.distance:.4f}"
  echo &"    {chunk.body}"

close(conn)
close(db)
