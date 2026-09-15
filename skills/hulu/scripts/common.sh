#!/usr/bin/env bash
# common.sh —— hulu skill 三个脚本的共享函数库（被 source，不直接执行）
#
# 约定：
#   - 数据（API 响应体）写 stdout，诊断信息写 stderr，互不污染
#   - 退出码：0 成功 / 1 其他 HTTP 或网络错误 / 2 用法错误 / 3 鉴权问题 / 4 未找到 / 5 限流
#   - 环境变量：HULUIC_KEY（API Key，hulu_sk_ 前缀）、HULUIC_API_BASE（默认 https://r.huluic.cn）

HULUIC_API_BASE="${HULUIC_API_BASE:-https://r.huluic.cn}"

EX_USAGE=2
EX_AUTH=3
EX_NOTFOUND=4
EX_RATELIMIT=5
EX_HTTP=1

HULUIC_TMP_HDR="$(mktemp)"
HULUIC_TMP_BODY="$(mktemp)"
trap 'rm -f "$HULUIC_TMP_HDR" "$HULUIC_TMP_BODY"' EXIT

log() { printf '%s\n' "$*" >&2; }

# Key 档端点前置检查：未配置 HULUIC_KEY 时直接失败并给出申请入口
require_key() {
  if [ -z "${HULUIC_KEY:-}" ]; then
    log "错误: 该端点需要 API Key（匿名档不开放）。"
    log "Error: this endpoint requires an API key."
    log "申请 / Get a key: https://huluic.cn/developer （前缀 hulu_sk_）"
    log "配置 / Configure: export HULUIC_KEY=hulu_sk_..."
    exit "$EX_AUTH"
  fi
}

# RFC 3986 percent-encode。LC_ALL=C 按字节遍历，对 UTF-8 多字节字符安全。
urlencode() {
  local LC_ALL=C
  local s="$1" out="" i c
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9._~-]) out+="$c" ;;
      *) printf -v c '%%%02X' "'$c"; out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

# 429 等待秒数：优先 Retry-After，回退 X-RateLimit-Reset（Unix 秒），兜底 30s，封顶 120s
retry_after_seconds() {
  local hf="$1" ra reset now delta
  ra="$(grep -i '^Retry-After:' "$hf" | tr -d '\r' | awk '{print $2}' | head -n 1)"
  if [[ "$ra" =~ ^[0-9]+$ ]]; then
    [ "$ra" -gt 120 ] && ra=120
    echo "$ra"; return
  fi
  reset="$(grep -i '^X-RateLimit-Reset:' "$hf" | tr -d '\r' | awk '{print $2}' | head -n 1)"
  if [[ "$reset" =~ ^[0-9]+$ ]]; then
    now="$(date +%s)"
    delta=$(( reset - now ))
    [ "$delta" -lt 1 ] && delta=1
    [ "$delta" -gt 120 ] && delta=120
    echo "$delta"; return
  fi
  echo 30
}

# huluic_request <path> [markdown|json] [retried]
# 成功：响应体 → stdout，返回 0
# 404：静默返回 EX_NOTFOUND（由调用方决定兜底策略，如 part.sh 的搜索跟随）
# 其他失败：错误信封 → stdout，诊断 → stderr，返回对应退出码
huluic_request() {
  local path="$1" fmt="${2:-markdown}" retried="${3:-0}"
  local accept="text/markdown"
  [ "$fmt" = "json" ] && accept="application/json"

  local -a args=(
    -sS -L --max-time 90
    -D "$HULUIC_TMP_HDR" -o "$HULUIC_TMP_BODY" -w '%{http_code}'
    -H "Accept: $accept"
    -H "User-Agent: hulu-skill/1.0 (+https://huluic.cn/developer)"
  )
  if [ -n "${HULUIC_KEY:-}" ]; then
    args+=( -H "Authorization: Bearer ${HULUIC_KEY}" )
  fi

  local status
  if ! status="$(curl "${args[@]}" "${HULUIC_API_BASE}${path}")"; then
    log "网络错误 / network error: curl 调用失败（检查网络或 HULUIC_API_BASE=$HULUIC_API_BASE）。"
    return "$EX_HTTP"
  fi

  case "$status" in
    2*)
      cat "$HULUIC_TMP_BODY"
      return 0
      ;;
    401)
      cat "$HULUIC_TMP_BODY"
      log ""
      log "401 未授权 / unauthorized: API Key 无效或已吊销。请检查 HULUIC_KEY（申请: https://huluic.cn/developer）。"
      return "$EX_AUTH"
      ;;
    403)
      cat "$HULUIC_TMP_BODY"
      log ""
      log "403 禁止 / forbidden: 该端点匿名不可用或 Key 权限不足（offers / offer-format 需配置 HULUIC_KEY）。"
      return "$EX_AUTH"
      ;;
    404)
      return "$EX_NOTFOUND"
      ;;
    429)
      if [ "$retried" = "0" ]; then
        local wait
        wait="$(retry_after_seconds "$HULUIC_TMP_HDR")"
        log "429 限流 / rate limited，${wait}s 后自动重试一次…"
        sleep "$wait"
        huluic_request "$path" "$fmt" 1
        return $?
      fi
      cat "$HULUIC_TMP_BODY"
      log ""
      log "429 限流 / rate limited（已自动重试一次仍被限流）。请稍后再试，勿循环调用。"
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
