#!/bin/bash
# Runs ON the EC2 server (by hand or from the pipeline via SSM).
set -euo pipefail
cd /opt/todo
git pull --ff-only

REGION=ap-southeast-2
DOCKERHUB_USER="${DOCKERHUB_USER:-sudharshan34}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

get() {
  aws ssm get-parameter --region "$REGION" --with-decryption \
    --name "/todo/$1" --query Parameter.Value --output text
}

# Build .env from SSM Parameter Store (nothing secret is stored in git)
{
  echo "DB_URL=$(get DB_URL)"
  echo "DB_USER=$(get DB_USER)"
  echo "DB_PASSWORD=$(get DB_PASSWORD)"
  echo "COHERE_API_KEY=$(get COHERE_API_KEY)"
  echo "SLACK_WEBHOOK_URL=$(get SLACK_WEBHOOK_URL)"
  echo "GRAFANA_ADMIN_PASSWORD=$(get GRAFANA_ADMIN_PASSWORD)"
  echo "FRONTEND_PORT=80"
  echo "BACKEND_IMAGE=${DOCKERHUB_USER}/todo-backend:${IMAGE_TAG}"
  echo "FRONTEND_IMAGE=${DOCKERHUB_USER}/todo-frontend:${IMAGE_TAG}"
} > .env
chmod 600 .env

docker compose pull backend frontend
docker compose up -d --no-build --remove-orphans

# Health check through nginx -> backend -> RDS. Fail fast if not healthy.
for i in $(seq 1 30); do
  if curl -fsS http://localhost/api/todos > /dev/null; then
    echo "Health check passed"
    exit 0
  fi
  echo "Waiting for app ($i/30)..."
  sleep 5
done
echo "Health check FAILED"
docker compose logs --tail 50 backend
exit 1