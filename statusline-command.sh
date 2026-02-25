#!/bin/bash

# Read JSON input
input=$(cat)

# Extract values
model=$(echo "$input" | jq -r '.model.display_name')
dir=$(echo "$input" | jq -r '.workspace.current_dir' | xargs basename)
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Get git branch (skip optional locks)
git_branch=""
if git -c core.fileMode=false rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -c core.fileMode=false symbolic-ref --short HEAD 2>/dev/null || git -c core.fileMode=false rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
        git_branch=" | git:($branch)"
    fi
fi

# Build status line with context percentage if available
if [ -n "$used" ]; then
    # Format used percentage to 1 decimal place
    used_formatted=$(printf "%.1f" "$used")
    printf "➜ | %s | %s | [ctx:%s%%]%s" "$model" "$dir" "$used_formatted" "$git_branch"
else
    printf "➜ | %s | %s%s" "$model" "$dir" "$git_branch"
fi
