#========================================================================
# PM2 部署 / 运维脚本（Windows PowerShell）—— 后端 + 定时备份
#
# 用法（在 backend 目录执行）：
#   .\deploy.ps1 install      安装依赖 + 启动（pm2 save 自启）
#   .\deploy.ps1 start        仅启动/拉起应用
#   .\deploy.ps1 restart      重启应用
#   .\deploy.ps1 stop         停止应用
#   .\deploy.ps1 status       查看进程状态
#   .\deploy.ps1 logs         实时日志
#   .\deploy.ps1 backup       手动执行一次备份
#   .\deploy.ps1 uninstall    停止并从 pm2 移除
#
# 环境变量：$env:APP_ENV="production" 开启 HTTPS
#========================================================================
param([string]$Cmd = "start")

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$env:APP_ENV = if ($env:APP_ENV) { $env:APP_ENV } else { "development" }
$envFlag = if ($env:APP_ENV -eq "production") { "--env production" } else { "" }

function Write-Step([string]$m) { Write-Host "[ deploy ] $m" -ForegroundColor Green }

function Test-Node { if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "未找到 node，请先安装 Node.js 18+" } }

function Ensure-Pm2 {
    if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) {
        Write-Step "未检测到 pm2，正在全局安装…"
        npm i -g pm2 | Out-Null
    }
    if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) { throw "pm2 安装失败，请手动 npm i -g pm2" }
}

function Start-App {
    Ensure-Pm2
    New-Item -ItemType Directory -Force -Path logs | Out-Null
    Write-Step "启动 pm2 进程（$env:APP_ENV）…"
    Invoke-Expression "pm2 start ecosystem.config.js $envFlag"
    pm2 save | Out-Null
    Write-Step "完成。执行 .\deploy.ps1 status 确认。"
}

function Install-App { Test-Node; Write-Step "安装后端依赖…"; npm install --omit=optional; Start-App }

switch ($Cmd) {
    "install"   { Install-App }
    "start"     { Test-Node; Start-App }
    "restart"   { Ensure-Pm2; Invoke-Expression "pm2 restart ecosystem.config.js $envFlag"; pm2 save | Out-Null }
    "stop"      { Ensure-Pm2; pm2 stop ecosystem.config.js 2>$null }
    "status"    { Ensure-Pm2; pm2 status }
    "logs"      { Ensure-Pm2; pm2 logs coal-backend }
    "backup"    { Write-Step "手动执行数据库备份…"; node scripts/backup-db.js }
    "uninstall" { Ensure-Pm2; pm2 delete ecosystem.config.js 2>$null; pm2 save | Out-Null }
    default { Write-Host "未知命令：$Cmd" -ForegroundColor Red; Write-Host "可用：install | start | restart | stop | status | logs | backup | uninstall" }
}