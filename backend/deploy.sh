#!/usr/bin/env bash
#========================================================================
# PM2 一键部署 / 运维脚本（后端 + 定时备份）
# 适用环境：Linux / macOS / Windows(Git Bash) —— 与 Deepin/Windows 均兼容
#
# 用法：
#   ./deploy.sh install    安装依赖 + 启动（并 pm2 save 启用开机自启）
#   ./deploy.sh start      仅启动/拉起应用
#   ./deploy.sh restart    重启应用
#   ./deploy.sh stop       停止应用
#   ./deploy.sh status     查看进程状态
#   ./deploy.sh logs       实时查看日志
#   ./deploy.sh backup     手动执行一次数据库备份
#   ./deploy.sh uninstall  停止并从 pm2 移除
#
# 环境变量（可选）：
#   APP_ENV=production   ./deploy.sh start    # 生产模式（开启 HTTPS）
#   BACKUP_INTERVAL_HOURS / BACKUP_RETENTION_DAYS
#========================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_ENV="${APP_ENV:-development}"
ECOSYSTEM="ecosystem.config.js"
CMD="${1:-start}"

# 支持用 ./deploy.sh 切换到生产（HTTPS_ENABLED=true）
if [ "$APP_ENV" = "production" ]; then
  ENV_FLAG="--env production"
else
  ENV_FLAG=""
fi

log() { printf '\033[32m[ deploy ]\033[0m %s\n' "$*"; }
err() { printf '\033[31m[ deploy ]\033[0m %s\n' "$*" >&2; }

require() {
  command -v node >/dev/null 2>&1 || { err "未找到 node，请先安装 Node.js 18+"; exit 1; }
  command -v npm  >/dev/null 2>&1 || { err "未找到 npm"; exit 1; }
}

ensure_pm2() {
  if ! command -v pm2 >/dev/null 2>&1; then
    log "未检测到 pm2，正在全局安装…"
    npm i -g pm2
  fi
  # 手动上 pm2 路径（npm 全局 bin 未必在 PATH 里）
  export PATH="$PATH:$(npm bin -g 2>/dev/null || true)"
  command -v pm2 >/dev/null 2>&1 || { err "pm2 安装失败，请手动 npm i -g pm2"; exit 1; }
}

start() {
  ensure_pm2
  mkdir -p logs
  log "启动 pm2 进程（$APP_ENV）…"
  # shellcheck disable=SC2086
  pm2 start "$ECOSYSTEM" $ENV_FLAG
  pm2 save || log "pm2 save 失败（无系统级自启），可后续手动 pm2 save"
  log "已完成，执行 ./deploy.sh status 确认。"
}

install() {
  require
  log "安装后端依赖…"
  npm install --omit=optional
  start
}

restart()  { ensure_pm2; pm2 restart "$ECOSYSTEM" $ENV_FLAG; pm2 save || true; }
stop()     { ensure_pm2; pm2 stop "$ECOSYSTEM" || true; }
status()   { ensure_pm2; pm2 status; }
logs()     { ensure_pm2; pm2 logs coal-backend; }
backup()   { log "手动执行数据库备份…"; node scripts/backup-db.js; }
uninstall(){ ensure_pm2; pm2 delete "$ECOSYSTEM" || true; pm2 save || true; }

case "$CMD" in
  install)   install ;;
  start)     require; start ;;
  restart)   restart ;;
  stop)      stop ;;
  status)    status ;;
  logs)      logs ;;
  backup)    backup ;;
  uninstall) uninstall ;;
  *)
    err "未知命令：$CMD"
    echo "可用命令：install | start | restart | stop | status | logs | backup | uninstall"
    exit 1
    ;;
esac