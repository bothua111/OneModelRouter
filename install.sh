#!/bin/sh
# 一模路通 OneModelRouter 一行安装脚本（macOS / Linux）
#   curl -fsSL https://<你的官网>/install.sh | sh
#
# 行为：
#   - 探测系统/架构 → 从 feed 取最新产物（Gitee raw 优先，GitHub / 镜像兜底）；
#   - 每个下载都按 latest.json 里的 sha256 校验，不符即拒装；
#   - macOS：把 .dmg 挂载后复制 OneModelRouter.app 到 /Applications（不可写则 ~/Applications）；
#   - Linux：AppImage 装到 ~/.local/bin/OneModelRouter（加执行权限），
#            有 .deb/.rpm 且非交互失败时回退提示手动安装。
#
# 选项（sh -s -- ...）：
#   --mirror <prefix>  GitHub 下载镜像前缀（放在 github.com URL 前），如 https://gh-proxy.com/
#   --proxy  <url>     下载用代理 http:// / socks5://
#   --appimage         Linux 强制装 AppImage（默认）
#   --deb | --rpm      Linux 改装对应包管理器包
set -eu

site_feeds="https://gitee.com/laojiaogroup/OneModelRouter/raw/master/update/latest.json
https://github.com/bothua111/OneModelRouter/releases/latest/download/latest.json"
proxy="${OMR_PROXY:-}"
mirror="${OMR_MIRROR:-}"
force=""

say(){ printf '  %s\n' "$*"; }
die(){ printf 'onemodelrouter: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --mirror) [ $# -ge 2 ] || die "--mirror needs a value"; mirror=$2; shift 2 ;;
    --mirror=*) mirror=${1#--mirror=}; shift ;;
    --proxy) [ $# -ge 2 ] || die "--proxy needs a value"; proxy=$2; shift 2 ;;
    --proxy=*) proxy=${1#--proxy=}; shift ;;
    --appimage|--deb|--rpm) force=${1#--}; shift ;;
    *) die "unknown option $1" ;;
  esac
done
case "$mirror" in ''|http*://*) ;; *) die "--mirror must be an http(s) prefix" ;; esac

get(){ if [ -n "$proxy" ]; then curl -fsSL --proxy "$proxy" "$@"; else curl -fsSL "$@"; fi; }

# 读 feed：依次尝试各源
feed=""
for u in $site_feeds; do
  if feed=$(get "$u" 2>/dev/null) && [ -n "$feed" ]; then break; fi
done
[ -n "$feed" ] || die "所有 feed 源均不可达，请检查网络或用 --proxy/--mirror"

# 平台与产物 id
os=$(uname -s)
case "$(uname -m)" in arm64|aarch64) arch=arm64 ;; x86_64|amd64) arch=x64 ;; *) arch=x64 ;; esac
case "$os" in
  Darwin) pid="macos-$( [ "$arch" = arm64 ] && echo arm64 || echo x64 )"
          [ "$pid" ] || pid="macos-arm64" ;;
  Linux)  case "$force" in
            deb) pid="linux-deb-$arch" ;;
            rpm) pid="linux-rpm-$arch" ;;
            *) pid="linux-appimage-$arch" ;;
          esac ;;
  *) die "unsupported system: $os（Windows 请用 install.ps1）" ;;
esac

# 从 feed 的 platforms.<pid> 取 file/url/giteeUrl/sha256
pick(){ printf '%s' "$1" | tr -d '\n' | sed -n "s/.*\"$2\":{[^}]*\"$3\":\"\([^\"]*\)\".*/\1/p" | head -n 1; }
file=$(pick "$feed" "$pid" file)
gurl=$(pick "$feed" "$pid" url)
geurl=$(pick "$feed" "$pid" giteeUrl)
sha=$(pick "$feed" "$pid" sha256)
[ -n "$file" ] && [ -n "$gurl" ] || die "feed 里没有 $pid 的产物（可能该版本未发布此平台）"

# 下载：镜像(gitee 直链 → github 镜像 → github 直连)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
try_fetch(){ # $1=url
  [ -n "$1" ] || return 1
  say "下载 $1"
  get -o "$tmp/$file" "$1"
}
fetched=""
if [ "$os" = Linux ]; then
  for u in "$geurl" "$gurl" "${mirror:+$mirror}$gurl"; do
    if try_fetch "$u"; then fetched=1; break; fi
  done
else
  for u in "$geurl" "$gurl" "${mirror:+$mirror}$gurl"; do
    if try_fetch "$u"; then fetched=1; break; fi
  done
fi
[ -n "$fetched" ] || die "下载失败：$file"

# 校验 sha256
if [ -n "$sha" ]; then
  if command -v sha256sum >/dev/null; then got=$(sha256sum "$tmp/$file" | cut -d' ' -f1)
  else got=$(shasum -a 256 "$tmp/$file" | cut -d' ' -f1); fi
  [ "$got" = "$sha" ] || die "$file 校验不匹配（期望 $sha，得到 $got），已拒绝安装"
  say "sha256 校验通过"
fi

case "$os" in
  Darwin)
    apps=/Applications; [ -w "$apps" ] || { apps="$HOME/Applications"; mkdir -p "$apps"; }
    mount=$(mktemp -d)
    hdiutil attach -quiet -nobrowse -mountpoint "$mount" "$tmp/$file"
    if [ -d "$mount/OneModelRouter.app" ]; then
      rm -rf "$apps/OneModelRouter.app"
      cp -R "$mount/OneModelRouter.app" "$apps/OneModelRouter.app"
      say "已安装 $apps/OneModelRouter.app"
    else
      hdiutil detach -quiet "$mount" || true
      die "dmg 内未找到 OneModelRouter.app"
    fi
    hdiutil detach -quiet "$mount" || true
    say "open -a OneModelRouter 启动"
    ;;
  Linux)
    case "$pid" in
      linux-appimage-*)
        bin="${OMR_BIN_DIR:-$HOME/.local/bin}"; mkdir -p "$bin"
        install -m 755 "$tmp/$file" "$bin/OneModelRouter"
        say "已安装 $bin/OneModelRouter（AppImage）"
        case ":$PATH:" in *":$bin:"*) ;; *) say "把 $bin 加入 PATH 后可直接运行 OneModelRouter" ;; esac
        say "运行：$bin/OneModelRouter --appimage-extract-and-run  或桌面双击"
        ;;
      linux-deb-*)
        say "已下载到 $tmp/$file；请执行：sudo dpkg -i \"$tmp/$file\" && sudo apt -f install"
        ;;
      linux-rpm-*)
        say "已下载到 $tmp/$file；请执行：sudo rpm -ivh \"$tmp/$file\""
        ;;
    esac
    ;;
esac
say "管理面板：http://127.0.0.1:18681/admin"
