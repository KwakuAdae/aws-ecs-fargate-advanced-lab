# Troubleshooting

First checks:

```bash
aws ecs describe-services --cluster fargate-adv-service-cluster --services fargate-adv-service-web \
  --query 'services[0].events[:8].[createdAt,message]' --output table

aws cloudformation describe-stack-events --stack-name fargate-adv-service \
  --query "StackEvents[?contains(ResourceStatus,'FAILED')].[LogicalResourceId,ResourceStatusReason]" --output table

aws logs tail /ecs/fargate-adv-service --since 15m
```

## CloudFormation

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `No export named fargate-adv-network-VpcId found` | Network stack not deployed, or a different name/region | Run `01-deploy-foundation.sh` first; keep `AWS_REGION` and stack names consistent |
| `Encountered unsupported property Strategy` / `AdvancedConfiguration` | Region or account doesn't have ECS native blue/green yet | Use a current commercial region (e.g. us-east-1), or set `Strategy: ROLLING` and remove `AdvancedConfiguration` |
| `Export ... cannot be deleted as it is in use` | Deleting the network/ECR stack before the service stack | Delete in reverse order (the cleanup script does this) |
| Stack update takes 5+ minutes | It waits for the whole blue/green deployment, including the bake time | Expected. Lower it with `./scripts/03-deploy-service.sh v3 BakeTimeInMinutes=0` |
| `UPDATE_ROLLBACK_COMPLETE` after a release | The deployment rolled back (circuit breaker or 5XX alarm) | Check the service events and container logs for why the new version failed |

## Tasks

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `CannotPullContainerError ... not found` | Tag not pushed, or a typo | `aws ecr list-images --repository-name fargate-advanced-web` |
| `CannotPullContainerError ... i/o timeout` | Private subnets have no route out | Check the private route table has `0.0.0.0/0 → NAT gateway`, and the NAT gateway is `available` |
| `exec format error` | Image built for ARM (Apple Silicon) | `02-build-push.sh` builds `--platform linux/amd64`. Push a new tag |
| Tasks start then stop: `Task failed ELB health checks` | `/health` not reachable on 8080, or the SG blocks the ALB | `docker run -p 8080:8080` locally and `curl localhost:8080/health`; check `TaskSecurityGroup` ingress |
| `tag invalid: The image tag 'v1' already exists` on push | ECR tags are immutable | Use a new tag (`v3`, a date, or a git SHA) |

## Load balancer

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `503 Service Temporarily Unavailable` | No healthy targets in the active target group | **EC2 → Target Groups → Targets**; see the Tasks section above |
| `404 Not found` (plain text) | Request hit the listener's default action | The rule matches `/*`, so this means the rule was edited or deleted. Redeploy the service stack |
| Test URL (:8080) times out | Your IP isn't in `TestListenerCidr` | Redeploy with `TestListenerCidr=<your-ip>/32` |
| Test URL shows the same version as production | No deployment in progress | Test traffic only goes to green during a deployment |

## Watch script

| Symptom | Fix |
|---------|-----|
| `ECS DEPLOYMENT` column shows `-` | Your AWS CLI is too old for `list-service-deployments`. Upgrade AWS CLI v2 |
