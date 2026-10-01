# SparkTread 文档索引

## 阅读顺序

1. `GAME_RULES.md`：**唯一的游戏规则**（R5.9，2026-09-16）。地图、四档墙、五类武器、两种装备、20 型敌人、22 类宝物、基地与胜负、tick 内结算顺序、计分、12 关内容预算、iPhone 适配与验收场景都以此为准。
2. `PRODUCT_IMPLEMENTATION_PLAN.md`：架构、模块边界、内容格式、存档与回放、测试策略与里程碑。其中的玩法章节只保留指向 `GAME_RULES.md` 的索引。
3. `docs/decisions/`：架构与产品决定记录（ADR）。
4. `docs/CURRENT_REVIEW.md`：实现审查日志、验证证据与未完成项；回放金样重算必须在此记录原因。
5. `ASSET_PRODUCTION_MANIFEST.md`、`ASSET_REQUIREMENTS_LIST_ZH.md`：素材规格与清单，不授权生成；运行素材来自 `Vendor/SparkTreadPixel`（ADR-0008），接入方法见 `docs/pixel/`。
6. `STAGE_52_METADATA.csv`：原版 52 个候选关卡的研究元数据，只供日后原版关卡内容包参考。
7. `docs/agent_handoffs/`：带日期的交接记录，属于历史。

## 权威顺序

出现冲突时：

1. 玩法规则：`GAME_RULES.md`；
2. 已接受的 ADR（ADR-0018 起，与 `GAME_RULES.md` 冲突的旧 ADR 条款失效）；
3. `PRODUCT_IMPLEMENTATION_PLAN.md`（架构、流程、格式）；
4. 自动测试与已固定的内容 schema；
5. 其他清单、提示词、聊天记录和非正式说明。

参考游戏的研究材料不能覆盖 `GAME_RULES.md` 的定案。旧版研究总纲（原 `GAME_RULES.md`）与中文总览 `PROJECT_MASTER_SUMMARY_ZH.md` 已于 2026-09-15 退役，内容可在提交 4f2705e 中查阅。

## ADR 状态

已接受：

- ADR-0001 空间单位：1 格＝1024 子单位，象限＝512（R5 另定义 1 子单位＝1000 毫子单位用于速度）。
- ADR-0002 `PlayerCommand` 是唯一外部输入契约；输入缓冲由核心持有。
- ADR-0003 权威状态可完整序列化，支持挂起恢复与快速重模拟。
- ADR-0004 设备基线 390 点级别（全屏渲染条款被 ADR-0018 取代：关键对象必须在安全矩形内）。
- ADR-0005 己方火力伤基地按难度生效。
- ADR-0006 18pt 可见宽度门槛。
- ADR-0007 显示时钟驱动固定步模拟（停顿阈值以 R5 §15.3 为准）。
- ADR-0008 PixelProduction 交付满足 A0 风格锁定。
- ADR-0009 竞技场固定 56×27 格。
- ADR-0010 所有者战斗规则（部分被 ADR-0018 取代）。
- ADR-0011 参照原作的音效集与关卡过场。
- ADR-0012 结算表与过关奖励（部分被 ADR-0018 取代）。
- ADR-0017 无危险预警、草丛燃烧、训练场（部分被 ADR-0018 取代）。
- ADR-0018 `GAME_RULES.md` R5 成为唯一玩法权威；地雷、月之盾、海之记忆移出 V1。
- ADR-0019 所有者真机调参：坦克与弹速降到 R5 的 40%，射程不变；普通弹、快弹冷却同比放大；穿甲 C 提速一倍（GAME_RULES R5.8）。
- ADR-0020 所有者决定：AP 打红砖、白砖深度加倍；白砖浅灰石砖、精钢抛光银钢（GAME_RULES R5.6）。
- ADR-0021 所有者决定：弹弹相遇按强弱对抗、火焰弹遇弹落火；无敌 20 秒；已在出生占位内的坦克可驶出；去掉增援提示（GAME_RULES R5.7）。
- ADR-0022 所有者决定：战场整屏等比居中，边区精钢装饰，系统遮挡只覆盖装饰带（GAME_RULES R5.9）。

提议中（尚待所有者接受）：

- ADR-0013 战役推进与跨关状态。
- ADR-0014 检查点存档与中断快照。
- ADR-0015 难度档案与导演阶段（部分被 ADR-0018 取代）。
- ADR-0016 通行档案与冰面惯性（地雷弹射部分已被 ADR-0018 移除）。

## 当前固定摘要

- Swift＋SpriteKit＋SwiftUI；iPhone 横屏首发，之后 iPad、macOS；
- 2D 正俯视，统一 56×27 竞技场，完整地图与全部活动坦克始终可见；
- V1 仅单人，无联网、无本地双人；
- 一套现代规则（`GAME_RULES.md`）；
- 运行素材为 `Vendor/SparkTreadPixel` 像素交付；新增素材生成需单独授权；
- 60 Hz 固定 tick，整数权威状态，`PlayerCommand` 为唯一外部输入。
