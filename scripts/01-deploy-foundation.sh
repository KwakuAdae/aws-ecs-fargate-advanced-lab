#!/usr/bin/env bash
# Step 1: Network (VPC, public + private subnets, NAT) and the ECR repository.
source "$(dirname "$0")/config.sh"

step "Network stack ${NETWORK_STACK} (~3 minutes, the NAT gateway is the slow part)"
deploy "$NETWORK_STACK" 01-network.yaml

step "ECR stack ${ECR_STACK}"
deploy "$ECR_STACK" 02-ecr.yaml

echo ""
echo "✅ Repository: $(out "$ECR_STACK" RepositoryUri)"
