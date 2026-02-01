#!/bin/bash

# =========================================================
# 脚本名称: VPS 运维工具箱 V5.2 (Lucky 轻量版)
# 适用环境: Debian 12 / Ubuntu 22+
# 更新日志: 
#   - V5.2: 替换 NPM 为 Lucky (全中文/极低内存/多功能)
#   - V5.1: 修复 WARP 交互卡死 & 智能 SSH 端口检测
#   - V5.0: 集成 DPanel Lite & 目录规范化
# =========================================================

# 基础配置
BASE_DIR="/opt/docker_data"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 检查 root
[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# ---------------------------------------------------------
# 核心功能模块
# ---------------------------------------------------------

# 1. 安装 DPanel (轻量级 Docker 管理器)
function install_dpanel() {
    echo -e "${GREEN}> 正在部署 DPanel (Lite版)...${PLAIN}"
    
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}错误: 请先运行选项 [2] 安装 Docker！${PLAIN}"; return;
    fi

    WORK_DIR="$BASE_DIR/dpanel"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

    # 生成配置文件
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
    docker compose up -d

    # 配置防火墙
    if command -v ufw >/dev/null 2>&1; then 
        ufw allow 8888/tcp comment 'DPanel'
    fi

    echo -e "${GREEN}>>> DPanel 部署成功！${PLAIN}"
    echo -e "访问地址: http://$(curl -s ifconfig.me):8888"
    echo -e "默认账号: admin"
    echo -e "默认密码: admin"
    echo -e "${YELLOW}警告: 请登录后立即修改密码！${PLAIN}"
}

# 2. 系统初始化
function system_init() {
    echo -e "${GREEN}> 系统初始化...${PLAIN}"
    # 增加安装 lsof 用于端口检测
    apt update -y && apt install -y curl wget git htop vim unzip socat tar gnupg lsb-release lsof
    timedatectl set-timezone Asia/Shanghai
    
    # BBR
    if ! grep -q "bbr" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi
    
    # Swap
    MemTotal=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    if [[ $MemTotal -lt 2097152 ]]; then
        if [ ! -f /swapfile ]; then fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
    fi
    echo -e "${GREEN}初始化完成 (BBR+Swap+时区)${PLAIN}"
}

# 3. Docker 安装
function install_docker() {
    echo -e "${GREEN}> 安装 Docker...${PLAIN}"
    if ! command -v docker >/dev/null 2>&1; then 
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker
        systemctl start docker
    fi
    # 依然添加别名以防万一
    if ! command -v docker-compose >/dev/null 2>&1; then 
        echo -e '#!/bin/bash\ndocker compose "$@"' > /usr/local/bin/docker-compose 
        chmod +x /usr/local/bin/docker-compose
    fi
    echo -e "${GREEN}Docker 准备就绪${PLAIN}"
}

# 4. 安装 Lucky (轻量级中文反代神器)
function install_lucky() {
    echo -e "${GREEN}> 正在部署 Lucky (轻量中文反代)...${PLAIN}"
    if ! command -v docker >/dev/null 2>&1; then echo -e "${RED}请先安装 Docker！${PLAIN}"; return; fi
    
    WORK_DIR="$BASE_DIR/lucky"
    mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
    
    # Lucky 使用 host 模式性能最好，且方便管理端口
    cat > docker-compose.yml <<EOF
version: '3'
services:
  lucky:
    image: gdysthen/lucky:latest
    container_name: lucky
    restart: always
    network_mode: host
    volumes:
      - ./conf:/goodluck
EOF

    echo -e "${GREEN}正在启动 Lucky...${PLAIN}"
    docker compose up -d

    # 配置防火墙 (开放 16601 管理口，以及 80/443 web口)
    if command -v ufw >/dev/null 2>&1; then 
        ufw allow 16601/tcp comment 'Lucky Panel'
        ufw allow 80/tcp comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
    fi

    echo -e "${GREEN}>>> Lucky 部署成功！${PLAIN}"
    echo -e "访问地址: http://$(curl -s ifconfig.me):16601"
    echo -e "默认账号: 666"
    echo -e "默认密码: 666"
    echo -e "${YELLOW}警告: 这是一个超级强大的工具，请登录后务必修改密码！${PLAIN}"
}

