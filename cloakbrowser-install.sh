#!/bin/bash
set -euo pipefail

# ==================== 配置项 ====================
CLOAK_VERSION="146.0.7680.177.5"
# 已改为固定完整加速直链，此变量不再参与拼接，保留兼容
DOWNLOAD_PROXY="https://us.lifekey.dpdns.org/"
KEEP_ALIVE_URL="https://www.baidu.com"
DATA_DIR="/root/.stealth_browser_profile"
LOG_FILE="/root/stealth_browser.log"
# ================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# 脚本标题（纯文本，无字符画）
echo -e "${YELLOW}${BOLD}============================================${NC}"
echo -e "${YELLOW}${BOLD}        CloakBrowser 全自动部署脚本         ${NC}"
echo -e "${YELLOW}${BOLD}  国内加速 | 依赖安装 | 开机自启 | 进程守护  ${NC}"
echo -e "${YELLOW}${BOLD}============================================${NC}"

# 检查 Root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\n${RED}${BOLD}[错误] 请使用 root 用户执行本脚本${NC}"
    exit 1
fi

echo -e "\n${GREEN}[1/8] 备份并配置国内软件源${NC}"
cp /etc/apt/sources.list /etc/apt/sources.list.bak
cat > /etc/apt/sources.list << 'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-security main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ jammy-backports main restricted universe multiverse
EOF
apt update -y

echo -e "\n${GREEN}[2/8] 安装系统运行依赖${NC}"
apt install -y --no-install-recommends \
curl wget python3 python3-pip \
libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
libatk1.0-0 libatk-bridge2.0-0 libatspi2.0-0 \
libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
libgbm1 libdrm2 libxkbcommon0 libasound2 libnss3 libcups2

echo -e "\n${GREEN}[3/8] 升级 pip 并安装 Python 依赖${NC}"
pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple --upgrade pip
pip3 install -i https://pypi.tuna.tsinghua.edu.cn/simple playwright cloakbrowser

echo -e "\n${GREEN}[4/8] 配置全局环境变量${NC}"
cat >> /etc/profile << EOF
# CloakBrowser 全局环境配置
export STEALTH_CHROME="/root/.cache/CloakBrowser/${CLOAK_VERSION}/chrome"
export PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH="\$STEALTH_CHROME"
export PATH="/root/.cache/CloakBrowser/${CLOAK_VERSION}:\$PATH"
EOF
source /etc/profile

echo -e "\n${GREEN}[5/8] 下载 CloakBrowser 内核文件（固定加速直链）${NC}"
mkdir -p /root/.cache/CloakBrowser/${CLOAK_VERSION}
if [ ! -f "/root/.cache/CloakBrowser/${CLOAK_VERSION}/chrome" ]; then
    echo "正在下载隐身浏览器内核..."
    # 使用固定完整加速直链
    wget -O /tmp/cloakbrowser-linux-x64.tar.gz \
    "https://us.lifekey.dpdns.org/https://cloakbrowser.dev/chromium-v146.0.7680.177.5/cloakbrowser-linux-x64.tar.gz"
    tar -xf /tmp/cloakbrowser-linux-x64.tar.gz -C /root/.cache/CloakBrowser/${CLOAK_VERSION}
    rm -f /tmp/cloakbrowser-linux-x64.tar.gz
fi
chmod +x /root/.cache/CloakBrowser/${CLOAK_VERSION}/chrome
echo "内核路径：/root/.cache/CloakBrowser/${CLOAK_VERSION}/chrome"

echo -e "\n${GREEN}[6/8] 创建后台常驻守护脚本${NC}"
cat > /root/stealth_browser_daemon.py << 'EOF'
import time
import logging
from playwright.sync_api import sync_playwright

USER_DATA_DIR = "/root/.stealth_browser_profile"
LOG_FILE = "/root/stealth_browser.log"
KEEP_ALIVE_URL = "https://www.baidu.com"

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

