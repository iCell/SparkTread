# 新像素图集：SpriteKit 接入与制作契约

当前交付的完整接入契约以 `Vendor/SparkTreadPixel/Docs/SPRITEKIT_USAGE_ZH.md` 为准；升级子模块时同时核对本文与运行时副本。本文的验证环境说明是素材交付时的历史记录，不是当前应用的验证结论。

本文件只适用于 `PixelProduction`。不要把上一级旧 `ST3` 接入说明、纹理尺寸或图集名称套到这里。运行时代码是美术表现适配器，不实现原版游戏规则。权威规则与美术分离，延续项目 architecture 约束。

## 1. 文件与依赖

向 Xcode 的游戏 target 添加：

- `Atlases` 下全部 17 个 `.atlas` 文件夹，保持扩展名与内部 PNG 名称；不要把所有文件夹打散成重名图片。
- `Metadata/pixel_assets.json`，保持 `Metadata` 子目录或放入 bundle 根目录，加载器都支持。
- `Runtime/PixelArt.swift`、`Runtime/PixelPresentation.swift`。

运行时仅依赖 Foundation、SpriteKit 及平台图片解码器。macOS 分支已由 Swift 6 编译并实测；UIKit 分支与 Xcode 编译后的 `.atlasc` 仍需在完整 Xcode 环境验证。当前电脑不能提供 iPhone 模拟器/真机验收证据。Atlas bundle 分支使用主应用 bundle，若封装进 Swift Package 的资源 bundle，需要另外实现资源 bundle 的纹理加载。

不要添加 `Current`、`Tools`、`Previews`、生成源图或 QA JSON 到应用。所有游戏需要的 PNG 都在 `Atlases` 内；没有对相邻旧包、网络图片或 Codex 缓存的运行时依赖。

压缩包不含生成母版。`build_pixel_assets.py` 仅保留加工流程，重导出需要显式提供当前 10 张键色源图；日常接入只运行 `verify_current.sh`，不需要重切。`pickup_catalog.json` 是本包自身的稳定道具数据，不再从旧素材目录读取。

## 2. 逻辑像素、画布、锚点

| 内容 | 导出画布 | 对齐契约 |
|---|---|---|
| 车体、左右履带、炮塔、装备 | 64×64 | 车体/履带地面锚点 `(32,35)`；炮塔 `(32,32)` |
| 基地 | 64×64 | `(32,35)`；四态共用缩放与底边 y=54，废墟碎片不拉伸主体 |
| 子弹/尾迹、地雷 | 32×32 | 子弹中心；地雷 `(16,17)` |
| 战斗特效 | 通常 48×48 | 枪口火焰 `(24,33)`；普通爆炸 `(24,24)`；以元数据为准 |
| 地面 | 48×48 | 作为 3×3 格底材，不是一个碰撞格 |
| 墙、水、冰、植被 | 16×16 | 1 个逻辑格，中心 `(8,8)` |
| UI/道具/状态 | 16～64 不等 | 不强行与车体使用同尺寸，按元数据与用途确定 |

元数据坐标以 PNG 左上角为原点，SpriteKit 本地坐标的 y 向上：

```text
anchorPoint = (anchorX / width, 1 - anchorY / height)
localPoint  = ((sourceX - anchorX) * scale,
               (anchorY - sourceY) * scale)
```

必须保留完整透明画布。不要按每帧非透明区域再次裁剪；不同朝向的可见包围盒可以不同，但逻辑占地和注册地面点不能改变。PNG 包围盒不等于碰撞形状。

`PixelArt.sprite` 已按该契约设置节点尺寸及 `.nearest` 采样。避免线性过滤与图片压缩。当前全图 fit 产生非整数缩放，可能出现像素宽度不均；必须在真机决定逻辑渲染分辨率与像素对齐策略，不能为了整数缩放裁剪地图。

## 3. 坦克装配

```swift
let art = try PixelArt() // Xcode 主 bundle 模式
// 本地工具用 PixelArt(root: pixelProductionURL)
let tank = try PixelTankNode(
    kind: "player", weapon: "normal", direction: 0,
    pixelScale: cellSize / 16, art: art
)
scene.addChild(tank)
tank.position = worldPresentationPosition
try tank.setDirection(1)
try tank.setTreadPhase(frameIndex)
try tank.setEquipment("amphi") // nil 移除
tank.setRecoil(recoilProgress) // 0...1，由表现时钟给出
let shotOrigin = tank.muzzle(in: scene)
```

