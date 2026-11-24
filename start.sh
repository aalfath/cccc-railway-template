#!/bin/bash
# CCCC on Railway: prepare the /data volume, make sure the admin Access Token from
# CCCC_ADMIN_TOKEN exists, seed the Pi agent's OpenAI-compatible provider, then run
# `cccc --headless` as the unprivileged "node" user (Claude Code refuses to skip
# permission prompts as root). Exits non-zero whenever CCCC stops on its own, so
# Railway's ON_FAILURE restart policy brings it back.
set -euo pipefail
log() { echo "cccc-railway: $*"; }

APP_USER=node
DATA=/data
export CCCC_HOME="${CCCC_HOME:-$DATA/cccc}"
export HOME="$DATA/home"
export CCCC_WEB_HOST=0.0.0.0
export CCCC_WEB_PORT="${PORT:-8848}"
# Upstream's own Docker image bakes CCCC_WEB_ALLOW_UNAUTHENTICATED=1; we never set it.
unset CCCC_WEB_ALLOW_UNAUTHENTICATED || true

# --- Admin Access Token ---------------------------------------------------------
TOKEN="${CCCC_ADMIN_TOKEN:-}"
if [ "${#TOKEN}" -lt 24 ] || ! printf '%s' "$TOKEN" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_-]+$'; then
	echo "cccc-railway: CCCC_ADMIN_TOKEN must be set (24+ letters, digits, _ or -). Refusing to start an open agent console." >&2
	exit 1
fi

mkdir -p "$CCCC_HOME" "$HOME" "$DATA/workspace"
chown "$APP_USER:$APP_USER" "$DATA" "$CCCC_HOME" "$HOME" "$DATA/workspace"
chmod 700 "$CCCC_HOME" "$HOME"
# First boot on a volume restored as root: hand everything back to the app user.
if [ -n "$(find "$DATA" -xdev -not -user "$APP_USER" -print -quit 2>/dev/null)" ]; then
	chown -R "$APP_USER:$APP_USER" "$DATA"
fi

# The token store is CCCC's own access_tokens.yaml. On the first boot we write it
# with one admin token (the value of CCCC_ADMIN_TOKEN). Later boots only add that
# token again if it is missing (for example after you change the variable), and
# leave every token you created in Settings > Web Access alone.
TOKENS="$CCCC_HOME/access_tokens.yaml"
now=$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)
entry=$(printf "  '%s':\n    user_id: Railway administrator\n    allowed_groups: []\n    is_admin: true\n    created_at: '%s'\n    updated_at: '%s'\n" "$TOKEN" "$now" "$now")
if [ ! -s "$TOKENS" ] || ! grep -q '^  [^ ].*:$' "$TOKENS"; then
	printf 'tokens:\n%s\n' "$entry" > "$TOKENS.tmp" && mv "$TOKENS.tmp" "$TOKENS"
	log "admin Access Token created from CCCC_ADMIN_TOKEN"
elif ! grep -qE "^  '?${TOKEN}'?:\$" "$TOKENS"; then
	printf '%s\n' "$entry" >> "$TOKENS"
	log "CCCC_ADMIN_TOKEN was not in the token store: added it as an admin token"
fi
chown "$APP_USER:$APP_USER" "$TOKENS"; chmod 600 "$TOKENS"
rm -f "$CCCC_HOME/web_bootstrap_token"
# The token is in the store now; agents started by CCCC don't need to see it.
unset CCCC_ADMIN_TOKEN TOKEN

