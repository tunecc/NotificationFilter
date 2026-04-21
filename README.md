# Shortcuts Timeout Blocker

一个基于 Theos / Logos 的 iOS 越狱 tweak，用来拦截 `Shortcuts` 的英文 `Automation failed` 通知。

## 当前行为

只在以下条件全部满足时屏蔽通知：

1. 通知分区为 `com.apple.shortcuts`
2. 兼容读取到的任一文本字段精确匹配 `Automation failed`

兼容读取的字段：

- `title`
- `header`
- `body`
- `message`
- `subtitle`

这意味着它不再依赖正文里的 `Remote execution timed out`，也不再按宽松关键词吞掉所有自动化通知。

## Hook 路径

当前实现同时覆盖两条路径：

1. `NCNotificationDispatcher::postNotificationWithRequest:`
2. `BBServer::publishBulletin:destinations:` 及兼容签名

这样做的原因是：仅依赖单一的 `NCNotificationDispatcher` 路径，在不同 iOS 版本上不够稳。

## 构建

默认构建 scheme：

- `rootless`

默认构建架构：

- `arm64`
- `arm64e`

正式打包：

```bash
cd /Users/tune/Downloads/快捷指令通知逆向/ShortcutsTimeoutBlocker
make clean package FINALPACKAGE=1 THEOS='/Users/tune/Develop/theos-roothide' THEOS_PACKAGE_SCHEME=rootless
```

如需 roothide 包：

```bash
cd /Users/tune/Downloads/快捷指令通知逆向/ShortcutsTimeoutBlocker
make clean package FINALPACKAGE=1 THEOS='/Users/tune/Develop/theos-roothide' THEOS_PACKAGE_SCHEME=roothide
```

## 关键文件

- `Makefile`: 构建配置
- `Tweak.xm`: 运行时 hook 与匹配逻辑
- `ShortcutsTimeoutBlocker.plist`: 注入目标，仅 `SpringBoard`
- `control`: 包元数据

## 已知边界

- 本项目只做本地静态验证，不包含设备侧实机验证
- 私有类与私有方法在未来 iOS 版本仍可能变化
- 当前只匹配英文 `Automation failed`，不覆盖其他语言文案
