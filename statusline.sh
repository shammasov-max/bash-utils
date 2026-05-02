#!/bin/sh
# Claude Code status line - inspired by Powerlevel10k lean theme
# Adapted for Linux

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // .workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.id // ""')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
session_name=$(echo "$input" | jq -r '.session_name // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // empty')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // empty')

# Token metrics from stdin
session_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
session_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

# Current tool tokens & cache from transcript (last assistant message)
cur_in="" cur_out="" cache_read="" cache_create=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  last_usage=$(tac "$transcript" 2>/dev/null | grep -m1 '"type":"assistant"\|"type": "assistant"' | jq -r '.message.usage // empty' 2>/dev/null)
  if [ -n "$last_usage" ] && [ "$last_usage" != "null" ]; then
    cur_in=$(echo "$last_usage" | jq -r '.input_tokens // 0')
    cur_out=$(echo "$last_usage" | jq -r '.output_tokens // 0')
    cache_read=$(echo "$last_usage" | jq -r '.cache_read_input_tokens // 0')
    cache_create=$(echo "$last_usage" | jq -r '.cache_creation_input_tokens // 0')
  fi
fi

# Format token count: 999 → "999", 1500 → "1.5k", 1500000 → "1.5M"
fmt_tok() {
  n="$1"
  if [ -z "$n" ] || [ "$n" = "null" ]; then printf -- "--"; return; fi
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    awk "BEGIN{printf \"%.1fM\", $n/1000000}"
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    awk "BEGIN{printf \"%.1fk\", $n/1000}"
  else
    printf "%s" "$n"
  fi
}

# Model pricing (per 1M tokens, USD)
# Prices: input / output / cache_write / cache_read
get_pricing() {
  local m="$1"
  case "$m" in
    *opus-4*|*opus-4-5*)        printf "15 75 18.75 1.5" ;;
    *opus*)                      printf "15 75 18.75 1.5" ;;
    *sonnet-4-5*|*sonnet-4*)    printf "3 15 3.75 0.3" ;;
    *sonnet*)                    printf "3 15 3.75 0.3" ;;
    *haiku*)                     printf "0.8 4 1 0.08" ;;
    *)                           printf "3 15 3.75 0.3" ;;
  esac
}

# Calculate session cost in USD
session_cost=""
daily_cost=""
if [ -n "$session_in" ] && [ -n "$session_out" ]; then
  pricing=$(get_pricing "$model")
  p_in=$(printf "%s" "$pricing" | awk '{print $1}')
  p_out=$(printf "%s" "$pricing" | awk '{print $2}')
  p_cw=$(printf "%s" "$pricing" | awk '{print $3}')
  p_cr=$(printf "%s" "$pricing" | awk '{print $4}')

  # session_cost = (in * p_in + out * p_out + cache_create * p_cw + cache_read * p_cr) / 1e6
  s_cost=$(awk "BEGIN{
    cr=${cache_read:-0}; cc=${cache_create:-0}
    inp=${session_in:-0}; out=${session_out:-0}
    base_in=inp-cr-cc; if(base_in<0) base_in=0
    printf \"%.4f\", (base_in*${p_in}+out*${p_out}+cc*${p_cw}+cr*${p_cr})/1000000
  }")

  # Format: $0.12 or $1.23
  session_cost=$(awk "BEGIN{printf \"\$%.2f\", ${s_cost}}")

  # Daily cost tracking — file per day, keyed by session_id
  today=$(date +%Y-%m-%d)
  daily_file="/tmp/claude-daily-${today}.json"

  # Update daily cost file: store per-session latest cost, sum all
  if [ -n "$session_id" ]; then
    # Read existing file or init empty
    if [ -f "$daily_file" ]; then
      old_cost=$(jq -r --arg sid "$session_id" '.sessions[$sid] // "0"' "$daily_file" 2>/dev/null || echo "0")
      new_json=$(jq --arg sid "$session_id" --arg cost "$s_cost" \
        '.sessions[$sid] = $cost' "$daily_file" 2>/dev/null)
    else
      old_cost="0"
      new_json="{\"sessions\":{\"${session_id}\":\"${s_cost}\"}}"
    fi
    printf "%s" "$new_json" > "$daily_file" 2>/dev/null

    # Sum all session costs
    daily_total=$(jq '[.sessions | to_entries[].value | tonumber] | add // 0' "$daily_file" 2>/dev/null)
    daily_cost=$(awk "BEGIN{printf \"\$%.2f\", ${daily_total:-0}}")
  fi
