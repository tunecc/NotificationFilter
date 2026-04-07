# Shortcuts Timeout Blocker

一个基于 roothide Theos 的 iOS 越狱 tweak。

它的目标很单一：**只屏蔽一类特定的快捷指令失败通知**，避免把整个 `Shortcuts` 的通知流量一刀切掉。

当前版本只拦截以下通知：

- `sectionIdentifier == "com.apple.shortcuts"`
- 标题精确等于 `Automation failed`
- 正文包含 `Remote execution timed out`

也就是说，它不会像原始样本那样用宽松关键词去吞掉所有“自动化”相关通知，而是把范围收缩到一个明确、可解释、可验证的失败场景。

---

## 1. 项目背景

这个工程不是凭空设计出来的，而是从一个现成样本逆向收敛出来的。

样本包：

- `../屏蔽快捷指令自动化通知 - rootless-1.0.1-iphoneos-arm64.deb`

我们先对原始样本做了静态分析，结论是：

1. 它是一个标准的 `MobileSubstrate` tweak
2. 只注入 `SpringBoard`
3. hook 的是 `NCNotificationDispatcher` 的 `postNotificationWithRequest:`
4. 过滤条件比较宽，只要：
   - `sectionIdentifier == com.apple.shortcuts`
   - 通知文案里包含 `自动化` 或 `automation`
5. 命中后就直接吞掉通知，不再调用原始实现

原始分析报告见：

- [`../analysis/20260406-222616-jb-shortcuts-notify/reverse-report.md`](../analysis/20260406-222616-jb-shortcuts-notify/reverse-report.md)

这个项目就是在那份逆向结论之上，做了一个**更精确、更保守**的版本。

---

## 2. 这个项目解决什么问题

在某些自动化场景里，`Shortcuts` 会反复推送类似下面这种失败通知：

- 标题：`Automation failed`
- 正文示例：`"At 22:30, daily" encountered an error: Remote execution timed out`

如果目标只是消掉这类“远程执行超时”的失败提醒，那么直接复用原始样本的逻辑会有两个问题：

1. 过滤范围太大
2. 可能误伤其他仍然有价值的快捷指令通知

所以本项目把过滤条件改成了三重命中：

1. 通知来自 `com.apple.shortcuts`
2. 标题必须是 `Automation failed`
3. 正文必须包含 `Remote execution timed out`

这样做的目的不是“尽量多拦”，而是“只拦明确目标”。

---

## 3. 当前实现思路

实现文件在：

- [`Tweak.xm`](./Tweak.xm)

核心策略：

1. hook `NCNotificationDispatcher`
2. 拦截 `postNotificationWithRequest:`
3. 从 `request` 里读取：
   - `sectionIdentifier`
   - `content`
   - `title/header`
   - `body/message/subtitle`
4. 只有在三重条件全部命中时才 `return`
5. 其余情况全部 `%orig`

这里保留了少量字段兼容逻辑，是因为不同 iOS 版本的通知内容对象字段名可能不完全一致。

当前源码里做了以下兼容读取：

- 标题候选：`title`、`header`
- 标题回退：如果 `message` 本身就等于 `Automation failed`，也把它视为标题
- 正文候选：`body`、`message`、`subtitle`

这部分逻辑在这里：

