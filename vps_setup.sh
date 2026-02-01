#!/bin/bash

# =========================================================
# 脚本名称: VPS 运维工具箱 V5.3 (应用全生命周期管理版)
# 适用环境: Debian 12 / Ubuntu 22+
# 更新日志: 
#   - V5.3: 修复 Lucky 镜像地址 (gdysthen -> gdy666)
#   - V5.3: 新增 [应用卸载/删除] 专属子菜单
#   - V5.3: 增加 Docker 运行状态检测，防止假死
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
# 安装类功能模块
# ---------------------------------------------------------

# 1. 安装 DPanel
function install_dpanel() {
    echo -e "${GREEN}> 正在部署 DPanel (Lite版)...${PLAIN}"
    if ! command -v docker >/dev/null 2>&1; then echo -e "${RED}请先安装 Docker！${PLAIN}"; return; fi

    WORK_DIR="$BASE_DIR/dpanel"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"

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

    echo -e "${GREEN}正在启动容器...${PLAIN}"
    # 增加错误检测，如果启动失败则停止
    if ! docker compose up -d; then
        echo -e "${RED}启动失败！请检查 Docker 服务或网络连接。${PLAIN}"
        return
    fi

    if command -v ufw >/dev/null 2>&1; then ufw allow 8888/tcp comment 'DPanel'; fi

    echo -e "${GREEN}>>> DPanel 部署成功！${PLAIN}"
    echo -e "访问地址: http://$(curl -s ifconfig.me):8888"
    echo -e "默认账号: admin | 密码: admin"
    echo -e "${YELLOW}请立即修改默认密码！${PLAIN}"
}

# 2. 安装 Lucky (修复镜像版)
function install_lucky() {
    echo -e "${GREEN}> 正在部署 Lucky (轻量中文反代)...${PLAIN}"
    if ! command -v docker >/dev/null 2>&1; then echo -e "${RED}请先安装 Docker！${PLAIN}"; return; fi
    
    WORK_DIR="$BASE_DIR/lucky"
    mkdir -p "$WORK_DIR" && cd "$WORK_DIR"
    
    # 修正：使用官方新镜像 gdy666/lucky
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

    echo -e "${GREEN}正在拉取镜像并启动...${PLAIN}"
    if ! docker compose up -d; then
        echo -e "${RED}启动失败！可能原因：Docker 未运行或镜像拉取超时。${PLAIN}"
        return
    fi

    if command -v ufw >/dev/null 2>&1; then 
        ufw allow 16601/tcp comment 'Lucky Panel'
        ufw allow 80/tcp comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
    fi

    echo -e "${GREEN}>>> Lucky 部署成功！${PLAIN}"
    echo -e "访问地址: http://$(curl -s ifconfig.me):16601"
    echo -e "默认账号: 666 | 密码: 666"
}

# 3. 安装 WARP
function install_warp() {
    echo -e "${GREEN}> 安装/修复 WARP...${PLAIN}"
    rm -f /etc/apt/sources.list.d/cloudflare-client.list
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ bookworm main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    
    apt update -y && apt install -y cloudflare-warp
    
    warp-cli registration delete >/dev/null 2>&1 
    echo "y" | warp-cli registration new
    warp-cli mode proxy
    warp-cli proxy port 40000
    warp-cli connect
    
    ip link set lo up
    iptables -I INPUT -i lo -j ACCEPT
    iptables -I OUTPUT -o lo -j ACCEPT
    
    echo -e "${GREEN}WARP SOCKS5 代理已启动: 端口 40000${PLAIN}"
}

# ---------------------------------------------------------
# 卸载类功能模块 (新增)
# ---------------------------------------------------------

# 卸载通用函数
function uninstall_app() {
    local app_name=$1
    local dir_name=$2
    local port=$3
    
    echo -e "${YELLOW}正在卸载 $app_name ...${PLAIN}"
    
    if [ -d "$BASE_DIR/$dir_name" ]; then
        cd "$BASE_DIR/$dir_name"
        # 尝试停止容器
        docker compose down >/dev/null 2>&1
        cd ..
        # 删除文件
        rm -rf "$BASE_DIR/$dir_name"
        echo -e "${GREEN}数据目录已删除。${PLAIN}"
    else
        echo -e "${YELLOW}目录不存在，跳过文件清理。${PLAIN}"
    fi

    # 清理防火墙
    if command -v ufw >/dev/null 2>&1; then
        if [ ! -z "$port" ]; then
            ufw delete allow "$port"/tcp >/dev/null 2>&1
            echo -e "${GREEN}防火墙端口 $port 已关闭。${PLAIN}"
        fi
    fi
    
    echo -e "${GREEN}>>> $app_name 卸载完成！${PLAIN}"
}

