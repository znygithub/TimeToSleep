# TimeToSleep

一个跑在终端里的早睡承诺装置。你和自己签一份契约，电脑替你守住底线。

[English](README_EN.md)

## 它做什么

- **渐进式提醒**：睡前逐步降低屏幕亮度、降低音量、发送通知
- **全面锁定**：全屏覆盖所有显示器，暂停媒体，静音
- **无法逃出**：锁定后到起床时间前，不能解锁
- **打卡记录**：记录你的早睡连续天数和历史

## 安装

```bash
git clone https://github.com/znygithub/TimeToSleep.git
cd TimeToSleep
bash install.sh
```

需要 macOS、Xcode Command Line Tools（`xcode-select --install`）和 Python 3。

## 开始使用

```bash
zzz init
```

交互式引导你完成设置：几点睡、几点起、哪几天启用，以及写一句话给深夜的自己。

## 命令

```
zzz              # 今晚状态 + 倒计时
zzz status       # 详细统计
zzz config       # 查看设置
zzz config bedtime 22:30   # 修改睡觉时间（提前=立即生效，推迟=24h冷静期）
zzz tonight off  # 跳过今晚（需要说明原因）
zzz log          # 历史记录
zzz test         # 测试锁屏（10 秒）
zzz uninstall    # 卸载
```

## 产品哲学

- **提前睡觉即时生效，推迟睡觉需要 24 小时冷静期。** 防止你在深夜头脑发热把时间往后改。
- **锁定是绝对的。** 到起床时间前无法解除。唯一的出路是重启电脑——而这足够的摩擦力能挡住大多数深夜刷手机的冲动。
- **卸载是自由的，但会让你反思。** 卸载前展示你的连续天数和统计。不挽留，只是让你看一眼你积累了什么。

## 技术实现

- `zzz` CLI（Shell 脚本）负责所有交互
- Swift 编译的全屏覆盖层（安装时编译，支持多显示器）
- macOS `launchd` 定时调度
- `osascript` 控制媒体和系统通知
- 配置存储在 `~/.timetosleep/`

## 许可

MIT
