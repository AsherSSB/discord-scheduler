#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
CONFIG_FILE="${CONFIG_FILE:-"$PROJECT_ROOT/.server.cfg"}"
ENV_FILE="${ENV_FILE:-"$PROJECT_ROOT/.env"}"

ask() {
  local prompt_text="$1" default_value="$2" input
  read -rp "$prompt_text [$default_value]: " input || true
  echo "${input:-$default_value}"
}

trim_quotes() {
  local s="$1"
  s="${s%\"}"; s="${s#\"}"
  s="${s%\'}"; s="${s#\'}"
  printf '%s' "$s"
}

bad_value() {
  case "${1,,}" in ""|changeme|your_*|xxx|xxxxx|"") return 0;; esac
  return 1
}

env_get() {
  [ -f "$ENV_FILE" ] || { echo ""; return 0; }
  local key="$1"
  grep -m1 -E "^[[:space:]]*$key[[:space:]]*=" "$ENV_FILE" 2>/dev/null \
    | sed -E 's/^[^=]*=//' | tr -d '\r' | sed -E 's/^[[:space:]]+//' \
    | sed -E 's/[[:space:]]+$//'
}

env_set() {
  mkdir -p "$(dirname "$ENV_FILE")"
  touch "$ENV_FILE"
  local key="$1" val="$2"
  if grep -q -E "^[[:space:]]*$key[[:space:]]*=" "$ENV_FILE"; then
    sed -E -i "s|^[[:space:]]*$key[[:space:]]*=.*|$key=$val|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
  fi
}

ensure_env() {
  local cid csec redir
  cid="$(trim_quotes "$(env_get DISCORD_CLIENT_ID)")"
  csec="$(trim_quotes "$(env_get DISCORD_CLIENT_SECRET)")"
  redir="$(trim_quotes "$(env_get DISCORD_REDIRECT_URI)")"
  if bad_value "$cid" || bad_value "$csec" || [ ! -f "$ENV_FILE" ]; then
    [ -t 0 ] || { echo "Missing Discord creds" >&2; exit 1; }
    [ -z "$cid" ]  && cid="changeme"
    [ -z "$csec" ] && csec="changeme"
    [ -z "$redir" ] && redir="https://your-domain.example/api/callback"
    cid="$(ask "DISCORD_CLIENT_ID" "$cid")"
    csec="$(ask "DISCORD_CLIENT_SECRET" "$csec")"
    redir="$(ask "DISCORD_REDIRECT_URI" "$redir")"
    env_set DISCORD_CLIENT_ID "$cid"
    env_set DISCORD_CLIENT_SECRET "$csec"
    [ -n "$redir" ] && env_set DISCORD_REDIRECT_URI "$redir"
  fi
  export DISCORD_CLIENT_ID="$cid"
  export DISCORD_CLIENT_SECRET="$csec"
  [ -n "${redir:-}" ] && export DISCORD_REDIRECT_URI="$redir"
}

create_cfg() {
  local def_server="$PROJECT_ROOT/src/server/server.py"
  local def_req="$PROJECT_ROOT/requirements.txt"
  local def_venv="$PROJECT_ROOT/.venv"
  local def_logs="$PROJECT_ROOT/logs"
  local def_pid="$PROJECT_ROOT/server.pid"
  local def_run="$PROJECT_ROOT/.run"
  local def_dist="$PROJECT_ROOT/src/client/dist"
  local def_port="5174"
  local def_host="0.0.0.0"
  local def_mod="server:app"
  local def_cmd=""
  local server_py req_txt venv_dir logs_dir pid_file run_dir dist_dir
  local port host app_module start_cmd

  server_py="$(ask "Path to server.py" "$def_server")"
  req_txt="$(ask "Path to requirements.txt" "$def_req")"
  venv_dir="$(ask "Virtualenv dir" "$def_venv")"
  logs_dir="$(ask "Logs dir" "$def_logs")"
  pid_file="$(ask "PID file" "$def_pid")"
  run_dir="$(ask "Runtime dir" "$def_run")"
  dist_dir="$(ask "Client dist dir" "$def_dist")"
  port="$(ask "Port" "$def_port")"
  host="$(ask "Host" "$def_host")"
  app_module="$(ask "ASGI module (module:attr)" "$def_mod")"
  start_cmd="$(ask "Custom start cmd (blank = auto)" "$def_cmd")"

  {
    echo "SERVER_FILE=$server_py"
    echo "REQ_FILE=$req_txt"
    echo "VENV_DIR=$venv_dir"
    echo "LOG_DIR=$logs_dir"
    echo "PID_FILE=$pid_file"
    echo "RUN_DIR=$run_dir"
    echo "CLIENT_DIST_DIR=$dist_dir"
    echo "PORT=$port"
    echo "HOST=$host"
    echo "APP_MODULE=$app_module"
    echo "START_CMD=$start_cmd"
    echo "FOLLOW_LOGS=1"
    echo "RELOAD=1"
  } > "$CONFIG_FILE"
}

load_cfg() {
  [ -f "$CONFIG_FILE" ] || create_cfg
  set -a; . "$CONFIG_FILE"; set +a
}

