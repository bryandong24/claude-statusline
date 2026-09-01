#!/bin/bash
# Claude Code status line: model | effort (ULTRA) | context | $ cost | usage left (5h / 7d / model-scoped weekly) + reset countdowns
# The model-scoped weekly bucket isn't in the statusline payload; it comes from
# Anthropic's OAuth usage endpoint (same data /usage shows), using the local
# Claude Code credentials, cached for 60s and refreshed in the background.

input=$(cat)

eval "$(printf '%s' "$input" | jq -r '@sh "m=\(.model.display_name // "?") e=\(.effort.level // "?") p=\(.context_window.used_percentage // 0 | round) t=\(.context_window.total_input_tokens // 0) w=\(.context_window.context_window_size // 0) u=\(if .ultracode == true or .effort.level == "max" then "on" else "off" end) r5=\((.rate_limits.five_hour.used_percentage // "-") | if type == "number" then round else "-" end) r7=\((.rate_limits.seven_day.used_percentage // "-") | if type == "number" then round else "-" end) z5=\((.rate_limits.five_hour.resets_at // "-") | if type == "number" then round else "-" end) z7=\((.rate_limits.seven_day.resets_at // "-") | if type == "number" then round else "-" end) cost=\(.cost.total_cost_usd // 0)"')"

cache="$HOME/.cache/claude-statusline-usage.json"
mkdir -p "$HOME/.cache" 2>/dev/null
mt=$(stat -c %Y "$cache" 2>/dev/null || echo 0)
now=$(date +%s)
if [ $((now - mt)) -ge 60 ]; then
  touch "$cache" 2>/dev/null   # claim the refresh window so rapid re-renders don't pile up fetches
  (
    tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$HOME/.claude/.credentials.json" 2>/dev/null)
    if [ -n "$tok" ]; then
      tmp="$cache.tmp.$$"
      if curl -sS -m 5 https://api.anthropic.com/api/oauth/usage \
           -H "Authorization: Bearer $tok" -H "anthropic-beta: oauth-2025-04-20" \
           -o "$tmp" 2>/dev/null && jq -e '.limits' "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$cache"
      else
        rm -f "$tmp"
      fi
    fi
  ) >/dev/null 2>&1 &
fi

rf="-"; rn="model"; zf="-"
if [ -s "$cache" ]; then
  eval "$(jq -r '([.limits[]? | select(.kind == "weekly_scoped")][0]) as $s | @sh "rf=\(($s.percent // "-") | if type == "number" then round else "-" end) rn=\(($s.scope.model.display_name // "model") | ascii_downcase | split(" ")[0]) rt=\($s.resets_at // "-")"' "$cache" 2>/dev/null)"
  [ "$rt" != "-" ] && zf=$(date -d "$rt" +%s 2>/dev/null || echo "-")
fi

if [ "$p" -ge 80 ]; then pc='\033[01;31m'; elif [ "$p" -ge 50 ]; then pc='\033[01;33m'; else pc='\033[01;32m'; fi
if [ "$w" -ge 1000000 ]; then ws="$((w/1000000))M"; else ws="$((w/1000))k"; fi
if [ "$u" = "on" ]; then ue=" \033[01;33m⚡ULTRA\033[00m"; else ue=""; fi
cst=$(LC_ALL=C printf '%.2f' "$cost" 2>/dev/null || echo 0.00)

fmt() { # $1 = seconds until reset -> compact countdown (2d5h / 3h12m / 37m)
  local s=$1
  [ "$s" -lt 0 ] && s=0
  local d=$((s/86400)) h=$(( (s%86400)/3600 )) mn=$(( (s%3600)/60 ))
  if [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$mn"
  else printf '%dm' "$mn"; fi
}

lim() { # $1 = used percentage; prints colored "<remaining>%%" for embedding in a printf format
  local left=$((100-$1)) c='\033[01;32m'
  [ "$left" -le 40 ] && c='\033[01;33m'
  [ "$left" -le 15 ] && c='\033[01;31m'
  printf '%s' "${c}${left}%%\033[00m"
}

bucket() { # $1 = label, $2 = used pct, $3 = reset epoch or "-"
  local out="\033[02m$1\033[00m $(lim "$2")"
  if [ "$3" != "-" ] && [ -n "$3" ]; then out="$out \033[02m($(fmt $(( $3 - now ))))\033[00m"; fi
  printf '%s' "$out"
}

rl=""
[ "$r5" != "-" ] && rl="$(bucket 5h "$r5" "$z5")"
[ "$r7" != "-" ] && rl="${rl}${rl:+ \033[02m·\033[00m }$(bucket 7d "$r7" "$z7")"
[ "$rf" != "-" ] && rl="${rl}${rl:+ \033[02m·\033[00m }$(bucket "$rn" "$rf" "$zf")"
[ -n "$rl" ] && rl=" \033[02m|\033[00m ${rl} \033[02mleft\033[00m"

printf "\033[01;36m%s\033[00m \033[02m|\033[00m \033[01;35m%s\033[00m$ue \033[02m|\033[00m ${pc}ctx %s%%\033[00m \033[02m(%sk/%s)\033[00m \033[02m|\033[00m \$%s$rl" "$m" "$e" "$p" "$((t/1000))" "$ws" "$cst"