# --- Agent CLIs: onboarding and the Pi provider ---------------------------------
[ -s "$HOME/.claude.json" ] || echo '{"hasCompletedOnboarding":true,"bypassPermissionsModeAccepted":true}' > "$HOME/.claude.json"
LLM_BASE_URL="${LLM_BASE_URL:-https://api.openai.com/v1}"
LLM_MODEL="${LLM_MODEL:-gpt-5.4-mini}"
LLM_CONTEXT_WINDOW="${LLM_CONTEXT_WINDOW:-128000}"
AGENT_DIR="$HOME/.pi/agent"
mkdir -p "$AGENT_DIR"
if [ -n "${LLM_API_KEY:-}" ]; then
	# The key itself never touches the disk: models.json refers to $LLM_API_KEY.
	MODELS="$AGENT_DIR/models.json"; SETTINGS="$AGENT_DIR/settings.json"; P=openai-compatible
	[ -s "$MODELS" ] || echo '{}' > "$MODELS"
	[ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"
	if jq -e --arg p "$P" '(.providers[$p] // null) == null or .providers[$p].apiKey == "$LLM_API_KEY"' "$MODELS" >/dev/null 2>&1; then
		jq --arg p "$P" --arg url "$LLM_BASE_URL" --arg m "$LLM_MODEL" --argjson ctx "$LLM_CONTEXT_WINDOW" \
			'.providers = (.providers // {}) | .providers[$p] = {baseUrl: $url, api: "openai-completions", apiKey: "$LLM_API_KEY", models: [{id: $m, name: $m, contextWindow: $ctx}]}' \
			"$MODELS" > "$MODELS.tmp" && mv "$MODELS.tmp" "$MODELS"
		jq --arg p "$P" --arg m "$LLM_MODEL" 'if (.defaultProvider // $p) == $p then .defaultProvider = $p | .defaultModel = $m else . end' \
			"$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
		log "Pi provider '$P' set to $LLM_BASE_URL, default model $LLM_MODEL"
	else
		log "Pi provider '$P' was changed by hand; leaving it alone"
	fi
	chmod 600 "$MODELS"
fi
chown -R "$APP_USER:$APP_USER" "$HOME/.claude.json" "$HOME/.pi"

# --- Small-plan limits -----------------------------------------------------------
# Railway shows every host CPU inside a 1 vCPU service; size thread pools from the
# cgroup quota instead.
cpus=1
if [ -r /sys/fs/cgroup/cpu.max ]; then
	read -r q p < /sys/fs/cgroup/cpu.max || true
	if [ "${q:-max}" != max ] && [ -n "${p:-}" ]; then cpus=$(( (q + p - 1) / p )); else cpus=$(nproc); fi
fi
[ "$cpus" -lt 1 ] && cpus=1; [ "$cpus" -gt 8 ] && cpus=8
export TOKIO_WORKER_THREADS="${TOKIO_WORKER_THREADS:-$((cpus < 2 ? 2 : cpus))}"
export UV_THREADPOOL_SIZE="${UV_THREADPOOL_SIZE:-$((cpus < 2 ? 2 : cpus))}"
export RAYON_NUM_THREADS="${RAYON_NUM_THREADS:-$cpus}"
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"
limit_mb=0
if [ -r /sys/fs/cgroup/memory.max ] && [ "$(cat /sys/fs/cgroup/memory.max)" != max ]; then
	limit_mb=$(( $(cat /sys/fs/cgroup/memory.max) / 1048576 ))
fi

# --- Run CCCC ----------------------------------------------------------------------
cd "$DATA/workspace"
log "CCCC $(cccc --version 2>/dev/null | head -1) starting on port $CCCC_WEB_PORT (memory limit ${limit_mb} MB, ${cpus} CPU)"
setpriv --reuid="$APP_USER" --regid="$APP_USER" --init-groups -- \
	env HOME="$HOME" USER="$APP_USER" LOGNAME="$APP_USER" cccc --headless &
app=$!
stopping=0
trap 'stopping=1; kill -TERM "$app" 2>/dev/null || true' TERM INT
set +e
wait "$app"; code=$?
while [ "$stopping" = 1 ] && kill -0 "$app" 2>/dev/null; do wait "$app"; code=$?; done
set -e
if [ "$stopping" = 1 ]; then exit 0; fi
log "cccc exited on its own (code $code); exiting non-zero so Railway restarts the service"
[ "$code" -eq 0 ] && code=1
exit "$code"