SERVER_FILE="${SERVER_FILE:-"$PROJECT_ROOT/src/server/server.py"}"
SERVER_DIR="${SERVER_DIR:-"$(dirname "$SERVER_FILE")"}"
REQ_FILE="${REQ_FILE:-"$PROJECT_ROOT/requirements.txt"}"
VENV_DIR="${VENV_DIR:-"$PROJECT_ROOT/.venv"}"
LOG_DIR="${LOG_DIR:-"$PROJECT_ROOT/logs"}"
PID_FILE="${PID_FILE:-"$PROJECT_ROOT/server.pid"}"
RUN_DIR="${RUN_DIR:-"$PROJECT_ROOT/.run"}"
CLIENT_DIST_DIR="${CLIENT_DIST_DIR:-"$PROJECT_ROOT/src/client/dist"}"

PORT="${PORT:-5174}"
HOST="${HOST:-0.0.0.0}"
START_CMD="${START_CMD:-}"
APP_MODULE="${APP_MODULE:-server:app}"
FOLLOW_LOGS="${FOLLOW_LOGS:-1}"
RELOAD="${RELOAD:-1}"

pybin() {
  command -v python3 >/dev/null 2>&1 && { echo python3; return; }
  command -v python  >/dev/null 2>&1 && { echo python;  return; }
  echo ""
}

listening() {
  [ -z "${PORT:-}" ] && return 1
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp | grep -q ":$PORT "
  else
    command -v lsof >/dev/null 2>&1 &&
      lsof -Pi :"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1
  fi
}

pid_alive() {
  local p="$1"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

is_running() {
  if [ -f "$PID_FILE" ]; then
    local p; p="$(cat "$PID_FILE" 2>/dev/null || true)"
    pid_alive "$p" || listening
  else
    listening
  fi
}

ensure_venv_and_reqs() {
  local py; py="$(pybin)"
  [ -n "$py" ] || { echo "python not found"; exit 1; }
  [ -d "$VENV_DIR" ] || "$py" -m venv "$VENV_DIR"
  "$VENV_DIR/bin/python" -m pip install --upgrade pip wheel setuptools
  [ -f "$REQ_FILE" ] && "$VENV_DIR/bin/python" -m pip install -r "$REQ_FILE"
}

start_cmd() {
  if [ -n "$START_CMD" ]; then echo "$START_CMD"; return; fi
  local cmd
  cmd="\"$VENV_DIR/bin/python\" -m uvicorn \"$APP_MODULE\""
  cmd+=" --host \"$HOST\" --port \"$PORT\" --app-dir \"$SERVER_DIR\""
  if [ "${RELOAD:-1}" != "0" ]; then
    cmd+=" --reload --reload-dir \"$SERVER_DIR\""
  fi
  echo "$cmd"
}

tail_logs() {
  mkdir -p "$LOG_DIR"
  touch "$LOG_DIR/server.log"
  tail -n +1 -F "$LOG_DIR/server.log" || true
}

start_bg() {
  mkdir -p "$CLIENT_DIST_DIR" "$LOG_DIR"
  : > "$LOG_DIR/server.log"
  local cmd; cmd="$(start_cmd)"
  nohup bash -lc "cd \"$SERVER_DIR\" && exec $cmd" \
    >> "$LOG_DIR/server.log" 2>&1 &
  echo $! > "$PID_FILE"
  for _ in $(seq 1 20); do listening && break; sleep 0.3; done
  if listening; then
    echo "server started (pid $(cat "$PID_FILE" 2>/dev/null || echo '?'))"
    [ "$FOLLOW_LOGS" = "1" ] && tail_logs
  else
    echo "failed to start; recent log:"
    tail -n 200 "$LOG_DIR/server.log" || true
    exit 1
  fi
}

stop_bg() {
  if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE" 2>/dev/null || echo)" 2>/dev/null || true
    rm -f "$PID_FILE"
  fi
  echo "stopped"
}

force_stop() {
  rm -f "$PID_FILE"
  if command -v lsof >/dev/null 2>&1; then
    lsof -t -iTCP:"$PORT" -sTCP:LISTEN | xargs -r kill -9 2>/dev/null || true
  fi
  pkill -9 -f "uvicorn .* ${APP_MODULE%:*}" 2>/dev/null || true
  echo "force-stopped"
}

SELF_ABS="$SCRIPT_DIR/$(basename "$0")"

case "${1:-run}" in
  config) create_cfg ;;
  env)    ensure_env ;;
  status)
    if is_running; then echo "server is running"
    else echo "server is not running"; fi
    ;;
  stop)        stop_bg ;;
  force-stop)  force_stop ;;
  restart)     "$SELF_ABS" stop || true; exec "$SELF_ABS" run ;;
  logs)        tail_logs ;;
  fg)
    ensure_venv_and_reqs
    cmd="$(start_cmd)"
    echo "running in foreground: $cmd"
    exec bash -lc "cd \"$SERVER_DIR\" && $cmd"
    ;;
  run|start|*)
    load_cfg
    ensure_env
    ensure_venv_and_reqs
    if is_running; then
      echo "server already running"
      [ "$FOLLOW_LOGS" = "1" ] && tail_logs
      exit 0
    fi
    start_bg
    ;;
esac
