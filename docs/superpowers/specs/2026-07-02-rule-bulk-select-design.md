# 规则批量选择与分区选词设计

日期：2026-07-02

## 背景

当前规则列表已经支持进入编辑态后逐条选择并删除规则。用户在单个 App 中维护大量关键词时，逐条选择成本较高，需要增加全选与取消全选能力。

选词页当前按通知字段分区展示词语按钮，例如标题、副标题、正文。用户需要在每个分区标题右侧增加分区全选能力，并且跨分区选词时不能合并为一条“全部文本”规则。

## 目标

- 规则列表编辑态支持一键全选和取消全选。
- 批量删除继续复用现有删除确认流程。
- 选词页每个分区支持单独全选和取消全选。
- 保存选词结果时按分区生成规则；标题和正文同时选中时生成两条规则，而不是一条全部文本规则。
- 保持现有规则数据结构、作用域字段和本地化体系兼容。

## 非目标

- 不新增新的规则存储格式。
- 不改变规则匹配引擎行为。
- 不重做选词页整体布局。
- 不为批量选择引入新的工具栏或复杂编辑模式。

## 现有实现依据

- `NotificationFilterPrefs/NFPRulesListEditorController.m` 已维护 `editingRules` 和 `selectedRuleIdentifiers`，并已有 `deleteSelectedRules`。
- `NotificationFilterPrefs/NFPNotificationRuleTokenPickerController.m` 通过 `tokenSections` 渲染标题、副标题、正文等分区。
- `NotificationFilterPrefs/NFPNotificationRuleTokenBuilder.m` 当前把跨分区选词合并为一条规则，并在混合 scope 时设置为 `NFRuleScopeAll`。
- `NotificationFilterPrefs/Resources/*/Localizable.strings` 已有通用按钮文案和规则页文案。

## 交互设计

### 规则列表编辑态

进入编辑态后：

- 左上角按钮显示 `全选`。
- 如果当前所有规则都已选中，左上角按钮显示 `取消全选`。
- 右上角继续显示现有 `删除(n)` 按钮。
- 未选中任何规则时，删除按钮禁用。
- 点击删除后继续弹出现有确认框。
- 删除确认成功后清空选择并退出编辑态。

空规则列表不提供全选能力；如果用户退出编辑态，清空所有选择。

### 选词页分区全选

每个有词语的分区使用横向标题行：

- 左侧显示分区名，例如 `标题`、`副标题`、`正文`。
- 右侧显示分区操作按钮。
- 当该分区未全部选中时，按钮显示 `全选`。
- 当该分区内所有 token 都已选中时，按钮显示 `取消全选`。
- 点击按钮只影响当前分区 token，不影响其他分区。
- 用户单点 token 或拖选 token 后，同步刷新各分区按钮状态。

空分区不渲染标题行，也不渲染分区操作按钮。

## 数据与保存语义

保存选词时，`NFPNotificationRuleTokenBuilder` 按 section 聚合被选 token：

- 每个 section 按原始 token 顺序拼接出一条规则文本。
- 每条规则的 `scope` 使用该 section 的 scope。
- 未选中 token 的 section 不生成规则。
- 跨多个 section 选择时返回多条 rule entries。
- 不再因为 mixed scopes 自动降级为 `NFRuleScopeAll`。

示例：

- 标题选中 `支付`、`成功`，正文选中 `验证码`。
- 保存结果生成两条规则：
  - `支付成功`，scope 为 `title`。
  - `验证码`，scope 为 `message`。

## 组件改动范围

- `NFPRulesListEditorController`：增加全选/取消全选按钮状态与选择集合批量更新逻辑。
- `NFPNotificationRuleTokenPickerController`：把分区 label 改为标题行，增加分区全选/取消逻辑，并在 token 选择变化后刷新分区按钮。
- `NFPNotificationRuleTokenBuilder`：调整 `ruleEntriesFromTokenSections` 的聚合规则，按 section 返回多条 entries。
- `Localizable.strings`：新增全选与取消全选相关中英文文案。
- `tests/NFPNotificationRuleTokenBuilderTests.m`：补充跨分区选择生成多条规则的回归测试。

## 错误处理与边界

- 如果没有选中任何 token，选词页继续沿用现有“至少选择一个词语”的提示。
- 如果某个 section 的 tokens 为空，忽略该 section。
- 如果 rule entry 保存失败，继续沿用现有保存失败提示。
- 如果规则列表中的 rule identifier 缺失，保持现有行为：该规则不参与选择，避免误删无法稳定定位的条目。

## 验收标准

- 规则列表进入编辑态后可以一次选中全部规则，再删除全部规则。
- 规则列表全选后按钮切换为取消全选；取消后选择数变为 0，删除按钮禁用。
- 选词页可对标题、正文等分区分别全选和取消。
- 标题和正文同时选中时，保存后新增两条分别带 `title` 和 `message` scope 的规则。
- 单分区选词仍只生成一条对应 scope 的规则。
- 现有拖选、单点选词、保存失败提示不回归。

## 验证计划

- 运行 `tests/NFPNotificationRuleTokenBuilderTests.m` 覆盖跨分区生成多条规则。
- 构建 PreferenceBundle 或运行项目现有可用构建命令，确认 Objective-C 编译通过。
- 手动检查 Settings 中规则列表编辑态按钮状态、批量删除确认，以及选词页分区全选状态。
