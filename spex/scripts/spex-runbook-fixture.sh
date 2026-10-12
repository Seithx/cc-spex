#!/usr/bin/env bash
# spex-runbook-fixture.sh - Lifecycle for local walkthrough fixtures (research R6).
#
# Quick local fixtures (process, container, compose) are started and stopped by
# this script. Slow and remote fixtures are only recorded (record/keep) so the
# runbook's test environment and cleanup stay complete; they are never stopped
# automatically.
#
# State lives in <scratch>/fixtures.json; logs in <scratch>/fixtures/.
# Requires jq. Containers use podman only.
#
# Exit codes: 0 success, 1 operation failed, 2 usage, 4 container runtime unavailable.
set -euo pipefail

PODMAN="${SPEX_PODMAN:-podman}"

die_usage() { echo "$1" >&2; exit 2; }

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Create the temp file in the state directory so the final mv is an atomic
# same-filesystem rename. A plain mktemp lands in $TMPDIR, which on Linux is
# often a different filesystem, turning mv into copy-then-unlink that can
# corrupt fixtures.json if interrupted.
state_tmp() { mktemp "$(dirname "$STATEFILE")/.fixtures.tmp.XXXXXX"; }

ensure_state() {
  mkdir -p "$SCRATCH/fixtures"
  STATEFILE="$SCRATCH/fixtures.json"
  [ -f "$STATEFILE" ] || echo '{"fixtures":[]}' > "$STATEFILE"
}

fixture_json() { # name -> the fixture object (compact) or empty
  jq -c --arg n "$1" '.fixtures[] | select(.name==$n)' "$STATEFILE" 2>/dev/null | head -1
}

set_state() { # name state
  local tmp; tmp=$(state_tmp)
  jq --arg n "$1" --arg s "$2" '(.fixtures[] | select(.name==$n)).state = $s' "$STATEFILE" > "$tmp" && mv "$tmp" "$STATEFILE"
}

require_runtime() {
  if ! command -v "$PODMAN" >/dev/null 2>&1; then
    echo "container runtime '$PODMAN' not found" >&2; exit 4
  fi
  if ! "$PODMAN" info >/dev/null 2>&1; then
    echo "container runtime '$PODMAN' is not available (is it running?)" >&2; exit 4
  fi
}

append_fixture() { # uses globals: name kind tier owner id pid pid_start file log started teardown state
  local tmp pidarg; tmp=$(state_tmp)
  if [ "$kind" = "process" ] && [ -n "${pid:-}" ]; then pidarg="$pid"; else pidarg="null"; fi
  jq --arg name "$name" --arg kind "$kind" --arg tier "$tier" --arg owner "$owner" \
     --arg id "${id:-}" --argjson pid "$pidarg" --arg pid_start "${pid_start:-}" \
     --arg file "${file:-}" --arg log "${log:-}" \
     --arg started "$started" --arg teardown "$teardown" --arg state "$state" \
     '.fixtures += [{name:$name, kind:$kind, tier:$tier, owner:$owner,
        id:(if $id=="" then null else $id end), pid:$pid,
        pid_start:(if $pid_start=="" then null else $pid_start end),
        file:(if $file=="" then null else $file end),
        log:$log, started:$started, teardown:$teardown, state:$state}]' \
     "$STATEFILE" > "$tmp" && mv "$tmp" "$STATEFILE"
}

