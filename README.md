# 🛠️ VPS 运维工具箱 (Lightweight VPS Toolbox)

**专为 Debian 12 / Ubuntu 22+ 设计的轻量级、全能型 VPS 运维脚本。**

抛弃臃肿，追求极致的资源利用率。集成了 Docker 环境、轻量化管理面板、反向代理神器、网络优化及安全加固功能。V6.4 版本更是加入了精准的系统资源看板、IP 质量体检以及一键 DD 重装系统功能。

---

## 🚀 快速开始 (Quick Start)

在 SSH 终端中执行以下命令即可启动（支持重复运行）：

```bash
apt update && apt install -y wget && wget -O vps_setup.sh https://raw.githubusercontent.com/sakuranano/vps_setup/refs/heads/main/vps_setup.sh && chmod +x vps_setup.sh && ./vps_setup.sh
```
(如果下载网络不佳，请检查 VPS 的 DNS 设置或网络连接)

✨ 核心功能 (Features)
1. 基础环境优化
系统初始化：自动配置 BBR 加速、添加 Swap 虚拟内存 (智能判断)、校准时区。

依赖管理：自动安装常用运维工具 (curl, wget, git, htop, vim, lsof, jq, procps 等)。

2. Docker 生态
Docker & Compose：一键安装最新版 Docker 引擎及 Docker Compose。

状态感知：主菜单实时显示 Docker 运行状态。

3. 轻量化应用集成
🎯 Lucky (反向代理神器)

替代笨重的 Nginx Proxy Manager。

特性：全中文界面、内存占用极低 (~20MB)、支持端口转发、DDNS、内网穿透。

镜像：官方最新 gdy666/lucky。

🐳 DPanel Lite (容器管理)

替代 Portainer。

特性：国人开发、极致轻量、支持 Compose 编排、文件管理、日志查看。

4. 网络与隐身
WARP SOCKS5 代理：一键配置 Cloudflare WARP (端口 40000)。

用途：隐藏 VPS 真实 IP，解锁 Netflix/Disney+/ChatGPT 等流媒体限制。

智能检测：支持检测本机直连 IP 或 WARP 代理 IP 的纯净度与解锁情况。

5. 系统看板与体检
📊 硬件资源看板：秒级读取 CPU 型号/主频、内存占用、硬盘使用率、AES 指令集状态 (基于 vmstat 采样，精准无误)。

🌍 全能 IP 体检：集成 IP.Check.Place，检测 IP 欺诈值、黑名单状态及流媒体解锁。

6. 高级系统管理
🛡️ 安全加固：自动识别当前 SSH 端口并放行，默认拒绝所有入站连接，仅开放必要端口；集成 Fail2Ban 防止爆破。

🔄 一键重装 (DD)：集成 InstallNET (移植自 kejilion)，支持一键将 VPS 重装为纯净版 Debian 12。（仅限 KVM/Xen 架构）

📝 默认端口与账号 (Default Info)
⚠️ 警告：安装完成后，请务必尽快修改默认密码！

应用名称	默认端口	访问地址	默认账号	默认密码
DPanel (容器面板)	8888	http://IP:8888	admin	admin
Lucky (反向代理)	16601	http://IP:16601	666	666
WARP Proxy	40000	127.0.0.1:40000	无	无 (SOCKS5)
🖥️ 脚本菜单预览
Plaintext
=================================================
   VPS 运维工具箱 V6.4 [Kejilion重装版]
   存储: /opt/docker_data
=================================================
1. 系统初始化 (BBR/Swap)     *建议首选*
2. 安装 Docker 环境          [已安装]
3. 安装 WARP 代理            [运行中]
-------------------------------------------------
4. 部署 Lucky 反代           [运行中]
5. 部署 DPanel 面板          [未安装]
-------------------------------------------------
6. 查看本机配置 (硬件/资源)
7. 全能 IP 体检 (解锁/欺诈分)
-------------------------------------------------
8. 安全加固 (防火墙/Fail2Ban)
9. 磁盘/日志清理
10. 卸载应用 ->
11. 重装 Debian 12 (DD)     *高危*
=================================================
❓ 常见问题 (FAQ)
Q: 为什么选择 Lucky 而不是 Nginx Proxy Manager (NPM)? A: NPM 虽然好用，但它是基于 Node.js 的，空闲状态下可能占用 100MB+ 内存。而 Lucky 基于 Go 语言，仅占用 20MB 左右，对于 1GB 内存的小鸡（VPS）来说，这节省下来的资源至关重要。

Q: 开启“安全加固”后连不上 SSH 了怎么办？ A: 脚本会自动检测你当前的 SSH 端口并放行。但如果你在防火墙开启后修改了 SSH 端口，请务必先手动放行新端口 (ufw allow 新端口) 再重启 SSH 服务。

Q: DD 重装系统卡住了怎么办？ A: 重装过程通常需要 10-20 分钟，期间 SSH 会断开。如果超过 30 分钟无法连接，请登录 VPS 服务商的 VNC 控制台查看情况。注意：OpenVZ 和 LXC 架构不支持 DD。

⚠️ 免责声明
本脚本仅供学习与技术交流使用，请勿用于任何非法用途。作者不承担因使用本脚本而导致的任何数据丢失或法律责任。建议在生产环境使用前先进行备份。

Made with ❤️ for Lightweight VPS
