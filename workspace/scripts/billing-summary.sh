#!/usr/bin/env bash
# Print current-month AWS cost breakdown by service.
# Usage: ./billing-summary.sh [PROFILE]
# On the host: pass a profile or set AWS_PROFILE.
# Inside the dev container: ambient credentials are used automatically.
set -euo pipefail

START="$(date -u +%Y-%m-01)"
END="$(date -u +%Y-%m-%d)"

# Build --profile flag only when ambient credentials are not already present.
PROFILE_ARG=()
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
  PROFILE="${1:-${AWS_PROFILE:-default}}"
  PROFILE_ARG=(--profile "${PROFILE}")
  PROFILE_LABEL="${PROFILE}"
else
  PROFILE_LABEL="ambient (${AWS_PROFILE:-injected credentials})"
fi

echo "AWS billing summary — ${START} to ${END}  (profile: ${PROFILE_LABEL})"
echo

aws ce get-cost-and-usage \
  "${PROFILE_ARG[@]}" \
  --region us-east-1 \
  --time-period "Start=${START},End=${END}" \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output json | python3 -c "
import json, sys

data   = json.load(sys.stdin)
groups = data['ResultsByTime'][0]['Groups']
rows   = [
    (float(g['Metrics']['UnblendedCost']['Amount']), g['Keys'][0])
    for g in groups
    if float(g['Metrics']['UnblendedCost']['Amount']) > 0
]
rows.sort(reverse=True)

total = sum(cost for cost, _ in rows)
col   = max(len(svc) for _, svc in rows) if rows else 40

print(f'  {\"Service\":<{col}}  {\"Cost (USD)\":>12}')
print('  ' + '-' * (col + 14))
for cost, svc in rows:
    print(f'  {svc:<{col}}  \${cost:>11.4f}')
print('  ' + '-' * (col + 14))
print(f'  {\"TOTAL (estimated)\":<{col}}  \${total:>11.4f}')
"
