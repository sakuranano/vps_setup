#!/bin/bash

# =========================================================
# 脚本名称: VPS 运维工具箱 V6.0 (状态感知最终版)
# 适用环境: Debian 12 / Ubuntu 22+
# 核心组件: Docker + Lucky + DPanel + WARP + IP.Check + SysInfo
# =========================================================

# 基础配置
BASE_DIR="/opt/docker_data"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

# 检查 root
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# ---------------------------------------------------------
# 辅助函数：状态检测
# ---------------------------------------------------------
function get_app_status() {
    # 1. Docker
    if command -v docker >/dev/null 2>&1; then 
        dock_status="${GREEN}[已安装]${PLAIN}" 
    else 
        dock_status="${RED}[未安装]${PLAIN}" 
    fi
    
    # 2. WARP (检查 40000 端口)
    if ss -nltp | grep -q ":40000"; then 
        warp_status="${GREEN}[运行中]${PLAIN}" 
    else 
        warp_status="${RED}[未启动]${PLAIN}" 
    fi
    
    # 3. Lucky (检查容器)
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^lucky$"; then 
        lucky_status="${GREEN}[运行中]${PLAIN}"
    else 
        lucky_status="${RED}[未安装]${PLAIN}"
    fi
    
    # 4. DPanel (检查容器)
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^dpanel$"; then 
        dp_status="${GREEN}[运行中]${PLAIN}"
    else 
        dp_status="${RED}[未安装]${PLAIN}"
    fi
}

# ---------------------------------------------------------
# 核心功能模块
# ---------------------------------------------------------

# 1. 安装 DPanel
function install_dpanel() {
    echo -e "${GREEN}> 正在部署 DPanel (Lite版)...${PLAIN}"
    if ! command -v docker >/dev/null 2>&1; then echo -e "${RED}请先安装 Docker！${PLAIN}"; return; fi

    WORK_DIR="$BASE_DIR/dpanel"
    mkdir -p "$WORK_DIR" && cd "$WORK_DIR"

    cat > docker-compose.yml <<EOF
version: '3'
services:
  dpanel:
    image: dpanel/dpanel:lite
    container_name: dpanel
    restart: unless-stopped
    ports:
      - "8888:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/dpanel
    environment:
      - APP_NAME=DPanel
EOF
    echo -e "${GREEN}正在启动 DPanel...${PLAIN}"
    if ! docker compose up -d; then echo -e "${RED}启动失败！${PLAIN}"; return; fi
    if command -v ufw >/dev/null 2>&1; then ufw allow 8888/tcp comment 'DPanel'; fi
    echo -e "${GREEN}>>> 部署成功！访问: http://$(curl -s ifconfig.me):8888${PLAIN} (默认密码: admin)"
}

# 2. 安装 Lucky
function install_lucky() {
    echo -e "${GREEN}> 正在部署 Lucky (中文反代)...${PLAIN}"
    if ! command -v docker >/dev/null 2>&1; then echo -e "${RED}请先安装 Docker！${PLAIN}"; return; fi
    
    WORK_DIR="$BASE_DIR/lucky"
    mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
    
    cat > docker-compose.yml <<EOF
version: '3'
services:
  lucky:
    image: gdy666/lucky:latest
    container_name: lucky
    restart: always
    network_mode: host
    volumes:
      - ./conf:/goodluck
EOF
    echo -e "${GREEN}正在启动 Lucky...${PLAIN}"
    if ! docker compose up -d; then echo -e "${RED}启动失败！${PLAIN}"; return; fi
    if command -v ufw >/dev/null 2>&1; then 
        ufw allow 16601/tcp comment 'Lucky Panel'; ufw allow 80/tcp comment 'HTTP'; ufw allow 443/tcp comment 'HTTPS'
    fi
    echo -e "${GREEN}>>> 部署成功！访问: http://$(curl -s ifconfig.me):16601${PLAIN} (默认密码: 666)"
}

