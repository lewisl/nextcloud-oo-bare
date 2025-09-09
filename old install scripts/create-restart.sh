for f in *.yml; do
  docker compose -f "$f" up -d
done


docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Health}}"