# ---------------------------------------------------------
# 基础模块
# ---------------------------------------------------------
function system_init() {
    echo -e "${GREEN}> 系统初始化...${PLAIN}"
    apt update -y && apt install -y curl wget git htop vim unzip socat tar gnupg lsb-release lsof
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
    if ! command -v docker >/dev/null 2>&1; then 
        curl -fsSL https://get.docker.com | bash
        systemctl enable docker; systemctl start docker
    fi
    if ! command -v docker-compose >/dev/null 2>&1; then 
        echo -e '#!/bin/bash\ndocker compose "$@"' > /usr/local/bin/docker-compose 
        chmod +x /usr/local/bin/docker-compose
    fi
    echo -e "${GREEN}Docker 就绪${PLAIN}"
}

function install_security() {
    echo -e "${GREEN}> 安全加固...${PLAIN}"
    apt install -y fail2ban ufw lsof
    SSH_PORT=$(ss -nltp | grep sshd | awk '{print $4}' | awk -F: '{print $NF}' | head -n 1)
    if [ -z "$SSH_PORT" ]; then SSH_PORT=22; fi
    echo -e "${YELLOW}检测到 SSH 端口: $SSH_PORT${PLAIN}"
    
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "$SSH_PORT"/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow 16601/tcp comment 'Lucky'
    ufw allow 8888/tcp comment 'DPanel'
    ufw route allow default allow out on docker0
    
    echo "y" | ufw enable
    systemctl enable fail2ban && systemctl start fail2ban
    echo -e "${GREEN}防护已开启${PLAIN}"
}

function ops_cleanup() {
    echo -e "${GREEN}> 清理垃圾文件...${PLAIN}"
    docker system prune -f
    find /var/lib/docker/containers/ -name "*-json.log" -exec truncate -s 0 {} \;
    echo -e "${GREEN}清理完成${PLAIN}"
}

# ---------------------------------------------------------
# 菜单系统
# ---------------------------------------------------------

# 卸载子菜单
function show_uninstall_menu() {
    clear
    echo -e "================================================="
    echo -e "   应用卸载与清理 ${RED}[危险操作]${PLAIN}"
    echo -e "================================================="
    echo -e "${GREEN}1.${PLAIN} 卸载 Lucky (反代工具)"
    echo -e "${GREEN}2.${PLAIN} 卸载 DPanel (Docker管理)"
    echo -e "${GREEN}3.${PLAIN} 卸载 NPM (旧版反代残留)"
    echo -e "-------------------------------------------------"
    echo -e "${GREEN}0.${PLAIN} 返回主菜单"
    echo -e "================================================="
    read -p "请选择: " un_num

    case "$un_num" in
        1) uninstall_app "Lucky" "lucky" "16601" ;;
        2) uninstall_app "DPanel" "dpanel" "8888" ;;
        3) uninstall_app "NPM" "nginx_proxy_manager" "81" ;;
        0) show_menu ;;
        *) echo -e "${RED}输入错误${PLAIN}"; sleep 1; show_uninstall_menu ;;
    esac
    
    if [[ "$un_num" != "0" ]]; then
        echo ""
        read -p "按回车键继续..." 
        show_uninstall_menu
    fi
}

# 主菜单
function show_menu() {
    clear
    echo -e "================================================="
    echo -e "   VPS 运维工具箱 V5.3 ${YELLOW}[全周期管理]${PLAIN}"
    echo -e "   存储目录: ${SKYBLUE}$BASE_DIR${PLAIN}"
    echo -e "================================================="
    echo -e "基础环境:"
    echo -e "${GREEN}1.${PLAIN} 系统初始化 (BBR/Swap/时区)"
    echo -e "${GREEN}2.${PLAIN} 安装 Docker 环境"
    echo -e "${GREEN}3.${PLAIN} 安装 WARP (IP隐藏/SOCKS5)"
    echo -e "应用部署:"
    echo -e "${GREEN}4.${PLAIN} ${SKYBLUE}部署 Lucky (中文反代神器)${PLAIN} ${YELLOW}*推荐*${PLAIN}"
    echo -e "${GREEN}5.${PLAIN} ${SKYBLUE}部署 DPanel (轻量Docker面板)${PLAIN}"
    echo -e "维护管理:"
    echo -e "${GREEN}6.${PLAIN} 安全加固 (防火墙+SSH防护)"
    echo -e "${GREEN}7.${PLAIN} 磁盘/日志清理"
    echo -e "${GREEN}8.${PLAIN} ${RED}卸载已装应用 ->${PLAIN}"
    echo -e "-------------------------------------------------"
    echo -e "${GREEN}0.${PLAIN} 退出"
    echo -e "================================================="
    read -p "请选择: " num

    case "$num" in
        1) system_init ;;
        2) install_docker ;;
        3) install_warp ;;
        4) install_lucky ;;
        5) install_dpanel ;;
        6) install_security ;;
        7) ops_cleanup ;;
        8) show_uninstall_menu ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误${PLAIN}" ;;
    esac
    
    echo ""
    read -p "按回车键返回..." 
    show_menu
}

show_menu