# 3. 安装 WARP
function install_warp() {
    echo -e "${GREEN}> 安装/修复 WARP...${PLAIN}"
    # 统一依赖检查
    apt update -y && apt install -y curl gnupg lsb-release
    
    rm -f /etc/apt/sources.list.d/cloudflare-client.list
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    
    apt update -y && apt install -y cloudflare-warp
    warp-cli registration delete >/dev/null 2>&1 
    echo "y" | warp-cli registration new
    warp-cli mode proxy; warp-cli proxy port 40000; warp-cli connect
    ip link set lo up; iptables -I INPUT -i lo -j ACCEPT; iptables -I OUTPUT -o lo -j ACCEPT
    echo -e "${GREEN}WARP SOCKS5 代理已启动: 端口 40000${PLAIN}"
}

# ---------------------------------------------------------
# 工具模块
# ---------------------------------------------------------

function check_system_info() {
    clear
    echo -e "=== 系统资源看板 ==="
    # 快速获取无需额外安装
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8"%"}')
    mem_used=$(free -m | awk '/Mem:/ {print $3}')
    mem_total=$(free -m | awk '/Mem:/ {print $2}')
    disk_used=$(df -h / | awk '/\// {print $3}')
    disk_total=$(df -h / | awk '/\// {print $2}')
    tcp_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
    
    echo -e "CPU 使用 : ${SKYBLUE}$cpu_usage${PLAIN}"
    echo -e "内存使用 : ${SKYBLUE}$mem_used / $mem_total MB${PLAIN}"
    echo -e "硬盘使用 : ${SKYBLUE}$disk_used / $disk_total${PLAIN}"
    echo -e "TCP 算法 : ${SKYBLUE}$tcp_cc${PLAIN}"
    echo -e "公网 IP  : ${SKYBLUE}$(curl -s4m 2 ifconfig.me)${PLAIN}"
    echo ""
    read -p "按回车返回..."
}

function check_all_info() {
    echo -e "${GREEN}> 启动全能体检脚本...${PLAIN}"
    apt install -y curl wget jq >/dev/null 2>&1
    echo -e "1. 本机直连  2. WARP代理"
    read -p "选择: " m
    if [[ "$m" == "2" ]]; then export ALL_PROXY=socks5://127.0.0.1:40000; fi
    bash <(curl -Ls IP.Check.Place)
    unset ALL_PROXY
    echo ""; read -p "按回车返回..."
}

function uninstall_app() {
    local app=$1; local dir=$2; local port=$3
    echo -e "${YELLOW}卸载 $app ...${PLAIN}"
    if [ -d "$BASE_DIR/$dir" ]; then
        cd "$BASE_DIR/$dir" && docker compose down >/dev/null 2>&1
        cd .. && rm -rf "$BASE_DIR/$dir"
    fi
    if command -v ufw >/dev/null 2>&1; then ufw delete allow "$port"/tcp >/dev/null 2>&1; fi
    echo -e "${GREEN}>>> $app 已卸载${PLAIN}"
}

function system_init() {
    echo -e "${GREEN}> 系统初始化...${PLAIN}"
    # 统一安装所有依赖
    apt update -y && apt install -y curl wget git htop vim unzip socat tar gnupg lsb-release lsof jq
    timedatectl set-timezone Asia/Shanghai
    if ! grep -q "bbr" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi
    MemTotal=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    if [[ $MemTotal -lt 2097152 ]]; then
        if [ ! -f /swapfile ]; then fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
    fi
    echo -e "${GREEN}初始化完成${PLAIN}"
}

function install_docker() {
    echo -e "${GREEN}> 安装 Docker...${PLAIN}"
    if ! command -v docker >/dev/null 2>&1; then curl -fsSL https://get.docker.com | bash; systemctl enable docker; systemctl start docker; fi
    if ! command -v docker-compose >/dev/null 2>&1; then echo -e '#!/bin/bash\ndocker compose "$@"' > /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose; fi
    echo -e "${GREEN}Docker 环境就绪${PLAIN}"
}

