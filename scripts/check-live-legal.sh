#!/usr/bin/env bash
# ============================================================================
# live-legal-monitor — probe the PUBLISHED legal page and fail loudly when it
#                     regresses. Companion of scripts/check-legal-page.sh:
#   check-legal-page.sh  guards the SOURCE (tracked *.html, runs on every push/PR)
#   check-live-legal.sh  guards PRODUCTION (fetches the real URL over HTTP)
#
# Usage:  bash scripts/check-live-legal.sh [BASE_URL]
#         default BASE_URL = https://qinglinzhao.github.io/the-bill-legal/
#
# Asserts, against whatever the URL actually serves:
#   A1  HTTP 200 and a plausibly complete body (>= 4000 bytes)
#   A2  the four legal anchors are present as real attributes:
#       id="privacy" / id="terms" / id="refund" / id="support"
#   A3  no placeholder junk shipped: TODO / example.com / [CONTACT EMAIL] /
#       [LEGAL ENTITY NAME] (case-insensitive)
#   A4  the page still looks like the legal page (title + support mailto)
#
# Exit 0 = pass, 1 = at least one assertion failed. Every failure is printed as
# a GitHub ::error annotation so it shows up on the run summary and the job log.
# ============================================================================
set -uo pipefail

BASE="${1:-https://qinglinzhao.github.io/the-bill-legal/}"
case "$BASE" in
  */) ;;
  *) BASE="$BASE/" ;;
esac

CACHEBUST="cb=$(date +%s)$$"
TARGET="${BASE}?${CACHEBUST}"
BODY="$(mktemp 2>/dev/null || echo "./live-legal-$$.html")"
ERR="${BODY}.err"
trap 'rm -f "$BODY" "$ERR"' EXIT
# Native curl on this dev box (Git-Bash/MSYS) does not understand /c/... paths
# that mktemp hands out, so hand it a native path there. Runners are Linux.
BODY_ARG="$BODY"
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*) command -v cygpath >/dev/null 2>&1 && BODY_ARG="$(cygpath -w "$BODY")" ;;
esac
MIN_BYTES=4000

fails=0
fail() { fails=$((fails + 1)); printf 'FAIL  %s\n' "$*"; echo "::error title=live-legal-monitor::$*"; }
ok()   { printf 'OK    %s\n' "$*"; }

echo "== live-legal-monitor ========================================"
echo "base:       $BASE"
echo "requesting: $TARGET"

code=$(curl -sS -L --max-time 30 -A 'the-bill-legal-monitor/1' -o "$BODY_ARG" -w '%{http_code}' "$TARGET" 2>"$ERR")
curl_rc=$?
if [ "$curl_rc" -ne 0 ]; then
  echo "curl stderr: $(cat "$ERR" 2>/dev/null)"
fi
[ -f "$BODY" ] || : > "$BODY"

bytes=$(wc -c < "$BODY" 2>/dev/null | tr -d ' \r\n')
[ -n "${bytes:-}" ] || bytes=0
echo "http:       ${code:-000}"
echo "bytes:      $bytes"
echo

echo "-- A1 HTTP status + body size --------------------------------"
[ "${code:-000}" = "200" ] || fail "A1 http status ${code:-000} (want 200)"
if [ "$bytes" -ge "$MIN_BYTES" ]; then
  ok "A1 http 200, ${bytes} B (>= ${MIN_BYTES})"
else
  fail "A1b body is only ${bytes} B (want >= ${MIN_BYTES}; truncated or empty deploy?)"
fi

echo
echo "-- A2 four legal anchors (real id attributes) ----------------"
for id in privacy terms refund support; do
  hit=$(grep -n -F "id=\"$id\"" "$BODY" 2>/dev/null | head -n 1)
  if [ -n "$hit" ]; then
    ok "A2 id=\"$id\"  @ line ${hit%%:*}"
  else
    fail "A2 anchor missing on the live page: id=\"$id\""
  fi
done

echo
echo "-- A3 placeholder junk --------------------------------------"
junk=$(grep -n -i -E '\bTODO\b|example\.com|PLACEHOLDER|\[CONTACT EMAIL\]|\[LEGAL ENTITY NAME\]' "$BODY" 2>/dev/null || true)
if [ -z "$junk" ]; then
  ok "A3 no TODO / example.com / placeholder tokens"
else
  while IFS= read -r line; do
    fail "A3 placeholder token on live page: ${line}"
  done <<< "$junk"
fi

echo
echo "-- A4 page identity -----------------------------------------"
if grep -q -i -E '<title>[^<]*THE BILL' "$BODY" 2>/dev/null; then
  ok "A4 <title> mentions THE BILL"
else
  fail "A4 <title> no longer mentions THE BILL (wrong page served?)"
fi

echo
echo "== summary ==================================================="
if [ "$fails" -eq 0 ]; then
  echo "PASS — live legal page serves all four anchors, HTTP 200, no placeholder junk."
  exit 0
fi
echo "FAIL — $fails assertion(s) failed against $BASE"
exit 1
