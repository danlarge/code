#!/usr/bin/env bash
# ======================================================================
# Git multi-repo updater with auto-discovery, safe FF-only updates,
# and permission self-repair for macOS. Compatible with Bash and Zsh.
#
# Execution assumptions:
# - macOS or BSD userland (supports chflags).
# - You have read/write access to the base directory.
# - Repos use an 'origin' remote.
# ======================================================================

# ----------------------------------------------------------------------
# GLOBAL SETTINGS
# ----------------------------------------------------------------------
# Purpose: safer shell defaults without aborting whole run on one failure.
# -u: error on unset variables
# pipefail: fail pipeline on first failing command
set -u
set -o pipefail
IFS=$'\n\t'

# ----------------------------------------------------------------------
# CONSTANTS / INPUTS
# ----------------------------------------------------------------------
# INPUT: BASE_DIR
# Meaning: absolute path containing your Git repositories as subfolders.
BASE_DIR="/Users/daniellarge/Applications_Uncontained/GitHubRepos"

# OUTPUT FILES: change and skip logs, truncated at start of run.
CHANGED_LOG="$BASE_DIR/changed_repos.log"
SKIPPED_LOG="$BASE_DIR/skipped_repos.log"

# ----------------------------------------------------------------------
# PRE-RUN: privilege warm-up for future sudo use (permission repair).
# INPUT: none. Prompts once if needed.
# EFFECT: caches sudo credentials; no action if not required later.
# ----------------------------------------------------------------------
echo "Requesting sudo (for permission repair only, if needed)..."
sudo -v || true

# ----------------------------------------------------------------------
# LOG INITIALIZATION
# INPUTS: $CHANGED_LOG, $SKIPPED_LOG
# EFFECT: truncate logs and add run header.
# ----------------------------------------------------------------------
: > "$CHANGED_LOG"
: > "$SKIPPED_LOG"
RUN_LOG="$(mktemp -t reposrun.XXXXXX)"
exec > >(tee "$RUN_LOG") 2>&1
{
  printf "Run: %s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
} >> "$CHANGED_LOG"
{
  printf "Run: %s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
} >> "$SKIPPED_LOG"

# ======================================================================
# FUNCTIONS
# ======================================================================

# ----------------------------------------------------------------------
# fn: note_skip
# INPUTS:
#   $1 = repo_name (string)
#   $2 = reason     (string)
# EFFECT:
#   - prints a human message
#   - appends a structured line to $SKIPPED_LOG
# RETURNS: 0
# ----------------------------------------------------------------------
note_skip() {
  local _name="$1"; local _reason="$2"
  echo "  Status: Skipped — ${_reason}."
  printf "%s\t%s\t%s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$_name" "$_reason" >> "$SKIPPED_LOG"
}

# ----------------------------------------------------------------------
# fn: note_change
# INPUTS:
#   $1 = repo_name (string)
#   $2 = branch    (string)
#   $3 = commit    (full SHA or short SHA)
# EFFECT:
#   - prints a human message
#   - appends a structured line to $CHANGED_LOG
# RETURNS: 0
# ----------------------------------------------------------------------
note_change() {
  local _name="$1"; local _branch="$2"; local _sha="$3"
  echo "  Status: Updated — ${_branch} (${_sha:0:7})."
  printf "%s\t%s\t%s\t%s\n" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$_name" "$_branch" "$_sha" >> "$CHANGED_LOG"
}

# ----------------------------------------------------------------------
# fn: is_git_repo
# INPUTS:
#   $1 = repo_path (absolute path)
# EFFECT: none
# RETURNS:
#   0 if repo_path contains a .git directory
#   1 otherwise
# ----------------------------------------------------------------------
is_git_repo() {
  [[ -d "$1/.git" ]]
}

# ----------------------------------------------------------------------
# fn: ensure_origin_exists
# INPUTS:
#   none (uses current directory's git context)
# EFFECT: none
# RETURNS:
#   0 if 'origin' remote is configured
#   1 otherwise
# ----------------------------------------------------------------------
ensure_origin_exists() {
  git remote get-url origin >/dev/null 2>&1
}

