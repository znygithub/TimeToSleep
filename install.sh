#!/usr/bin/env bash
# TimeToSleep installer
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/ui.sh"

clear 2>/dev/null || true
ui_moon

ui_print "  ${BOLD}安装 TimeToSleep${RESET}"
ui_blank

# ── 1. Check prerequisites ──
ui_step "检查环境..."

if [[ "$(uname)" != "Darwin" ]]; then
  ui_error "TimeToSleep 目前只支持 macOS"
  exit 1
fi

if ! command -v swiftc &>/dev/null; then
  ui_error "需要 Xcode Command Line Tools"
  ui_dim "安装: xcode-select --install"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  ui_error "需要 Python 3"
  exit 1
fi

ui_success "环境检查通过"

# ── 2. Create install directory ──
INSTALL_DIR="$HOME/.timetosleep"
ui_step "创建安装目录: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/src"

# ── 3. Compile Swift overlay ──
ui_step "编译锁屏覆盖层..."
bash "$SCRIPT_DIR/src/overlay/build.sh" "$INSTALL_DIR/bin/zzz-overlay"
ui_success "编译完成"

# ── 4. Copy files ──
ui_step "安装文件..."
cp -r "$SCRIPT_DIR/lib/"* "$INSTALL_DIR/lib/"
cp -r "$SCRIPT_DIR/src/"* "$INSTALL_DIR/src/"
cp "$SCRIPT_DIR/bin/zzz" "$INSTALL_DIR/bin/zzz"
chmod +x "$INSTALL_DIR/bin/zzz"
chmod +x "$INSTALL_DIR/src/daemon.sh"

# ── 5. Create symlink ──
ui_step "创建 zzz 命令..."

LINKED=false

# Try /usr/local/bin first
if [ -w "/usr/local/bin" ]; then
  ln -sf "$INSTALL_DIR/bin/zzz" "/usr/local/bin/zzz"
  ui_success "已安装到 /usr/local/bin/zzz"
  LINKED=true
fi

# Fallback: add to PATH via shell profile
if [ "$LINKED" = false ]; then
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [ -f "$rc" ]; then
      if ! grep -q '.timetosleep/bin' "$rc" 2>/dev/null; then
        echo '' >> "$rc"
        echo '# TimeToSleep' >> "$rc"
        echo 'export PATH="$HOME/.timetosleep/bin:$PATH"' >> "$rc"
      fi
      LINKED=true
      break
    fi
  done
  # Always ensure .zshrc exists on macOS
  if [ "$LINKED" = false ]; then
    echo '# TimeToSleep' >> "$HOME/.zshrc"
    echo 'export PATH="$HOME/.timetosleep/bin:$PATH"' >> "$HOME/.zshrc"
    LINKED=true
  fi
  export PATH="$HOME/.timetosleep/bin:$PATH"
  ui_success "已添加到 PATH（重启终端或 source ~/.zshrc 生效）"
fi

# ── 6. Done ──
ui_blank
ui_box "$(printf '%b\n' \
  "${C_GREEN}${BOLD}安装完成！${RESET}" \
  "" \
  "运行 ${BOLD}zzz init${RESET} 开始设置你的早睡契约")"
ui_blank
