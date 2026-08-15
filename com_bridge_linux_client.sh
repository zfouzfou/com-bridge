#!/bin/bash
# =============================================
#  COM Bridge — WSL 端：创建虚拟 tty 连接 Windows 桥
#  用法:  sudo ./wsl.sh [start|stop|status|install]
#  默认:  TCP 端口 12345
# =============================================

set -e

TTY_DEV="/dev/ttyVIRTUAL"
PID_FILE="/tmp/wsl_com_bridge.pid"

# ── 自动检测 Windows 主机 IP ─────────────────────
detect_windows_ip() {
    local ip
    ip=$(ip route show default 2>/dev/null | awk '{print $3}')
    if [ -n "$ip" ] && [ "$ip" != "0.0.0.0" ]; then
        echo "$ip"
        return 0
    fi
    ip=$(grep -m1 nameserver /etc/resolv.conf 2>/dev/null | awk '{print $2}')
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    echo "ERROR"
    return 1
}

WINDOWS_HOST=$(detect_windows_ip)
if [ "$WINDOWS_HOST" = "ERROR" ]; then
    echo "❌ 无法检测 Windows 主机 IP"
    echo "   请手动设置: export WINDOWS_HOST=192.168.x.x"
    exit 1
fi

# ── 功能函数 ──────────────────────────────────────

install_deps() {
    echo "📦 安装 WSL 依赖..."
    apt-get update -qq
    apt-get install -y -qq socat
    echo "✅ socat 已安装"
    socat -V | head -1
}

start() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "⚠️  桥接已在运行 (PID $(cat "$PID_FILE"))"
        echo "   先停止: sudo $0 stop"
        return 0
    fi

    rm -f "$TTY_DEV"

    echo "🔗  创建虚拟 tty: $TTY_DEV → $WINDOWS_HOST:$TCP_PORT"
    echo ""

    # 测试 Windows 端是否可达
    if timeout 2 bash -c "echo > /dev/tcp/$WINDOWS_HOST/$TCP_PORT" 2>/dev/null; then
        echo "✅  Windows 桥接就绪"
    else
        echo "⚠️  Windows 桥接端口 $TCP_PORT 不可达（启动后自动重连）"
        echo ""
    fi

    # setsid 脱离终端，forever+interval 自动重连
    setsid socat \
        pty,link="$TTY_DEV",raw,echo=0,mode=666 \
        tcp:"$WINDOWS_HOST:$TCP_PORT",forever,interval=2 \
        </dev/null >/dev/null 2>&1 &

    SOCAT_PID=$!
    echo "$SOCAT_PID" > "$PID_FILE"

    sleep 1
    if [ -e "$TTY_DEV" ]; then
        echo ""
        echo "✅ 就绪！"
        echo "   打开串口:  picocom -b 115200 $TTY_DEV"
        echo "   停止:      sudo $0 stop"
        echo "   状态:      sudo $0 status"
    else
        echo "⚠️  设备文件暂未创建，Windows 桥接启动后自动连接"
    fi
}

stop() {
    if [ -f "$PID_FILE" ]; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    pkill -f "socat.*$TTY_DEV" 2>/dev/null || true
    rm -f "$TTY_DEV"
    echo "🛑 已停止"
}

status() {
    echo "━━━ COM Bridge 状态 ━━━━━━━━━━━━━━━━━"
    echo "WSL → Windows:  $WINDOWS_HOST:$TCP_PORT"
    echo "虚拟串口:       $TTY_DEV"
    echo ""

    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        echo "🟢 桥接: 运行中 (PID $(cat "$PID_FILE"))"
    else
        echo "🔴 桥接: 未运行"
    fi

    if [ -e "$TTY_DEV" ]; then
        echo "🟢 设备: 存在"
    else
        echo "🔴 设备: 不存在"
    fi

    if timeout 2 bash -c "echo > /dev/tcp/$WINDOWS_HOST/$TCP_PORT" 2>/dev/null; then
        echo "🟢 TCP:  可连接"
    else
        echo "🔴 TCP:  不可达（Windows 端未启动？）"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── 主入口 ────────────────────────────────────────

if [ "$EUID" -ne 0 ]; then
    echo "请以 sudo 运行: sudo $0 [命令] [TCP端口]"
    exit 1
fi

TCP_PORT="${2:-12345}"

case "${1:-start}" in
    install) install_deps ;;
    start)   start ;;
    stop)    stop ;;
    status)  status ;;
    restart) stop; sleep 1; start ;;
    *)
        basename="$(basename "$0")"
        echo "COM Bridge — WSL 端"
        echo ""
        echo "用法:  sudo ./$basename [命令] [TCP端口]"
        echo ""
        echo "命令:"
        echo "  start           启动桥接（默认）"
        echo "  stop            停止"
        echo "  status          查看状态"
        echo "  restart         重启"
        echo "  install         安装 socat 依赖"
        echo ""
        echo "示例:"
        echo "  sudo ./$basename start          # 默认 TCP :12345"
        echo "  sudo ./$basename start 12346    # 指定端口"
        echo "  sudo ./$basename status"
        echo "  sudo ./$basename stop"
        echo ""
        echo "💡 COM 口和波特率在 Windows 端配置（com_bridge_win_server.bat COM4 115200）"
        echo "   WSL 端无需关心这些参数"
        exit 1
        ;;
esac