#!/usr/bin/env bash
# Local test of the lead connections migration: baseline -> earlier migrations -> this migration -> tests -> undo -> re-apply.
# Needs a throwaway local Postgres 17. Usage: PGHOST=/tmp/pgbill PGPORT=55432 ./run_lead_connections.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${DB:-lead_conn_test}
P="psql -U ${PGUSER:-postgres} -v ON_ERROR_STOP=1 -q -X"
dropdb -U ${PGUSER:-postgres} --if-exists "$DB"; createdb -U ${PGUSER:-postgres} "$DB"
$P -d "$DB" -f tests/local_stubs.sql
$P -d "$DB" -f baseline/schema.sql
$P -d "$DB" -f tests/seed.sql
M=migrations/20261031150000_lead_connections
U=rollback/20261031150000_lead_connections_undo
for m in migrations/*.sql; do [ "$m" = "$M.sql" ] || $P -d "$DB" -f "$m"; done
dump() { pg_dump -U ${PGUSER:-postgres} -d "$DB" --schema-only -n public | grep -v -E '^--|^$|^SET |^SELECT pg_catalog|^.(un)?restrict ' ; }
dump > /tmp/lc_before.sql
echo "== apply";  $P -d "$DB" -f $M.sql
echo "== tests";  $P -d "$DB" -f tests/lead_connections_test.sql 2>&1 | grep -E 'PASS|FAIL|SKIP|ERROR' | sed 's/^.*NOTICE:  //'
echo "== undo";   $P -d "$DB" -f $U.sql
dump > /tmp/lc_after.sql
if diff -u /tmp/lc_before.sql /tmp/lc_after.sql; then echo "UNDO OK: schema identical"; else echo "UNDO DIFF ABOVE"; exit 1; fi
echo "== re-apply"; $P -d "$DB" -f $M.sql && echo "RE-APPLY OK"
