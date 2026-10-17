# ECS Blue/Green Deployments Explained

## Rolling vs blue/green

| | Rolling update (ECS default) | Blue/green (this lab) |
|---|---|---|
| How | Replace tasks a few at a time | Start a full new set ("green"), then switch traffic |
| Mixed versions served? | Yes, during the rollout | No: production switches in one step |
| Test before users see it? | No | Yes, through the **test listener** |
| Rollback | Another rolling update (minutes) | Switch the listener back (seconds), while blue is still running |
| Extra capacity during deploy | A little | Up to 2× tasks for the deployment + bake time |

## The pieces in `03-service.yaml`

```yaml
LoadBalancers:
  - ContainerName: web
    ContainerPort: 8080
    TargetGroupArn: !Ref BlueTargetGroup            # where production traffic goes today
    AdvancedConfiguration:
      AlternateTargetGroupArn: !Ref GreenTargetGroup  # where the next version is registered
      ProductionListenerRule: !Ref ProductionListenerRule
      TestListenerRule: !Ref TestListenerRule
      RoleArn: !GetAtt EcsInfrastructureRole.Arn       # lets ECS edit the listener rules

DeploymentConfiguration:
  Strategy: BLUE_GREEN
  BakeTimeInMinutes: 3
  DeploymentCircuitBreaker: { Enable: true, Rollback: true }
  Alarms: { AlarmNames: [<5xx alarm>], Enable: true, Rollback: true }
```

Both listener rules forward to **both** target groups with weights (`blue 100 / green 0` at the
start). A deployment is just ECS changing those weights at the right moments.

The roles "blue" and "green" swap on every deployment. After v2 goes live on the green target
group, the next release (v3) is registered in the blue target group, and so on.

## Lifecycle stages

`./scripts/04-watch-release.sh` prints the current stage from `aws ecs describe-service-deployments`:

| Stage | What's happening |
|-------|------------------|
| `RECONCILE_SERVICE` | ECS prepares the deployment |
| `PRE_SCALE_UP` / `SCALE_UP` | Green tasks start and pass health checks in the alternate target group |
| `POST_SCALE_UP` | Hook point: validate green before any traffic |
| `TEST_TRAFFIC_SHIFT` / `POST_TEST_TRAFFIC_SHIFT` | Test listener (:8080) → green. Hook point for automated tests |
| `PRODUCTION_TRAFFIC_SHIFT` / `POST_PRODUCTION_TRAFFIC_SHIFT` | Production listener (:80) → green |
| `BAKE_TIME` | Blue still running; any alarm → instant rollback |
| `CLEAN_UP` | Blue tasks are stopped |

Each `POST_*` stage (and `PRE_SCALE_UP`) can run a **lifecycle hook**: a Lambda function that
returns `SUCCEEDED`, `FAILED` (roll back) or `IN_PROGRESS` (ask again later).

## How rollback is triggered

1. **Deployment circuit breaker**: green tasks keep failing to start or fail health checks.
2. **CloudWatch alarm**: `Target5xxAlarm` (more than 5 target 5XX responses in a minute) goes
   into ALARM during the deployment or bake time.
3. **Manually**: `aws ecs stop-service-deployment --service-deployment-arn <arn> --stop-type ROLLBACK`.
4. **Lifecycle hook** returns `FAILED`.

In every case ECS points the listener rules back at blue (still running), then removes green.

## Watching it in the console

**ECS → Clusters → fargate-adv-service-cluster → Services → fargate-adv-service-web → Deployments**
shows the current deployment, its lifecycle stage, and the source/target service revisions.
**EC2 → Load Balancers → Listeners → Rules** shows the weights changing live.
