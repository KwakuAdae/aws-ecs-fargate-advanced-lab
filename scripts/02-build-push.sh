#!/usr/bin/env bash
# Step 2: Build an image and push it to ECR.
#   ./scripts/02-build-push.sh v1 blue
#   ./scripts/02-build-push.sh v2 green
source "$(dirname "$0")/config.sh"
VERSION="${1:?usage: $0 <version-tag> [blue|green|orange]}"
COLOR="${2:-blue}"
REPO_URI="$(out "$ECR_STACK" RepositoryUri)"
REGISTRY="${REPO_URI%%/*}"

step "Logging Docker in to ${REGISTRY}"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

step "Building ${REPO_URI}:${VERSION} (${COLOR})"
docker build --platform linux/amd64 \
  --build-arg APP_VERSION="$VERSION" \
  --build-arg APP_COLOR="$COLOR" \
  --build-arg BUILD_TIME="$(date -u +%Y-%m-%dT%H:%MZ)" \
  -t "${REPO_URI}:${VERSION}" "${ROOT_DIR}/app"

step "Pushing (tags are immutable: pushing ${VERSION} twice fails on purpose)"
docker push "${REPO_URI}:${VERSION}"

step "Scan results (scan on push)"
aws ecr wait image-scan-complete --repository-name "$(out "$ECR_STACK" RepositoryName)" \
  --image-id imageTag="$VERSION" --region "$AWS_REGION" 2>/dev/null || true
aws ecr describe-image-scan-findings --repository-name "$(out "$ECR_STACK" RepositoryName)" \
  --image-id imageTag="$VERSION" --region "$AWS_REGION" \
  --query 'imageScanFindings.findingSeverityCounts' --output table 2>/dev/null || echo "   (no findings reported)"
