# SparkTread · 精致像素 2.5D 素材

2026-09-03。当前像素美术的可接入原型包：**17 个图集、1,617 个 RGBA PNG 条目**，以及 Swift/SpriteKit 装配代码和实际渲染验证。不是完整游戏，也没有标记为最终发行或 iPhone 真机验收完成。

## 看实际效果

- [完整竞技场：SpriteKit 实际渲染](Previews/pixel_arena_phone_1.png)
- [两秒演示动画：24 张 SpriteKit 帧](Previews/pixel_battle.gif)
- [30 种坦克模块组合](Previews/pixel_roster_phone_0.png)
- [四方向与装备组合](Previews/pixel_equipment_spritekit.png)
- [方形基地四态与护盾](Previews/pixel_base_spritekit.png)
- [25 种道具](Previews/pixel_pickups_spritekit.png)
- [地雷生命周期](Previews/pixel_mines_spritekit.png)
- [32 类效果的组合预览](Previews/pixel_effects_spritekit.png)

上面这些图是加载本包 PNG 后由 macOS 的 `SKView.texture` 捕获的画面，不是 AI 生成的完整地图。动画是有脚本的美术展示，不代表 AI、碰撞、联机或完整战斗已经实现。

## 开发入口

1. [SpriteKit 接入说明](Docs/SPRITEKIT_USAGE_ZH.md)：文件、尺寸、锚点、朝向、动画、状态和代码示例。
2. [范围与验收](Docs/COVERAGE_AND_QA_ZH.md)：已生成、已检查与尚未验收，供其他 AI 审查。
3. [运行时资源与配方清单](Metadata/pixel_assets.json)：每个 ID、相对路径、画布、Alpha 包围盒、挂点和 SHA-256。
4. [素材检查](Metadata/asset_checks.json)、[运行时检查](Metadata/pixel_runtime_checks.json)、[交付检查摘要](Metadata/delivery_summary.json)。

只向应用目标添加 `Atlases/*.atlas`、`Metadata/pixel_assets.json` 和 `Runtime/*.swift`。不要同时引入上一级旧材质的图集与运行时代码来冒充这套新风格。`Current` 是早期 RGB 方向参考，**禁止放进图集**；它不再是运行时资源。

## 验证与来源

在有 macOS 图形会话和 Swift 命令行工具的机器上：

```sh
/bin/zsh Tools/verify_current.sh
```

该检查只加载当前成品，不依赖原图、生成缓存、其他素材包或网络。图形沙箱限制可能需要允许本地渲染程序访问图形服务。测试不安装 App，也不启动 iPhone 模拟器。

美术主体使用内置 imagegen 生成；按用户确认的方式进行本地键色背景去除、像素化、等画布、分层、挂点和衍生状态处理。UI 几何、环、文字及状态动画由代码构成。[完整生成提示词](GENERATION_BATCH_02.md)已保留。未使用 API/CLI 图像生成或原版游戏纹理。

## 不能误读的边界

- 1,617 是纹理条目数，包含邻接、动画、共享衍生帧，不等于 1,617 个独立手绘物件。
- 当前 48×27 是统一完整地图的**测试夹具**，不是新的关卡尺寸决定；不滚屏、不裁图、不旋转镜头。
- 小屏坦克最低可见包围盒约 19–20×15 屏幕点，未达到旧 28×28 点暂定门槛。该冲突没有被悄悄豁免。
- iOS 编译图集、真机触控/性能、战场遮挡可读性、正式关卡缩略图及完整菜单/教学流程仍未验收；详见范围文档。品牌、音频、发行素材继续后置。
