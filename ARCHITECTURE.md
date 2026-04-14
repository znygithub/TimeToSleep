# TimeToSleep 代码架构

本文档面向接手项目的开发者，帮你快速理解整体结构和各模块的职责。

## 目录结构

```
TimeToSleep/
├── bin/
│   ├── zzz                 # CLI 主入口，所有用户命令的路由
│   └── zzz-overlay         # 预编译的 Swift 全屏锁屏二进制（arm64 + x86_64）
├── lib/
│   ├── config.sh           # 配置读写（~/.timetosleep/config.json）
│   ├── ui.sh               # 终端 UI 工具包（颜色、框线、交互式输入组件）
│   ├── schedule.sh         # launchd 定时任务的注册 / 注销 / 更新
│   └── stats.sh            # 打卡记录和连续天数统计
├── src/
│   ├── init.sh             # Onboarding 交互流程（zzz init）
│   ├── daemon.sh           # 守护进程：风力 → 锁定 → 唤醒 三阶段编排
│   ├── media.sh            # 媒体控制（暂停播放器、音量渐降）
│   ├── brightness.sh       # 屏幕亮度控制（渐暗、保存/恢复）
│   └── overlay/
│       ├── LockScreen.swift # 全屏锁屏覆盖层源码
│       └── build.sh        # 编译脚本（仅开发者需要）
├── install.sh              # 安装脚本
├── README.md               # 产品说明（中文）
└── README_EN.md            # 产品说明（英文）
```

## 运行时数据

安装后所有运行时数据存储在 `~/.timetosleep/`：

```
~/.timetosleep/
├── bin/                    # 可执行文件副本
├── lib/                    # 库文件副本
├── src/                    # 源脚本副本
├── config.json             # 用户配置
├── stats.json              # 打卡历史
├── saved_brightness        # 锁定前保存的屏幕亮度（临时）
├── saved_volume            # 锁定前保存的音量（临时）
├── skip_tonight            # 今晚跳过标记（临时）
└── daemon.log              # 守护进程日志
```

## 核心流程

### 1. 安装（install.sh）

```
install.sh
  ├── 检查 macOS 环境
  ├── 创建 ~/.timetosleep/ 目录
  ├── 复制所有文件（含预编译的 zzz-overlay）
  └── 添加 zzz 到 PATH（/usr/local/bin 或写入 .zshrc）
```

不需要编译，不需要 Xcode。二进制文件直接从仓库复制。

### 2. Onboarding（src/init.sh）

`zzz init` 触发，交互式收集用户设置：

```
init.sh
  ├── 展示欢迎界面
  ├── 收集设置（睡觉时间、起床时间、启用日、提醒提前量、锁屏文字）
  ├── 展示契约摘要
  ├── 要求用户输入承诺语确认（3 次重试机会）
  ├── 写入 config.json
  ├── 初始化 stats.json
  └── 调用 schedule.sh 注册 launchd 定时任务
```

### 3. 每日触发（daemon.sh）—— 最核心的流程

launchd 在每天 `(bedtime - winddown)` 时间点启动 daemon.sh，它编排三个阶段：

```
daemon.sh
  │
  ├── 前置检查
  │   ├── 读取 config.json
  │   ├── 今天是否在启用日？否 → 退出
  │   └── 是否有 skip_tonight 标记？是 → 记录跳过，退出
  │
  ├── 阶段一：Wind-down（渐进提醒）
  │   ├── 保存当前亮度和音量
  │   ├── t-30min: 系统通知 + 轻微降亮度
  │   ├── t-20min: 再次通知 + 继续降亮度
  │   ├── t-10min: 警告通知 + 降音量 + 大幅降亮度
  │   └── 等待到精确的 bedtime
  │
  ├── 阶段二：Lockdown（完全锁定）
  │   ├── media.sh: 暂停所有媒体播放器，静音
  │   ├── brightness.sh: 亮度降到最低
  │   ├── 启动 zzz-overlay（全屏覆盖层）
  │   ├── 如果 overlay 被杀掉 → 2 秒后自动重启（循环）
  │   └── 等待到起床时间 → overlay 自动退出
  │
  └── 阶段三：Wake-up（恢复）
      ├── 恢复亮度和音量
      ├── 发送早安通知（含连续天数）
      └── 记录今日为 "completed"
```