cmd_start() {
  SCRATCH="${1:-}"; shift || true
  [ -n "$SCRATCH" ] || die_usage "start: <scratch> required"
  local name="" kind="" file="" ; local -a cmd=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) shift; name="${1:-}" ;;
      --kind) shift; kind="${1:-}" ;;
      --file) shift; file="${1:-}" ;;
      --) shift; cmd=("$@"); break ;;
      *) die_usage "start: unexpected argument '$1'" ;;
    esac
    shift || true
  done
  [ -n "$name" ] || die_usage "start: --name required"
  case "$kind" in process|container|compose) ;; *) die_usage "start: --kind must be process|container|compose" ;; esac
  ensure_state

  local existing; existing=$(fixture_json "$name")
  if [ -n "$existing" ] && [ "$(echo "$existing" | jq -r '.state')" = "running" ]; then
    echo "start: fixture '$name' already running" >&2; exit 1
  fi
  # Remove any prior stopped record with the same name before re-adding.
  if [ -n "$existing" ]; then
    local tmp; tmp=$(state_tmp)
    jq --arg n "$name" '.fixtures |= map(select(.name != $n))' "$STATEFILE" > "$tmp" && mv "$tmp" "$STATEFILE"
  fi

  local tier="quick" owner="agent" id="" pid="" pid_start="" log="" started state="running" teardown=""
  started=$(now_iso)
  log="$SCRATCH/fixtures/$name.log"
  case "$kind" in
    process)
      [ ${#cmd[@]} -gt 0 ] || die_usage "start: process kind needs a command after --"
      nohup "${cmd[@]}" >"$log" 2>&1 &
      pid=$!
      # Record the start time so teardown/status can tell our process from a
      # later process that reuses the same PID after an interrupted session.
      pid_start=$(ps -o lstart= -p "$pid" 2>/dev/null || true)
      teardown="kill $pid"
      ;;
    container)
      [ ${#cmd[@]} -gt 0 ] || die_usage "start: container kind needs a 'podman run -d ...' command after --"
      case " ${cmd[*]} " in
        *" -d "*|*" --detach "*) ;;
        *) die_usage "start: container command must detach (include -d or --detach), otherwise start would hang waiting for it to exit" ;;
      esac
      require_runtime
      local out
      if ! out=$("${cmd[@]}" 2>"$log"); then
        echo "start: container command failed (see $log)" >&2; exit 1
      fi
      id=$(printf '%s\n' "$out" | tail -1 | tr -d '[:space:]')
      [ -n "$id" ] || { echo "start: container did not return an id" >&2; exit 1; }
      teardown="$PODMAN stop $id && $PODMAN rm $id"
      ;;
    compose)
      [ -n "$file" ] || die_usage "start: compose kind needs --file <compose-file>"
      require_runtime
      if ! "$PODMAN" compose -f "$file" up -d >"$log" 2>&1; then
        echo "start: compose up failed (see $log)" >&2; exit 1
      fi
      teardown="$PODMAN compose -f \"$file\" down"
      ;;
  esac
  append_fixture
  echo "FIXTURE_STARTED name=$name kind=$kind"
}

stop_one() { # name ; returns 0 even for external (no-op)
  local n="$1" f kind pid pstart id file teardown
  f=$(fixture_json "$n")
  [ -n "$f" ] || { echo "stop: no fixture named '$n'" >&2; return 1; }
  kind=$(echo "$f" | jq -r '.kind')
  if [ "$kind" = "external" ]; then
    echo "stop: '$n' is external; leaving it running (teardown: $(echo "$f" | jq -r '.teardown'))" >&2
    return 0
  fi
  pid=$(echo "$f" | jq -r '.pid // empty')
  pstart=$(echo "$f" | jq -r '.pid_start // empty')
  id=$(echo "$f" | jq -r '.id // empty')
  file=$(echo "$f" | jq -r '.file // empty')
  teardown=$(echo "$f" | jq -r '.teardown // empty')
  case "$kind" in
    process)
      # Only signal the PID when it is alive AND still the process we started:
      # a recorded start time that no longer matches means the PID was recycled,
      # so we must not kill an unrelated process (FR-027 resume path).
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null \
         && { [ -z "$pstart" ] || [ "$(ps -o lstart= -p "$pid" 2>/dev/null)" = "$pstart" ]; }; then
        kill -TERM "$pid" 2>/dev/null || true
        local i=0
        while [ $i -lt 50 ]; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; i=$((i+1)); done
        if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null || true; fi
      fi
      ;;
    container)
      [ -n "$id" ] && { "$PODMAN" stop "$id" >/dev/null 2>&1 || true; "$PODMAN" rm "$id" >/dev/null 2>&1 || true; }
      ;;
    compose)
      # Run the recorded compose file directly; never eval a rebuilt command
      # string (a crafted file path could inject shell during teardown).
      [ -n "$file" ] && "$PODMAN" compose -f "$file" down >/dev/null 2>&1 || true
      ;;
  esac
  set_state "$n" stopped
}

cmd_stop() {
  SCRATCH="${1:-}"; shift || true
  [ -n "$SCRATCH" ] || die_usage "stop: <scratch> required"
  ensure_state
  local target="" quick=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) shift; target="${1:-}" ;;
      --quick) quick=true ;;
      *) die_usage "stop: unexpected argument '$1'" ;;
    esac
    shift || true
  done
  if [ "$quick" = true ]; then
    # Read names one per line so a fixture name with spaces or glob characters
    # is not word-split or globbed (which would skip stopping it, leaking it).
    local n
    while IFS= read -r n; do
      [ -n "$n" ] || continue
      stop_one "$n" || true
    done < <(jq -r '.fixtures[] | select(.tier=="quick" and .kind!="external") | .name' "$STATEFILE")
  elif [ -n "$target" ]; then
    stop_one "$target"
  else
    die_usage "stop: --name <n> or --quick required"
  fi
}

