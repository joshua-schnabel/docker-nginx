#!/usr/bin/env bash
set -Eeuo pipefail

# This script runs a set of integration tests against the built image.
# It does NOT test ACME flows. It only checks container boot, HTTP, metrics,
# TLS self-signed generation, and FORCE_TLS redirect behavior.

IMAGE=${IMAGE:-docker-nginx:test}
NAME_PREFIX=nginx-it-$$

cleanup() {
  echo "Cleaning up containers..."
  docker rm -f ${NAME_PREFIX}-off 2>/dev/null || true
  docker rm -f ${NAME_PREFIX}-tls 2>/dev/null || true
  docker rm -f ${NAME_PREFIX}-redir 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait_healthy() {
  cid=$1
  i=0
  until [ "$i" -ge 40 ]; do
    if docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null | grep -q healthy; then
      return 0
    fi
    i=$((i+1))
    sleep 1
  done
  echo "Container $cid did not become healthy"
  return 1
}

req_in() {
  # curl inside container: $1=cid, $2=method, $3=url, [4+]=extra curl args
  cid="$1"; shift
  method="$1"; shift
  url="$1"; shift
  docker exec "$cid" curl -fsS -X "$method" --max-time 8 "$url" "$@"
}

# Test 1: TLS_MODE=off (default config on 8080)
# Expect: health OK on 4444, GET / returns default page 200 on 8080
cid_off=$(docker run -d --name ${NAME_PREFIX}-off \
  --health-cmd "wget -qO- http://127.0.0.1:4444/health >/dev/null || exit 1" \
  --health-interval 2s --health-timeout 2s --health-retries 15 --health-start-period 5s \
  "$IMAGE")

wait_healthy "$cid_off"

# health
req_in "$cid_off" GET http://127.0.0.1:4444/health >/dev/null
# default page
status=$(docker exec "$cid_off" sh -c 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/')
[ "$status" = "200" ] || { echo "Expected 200 on / with TLS off, got $status"; exit 1; }

# metrics
req_in "$cid_off" GET http://127.0.0.1:4444/metrics | grep -q nginx_http_connections || { echo "Missing metrics output"; exit 1; }

# nginx_status endpoint
req_in "$cid_off" GET http://127.0.0.1:4444/nginx_status | grep -qi 'Active connections' || { echo "Missing nginx_status"; exit 1; }

# custom Server header
hdrs=$(docker exec "$cid_off" sh -c 'curl -sI http://127.0.0.1:8080/')
echo "$hdrs" | grep -qi "These aren't the droids you're looking for" || { echo "Missing overridden Server header"; exit 1; }

# Test 2: TLS custom (self-signed certs should be generated)
# Expect: 200 on HTTPS port 8443 with -k
cid_tls=$(docker run -d --name ${NAME_PREFIX}-tls \
  -e TLS_MODE=custom \
  --health-cmd "wget -qO- http://127.0.0.1:4444/health >/dev/null || exit 1" \
  --health-interval 2s --health-timeout 2s --health-retries 15 --health-start-period 5s \
  "$IMAGE")

wait_healthy "$cid_tls"

status_https=$(docker exec "$cid_tls" sh -c 'curl -k -s -o /dev/null -w "%{http_code}" https://127.0.0.1:8443/')
[ "$status_https" = "200" ] || { echo "Expected 200 on HTTPS / with TLS custom, got $status_https"; exit 1; }

# cert/key should exist
docker exec "$cid_tls" sh -c 'test -f /application/data/certs/localhost.pem && test -f /application/data/certs/localhost.key'

# Test 3: FORCE_TLS redirect
# Expect: 301 redirect on 8080 to https
cid_redir=$(docker run -d --name ${NAME_PREFIX}-redir \
  -e TLS_MODE=custom -e FORCE_TLS=true \
  --health-cmd "wget -qO- http://127.0.0.1:4444/health >/dev/null || exit 1" \
  --health-interval 2s --health-timeout 2s --health-retries 15 --health-start-period 5s \
  "$IMAGE")

wait_healthy "$cid_redir"

redir_code=$(docker exec "$cid_redir" sh -c 'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/')
[ "$redir_code" = "301" ] || { echo "Expected 301 on HTTP when FORCE_TLS=true, got $redir_code"; exit 1; }

# Optional: Follow redirect and expect 200 on HTTPS
final_code=$(docker exec "$cid_redir" sh -c 'curl -k -s -L -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/')
[ "$final_code" = "200" ] || { echo "Expected 200 after redirect follow, got $final_code"; exit 1; }

# logs should be present and writable
docker exec "$cid_redir" sh -c 'test -w /application/data/logs/access.log && test -w /application/data/logs/error.log'

echo "All tests passed."
