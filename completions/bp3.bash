# bp3 bash completion: static verbs/edges/flags, dynamic quest/exp names.
# Candidates come from _bp3_candidates (words after bp3, last word is the
# current one); completion fails silently on any error.
# shellcheck shell=bash

_bp3_flags='--format --reason --commit --verdict --target --type --depends-on'
_bp3_edges='handoff grade verify land block resume'
_bp3_quest_verbs='c r d create read delete'
_bp3_exp_verbs='c r u d create read update delete'
_bp3_format_values='json table tree'
_bp3_verdict_values='ship needs_fix pass fail'

_bp3_words() {
  # Print the words of a space-separated list, one per line.
  local w
  # shellcheck disable=SC2086 # the list is split on purpose
  for w in $1; do printf '%s\n' "$w"; done
}

_bp3_filter() {
  # _bp3_filter <current>: print stdin lines starting with <current>.
  local cur="$1" line
  while IFS= read -r line; do
    case "$line" in
      "$cur"*) printf '%s\n' "$line" ;;
    esac
  done
}

_bp3_cmd() {
  if [ -n "${BP3_COMPLETION_BP3:-}" ]; then
    [ -x "$BP3_COMPLETION_BP3" ] || return 1
    printf '%s\n' "$BP3_COMPLETION_BP3"
  elif command -v bp3 >/dev/null 2>&1; then
    printf '%s\n' 'bp3'
  elif [ -x ./bin/bp3 ]; then
    printf '%s\n' './bin/bp3'
  else
    return 1
  fi
}

_bp3_quests() {
  local cmd
  cmd="$(_bp3_cmd)" || return 0
  command -v jq >/dev/null 2>&1 || return 0
  "$cmd" q r 2>/dev/null | jq -r '.quests[]?.quest // empty' 2>/dev/null || true
}

_bp3_exps() {
  local cmd quest="$1"
  cmd="$(_bp3_cmd)" || return 0
  command -v jq >/dev/null 2>&1 || return 0
  "$cmd" q "$quest" r 2>/dev/null | jq -r '.exps[]?.exp // empty' 2>/dev/null || true
}

_bp3_is_verb() {
  case "$1" in
    c|create|r|read|u|update|d|delete) return 0 ;;
    *) return 1 ;;
  esac
}

_bp3_candidates() {
  local -a words=("$@")
  local n=${#words[@]} cur='' prev_last=''
  if [ "$n" -gt 0 ]; then cur="${words[$((n - 1))]}"; fi
  if [ "$n" -gt 1 ]; then prev_last="${words[$((n - 2))]}"; fi

  case "$prev_last" in
    --format) _bp3_words "$_bp3_format_values" | _bp3_filter "$cur"; return 0 ;;
    --verdict) _bp3_words "$_bp3_verdict_values" | _bp3_filter "$cur"; return 0 ;;
    --reason|--commit|--target|--type|--depends-on) return 0 ;;
  esac

  case "$cur" in
    --format=*)
      local v
      for v in $_bp3_format_values; do printf '%s\n' "--format=$v"; done | _bp3_filter "$cur"
      return 0 ;;
    --verdict=*)
      local v
      for v in $_bp3_verdict_values; do printf '%s\n' "--verdict=$v"; done | _bp3_filter "$cur"
      return 0 ;;
    --*|-*)
      _bp3_words "$_bp3_flags" | _bp3_filter "$cur"
      return 0 ;;
  esac

  # Completed words before the current one.
  local -a a=()
  local i
  for ((i = 0; i < n - 1; i++)); do a+=("${words[$i]}"); done

  local has_q=0
  if [ "${#a[@]}" -gt 0 ] && { [ "${a[0]}" = 'q' ] || [ "${a[0]}" = 'quest' ]; }; then
    has_q=1
    local -a rest=()
    local j
    for ((j = 1; j < ${#a[@]}; j++)); do rest+=("${a[$j]}"); done
    a=()
    for ((j = 0; j < ${#rest[@]}; j++)); do a+=("${rest[$j]}"); done
  fi

  if [ "$has_q" -eq 0 ]; then
    if [ "${#a[@]}" -eq 0 ]; then
      printf '%s\n' q quest init skills harness worktree | _bp3_filter "$cur"
    elif [ "${#a[@]}" -eq 1 ] && [ "${a[0]}" = 'skills' ]; then
      printf '%s\n' install | _bp3_filter "$cur"
    elif [ "${#a[@]}" -eq 1 ] && [ "${a[0]}" = 'harness' ]; then
      printf '%s\n' supervisor init-check find-tape watch desk s i f w d | _bp3_filter "$cur"
    elif [ "${#a[@]}" -eq 2 ] && [ "${a[0]}" = 'harness' ] && { [ "${a[1]}" = 'desk' ] || [ "${a[1]}" = 'd' ]; }; then
      printf '%s\n' derive create inspect remove prepare check exit release list | _bp3_filter "$cur"
    elif [ "${#a[@]}" -eq 1 ] && [ "${a[0]}" = 'worktree' ]; then
      printf '%s\n' derive create inspect remove prepare check exit release list | _bp3_filter "$cur"
    fi
    return 0
  fi

  _bp3_cmd >/dev/null 2>&1 || return 0

  if [ "${#a[@]}" -eq 0 ]; then
    _bp3_quests | _bp3_filter "$cur"
    return 0
  fi

  if _bp3_is_verb "${a[0]}"; then
    if [ "${#a[@]}" -eq 1 ]; then
      case "${a[0]}" in
        r|read|d|delete) _bp3_quests | _bp3_filter "$cur" ;;
        *) : ;;
      esac
    fi
    return 0
  fi

  # a[0] is a quest name.
  if [ "${#a[@]}" -eq 1 ]; then
    _bp3_words "$_bp3_exp_verbs" | _bp3_filter "$cur"
    return 0
  fi

  if [ "${#a[@]}" -eq 2 ]; then
    case "${a[1]}" in
      r|read|d|delete|u|update) _bp3_exps "${a[0]}" | _bp3_filter "$cur" ;;
      *) : ;;
    esac
    return 0
  fi

  if [ "${#a[@]}" -eq 3 ] && { [ "${a[1]}" = 'u' ] || [ "${a[1]}" = 'update' ]; }; then
    _bp3_words "$_bp3_edges" | _bp3_filter "$cur"
    return 0
  fi

  return 0
}

_bp3() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local -a cands=()
  local line
  while IFS= read -r line; do
    [ -n "$line" ] && cands+=("$line")
  done < <(_bp3_candidates "${COMP_WORDS[@]:1}" 2>/dev/null)
  COMPREPLY=()
  if [ "${#cands[@]}" -gt 0 ]; then
    # Candidates already match the current word; compgen keeps COMPREPLY exact.
    while IFS= read -r line; do
      COMPREPLY+=("$line")
    done < <(compgen -W "${cands[*]}" -- "$cur" 2>/dev/null)
  fi
  return 0
}

complete -F _bp3 bp3 2>/dev/null || true
