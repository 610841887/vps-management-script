# VPS 管理脚本 (VPS Management Script)

一个功能全面的 Bash 脚本，用于在 Linux VPS 上一键部署和管理 X-ray 服务。

## 功能特性

- **一键安装**: 自动化部署 X-ray 核心，配置 VLESS + XTLS-Vision + Reality。
- **菜单驱动**: 简单易用的命令行菜单界面。
- **自更新**: 脚本支持在线自我更新，随时获取最新功能。
- **安全增强**:
    - **TCP BBR**: 一键开启 BBR 拥塞控制，优化网络速度。
    - **UFW 防火墙**: 集成防火墙管理，轻松放行/关闭端口。
    - **路由规则**: 预配置路由规则，自动拦截局域网 IP 和 BitTorrent 流量。
- **核心管理**: 支持更新 X-ray 核心、在线编辑配置、查看运行状态。
- **系统兼容**: 支持 Debian, Ubuntu, 和 CentOS 系统。

## 使用说明 (Usage)

使用 Root 用户登录服务器，运行以下一键安装命令：

```bash
wget -N --no-check-certificate https://raw.githubusercontent.com/610841887/vps-management-script/main/install_xray.sh && chmod +x install_xray.sh && ./install_xray.sh
```

## 系统要求

- Linux VPS (Debian / Ubuntu / CentOS)
- Root 权限 (推荐 root 用户执行)

## 许可证

MIT License