fi

# Cache hit percentage
cache_pct=""
if [ -n "$cache_read" ] && [ "$cache_read" != "0" ]; then
  cache_total=$((${cache_read:-0} + ${cache_create:-0} + $(echo "$last_usage" | jq -r '.input_tokens // 0')))
  if [ "$cache_total" -gt 0 ] 2>/dev/null; then
    cache_pct=$(awk "BEGIN{printf \"%.0f\", $cache_read/$cache_total*100}")
  fi
fi

# Shorten home directory
home="$HOME"
short_dir="${cwd/#$home/~}"

# Shorten path: ~/projects/deep/my-app → ~/p/d/my-app
shorten_path() {
  local p="${1/#$home/\~}"
  local base="${p##*/}"
  local dir="${p%/*}"
  [ "$dir" = "$p" ] && { printf "%s" "$p"; return; }
  local short="" part old_IFS="$IFS"
  IFS='/'
  for part in $dir; do
    if [ "$part" = "~" ]; then
      short="~"
    elif [ -n "$part" ]; then
      short="${short}/${part:0:1}"
    fi
  done
  IFS="$old_IFS"
  printf "%s/%s" "$short" "$base"
}
short_project=$(shorten_path "$project_dir")

# Git info
git_branch=""
git_dirty=""
if git -C "$cwd" rev-parse --git-dir --no-optional-locks > /dev/null 2>&1; then
  git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$git_branch" ]; then
    git_status=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
    if [ -n "$git_status" ]; then
      git_dirty=" *"
    fi
  fi
fi

# Context usage percentage
ctx_pct=""
ctx_color="32"  # green
if [ -n "$used_pct" ]; then
  ctx_pct=$(printf "%.0f" "$used_pct")
  if [ "$ctx_pct" -ge 80 ]; then
    ctx_color="31"  # red
  elif [ "$ctx_pct" -ge 50 ]; then
    ctx_color="33"  # yellow
  fi
fi

# Usage limits (cached for 60 seconds)
cache_file="/tmp/claude-usage-cache.json"
cache_ttl=60
five_h=""
seven_d=""
fh_reset=""
sd_reset=""

fetch_usage() {
  creds_file="$HOME/.claude/.credentials.json"
  [ -f "$creds_file" ] || return 1
  access_token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds_file" 2>/dev/null) || return 1
  [ -z "$access_token" ] && return 1
  tmp_file="${cache_file}.tmp"
  curl -s --max-time 3 "https://api.anthropic.com/api/oauth/usage" \
    -H "Authorization: Bearer $access_token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "User-Agent: claude-code/2.1.47" > "$tmp_file" 2>/dev/null
  if [ -s "$tmp_file" ]; then
    mv "$tmp_file" "$cache_file"
  else
    rm -f "$tmp_file"
  fi
}

need_refresh=true
if [ -f "$cache_file" ]; then
  cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
  if [ "$cache_age" -lt "$cache_ttl" ]; then
    need_refresh=false
  fi
fi

if [ "$need_refresh" = true ]; then
  fetch_usage
fi

if [ -f "$cache_file" ]; then
  five_h=$(jq -r '.five_hour.utilization // empty' "$cache_file" 2>/dev/null)
  seven_d=$(jq -r '.seven_day.utilization // empty' "$cache_file" 2>/dev/null)
  five_h=${five_h%.*}
  seven_d=${seven_d%.*}

  fh_ts=$(jq -r '.five_hour.resets_at // empty' "$cache_file" 2>/dev/null)
  sd_ts=$(jq -r '.seven_day.resets_at // empty' "$cache_file" 2>/dev/null)
  if [ -n "$fh_ts" ]; then
    epoch=$(date -d "${fh_ts%%.*}" "+%s" 2>/dev/null)
    [ -n "$epoch" ] && fh_reset=$(date -d "@$epoch" "+%H:%M" 2>/dev/null)
  fi
  if [ -n "$sd_ts" ]; then
    epoch=$(date -d "${sd_ts%%.*}" "+%s" 2>/dev/null)
    [ -n "$epoch" ] && sd_reset=$(date -d "@$epoch" "+%-d'%H:%M" 2>/dev/null)
  fi
fi

