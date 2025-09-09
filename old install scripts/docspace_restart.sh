#!/bin/bash

set -e

CONTAINERS=(
  dashboards
  docspace
  ds
  proxy
  proxy-ssl
  rabbitmq
  redis
  identity
  notify
  opensearch
  healthchecks
  db
  migration-runner
  fluent
  # add any additional or missing service names here
)

echo "Stopping containers..."
for name in "${CONTAINERS[@]}"; do
  if docker ps -a --format '{{.Names}}' | grep -q "^$name$"; then
    echo "Stopping $name..."
    docker stop "$name" || true
    echo "Removing $name..."
    docker rm "$name" || true
  fi
done

echo "Starting containers..."
for name in "${CONTAINERS[@]}"; do
  YAML="${name}.yml"
  if [ -f "$YAML" ]; then
    echo "Starting $name from $YAML..."
    docker compose -f "$YAML" up -d || docker-compose -f "$YAML" up -d
  fi
done

echo "All containers restarted."
