#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
PLAIN='\033[0m'

# 配置文件路径
CONFIG_FILE="/usr/local/etc/xray/config.json"
SERVICE_FILE="/etc/systemd/system/xray.service"
BIN_FILE="/usr/local/bin/xray"

# 检查 Root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 必须使用 root 用户运行此脚本！${PLAIN}"
        exit 1
    fi
}

# 基础依赖检查与安装
install_dependencies() {
    echo -e "${YELLOW}正在检查并安装系统依赖...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt update -y
        apt install -y curl wget tar jq openssl uuid-runtime nano
    elif [ -f /etc/redhat-release ]; then
        yum update -y
        yum install -y curl wget tar jq openssl nano
        if ! command -v jq &> /dev/null; then
             yum install -y epel-release
             yum install -y jq
        fi
        if ! command -v uuidgen &> /dev/null; then
             yum install -y util-linux
        fi
    else
        echo -e "${RED}不支持的操作系统，脚本仅支持 Debian/Ubuntu/CentOS 系列。${PLAIN}"
        exit 1
    fi
}

# 获取最新 X-ray 版本
get_latest_version() {
    echo -e "${YELLOW}正在获取 X-ray 最新版本信息...${PLAIN}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
    if [[ -z "$LATEST_VERSION" || "$LATEST_VERSION" == "null" ]]; then
        echo -e "${RED}获取版本失败，使用备用版本 v1.8.24${PLAIN}"
        LATEST_VERSION="v1.8.24" 
    else
        echo -e "${GREEN}最新版本: ${LATEST_VERSION}${PLAIN}"
    fi
}

# 安装/更新 X-ray 核心
install_xray_core() {
    get_latest_version
    local ARCH=$(uname -m)
    local XRAY_FILE="Xray-linux-64.zip"
    
    case "$ARCH" in
        x86_64) XRAY_FILE="Xray-linux-64.zip" ;;
        aarch64) XRAY_FILE="Xray-linux-arm64-v8a.zip" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${PLAIN}"; exit 1 ;;
    esac

    echo -e "${YELLOW}正在下载 X-ray 核心...${PLAIN}"
    mkdir -p /usr/local/bin/xray_temp
    cd /usr/local/bin/xray_temp
    
    # 强制删除旧文件以防缓存错误文件
    rm -f "$XRAY_FILE"
    
    wget --no-check-certificate "https://github.com/XTLS/Xray-core/releases/download/${LATEST_VERSION}/${XRAY_FILE}"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}下载失败，请检查网络连接。${PLAIN}"
        cd ~; rm -rf /usr/local/bin/xray_temp
        return 1
    fi

    echo -e "${YELLOW}正在解压并安装...${PLAIN}"
    unzip -o "$XRAY_FILE"
    
    systemctl stop xray 2>/dev/null

    cp xray /usr/local/bin/xray
    chmod +x /usr/local/bin/xray

    # 验证版本
    echo -e "${BLUE}验证安装版本:${PLAIN}"
    /usr/local/bin/xray version
    
    mkdir -p /usr/local/share/xray
    cp geosite.dat /usr/local/share/xray/
    cp geoip.dat /usr/local/share/xray/

    cd ~
    rm -rf /usr/local/bin/xray_temp
    echo -e "${GREEN}X-ray 核心安装/更新完成。${PLAIN}"
}