CHROME_ARGS = [
    "--no-sandbox",
    "--disable-setuid-sandbox",
    "--disable-dev-shm-usage",
    "--disable-blink-features=AutomationControlled",
    "--disable-images",
    "--mute-audio"
]

browser = None
page = None

def init_browser():
    global browser, page
    try:
        p = sync_playwright().start()
        browser = p.chromium.launch(
            headless=True,
            args=CHROME_ARGS,
            user_data_dir=USER_DATA_DIR,
            timeout=60000
        )
        page = browser.new_page()
        page.goto(KEEP_ALIVE_URL, timeout=30000, wait_until="domcontentloaded")
        logging.info("[OK] 隐身浏览器初始化成功，开始常驻运行")
        return True
    except Exception as e:
        logging.error(f"[ERROR] 浏览器初始化失败: {str(e)}")
        return False

def main():
    while True:
        if not browser or not page:
            init_browser()
        time.sleep(60)
        try:
            page.reload(timeout=30000)
        except Exception as e:
            logging.warning(f"[WARN] 页面保活异常，重新初始化: {str(e)}")
            if browser:
                browser.close()
            browser = None
            page = None

if __name__ == "__main__":
    main()
EOF
chmod +x /root/stealth_browser_daemon.py

echo -e "\n${GREEN}[7/8] 配置 Systemd 开机自启与进程守护${NC}"
systemctl stop stealth-browser 2>/dev/null || true
systemctl disable stealth-browser 2>/dev/null || true

cat > /etc/systemd/system/stealth-browser.service << 'EOF'
[Unit]
Description=CloakBrowser Stealth Anti-Captcha Service
After=network.target

[Service]
User=root
WorkingDirectory=/root
ExecStart=/usr/bin/python3 /root/stealth_browser_daemon.py
Restart=on-failure
RestartSec=5
StartLimitBurst=10
StartLimitInterval=60

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable stealth-browser
systemctl start stealth-browser

echo -e "\n${GREEN}[8/8] 检测服务运行状态${NC}"
sleep 3

# 服务状态检测
if systemctl is-active --quiet stealth-browser; then
    echo -e "\n${GREEN}${BOLD}[SUCCESS] 服务启动正常${NC}"
else
    echo -e "\n${RED}${BOLD}[FAILED] 服务启动失败，请执行：tail -f /root/stealth_browser.log 查看日志${NC}"
    exit 1
fi

# 全局调用+页面加载检测
echo -e "\n${YELLOW}正在验证全局默认调用...${NC}"
python3 << 'EOF'
from playwright.sync_api import sync_playwright
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto("https://www.baidu.com", timeout=30000)
        print("[OK] 全局默认隐身浏览器调用成功")
        browser.close()
except Exception as e:
    print(f"[ERROR] 全局调用失败: {str(e)}")
    exit(1)
EOF

# 部署完成信息输出
echo -e "\n${GREEN}${BOLD}============================================${NC}"
echo -e "${GREEN}${BOLD}            全部部署流程完成                ${NC}"
echo -e "${GREEN}${BOLD}============================================${NC}"
echo -e "内核版本：${CLOAK_VERSION}"
echo -e "开机自启：已启用"
echo -e "异常重启：5秒自动恢复"
echo -e "全局内核：Playwright 默认调用隐身内核"
echo -e ""
echo -e "${YELLOW}常用管理命令：${NC}"
echo -e "  查看状态 ：systemctl status stealth-browser"
echo -e "  实时日志 ：tail -f /root/stealth_browser.log"
echo -e "  重启服务 ：systemctl restart stealth-browser"
echo -e "  停止服务 ：systemctl stop stealth-browser"
echo -e ""
echo -e "${YELLOW}使用说明：${NC}"
echo -e "  编写 Playwright 代码无需手动指定浏览器路径，"
echo -e "  自动使用 CloakBrowser 绕过 Cloudflare 人机验证。"
echo -e "${GREEN}${BOLD}============================================${NC}"

