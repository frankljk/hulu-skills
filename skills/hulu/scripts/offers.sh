#!/usr/bin/env bash
# offers.sh <型号> [--json] [--live] [--channels id1,id2] —— 报价查询（需 HULUIC_KEY）
#
# 默认模式：GET /v2/offers/{mpn} 落库快照（秒回，阶梯价/库存/新鲜度）。
#   注意：返回 coverage: "no_offers" 是正常结果（该型号暂无授权报价），
#   不是错误，不要重复调用。数据写 stdout，诊断写 stderr。
#
# --live 模式：GET /v2/offers/live/{mpn} 多渠道实时搜索（SSE，30~120s）。
#   渠道进度实时写 stderr；结束后 done 事件 JSON（summary + 合并 offers +
#   attribution）写 stdout。渠道级失败/需登录属常态，只要 done 正常到达即为成功。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat >&2 <<'EOF'
用法 / Usage:
  offers.sh <MPN> [--json] [--live] [--channels id1,id2]

示例 / Examples:
  offers.sh STM32F103C8T6                     # 落库快照（Markdown，默认）
  offers.sh STM32F103C8T6 --json              # 落库快照（JSON envelope）
  offers.sh LM358 --live                      # 实时多渠道搜索（SSE，stdout 为 done 事件 JSON）
  offers.sh LM358 --live --channels digikey,mouser   # 只搜指定 API 渠道

需要 / Requires: export HULUIC_KEY=hulu_sk_...（申请: https://huluic.cn/developer）
EOF
  exit "$EX_USAGE"
}

[ $# -lt 1 ] && usage
INPUT="$1"; shift
FMT="markdown"
LIVE=0
CHANNELS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) FMT="json" ;;
    --live) LIVE=1 ;;
    --channels)
      [ $# -ge 2 ] || usage
      CHANNELS="$2"; shift
      ;;
    --channels=*) CHANNELS="${1#--channels=}" ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
  shift
done

[ -n "$INPUT" ] || usage
require_key

ENCODED="$(urlencode "$INPUT")"

# ------------------------------------------------------------------
# --live：SSE 消费（curl -N 逐行读；渠道进度 → stderr，done JSON → stdout）
# ------------------------------------------------------------------
offers_live() {
  local retried="${1:-0}"
  local path="/v2/offers/live/$ENCODED"
  [ -n "$CHANNELS" ] && path="${path}?channels=$(urlencode "$CHANNELS")"

  local event="" done_json="" line data
  : > "$HULUIC_TMP_BODY"
  # shellcheck disable=SC2034  # event 在 case 中读写
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
      "event: "*) event="${line#event: }" ;;
      "data: "*)
        data="${line#data: }"
        case "$event" in
          channel)
            if command -v jq >/dev/null 2>&1; then
              printf '%s\n' "$(printf '%s' "$data" | jq -r \
                '"[\(.status)] \(.channel_name // .channel_id)" +
                 (if .count != null then " \(.count) 条" else "" end) +
                 (if .error then " — \(.error)" else "" end) +
                 (if .login_url then "（需登录: \(.login_url)）" else "" end)' 2>/dev/null || printf '%s' "$data")" >&2
            else
              log "渠道进度 / channel: $data"
            fi
            ;;
          done) done_json="$data" ;;
          error) printf '%s\n' "$data" >&2 ;;
        esac
        ;;
    esac
  done < <(curl -sS -N --max-time 300 \
              -D "$HULUIC_TMP_HDR" \
              -H "Accept: text/event-stream" \
              -H "User-Agent: hulu-skill/1.0 (+https://huluic.cn/developer)" \
              -H "Authorization: Bearer ${HULUIC_KEY}" \
              "${HULUIC_API_BASE}${path}" | tee "$HULUIC_TMP_BODY")

  local status
  status="$(head -n 1 "$HULUIC_TMP_HDR" | tr -d '\r' | awk '{print $2}')"

  case "$status" in
    2*)
      if [ -n "$done_json" ]; then
        printf '%s\n' "$done_json"
        return 0
      fi
      log "SSE 流结束但未收到 done 事件（搜索被中断或服务异常）。"
      return "$EX_HTTP"
      ;;
    401|403)
      cat "$HULUIC_TMP_BODY"
      log ""
      log "$status 鉴权失败 / auth failed: 检查 HULUIC_KEY 是否有效且权限含 offers-live（申请: https://huluic.cn/developer）。"
      return "$EX_AUTH"
      ;;
    429)
      if [ "$retried" = "0" ]; then
        local wait
        wait="$(retry_after_seconds "$HULUIC_TMP_HDR")"
        log "429 限流 / rate limited，${wait}s 后自动重试一次…"
        sleep "$wait"
        offers_live 1
        return $?
      fi
      cat "$HULUIC_TMP_BODY"
      log ""
      log "429 限流 / rate limited（offers-live 起步 100 次/天；已自动重试一次仍被限流）。"
      return "$EX_RATELIMIT"
      ;;
    *)
      cat "$HULUIC_TMP_BODY"
      log ""
      log "HTTP $status 错误 / request failed（X-Request-Id 见错误信封 meta）。"
      return "$EX_HTTP"
      ;;
  esac
}

if [ "$LIVE" = "1" ]; then
  offers_live
  exit $?
fi

rc=0
huluic_request "/v2/offers/$ENCODED" "$FMT" || rc=$?
[ "$rc" -eq 0 ] && exit 0
if [ "$rc" -eq "$EX_NOTFOUND" ]; then
  log "404: 未找到 \"$INPUT\" 的报价记录 / no offers record for this MPN。"
fi
exit "$rc"