# ----------------------------------------------------------------------
# Discover if origin has a given branch without updating local refs
remote_has_branch() {
  local _b="$1"
  git ls-remote --heads origin "$_b" >/dev/null 2>&1
}

# Read origin's default branch even if we've never fetched
remote_default_branch() {
  git ls-remote --symref origin HEAD 2>/dev/null \
    | awk '/^ref:/ {sub(/^refs\/heads\//,"",$3); print $3; exit}'
}

# fn: diagnose_remote_unresolved
# INPUTS:
#   none (uses cwd repo)
# EFFECT:
#   prints a concise human reason for why no branch could be selected
# RETURNS:
#   0 always (message printed by caller via note_skip)
diagnose_remote_unresolved() {
  local url heads any err rc
  url="$(git remote get-url origin 2>/dev/null || true)"
  # Try to list heads
  err="$(git ls-remote --heads origin 2> .git/.lsr_err)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    # Could be auth/network. Show concise stderr.
    local msg; msg="$(tr '
' ' ' < .git/.lsr_err | sed 's/  */ /g' | tail -c 200)"
    echo "cannot reach origin (${url:-unknown}) — ${msg}"; rm -f .git/.lsr_err; return 0
  fi
  rm -f .git/.lsr_err
  heads="$(printf '%s
' "$err" | wc -l | tr -d ' ')"
  # Also check if repo has any refs at all
  any="$(git ls-remote origin 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$any" == "0" ]]; then
    echo "origin (${url:-unknown}) has no refs — remote is empty"; return 0
  fi
  if [[ "$heads" == "0" ]]; then
    echo "origin (${url:-unknown}) has no branches (only tags or other refs)"; return 0
  fi
  echo "no matching branch policy for remote heads — sample: $(git ls-remote --heads origin 2>/dev/null | sed -E 's|^.+[[:space:]]+refs/heads/||' | head -n3 | paste -sd', ' -)"; return 0
}


# fn: detect_target_branch
# Choose target branch robustly with multiple fallbacks
detect_target_branch() {
  local _current _default _first
  _current="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -n "$_current" ]] && remote_has_branch "$_current"; then
    echo "$_current"; return 0
  fi

  # Remote default via ls-remote symref
  _default="$(remote_default_branch || true)"
  if [[ -n "$_default" ]]; then
    echo "$_default"; return 0
  fi

  # Remote default via 'git remote show origin'
  _default="$(git remote show origin 2>/dev/null | awk -F': ' '/HEAD branch/ {print $2; exit}')"
  if [[ -n "$_default" ]] && remote_has_branch "$_default"; then
    echo "$_default"; return 0
  fi

  # Common names that actually exist
  if remote_has_branch main; then
    echo "main"; return 0
  fi
  if remote_has_branch master; then
    echo "master"; return 0
  fi

  # Fallback: pick first branch advertised by the remote (sed avoids awk portability issues)
  _first="$(git ls-remote --heads origin 2>/dev/null | sed -E 's|^.+[[:space:]]+refs/heads/||' | head -n1)"
  if [[ -n "$_first" ]]; then
    echo "$_first"; return 0
  fi

  echo ""; return 1
}


# ----------------------------------------------------------------------
# fn: has_local_config_changes
# INPUTS:
#   none (uses current directory's git context)
# EFFECT: none
# RETURNS:
#   0 if working tree shows modified paths matching 'config' (case-insensitive)
#   1 otherwise
# NOTES:
#   Adjust grep if you need stricter patterns.
# ----------------------------------------------------------------------
has_local_config_changes() {
  git status --porcelain | awk '{print $2}' | grep -qi 'config'
}

# ----------------------------------------------------------------------
# fn: fetch_target
# Fetch with clearer diagnostics
fetch_target() {
  local _branch="$1"
  if ! remote_has_branch "$_branch"; then
    note_skip "$(basename "$(pwd)")" "origin ($(git remote get-url origin 2>/dev/null || echo unknown)) has no branch '${_branch}'"
    return 1
  fi
  if ! git fetch --prune origin "$_branch" 2> .git/.fetch_err; then
    local _err; _err="$(tr '
' ' ' < .git/.fetch_err | sed 's/  */ /g' | tail -c 300)"
    note_skip "$(basename "$(pwd)")" "fetch error for origin/${_branch} (${_err})"
    return 1
  fi
  rm -f .git/.fetch_err
}


