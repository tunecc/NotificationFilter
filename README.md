# Notification Filter

一个基于 Theos / Logos 的 iOS 越狱插件，用来在 `SpringBoard` 中按规则过滤通知，并在系统“设置”中提供完整配置界面。

## 功能概览

- 全局开关
- 全局规则：包含 / 排除 / 正则
- 单应用规则：对指定应用单独配置包含 / 排除 / 正则
- 规则组合：全局规则与单应用规则叠加，排除规则优先放行
- 过滤日志：持久化最近 500 条被拦截通知，可在设置中查看和清空

## 工程结构

- `NotificationFilterTweak/`
  - 运行时 hook
  - 通知抽取
  - 规则引擎
  - 过滤日志写入
- `NotificationFilterPrefs/`
  - 设置页入口
  - 全局规则页
  - 应用规则列表与单应用规则页
  - 日志查看页
- `Shared/`
  - 偏好读写
  - 日志存储
- `layout/Library/PreferenceLoader/Preferences/`
  - PreferenceLoader 入口 plist

## 运行时行为

当前实现继续覆盖两条通知入口：

1. `NCNotificationDispatcher::postNotificationWithRequest:`
2. `BBServer::publishBulletin:destinations:` 及兼容签名

通知会被抽取为统一模型，再按以下顺序处理：

1. 主开关关闭 -> 直接放行
2. 收集全局规则和当前应用规则
3. 任一作用域命中排除规则 -> 放行
4. 任一作用域命中包含或正则 -> 拦截并写日志
5. 否则放行

## 构建

默认构建 scheme：

- `roothide`

默认构建架构：

- `arm64`
- `arm64e`

打包命令：

```bash
cd /Users/tune/Documents/Scripts/Jailbreak/通知过滤/NotificationFilter
make clean package THEOS='/Users/tune/Develop/theos-roothide' THEOS_PACKAGE_SCHEME=roothide
```

生成的包位于：

- `packages/com.tune.notificationfilter_*_iphoneos-arm64e.deb`（roothide 优先）

常用命令：

```bash
# roothide 调试包
make package-debug-roothide THEOS='/Users/tune/Develop/theos-roothide'

# roothide 调试安装
make install-debug-roothide THEOS='/Users/tune/Develop/theos-roothide'

# roothide 正式包
make package-roothide THEOS='/Users/tune/Develop/theos-roothide'

# roothide 正式安装
make install-roothide THEOS='/Users/tune/Develop/theos-roothide'
```

## 依赖

运行依赖：

- `mobilesubstrate`
- `preferenceloader`

设置页中的应用检测当前使用私有 `LSApplicationWorkspace` / `LSApplicationProxy`，不依赖 `Cephei Tweak Support`。
日志路径使用 roothide 的 `jbroot(...)` 路径转换，在非 roothide 构建下会自动回退到 rootless 路径转换。

## 已知边界

- 本项目只做了本地编译和打包验证，未做设备实机验证
- 设置 bundle 当前通过动态解析 `Preferences` 相关符号完成链接，构建会出现 `dynamic_lookup` 警告
- 私有类、私有方法和私有图标 API 在未来 iOS 版本可能变化
