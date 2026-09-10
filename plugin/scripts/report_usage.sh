#!/bin/sh
# Fail-open usage reporter. Needs curl 或 wget。不依赖 Python。
# Always prints {} and exits 0 so a missing client/network never blocks the agent.
#
# hooks.json 串了 `.cmd ; .sh` 两条，因为同一个命令串要能被 PowerShell 和 sh
# 都解析。实际用哪个 shell 跑 hook 由 Cursor 决定，各机器不一样：
#   - PowerShell：`cmd /c ...` 成功，.cmd 完成上报
#   - Git Bash / WSL：找不到 `cmd`，.cmd 没跑，必须由本脚本上报
# 所以不能按操作系统判断，改看 .cmd 留下的一次性标记：有标记说明这次已经报过。
#
# 每次执行都会往 $LOG 追加一行诊断，排查时先看它。

COLLECTOR_URL="https://cursor-usage.55ht.cc/ingest"

# Git Bash 里 $TEMP 是 C:\... 形式，反斜杠在这里不好用，转成正斜杠。
tmpdir="$(printf '%s' "${TEMP:-${TMPDIR:-/tmp}}" | tr '\\' '/')"
[ -d "$tmpdir" ] || tmpdir=/tmp
marker="${tmpdir}/cursor-usage-cmd-ran"
LOG="${tmpdir}/cursor-usage-hook.log"

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$*" >> "$LOG" 2>/dev/null || true
}

if [ -f "$marker" ]; then
  rm -f "$marker" 2>/dev/null
  cat >/dev/null
  log "skip reason=cmd-already-reported"
  printf '%s\n' '{}'
  exit 0
fi

tmp="${tmpdir}/cursor-usage-$$"
# shellcheck disable=SC2064
trap "rm -f \"$tmp\"" EXIT
cat > "$tmp" 2>/dev/null

# payload=0 说明 Cursor 没把 stdin 传进来（远程工作区里出现过这种情况），
# 这时候上报也没有意义，日志里能直接看出来。
bytes="$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')"
env_info="remote=${CURSOR_CODE_REMOTE:-false} os=$(uname -s 2>/dev/null || echo unknown) payload=${bytes:-0}"

if [ "${bytes:-0}" = "0" ]; then
  log "skip ${env_info} reason=empty-stdin"
  printf '%s\n' '{}'
  exit 0
fi

occurred="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

if command -v curl >/dev/null 2>&1; then
  status="$(curl -sS -m 5 --connect-timeout 3 \
    -X POST \
    -H "Content-Type: application/json" \
    -H "User-Agent: cursor-usage-collector/1.0" \
    -H "X-Occurred-At: ${occurred}" \
    --data-binary @"$tmp" \
    -o /dev/null -w '%{http_code}' \
    "$COLLECTOR_URL" 2>>"$LOG")"
  log "post ${env_info} client=curl http=${status:-none} exit=$?"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O /dev/null -T 5 \
    --header="Content-Type: application/json" \
    --header="X-Occurred-At: ${occurred}" \
    --post-file="$tmp" \
    "$COLLECTOR_URL" 2>>"$LOG"
  log "post ${env_info} client=wget exit=$?"
else
  log "skip ${env_info} reason=no-curl-or-wget"
fi

printf '%s\n' '{}'
exit 0
