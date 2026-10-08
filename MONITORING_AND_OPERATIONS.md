# Monitoring and Operations

## 1. Which metrics I monitor and why

| Area | Metrics | Source | Why |
|---|---|---|---|
| Availability | `up` for each target, `/actuator/health` | Prometheus, Spring Boot Actuator | The first sign that the service or the database connection is down |
| Traffic | Request rate per endpoint (`http_server_requests_seconds_count`) | Actuator + Micrometer | Shows load and sudden drops or spikes |
| Errors | Rate of HTTP 5xx responses vs total | Actuator + Micrometer | Shows users are getting failures |
| Latency | p95 and average response time | Actuator + Micrometer | Detects slowness before it becomes an outage |
| Database | HikariCP active/pending connections, connection timeouts | Actuator + Micrometer | Detects RDS connectivity or pool problems |
| JVM | Heap usage, GC pause time | Actuator + Micrometer | Detects memory leaks and pressure |
| Host | CPU, memory, disk usage, disk I/O | node-exporter | Shows resource exhaustion on the EC2 instance |
| Containers | Container restarts, uptime, CPU and memory per container | cAdvisor | Detects crash loops and runaway containers |
| RDS | CPU, free storage, connections, free memory | CloudWatch | Detects database saturation (not scraped by Prometheus here) |

## 2. Which logs are critical
- **Backend application logs** (`docker logs todo-backend-1`): exceptions, database connection errors (such as `Connect timed out`), failed Cohere or Slack calls.
- **Deployment logs**: GitHub Actions run logs and the output of `scripts/deploy.sh`.
- **Container and Docker daemon logs**: restarts, out-of-memory kills, failed health checks.
- **RDS logs** (error log and slow query log in CloudWatch): failed logins, crashes, slow queries.
- **AWS audit logs** (CloudTrail): IAM changes, security group changes, SSM sessions. These are key when investigating a leaked secret.
- Logs are written to stdout, so Docker log rotation (`max-size`) keeps the disk from filling up.

## 3. Which alerts matter, and which should not alert

**Alerts that matter (page or notify):**

| Alert | Condition | Severity |
|---|---|---|
| Service down | `up == 0` for 1 minute | Critical |
| High error rate | 5xx responses above 5% of requests for 5 minutes | Critical |
| Container restarting | More than 3 restarts in 15 minutes | Critical |
| High CPU | Host CPU above 85% for 10 minutes | Warning |
| Low disk | Disk free below 15% | Warning |
| High memory | Host memory above 90% for 10 minutes | Warning |
| High latency | p95 above 2 seconds for 10 minutes | Warning |

**Alerts that should not fire (to avoid noise):**
- A single 4xx response (users mistyping or invalid input is normal).
- Short CPU or memory spikes under 5 minutes, such as during a deploy or startup.
- A single failed scrape. Alerts use a `for:` duration so a brief blip does not fire.
- Individual JVM garbage collection events.
- Container restarts that happen during an intentional deployment.
- Every informational log line. Alerts are tied to symptoms users feel, not to every internal event.

Every alert has a `for:` duration, a severity and a clear name, so each notification is actionable.

## 4. How operational issues are detected early
- **Health checks:** Docker health checks plus the pipeline's `/actuator/health` check catch a bad release within seconds of deployment.
- **Prometheus alerts and Grafana dashboard:** warnings (CPU, disk, memory, latency) fire before a failure, and critical alerts fire when users are affected.
- **Trends:** disk and memory graphs show slow growth, so problems are noticed before the thresholds are hit.
- **Alert on symptoms:** the error rate and latency alerts reflect what users experience, even when the cause is unknown.
- **Runbook:** for each alert, check `docker ps`, then `docker logs`, then the Grafana dashboard. If a release is the cause, roll back as described in `FAILURE_AND_ROLLBACK.md`.
- **Possible improvements:** Alertmanager or Grafana contact points (Slack or email), an external uptime check on the public URL, and CloudWatch alarms for RDS.