# 生成新的配置
generate_config() {
    mkdir -p /usr/local/etc/xray

    # 如果已存在配置文件，询问是否覆盖
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}检测到已存在配置文件 config.json${PLAIN}"
        read -p "是否覆盖重新生成? [y/N]: " overwrite
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            echo -e "${YELLOW}跳过配置生成。${PLAIN}"
            return
        fi
    fi

    local uuid=$(uuidgen)
    echo -e "${YELLOW}正在生成 x25519 密钥对...${PLAIN}"
    local key_pair=$(xray x25519)
    local private_key=$(echo "$key_pair" | grep "Private" | awk '{print $3}')
    
    echo -e "${BLUE}请输入端口 [1-65535] (默认随机): ${PLAIN}"
    read -p "" port
    if [[ -z "$port" ]]; then
        port=$((RANDOM + 10000))
        [[ $port -gt 65535 ]] && port=$(($port - 10000))
        echo -e "${YELLOW}使用随机端口: $port${PLAIN}"
    fi

    local sni_dest="www.microsoft.com:443"
    local sni_server_names='["www.microsoft.com", "microsoft.com"]'
    
    echo -e "${BLUE}请输入伪装域名(SNI) (默认: www.microsoft.com): ${PLAIN}"
    read -p "" input_sni
    if [[ ! -z "$input_sni" ]]; then
        sni_dest="${input_sni}:443"
        sni_server_names="[\"${input_sni}\"]"
    fi

    cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${sni_dest}",
          "xver": 0,
          "serverNames": ${sni_server_names},
          "privateKey": "${private_key}",
          "shortIds": ["", "$(openssl rand -hex 4)"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
    echo -e "${GREEN}配置文件生成完毕。${PLAIN}"
}

# 配置 systemd
setup_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable xray
    restart_service
}

# 重启服务
restart_service() {
    systemctl restart xray
    if systemctl is-active --quiet xray; then
         echo -e "${GREEN}X-ray 服务启动成功！${PLAIN}"
    else
         echo -e "${RED}X-ray 服务启动失败，请检查日志。${PLAIN}"
    fi
}

# 查看运行状态
check_status() {
    if [[ ! -f "$BIN_FILE" ]]; then
        echo -e "${RED}X-ray 未安装。${PLAIN}"
        return
    fi
    
    echo -e "${BLUE}---------- X-ray 状态 ----------${PLAIN}"
    local version=$($BIN_FILE version | head -n 1 | awk '{print $2}')
    echo -e "版本: ${GREEN}${version}${PLAIN}"
    
    if systemctl is-active --quiet xray; then
        echo -e "服务状态: ${GREEN}运行中 (Running)${PLAIN}"
    else
        echo -e "服务状态: ${RED}未运行 (Stopped)${PLAIN}"
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "配置文件: ${GREEN}存在${PLAIN}"
    else
        echo -e "配置文件: ${RED}丢失${PLAIN}"
    fi
    echo -e "${BLUE}--------------------------------${PLAIN}"
}

# 读取并显示链接
show_link() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}配置文件不存在，无法显示链接。${PLAIN}"
        return
    fi

    local uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_FILE")
    local port=$(jq -r '.inbounds[0].port' "$CONFIG_FILE")
    local flow=$(jq -r '.inbounds[0].settings.clients[0].flow' "$CONFIG_FILE")
    # 注意：这里我们假设只有一个inbound且格式符合我们生成的标准，用于简单读取
    # 实际情况可能需要更复杂的解析，这里只做基本尝试
    local private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' "$CONFIG_FILE")
    local sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "$CONFIG_FILE")
    
    # 此时我们需要对应的公钥，但配置文件只存了私钥。
    # X-ray 没有直接从私钥导出公钥的简单CLI工具供脚本快速调用（除非再运行一次x25519逻辑很麻烦）。
    # *修正策略*: 为了显示链接，我们需要公钥。如果公钥丢失，链接将无效。
    # 简单的做法是：我们无法轻易从私钥反推公钥用于显示，除非我们把公钥也存在某个地方或者不显示公钥。
    # 但Reality必须要有公钥。
    # 妥协方案：尝试从日志或者当初生成时保存的文件读取？不行，太乱。
    # 更好方案：使用 xray x25519 -i "private_key" (如果支持) 或者提示用户无法恢复公钥。
    # 查阅文档，`xray x25519` 生成是一次性的。
    # 实际上，Reality的私钥生成对应公钥是确定性的，但Xray CLI好像没提供直接转换命令。
    # 等等，如果只是为了查看配置，不重新生成，我们可能确实无法找回公钥。
    # 为了解决这个问题，我们可以在生成配置时，把公钥作为注释写在json里，或者单独存一个文件。
    # 这里我们采用单独存文件的方式 `/usr/local/etc/xray/public.key`。
    
    local public_key=""
    if [[ -f "/usr/local/etc/xray/public.key" ]]; then
        public_key=$(cat /usr/local/etc/xray/public.key)
    else
        echo -e "${RED}警告: 未找到公钥文件，链接中的 pbk 将为空，请手动填入！${PLAIN}"
    fi

    local server_ip=$(curl -s4 ifconfig.me)
    local link="vless://${uuid}@${server_ip}:${port}?security=reality&encryption=none&pbk=${public_key}&headerType=none&fp=chrome&type=tcp&flow=${flow}&sni=${sni}#Xray_Vision_Reality"

    echo ""
    echo -e "${BLUE}================ 配置信息 =================${PLAIN}"
    echo -e "地址: ${GREEN}${server_ip}${PLAIN}"
    echo -e "端口: ${GREEN}${port}${PLAIN}"
    echo -e "UUID: ${GREEN}${uuid}${PLAIN}"
    echo -e "SNI : ${GREEN}${sni}${PLAIN}"
    echo -e "PBK : ${GREEN}${public_key}${PLAIN}"
    echo -e "${BLUE}================ 分享链接 =================${PLAIN}"
    echo -e "${YELLOW}${link}${PLAIN}"
    echo -e "${BLUE}===========================================${PLAIN}"
}

