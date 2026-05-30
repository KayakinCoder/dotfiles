#!/usr/bin/env bash
# Claude Code status line script
# Reads JSON from stdin and prints a formatted status line.

input=$(cat)

# --- model ---
model=$(echo "$input" | jq -r '.model.display_name // empty')

# --- cwd ---
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
# Abbreviate home directory
cwd="${cwd/#$HOME/~}"

# --- git repo (owner/name) ---
repo=$(echo "$input" | jq -r '.workspace.repo | if . then .owner + "/" + .name else empty end')

# --- git branch (read from filesystem, skipping optional locks) ---
branch=""
in_git_repo=false
if [ -n "$cwd" ]; then
  # Resolve ~ back to $HOME for git
  real_cwd="${cwd/#\~/$HOME}"
  branch=$(git -C "$real_cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  if git -C "$real_cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    in_git_repo=true
  fi
fi

# --- context window ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_str=""
if [ -n "$used_pct" ]; then
  ctx_str=$(printf "ctx:%.0f%%" "$used_pct")
fi

# --- Claude.ai rate limits ---
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rate_str=""
if [ -n "$five_pct" ]; then
  rate_str=$(printf "5h:%.0f%%" "$five_pct")
fi
if [ -n "$week_pct" ]; then
  week_part=$(printf "7d:%.0f%%" "$week_pct")
  if [ -n "$rate_str" ]; then
    rate_str="$rate_str $week_part"
  else
    rate_str="$week_part"
  fi
fi

# --- assemble parts ---
# Location group: cwd, repo, branch
location_parts=()
[ -n "$cwd" ] && location_parts+=("$cwd")
[ -n "$repo" ] && location_parts+=("($repo)")
[ -n "$branch" ] && location_parts+=("[🌲 $branch]")

# Session group: model, context, usage
session_parts=()
[ -n "$model" ] && session_parts+=("$model")
[ -n "$ctx_str" ] && session_parts+=("$ctx_str")
[ -n "$rate_str" ] && session_parts+=("$rate_str")

# Join an array with " | "
join_parts() {
  local joined=""
  local part
  for part in "$@"; do
    if [ -z "$joined" ]; then
      joined="$part"
    else
      joined="$joined | $part"
    fi
  done
  printf "%s" "$joined"
}

if [ "$in_git_repo" = true ]; then
  # In a git repo: location on line 1, session on its own line
  printf "%s\n%s" "$(join_parts "${location_parts[@]}")" "$(join_parts "${session_parts[@]}")"
else
  # Not in a git repo: everything on one line
  join_parts "${location_parts[@]}" "${session_parts[@]}"
fi
