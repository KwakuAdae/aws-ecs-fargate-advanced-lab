# Security Design

## Network path

```
Internet ──:80/:8080──▶ ALB security group ──:8080──▶ Task security group ──▶ container
                         (public subnets)                (private subnets, no public IP)
```

| Control | Where | Effect |
|---------|-------|--------|
| Tasks in **private subnets** with `AssignPublicIp: DISABLED` | `03-service.yaml` → `Service` | No direct internet path to any container |
| Task SG allows **only** the ALB SG on 8080 | `TaskSecurityGroup` | Even other resources in the VPC can't reach the tasks |
| Test listener limited by `TestListenerCidr` | `AlbSecurityGroup` | Set it to `<your-ip>/32` so only you can preview new versions |
| NAT gateway for outbound only | `01-network.yaml` | Tasks can pull images and send logs, but can't accept inbound connections |

## IAM: three roles, three jobs

| Role | Assumed by | Permissions |
|------|-----------|-------------|
| Task **execution** role | ECS agent | Pull from ECR, write to CloudWatch Logs (`AmazonECSTaskExecutionRolePolicy`) |
| **Task** role | Your container | Only `ssmmessages:*` for ECS Exec. Add app permissions (S3, DynamoDB...) here, never to the execution role |
| ECS **infrastructure** role | ECS service | Modify listener rules/target groups during blue/green (`AmazonECSInfrastructureRolePolicyForLoadBalancers`) |

## Container

- `nginx-unprivileged` runs as **UID 101**, not root, and listens on a non-privileged port (8080).
- **ECR immutable tags**: a deployed tag always refers to the exact same image.
- **Scan on push** reports known CVEs for every image (`02-build-push.sh` prints the summary).

## Production hardening ideas

- HTTPS listener with an ACM certificate, and an HTTP→HTTPS redirect
- AWS WAF on the ALB
- VPC endpoints instead of a NAT gateway (traffic to ECR/S3/Logs stays on the AWS network)
- `readonlyRootFilesystem: true` with writable `tmpfs` mounts for nginx's cache directories
- ALB access logs to S3
