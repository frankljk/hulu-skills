# hulu-skills

让 AI Agent（Codex / Claude Code / Qoder 等）"天生会查" huluic.cn 的电子元器件数据：
型号参数、实时报价、库存、厂商信息，以及把任意商品页 URL 解析为结构化 Offer。

底层是 huluic.cn 公开 API v2（`https://r.huluic.cn`）——**URL 即 API**，全部 GET，匿名档免注册：

```bash
# 不用装任何东西，现在就能跑（匿名档）
curl "https://r.huluic.cn/v2/search/STM32F103"
curl -H "Accept: text/markdown" "https://r.huluic.cn/v2/part/{onepartno}"
```

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/frankljk/hulu-skills/main/install.sh | bash
```

默认安装到 `~/.codex/skills/hulu` 和 `~/.claude/skills/hulu`（目录不存在会自动创建）。

### 手动安装

```bash
git clone https://github.com/frankljk/hulu-skills.git
cd hulu-skills
./install.sh                      # 或：SKILLS_DIR=/path/to/skills ./install.sh
```

其他 Agent：把 `skills/hulu/` 整个目录拷到对应技能目录即可（SKILL.md 是通用标准格式）。
Windows 用户请在 Git Bash 或 WSL 中运行。

## 使用

安装后 Agent 会自动识别；也可手动调用脚本：

```bash
# 型号 → 参数 / 厂商 / 分类 / 数据手册（匿名可用）
bash skills/hulu/scripts/part.sh STM32F103C8T6

# 型号 → 实时报价（需 Key）
export HULUIC_KEY=hulu_sk_xxxxxxxx        # 申请: https://huluic.cn/developer
bash skills/hulu/scripts/offers.sh STM32F103C8T6

# 商品页 URL → 结构化 Offer（需 Key）
bash skills/hulu/scripts/read_offer.sh "https://www.example-mall.com/product/12345" --mpn STM32F103C8T6
```

- 所有脚本默认输出 **Markdown**（Agent 读取最省 token）；加 `--json` 切 JSON。
- 零依赖：只用到 `bash` + `curl`（不要求 jq）。
- 429 限流时脚本按 `Retry-After` / `X-RateLimit-Reset` 自动等待并重试一次。
- 环境变量：`HULUIC_KEY`（API Key）、`HULUIC_API_BASE`（默认 `https://r.huluic.cn`）。

## 不想装？用 MCP

同一个数据面还有一个 Remote MCP Server（Streamable HTTP，无状态）——填一个 URL 即可，零安装：

```
https://r.huluic.cn/mcp
```

5 个工具与 v2 端点一一对应：`search_parts` / `get_part` / `get_manufacturer`（匿名可用）、`get_offers` / `read_offer_url`（需 Key，在客户端配置里带 `Authorization: Bearer hulu_sk_...` 头）。

<details>
<summary>Claude Desktop（Settings → Connectors → Add custom connector）</summary>

```json
{
  "mcpServers": {
    "huluic": {
      "type": "http",
      "url": "https://r.huluic.cn/mcp"
    }
  }
}
```

需 Key 的工具：在 connector 配置里添加请求头 `Authorization: Bearer hulu_sk_...`。

</details>

<details>
<summary>Codex CLI（~/.codex/config.toml）</summary>

```toml
[mcp_servers.huluic]
url = "https://r.huluic.cn/mcp"

# 需要 Key 的工具时取消注释：
# [mcp_servers.huluic.http_headers]
# Authorization = "Bearer hulu_sk_xxxxxxxx"
```

</details>

<details>
<summary>Cursor（Settings → MCP → Add new global MCP server）</summary>

```json
{
  "mcpServers": {
    "huluic": {
      "url": "https://r.huluic.cn/mcp"
    }
  }
}
```

</details>

## 仓库结构

```
hulu-skills/
  README.md
  install.sh                      # 一键/手动安装
  skills/hulu/
    SKILL.md                      # Agent 入口：触发词、端点决策表、错误处理准则、署名要求
    scripts/
      common.sh                   # 共享层：鉴权头 / Accept 协商 / 429 重试 / urlencode
      part.sh                     # 型号 → 参数（匿名，404 自动搜索兜底）
      offers.sh                   # 型号 → 实时报价（需 Key）
      read_offer.sh               # URL → 结构化 Offer（需 Key）
  .github/workflows/smoke.yml     # 每周冒烟：验证示例 MPN 与匿名端点可用
```

## 维护

- `.github/workflows/smoke.yml` 每周一自动跑匿名档冒烟（part/search），失败自动开 issue——死示例比没示例更伤信誉。
- 示例 MPN（`STM32F103C8T6`）选用有真实数据的型号；换示例时先确认有数据。

## License

MIT（详见 LICENSE）。数据使用请遵循 https://huluic.cn/developer 的条款；引用数据请标注 "数据来源：huluic.cn"。
