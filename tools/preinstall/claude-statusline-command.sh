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
if [ -n "$cwd" ]; then
  # Resolve ~ back to $HOME for git
  real_cwd="${cwd/#\~/$HOME}"
  branch=$(git -C "$real_cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
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
parts=()

# cwd always shown
[ -n "$cwd" ] && parts+=("$cwd")

# repo shown when available
[ -n "$repo" ] && parts+=("($repo)")

# branch shown when available
[ -n "$branch" ] && parts+=("[$branch]")

# model always shown
[ -n "$model" ] && parts+=("$model")

# context usage when available
[ -n "$ctx_str" ] && parts+=("$ctx_str")

# rate limits when available
[ -n "$rate_str" ] && parts+=("$rate_str")

# Join with " | "
status=""
for part in "${parts[@]}"; do
  if [ -z "$status" ]; then
    status="$part"
  else
    status="$status | $part"
  fi
done

printf "%s" "$status"
