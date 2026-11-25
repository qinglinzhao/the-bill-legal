#!/usr/bin/env bash
# ============================================================================
# legal-guard — regression gate for the published legal pages of
#                 qinglinzhao/the-bill-legal (GitHub Pages project site)
#
# Usage:  bash scripts/check-legal-page.sh [FILE ...]
#         (default target: index.html)
#
# Fails with exit status 1 when any scanned file contains
#   R1  a placeholder token that must never ship
#   R2  a local machine path / build-tree path leak
#   R3  a required legal section is absent (Privacy / EULA-or-Terms /
#       Refund / Support Email — matched on an <h1..h6> heading or an
#       id / name / href anchor, in English or Simplified Chinese)
#
# Every hit is printed as
#   <file>:<line>: [<rule>] <matched line>
# and additionally emitted as a GitHub "::error file=...,line=..." annotation
# so the line number is clickable in the Actions log and on the PR diff.
#
# The rules are intentionally fixed-string for R1/R2 (no regex escaping games
# around backslashes) and case-insensitive throughout.
# ============================================================================
set -uo pipefail

FILES=("$@")
if [ "${#FILES[@]}" -eq 0 ]; then
  FILES=(index.html)
fi

hits=0

emit() { # $1=file  $2=line  $3=rule  $4=text
  hits=$((hits + 1))
  printf '%s:%s: [%s] %s\n' "$1" "$2" "$3" "$4"
  if [ "$2" -gt 0 ]; then
    echo "::error file=$1,line=$2,title=legal-guard $3::forbidden content matched"
  else
    echo "::error file=$1,title=legal-guard $3::required section missing"
  fi
}

scan() { # $1=rule ; remaining args = grep options
  local rule="$1"; shift
  local line file rest lineno text
  while IFS= read -r line; do
    file=${line%%:*}
    rest=${line#*:}
    lineno=${rest%%:*}
    text=${rest#*:}
    emit "$file" "$lineno" "$rule" "$text"
  done < <(grep -Hn -i "$@" -- "${FILES[@]}" 2>/dev/null || true)
}

echo "== legal-guard ==============================================="
echo "targets: ${FILES[*]}"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "::error file=$f::scanned file does not exist"; exit 1; }
done

echo
echo "-- R1 placeholder tokens (fixed strings) ---------------------"
scan R1-placeholder -F \
  -e '[CONTACT EMAIL]' \
  -e '[联系邮箱]' \
  -e '[LEGAL ENTITY NAME]' \
  -e '[法律主体名称]' \
  -e 'example.com'

echo
echo "-- R1b placeholder tokens (word forms, case-insensitive) -----"
scan R1-placeholder -E -e 'TODO' -e 'PLACEHOLDER' -e 'lorem'

echo
echo "-- R2 local path / machine leak (fixed strings) --------------"
scan R2-path-leak -F \
  -e 'D:\' \
  -e 'D:/' \
  -e 'C:\Users' \
  -e 'C:/Users' \
  -e 'AppData' \
  -e '/d/Hermes'

echo
echo "-- R3 required legal sections --------------------------------"
# Each entry: <id> | <label> | <extended regex>
check_section() {
  local id="$1" label="$2" re="$3"
  local hit
  hit=$(grep -n -i -E "$re" -- "${FILES[@]}" 2>/dev/null | head -n 1 || true)
  if [ -z "$hit" ]; then
    # Report against the primary target so the annotation lands on a real file.
    emit "${FILES[0]}" 0 "R3-missing-$id" "required section not found: $label"
  else
    local f=${hit%%:*}; local rest=${hit#*:}; local n=${rest%%:*}
    printf 'OK  %s:%s  (%s)\n' "$f" "$n" "$label"
  fi
}

check_section privacy "Privacy" \
  '(<h[1-6][^>]*>[^<]*(privacy|隐私)|(id|name|href)[[:space:]]*=[[:space:]]*"[^"]*(privacy|隐私))'
check_section eula "EULA / Terms" \
  '(<h[1-6][^>]*>[^<]*(eula|terms|最终用户|服务条款|使用条款)|(id|name|href)[[:space:]]*=[[:space:]]*"[^"]*(eula|terms))'
check_section refund "Refund" \
  '(<h[1-6][^>]*>[^<]*(refund|退款)|(id|name|href)[[:space:]]*=[[:space:]]*"[^"]*(refund))'
check_section support "Support Email" \
  '(<h[1-6][^>]*>[^<]*(support[[:space:]_-]*e?mail|支持邮箱|客服邮箱|技术支持)|(id|name|href)[[:space:]]*=[[:space:]]*"[^"]*(support-?email)|mailto:support@)'

echo
echo "== summary ==================================================="
if [ "$hits" -eq 0 ]; then
  echo "PASS — no forbidden content, all required sections present."
  exit 0
fi
echo "FAIL — $hits violation(s) above. See file:line in the log."
exit 1
