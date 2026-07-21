# 规则卡片浅色层次感设计

## 背景

`NotificationFilterPrefs/NFPRulesListEditorController` 使用 `UITableViewStyleInsetGrouped`，并在 `viewDidLoad` 中将 `tableView.backgroundColor` 设为 `systemGroupedBackgroundColor`。规则行由 `NFPRuleCardCell` 以卡片形式绘制。

当前卡片在初始化时使用：

```objc
cardView.backgroundColor = [UIColor secondarySystemBackgroundColor];
```

在浅色模式下，`systemGroupedBackgroundColor` 与 `secondarySystemBackgroundColor` 都偏灰，页面底与卡片面几乎同色，圆角与阴影不足以形成清晰层次，用户观感为「已经添加的规则背景是灰色的，没有层次感」。

## 目标

- 浅色模式下，已添加规则卡片相对列表底色明显更亮（白/近白），形成「白卡片浮在灰底上」的层次。
- 深色模式下卡片仍相对列表底抬升一层，不糊成一片。
- 继续使用系统 semantic color，随系统外观自动适配。
- 不改变规则列表的交互、布局、编辑/多选行为。

## 非目标

- 不调整卡片圆角、边框宽度、阴影参数（若真机仍偏平，另开任务做外观微调）。
- 不改动 `NFPRulesListEditorController` 的列表背景色。
- 不引入自定义色板或新 UI 组件。
- 不修改其他列表页或非 `NFPRuleCardCell` 的 cell 样式。

## 当前问题

层次问题来自颜色语义不匹配，而非缺少边框/阴影：

| 层 | 当前颜色 | 浅色观感 |
|---|---|---|
| 列表底 | `systemGroupedBackgroundColor` | 浅灰 |
| 卡片面 | `secondarySystemBackgroundColor` | 也是浅灰 |

Grouped 列表上的表面应使用 Grouped 系列的 secondary 色：`secondarySystemGroupedBackgroundColor`。在浅色下该色接近白色，与 grouped 底色对比清晰；深色下系统会提供抬升后的表面色。

现有 `updateCardAppearance` 只维护边框与阴影，不重设 `cardView.backgroundColor`。System dynamic color 在 trait 变化时通常会自动解析，但为避免复用路径或未来改动导致背景被写死后不再更新，设计要求在外观更新路径中显式保持同一 semantic color。

## 设计概览

采用最小改动：只修正 `NFPRuleCardCell` 的卡片背景语义色。

原则：

- 列表底继续由控制器负责（已是 `systemGroupedBackgroundColor`）。
- 卡片面使用 `secondarySystemGroupedBackgroundColor`，与 grouped 列表配套。
- 边框、阴影、圆角、禁用透明度等现有逻辑保持不变。

## 变更范围

仅 `NotificationFilterPrefs/NFPRuleCardCell.m`：

1. **初始化**：将 `cardView.backgroundColor` 从 `secondarySystemBackgroundColor` 改为 `secondarySystemGroupedBackgroundColor`。
2. **外观更新**：在 `updateCardAppearance` 中同样设置  
   `self.cardView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];`  
   保证 `traitCollectionDidChange` 与初始化路径一致。

不修改：

- `NFPRuleCardCell.h` 公共接口
- `NFPRulesListEditorController` 及其他控制器
- 本地化文案、资源、偏好键

## 页面表现

| 模式 | 列表底 | 卡片面 |
|------|--------|--------|
| 浅色 | `systemGroupedBackground`（浅灰） | `secondarySystemGroupedBackground`（白/近白） |
| 深色 | `systemGroupedBackground`（深底） | `secondarySystemGroupedBackground`（抬升表面） |

其余表现不变：

- 禁用规则：`cardView.alpha = 0.75`，标题用 secondary label 色
- 编辑多选：勾选按钮与 leading 缩进逻辑不变
- 验证标签：绿/红半透明底不变
- 边框与浅色阴影：`updateCardAppearance` 现有逻辑不变

## 兼容性

- `secondarySystemGroupedBackgroundColor` 为 iOS 13+ API，与项目内已有 `systemGroupedBackgroundColor`、`secondarySystemBackgroundColor` 等用法一致。
- 无需版本分支或 fallback。

## 验证

真机或模拟器 Preference UI（有已添加规则时）：

1. **浅色**：进入已添加拦截规则列表，卡片应明显白于页面底，层次清晰。
2. **深色**：同一列表中卡片与底色可区分，不发灰糊成一片。
3. **交互回归**：开关启用/禁用、编辑多选、验证状态标签显示正常。
4. **外观切换**（可选）：系统浅/深切换后卡片背景仍正确。

构建门禁：对改动涉及的 Preference 包执行既有 package 命令（如 `make package-debug-rootless`）通过即可；本次无自动化 UI 测试。

## 实现备注

- 单文件、语义色替换为主，实现计划可极短。
- 若实现后浅色层次仍不足，再单独评估阴影/边框微调，不在本规格范围内扩大范围。
