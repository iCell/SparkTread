# SparkTread（原代号 Project Golden Eagle）文档索引

## 阅读顺序

1. `docs/decisions/`：已接受的 ADR（ADR-0001 美术方向、ADR-0002 项目名、ADR-0003 可读性门槛）。
2. `PROJECT_MASTER_SUMMARY_ZH.md`：中文总览，汇总全部已确认方向。
3. `PRODUCT_IMPLEMENTATION_PLAN.md`：产品、架构、范围、里程碑和验收的最终实施权威。
4. `ASSET_REQUIREMENTS_LIST_ZH.md`：只列举全部素材需求，不授权生成。
5. `ASSET_PRODUCTION_MANIFEST.md`：素材技术规格、生产边界和来源台账要求。
6. `GAME_MECHANICS_SPEC.md`：原版机制证据和恢复数据。
7. `RESEARCH_SUMMARY.md`：原版反向分析摘要。
8. `STAGE_52_METADATA.csv`：52 个候选参考关卡元数据。
9. `PixelProduction/README.md` 与 `PixelProduction/Docs/`：正式美术资源包及接入文档。

## 权威顺序

出现冲突时：

1. 已接受的 ADR；
2. `PRODUCT_IMPLEMENTATION_PLAN.md`；
3. `PROJECT_MASTER_SUMMARY_ZH.md`；
4. 自动测试和已固定内容 schema；
5. `GAME_MECHANICS_SPEC.md` 中的参考事实；
6. 其他清单、提示词、聊天记录和非正式说明。

原版研究事实不能覆盖现代产品中已经固定的平台、地图、视角、单人范围、美术和架构决定。

## 当前固定摘要

- Swift + SpriteKit + SwiftUI；
- iPhone 横屏首发，之后 iPad、macOS；
- 2D 正俯视；
- 统一一种固定竞技场；
- 完整地图和所有活动坦克始终可见；
- V1 仅单人；
- 后续两人在线合作；
- 一套现代游戏规则；
- 美术方向：`PixelProduction/` 精致像素风（ADR-0001，取代 D-019/D-020 的柔和玩具风）；
- 项目名与 scheme：SparkTread（ADR-0002）；
- 竞技场保持 48×27，可读性门槛按 ADR-0003 的功能性标准执行；
- 新素材生成仍需显式请求，缺口以 `PixelProduction` 台账为准。

## 风格参考

正式美术权威为 `PixelProduction/`（图集 + `Metadata/pixel_assets.json` + `Docs/SPRITEKIT_USAGE_ZH.md`）。原 `styleboards/` 软风格板已随 ADR-0001 废弃并删除，不再恢复。