function install_security() {
    echo -e "${GREEN}> 安全加固...${PLAIN}"
    apt install -y fail2ban ufw lsof
    SSH_PORT=$(ss -nltp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | head -n 1)
    if [ -z "$SSH_PORT" ]; then SSH_PORT=22; fi
    ufw default deny incoming; ufw default allow outgoing
    ufw allow "$SSH_PORT"/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'; ufw allow 443/tcp comment 'HTTPS'
    ufw allow 16601/tcp comment 'Lucky'; ufw allow 8888/tcp comment 'DPanel'
    ufw route allow default allow out on docker0
    echo "y" | ufw enable
    systemctl enable fail2ban && systemctl start fail2ban
    echo -e "${GREEN}安全策略已应用${PLAIN}"
}

function ops_cleanup() {
    docker system prune -f
    find /var/lib/docker/containers/ -name "*-json.log" -exec truncate -s 0 {} \;
    echo -e "${GREEN}清理完成${PLAIN}"
}

# ---------------------------------------------------------
# 菜单逻辑
# ---------------------------------------------------------

function show_uninstall_menu() {
    clear
    echo -e "================================================="
    echo -e "   应用卸载管理 ${RED}[危险]${PLAIN}"
    echo -e "================================================="
    echo -e "1. 卸载 Lucky"
    echo -e "2. 卸载 DPanel"
    echo -e "0. 返回"
    read -p "选择: " u
    case "$u" in
        1) uninstall_app "Lucky" "lucky" "16601" ;;
        2) uninstall_app "DPanel" "dpanel" "8888" ;;
        0) show_menu ;;
        *) show_uninstall_menu ;;
    esac
    if [[ "$u" != "0" ]]; then read -p "按回车继续..." && show_uninstall_menu; fi
}

function show_menu() {
    get_app_status # 刷新状态
    clear
    echo -e "================================================="
    echo -e "   VPS 运维工具箱 V6.0 ${YELLOW}[Final Stable]${PLAIN}"
    echo -e "   存储: ${SKYBLUE}$BASE_DIR${PLAIN}"
    echo -e "================================================="
    echo -e "${GREEN}1.${PLAIN} 系统初始化 (BBR/Swap/依赖) ${YELLOW}*建议首选*${PLAIN}"
    echo -e "${GREEN}2.${PLAIN} 安装 Docker 环境  $dock_status"
    echo -e "${GREEN}3.${PLAIN} 安装 WARP 代理    $warp_status"
    echo -e "-------------------------------------------------"
    echo -e "${GREEN}4.${PLAIN} ${SKYBLUE}部署 Lucky 反代${PLAIN}   $lucky_status"
    echo -e "${GREEN}5.${PLAIN} ${SKYBLUE}部署 DPanel 面板${PLAIN}  $dp_status"
    echo -e "-------------------------------------------------"
    echo -e "${GREEN}6.${PLAIN} 查看本机配置 (轻量看板)"
    echo -e "${GREEN}7.${PLAIN} 全能 IP 体检 (解锁/欺诈分)"
    echo -e "-------------------------------------------------"
    echo -e "${GREEN}8.${PLAIN} 安全加固 (防火墙/Fail2Ban)"
    echo -e "${GREEN}9.${PLAIN} 磁盘/日志清理"
    echo -e "${GREEN}10.${PLAIN} ${RED}卸载应用 ->${PLAIN}"
    echo -e "================================================="
    echo -e "${GREEN}0.${PLAIN} 退出"
    echo -e "================================================="
    read -p "请选择: " num
    case "$num" in
        1) system_init ;;
        2) install_docker ;;
        3) install_warp ;;
        4) install_lucky ;;
        5) install_dpanel ;;
        6) check_system_info ;;
        7) check_all_info ;;
        8) install_security ;;
        9) ops_cleanup ;;
        10) show_uninstall_menu ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误${PLAIN}" ;;
    esac
    echo ""
    read -p "按回车键返回..." 
    show_menu
}

show_menu
