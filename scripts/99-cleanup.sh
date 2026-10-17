#!/usr/bin/env bash
# Delete the three stacks in reverse order (service → ECR → network).
source "$(dirname "$0")/config.sh"
set +e
for stack in "$SERVICE_STACK" "$ECR_STACK" "$NETWORK_STACK"; do
  step "Deleting ${stack}"
  aws cloudformation delete-stack --stack-name "$stack" --region "$AWS_REGION"
  aws cloudformation wait stack-delete-complete --stack-name "$stack" --region "$AWS_REGION" \
    && echo "   deleted" || echo "   ⚠️ check the CloudFormation console for ${stack}"
done
echo ""
echo "✅ Cleanup complete."
