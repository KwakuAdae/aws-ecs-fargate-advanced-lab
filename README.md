# Lab: Advanced ECS Fargate: ALB, Private Subnets, Blue/Green Deployments and Auto Scaling

A hands-on lab that deploys a containerized website to **Amazon ECS on AWS Fargate** the way
production teams do: image in **Amazon ECR**, containers in **private subnets** behind an
**Application Load Balancer**, **zero-downtime blue/green releases** with automatic rollback,
and **auto scaling**. All infrastructure is defined in **CloudFormation**.

> Start with the beginner lab [Deploy a Website to ECR and ECS Fargate](https://github.com/KwakuAdae/aws-ecs-fargate-website-lab)
> if you're new to ECS. It uses the default VPC, a public IP per task and CLI scripts.
> This lab replaces each of those shortcuts with the production pattern.

```
                                   ┌──────────────────────── VPC 10.30.0.0/16 (2 AZs) ────────────────────────┐
                                   │  Public subnets                     Private subnets                      │
 ┌─────────┐   :80  production     │  ┌───────────────────────────┐      ┌──────────────────────────────┐    │
 │ Users   │ ────────────────────────▶│ Application Load Balancer │      │  ECS service (Fargate)       │    │
 └─────────┘                       │  │  listener :80  ─┐         │      │                              │    │
 ┌─────────┐   :8080  test         │  │  listener :8080 ┤ rules   │ ───▶ │  BLUE  tasks (v1) ◀─ TG blue  │    │
 │ You     │ ────────────────────────▶│                 └─────────│ ───▶ │  GREEN tasks (v2) ◀─ TG green │    │
 └─────────┘                       │  └───────────────────────────┘      │  2-6 tasks, CPU/memory scaling │    │
                                   │  NAT gateway ◀──────────────────────│  (pull image, send logs)     │    │
                                   │                                     └──────────────────────────────┘    │
                                   └──────────────────────────────────────────────────────────────────────────┘
   Amazon ECR (immutable tags, scan on push)   ·   CloudWatch Logs + Container Insights   ·   5XX alarm → rollback
```

## What you will learn

| Area | Topics |
|------|--------|
| **Networking** | VPC with public/private subnets across 2 AZs, internet gateway, NAT gateway, route tables, security groups that only allow ALB → task traffic |
| **ECR** | Immutable tags, scan on push, lifecycle policy, `EmptyOnDelete` |
| **Load balancing** | ALB, two listeners (production :80, test :8080), weighted listener rules, `ip` target groups, health checks, deregistration delay |
| **ECS Fargate** | Cluster with Container Insights, task definition, execution role vs task role, private tasks without public IPs, ECS Exec |
| **Deployments** | **ECS native blue/green**: test traffic, bake time, instant rollback, deployment circuit breaker, **alarm-based rollback** |
| **Scaling** | Application Auto Scaling with CPU and memory target tracking |
| **CloudFormation** | Three stacks linked with **exports / `Fn::ImportValue`**, `!Cidr`, `!GetAZs`, `!Split`, parameters, `aws cloudformation deploy` |

## Project structure

```
aws-ecs-fargate-advanced-lab/
├── app/
│   ├── Dockerfile            # nginx-unprivileged; version + color baked in at build time
│   ├── nginx.conf            # /health and /version.json
│   └── index.html
├── cloudformation/
│   ├── 01-network.yaml       # VPC, 2 public + 2 private subnets, IGW, NAT gateway
│   ├── 02-ecr.yaml           # ECR repository
│   └── 03-service.yaml       # ALB, target groups, ECS cluster/task/service, roles, alarm, scaling
├── scripts/
│   ├── 01-deploy-foundation.sh  # network + ECR stacks
│   ├── 02-build-push.sh         # build an image version and push it
│   ├── 03-deploy-service.sh     # deploy/release a version (blue/green)
│   ├── 04-watch-release.sh      # live view of production vs test traffic
│   ├── 05-load-test.sh          # trigger auto scaling
│   └── 99-cleanup.sh            # delete all three stacks
└── docs/
    ├── 01-blue-green-explained.md
    ├── 02-security-design.md
    └── 03-troubleshooting.md
```

## Prerequisites

| Tool | Check | Notes |
|------|-------|-------|
| AWS account | — | See [Cost](#cost). The NAT gateway and ALB are billed hourly |
| AWS CLI v2 (recent) | `aws --version` | Must support ECS blue/green (`aws ecs list-service-deployments help`) |
| Docker | `docker --version` | Docker Desktop on Mac/Windows |
| Python 3 | `python3 --version` | Used by the watch script to read JSON |

---

## Quick start

```bash
git clone https://github.com/KwakuAdae/aws-ecs-fargate-advanced-lab.git
cd aws-ecs-fargate-advanced-lab

./scripts/01-deploy-foundation.sh        # network + ECR (~3 min)
./scripts/02-build-push.sh v1 blue
./scripts/03-deploy-service.sh v1        # ALB + ECS (~5 min), prints the URL

./scripts/02-build-push.sh v2 green      # a new release...
./scripts/03-deploy-service.sh v2        # ...deployed blue/green
./scripts/04-watch-release.sh            # (second terminal) watch it happen

./scripts/99-cleanup.sh
```

---

## Step 1: Test the website locally

```bash
docker build -t web:v1 --build-arg APP_VERSION=v1 --build-arg APP_COLOR=blue app
docker run --rm -p 8080:8080 web:v1
# http://localhost:8080             → blue page, "VERSION v1 · blue"
# http://localhost:8080/version.json → {"version":"v1","color":"blue",...}
# http://localhost:8080/health       → OK
```

Each release is built with its own version and color, so during a deployment you can see at a
glance which one answered.

## Step 2: Deploy the network and ECR

```bash
./scripts/01-deploy-foundation.sh
```

[`01-network.yaml`](cloudformation/01-network.yaml) creates:

| Resource | Purpose |
|----------|---------|
| VPC `10.30.0.0/16` | Your private network |
| 2 **public** subnets (`10.30.0.0/24`, `10.30.1.0/24`) | The ALB and NAT gateway; route `0.0.0.0/0 → internet gateway` |
| 2 **private** subnets (`10.30.2.0/24`, `10.30.3.0/24`) | The containers; route `0.0.0.0/0 → NAT gateway` (outbound only) |
| NAT gateway | Lets private tasks pull images from ECR and send logs, without being reachable from the internet |

The stack **exports** `VpcId`, `PublicSubnets` and `PrivateSubnets`. The service stack reads them
with `Fn::ImportValue`, so CloudFormation won't let you delete the network while the service uses it.

[`02-ecr.yaml`](cloudformation/02-ecr.yaml) creates a repository with **immutable tags** (a `v1`
image can never be silently replaced), **scan on push**, and a lifecycle policy that keeps the
last 10 images.

## Step 3: Build and push v1

```bash
./scripts/02-build-push.sh v1 blue
```

The script logs Docker in to ECR, builds for `linux/amd64`, pushes, then shows the vulnerability
scan summary. Try pushing `v1` again: ECR rejects it because the tag is immutable.

## Step 4: Deploy the service

```bash
./scripts/03-deploy-service.sh v1
```

[`03-service.yaml`](cloudformation/03-service.yaml) creates:

- **Security groups**: ALB accepts `:80` from anywhere and `:8080` from `TestListenerCidr`;
  tasks accept `:8080` **only from the ALB's security group**.
- **ALB** in the public subnets, with **two target groups** (`blue`, `green`) and two listeners:
  - **production :80** and **test :8080**, each with a rule that forwards to the target groups
    by weight. ECS changes these weights during deployments.
- **IAM roles**:
  - *task execution role*: ECS pulls the image and writes logs
  - *task role*: the container's own permissions (here only ECS Exec)
  - *ECS infrastructure role*: lets ECS update the listener rules
- **ECS cluster** with Container Insights, a **task definition** (0.25 vCPU / 0.5 GB), and a
  **service** running 2 tasks in the **private subnets** with **no public IP**.
- **5XX alarm** and **auto scaling** (2–6 tasks).

When it finishes:

```
✅ Production: http://fargate-adv-service-alb-123456789.us-east-1.elb.amazonaws.com
   Test:       http://fargate-adv-service-alb-123456789.us-east-1.elb.amazonaws.com:8080
```

Open the production URL to see the **blue v1** page. The tasks have no public IP; all traffic
goes through the ALB.

## Step 5: Release v2 with a blue/green deployment

Build the new version, start the release, and watch it in a second terminal:

```bash
./scripts/02-build-push.sh v2 green
./scripts/03-deploy-service.sh v2           # terminal 1
./scripts/04-watch-release.sh               # terminal 2
```

```
TIME       PRODUCTION :80   TEST :8080       ECS DEPLOYMENT
10:00:03   v1 blue          v1 blue          IN_PROGRESS SCALE_UP
10:00:51   v1 blue          v2 green         IN_PROGRESS TEST_TRAFFIC_SHIFT      ← only the test port sees v2
10:01:30   v2 green         v2 green         IN_PROGRESS PRODUCTION_TRAFFIC_SHIFT
10:01:36   v2 green         v2 green         IN_PROGRESS BAKE_TIME              ← v1 still running, instant rollback possible
10:04:40   v2 green         v2 green         IN_PROGRESS CLEAN_UP
10:05:05   v2 green         v2 green         SUCCESSFUL
```

What happened:

1. ECS started v2 ("green") tasks **alongside** v1 ("blue") and registered them in the other target group.
2. The **test listener (:8080)** switched to green first, so you can check v2 before users see it.
3. The **production listener (:80)** switched to green **all at once**: no mixed versions, no downtime.
4. During the **bake time** (3 minutes by default), blue keeps running. If the **5XX alarm**
   fires, ECS switches production straight back to blue.
5. After the bake time, the blue tasks are stopped.

Details and lifecycle stages: [docs/01-blue-green-explained.md](docs/01-blue-green-explained.md).

## Step 6: Watch an automatic rollback

Deploy a version that can never become healthy, for example an image tag that doesn't exist:

```bash
./scripts/03-deploy-service.sh v99
```

The new tasks fail to start, the **deployment circuit breaker** trips, ECS rolls back to the last
good version, and CloudFormation reports the stack update as failed and rolls back too.
Production keeps serving v2 the whole time.

> Rolling back on errors works the same way: `Target5xxAlarm` is listed under
> `DeploymentConfiguration.Alarms` with `Rollback: true`.

## Step 7: Auto scaling

```bash
./scripts/05-load-test.sh 300 50
# 10:10:20  desired=2  running=2
# 10:12:40  desired=4  running=3
# 10:13:00  desired=4  running=4
```

Target tracking keeps average CPU around 60% and memory around 70%, between 2 and 6 tasks. See the
scaling activity in **ECS → Cluster → Service → Events**, or **CloudWatch → Alarms** (target
tracking creates its own alarms).

## Step 8: Logs, metrics and a shell inside a container

```bash
aws logs tail /ecs/fargate-adv-service --follow                       # nginx access logs

aws ecs execute-command --cluster fargate-adv-service-cluster \
  --task <task-id> --container web --interactive --command "/bin/sh"  # ECS Exec (needs the Session Manager plugin)
```

**CloudWatch → Container Insights** shows CPU, memory and network per service and task.

## Step 9: Clean up

```bash
./scripts/99-cleanup.sh
```

The stacks are deleted in reverse order: service → ECR (with its images) → network.

---

## Cost

| Resource | Approx. cost (us-east-1) |
|----------|--------------------------|
| Fargate, 2 tasks × (0.25 vCPU, 0.5 GB) | ~$0.025 / hour (doubles briefly during a blue/green deploy) |
| Application Load Balancer | ~$0.0225 / hour + LCUs |
| NAT gateway | ~$0.045 / hour + $0.045/GB |
| Public IPv4 (ALB ×2, NAT) | ~$0.015 / hour |
| Container Insights, logs, ECR | a few cents |

**About $0.11 per hour.** Delete the stacks when you finish the lab.

## Going further

- **HTTPS**: add an ACM certificate and a `:443` listener, and redirect `:80 → :443`
- Replace the NAT gateway with **VPC endpoints** (ECR API, ECR DKR, S3, CloudWatch Logs)
- Try the other strategies: `Strategy: CANARY` or `LINEAR` (with `CanaryConfiguration` / `LinearConfiguration`)
- Add **lifecycle hooks** (`DeploymentConfiguration.LifecycleHooks`): a Lambda that tests the
  green version on the test listener before production shifts
- **CI/CD**: GitHub Actions with OIDC → build, push, `03-deploy-service.sh $GITHUB_SHA`
- Run on **Fargate Spot** with a capacity provider strategy
- Sister labs: [ECS Fargate basics](https://github.com/KwakuAdae/aws-ecs-fargate-website-lab) ·
  [EKS microservices](https://github.com/KwakuAdae/aws-eks-microservices-lab) ·
  [API Gateway + SAM](https://github.com/KwakuAdae/aws-api-gateway-sam-lab) ·
  [CloudWatch Logs + Terraform](https://github.com/KwakuAdae/aws-cloudwatch-logs-terraform-lab)

## Troubleshooting

See [docs/03-troubleshooting.md](docs/03-troubleshooting.md).

## Author

**Kwaku Adae**: [github.com/KwakuAdae](https://github.com/KwakuAdae)

Feedback and reviews are welcome. Open an issue or a pull request!
