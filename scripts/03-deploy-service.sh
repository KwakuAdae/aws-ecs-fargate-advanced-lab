#!/usr/bin/env bash
# Step 3 (and every release): deploy the service stack with an image tag.
#   ./scripts/03-deploy-service.sh v1          # first deploy
#   ./scripts/03-deploy-service.sh v2          # blue/green release of v2
# Extra Key=Value pairs are passed as parameters, e.g. BakeTimeInMinutes=10
source "$(dirname "$0")/config.sh"
TAG="${1:?usage: $0 <image-tag> [Key=Value ...]}"; shift

step "Deploying ${SERVICE_STACK} with ImageTag=${TAG}"
echo "   CloudFormation waits for the whole ECS deployment, including the bake time."
echo "   In another terminal:  ./scripts/04-watch-release.sh"
deploy "$SERVICE_STACK" 03-service.yaml \
  NetworkStack="$NETWORK_STACK" EcrStack="$ECR_STACK" ImageTag="$TAG" "$@"

echo ""
echo "✅ Production: $(out "$SERVICE_STACK" ProductionUrl)"
echo "   Test:       $(out "$SERVICE_STACK" TestUrl)"
