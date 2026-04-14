# 踩坑合集

## 1. macOS bash 3.2 + 中文退格删不动

macOS 自带 bash 3.2，内核行规程不支持 `iutf8`（Linux 专属）。`read -r` 走 canonical 模式，退格按字节删而非按字符删——中文 UTF-8 一个字三字节，删几下就卡死了。

**解法：** `read -e -r` 启用 readline，readline 自己处理 UTF-8，不依赖内核。

## 2. read -e 退格会吃掉 prompt

用 `printf` 先打印带颜色的 prompt 再 `read -e`，readline 不知道 prompt 的存在，退格会把 `›` 都删掉。

**解法：** 用 `read -e -r -p "$prompt"` 把 prompt 交给 readline 管理，ANSI 转义码用 `\001`..`\002` 包裹告诉 readline 这些是不可见字符：

```bash
_rl() { printf '\001%b\002' "$1"; }
local prompt="  $(_rl '\033[38;5;245m')›$(_rl '\033[0m') "
read -e -r -p "$prompt" answer
```

## 3. set -e 下子命令返回非零直接退出

`_parse_time` 解析失败 `return 1`，外层 `parsed=$(_parse_time "$input")` 拿到非零退出码，`set -e` 直接杀掉整个脚本——`while true` 重试循环根本走不到。

**解法：** `parsed=$(_parse_time "$input") || true`

## 4. install.sh 结束后用户不知道下一步

装完只打印"请运行 `zzz init`"，用户（或 AI）跑完安装脚本后什么也没弹出来，不知道接下来该干嘛。

**解法：** 安装末尾用 `osascript` 弹一个新 Terminal 窗口跑 `zzz init`，不管谁触发安装都能看到 onboarding：

```bash
osascript -e "
tell application \"Terminal\"
    activate
    do script \"'$INSTALL_DIR/bin/zzz' init\"
end tell
"
```
