#!/usr/bin/env bash
# install.sh —— hulu skill 一键安装
#
# 用法：
#   一键（远程）: curl -fsSL https://raw.githubusercontent.com/frankljk/hulu-skills/main/install.sh | bash
#   本地（克隆后）: ./install.sh
#
# 默认安装到所有已知 Agent 技能目录（不存在则创建）：
#   ~/.codex/skills/hulu
#   ~/.claude/skills/hulu
# 自定义目标：SKILLS_DIR=/path/to/skills ./install.sh（只装到该目录）

set -euo pipefail

REPO="${HULU_SKILLS_REPO:-frankljk/hulu-skills}"
BRANCH="${HULU_SKILLS_BRANCH:-main}"
SKILL_NAME="hulu"

# ---- 1) 定位 skill 源：本地克隆内执行用本地文件，否则拉远程 tarball ----
SRC_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] \
  && [ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/skills/$SKILL_NAME/SKILL.md" ]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/skills/$SKILL_NAME" && pwd)"
  echo "使用本地源 / using local source: $SRC_DIR"
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  TARBALL="https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH"
  echo "下载 / downloading: $TARBALL"
  curl -fsSL "$TARBALL" -o "$TMP/repo.tar.gz"
  tar -xzf "$TMP/repo.tar.gz" -C "$TMP"
  SRC_DIR="$(find "$TMP" -maxdepth 3 -type d -path "*/skills/$SKILL_NAME" | head -n 1)"
fi

if [ -z "$SRC_DIR" ] || [ ! -f "$SRC_DIR/SKILL.md" ]; then
  echo "错误: 未找到 skill 源 / skill source not found" >&2
  exit 1
fi

install_to() {
  local base="$1"
  mkdir -p "$base"
  rm -rf "${base:?}/$SKILL_NAME"
  mkdir -p "$base/$SKILL_NAME"
  cp -R "$SRC_DIR/." "$base/$SKILL_NAME/"
  chmod +x "$base/$SKILL_NAME/scripts/"*.sh 2>/dev/null || true
  echo "✔ 已安装 / installed: $base/$SKILL_NAME"
}

# ---- 2) 安装到目标目录 ----
if [ -n "${SKILLS_DIR:-}" ]; then
  install_to "$SKILLS_DIR"
else
  install_to "$HOME/.codex/skills"
  install_to "$HOME/.claude/skills"
fi

cat <<'EOF'

安装完成 / Done.

快速验证 / Verify（匿名可用，无需 Key）:
  bash ~/.claude/skills/hulu/scripts/part.sh STM32F103C8T6

报价类端点需要 API Key（https://huluic.cn/developer 申请）:
  export HULUIC_KEY=hulu_sk_...

其他 Agent（Qoder / Cursor / Windsurf 等）:
  将 skills/hulu 目录拷贝到该 Agent 的技能目录即可，SKILL.md 是通用标准格式。
EOF