cmd_record() {
  SCRATCH="${1:-}"; shift || true
  [ -n "$SCRATCH" ] || die_usage "record: <scratch> required"
  local name="" tier="" owner="" teardown="" note=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) shift; name="${1:-}" ;;
      --tier) shift; tier="${1:-}" ;;
      --owner) shift; owner="${1:-}" ;;
      --teardown) shift; teardown="${1:-}" ;;
      --note) shift; note="${1:-}" ;;
      *) die_usage "record: unexpected argument '$1'" ;;
    esac
    shift || true
  done
  [ -n "$name" ] || die_usage "record: --name required"
  case "$tier" in slow|remote|quick) ;; *) die_usage "record: --tier must be slow|remote|quick" ;; esac
  case "$owner" in agent|user) ;; *) die_usage "record: --owner must be agent|user" ;; esac
  ensure_state
  local tmp; tmp=$(state_tmp)
  jq --arg name "$name" --arg tier "$tier" --arg owner "$owner" --arg teardown "$teardown" \
     --arg note "$note" --arg started "$(now_iso)" \
     '.fixtures |= (map(select(.name != $name)) + [{name:$name, kind:"external", tier:$tier,
        owner:$owner, id:null, pid:null, log:"", started:$started, teardown:$teardown,
        note:(if $note=="" then null else $note end), state:"unknown"}])' \
     "$STATEFILE" > "$tmp" && mv "$tmp" "$STATEFILE"
  echo "FIXTURE_RECORDED name=$name tier=$tier"
}

cmd_keep() {
  SCRATCH="${1:-}"; shift || true
  [ -n "$SCRATCH" ] || die_usage "keep: <scratch> required"
  local name=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) shift; name="${1:-}" ;;
      *) die_usage "keep: unexpected argument '$1'" ;;
    esac
    shift || true
  done
  [ -n "$name" ] || die_usage "keep: --name required"
  ensure_state
  [ -n "$(fixture_json "$name")" ] || { echo "keep: no fixture named '$name'" >&2; exit 1; }
  set_state "$name" kept
  echo "FIXTURE_KEPT name=$name"
}

cmd_status() {
  SCRATCH="${1:-}"; shift || true
  [ -n "$SCRATCH" ] || die_usage "status: <scratch> required"
  ensure_state
  local count i f kind pid pstart id state out="[]"
  count=$(jq '.fixtures | length' "$STATEFILE")
  i=0
  while [ "$i" -lt "$count" ]; do
    f=$(jq -c ".fixtures[$i]" "$STATEFILE")
    kind=$(echo "$f" | jq -r '.kind')
    pid=$(echo "$f" | jq -r '.pid // empty')
    pstart=$(echo "$f" | jq -r '.pid_start // empty')
    id=$(echo "$f" | jq -r '.id // empty')
    state=$(echo "$f" | jq -r '.state')
    if [ "$state" != "kept" ]; then
      if [ "$kind" = "process" ] && [ -n "$pid" ]; then
        # Alive AND still our process (start time matches) -> running.
        if kill -0 "$pid" 2>/dev/null \
           && { [ -z "$pstart" ] || [ "$(ps -o lstart= -p "$pid" 2>/dev/null)" = "$pstart" ]; }; then
          state=running
        else
          state=stopped
        fi
      elif [ "$kind" = "container" ] && [ -n "$id" ]; then
        # inspect exits 0 for exited containers too; check the actual run state.
        if [ "$("$PODMAN" inspect -f '{{.State.Running}}' "$id" 2>/dev/null)" = "true" ]; then
          state=running
        else
          state=stopped
        fi
      fi
    fi
    f=$(echo "$f" | jq --arg s "$state" '.state=$s')
    out=$(echo "$out" | jq --argjson f "$f" '. + [$f]')
    i=$((i + 1))
  done
  local tmp; tmp=$(state_tmp)
  jq -n --argjson fx "$out" '{fixtures:$fx}' > "$tmp" && mv "$tmp" "$STATEFILE"
  cat "$STATEFILE"
}

main() {
  [ $# -ge 1 ] || die_usage "usage: spex-runbook-fixture.sh {start|stop|record|keep|status} <scratch> ..."
  local action="$1"; shift
  case "$action" in
    start) cmd_start "$@" ;;
    stop) cmd_stop "$@" ;;
    record) cmd_record "$@" ;;
    keep) cmd_keep "$@" ;;
    status) cmd_status "$@" ;;
    *) die_usage "unknown action '$action'" ;;
  esac
}

main "$@"