# 5. WARP 安装
function install_warp() {
    echo -e "${GREEN}> 安装/修复 WARP...${PLAIN}"
    rm -f /etc/apt/sources.list.d/cloudflare-client.list
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    
    apt update -y && apt install -y cloudflare-warp
    
    # 修复：增加 echo "y" 避免交互卡死
    warp-cli registration delete >/dev/null 2>&1 
    echo "y" | warp-cli registration new
    
    warp-cli mode proxy
    warp-cli proxy port 40000
    warp-cli connect
    
    # 解决回环问题
    ip link set lo up
    iptables -I INPUT -i lo -j ACCEPT
    iptables -I OUTPUT -o lo -j ACCEPT
    
    echo -e "${GREEN}WARP SOCKS5 代理已启动: 端口 40000${PLAIN}"
}

# 6. 安全加固 (智能版)
function install_security() {
    echo -e "${GREEN}> 安全加固 (防火墙 & 防爆破)...${PLAIN}"
    apt install -y fail2ban ufw lsof
    
    # --- 智能检测 SSH 端口 ---
    # 获取当前 SSHD 正在监听的端口
    SSH_PORT=$(ss -nltp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | head -n 1)
    if [ -z "$SSH_PORT" ]; then SSH_PORT=22; fi
    
    echo -e "${YELLOW}检测到 SSH 端口为: $SSH_PORT (将自动放行)${PLAIN}"
    
    # UFW 配置
    ufw default deny incoming
    ufw default allow outgoing
    
    # 放行端口
    ufw allow "$SSH_PORT"/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow 16601/tcp comment 'Lucky Panel'
    ufw allow 8888/tcp comment 'DPanel' 
    ufw route allow default allow out on docker0
    
    echo "y" | ufw enable
    systemctl enable fail2ban && systemctl start fail2ban
    
    echo -e "${GREEN}安全策略已应用！${PLAIN}"
}

# 7. 运维清理
function ops_cleanup() {
    echo -e "${GREEN}> 清理日志和垃圾文件...${PLAIN}"
    docker system prune -f
    find /var/lib/docker/containers/ -name "*-json.log" -exec truncate -s 0 {} \;
    echo -e "${GREEN}清理完成${PLAIN}"
}

# ---------------------------------------------------------
# 主菜单
# ---------------------------------------------------------
function show_menu() {
    clear
    echo -e "================================================="
    echo -e "   VPS 运维工具箱 V5.2 ${YELLOW}[Lucky 中文版]${PLAIN}"
    echo -e "   存储目录: ${SKYBLUE}$BASE_DIR${PLAIN}"
    echo -e "================================================="
    echo -e "${GREEN}1.${PLAIN} 系统初始化 (BBR/Swap/时区)"
    echo -e "${GREEN}2.${PLAIN} 安装 Docker 环境"
    echo -e "${GREEN}3.${PLAIN} ${SKYBLUE}部署 Lucky (中文反代/端口转发)${PLAIN}"
    echo -e "${GREEN}4.${PLAIN} 安装 WARP (IP隐藏/SOCKS5)"
    echo -e "-------------------------------------------------"
    echo -e "${GREEN}5.${PLAIN} ${SKYBLUE}部署 DPanel (轻量级 Docker管理)${PLAIN}"
    echo -e "${GREEN}6.${PLAIN} 安全加固 (智能防火墙 + Fail2Ban)"
    echo -e "${GREEN}7.${PLAIN} 磁盘/日志清理"
    echo -e "-------------------------------------------------"
    echo -e "${GREEN}0.${PLAIN} 退出"
    echo -e "================================================="
    read -p "请选择: " num

    case "$num" in
        1) system_init ;;
        2) install_docker ;;
        3) install_lucky ;;
        4) install_warp ;;
        5) install_dpanel ;;
        6) install_security ;;
        7) ops_cleanup ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误${PLAIN}" ;;
    esac
    
    echo ""
    read -p "按回车键返回..." 
    show_menu
}

show_menu
