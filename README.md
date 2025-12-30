# VPS 管理脚本 (VPS Management Script)

一个功能全面的 Bash 脚本，用于在 Linux VPS 上一键部署和管理 X-ray 服务。

## 功能特性

- **一键安装**: 自动化部署 X-ray 核心，配置 VLESS + XTLS-Vision + Reality。
- **菜单驱动**: 简单易用的命令行菜单界面。
- **自更新**: 脚本支持在线自我更新，随时获取最新功能。
- **安全增强**:
- **功能丰富**:
    - **X-ray 管理**:  安装、更新、配置、卸载全套生命周期管理。
    - **性能优化**: 集成 `vps-tcp-tune` 脚本，一键优化系统参数与 BBR。
    - **线路测试**: 集成 `NodeQuality` 脚本，全面检测 VPS 线路与质量。
    - **安全防护**: 集成 `Fail2Ban`，一键配置 SSH 防爆破保护。
    - **系统重装**: 集成 `reinstall.sh` DD 脚本，支持一键重装 Linux/Windows 系统。
    - **UFW 防火墙**: 集成防火墙管理，轻松放行/关闭端口。
- **系统兼容**: 支持 Debian, Ubuntu, 和 CentOS 系统。

## 使用说明 (Usage)

使用 Root 用户登录服务器，运行以下一键安装命令：

```bash
wget -N --no-check-certificate https://raw.githubusercontent.com/610841887/vps-management-script/main/install.sh && chmod +x install.sh && ./install.sh
```

### 快捷管理
脚本安装后会自动设置 `vps` 快捷指令。以后只需输入以下命令即可启动脚本：

```bash
vps
```

## 系统要求

- Linux VPS (Debian / Ubuntu / CentOS)
- Root 权限 (推荐 root 用户执行)

## 许可证

MIT License