- `kind`：`player/scout/standard/armored/heavy`。
- `weapon`：`normal/rapid/fire/ap/explosion/mine`。
- `direction`：`0=上、1=右、2=下、3=左`。
- 5 类车体×6 武器=30 个组合，每个组合有四朝向。普通玩家和普通敌军使用不同炮塔。
- 分层：装备底座 0 → 两侧履带 1 → 车体 2 → 炮塔 3 → 月牙/彩圈模块 4。
- 四方向切换纹理，**不旋转带阴影的完整车体**。炮塔挂点读取每个 `rig.mountOffset`，不得硬编码 `(0,-3)`。
- 履带为 4 相位的内部橡胶明暗滚动，透明外缘不移动。它不是整条履带平移，也不是 4 张重新生成的车体。建议用行驶距离选择相位；停车保持相位。
- 后坐力只移动炮塔；左右履带与车体不受后坐力影响。连发炮可从 `muzzleCount` 获取两个挂点。
- `setEquipment` 在改变朝向时重新绑定对应方向附件；装备状态反馈仍由调用方的玩法事件驱动。
- `turrets[*].rearDeploy` 是雷后置投放候选挂点，不是炮口；需要按相同坐标公式转换。不要用炮口位置生成地雷。
- 当前车体 `bodyBounds=(16,22,48,48)`，逻辑宽度 32px；统一使用 `pixelScale = cellSize / 16`，不得再叠加旧的 `0.82` 缩放。真机可读性仍需独立验收。

所有敌车当前共用同一视觉车体目标框，四档仍有顶盖/护板差异；高倍率目录可见，手机实战的档位辨识尚待验证。不得为表现方便改变四档权威碰撞体。

## 4. 子弹与发射

五类飞行弹体在 `projectiles` 字典中，主体与尾迹独立。以屏幕向上为基准，可以旋转这些对称、无地面侧面依赖的小型弹体及枪口火焰。

- 普通与特殊开火通道仍由输入/规则层分别控制，不根据武器贴图自动改变开火规则。
- 正常的起点来自 `tank.muzzle`；随后按权威运动快照更新位置，不把截图中的两个弹体当成完整弹道实现。
- 普通弹体可见宽度测试下限 1.8pt，特殊弹体 2.2pt；示例只沿横截面补宽，最大 4 倍，不改变弹长、速度或碰撞。
- 不从贴图 Alpha 建物理体。`RenderPixel.swift` 的补宽是显示保护，不是游戏规则。
- 枪口效果 `muzzle/rapid/fire/ap` 有四帧。爆破炮可复用普通枪口配方并组合橙色火光；地雷使用投放/布防提示。不同纹理映射在 `effects`、`eventRecipes` 内。

## 5. 特效与生命周期

```swift
let fx = try PixelEffectNode(kind: .tankExplosion,
                             pixelScale: cellSize / 16, art: art)
scene.addChild(fx)
fx.position = eventPosition
try fx.advance(to: presentationAge)
// 非循环事件 age >= duration 后内部隐藏，调用方回收节点。
// 循环事件必须在规则通知状态结束后显式停止：
fx.stop()
```

32 个枚举事件与 JSON 配方一一对应。配方包含帧、延迟、时长、偏移、移动、缩放、淡出与循环标志；时长仅为表现参数，不控制冻结、布雷、护盾或燃烧的规则持续时间。暂停时不推进 presentationAge。

`fireBurn/spawnWarning/repair/baseCritical/amphiWake` 是循环表现。每个节点初始化后不按帧增加子节点；外部仍须提供有界效果池、优先级和低刺激模式，避免密集战斗过载。烟、火、碎屑、焦痕可共享原语；当前 32 个配方是视觉原型，燃烧区域边界、持久地面残留池和实际事件集成仍需补充。

## 6. 道具、地雷、基地

```swift
let pickup = try PixelPickupNode(id: 21, pixelScale: 1, art: art)
try pickup.update(phase: .idle, age: 0.2)

let mine = try PixelMineNode(level: 2, owner: "enemy", surface: .water,
                            pixelScale: 1, art: art)
try mine.update(phase: .arming, age: 0.2, progress: 0.4)

let base = try PixelBaseNode(pixelScale: 1, art: art)
try base.update(damageState: 1, shieldPhase: .active, age: 0.2)
```

