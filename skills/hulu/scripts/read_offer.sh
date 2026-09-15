#!/usr/bin/env bash
# read_offer.sh <商品页URL> [--mpn 期望型号] [--json] —— URL → 结构化 Offer（需 HULUIC_KEY）
#
# 抓取目标商品页并抽取为结构化报价（价格/库存/MOQ/阶梯价），
# --mpn 用于 verified.mpn_matched 一致性校验。目标 URL 经 RFC 3986 编码后放入路径。
# 该端点是长请求（抓取 + 抽取），请耐心等待。数据写 stdout，诊断写 stderr。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'EOF'
用法 / Usage:
  read_offer.sh <商品页URL> [--mpn 期望型号] [--json]

示例 / Examples:
  read_offer.sh "https://www.example-mall.com/product/12345"
  read_offer.sh "https://www.example-mall.com/product/12345" --mpn STM32F103C8T6 --json

需要 / Requires: export HULUIC_KEY=hulu_sk_...（申请: https://huluic.cn/developer）
EOF
  exit "$EX_USAGE"
}

[ $# -lt 1 ] && usage
URL="$1"; shift
FMT="markdown"
MPN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) FMT="json" ;;
    --mpn) shift; MPN="${1:-}"; [ -n "$MPN" ] || usage ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
  shift
done

case "$URL" in
  http://*|https://*) ;;
  *) log "错误: URL 必须以 http(s):// 开头 / URL must start with http(s)://"; usage ;;
esac
require_key

ENCODED_URL="$(urlencode "$URL")"
REQ_PATH="/v2/offer/$ENCODED_URL"
if [ -n "$MPN" ]; then
  REQ_PATH="$REQ_PATH?mpn=$(urlencode "$MPN")"
fi

huluic_request "$REQ_PATH" "$FMT"
