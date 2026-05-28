#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
default_runtime_image="$(cat "$repo_root/config/agent_runtime_image.txt")"
image="${MOONCRAFT_RUNTIME_IMAGE_CHECK_IMAGE:-${MOONCRAFT_AGENT_RUNTIME_DEPS_CHECK_IMAGE:-${MOONCRAFT_CODEX_DEPS_CHECK_DOCKER_IMAGE:-${1:-$default_runtime_image}}}}"
platform="${MOONCRAFT_RUNTIME_IMAGE_CHECK_PLATFORM:-${MOONCRAFT_AGENT_RUNTIME_DEPS_CHECK_PLATFORM:-${MOONCRAFT_CODEX_DEPS_CHECK_DOCKER_PLATFORM:-${2:-host}}}}"
tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/mooncraft-runtime-image-check.XXXXXX")"
container_name="mooncraft-runtime-image-check-$$"
cleanup() {
  docker rm -f "$container_name" >/dev/null 2>&1 || true
  rm -rf "$tmp_root"
}
trap cleanup EXIT
mkdir -p "$tmp_root/workspace" "$tmp_root/home" "$tmp_root/artifacts"
chmod -R a+rwX "$tmp_root"
mkdir -p "$tmp_root/workspace/fakebin"
cat >"$tmp_root/workspace/fakebin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/tmp/mooncraft-runtime-image-check-prompt.txt
printf '%s\n' '{"type":"thread.started","thread_id":"thread-image-check"}'
printf '%s\n' '{"type":"turn.started"}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","id":"msg-1","text":"Runtime image check completed."}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}'
EOF
chmod +x "$tmp_root/workspace/fakebin/codex"
cat >"$tmp_root/workspace/mooncraft-preview.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
port="${1:-${PORT:-4792}}"
python3 -m http.server "$port" --bind 0.0.0.0 >/tmp/mooncraft-preview.log 2>&1
EOF
chmod +x "$tmp_root/workspace/mooncraft-preview.sh"
printf '%s\n' '<!doctype html><title>MoonCraft Runtime Image Check</title>' >"$tmp_root/workspace/index.html"

if [[ "$platform" = host || "$platform" = auto ]]; then
  platform="$("$repo_root/scripts/publish_agent_runtime_image.sh" host-platform)"
fi

case "$platform" in
  linux/amd64 | linux/arm64) ;;
  *)
    echo "Unsupported runtime image check platform: $platform" >&2
    echo "Use host, linux/amd64, or linux/arm64." >&2
    exit 64
    ;;
esac

docker run --rm \
  --platform "$platform" \
  -v "$tmp_root/workspace:/workspace" \
  -v "$tmp_root/home:/home/mooncraft" \
  -v "$tmp_root/artifacts:/artifacts" \
  -w /workspace \
  "$image" \
  bash -lc '
    set -euo pipefail
    test "$(id -u)" != "0"
    test "${HOME:-}" = "/home/mooncraft"
    test "${MOON_HOME:-}" = "/home/mooncraft/.moon"
    test -w /workspace
    test -w /home/mooncraft
    test -w "$MOON_HOME"
    test -w /artifacts
    command -v rg >/dev/null
    command -v jq >/dev/null
    command -v sort >/dev/null
    command -v cc >/dev/null
    command -v gcc >/dev/null
    command -v make >/dev/null
    command -v pkg-config >/dev/null
    command -v moon >/dev/null
    command -v codex >/dev/null
    command -v python3 >/dev/null
    command -v mooncraft-runtime-service >/dev/null
    moon version >/dev/null
    python3 --version >/dev/null
    codex --version >/dev/null
    printf "%s\n" "int main(void) { return 0; }" > /tmp/mooncraft-runtime-check.c
    cc /tmp/mooncraft-runtime-check.c -o /tmp/mooncraft-runtime-check
    /tmp/mooncraft-runtime-check
    test -d "$HOME/.codex/skills"
    test -d /opt/mooncraft/templates
    echo "Runtime image tool check completed."
  '

docker run -d --rm \
  --name "$container_name" \
  --platform "$platform" \
  -e PATH="/workspace/fakebin:/opt/moon/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  -v "$tmp_root/workspace:/workspace" \
  -v "$tmp_root/home:/home/mooncraft" \
  -w /workspace \
  "$image" >/dev/null

for _ in $(seq 1 40); do
  if docker exec "$container_name" curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; then
    docker exec "$container_name" curl -fsS http://127.0.0.1:8080/runs/missing >/dev/null 2>&1 && {
      echo "Runtime Service returned success for a missing run." >&2
      exit 1
    }
    docker exec "$container_name" curl -fsS \
      -H "Content-Type: application/json" \
      -d '{"run_id":"run-image-check","prompt":"Build a tiny app for runtime image validation."}' \
      http://127.0.0.1:8080/exec >/dev/null
    for _ in $(seq 1 40); do
      status="$(
        docker exec "$container_name" sh -lc \
          'curl -fsS http://127.0.0.1:8080/runs/run-image-check | jq -er .status'
      )"
      if [[ "$status" = "succeeded" ]]; then
        break
      fi
      if [[ "$status" = "failed" ]]; then
        docker exec "$container_name" curl -fsS http://127.0.0.1:8080/runs/run-image-check >&2 || true
        echo "Runtime Service image-check run failed." >&2
        exit 1
      fi
      sleep 0.25
    done
    if [[ "${status:-}" != "succeeded" ]]; then
      docker exec "$container_name" curl -fsS http://127.0.0.1:8080/runs/run-image-check >&2 || true
      echo "Runtime Service image-check run did not finish." >&2
      exit 1
    fi
    docker exec "$container_name" sh -lc \
      'curl -fsS "http://127.0.0.1:8080/runs/run-image-check/events?after=0" | jq -e ".events | length > 0" >/dev/null'
    docker exec "$container_name" curl -fsS http://127.0.0.1:8080/preview >/dev/null
    echo "Runtime Service check completed."
    exit 0
  fi
  sleep 0.5
done

docker logs "$container_name" >&2 || true
echo "Runtime Service did not become healthy at /health." >&2
exit 1
