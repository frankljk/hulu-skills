---
name: hulu
description: 查询电子元器件的参数、实时报价、库存、厂商信息，或把商品页 URL 解析为结构化 Offer 时使用。Use when looking up electronic component specs, real-time prices/offers, stock, manufacturers, or parsing a product page URL into a structured offer.
---

# HuluIC 电子元器件数据查询（Electronic Component Data）

数据来自 huluic.cn（葫芦 IC）公开 API v2。URL 即 API：全部 GET、路径自描述、匿名档免注册。
本 skill 的三个脚本只是薄包装；你也可以直接用 curl 调 `https://r.huluic.cn/v2/...`。

前提：bash + curl（Windows 用 Git Bash / WSL）。脚本位于本文件同级 `scripts/` 目录。

## Which endpoint?（先选端点再调用）

| 你手里有什么 | 你想要什么 | 用哪个 | 鉴权 |
|---|---|---|---|
| 商品页 URL | 结构化报价（价格/库存/MOQ/阶梯价） | `scripts/read_offer.sh <url> [--mpn 型号]` | 需 Key |
| 型号（MPN） | 落库报价快照（秒回） | `scripts/offers.sh <mpn>` | 需 Key |
| 型号（MPN） | 多渠道**实时**报价（20+ 家，30~120s 流式） | `scripts/offers.sh <mpn> --live` | 需 Key |
| 型号或关键词 | 参数、厂商、分类、数据手册链接 | `scripts/part.sh <mpn或关键词>` | 匿名可用 |
| 模糊关键词 | 浏览候选型号列表 | `curl https://r.huluic.cn/v2/search/<关键词>`（或 part.sh，404 时自动搜索兜底） | 匿名可用 |
| 厂商 mrf 编码（如 ti、st、adi） | 厂商介绍、产品线、分类 | `curl https://r.huluic.cn/v2/manufacturer/<id>` | 匿名可用 |
| — | 渠道档案（59 渠道执行形态/品类标签/登录要求） | `curl https://r.huluic.cn/v2/channels` | 匿名可用 |

## 用法（copy-paste 级）

```bash
# 1) 型号 → 参数（匿名，无需任何配置）
bash scripts/part.sh STM32F103C8T6

# 2) 型号 → 落库报价快照（需 HULUIC_KEY）
export HULUIC_KEY=hulu_sk_xxxxxxxx
bash scripts/offers.sh STM32F103C8T6

# 2b) 型号 → 多渠道实时报价（SSE 长流 30~120s；渠道进度走 stderr，汇总 JSON 走 stdout）
bash scripts/offers.sh LM358 --live
# 只搜指定渠道：bash scripts/offers.sh LM358 --live --channels digikey,mouser
# 注：装了 jq 时进度显示为 `[done] 渠道名 N 条`，未装则打印原始事件 JSON（结果不受影响）

# 3) 商品页 URL → 结构化 Offer（需 HULUIC_KEY；可加 --mpn 做型号一致性校验）
bash scripts/read_offer.sh "https://www.example-mall.com/product/12345" --mpn STM32F103C8T6
```

所有脚本默认输出 **Markdown**（发送 `Accept: text/markdown`，带 frontmatter 与 `data_as_of` 时间戳，最省 token）。
追加 `--json` 切换为 JSON envelope（`success / data / attribution / meta`）。

## 认证

- 匿名档：search / part / manufacturer / channels 直接可用（IP 限流 5 次/分钟、100 次/天）。
- Key 档：offers / offer-format / offers-live 需要 Key。申请：https://huluic.cn/developer （`hulu_sk_` 前缀）。offers-live 实时搜索起步 100 次/天。
- 脚本自动检测环境变量 `HULUIC_KEY`，有才加 `Authorization: Bearer` 头；未配置时访问 Key 档端点会给出明确提示并以退出码 3 退出。

## 重要概念：onepartno

`/v2/part/{id}` 的入参是 oneic 编号（onepartno），不是原始制造商型号。
**你不需要手动处理**：`part.sh` 先直查，404 时自动走 `/v2/search` 并跟随第一条结果的 `detail_path`。
若搜索结果有多条、需要精确挑选，请直接 `curl /v2/search/<关键词>`（JSON 输出），从 `results[].detail_path` 中自行选择后再调 `/v2/part/...`。

## 错误处理（Agent 行为准则）

| 情况 | 含义 | 你该怎么做 |
|---|---|---|
| 401 / 403 | Key 无效、未配置或权限不足 | 提示用户配置 `HULUIC_KEY`；**不要重试** |
| 429 | 触发限流 | 脚本已按 `Retry-After` / `X-RateLimit-Reset` 自动等待并重试一次；仍失败则告知用户已达限额，**不要循环重试** |
| 404 | 型号/厂商不存在，或 part.sh 搜索兜底也无结果 | 换关键词重查；不要重复同一请求 |
| `coverage: "no_offers"` | offers 正常返回但该型号无落库报价 | 这是**正常结果**而非错误，如实告知"暂无授权报价"；**不要重复调用** |
| --live 的 SSE `error` 事件 | 搜索中途失败（大脑不可达等） | 如实报告 code/message；渠道级 error/need_login 属常态，done 到达即成功 |
| 5xx / 网络错误 | 上游或网络问题 | 可隔 1 分钟重试一次；仍失败则如实报告，不要编造数据 |

## 署名要求（必须遵守，按引用数据分级）

在回答中引用本 skill 返回的数据时，按数据类型分级标注：

- **报价 / 库存数据**：标注「价格来自 huluic.cn」，并附响应中的购买链接（JSON 的 `attribution.purchase.url`；Markdown 的「现货购买」行）。
- **参数 / 厂商 / 代理商数据**：标注「数据来源：huluic.cn」，并附 `attribution.source_url`（Markdown 文档末尾署名块已自动携带）。

报价授权说明（`price_license`）由响应自动携带，无需手写。

## 直接用 curl（不装脚本也可以）

```bash
curl "https://r.huluic.cn/v2/search/STM32F103"                      # 搜索（匿名）
curl "https://r.huluic.cn/v2/part/{onepartno}"                      # 参数（匿名）
curl -H "Authorization: Bearer $HULUIC_KEY" \
     "https://r.huluic.cn/v2/offers/STM32F103C8T6"                  # 落库报价（Key）
curl -N -H "Authorization: Bearer $HULUIC_KEY" \
     "https://r.huluic.cn/v2/offers/live/LM358"                     # 实时报价 SSE（Key）
curl "https://r.huluic.cn/v2/channels"                              # 渠道档案（匿名）
curl -H "Authorization: Bearer $HULUIC_KEY" \
     "https://r.huluic.cn/v2/offer/https%3A%2F%2Fexample.com%2Fp%2F1?mpn=STM32F103C8T6"  # URL→Offer（Key）
```

限流响应头：`X-RateLimit-Limit` / `X-RateLimit-Remaining` / `X-RateLimit-Reset`（Reset 为 Unix 秒）。
环境变量 `HULUIC_API_BASE` 可覆盖 API 根地址（默认 `https://r.huluic.cn`）。