- 道具 ID 为 `0...24`，对应全部旧清单的稳定 key，不随 atlas 排序改变。9～12 是四种分数道具，数值由原生文字显示。六态：spawning/idle/collecting/replacing/atLimit/expired。
- 地雷 level `0...3`，owner `player/enemy`，surface ground/water/ice，八态由 `PixelMinePhase` 枚举。归属使用圆形勾/菱形叉，等级附带数字，不只靠颜色。
- 调用方提供布防进度、已揭示标记和状态年龄；到达 1 不自动进入下一阶段。不根据等级虚构爆炸半径。水面叠加水花，冰面叠加碎冰，不自动画地面焦痕。
- 基地 damageState `0=健康、1=受损、2=危险、3=废墟`；护盾 absent/appearing/active/warning/ending。伤害阈值由规则层决定。四态共用一个 ground anchor。

## 7. 地形连接与场景组织

逻辑格为 16 图像像素。水、冰、植被使用 47 个合法 8 邻域 mask：N=1、E=2、S=4、W=8、NE=16、SE=32、SW=64、NW=128。只有对应的两个正交邻格均存在时保留对角位。`canonicalTopologyMasks` 列出全部合法值；不要把未归一化的 0...255 直接拼到文件名。

文件形式 `px_water_255_0`，最后一段是动画帧。水/冰四帧、植被三帧。砖/钢连接为四邻域 0...15；剩余象限 rem 的 bit0/1/2/3 分别为左上/右上/左下/右下，0 是全透明的清除状态。逻辑破坏由规则层决定并同步贴图。

联合状态使用 `px_brick_joint_CC_RR` / `px_steel_joint_CC_RR`：CC 为两位十进制正交连接 mask，RR 为两位十进制剩余象限 mask。两种材质各 16×16=256 个联合条目已导出，透明象限不会被边框重新填实。它们表达格级邻接；半格边缘与邻居也残缺时的更细接触判断仍由适配器决定。完整图集加载通过不等于每个上下文拼接均经人工审阅。

地面/水/地面痕迹最底层；低墙、基地、坦克按地面 y 排序；植被可在前景层，但覆盖活动坦克时应局部淡化。此包没有自动遮挡消解系统。场景道具的 `prop` 类型不能自行变成不可通行地形；桥、排水口和出生平台是否可行走由关卡/规则 schema 决定。

## 8. UI 与缩略图

UI 是像素材质、图标与可拉伸按钮/面板，文字由原生字体绘制，不把中文烘焙进图片。可拉伸面板使用中心区域 `(0.25,0.25,0.5,0.5)`；触摸 hit area 与装饰的透明边缘无关。

摇杆底座/摇杆帽、普通/特殊按钮、普通/压下/禁用/冷却/空弹/选中/锁定材质已导出。HUD 其余数值、生命/装甲/火力/速度/弹药/装备可使用道具、状态纹理和原生文本。`RenderPixel.swift` 的 HUD 值是测试常量，不是完整 HUD 数据绑定，也不是多点触控实现。

暂停、胜/败、设置、选关、基地教学已有实际组成预览。正式菜单路由、保存/导入、设置行为、可访问性、控制编辑器及五段交互教学不在这个渲染工具内。12 张正式关卡缩略图应由真实关卡数据生成；当前 TEST 卡片不能交付为正式关卡内容。

## 9. 验证与二次审查

运行 `Tools/verify_current.sh`。独立工具覆盖全部资源哈希/尺寸/最近邻加载、25 道具的六态与复用、4 级×2 归属×3 表面的八态地雷、32 效果开始/结束/停止、装备四向与炮口稳定。它输出 7 个真实 SpriteKit 图录，再渲染三种屏幕比例、阵容、界面与动画。

几何边界测试只证明对象在完整地图矩形中，**不证明多指遮挡、所有障碍前后遮挡、所有组合美术品质、碰撞或真机流畅度**。原始 RGBA 大小约 7.24MiB，不是实际 GPU/进程内存或 FPS 结论。详见验收文档，不要把通过的自动检查等同于全部产品完成。
