#!/bin/sh
# 应用管理：Strata 服务（可按 .env 自动拉起）+ chat-demo 开发服务器。
#
# 用法:
#   ./serve.sh start          起服务（Strata 未跑时按 .env 的 STRATA_MODEL_PATH 拉起，然后起网页）
#   ./serve.sh stop           停网页开发服务器（不动 Strata）
#   ./serve.sh restart        重启网页开发服务器
#   ./serve.sh status         两个服务的状态 + 补丁状态
#   ./serve.sh logs           看开发服务器日志
#   ./serve.sh strata-start   只拉起 Strata
#   ./serve.sh strata-stop    停掉 Strata（释放显存）
#
# 配置在 .env（从 .env.example 复制），环境变量优先。
set -eu
cd "$(dirname "$0")"

# 读 .env（简单 KEY=VALUE；含空格的值加引号）
if [ -f .env ]; then
    set -a
    . ./.env 2>/dev/null || warn ".env 解析失败（含空格的值要加引号），本项配置被忽略"
    set +a
fi
DEV_PORT="${DEV_PORT:-8091}"
STRATA_URL="${STRATA_URL:-http://127.0.0.1:8080}"
WEB_URL="http://localhost:$DEV_PORT"

if [ -z "${STRATA_BIN:-}" ]; then
    if [ -x "$HOME/.local/bin/strata" ]; then
        STRATA_BIN="$HOME/.local/bin/strata"
    else
        STRATA_BIN="strata"
    fi
fi

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m 警告:\033[0m %s\n' "$*"; }

strata_ready() { curl -s --noproxy "*" -o /dev/null --max-time 3 "$STRATA_URL/health"; }
web_ready() { curl -s --noproxy "*" -o /dev/null --max-time 3 "$WEB_URL/"; }
wait_for() { # wait_for URL 次数: 轮询到通或次数用尽
    _url=$1
    _tries=$2
    _i=0
    while ! curl -s --noproxy "*" -o /dev/null --max-time 2 "$_url"; do
        _i=$((_i + 1))
        [ "$_i" -ge "$_tries" ] && return 1
        sleep 1
    done
}

serve_dir() {
    if [ -n "${STRATA_SERVE_DIR:-}" ]; then
        printf '%s' "$STRATA_SERVE_DIR"
        return 0
    fi
    _sd_home="${STRATA_HOME:-$HOME/.local/share/strata}"
    ls -1d "$_sd_home"/terminal/[0-9]*/serve 2>/dev/null | sort -V | tail -1
}

ensure_strata() {
    if strata_ready; then
        say "Strata 已在运行: $STRATA_URL"
        return 0
    fi
    if [ -n "${STRATA_MODEL_PATH:-}" ] && [ -f "${STRATA_MODEL_PATH}" ]; then
        say "拉起 Strata（模型: $STRATA_MODEL_PATH ${STRATA_LAUNCH_ARGS:-}）..."
        # shellcheck disable=SC2086 # STRATA_LAUNCH_ARGS 按空格拆成多个参数
        "$STRATA_BIN" launch --model-path "$STRATA_MODEL_PATH" --yes --no-tui ${STRATA_LAUNCH_ARGS:-}
        if wait_for "$STRATA_URL/health" 300; then
            say "Strata 就绪: $STRATA_URL"
        else
            warn "Strata 启动较慢（首次打包要读全部模型文件），继续往下；稍后用 ./serve.sh status 看"
        fi
    else
        warn "Strata 未运行，且 .env 没配 STRATA_MODEL_PATH；假设你自己管理 Strata"
    fi
}

ensure_web() {
    if web_ready; then
        say "开发服务器已在运行: $WEB_URL"
        return 0
    fi
    if [ ! -d node_modules ]; then
        say "依赖未装，先跑 ./install.sh"
        exit 1
    fi
    say "启动开发服务器（端口 $DEV_PORT）..."
    nohup pnpm dev >.dev-server.log 2>&1 &
    echo $! >.dev-server.pid
    if wait_for "$WEB_URL/" 60; then
        say "开发服务器就绪: $WEB_URL"
    else
        warn "启动失败，看日志: ./serve.sh logs"
        exit 1
    fi
}

check_patch() {
    _d=$(serve_dir)
    if [ -n "$_d" ] && [ -f "$_d/frontend.py" ]; then
        if grep -q native_latest_reminder "$_d/frontend.py"; then
            say "Strata 补丁: 已生效"
        else
            warn "Strata 补丁: 未打（聊天会报 'Unexpected message role.'），跑一次 ./install.sh"
        fi
    else
        warn "Strata 补丁: 没找到 Strata 安装，无法检查"
    fi
}

case "${1:-status}" in
    start)
        ensure_strata
        ensure_web
        say "打开 $WEB_URL （设置里 API Key 随便填，本地服务不校验）"
        ;;
    stop)
        if [ -f .dev-server.pid ]; then
            _pid=$(cat .dev-server.pid)
            if kill "$_pid" 2>/dev/null; then
                say "已停止开发服务器（pid $_pid）"
            else
                say "pid $_pid 已不在（可能之前停过）"
            fi
            rm -f .dev-server.pid
        elif web_ready; then
            warn "开发服务器在运行但没有 pid 记录；手动结束: pkill -f 'rspack serve'"
        else
            say "开发服务器未在运行"
        fi
        ;;
    restart)
        "$0" stop
        "$0" start
        ;;
    status)
        if strata_ready; then
            say "Strata: 运行中 ($STRATA_URL)"
        else
            warn "Strata: 未运行"
        fi
        if web_ready; then
            say "网页:   运行中 ($WEB_URL)"
        else
            warn "网页:   未运行"
        fi
        check_patch
        ;;
    logs)
        [ -f .dev-server.log ] && tail -n 40 -f .dev-server.log || warn "还没有日志（先 ./serve.sh start）"
        ;;
    strata-start)
        ensure_strata
        ;;
    strata-stop)
        "$STRATA_BIN" launch --stop
        ;;
    *)
        echo "用法: ./serve.sh {start|stop|restart|status|logs|strata-start|strata-stop}" >&2
        exit 1
        ;;
esac
