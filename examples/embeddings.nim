import nimb
import std/[strformat, with]

var db = openDatabase(memoryDatabase())
var conn = connect(db)

discard exec(conn, """
  CREATE TABLE support_chunks (
    doc_id TEXT NOT NULL,
    section TEXT NOT NULL,
    body TEXT NOT NULL,
    embedding F32_BLOB(4)
  );
""")

discard exec(conn, """
  CREATE INDEX support_chunks_idx
  ON support_chunks (libsql_vector_idx(embedding));
""")

discard exec(conn, """
  INSERT INTO support_chunks (doc_id, section, body, embedding) VALUES
    ('getting-started', 'create-database',
      'Create a database, then connect with a local replica for low-latency reads.',
      vector32('[0.92, 0.10, 0.03, 0.00]')),
    ('getting-started', 'auth-tokens',
      'Use auth tokens for remote access and keep them out of client builds.',
      vector32('[0.15, 0.91, 0.08, 0.02]')),
    ('rag-guide', 'chunking',
      'Store small semantic chunks so similarity search can return precise retrieval units.',
      vector32('[0.88, 0.09, 0.11, 0.03]')),
    ('rag-guide', 'freshness',
      'Re-embed content after important edits so retrieval reflects the latest source material.',
      vector32('[0.52, 0.25, 0.78, 0.04]'));
""")

let queryVector = "[0.90, 0.08, 0.06, 0.01]"

var nearest = initSelectRaw()
with nearest:
  tableExpr """
    vector_top_k('support_chunks_idx', ?, 3) hits
    JOIN support_chunks c ON c.rowid = hits.id
  """, queryVector
  columnExpr "c.doc_id"
  columnExpr "c.section"
  columnExpr "c.body"
  columnExpr &"vector_distance_cos(c.embedding, vector32('{queryVector}')) AS distance"
  orderBy "distance ASC"

echo "Nearest support chunks for a database setup query:"
for row in rows(conn, nearest):
  let docId = row["doc_id"].getString
  let section = row["section"].getString
  let distance = row["distance"].getFloat
  let body = row["body"].getString
  echo &"  [{docId}/{section}] distance={distance:.4f}"
  echo &"    {body}"

close(conn)
close(db)
