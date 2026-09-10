# Project Golden Eagle 文档索引

## 阅读顺序

1. `PROJECT_MASTER_SUMMARY_ZH.md`：中文总览，汇总全部已确认方向。
2. `PRODUCT_IMPLEMENTATION_PLAN.md`：产品、架构、范围、里程碑和验收的最终实施权威。
3. `ASSET_REQUIREMENTS_LIST_ZH.md`：只列举全部素材需求，不授权生成。
4. `ASSET_PRODUCTION_MANIFEST.md`：素材技术规格、生产边界和来源台账要求。
5. `GAME_MECHANICS_SPEC.md`：原版机制证据和恢复数据。
6. `RESEARCH_SUMMARY.md`：原版反向分析摘要。
7. `STAGE_52_METADATA.csv`：52 个候选参考关卡元数据。
8. `docs/CURRENT_REVIEW.md`：当前实现审查（2026-09-09 Claude/PI 联合评审）、验证证据与未完成项。
9. `docs/agent_handoffs/2026-09-09-joint-review.md`：联合评审交接：已完成、验证命令、地雷区、下一步。

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

- `docs/decisions/ADR-0006-legibility-gate-pixel-scale.md`：像素素材可读性验收。
- `docs/decisions/ADR-0007-simulation-clock-driver.md`：独立显示时钟驱动固定步模拟。
- `docs/decisions/ADR-0008-a0-satisfied-by-pixelproduction.md`：PixelProduction 交付满足 A0 风格锁定。
- `docs/decisions/ADR-0009-universal-arena-56x27.md`：V1 竞技场固定为 56×27 格。

- `docs/decisions/ADR-0010-owner-combat-rules-and-fort-ring.md`：特殊弹药耗尽回退普通弹、基地护盾加固堡垒环与占用格策略（到期恢复为记录材质，所有者决定 B）、隐藏宝物揭示条件、地雷可见性。所有者 2026-09-10 接受。
- `docs/decisions/ADR-0011-reference-sfx-and-stage-transitions.md`：参照原作的音效集（八段原作录音节选、原创开场曲、其余合成）、事件映射、关卡过场时间线（开场卡片/十字揭幕/任务完成/战斗成绩）。所有者 2026-09-10 接受，并记录了版权使用决定。

- `docs/decisions/ADR-0012-results-table-and-stage-clear-bonuses.md`：参照原作结算画面的战斗成绩表（8 个奖励类别的坦克图标、4 行 ×1…×4、加权总计）与过关奖励（结算加分 + Reward，按关卡区间 200/330、600/660、1000/1000）。所有者 2026-09-10 接受（分档规则授权决定；不做 MaxHits/MaxCombos；用坦克图标）。

## 提议中的 ADR（待所有者接受，尚不具备权威）

- `docs/decisions/ADR-0014-checkpoint-save-and-suspended-session.md`：检查点存档（每关通关后写 `campaign_progress.json`）与中断快照（游戏中离开前台写 `suspended_session.json`，关卡结束或放弃时删除；标题页提供"继续上次战斗"，恢复后处于暂停）；文件带版本号、原子写入、损坏或异版本文件报错不崩溃。
- `docs/decisions/ADR-0013-campaign-progression-and-session-state.md`：战役推进——三关顺序内容（VS-02 隐于草丛、VS-03 沙漠阶梯，按原作地图适配 56×27）、跨关携带状态（生命、分数、弹药、保留升级；护甲不携带）、胜利自动进入下一关、失败从关卡起点检查点重来、回放格式 4 与链式战役回放。
- `Tools/reference_measure/README.md`：参照原作录像的测量流程与脚本（不含媒体），复现 ADR-0011 / CURRENT_REVIEW 中的音效与过场数据。

## 当前固定摘要

- Swift + SpriteKit + SwiftUI；
- iPhone 横屏首发，之后 iPad、macOS；
- 2D 正俯视；
- 统一一种固定竞技场；
- 完整地图和所有活动坦克始终可见；
- V1 仅单人；
- 后续两人在线合作；
- 一套现代游戏规则；
- 当前运行素材为 `Vendor/SparkTreadPixel` 的像素交付，A0 已满足（ADR-0008）；
- `Assets/Design` 和 `styleboards` 为历史设计参考，不是当前运行图集；新增素材生成仍需单独授权；
- 1 格 = 1024 子单位；`PlayerCommand` 为唯一外部输入契约；
- 权威状态可完整序列化并支持快速重模拟；
- 设备基线 390 点级别；竞技场全屏渲染。

## 风格参考

- `styleboards/golden_eagle_arena_styleboard_v2_soft.png`
- `styleboards/golden_eagle_tank_family_styleboard_v2_soft.png`

风格图不是正式精灵表。

