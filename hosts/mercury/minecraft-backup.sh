# shellcheck shell=bash
#
# Weekly Minecraft backup, configured entirely through environment variables
# set by the systemd unit in minecraft-backup.nix (the tests set them to
# disposable directories).
#
# Guarantees:
#   - Saving is always switched back on, even when the copy fails.
#   - The copy goes to a hidden .partial-* directory and is renamed into
#     place only when rsync succeeds, so a failed run never leaves something
#     that looks like a good backup.
#   - Old backups are pruned only after a new one is in place, and only
#     directories named like a timestamp are ever candidates.
#   - BACKUP_ROOT must already exist (the unit's ExecStartPre creates it only
#     when the ZFS dataset is mounted); this script never creates it.

: "${BACKUP_ROOT:?BACKUP_ROOT must be set}"
: "${SERVER_DATA_DIR:?SERVER_DATA_DIR must be set}"
: "${SOCK:?SOCK must be set}"
KEEP_BACKUPS="${KEEP_BACKUPS:-8}"
FLUSH_TIMEOUT="${FLUSH_TIMEOUT:-60}"
FLUSH_FALLBACK_SLEEP="${FLUSH_FALLBACK_SLEEP:-10}"

if [ ! -d "$BACKUP_ROOT" ]; then
  echo "ERROR: $BACKUP_ROOT does not exist; refusing to create it." >&2
  exit 1
fi
if [ ! -d "$SERVER_DATA_DIR" ]; then
  echo "ERROR: server data directory $SERVER_DATA_DIR does not exist." >&2
  exit 1
fi

timestamp="$(date +%Y-%m-%d_%H%M%S)"
final="$BACKUP_ROOT/$timestamp"
partial="$BACKUP_ROOT/.partial-$timestamp"
running=false
session=""

cleanup() {
  status=$?
  if [ "$running" = true ]; then
    if ! tmux -S "$SOCK" send-keys -t "$session" "save-on" Enter; then
      echo "WARNING: could not re-enable world saving; run save-on in the server console." >&2
    fi
  fi
  if [ "$status" -ne 0 ]; then
    rm -rf -- "$partial"
    echo "Backup FAILED (exit $status); nothing was published." >&2
  fi
  exit "$status"
}
trap cleanup EXIT

# Leftovers from an earlier crashed run.
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name '.partial-*' -exec rm -rf -- {} +

count_saves() {
  if [ -f "$1" ]; then
    grep -c -E 'Saved the (game|world)' "$1" || true
  else
    echo 0
  fi
}

if tmux -S "$SOCK" has-session 2>/dev/null; then
  session="$(tmux -S "$SOCK" list-sessions -F '#{session_name}' | head -n1)"
  # Set before save-off so the exit trap restores saving whatever happens next.
  running=true
  server_log="$SERVER_DATA_DIR/logs/latest.log"
  saves_before="$(count_saves "$server_log")"
  echo "Server is running - flushing world to disk before copying"
  tmux -S "$SOCK" send-keys -t "$session" "save-off" Enter
  tmux -S "$SOCK" send-keys -t "$session" "save-all flush" Enter

  confirmed=false
  waited=0
  while [ "$waited" -lt "$FLUSH_TIMEOUT" ]; do
    if [ "$(count_saves "$server_log")" -gt "$saves_before" ]; then
      confirmed=true
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  if [ "$confirmed" != true ]; then
    echo "WARNING: save was not confirmed in the server log within ${FLUSH_TIMEOUT}s;" \
      "waiting ${FLUSH_FALLBACK_SLEEP}s as a fallback before copying." >&2
    sleep "$FLUSH_FALLBACK_SLEEP"
  fi
else
  echo "Server isn't running - copying world files as-is"
fi

mkdir -- "$partial"
rsync -a \
  --exclude 'libraries' \
  --exclude 'cache' \
  --exclude 'logs' \
  --exclude 'crash-reports' \
  --exclude '*.jar' \
  "$SERVER_DATA_DIR/" "$partial/"
mv -- "$partial" "$final"
echo "Backup written to $final"

# Prune down to the newest $KEEP_BACKUPS backups. Only timestamp-named
# directories are considered; names sort correctly as plain strings.
mapfile -t backups < <(
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]' \
    -printf '%f\n' | sort -r
)
if ((${#backups[@]} > KEEP_BACKUPS)); then
  for old in "${backups[@]:KEEP_BACKUPS}"; do
    echo "Pruning old backup: $old"
    rm -rf -- "${BACKUP_ROOT:?}/$old"
  done
fi
