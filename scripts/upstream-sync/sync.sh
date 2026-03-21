#!/usr/bin/env bash
set -euo pipefail

# Upstream Sync Script for claude-combine
# Checks superpowers and everything-claude-code for updates,
# copies changed files, and creates a PR.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
STATE="$SCRIPT_DIR/state.json"
TMPDIR_BASE=$(mktemp -d)
DRY_RUN="${DRY_RUN:-false}"
CHANGES_FOUND=false
PR_BODY=""
PENDING_UPDATES=""

cleanup() {
  rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

log() { echo "[upstream-sync] $*"; }
err() { echo "[upstream-sync] ERROR: $*" >&2; }

# Check dependencies
for cmd in git gh jq; do
  if ! command -v "$cmd" &>/dev/null; then
    err "Required command '$cmd' not found"
    exit 1
  fi
done

# Read config
read_config() {
  jq -r "$1" "$CONFIG"
}

# Read state
read_state() {
  jq -r "$1" "$STATE"
}

# Update state
update_state() {
  local upstream="$1" sha="$2"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local tmp
  tmp=$(mktemp)
  jq --arg name "$upstream" --arg sha "$sha" --arg now "$now" \
    '.[$name].last_synced_sha = $sha | .[$name].last_synced_at = $now' \
    "$STATE" > "$tmp" && mv "$tmp" "$STATE"
}

# Get latest commit SHA from upstream
get_upstream_sha() {
  local repo="$1" branch="$2"
  gh api "repos/$repo/commits/$branch" --jq '.sha' 2>/dev/null
}

# Get commit log between two SHAs
get_commit_log() {
  local repo="$1" base="$2" head="$3"
  if [ "$base" = "null" ] || [ -z "$base" ]; then
    gh api "repos/$repo/commits?sha=$head&per_page=5" \
      --jq '.[].commit | "- " + (.message | split("\n")[0])' 2>/dev/null
  else
    gh api "repos/$repo/compare/${base}...${head}" \
      --jq '.commits[].commit | "- " + (.message | split("\n")[0])' 2>/dev/null
  fi
}

# Clone upstream repo (shallow)
clone_upstream() {
  local repo="$1" branch="$2" dest="$3"
  log "Cloning $repo ($branch) ..."
  git clone --depth 1 --branch "$branch" --single-branch \
    "https://github.com/$repo.git" "$dest" 2>/dev/null
}

# Sync files for "full" mode (superpowers - sync all files in listed directories)
sync_full() {
  local upstream_name="$1" clone_dir="$2"
  local dirs
  dirs=$(jq -r ".upstreams[] | select(.name==\"$upstream_name\") | .directories[]" "$CONFIG")

  local file_count=0
  for dir in $dirs; do
    if [ ! -d "$clone_dir/$dir" ]; then
      continue
    fi

    # Walk all files in the upstream directory
    while IFS= read -r -d '' src_file; do
      local rel_path="${src_file#$clone_dir/}"

      # Check overlap priority
      local priority
      priority=$(jq -r ".overlap_priority[\"$rel_path\"] // \"\"" "$CONFIG")
      if [ -n "$priority" ] && [ "$priority" != "$upstream_name" ]; then
        continue
      fi

      local dest_file="$REPO_ROOT/$rel_path"
      local dest_dir
      dest_dir=$(dirname "$dest_file")
      mkdir -p "$dest_dir"

      # Copy if file is new or different
      if [ ! -f "$dest_file" ] || ! diff -q "$src_file" "$dest_file" &>/dev/null; then
        cp "$src_file" "$dest_file"
        file_count=$((file_count + 1))
      fi
    done < <(find "$clone_dir/$dir" -type f -print0)
  done

  echo "$file_count"
}

# Sync files for "selective" mode (ECC - only sync listed items)
sync_selective() {
  local upstream_name="$1" clone_dir="$2"
  local file_count=0

  # Sync skills (directories)
  local skills
  skills=$(jq -r ".upstreams[] | select(.name==\"$upstream_name\") | .mappings.skills[]" "$CONFIG" 2>/dev/null)
  for skill in $skills; do
    local src_dir="$clone_dir/skills/$skill"
    local dest_dir="$REPO_ROOT/skills/$skill"
    if [ -d "$src_dir" ]; then
      while IFS= read -r -d '' src_file; do
        local rel="${src_file#$src_dir/}"
        mkdir -p "$(dirname "$dest_dir/$rel")"
        if [ ! -f "$dest_dir/$rel" ] || ! diff -q "$src_file" "$dest_dir/$rel" &>/dev/null; then
          cp "$src_file" "$dest_dir/$rel"
          file_count=$((file_count + 1))
        fi
      done < <(find "$src_dir" -type f -print0)
    fi
  done

  # Sync agents (single files)
  local agents
  agents=$(jq -r ".upstreams[] | select(.name==\"$upstream_name\") | .mappings.agents[]" "$CONFIG" 2>/dev/null)
  for agent in $agents; do
    local src="$clone_dir/agents/$agent"
    local dest="$REPO_ROOT/agents/$agent"

    # Check overlap priority
    local priority
    priority=$(jq -r ".overlap_priority[\"agents/$agent\"] // \"\"" "$CONFIG")
    if [ -n "$priority" ] && [ "$priority" != "$upstream_name" ]; then
      continue
    fi

    if [ -f "$src" ]; then
      if [ ! -f "$dest" ] || ! diff -q "$src" "$dest" &>/dev/null; then
        cp "$src" "$dest"
        file_count=$((file_count + 1))
      fi
    fi
  done

  # Sync commands (single files)
  local commands
  commands=$(jq -r ".upstreams[] | select(.name==\"$upstream_name\") | .mappings.commands[]" "$CONFIG" 2>/dev/null)
  for cmd_file in $commands; do
    local src="$clone_dir/commands/$cmd_file"
    local dest="$REPO_ROOT/commands/$cmd_file"
    if [ -f "$src" ]; then
      if [ ! -f "$dest" ] || ! diff -q "$src" "$dest" &>/dev/null; then
        cp "$src" "$dest"
        file_count=$((file_count + 1))
      fi
    fi
  done

  # Sync rules (directories)
  local rules
  rules=$(jq -r ".upstreams[] | select(.name==\"$upstream_name\") | .mappings.rules[]?" "$CONFIG" 2>/dev/null)
  for rule_dir in $rules; do
    local src_dir="$clone_dir/rules/$rule_dir"
    local dest_dir="$REPO_ROOT/rules/$rule_dir"
    if [ -d "$src_dir" ]; then
      while IFS= read -r -d '' src_file; do
        local rel="${src_file#$src_dir/}"
        mkdir -p "$(dirname "$dest_dir/$rel")"
        if [ ! -f "$dest_dir/$rel" ] || ! diff -q "$src_file" "$dest_dir/$rel" &>/dev/null; then
          cp "$src_file" "$dest_dir/$rel"
          file_count=$((file_count + 1))
        fi
      done < <(find "$src_dir" -type f -print0)
    fi
  done

  echo "$file_count"
}

# Check for new items in upstream that aren't tracked yet
check_new_items() {
  local upstream_name="$1" clone_dir="$2"
  local new_items=""

  if [ "$upstream_name" = "superpowers" ]; then
    # For superpowers (full sync), check for new skill directories
    if [ -d "$clone_dir/skills" ]; then
      for skill_dir in "$clone_dir/skills"/*/; do
        local skill_name
        skill_name=$(basename "$skill_dir")
        if [ ! -d "$REPO_ROOT/skills/$skill_name" ]; then
          new_items="$new_items\n- New skill: \`$skill_name\`"
        fi
      done
    fi
  else
    # For ECC, check for new skills/agents/commands not in our config
    if [ -d "$clone_dir/skills" ]; then
      for skill_dir in "$clone_dir/skills"/*/; do
        local skill_name
        skill_name=$(basename "$skill_dir")
        if [ ! -d "$REPO_ROOT/skills/$skill_name" ]; then
          local in_config
          in_config=$(jq -r ".upstreams[] | select(.name==\"$upstream_name\") | .mappings.skills[] | select(.==\"$skill_name\")" "$CONFIG" 2>/dev/null)
          if [ -z "$in_config" ]; then
            new_items="$new_items\n- New skill available: \`$skill_name\`"
          fi
        fi
      done
    fi
  fi

  echo -e "$new_items"
}

# ─── Main ───────────────────────────────────────────────────────────────────────

main() {
  log "Starting upstream sync check..."
  cd "$REPO_ROOT"

  local branch_name="upstream-sync/$(date +%Y-%m-%d)"
  local total_changes=0

  # Check if a sync PR already exists
  local existing_pr
  existing_pr=$(gh pr list --head "$branch_name" --json number --jq '.[0].number' 2>/dev/null || echo "")
  if [ -n "$existing_pr" ]; then
    log "Sync PR #$existing_pr already exists for today. Skipping."
    exit 0
  fi

  # Process each upstream
  local upstream_count
  upstream_count=$(jq '.upstreams | length' "$CONFIG")

  for i in $(seq 0 $((upstream_count - 1))); do
    local name repo branch sync_mode
    name=$(jq -r ".upstreams[$i].name" "$CONFIG")
    repo=$(jq -r ".upstreams[$i].repo" "$CONFIG")
    branch=$(jq -r ".upstreams[$i].branch" "$CONFIG")
    sync_mode=$(jq -r ".upstreams[$i].sync_mode" "$CONFIG")

    log "Checking $name ($repo)..."

    # Get latest SHA
    local latest_sha
    latest_sha=$(get_upstream_sha "$repo" "$branch")
    if [ -z "$latest_sha" ]; then
      err "Failed to get SHA for $repo"
      continue
    fi

    local last_sha
    last_sha=$(read_state ".[\"$name\"].last_synced_sha")

    if [ "$latest_sha" = "$last_sha" ]; then
      log "$name: no new commits (at $latest_sha)"
      continue
    fi

    log "$name: new commits found! $last_sha -> $latest_sha"

    # Clone upstream
    local clone_dir="$TMPDIR_BASE/$name"
    clone_upstream "$repo" "$branch" "$clone_dir"

    # Sync files
    local changed_count=0
    if [ "$sync_mode" = "full" ]; then
      changed_count=$(sync_full "$name" "$clone_dir")
    else
      changed_count=$(sync_selective "$name" "$clone_dir")
    fi

    total_changes=$((total_changes + changed_count))

    # Get commit log for PR body
    local commit_log
    commit_log=$(get_commit_log "$repo" "$last_sha" "$latest_sha")

    # Check for new items
    local new_items
    new_items=$(check_new_items "$name" "$clone_dir")

    # Build PR body section
    PR_BODY="$PR_BODY
### $name (\`$repo\`)
**Branch:** \`$branch\`
**Changes:** $changed_count files updated
**Commits since last sync:**
$commit_log
"

    if [ -n "$new_items" ]; then
      PR_BODY="$PR_BODY
**New items available (not yet imported):**
$new_items
"
    fi

    # Track SHA for later state update
    PENDING_UPDATES="$PENDING_UPDATES $name:$latest_sha"
  done

  # Create PR if changes found
  if [ "$total_changes" -gt 0 ]; then
    CHANGES_FOUND=true
    log "Total files changed: $total_changes"

    if [ "$DRY_RUN" = "true" ]; then
      log "[DRY RUN] Would create PR with $total_changes file changes"
      echo -e "$PR_BODY"
      exit 0
    fi

    # Update state before committing (included in PR)
    for entry in $PENDING_UPDATES; do
      local uname="${entry%%:*}" usha="${entry#*:}"
      update_state "$uname" "$usha"
    done

    # Create branch and commit
    git checkout -b "$branch_name"
    git add -A
    git commit -m "$(cat <<EOF
chore: sync upstream changes ($(date +%Y-%m-%d))

Automated sync from upstream repositories.
EOF
    )"

    # Push and create PR
    git push -u origin "$branch_name"

    gh pr create \
      --title "Upstream sync: $(date +%Y-%m-%d)" \
      --body "$(cat <<EOF
## Upstream Sync

Automated daily sync from upstream repositories.

$PR_BODY

---
> This PR was auto-generated by the upstream sync workflow.
> Review the changes carefully before merging.
EOF
    )"

    log "PR created successfully!"
  else
    log "No changes detected in any upstream repo."

    if [ "$DRY_RUN" = "true" ]; then
      exit 0
    fi

    # Still update state if SHAs changed but files are identical
    for entry in $PENDING_UPDATES; do
      local uname="${entry%%:*}" usha="${entry#*:}"
      update_state "$uname" "$usha"
    done

    # Commit state update if changed
    if ! git diff --quiet "$STATE" 2>/dev/null; then
      git add "$STATE"
      git commit -m "chore: update upstream sync state"
      git push
    fi
  fi
}

main "$@"
