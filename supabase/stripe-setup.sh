#!/usr/bin/env bash
# Creates the Spectrum Pipeline billing catalogue in a Stripe SANDBOX / TEST account:
#   3 products + monthly AUD prices (GST exclusive, lookup keys, plan/seat_limit metadata)
#   1 dedicated Customer Portal configuration (only these 3 prices)
# Refuses to run with a live key. Re-running is safe: existing lookup keys are reused.
#
#   export STRIPE_SECRET_KEY=sk_test_...     # never commit or echo this
#   APP_URL=https://spectrumsalesonline.net ./supabase/stripe-setup.sh
#
# Prints only object ids (prod_/price_/bpc_), never keys.
set -euo pipefail

: "${STRIPE_SECRET_KEY:?set STRIPE_SECRET_KEY to a sandbox/test key}"
case "$STRIPE_SECRET_KEY" in
  sk_test_*|rk_test_*) ;;
  *) echo "Refusing: STRIPE_SECRET_KEY is not a test-mode key." >&2; exit 1 ;;
esac
APP_URL="${APP_URL:-https://spectrumsalesonline.net}"
API="https://api.stripe.com/v1"
VER="2026-09-30.endive"          # same API version the edge functions use (stripe npm 23.0.1)
TAX_CODE="txcd_10103001"         # Software as a service (SaaS) - business use

stripe_call() {  # method path [curl -d args...]
  local method=$1 path=$2; shift 2
  curl -sS --fail-with-body -X "$method" "$API$path" -u "$STRIPE_SECRET_KEY:" \
       -H "Stripe-Version: $VER" "$@"
}
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

declare -A PRICE_IDS PRODUCT_IDS
make_plan() {  # plan name amount_cents seats description
  local plan=$1 name=$2 amount=$3 seats=$4 desc=$5 key="pipeline_${1}_monthly"
  local existing
  existing=$(stripe_call GET "/prices?active=true&lookup_keys[]=$key" | jget "d['data'][0]['id'] + ' ' + d['data'][0]['product'] if d['data'] else ''")
  if [[ -n "$existing" ]]; then
    PRICE_IDS[$plan]=${existing% *}; PRODUCT_IDS[$plan]=${existing#* }
    echo "exists  $key -> ${PRICE_IDS[$plan]} (${PRODUCT_IDS[$plan]})"; return
  fi
  local prod
  prod=$(stripe_call POST /products \
    -d name="Spectrum Pipeline $name" -d description="$desc" -d tax_code="$TAX_CODE" \
    -d "metadata[app]=spectrum-pipeline" -d "metadata[plan]=$plan" -d "metadata[seat_limit]=$seats" \
    -H "Idempotency-Key: pipeline-product-$plan-v1" | jget "d['id']")
  local price
  price=$(stripe_call POST /prices \
    -d product="$prod" -d currency=aud -d unit_amount="$amount" \
    -d "recurring[interval]=month" -d tax_behavior=exclusive \
    -d lookup_key="$key" -d transfer_lookup_key=true -d nickname="$name monthly (ex GST)" \
    -d "metadata[app]=spectrum-pipeline" -d "metadata[plan]=$plan" -d "metadata[seat_limit]=$seats" \
    -H "Idempotency-Key: pipeline-price-$plan-v1" | jget "d['id']")
  PRICE_IDS[$plan]=$price; PRODUCT_IDS[$plan]=$prod
  echo "created $key -> $price ($prod)"
}

make_plan starter Starter 14900 3  "Up to 3 users"
make_plan team    Team    34900 10 "Up to 10 users"
make_plan network Network 79900 25 "Franchise networks, up to 25 users"

i=0; prod_args=()
for plan in starter team network; do
  prod_args+=(-d "features[subscription_update][products][$i][product]=${PRODUCT_IDS[$plan]}"
              -d "features[subscription_update][products][$i][prices][0]=${PRICE_IDS[$plan]}")
  i=$((i+1))
done

bpc=$(stripe_call POST /billing_portal/configurations \
  -d "business_profile[headline]=Spectrum Sales Pipeline - manage your subscription" \
  -d "default_return_url=$APP_URL/?billing=portal" \
  -d "features[customer_update][enabled]=true" \
  -d "features[customer_update][allowed_updates][]=name" \
  -d "features[customer_update][allowed_updates][]=email" \
  -d "features[customer_update][allowed_updates][]=address" \
  -d "features[customer_update][allowed_updates][]=tax_id" \
  -d "features[invoice_history][enabled]=true" \
  -d "features[payment_method_update][enabled]=true" \
  -d "features[subscription_cancel][enabled]=true" \
  -d "features[subscription_cancel][mode]=at_period_end" \
  -d "features[subscription_cancel][cancellation_reason][enabled]=true" \
  -d "features[subscription_cancel][cancellation_reason][options][]=too_expensive" \
  -d "features[subscription_cancel][cancellation_reason][options][]=missing_features" \
  -d "features[subscription_cancel][cancellation_reason][options][]=switched_service" \
  -d "features[subscription_cancel][cancellation_reason][options][]=unused" \
  -d "features[subscription_cancel][cancellation_reason][options][]=other" \
  -d "features[subscription_update][enabled]=true" \
  -d "features[subscription_update][default_allowed_updates][]=price" \
  -d "features[subscription_update][proration_behavior]=create_prorations" \
  -d "features[subscription_update][trial_update_behavior]=continue_trial" \
  -d "metadata[app]=spectrum-pipeline" \
  "${prod_args[@]}" \
  -H "Idempotency-Key: pipeline-portal-config-v1" | jget "d['id']")
echo "portal configuration -> $bpc   (set as STRIPE_PORTAL_CONFIG_ID)"
