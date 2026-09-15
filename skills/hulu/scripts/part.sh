#!/usr/bin/env bash
# part.sh <型号|关键词> [--json] —— 元件参数 / 厂商 / 分类 / 数据手册（匿名档可用）
#
# /v2/part/{id} 入参是 oneic 编号（onepartno）。本脚本自动处理：
#   1) 直查 /v2/part/<输入>
#   2) 404 时走 /v2/search/<输入>，跟随第一条结果的 detail_path 再查
# 数据写 stdout，诊断写 stderr。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'EOF'
用法 / Usage:
  part.sh <MPN 或关键词> [--json]

示例 / Examples:
  part.sh STM32F103C8T6        # Markdown 输出（默认）
  part.sh STM32F103 --json     # JSON envelope 输出
EOF
  exit "$EX_USAGE"
}

[ $# -lt 1 ] && usage
INPUT="$1"; shift
FMT="markdown"
while [ $# -gt 0 ]; do
  case "$1" in
    --json) FMT="json" ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
  shift
done

[ -n "$INPUT" ] || usage
ENCODED="$(urlencode "$INPUT")"

# 1) 直查详情（精确型号或 onepartno 可直接命中）
rc=0
huluic_request "/v2/part/$ENCODED" "$FMT" || rc=$?
[ "$rc" -eq 0 ] && exit 0
if [ "$rc" -ne "$EX_NOTFOUND" ]; then
  exit "$rc"
fi

# 2) 404 → 搜索兜底：取第一条结果的 detail_path 跟进
log "直查未命中，尝试搜索 \"$INPUT\" … / not found directly, searching…"
if SEARCH_JSON="$(huluic_request "/v2/search/$ENCODED" json)"; then
  :
else
  rc=$?
  printf '%s' "$SEARCH_JSON"
  exit "$rc"
fi

DETAIL_PATH="$(printf '%s' "$SEARCH_JSON" \
  | grep -o '"detail_path"[[:space:]]*:[[:space:]]*"/v2/part/[^"]*"' \
  | head -n 1 \
  | sed 's/.*"\(\/v2\/part\/[^"]*\)".*/\1/')"

if [ -z "$DETAIL_PATH" ]; then
  log "搜索无结果 / no results for \"$INPUT\"。请换关键词重试。"
  exit "$EX_NOTFOUND"
fi

log "跟随搜索结果 / following search hit: $DETAIL_PATH"
huluic_request "$DETAIL_PATH" "$FMT"