# 修正生成配置函数以保存公钥
generate_config() {
    mkdir -p /usr/local/etc/xray

    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}检测到已存在配置文件 config.json${PLAIN}"
        read -p "是否覆盖重新生成? [y/N]: " overwrite
        if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
            echo -e "${YELLOW}跳过配置生成。${PLAIN}"
            return
        fi
    fi

    local uuid=$(uuidgen)
    echo -e "${YELLOW}正在生成 x25519 密钥对...${PLAIN}"
    
    # 使用绝对路径调用 xray
    local key_pair=$($BIN_FILE x25519)
    echo -e "密钥生成调试信息:\n$key_pair"
    
    # 尝试多种格式解析
    # 标准/旧版格式: "Private key: ..." 或 "Private Key: ..."
    local private_key=$(echo "$key_pair" | grep -i "Private" | awk -F': ' '{print $2}' | awk '{print $1}')
    local public_key=$(echo "$key_pair" | grep -i "Public" | awk -F': ' '{print $2}' | awk '{print $1}')
    
    # 兼容新版 Xray/其他变种格式:
    # PrivateKey: ...
    # Password: ... (在新版中作为 Public Key 使用)
    if [[ -z "$private_key" ]]; then
        # 尝试匹配 "PrivateKey: xxx"
        private_key=$(echo "$key_pair" | grep "PrivateKey:" | awk '{print $2}')
    fi
     if [[ -z "$private_key" ]]; then
        # 尝试匹配 "Private key: xxx" (awk 默认空格分隔，取第3个)
        private_key=$(echo "$key_pair" | grep -i "Private" | awk '{print $3}')
    fi

    if [[ -z "$public_key" ]]; then
        # 新版将 Public Key 显示为 "Password:" ?
        public_key=$(echo "$key_pair" | grep "Password:" | awk '{print $2}')
    fi
    if [[ -z "$public_key" ]]; then
        # 旧版 "Public key: xxx"
        public_key=$(echo "$key_pair" | grep -i "Public" | awk '{print $3}')
    fi

    if [[ -z "$public_key" ]]; then
        echo -e "${RED}严重错误: 无法获取公钥！${PLAIN}"
        echo -e "请手动记录上方调试信息中的 Public key (或 Password)。"
    fi
    
    # 保存公钥
    echo "$public_key" > /usr/local/etc/xray/public.key

    echo -e "${BLUE}请输入端口 [1-65535] (默认随机): ${PLAIN}"
    read -p "" port
    if [[ -z "$port" ]]; then
        port=$((RANDOM + 10000))
        [[ $port -gt 65535 ]] && port=$(($port - 10000))
        echo -e "${YELLOW}使用随机端口: $port${PLAIN}"
    fi

    local sni_dest="www.microsoft.com:443"
    local sni_server_names='["www.microsoft.com", "microsoft.com"]'
    
    echo -e "${BLUE}请输入伪装域名(SNI) (默认: www.microsoft.com): ${PLAIN}"
    read -p "" input_sni
    if [[ ! -z "$input_sni" ]]; then
        sni_dest="${input_sni}:443"
        sni_server_names="[\"${input_sni}\"]"
    fi

    cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${sni_dest}",
          "xver": 0,
          "serverNames": ${sni_server_names},
          "privateKey": "${private_key}",
          "shortIds": ["", "$(openssl rand -hex 4)"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      }
    ]
  }
}
EOF
    echo -e "${GREEN}配置文件生成完毕 (已启用: 禁止局域网访问, 禁止 BitTorrent)。${PLAIN}"
}

