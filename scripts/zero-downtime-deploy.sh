#!/bin/bash
set -e

# Zero-downtime deployment script for docker compose
# This creates new containers before removing old ones

COMPOSE_FILE="docker-compose.prod.yml"

echo "[Deploy] Starting zero-downtime deployment..."

# Build new images
echo "[Deploy] Building new images..."
docker compose -f $COMPOSE_FILE build

# Rename old containers to keep them running
echo "[Deploy] Preparing old containers..."
for service in pyramid worker qreader-primary proxy; do
  old_container=$(docker compose -f $COMPOSE_FILE ps -q $service 2>/dev/null || echo "")
  if [ -n "$old_container" ]; then
    echo "[Deploy] Renaming old $service container"
    docker rename $old_container "${service}-old-$(date +%s)" 2>/dev/null || true
  fi
done

# Start new containers
echo "[Deploy] Starting new containers..."
docker compose -f $COMPOSE_FILE up -d

# Wait for health checks on pyramid service
echo "[Deploy] Waiting for health checks..."
max_wait=60
wait_time=0
while [ $wait_time -lt $max_wait ]; do
  pyramid_container=$(docker compose -f $COMPOSE_FILE ps -q pyramid)
  if [ -n "$pyramid_container" ]; then
    health=$(docker inspect --format='{{.State.Health.Status}}' $pyramid_container 2>/dev/null || echo "none")
    if [ "$health" = "healthy" ]; then
      echo "[Deploy] ✓ New containers are healthy!"
      break
    fi
  fi
  echo "[Deploy] Waiting for health check... ($wait_time/$max_wait)"
  sleep 3
  wait_time=$((wait_time + 3))
done

if [ $wait_time -ge $max_wait ]; then
  echo "[Deploy] ✗ ERROR: New containers failed health check"
  echo "[Deploy] Rolling back..."
  docker compose -f $COMPOSE_FILE down
  # Restore old containers
  for service in pyramid worker qreader-primary proxy; do
    old_container=$(docker ps -a --filter "name=${service}-old-" --format "{{.ID}}" | head -1)
    if [ -n "$old_container" ]; then
      docker rename $old_container $service 2>/dev/null || true
      docker start $old_container 2>/dev/null || true
    fi
  done
  exit 1
fi

# Remove old containers
echo "[Deploy] Removing old containers..."
docker ps -a --filter "name=-old-" --format "{{.ID}}" | xargs -r docker rm -f

# Clean up unused images
echo "[Deploy] Cleaning up..."
docker image prune -f

echo "[Deploy] ✓ Zero-downtime deployment complete!"