- [`Tweak.xm`](./Tweak.xm#L42)

---

## 4. 和原始样本的区别

### 原始样本

原始样本本质上是一个“文本包含式过滤器”：

- 只要来自 `com.apple.shortcuts`
- 只要文案包含 `自动化` 或 `automation`
- 就吞掉

优点：

- 实现很小
- 命中率高

缺点：

- 容易误伤其他快捷指令通知
- 对文案语言和措辞非常敏感

### 当前项目

当前项目是一个“精确失败类型过滤器”：

- 只匹配固定标题
- 只匹配固定错误片段
- 不尝试概括成“所有自动化失败”

优点：

- 误伤面更小
- 行为更可预期
- 后续扩展时更容易按规则分层

代价：

- 覆盖面更窄
- 如果 Apple 改了标题或文案，规则就会失效

---

## 5. 工程结构

```text
ShortcutsTimeoutBlocker/
├── Makefile
├── README.md
├── ShortcutsTimeoutBlocker.plist
├── Tweak.xm
├── control
└── packages/
    ├── com.tune.shortcutstimeoutblocker_0.0.1-1+debug_iphoneos-arm64e.deb
    └── com.tune.shortcutstimeoutblocker_0.0.1_iphoneos-arm64e.deb
```

关键文件说明：

- [`Makefile`](./Makefile)
  - roothide 构建配置
  - 指定 `THEOS_PACKAGE_SCHEME ?= roothide`
  - 指定 `INSTALL_TARGET_PROCESSES = SpringBoard`
  - 把 clang 模块缓存定向到工程内，避免写主目录缓存失败

- [`control`](./control)
  - 包标识：`com.tune.shortcutstimeoutblocker`
  - 版本：`0.0.1`

- [`ShortcutsTimeoutBlocker.plist`](./ShortcutsTimeoutBlocker.plist)
  - 只注入 `com.apple.springboard`

- [`Tweak.xm`](./Tweak.xm)
  - 实际的通知过滤逻辑

---

## 6. 构建方式

本项目使用：

- roothide Theos：`/Users/tune/Develop/theos-roothide`
- Xcode iPhoneOS SDK

构建命令：

```bash
cd /Users/tune/Downloads/untitled_folder/ShortcutsTimeoutBlocker
make clean package THEOS='/Users/tune/Develop/theos-roothide' THEOS_PACKAGE_SCHEME=roothide
```

正式包构建：

```bash
cd /Users/tune/Downloads/untitled_folder/ShortcutsTimeoutBlocker
make clean package FINALPACKAGE=1 THEOS='/Users/tune/Develop/theos-roothide' THEOS_PACKAGE_SCHEME=roothide
```

当前已经实际生成的包：

- [`packages/com.tune.shortcutstimeoutblocker_0.0.1_iphoneos-arm64e.deb`](./packages/com.tune.shortcutstimeoutblocker_0.0.1_iphoneos-arm64e.deb)

---

## 7. 打包结果

实际打包复核结果：

- Package: `com.tune.shortcutstimeoutblocker`
- Version: `0.0.1`
- Architecture: `iphoneos-arm64e`

包内文件：

- `Library/MobileSubstrate/DynamicLibraries/ShortcutsTimeoutBlocker.dylib`
- `Library/MobileSubstrate/DynamicLibraries/ShortcutsTimeoutBlocker.plist`

注意：

- roothide Theos 最终包架构落成 `iphoneos-arm64e`
- 这是实际打包结果，不是 README 中的理论描述

---

## 8. 逆向记录摘要

这部分是后续继续改 tweak 时最有价值的经验。

### 8.1 为什么 hook SpringBoard

原始样本的注入 `plist` 只过滤到：

- `com.apple.springboard`

说明通知是在 SpringBoard 派发链路上被截住的，而不是在 `Shortcuts` App 进程内部被抹掉。

这个判断非常关键，因为它决定了：

- 不需要注入 `com.apple.shortcuts`
- 不需要改快捷指令 App 本身
- 不需要碰设置或偏好项

### 8.2 为什么盯 `NCNotificationDispatcher`

逆向样本时确认到关键类和方法是：

- `NCNotificationDispatcher`
- `postNotificationWithRequest:`

这意味着 tweak 的介入位置足够靠后：

- 通知对象已经构造完成
- section / title / body 这些信息已经具备
- 可以直接做内容级过滤

这个位置的好处是实现简单、改动面小。

代价是它依赖私有类和私有调用链。

### 8.3 原始样本给出的经验

原始样本虽然简单，但它证明了三件事：

1. `com.apple.shortcuts` 是一个可用的 section 标识
2. `request -> content -> message` 这条读取链路在目标系统上是存在的
3. 用 `postNotificationWithRequest:` 做吞通知是可行的

这三个点让我们在做新项目时，不需要从 0 开始猜注入点。

### 8.4 这次改造的经验

从“宽泛关键词过滤”改成“精确失败类型过滤”时，最重要的经验是：

- 不要一开始就追求“泛化”
- 先用你能证明的最小规则把目标场景吃住

原始样本能说明“automation / 自动化”可以用来粗略识别；
但你的真实目标其实更窄，是只屏蔽：

- `Automation failed`
- `Remote execution timed out`

所以最终实现里，我们没有继续沿用“automation 关键词”。

---

## 9. 这次实际遇到的构建坑

构建时出现过一个不是代码逻辑问题、而是环境问题的错误：

```text
unable to open output file '/Users/tune/.cache/clang/ModuleCache/...': Operation not permitted
```

根因：

- clang 默认想把模块缓存写到用户主目录的 `.cache`
- 当前执行环境不允许写那个路径

处理方式：

- 在 [`Makefile`](./Makefile#L7) 里显式增加：

```make
MODULE_CACHE_DIR = $(CURDIR)/.cache/clang/ModuleCache
ShortcutsTimeoutBlocker_CFLAGS = -fobjc-arc -fmodules-cache-path=$(MODULE_CACHE_DIR)
```

经验：

- 如果构建环境受沙箱或权限限制，先查缓存和临时目录写入点
- 这类问题往往不是 tweak 源码本身有错

---

## 10. 如何验证这个 tweak 是否仍然“只拦这一类通知”

最少做这几类检查：

### 静态检查

1. 看注入 `plist` 是否只包含 `com.apple.springboard`
2. 看打包后的 dylib 字符串是否包含：
   - `com.apple.shortcuts`
   - `Automation failed`
   - `Remote execution timed out`
3. 看源码是否仍然保留 `%orig`

### 设备侧人工检查

1. 制造一个会产生 `Remote execution timed out` 的自动化失败
2. 确认该通知不再出现
3. 再制造一个不同类型的快捷指令通知
4. 确认它仍然出现

如果第 4 步也消失了，说明过滤条件写宽了。

---

## 11. 后续可以怎么扩展

如果以后要继续做这个方向，建议按“规则表”而不是“继续堆 if”去演进。

### 可以考虑的扩展方向

1. 支持更多失败类型
   - 例如把不同错误片段拆成独立规则

2. 支持本地化
   - 中文标题
   - 其他系统语言的错误正文

3. 支持运行时调试日志
   - 先只在 debug 构建打开
   - 方便观察真实 title/body 字段长什么样

4. 支持偏好配置
   - 允许用户决定要屏蔽哪些失败类型

### 不建议立刻做的事

1. 一开始就做“屏蔽所有快捷指令失败通知”
2. 一开始就做复杂 UI 设置页
3. 在没掌握更多通知样本前就做模糊匹配

---

## 12. 已知边界

这个项目目前的边界很明确：

1. 它依赖私有类：
   - `NCNotificationDispatcher`

2. 它依赖私有通知对象结构：
   - `sectionIdentifier`
   - `content`
   - `title/header`
   - `body/message/subtitle`

3. 它依赖当前英文文案：
   - `Automation failed`
   - `Remote execution timed out`

所以只要 iOS 大版本改了通知结构或文案，这个 tweak 就可能失效。

这不是实现失误，而是这类私有链路 hook 天然存在的维护成本。

---

## 13. 相关文件

项目内：

- [`Tweak.xm`](./Tweak.xm)
- [`Makefile`](./Makefile)
- [`control`](./control)
- [`ShortcutsTimeoutBlocker.plist`](./ShortcutsTimeoutBlocker.plist)

逆向资料：

- [`../analysis/20260406-222616-jb-shortcuts-notify/reverse-report.md`](../analysis/20260406-222616-jb-shortcuts-notify/reverse-report.md)

构建与验证记录：

- [`../outputs/runtime/vibe-sessions/20260407-125548-shortcuts-timeout-blocker/phase-build-and-verify.json`](../outputs/runtime/vibe-sessions/20260407-125548-shortcuts-timeout-blocker/phase-build-and-verify.json)

---

## 14. 一句话总结

这个项目的价值不在于“写了一个能吞通知的 tweak”，而在于把一个宽泛的逆向样本收敛成了一个**行为边界清晰、误伤面更小、后续更容易继续演进**的工程起点。
