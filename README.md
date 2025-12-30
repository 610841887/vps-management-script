# VPS Management Script

A comprehensive Bash script for one-click deployment and management of X-ray services on Linux VPS.

## Features

- **One-Click Installation**: Automated setup of X-ray core with VLESS + XTLS-Vision + Reality.
- **Menu-Driven**: Easy-to-use menu interface for management.
- **Security Enhancements**:
    - **TCP BBR**: Enable BBR congestion control with a single click.
    - **UFW Firewall**: Integrated firewall management to allow/block ports easily.
    - **Routing Rules**: Pre-configured rules to block private/LAN IPs and BitTorrent traffic.
- **Core Management**: Update X-ray core, edit configuration, and check status.
- **Compatibility**: Supports Debian, Ubuntu, and CentOS.

## Usage

1.  Download the script:
    ```bash
    wget -N --no-check-certificate https://raw.githubusercontent.com/610841887/vps-management-script/main/install_xray.sh
    chmod +x install_xray.sh
    ```

2.  Run the script:
    ```bash
    ./install_xray.sh
    ```

## Requirements

- Linux VPS (Debian / Ubuntu / CentOS)
- Root privileges

## License

MIT License
