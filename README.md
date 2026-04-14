# TimeToSleep

> 没有什么事比睡觉更重要。
>
> 早睡是好睡眠的前提，而大多数人晚睡的原因就是放不下电脑。但让人主动远离电脑，本身就是反人性的——那不如换个思路：到点了，电脑自己锁死。
>
> 不需要你有多自律，不需要你"再看五分钟"。时间到了，屏幕黑了，今天就结束了。这才是顺应人性的做法。

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

需要 macOS 11+，无需安装其他依赖。

## 开始使用

```bash
zzz init
```

交互式引导你完成设置：几点睡、几点起、哪几天启用，以及写一句话给深夜的自己。

## 命令

```
zzz              # 今晚状态 + 倒计时
zzz status       # 详细统计
zzz config       # 查看 / 修改设置
zzz tonight off  # 跳过今晚（需要说明原因）
zzz log          # 历史记录
zzz test         # 测试锁屏（10 秒）
zzz uninstall    # 卸载
```

## 技术实现

- `zzz` CLI（Shell 脚本）负责所有交互
- Swift 编译的全屏覆盖层（安装时编译，支持多显示器）
- macOS `launchd` 定时调度
- `osascript` 控制媒体和系统通知
- 配置存储在 `~/.timetosleep/`

## 许可

MIT
