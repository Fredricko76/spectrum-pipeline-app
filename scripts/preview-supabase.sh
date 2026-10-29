#!/bin/sh
# Netlify deploy-preview / branch-deploy ONLY: point the static app at the
# Supabase "billing-test" development branch instead of production.
# Production has no build command (see netlify.toml) and never runs this.
# The values below are PUBLIC (URL + publishable key), the same kind of value
# production already ships in index.html. No secrets belong here.
set -eu

case "${CONTEXT:-}" in
  deploy-preview|branch-deploy) ;;
  *) echo "preview-supabase: CONTEXT='${CONTEXT:-}' is not a preview - leaving index.html untouched"; exit 0 ;;
esac

PROD_URL='https://qjkmkmmrgtoaocygymqo.supabase.co'
PROD_KEY='sb_publishable_4Jim3KNPeBOh5kkdYr-RLw_lWrCOaAg'
TEST_URL="${PREVIEW_SUPABASE_URL:-https://wwdhiailerkmwpnuqpvm.supabase.co}"
TEST_KEY="${PREVIEW_SUPABASE_KEY:-sb_publishable_15inG19zozn9eZwcJkSLtA_gEg6taiq}"

f=index.html
[ "$(grep -c "const SUPABASE_URL = \"$PROD_URL\";" "$f")" = 1 ] || { echo "preview-supabase: SUPABASE_URL line not found"; exit 1; }
[ "$(grep -c "const SUPABASE_KEY = \"$PROD_KEY\";" "$f")" = 1 ] || { echo "preview-supabase: SUPABASE_KEY line not found"; exit 1; }

sed -i \
  -e "s#const SUPABASE_URL = \"$PROD_URL\";#const SUPABASE_URL = \"$TEST_URL\";#" \
  -e "s#const SUPABASE_KEY = \"$PROD_KEY\";#const SUPABASE_KEY = \"$TEST_KEY\";#" \
  "$f"

# visible marker so nobody mistakes a preview for the real app
sed -i 's#</body>#<div style="position:fixed;left:0;bottom:0;z-index:99999;background:\#b7791f;color:\#fff;font:600 11px/1 system-ui,sans-serif;padding:5px 9px;border-top-right-radius:6px;pointer-events:none">PREVIEW - TEST DATABASE (billing-test)</div>\n</body>#' "$f"

grep -q "$TEST_URL" "$f" && ! grep -q "$PROD_URL" "$f" || { echo "preview-supabase: production URL still present"; exit 1; }
echo "preview-supabase: $CONTEXT build now points at $TEST_URL"
