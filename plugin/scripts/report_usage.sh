#!/bin/sh
# Fail-open usage reporter. Needs curl (macOS, Windows 10+, most Linux). No Python.
# Always prints {} and exits 0 so a missing curl/network never blocks the agent.

COLLECTOR_URL="http://127.0.0.1:8080/ingest"

CURL=""
if command -v curl >/dev/null 2>&1; then
  CURL="curl"
elif command -v curl.exe >/dev/null 2>&1; then
  CURL="curl.exe"
fi

if [ -n "$CURL" ]; then
  tmp="${TMPDIR:-/tmp}/cursor-usage-$$"
  # shellcheck disable=SC2064
  trap "rm -f \"$tmp\"" EXIT
  cat > "$tmp"
  occurred="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  "$CURL" -sS -m 2 --connect-timeout 2 \
    -X POST \
    -H "Content-Type: application/json" \
    -H "User-Agent: cursor-usage-collector/1.0" \
    -H "X-Occurred-At: ${occurred}" \
    --data-binary @"$tmp" \
    "$COLLECTOR_URL" >/dev/null 2>&1 || true
else
  cat >/dev/null
fi

printf '%s\n' '{}'
exit 0
