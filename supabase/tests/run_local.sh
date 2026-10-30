#!/usr/bin/env bash
# Local migration test: baseline -> seed -> migrate -> test -> undo (schema must match baseline) -> migrate -> test.
# Needs a throwaway local Postgres 17. Usage: PGHOST=/tmp/pgbill PGPORT=55432 ./run_local.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${DB:-billing_test}
P="psql -U ${PGUSER:-postgres} -v ON_ERROR_STOP=1 -q -X"
dropdb -U ${PGUSER:-postgres} --if-exists "$DB"; createdb -U ${PGUSER:-postgres} "$DB"
$P -d "$DB" -f tests/local_stubs.sql
$P -d "$DB" -f baseline/schema.sql
$P -d "$DB" -f tests/seed.sql
dump() { pg_dump -U ${PGUSER:-postgres} -d "$DB" --schema-only -n public | grep -v -E '^--|^$|^SET |^SELECT pg_catalog|^.(un)?restrict ' ; }
dump > /tmp/schema_before.sql
echo "== apply migration";  $P -d "$DB" -f migrations/20261030100000_stripe_billing.sql
echo "== tests (1st apply)"; $P -d "$DB" -f tests/billing_test.sql 2>&1 | grep -E 'PASS|FAIL|ERROR|PASSED' | sed 's/^.*NOTICE:  //'
echo "== undo";             $P -d "$DB" -f rollback/20261030100000_stripe_billing_undo.sql
dump > /tmp/schema_after_undo.sql
if diff -u /tmp/schema_before.sql /tmp/schema_after_undo.sql; then echo "UNDO OK: schema identical to baseline"; else echo "UNDO DIFF ABOVE"; exit 1; fi
echo "== re-apply migration"; $P -d "$DB" -f migrations/20261030100000_stripe_billing.sql
echo "== tests (2nd apply)"; $P -d "$DB" -f tests/billing_test.sql 2>&1 | grep -E 'PASS|FAIL|ERROR|PASSED' | sed 's/^.*NOTICE:  //'
