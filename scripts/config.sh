#!/usr/bin/env bash
# Shared lab settings. Override any value by exporting it before running a script.
set -euo pipefail
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_PAGER=""
export NETWORK_STACK="${NETWORK_STACK:-fargate-adv-network}"
export ECR_STACK="${ECR_STACK:-fargate-adv-ecr}"
export SERVICE_STACK="${SERVICE_STACK:-fargate-adv-service}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFN_DIR="${ROOT_DIR}/cloudformation"

out() {   # out STACK KEY → value of a CloudFormation output
  aws cloudformation describe-stacks --stack-name "$1" --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}
deploy() {  # deploy STACK TEMPLATE [Key=Value ...]
  local stack="$1" template="$2"; shift 2
  aws cloudformation deploy --stack-name "$stack" --template-file "${CFN_DIR}/${template}" \
    --region "$AWS_REGION" --capabilities CAPABILITY_IAM --no-fail-on-empty-changeset \
    ${1:+--parameter-overrides "$@"}
}
step() { echo ""; echo "▶ $*"; }
