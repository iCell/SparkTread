# Project Golden Eagle 文档索引

## 阅读顺序

1. `PROJECT_MASTER_SUMMARY_ZH.md`：中文总览，汇总全部已确认方向。
2. `PRODUCT_IMPLEMENTATION_PLAN.md`：产品、架构、范围、里程碑和验收的最终实施权威。
3. `ASSET_REQUIREMENTS_LIST_ZH.md`：只列举全部素材需求，不授权生成。
4. `ASSET_PRODUCTION_MANIFEST.md`：素材技术规格、生产边界和来源台账要求。
5. `GAME_MECHANICS_SPEC.md`：原版机制证据和恢复数据。
6. `RESEARCH_SUMMARY.md`：原版反向分析摘要。
7. `STAGE_52_METADATA.csv`：52 个候选参考关卡元数据。
8. `AI_REVIEW_PROMPT.md`：交给其他 AI 模型审查规划时使用。

## 权威顺序

出现冲突时：

1. 已接受的 ADR；
2. `PRODUCT_IMPLEMENTATION_PLAN.md`；
3. `PROJECT_MASTER_SUMMARY_ZH.md`；
4. 自动测试和已固定内容 schema；
5. `GAME_MECHANICS_SPEC.md` 中的参考事实；
6. 其他清单、提示词、聊天记录和非正式说明。

原版研究事实不能覆盖现代产品中已经固定的平台、地图、视角、单人范围、美术和架构决定。

## 已接受 ADR

- `docs/decisions/ADR-0001-spatial-unit-system.md`：1 格 = 1024 子单位，象限 = 512。
- `docs/decisions/ADR-0002-command-contract-and-input-buffering.md`：`PlayerCommand` 唯一外部输入契约；缓冲由核心持有。
- `docs/decisions/ADR-0003-serializable-world-state.md`：权威状态可完整序列化，支持挂起恢复与快速重模拟。
- `docs/decisions/ADR-0004-arena-rendering-and-device-floor.md`：全屏渲染；设备基线 390 点级别。
- `docs/decisions/ADR-0005-allied-base-damage-by-difficulty.md`：己方火力对基地按难度生效——Casual 免疫，Standard/Veteran 开启。

## 当前固定摘要

- Swift + SpriteKit + SwiftUI；
- iPhone 横屏首发，之后 iPad、macOS；
- 2D 正俯视；
- 统一一种固定竞技场；
- 完整地图和所有活动坦克始终可见；
- V1 仅单人；
- 后续两人在线合作；
- 一套现代游戏规则；
- 柔和现代机械玩具街机风；
- 当前素材工作只列清单，不进行新生成（A0 风格锁定母版需单独记录授权）；
- 1 格 = 1024 子单位；`PlayerCommand` 为唯一外部输入契约；
- 权威状态可完整序列化并支持快速重模拟；
- 设备基线 390 点级别；竞技场全屏渲染。

## 风格参考

- `styleboards/golden_eagle_arena_styleboard_v2_soft.png`
- `styleboards/golden_eagle_tank_family_styleboard_v2_soft.png`

风格图不是正式精灵表。