# ----------------------------------------------------------------------
# fn: sync_two_way
# INPUTS:
#   $1 = target branch name
# EFFECT:
#   - If local is behind or equal to remote: fast-forward (reset --hard) to origin/<branch>
#   - If local is strictly ahead of remote and fast-forward push is possible: push to origin
#   - If diverged: do not merge automatically; caller logs a skip
# RETURNS:
#   0 on success or no-op
#   10 if diverged (both have unique commits)
#   20 if update failed (permissions or push error)
sync_two_way() {
  local _branch="$1"
  local _local _remote
  _local="$(git rev-parse HEAD)"
  _remote="$(git rev-parse "origin/${_branch}")"

  # Case A: local is ancestor of remote -> we are behind or equal; pull fast-forward (reset)
  if git merge-base --is-ancestor "${_local}" "${_remote}"; then
    if [[ "${_local}" == "${_remote}" ]]; then
      echo "  Status: Up to date — ${_branch} (${_remote:0:7})."
      return 0
    fi
    if git reset --hard "origin/${_branch}" >/dev/null 2>&1; then
      note_change "$(basename "$(pwd)")" "${_branch}" "${_remote}"
      echo "  Status: Updated — ${_branch} (${_remote:0:7})."
      return 0
    else
      return 20
    fi
  fi

  # Case B: remote is ancestor of local -> we are ahead; push fast-forward to origin
  if git merge-base --is-ancestor "${_remote}" "${_local}"; then
    # This is a regular fast-forward push; no force needed
    if git push -q origin "HEAD:${_branch}" >/dev/null 2>&1; then
      echo "  Status: Pushed — ${_branch} ($(_local_sha=${_local}; echo ${_local_sha:0:7}))."
      return 0
    else
      return 20
    fi
  fi

  # Case C: diverged (no fast-forward either direction)
  return 10
}

# fn: ff_to_origin
# INPUTS:
#   $1 = target branch name
# EFFECT:
#   - If HEAD is ancestor of origin/<branch>:
#       * if behind: hard reset to origin/<branch> (discard local changes/commits)
#       * if equal: no-op
#   - If diverged or ahead: do nothing
# RETURNS:
#   0 on success or no-op
#   10 if diverged/ahead
#   20 if reset failed
# ----------------------------------------------------------------------
ff_to_origin() {
  local _branch="$1"
  local _local
  _local="$(git rev-parse HEAD)"
  local _remote
  _remote="$(git rev-parse "origin/${_branch}")"

  # HEAD is ancestor of remote => behind or equal; safe to fast-forward
  if git merge-base --is-ancestor "${_local}" "${_remote}"; then
    if [[ "${_local}" == "${_remote}" ]]; then
      echo "  Status: Up to date — ${_branch} (${_remote:0:7})."
      return 0
    fi
    # behind: force working tree to remote state
    if git reset --hard "origin/${_branch}" >/dev/null 2>&1; then
      note_change "$(basename "$(pwd)")" "${_branch}" "${_remote}"
      return 0
    else
      # permissions or file flags likely blocked reset
      return 20
    fi
  else
    # diverged or ahead; do not auto-merge
    return 10
  fi
}

# ----------------------------------------------------------------------
# fn: repair_permissions
# INPUTS:
#   $1 = repo_path (absolute path)
# EFFECT:
#   - Clears macOS 'uchg' flags recursively
#   - Resets ownership to current user:staff
#   - Ensures u+rwX everywhere
# RETURNS:
#   0 always (best-effort)
# ----------------------------------------------------------------------
repair_permissions() {
  local _path="$1"
  # Clear immutable flags; ignore errors if not set
  chflags -R nouchg "$_path" 2>/dev/null || true
  # Fix ownership; may prompt for sudo if cached creds expired
  sudo chown -R "$USER":staff "$_path" 2>/dev/null || true
  # Ensure write and search permissions for user
  chmod -R u+rwX "$_path" 2>/dev/null || true
}

