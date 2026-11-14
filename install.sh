#!/bin/sh
# 安装本项目的本地环境：
#   1. 检查 Node.js（>= 22.12）与 pnpm
#   2. pnpm install 装依赖
#   3. 生成 .env（不存在时从 .env.example 复制）
#   4. 给 Strata 的 serve/frontend.py 打 latest_reminder 兼容补丁
#      （没有这个补丁，聊天会报 'Unexpected message role.'；幂等，已打则跳过）
#
# 用法:
#   ./install.sh                     常规安装
#   ./install.sh --strata-home DIR   Strata 装在别处时指定根目录（找 terminal/*/serve）
#   ./install.sh --skip-strata       跳过 Strata 补丁
# 环境变量 STRATA_SERVE_DIR 直接指定 serve 目录，优先于自动探测。
set -eu
cd "$(dirname "$0")"

STRATA_HOME="${STRATA_HOME:-$HOME/.local/share/strata}"
SKIP_STRATA=0
while [ $# -gt 0 ]; do
    case "$1" in
        --strata-home) STRATA_HOME="$2"; shift 2 ;;
        --skip-strata) SKIP_STRATA=1; shift ;;
        *) echo "未知参数: $1（可用 --strata-home DIR / --skip-strata）" >&2; exit 1 ;;
    esac
done

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m 警告:\033[0m %s\n' "$*"; }

# 1. 前置工具
if ! command -v node >/dev/null 2>&1; then
    echo "缺 Node.js（需要 22.12+）：https://nodejs.org 或 nvm" >&2
    exit 1
fi
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
if [ "$NODE_MAJOR" -lt 22 ]; then
    warn "Node 版本 $(node -v) 低于上游要求的 22.12，构建工具链可能不工作"
fi
if ! command -v pnpm >/dev/null 2>&1; then
    warn "缺 pnpm，尝试 corepack enable（新开终端后生效）"
    corepack enable 2>/dev/null || {
        echo "请先安装 pnpm: npm install -g pnpm" >&2
        exit 1
    }
fi
if ! command -v python3 >/dev/null 2>&1; then
    warn "缺 python3，Strata 补丁这一步会跳过（聊天会报 'Unexpected message role.'）"
fi

# 2. 依赖
say "安装前端依赖（pnpm install）"
pnpm install

# 3. .env
if [ ! -f .env ]; then
    cp .env.example .env
    say "已从 .env.example 生成 .env，按需修改（模型路径等）"
else
    say ".env 已存在，跳过"
fi

# 4. Strata 补丁
if [ "$SKIP_STRATA" = "1" ]; then
    say "跳过 Strata 补丁（--skip-strata）"
elif ! command -v python3 >/dev/null 2>&1; then
    warn "没有 python3，补丁未打；之后补上 python3 再跑一次 ./install.sh 即可"
else
    SERVE_DIR="${STRATA_SERVE_DIR:-}"
    if [ -z "$SERVE_DIR" ]; then
        SERVE_DIR=$(ls -1d "$STRATA_HOME"/terminal/[0-9]*/serve 2>/dev/null | sort -V | tail -1)
    fi
    if [ -z "$SERVE_DIR" ] || [ ! -f "$SERVE_DIR/frontend.py" ]; then
        warn "没找到 Strata 的 serve 目录（探测过 $STRATA_HOME/terminal/版本号/serve）。"
        warn "Strata 装在别处时: ./install.sh --strata-home /path/to/strata，或 STRATA_SERVE_DIR=路径 ./install.sh"
        warn "补丁未打。不打的后果：聊天报 'Unexpected message role.'"
    else
        say "检查 Strata 补丁: $SERVE_DIR/frontend.py"
        if python3 patches/patch_strata_frontend.py "$SERVE_DIR" --check; then
            say "补丁已生效"
        else
            python3 patches/patch_strata_frontend.py "$SERVE_DIR"
            say "补丁已写入。正在运行的 Strata 服务要重启才生效: strata launch --stop 后重新启动"
        fi
    fi
fi

say "完成。启动: ./serve.sh start    状态: ./serve.sh status    停止: ./serve.sh stop"
