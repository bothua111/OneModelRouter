#requires -Version 5.1
<#
  一模路通 OneModelRouter Windows 一行安装：
    powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr <官网>/install.ps1 -useb | iex"

  行为：取 feed（Gitee raw 优先 → GitHub → 镜像）→ 下载 Setup .exe → 按 sha256 校验 →
        运行安装器（默认显示界面；-Silent 传 /S）。
  参数：
    -Silent       静默安装
    -Mirror <url> GitHub 下载镜像前缀
    -Proxy  <url> 下载代理
#>
[CmdletBinding()]
param(
  [switch]$Silent,
  [string]$Mirror = '',
  [string]$Proxy  = ''
)
$ErrorActionPreference = 'Stop'

$feeds = @(
  'https://gitee.com/laojiaogroup/OneModelRouter/raw/master/update/latest.json',
  'https://github.com/bothua111/OneModelRouter/releases/latest/download/latest.json',
  'https://gh-proxy.com/https://github.com/bothua111/OneModelRouter/releases/latest/download/latest.json'
)
if ($Proxy) { $global:env:HTTPS_PROXY = $Proxy; $global:env:HTTP_PROXY = $Proxy }

function Invoke-Iwr([string]$Uri) {
  $p = @{ Uri = $Uri; UseBasicParsing = $true }
  if ($Proxy) { $p['Proxy'] = $Proxy }
  Invoke-WebRequest @p
}

# 取 feed
$feed = $null
foreach ($u in $feeds) {
  try { $r = Invoke-Iwr $u; $feed = ($r.Content | ConvertFrom-Json); if ($feed) { break } } catch {}
}
if (-not $feed) { Write-Error '所有 feed 源均不可达，请检查网络或加 -Proxy/-Mirror'; exit 1 }

$win = $feed.platforms.windows
if (-not $win) { Write-Error "feed 里没有 Windows 产物"; exit 1 }
$ver = $feed.version
Write-Host "[omr] 最新版本 v$ver，产物 $($win.file)"

$tmp = Join-Path $env:TEMP ("omr-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$dest = Join-Path $tmp $win.file

# 下载候选：Gitee 直链 → GitHub → 镜像
$cands = @()
if ($win.giteeUrl) { $cands += $win.giteeUrl }
$cands += $win.url
if ($Mirror) { $cands += ($Mirror.TrimEnd('/') + '/' + $win.url) }
$ok = $false
foreach ($u in $cands) {
  try { Write-Host "[omr] 下载 $u"; Invoke-Iwr $u -OutFile $dest; if (Test-Path $dest) { $ok = $true; break } } catch {}
}
if (-not $ok) { Write-Error '下载失败'; exit 1 }

# sha256 校验
if ($win.sha256) {
  $got = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLower()
  if ($got -ne $win.sha256.ToLower()) {
    Remove-Item -LiteralPath $dest -Force
    Write-Error "sha256 校验不匹配（期望 $($win.sha256)，得到 $got），已拒绝安装"
    exit 1
  }
  Write-Host '[omr] sha256 校验通过'
}

# 运行安装器
$args = if ($Silent) { @('/S') } else { @() }
Write-Host '[omr] 启动安装器…'
Start-Process -FilePath $dest -ArgumentList $args -Wait
Write-Host '[omr] 完成。管理面板：http://127.0.0.1:18681/admin'
