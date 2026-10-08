# Failure and Rollback Scenarios

Every release image is tagged with its Git commit SHA, so any earlier version can be identified and redeployed.

## 1. A faulty version is deployed. How do I roll back?
- **Detect:** the pipeline's post-deploy health check (`/actuator/health`) fails, or Grafana/Prometheus alerts fire (error rate, service down).
- **Fastest rollback (no code change):** in GitHub, open Actions, choose the last known good run and click "Re-run all jobs". The pipeline redeploys the image built from that commit.
- **Clean rollback (Git history):** run `git revert <bad-commit>` and push to main. The pipeline builds, tests and deploys the reverted code automatically, so history shows what happened.
- **Emergency rollback on the server:** connect with SSM Session Manager, point the compose file at the previous SHA-tagged image already in the registry, then run `docker compose up -d`.
- **Verify:** `curl http://localhost:8080/actuator/health` returns `{"status":"UP"}` and the Grafana error rate returns to normal.
- Old images stay in the registry, so rollback never needs a rebuild.

## 2. The application crashes after deployment. What happens?
- The Docker health check marks the backend `unhealthy`, and the container restart policy restarts it automatically.
- The pipeline's health check step fails, so the deploy job is marked failed and the team is notified in GitHub.
- Prometheus alerts fire: "Service down" (`up == 0` for 1 minute) and "Container restarting" (more than 3 restarts in 15 minutes).
- The frontend and the monitoring stack keep running, because each service is a separate container.
- Diagnosis: `docker ps`, then `docker logs todo-backend-1`. Typical causes are a wrong `DB_URL`, a blocked RDS security group (`Connect timed out`) or a missing environment variable. If the cause is not an environment fix, roll back as in section 1.

## 3. The CI/CD tool is unavailable. Can I still deploy?
Yes. The deployment does not depend on GitHub Actions.
- Connect to the EC2 instance with SSM Session Manager (this uses AWS, not GitHub).
- Run `cd /opt/todo && git pull && bash scripts/deploy.sh`. This is the same script the pipeline runs.
- If the registry is also unreachable, the images already on the server keep running. Images can also be built on the server with `docker compose up -d --build`.
- Once the CI tool is back, a push to main resumes automated deployment. Manual deploys are recorded in the commit history.

## 4. Secrets are leaked. What steps do I take?
1. **Contain:** immediately rotate or revoke the leaked secret (Cohere API key in the Cohere dashboard, Slack webhook by regenerating it, DB password by changing it in RDS).
2. **Replace:** update the new values in `/opt/todo/.env` on the server and in GitHub Actions secrets, then redeploy (`bash scripts/deploy.sh`).
3. **Investigate:** check CloudTrail, GitHub audit logs and the Actions logs to see how the secret leaked and whether it was used.
4. **Clean up:** if it was committed to Git, removing the file is not enough. Rewrite the history (for example with `git filter-repo`) or treat the repository as compromised, and rely on the rotation in step 1.
5. **Prevent:** keep `.env` in `.gitignore`, keep only `.env.example` in Git, and enable GitHub secret scanning and push protection. Longer term, move secrets to SSM Parameter Store or Secrets Manager.

## 5. The EC2 instance fails. How do I recover?
- **Detect:** Prometheus "Service down" alert, a failed EC2 status check, or the pipeline health check failing.
- **Short outage or hang:** reboot the instance from the EC2 console. Docker is enabled at boot and containers restart automatically.
- **Instance lost:** launch a new instance with the same IAM role (`todo-ec2-role`) and security group (`todo-ec2-sg`), then re-associate the Elastic IP so the public address does not change.
- **Rebuild:** install Docker, clone the repository to `/opt/todo`, recreate `/opt/todo/.env` from `.env.example`, and run `bash scripts/deploy.sh`. Steps are in `aws/aws-setup.md`.
- **Data impact:** none. The application has no state on the server, because the data lives in RDS and the images are in the registry. Only Prometheus history and Grafana settings on the instance would be lost (they can be restored from the repository files).
- **Improvement:** an Auto Scaling group of one instance, or an EC2 auto-recovery alarm, would make this automatic.

## 6. The RDS database becomes unavailable. What is the impact and the recovery plan?
- **Impact:** the backend cannot read or write to-dos, so Add Todo and Summarize fail and `/actuator/health` reports DOWN. The frontend still loads but shows errors. The Prometheus service-down and error-rate alerts fire. No data is lost by an outage alone.
- **Recovery by cause:**
  - Network or security group problem: restore the `todo-rds-sg` rule (MySQL 3306 from `todo-ec2-sg`).
  - Instance problem or maintenance: wait for the automatic restart, or reboot the instance from the RDS console.
  - Data corruption or deletion: restore from backup (see below).
- **Backups:** automated daily backups with point-in-time recovery (retention set to 7 days). Restoring creates a new instance, so update `DB_URL` in `/opt/todo/.env` to the new endpoint and redeploy. A manual snapshot is taken before risky changes.
- **Multi-AZ:** this setup uses a single-AZ database to stay in the free tier. In production, Multi-AZ RDS fails over to a standby in another zone automatically, usually within one to two minutes, with no change to the endpoint.
- **Application behavior:** the connection pool retries, and the backend recovers by itself once the database is reachable again.