# 开启 BBR
enable_bbr() {
    echo -e "${YELLOW}正在开启 TCP BBR...${PLAIN}"
    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${GREEN}BBR 已经开启。${PLAIN}"
        return
    fi
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    echo -e "${GREEN}BBR 开启成功。${PLAIN}"
}

# 防火墙配置
setup_firewall() {
    if ! command -v ufw &> /dev/null; then
        echo -e "${YELLOW}未检测到 ufw，尝试安装...${PLAIN}"
        if [ -f /etc/debian_version ]; then
            apt update -y && apt install -y ufw
        elif [ -f /etc/redhat-release ]; then
             yum install -y ufw
        fi
    fi
    
    if ! command -v ufw &> /dev/null; then
        echo -e "${RED}无法安装 UFW，请手动检查系统源或使用 iptables/firewalld。${PLAIN}"
        return
    fi
    
    echo -e "${YELLOW}正在自动配置 UFW...${PLAIN}"
    ufw allow ssh
    ufw allow 22/tcp
    
    # 获取当前配置端口
    local port=""
    if [[ -f "$CONFIG_FILE" ]]; then
        port=$(jq -r '.inbounds[0].port' "$CONFIG_FILE")
    fi
    
    if [[ ! -z "$port" && "$port" != "null" ]]; then
        echo -e "${YELLOW}放行 X-ray 端口: $port${PLAIN}"
        ufw allow "$port"/tcp
    else
        echo -e "${RED}未找到 X-ray 端口配置，跳过 X-ray 端口放行。${PLAIN}"
    fi

    echo -e "${YELLOW}正在启用 UFW (可能中断 SSH 连接，请确保 SSH 端口已放行)...${PLAIN}"
    echo "y" | ufw enable
    echo -e "${GREEN}UFW 防火墙配置完成。${PLAIN}"
    ufw status verbose
}

# 防火墙菜单
firewall_menu() {
    clear
    echo -e "${BLUE}---------- 防火墙管理 (UFW) ----------${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 一键开启并放行 SSH/X-ray"
    echo -e "  ${GREEN}2.${PLAIN} 关闭防火墙"
    echo -e "  ${GREEN}3.${PLAIN} 查看防火墙状态"
    echo -e "  ${GREEN}4.${PLAIN} 手动放行指定端口"
    echo -e "  ${GREEN}5.${PLAIN} 手动关闭指定端口 (删除放行规则)"
    echo -e "  ${GREEN}0.${PLAIN} 返回主菜单"
    echo -e "${BLUE}--------------------------------------${PLAIN}"
    
    read -p "请输入选项 [0-5]: " fnum
    case "$fnum" in
        1)
            setup_firewall
            read -p "按回车键继续..."
            firewall_menu
            ;;
        2)
            echo -e "${YELLOW}正在关闭 UFW...${PLAIN}"
            ufw disable
            read -p "按回车键继续..."
            firewall_menu
            ;;
        3)
            echo -e "${BLUE}当前 UFW 状态:${PLAIN}"
            if command -v ufw &> /dev/null; then
                ufw status verbose
            else
                echo -e "${RED}UFW 未安装。${PLAIN}"
            fi
            read -p "按回车键继续..."
            firewall_menu
            ;;
        4)
            read -p "请输入要放行的端口 (如 80 或 80/tcp): " cport
            if [[ ! -z "$cport" ]]; then
                ufw allow "$cport"
                echo -e "${GREEN}端口 $cport 已放行。${PLAIN}"
            fi
            read -p "按回车键继续..."
            firewall_menu
            ;;
        5)
            read -p "请输入要关闭的端口 (如 80 或 80/tcp): " dport
            if [[ ! -z "$dport" ]]; then
                ufw delete allow "$dport"
                echo -e "${GREEN}端口 $dport 放行规则已删除。${PLAIN}"
            fi
            read -p "按回车键继续..."
            firewall_menu
            ;;
        0)
            show_menu
            ;;
        *)
            firewall_menu
            ;;
    esac
}

