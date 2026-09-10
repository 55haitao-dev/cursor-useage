#!/bin/sh
# Fail-open usage reporter. Needs curl (macOS, Windows 10+, most Linux). No Python.
# Always prints {} and exits 0 so a missing curl/network never blocks the agent.
#
# hooks.json 串了 `.cmd ; .sh` 两条，因为同一个命令串要能被 PowerShell 和 sh
# 都解析。实际用哪个 shell 跑 hook 由 Cursor 决定，各机器不一样：
#   - PowerShell：`cmd /c ...` 成功，.cmd 完成上报
#   - Git Bash：找不到 `cmd`，.cmd 没跑，必须由本脚本上报
# 所以不能按操作系统判断，改看 .cmd 留下的一次性标记：有标记说明这次已经报过。

COLLECTOR_URL="https://cursor-usage.55ht.cc/ingest"

# Git Bash 里 $TEMP 是 C:\... 形式，反斜杠在这里不好用，转成正斜杠。
tmpdir="$(printf '%s' "${TEMP:-${TMPDIR:-/tmp}}" | tr '\\' '/')"
marker="${tmpdir}/cursor-usage-cmd-ran"

if [ -f "$marker" ]; then
  rm -f "$marker"
  cat >/dev/null
  printf '%s\n' '{}'
  exit 0
fi

if command -v curl >/dev/null 2>&1; then
  tmp="${tmpdir}/cursor-usage-$$"
  # shellcheck disable=SC2064
  trap "rm -f \"$tmp\"" EXIT
  cat > "$tmp"
  occurred="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  curl -sS -m 2 --connect-timeout 2 \
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
