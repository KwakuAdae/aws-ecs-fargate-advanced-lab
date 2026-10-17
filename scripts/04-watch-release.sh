#!/usr/bin/env bash
# Watch a blue/green release: every 3 seconds show which version the production listener (:80)
# and the test listener (:8080) are serving, plus the ECS deployment status. Ctrl+C to stop.
source "$(dirname "$0")/config.sh"
PROD="$(out "$SERVICE_STACK" ProductionUrl)"
TEST="$(out "$SERVICE_STACK" TestUrl)"
CLUSTER="$(out "$SERVICE_STACK" ClusterName)"
SERVICE="$(out "$SERVICE_STACK" ServiceName)"

version() { curl -s --max-time 2 "$1/version.json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["version"], d["color"])' 2>/dev/null || echo "-"; }

printf "%-10s %-16s %-16s %s\n" TIME "PRODUCTION :80" "TEST :8080" "ECS DEPLOYMENT"
while true; do
  STATUS=$(aws ecs describe-service-deployments --region "$AWS_REGION" \
    --service-deployment-arns "$(aws ecs list-service-deployments --cluster "$CLUSTER" --service "$SERVICE" \
       --region "$AWS_REGION" --max-results 1 --query 'serviceDeployments[0].serviceDeploymentArn' --output text)" \
    --query 'serviceDeployments[0].[status,lifecycleStage]' --output text 2>/dev/null | tr '\t' ' ')
  printf "%-10s %-16s %-16s %s\n" "$(date +%H:%M:%S)" "$(version "$PROD")" "$(version "$TEST")" "${STATUS:--}"
  sleep 3
done