# 编辑配置
edit_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}配置文件不存在。${PLAIN}"
        return
    fi
    if ! command -v nano &> /dev/null; then
         echo -e "${YELLOW}Nano 编辑器未安装，正在安装...${PLAIN}"
         if [ -f /etc/debian_version ]; then apt install -y nano; else yum install -y nano; fi
    fi
    nano "$CONFIG_FILE"
    echo -e "${YELLOW}编辑完成，正在重启服务...${PLAIN}"
    restart_service
}

# 卸载
uninstall_xray() {
    echo -e "${RED}警告: 此操作将完全删除 X-ray 及其配置！${PLAIN}"
    read -p "确定要继续吗? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}已取消卸载。${PLAIN}"
        return
    fi
    
    systemctl stop xray
    systemctl disable xray
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    
    rm -f "$BIN_FILE"
    rm -rf /usr/local/share/xray
    
    read -p "是否删除配置文件目录 (/usr/local/etc/xray)? [y/N]: " del_conf
    if [[ "$del_conf" == "y" || "$del_conf" == "Y" ]]; then
        rm -rf /usr/local/etc/xray
    fi
    
    echo -e "${GREEN}X-ray 已卸载。${PLAIN}"
}

# 查看日志
show_log() {
    echo -e "${YELLOW}正在打开实时日志 (按 Ctrl+C 退出)...${PLAIN}"
    journalctl -u xray -f
}

# 主菜单
show_menu() {
    clear
    echo -e "${BLUE}=============================================${PLAIN}"
    echo -e "${BLUE}       X-ray 一键管理脚本 (VLESS+Vision)     ${PLAIN}"
    echo -e "${BLUE}=============================================${PLAIN}"
    echo -e "  ${GREEN}1.${PLAIN} 安装 X-ray (全新安装)"
    echo -e "  ${GREEN}2.${PLAIN} 更新 X-ray 核心 (保留配置)"
    echo -e "  ${GREEN}3.${PLAIN} 修改配置文件"
    echo -e "  ${GREEN}4.${PLAIN} 查看配置链接"
    echo -e "  ${GREEN}5.${PLAIN} 查看运行状态"
    echo -e "  ${GREEN}6.${PLAIN} 查看实时日志"
    echo -e "  ${GREEN}7.${PLAIN} 开启 TCP BBR (系统优化)"
    echo -e "  ${GREEN}8.${PLAIN} 防火墙管理 (UFW)"
    echo -e "  ${RED}9. 卸载 X-ray${PLAIN}"
    echo -e "  ${GREEN}0.${PLAIN} 退出脚本"
    echo -e "${BLUE}=============================================${PLAIN}"
    
    check_status
    
    read -p "请输入选项 [0-9]: " num
    case "$num" in
        1)
            install_dependencies
            install_xray_core
            generate_config
            setup_service
            
            # 询问配置防火墙
            echo ""
            read -p "是否配置防火墙 (UFW) 并放行相关端口? [y/N]: " ask_ufw
            if [[ "$ask_ufw" == "y" || "$ask_ufw" == "Y" ]]; then
                setup_firewall
            fi
            
            show_link
            ;;
        2)
            install_xray_core
            restart_service
            ;;
        3)
            edit_config
            ;;
        4)
            show_link
            ;;
        5)
            check_status
            read -p "按回车键返回菜单..."
            show_menu
            ;;
        6)
            show_log
            ;;
        7)
            enable_bbr
            read -p "按回车键返回菜单..."
            show_menu
            ;;
        8)
            firewall_menu
            ;;
        9)
            uninstall_xray
            ;;
        0)
            exit 0
            ;;
        *)
            echo -e "${RED}请输入正确的数字 [0-9]${PLAIN}"
            sleep 1
            show_menu
            ;;
    esac
}

# 入口
check_root
# 如果有参数，可以做非交互模式，目前仅菜单与无参
show_menu
