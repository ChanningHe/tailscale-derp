#!/usr/bin/env bash
# Smoke-test a derper image: runs rootless, serves plain HTTP, answers DERP upgrades.
set -euo pipefail

readonly IMAGE="${1:?usage: smoke-test.sh IMAGE}"
readonly CONTAINER_PORT=31478
readonly HOST_PORT="${HOST_PORT:-${CONTAINER_PORT}}"
readonly EXPECTED_USER="65532:65532"
readonly STARTUP_TIMEOUT_SECONDS=30
readonly NAME="derper-smoke-$$"

fail() { echo "FAIL: $*" >&2; docker logs "$NAME" >&2 || true; exit 1; }
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

user="$(docker image inspect -f '{{.Config.User}}' "$IMAGE")"
[[ "$user" == "$EXPECTED_USER" ]] || fail "image user is '$user', want '$EXPECTED_USER'"

docker run -d --name "$NAME" -p "127.0.0.1:${HOST_PORT}:${CONTAINER_PORT}" "$IMAGE" >/dev/null

base="http://127.0.0.1:${HOST_PORT}"
for _ in $(seq "$STARTUP_TIMEOUT_SECONDS"); do
  curl -fsS -o /dev/null "$base/derp/probe" 2>/dev/null && break
  sleep 1
done

curl -fsS -o /dev/null "$base/derp/probe" || fail "/derp/probe not reachable"
code="$(curl -sS -o /dev/null -w '%{http_code}' "$base/generate_204")"
[[ "$code" == "204" ]] || fail "/generate_204 returned $code"

# A DERP upgrade over plain HTTP (what the reverse proxy forwards) must get 101.
code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 2 \
  -H 'Upgrade: DERP' -H 'Connection: Upgrade' "$base/derp" 2>/dev/null || true)"
[[ "$code" == "101" ]] || fail "/derp upgrade returned $code, want 101"

docker logs "$NAME" 2>&1 | grep -q "serving on :${CONTAINER_PORT}" || fail "not serving plain HTTP on :${CONTAINER_PORT}"

echo "OK: $IMAGE"