# Workflow sessions (filtered to current Claude Code instance)
wf_info=""
wf_state_dir="$HOME/.claude/workflow-state"
if [ -d "$wf_state_dir" ]; then
  active_count=0
  active_name=""
  for f in "$wf_state_dir"/*.json; do
    [ -f "$f" ] || continue
    af=$(jq -r '.active_frame // -1' "$f" 2>/dev/null)
    if [ "$af" -ge 0 ]; then
      cpid=$(jq -r '.context.claude_code_pid // 0' "$f" 2>/dev/null)
      [ "$cpid" != "$PPID" ] && continue
      active_count=$((active_count + 1))
      if [ -z "$active_name" ]; then
        active_name=$(jq -r '.stack[.active_frame].workflow // ""' "$f" 2>/dev/null)
        active_state=$(jq -r '.stack[.active_frame].current_state // ""' "$f" 2>/dev/null)
      fi
    fi
  done
  if [ "$active_count" -gt 0 ]; then
    if [ "$active_count" -eq 1 ] && [ -n "$active_name" ]; then
      wf_info="\033[96m\xE2\x9A\x99 ${active_name}:${active_state}\033[0m \033[2;90mhttp://localhost:3100\033[0m"
    else
      wf_info="\033[96m\xE2\x9A\x99 ${active_count} workflows\033[0m \033[2;90mhttp://localhost:3100\033[0m"
    fi
  fi
fi

# Build output
output=""

# PS1-style user@host:project prefix — bold green user@host, bold blue project path
output="\033[01;32m$(whoami)@$(hostname -s)\033[00m:\033[01;34m${short_project}\033[00m"

# Lines added/removed — right after path, before branch
if [ -n "$lines_added" ] || [ -n "$lines_removed" ]; then
  added_val="${lines_added:-0}"
  removed_val="${lines_removed:-0}"
  if [ "$added_val" -gt 0 ] 2>/dev/null; then
    added_colored="\033[32m${added_val}\033[0m"
  else
    added_colored="\033[90m${added_val}\033[0m"
  fi
  if [ "$removed_val" -gt 0 ] 2>/dev/null; then
    removed_colored="\033[31m${removed_val}\033[0m"
  else
    removed_colored="\033[90m${removed_val}\033[0m"
  fi
  output="${output}\t${added_colored} ${removed_colored}"
fi

# Git branch (green clean, yellow dirty)
if [ -n "$git_branch" ]; then
  if [ -n "$git_dirty" ]; then
    output="${output} \t\033[33m${git_branch}${git_dirty}\033[0m"
  else
    output="${output} \t\033[32m${git_branch}\033[0m"
  fi
fi

# Session name (cyan)
if [ -n "$session_name" ]; then
  output="${output} \033[36m[${session_name}]\033[0m"
fi

# Workflow (cyan)
if [ -n "$wf_info" ]; then
  output="${output}  ${wf_info}"
fi

# Model short name (magenta): claude-sonnet-4-6 → sonnet
short_model=$(printf "%s" "$model" | sed 's/claude-\([^-]*\).*/\1/')
output="${output}  \033[35m${short_model}\033[0m"

# Metrics group
metrics=""

if [ -n "$ctx_pct" ]; then
  metrics="\033[${ctx_color}m\xEF\x8B\x9B ${ctx_pct}%\033[0m"
fi

if [ -n "$seven_d" ]; then
  if [ "$seven_d" -ge 80 ]; then sd_color="31"
  elif [ "$seven_d" -ge 50 ]; then sd_color="33"
  else sd_color="90"; fi
  metrics="${metrics}  \033[${sd_color}m\xEF\x81\xB3 ${seven_d}%\033[0m"
fi

if [ -n "$five_h" ]; then
  if [ "$five_h" -ge 80 ]; then fh_color="31"
  elif [ "$five_h" -ge 50 ]; then fh_color="33"
  else fh_color="90"; fi
  metrics="${metrics}  \033[${fh_color}m\xEF\x80\x97 ${five_h}%\033[0m"
  if [ -n "$fh_reset" ]; then
    metrics="${metrics}\033[2;90m ${fh_reset}\033[0m"
  fi
fi

output="${output}  ${metrics}"

# Session cost + daily spend (dim, at end of line)
if [ -n "$session_cost" ]; then
  cost_str="\033[2;37m${session_cost}"
  if [ -n "$daily_cost" ] && [ "$daily_cost" != "$session_cost" ]; then
    cost_str="${cost_str}\033[2;90m/\033[2;37m${daily_cost}d"
  fi
  cost_str="${cost_str}\033[0m"
  output="${output}  ${cost_str}"
fi

printf "%b" "$output"
