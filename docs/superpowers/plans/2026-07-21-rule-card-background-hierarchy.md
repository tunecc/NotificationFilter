# Rule Card Background Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make already-added rule cards read as white surfaces on the grouped gray list background in light mode, restoring visual hierarchy without changing interaction or layout.

**Architecture:** Keep the change inside `NFPRuleCardCell`. The list page already uses `systemGroupedBackgroundColor`; the card surface switches from non-grouped `secondarySystemBackgroundColor` to grouped `secondarySystemGroupedBackgroundColor`. The same semantic color is set both at init and in `updateCardAppearance` so trait changes stay consistent.

**Tech Stack:** Objective-C, UIKit PreferenceBundle, Theos packaging.

## Global Constraints

- 仅修改 `NotificationFilterPrefs/NFPRuleCardCell.m`。
- 卡片背景使用 `secondarySystemGroupedBackgroundColor`，不用自定义 RGB / 写死白色。
- 不调整圆角、边框宽度、阴影参数。
- 不改动 `NFPRulesListEditorController` 或其他列表页。
- 不修改公共接口、本地化、偏好键。
- 最低构建验证为 `make package-debug-rootless`。
- 无自动化 UI 测试；视觉验收以 Preference 真机/模拟器浅色规则列表为准。

---

## File Structure

- Modify `NotificationFilterPrefs/NFPRuleCardCell.m`: replace the card surface color at initialization and re-apply it inside `updateCardAppearance`.

---

### Task 1: Switch Rule Card To Grouped Secondary Background

**Files:**
- Modify: `NotificationFilterPrefs/NFPRuleCardCell.m`

**Interfaces:**
- Consumes: existing `cardView`, `-updateCardAppearance`, `-traitCollectionDidChange:`.
- Produces: no new public API; card surface color is `secondarySystemGroupedBackgroundColor`.

- [ ] **Step 1: Confirm the current wrong color is still present**

Run:

```bash
rg -n "secondarySystemBackgroundColor|secondarySystemGroupedBackgroundColor|updateCardAppearance" NotificationFilterPrefs/NFPRuleCardCell.m
```

Expected before change:

- Line ~29: `cardView.backgroundColor = [UIColor secondarySystemBackgroundColor];`
- `updateCardAppearance` sets border/shadow only, not `cardView.backgroundColor`
- No `secondarySystemGroupedBackgroundColor` yet

- [ ] **Step 2: Change the init-time card background**

In `NotificationFilterPrefs/NFPRuleCardCell.m`, inside `-initWithStyle:reuseIdentifier:`, replace:

```objc
cardView.backgroundColor = [UIColor secondarySystemBackgroundColor];
```

with:

```objc
cardView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
```

- [ ] **Step 3: Re-apply the same color in `updateCardAppearance`**

In the same file, update `-updateCardAppearance` to:

```objc
- (void)updateCardAppearance {
    BOOL darkMode = NO;
    if (@available(iOS 12.0, *)) {
        darkMode = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    }

    self.cardView.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];

    self.cardView.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    UIColor *borderColor = darkMode ? [[UIColor separatorColor] colorWithAlphaComponent:0.32] : [UIColor opaqueSeparatorColor];
    self.cardView.layer.borderColor = borderColor.CGColor;

    self.cardView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.cardView.layer.shadowOpacity = darkMode ? 0.0 : 0.08;
}
```

Do not change border width, shadow radius/offset, corner radius, alpha, or layout constraints.

- [ ] **Step 4: Verify the file contains only the intended color change**

Run:

```bash
rg -n "secondarySystemBackgroundColor|secondarySystemGroupedBackgroundColor" NotificationFilterPrefs/NFPRuleCardCell.m
```

Expected:

- No remaining `secondarySystemBackgroundColor` in this file
- Exactly two `secondarySystemGroupedBackgroundColor` hits (init + `updateCardAppearance`)

Also sanity-check surrounding appearance code still present:

```bash
rg -n "cornerRadius|shadowOpacity|borderWidth" NotificationFilterPrefs/NFPRuleCardCell.m
```

Expected: existing corner/shadow/border lines still there and unchanged in value.

- [ ] **Step 5: Build the Preference package**

Run from repo root:

```bash
make package-debug-rootless
```

Expected: build succeeds (exit code 0). If the environment lacks Theos/device toolchain, stop and report the exact build error instead of claiming success.

- [ ] **Step 6: Manual visual check list (device or simulator)**

With at least one saved rule:

1. Light mode → open the already-added rules list: cards should be clearly lighter/whiter than the page background.
2. Dark mode → same list: cards still separable from the page background.
3. Toggle a rule switch, enter multi-select edit, and confirm validation badges (if any) still render.
4. Optional: switch system appearance while the list is open; card surface should stay correct.

If light-mode hierarchy is still weak after this color swap, do **not** expand into shadow/border tweaks in this task; report back against the design non-goals.

- [ ] **Step 7: Commit**

```bash
git add NotificationFilterPrefs/NFPRuleCardCell.m
git commit -m "$(cat <<'EOF'
fix: use grouped secondary background on rule cards

Light mode rule cards were nearly the same gray as the inset
grouped list background. Switch to secondarySystemGroupedBackgroundColor
so cards read as white surfaces with clear hierarchy.
EOF
)"
```

---

## Spec Coverage Checklist

| Spec requirement | Task / step |
|---|---|
| Init uses `secondarySystemGroupedBackgroundColor` | Task 1 Step 2 |
| `updateCardAppearance` also sets the same color | Task 1 Step 3 |
| No controller / other-list changes | Global constraints + single-file task |
| No corner/border/shadow parameter changes | Task 1 Step 3 explicit preserve + Step 4 check |
| Light/dark visual hierarchy | Task 1 Step 6 |
| Interaction regression (toggle/edit/badge) | Task 1 Step 6 |
| Package build gate | Task 1 Step 5 |

## Self-Review Notes

- No placeholders, no TBD.
- No automated unit test: project has no Preference UI test target for cell background; package + manual visual check matches AGENTS.md and the design doc.
- Single task is appropriate: one file, one semantic fix, one commit.