### 4. 全屏覆盖层（src/overlay/LockScreen.swift）

一个独立的 Swift 程序，没有依赖 Xcode 项目，直接 `swiftc` 编译。

架构很简单，四个组件：

| 组件 | 职责 |
|------|------|
| `SleepConfig` | 从 config.json 读取锁屏文字和起床时间 |
| `LockWindowController` | 为每个显示器创建一个全屏窗口，管理生命周期 |
| `LockScreenView` | 渲染锁屏界面（时钟、承诺语、呼吸动画） |
| `LockAppDelegate` | 拦截键盘事件，阻止退出 |

关键技术点：
- 窗口层级 = `CGShieldingWindowLevel + 1`，在几乎所有窗口之上
- 每 2 秒 keepAlive 循环强制窗口置顶
- 监听 `didChangeScreenParametersNotification`，外接显示器变化时自动重建窗口
- 每秒检查当前时间，到达起床时间自动 `exit(0)`

### 5. CLI 路由（bin/zzz）

所有用户命令的入口，结构是一个简单的 case 路由：

```
zzz [command] [args]
  │
  ├── (空)         → cmd_default()    显示今晚状态
  ├── init         → cmd_init()       调用 src/init.sh
  ├── status       → cmd_status()     详细统计
  ├── config       → cmd_config()     查看/修改设置
  ├── tonight off  → cmd_tonight()    跳过今晚
  ├── log          → cmd_log()        历史记录
  ├── test         → cmd_test()       启动 overlay 10 秒
  ├── uninstall    → cmd_uninstall()  卸载
  └── help         → cmd_help()       帮助
```

## 模块依赖关系

```
bin/zzz ──────────┬── lib/config.sh    ← 被几乎所有模块依赖
                  ├── lib/ui.sh        ← 被所有面向用户的模块依赖
                  ├── lib/stats.sh     ← 依赖 config.sh
                  └── lib/schedule.sh  ← 依赖 config.sh

src/init.sh ──────┬── lib/ui.sh
                  ├── lib/config.sh
                  ├── lib/stats.sh
                  └── lib/schedule.sh

src/daemon.sh ────┬── lib/config.sh
                  ├── lib/stats.sh
                  ├── src/media.sh     ← 无依赖，纯 osascript 调用
                  ├── src/brightness.sh ← 无依赖，纯 python3/CoreDisplay 调用
                  └── bin/zzz-overlay  ← 独立二进制，通过进程启动

bin/zzz-overlay ──── ~/.timetosleep/config.json（直接读文件，不依赖 shell 库）
```

## 技术选型说明

| 选择 | 原因 |
|------|------|
| Shell 脚本（非 Python/Node） | 零依赖，macOS 自带 bash。终端产品用终端语言，天然契合 |
| Swift 做锁屏（非纯终端） | 纯终端窗口可以被轻易关闭。需要 NSWindow 的窗口层级控制才能实现真正的"锁死" |
| 预编译通用二进制 | 用户不需要装 Xcode。arm64 + x86_64 通用，覆盖所有 Mac |
| launchd（非 cron） | macOS 原生调度器，支持用户级 agent，系统休眠唤醒后自动补触发 |
| python3 做 JSON 和亮度控制 | macOS 自带 python3。jq 不是所有机器都有，python3 作为 fallback 更可靠 |
| osascript 做媒体控制 | 可以直接控制 Spotify、Apple Music 等原生应用，无需第三方库 |

## 想改代码？从这里开始

- **改锁屏界面的样式**：`src/overlay/LockScreen.swift` → `LockScreenView.setupUI()`，改完后运行 `src/overlay/build.sh` 重新编译
- **加新命令**：`bin/zzz` 底部的 case 路由加一条，写对应的 `cmd_xxx()` 函数
- **改 onboarding 流程**：`src/init.sh` → `run_init()`
- **改风力/锁定行为**：`src/daemon.sh` → `wind_down()` 和 `lockdown()`
- **改终端 UI 组件**：`lib/ui.sh`，所有交互组件都在这里
- **改定时调度逻辑**：`lib/schedule.sh`，生成 launchd plist 的地方
