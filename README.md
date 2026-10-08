# Todo Summary Assistant: DevOps Delivery Pipeline

A full-stack app to manage to-do items, summarize pending tasks with the Cohere LLM and send the summary to Slack. This repository adds a production-style DevOps pipeline: Docker, GitHub Actions CI/CD, AWS EC2 + RDS, and Prometheus + Grafana monitoring.

## Features
- Create, edit and delete to-do items.
- Summarize pending to-dos with Cohere and post the summary to a Slack channel via an Incoming Webhook.
- Success/failure notifications in the UI.

## Tech stack
- Frontend: React, Axios
- Backend: Spring Boot (Java 17), Maven, Spring Data JPA, OkHttp
- Database: MySQL (AWS RDS in production)
- DevOps: Docker, Docker Compose, GitHub Actions, AWS EC2/RDS/IAM, Prometheus, Grafana, node-exporter, cAdvisor

## Architecture
GitHub push -> GitHub Actions (test, build, push images, deploy) -> EC2 (Docker Compose: frontend, backend, Prometheus, Grafana, node-exporter, cAdvisor) -> RDS MySQL (private).
See `aws/architecture-diagram.png` and `aws/aws-setup.md`.

## Runtime requirements
- Backend: Java 17+, Maven, MySQL 8
- Frontend: Node.js 18+, npm
- Docker and Docker Compose v2
- A Cohere API key and a Slack Incoming Webhook URL

## Environment variables
All settings are read from the environment. No secrets are committed (see `.env.example`).

| Variable | Purpose |
|---|---|
| DB_URL | JDBC URL of MySQL (RDS endpoint in production) |
| DB_USER | Database user |
| DB_PASSWORD | Database password |
| COHERE_API_KEY | Cohere API key (create one at cohere.ai) |
| SLACK_WEBHOOK_URL | Slack Incoming Webhook URL (create at api.slack.com/apps) |
| CORS_ALLOWED_ORIGINS | Allowed frontend origin(s) |

## Run locally
1. Start MySQL: `docker run --name todo-mysql -e MYSQL_ROOT_PASSWORD=<password> -e MYSQL_DATABASE=todo_db -p 3306:3306 -d mysql:8`
2. Set the variables in the terminal (Windows: `set DB_PASSWORD=<password>`, Linux/macOS: `export DB_PASSWORD=<password>`). Do not write them in any file.
3. Backend: `cd Backend/todo-summary-assistant && mvn spring-boot:run` (port 8080).
4. Frontend: `cd Frontend/todo && npm install && npm start` (port 3000).

Or run the whole stack with Docker Compose: copy `.env.example` to `.env`, fill in the values, then `docker compose up -d --build`.

## Docker design choices
- Multi-stage builds: build tools (Maven, Node) stay in the build stage and only the runtime is shipped, which keeps images small.
- Containers run as a non-root user.
- Configuration comes from environment variables only.
- `.dockerignore` files keep the build context and images lean.
- Health checks let Docker and the pipeline detect an unhealthy backend.

## CI/CD pipeline (`.github/workflows/ci-cd.yml`)
Triggers on push and pull request to main.
1. **backend-test**: builds the backend with Maven and runs tests.
2. **frontend-test**: installs dependencies, runs tests and builds the React app.
3. **build-and-push**: builds both Docker images, tags them with the commit SHA and pushes them to <<Docker Hub or ECR>>.
4. **deploy**: connects to EC2 and runs `scripts/deploy.sh`, which pulls the new images and restarts the containers.
5. **health check**: calls `/actuator/health` after deployment; the job fails if it is not UP.

Each stage depends on the previous one (`needs`), so the pipeline fails fast. All credentials are stored in GitHub Actions secrets.

## AWS deployment
- EC2 with Docker, accessed through SSM Session Manager, using the IAM role `todo-ec2-role` (no AWS keys in code).
- RDS MySQL (`database-1`), not publicly accessible. Its security group `todo-rds-sg` allows port 3306 only from `todo-ec2-sg`.
- DB credentials are kept in `/opt/todo/.env` on the server, outside the repository.
- Details: `aws/aws-setup.md`.

## Monitoring
Prometheus scrapes the backend (`/actuator/prometheus`), node-exporter and cAdvisor. Grafana shows request rate, errors, latency, CPU, memory, disk and container restarts. Alert rules are in `monitoring/alert-rules.yml`.
- App: `http://<<EC2-IP>>`
- Grafana: `http://<<EC2-IP>>:3001`
- Prometheus: `http://<<EC2-IP>>:9090`

## Changes to application code (DevOps enablement only)
- `application.properties` reads all settings from environment variables instead of hardcoded values.
- Added Spring Boot Actuator and the Micrometer Prometheus registry to expose `/actuator/health` and `/actuator/prometheus`.
- The CI frontend build uses `CI=false` so ESLint warnings do not fail the build.
No business logic was changed.

## Assumptions
- The default VPC and a public subnet are used for EC2. For RDS, "private" means Public access = No plus a restricted security group.
- Free-tier instance types are used. AWS resources should be stopped or deleted after the review.
- Failure and rollback plans: `FAILURE_AND_ROLLBACK.md`. Monitoring design: `MONITORING_AND_OPERATIONS.md`.

## Demo images

![Screenshot (1146)](https://github.com/user-attachments/assets/53fe53e3-b527-4659-9ab6-b462ae034fbd)

![Screenshot (1144)](https://github.com/user-attachments/assets/474b1a46-36c8-4407-8bf9-a46ca911603b)

![Screenshot (1143)](https://github.com/user-attachments/assets/1e9f8783-d0df-42ce-a3f8-ec7ca5e7c078)
