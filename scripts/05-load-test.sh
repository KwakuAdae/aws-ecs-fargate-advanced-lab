#!/usr/bin/env bash
# Send steady traffic to the production URL and watch the service scale (CPU target 60%).
#   ./scripts/05-load-test.sh [seconds] [parallel]
source "$(dirname "$0")/config.sh"
SECS="${1:-300}"; PAR="${2:-50}"
PROD="$(out "$SERVICE_STACK" ProductionUrl)"
CLUSTER="$(out "$SERVICE_STACK" ClusterName)"
SERVICE="$(out "$SERVICE_STACK" ServiceName)"

step "Sending traffic to ${PROD} for ${SECS}s with ${PAR} parallel workers"
END=$(( $(date +%s) + SECS ))
for _ in $(seq "$PAR"); do
  ( while [ "$(date +%s)" -lt "$END" ]; do curl -s -o /dev/null "$PROD/"; done ) &
done

while [ "$(date +%s)" -lt "$END" ]; do
  aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION" \
    --query 'services[0].[desiredCount,runningCount]' --output text | \
    awk -v t="$(date +%H:%M:%S)" '{print t "  desired=" $1 "  running=" $2}'
  sleep 20
done
wait
echo "Done. The service scales back in after the cooldown (a few minutes)."
