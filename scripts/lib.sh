# Shared AppMan environment for this plugin.
# Sourced by appman-status, appman-upgrade, and the install helpers.

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$PLUGIN_DIR/scripts"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
STATE_FILE="$STATE_DIR/appman.json"
LOCK_FILE="$STATE_DIR/appman.lock"

# Never prompt. AppMan runs as your user; no sudo is involved.
export NONINTERACTIVE=1
export CI=1

if command -v appman >/dev/null 2>&1; then
  APPMAN="$(command -v appman)"
else
  APPMAN=""
fi

# Where AppMan keeps its apps (first line of its config file).
if [[ -f $HOME/.config/appman/appman-config ]]; then
  APPSPATH="$(head -n 1 "$HOME/.config/appman/appman-config")"
fi
APPSPATH="${APPSPATH:-$HOME/Applications}"

mkdir -p "$STATE_DIR"

now_unix() {
  date +%s
}

empty_state() {
  jq -nc --argjson checkedAt "$(now_unix)" '{
    ok: true,
    checkedAt: $checkedAt,
    checking: false,
    updating: false,
    error: "",
    apps: []
  }'
}

read_state() {
  if [[ -f $STATE_FILE ]]; then
    cat "$STATE_FILE"
  else
    empty_state
  fi
}

write_state_file() {
  local json=$1
  local tmp
  tmp="$(mktemp "$STATE_DIR/appman.XXXXXX")"
  printf '%s\n' "$json" >"$tmp"
  mv -f "$tmp" "$STATE_FILE"
}

merge_state() {
  local patch=$1
  write_state_file "$(jq -c --argjson patch "$patch" '. * $patch' <<<"$(read_state)")"
}

appman_ready() {
  [[ -n $APPMAN && -x $APPMAN ]]
}

fail_state() {
  local message=$1
  merge_state "$(jq -nc --arg error "$message" --argjson checkedAt "$(now_unix)" '{
    ok: false,
    checkedAt: $checkedAt,
    checking: false,
    updating: false,
    error: $error
  }')"
  cat "$STATE_FILE"
}

installed_count() {
  jq -r '(.apps // []) | length' <<<"$(read_state)"
}

# Non-blocking lock for the bar poll. Returns 1 if another job owns it.
try_lock() {
  exec 9>"$LOCK_FILE"
  flock -n 9
}

# Blocking lock for upgrades. Waits up to 10 minutes.
wait_lock() {
  exec 9>"$LOCK_FILE"
  flock -w 600 9
}

release_lock() {
  exec 9>&- || true
}