# ----------------------------------------------------------------------
# fn: update_repo
# INPUTS:
#   $1 = repo_path (absolute path)
# EFFECT:
#   - Validates repo
#   - Determines target branch
#   - Skips if local config changes present
#   - Fetches target
#   - Fast-forward updates or logs skip
#   - On permission failure, performs repair and retries once
# RETURNS:
#   0 on success or no-op
#   non-zero on skip conditions (informational)
# ----------------------------------------------------------------------
update_repo() {
  local repo_path="$1"
  local repo_name; repo_name="$(basename "$repo_path")"
  echo "Processing: $repo_name"

  # Ensure repository structure
  if ! is_git_repo "$repo_path"; then
    note_skip "$repo_name" "not a git repo"
    return 1
  fi

  # Enter repo directory for all git operations
  if ! pushd "$repo_path" > /dev/null 2>&1; then
    note_skip "$repo_name" "cannot enter directory"
    return 1
  fi

  # Ensure an 'origin' remote exists
  if ! ensure_origin_exists; then
    note_skip "$repo_name" "no origin remote"
    popd > /dev/null; return 1
  fi

  # Resolve the correct update branch
  local target_branch
  target_branch="$(detect_target_branch)"
  origin_url="$(git remote get-url origin 2>/dev/null || echo unknown)"
  if [[ -n "$target_branch" ]]; then echo "  Remote: ${origin_url}"; echo "  Branch: ${target_branch}"; fi
  if [[ -z "$target_branch" ]]; then
    reason="$(diagnose_remote_unresolved)";
    note_skip "$repo_name" "${reason}"; popd > /dev/null; return 1; fi

  # Protect local config edits
  if has_local_config_changes; then
    note_skip "$repo_name" "local config changes detected"
    popd > /dev/null; return 1
  fi

  # Fetch latest remote state for the target branch
  # Fetch latest remote state for the target branch
  if ! fetch_target "$target_branch"; then
    # Detailed reason already logged by fetch_target (e.g., missing branch, auth/network)
    popd > /dev/null; return 1
  fi

  # Attempt fast-forward update
  if sync_two_way "$target_branch"; then
    :
  else
    case "$?" in
      10)
        note_skip "$repo_name" "diverged from origin/${target_branch} — manual merge required"
        ;;
      20)
        echo "  Reset failed due to permissions. Attempting repair..."
        popd > /dev/null
        repair_permissions "$repo_path"
        # Retry inside repo
        if pushd "$repo_path" > /dev/null 2>&1 && sync_two_way "$target_branch"; then
          :
        else
          note_skip "$repo_name" "reset failed after repair"
        fi
        ;;
      *)
        note_skip "$repo_name" "update failed — permissions or push error"
        ;;
    esac
  fi

  # Leave repo directory
  popd > /dev/null || true
}

# ======================================================================
# MAIN
# ======================================================================

echo "Scanning for repositories in: $BASE_DIR"

# Iterate immediate subdirectories. Compatible with Bash and Zsh.
# Uses newline splitting; handles spaces in names.
find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | while IFS=$'\n' read -r dir; do
  update_repo "$dir"
done

# SUMMARY OUTPUT
echo
updated_count=$(grep -cE '^\S+\t\S+\t\S+\t[0-9a-f]{7,40}$' "$CHANGED_LOG" 2>/dev/null || echo 0)
uptodate_count=$(grep -c "Status: Up to date —" "$RUN_LOG" 2>/dev/null || echo 0)
skipped_count=$(wc -l < "$SKIPPED_LOG" 2>/dev/null || echo 0)

echo "Summary:"
printf "  Updated:     %s\n" "$updated_count"
printf "  Up to date:  %s\n" "$uptodate_count"
printf "  Skipped:     %s\n" "$skipped_count"
echo
echo "Changed repos log: $CHANGED_LOG"
echo "Skipped  repos log: $SKIPPED_LOG"