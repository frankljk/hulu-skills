#!/usr/bin/env bash
# offers.sh <型号> [--json] —— 实时落库报价（价格/库存/阶梯价，需 HULUIC_KEY）
#
# 注意：返回 coverage: "no_offers" 是正常结果（该型号暂无授权报价），
# 不是错误，不要重复调用。数据写 stdout，诊断写 stderr。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'EOF'
用法 / Usage:
  offers.sh <MPN> [--json]

示例 / Examples:
  offers.sh STM32F103C8T6         # Markdown 输出（默认）
  offers.sh STM32F103C8T6 --json  # JSON envelope 输出

需要 / Requires: export HULUIC_KEY=hulu_sk_...（申请: https://huluic.cn/developer）
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
require_key

ENCODED="$(urlencode "$INPUT")"
rc=0
huluic_request "/v2/offers/$ENCODED" "$FMT" || rc=$?
[ "$rc" -eq 0 ] && exit 0
if [ "$rc" -eq "$EX_NOTFOUND" ]; then
  log "404: 未找到 \"$INPUT\" 的报价记录 / no offers record for this MPN。"
fi
exit "$rc"
