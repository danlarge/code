#!/bin/bash
# Fetch ClamAV DBs via cvdupdate, then push to QNAP if changed.
# macOS Bash 3.2 compatible. No associative arrays. No nounset.

set -e -o pipefail
set +u

# ==== CONFIG ====
NAS_HOST="192.168.1.103"
NAS_USER="admin"
SSH_PORT_OPT=""          # e.g. "-p 2222"
USE_SUDO=""              # "1" if NAS needs sudo to write the paths
MAC_USER="daniellarge"   # login user that owns SSH keys and pipx cvdupdate
# =================

# Paths usable under launchd/root
MAC_HOME="/Users/$MAC_USER"
export PATH="/usr/local/bin:/opt/homebrew/bin:${MAC_HOME}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Locate cvdupdate binary
CVD_BIN=""
for p in "/usr/local/bin/cvd" "/opt/homebrew/bin/cvd" "${MAC_HOME}/.local/bin/cvd"; do
  if [ -x "$p" ]; then CVD_BIN="$p"; break; fi
done
if [ -z "$CVD_BIN" ]; then
  echo "cvdupdate (cvd) not found. Install with: brew install pipx && pipx install cvdupdate"
  exit 1
fi

# Local cache & logs (must be user-owned)
CACHE_DIR="${MAC_HOME}/Library/Caches/clamav_defs"
LOG_DIR="${MAC_HOME}/Library/Logs/cvdupdate"
if [ "$(id -u)" -eq 0 ] && [ "$MAC_USER" != "root" ]; then
  sudo install -d -m 755 -o "$MAC_USER" -g staff "$CACHE_DIR" "$LOG_DIR"
else
  mkdir -p "$CACHE_DIR" "$LOG_DIR"
fi

# Run a command as the login user (HOME + PATH set)
as_user() {
  if [ "$(id -u)" -eq 0 ] && [ "$MAC_USER" != "root" ]; then
    HOME="$MAC_HOME" sudo -E -u "$MAC_USER" env HOME="$MAC_HOME" PATH="$PATH" "$@"
  else
    "$@"
  fi
}

# Configure cvdupdate and update databases
as_user "$CVD_BIN" config set --dbdir "$CACHE_DIR"
as_user "$CVD_BIN" config set --logdir "$LOG_DIR"
as_user "$CVD_BIN" update

# Map db name -> NAS destination (Bash 3.2 friendly)
dest_for() {
  case "$1" in
    main)     echo "/mnt/ext/usr/share/clamav/main.cvd" ;;
    daily)    echo "/mnt/ext/usr/share/clamav/daily.cvd" ;;
    bytecode) echo "/mnt/ext/usr/share/clamav/bytecode.cvd" ;;
    *) return 1 ;;
  esac
}

# Pick local source (.cvd or .cld)
src_for() {
  base="$1"
  if   [ -s "${CACHE_DIR}/${base}.cvd" ]; then echo "${CACHE_DIR}/${base}.cvd"
  elif [ -s "${CACHE_DIR}/${base}.cld" ]; then echo "${CACHE_DIR}/${base}.cld"
  else return 1; fi
}

# md5 helpers
md5_file() { if command -v md5 >/dev/null 2>&1; then md5 -q "$1"; else md5sum "$1" | awk '{print $1}'; fi; }

# Brief NAS wake (max ~60s)
deadline=$(( $(date +%s) + 60 ))
while ! ssh $SSH_PORT_OPT -o BatchMode=yes -o ConnectTimeout=7 -o ConnectionAttempts=1 "${NAS_USER}@${NAS_HOST}" "echo ok" >/dev/null 2>&1; do
  [ "$(date +%s)" -ge "$deadline" ] && { echo "SSH to ${NAS_USER}@${NAS_HOST} unavailable"; exit 1; }
  sleep 5
done

# Copy only if changed
for base in main daily bytecode; do
  src="$(src_for "$base" || true)"
  if [ -z "${src:-}" ]; then
    echo "No local $base db; skipping"
    continue
  fi
  dest="$(dest_for "$base")"

  local_md5="$(md5_file "$src")"
  remote_md5="$(ssh $SSH_PORT_OPT "${NAS_USER}@${NAS_HOST}" \
    "if [ -f '$dest' ]; then (command -v md5sum >/dev/null 2>&1 && md5sum '$dest' | awk '{print \$1}') || (command -v md5 >/dev/null 2>&1 && md5 -q '$dest'); fi" \
    2>/dev/null || true)"

  if [ -n "$remote_md5" ] && [ "$remote_md5" = "$local_md5" ]; then
    echo "Up to date: $dest"
    continue
  fi

  echo "Updating: $dest"
  if [ -n "$USE_SUDO" ]; then
    tmp="/tmp/${base}.db.$$"
    scp $SSH_PORT_OPT -q "$src" "${NAS_USER}@${NAS_HOST}":"$tmp"
    ssh $SSH_PORT_OPT "${NAS_USER}@${NAS_HOST}" "sudo mkdir -p '$(dirname "$dest")' && sudo mv '$tmp' '$dest' && sudo chmod 644 '$dest'"
  else
    ssh $SSH_PORT_OPT "${NAS_USER}@${NAS_HOST}" "mkdir -p '$(dirname "$dest")'"
    scp $SSH_PORT_OPT -q "$src" "${NAS_USER}@${NAS_HOST}":"$dest"
    ssh $SSH_PORT_OPT "${NAS_USER}@${NAS_HOST}" "chmod 644 '$dest' || true"
  fi

  # If source is .cld but dest is .cvd, also drop a sibling .cld (optional)
  case "$src" in
    *.cld)
      case "$dest" in
        *.cvd)
          alt="${dest%.cvd}.cld"
          ssh $SSH_PORT_OPT "${NAS_USER}@${NAS_HOST}" "mkdir -p '$(dirname "$alt")'"
          scp $SSH_PORT_OPT -q "$src" "${NAS_USER}@${NAS_HOST}":"$alt"
          ssh $SSH_PORT_OPT "${NAS_USER}@${NAS_HOST}" "chmod 644 '$alt' || true"
          ;;
      esac
      ;;
  esac
done

echo "Done."
