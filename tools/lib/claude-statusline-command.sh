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
# used_percentage: 0-100. resets_at: unix epoch seconds when the window rolls over.
now=$(date +%s)
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Time until a reset, as a one-decimal count of the given unit (3600 = hours, 86400 = days).
time_until() {
  local reset_at="$1" unit_secs="$2"
  awk -v r="$reset_at" -v n="$now" -v u="$unit_secs" 'BEGIN { d = r - n; if (d < 0) d = 0; printf "%.1f", d / u }'
}

five_str=""
if [ -n "$five_pct" ]; then
  five_str=$(printf "5h:%.0f%%" "$five_pct")
  [ -n "$five_reset" ] && five_str="$five_str Re:$(time_until "$five_reset" 3600)h"
fi
week_str=""
if [ -n "$week_pct" ]; then
  week_str=$(printf "7d:%.0f%%" "$week_pct")
  [ -n "$week_reset" ] && week_str="$week_str Re:$(time_until "$week_reset" 86400)d"
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
[ -n "$five_str" ] && session_parts+=("$five_str")
[ -n "$week_str" ] && session_parts+=("$week_str")

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
