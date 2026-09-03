import Foundation
import SpriteKit

/// Visual event identifiers only. Gameplay chooses when and where they occur.
enum PixelEffectKind:String,CaseIterable {
    case brickHit,steelHit,armorHit,shieldHit,waterHit,projectileCancel
    case tankExplosion,groundExplosion,apEntry,apExit,fireIgnite,fireBurn,fireExtinguish,waterExtinguish
    case mineArming,mineTrigger,mineDisarm,spawnWarning,spawnComplete,pickupSpawn,pickupCollect,upgrade
    case repair,baseHit,baseCritical,baseShieldAppear,baseShieldEnd,freezeBurst,iceHit,foliageHit,amphiWake,skidTrail
}

/// Uses a supplied presentation clock. No SKAction timers, RNG, physics or game-state mutation.
@MainActor final class PixelEffectNode:SKNode {
    private let art:PixelArt,recipe:PixelFXRecipe,pixelScale:CGFloat
    private var parts:[SKSpriteNode]=[]
    private(set) var stopped=false
    let kind:PixelEffectKind
    var loops:Bool {recipe.loop}
    var duration:Double {recipe.parts.map{$0.delay+$0.duration}.max() ?? 0}
    var visiblePartCount:Int {isHidden ? 0 : parts.filter{!$0.isHidden && $0.alpha>0.001}.count}
    init(kind:PixelEffectKind,pixelScale:CGFloat,art:PixelArt) throws {
        guard pixelScale.isFinite,pixelScale>0,let r=art.manifest.eventRecipes[kind.rawValue] else {throw PixelArtError.missing(kind.rawValue)}
        self.kind=kind;self.pixelScale=pixelScale;self.art=art;recipe=r
        super.init();name="event_"+kind.rawValue
        for (i,p) in r.parts.enumerated() {
            let n=try art.sprite(p.frames[0],scale:pixelScale*p.scale);n.zPosition=CGFloat(i)*0.01;addChild(n);parts.append(n)
        }
        try advance(to:0)
    }
    required init?(coder:NSCoder){fatalError("Use registered recipe")}
    func advance(to age:Double) throws {
        guard !stopped else{return}
        guard age.isFinite,age>=0 else {throw PixelArtError.missing("finite nonnegative FX age")}
        for (n,p) in zip(parts,recipe.parts) {
            var t=age-p.delay
            if recipe.loop && t>=0 {t=t.truncatingRemainder(dividingBy:p.duration)}
            n.isHidden=t<0 || t>=p.duration
            guard !n.isHidden else {continue}
            let u=t/p.duration,i=min(p.frames.count-1,Int(u*Double(p.frames.count)))
            n.texture=try art.texture(p.frames[i]);n.position=CGPoint(x:(p.offset[0]+p.travel[0]*u)*pixelScale,y:(p.offset[1]+p.travel[1]*u)*pixelScale)
            n.alpha=p.fade ? min(1,(1-u)*2) : 1
        }
    }
    func stop(){stopped=true;removeAllChildren();parts.removeAll();removeFromParent()}
}

enum PixelPickupPhase:String,CaseIterable {case spawning,idle,collecting,replacing,atLimit,expired}
@MainActor final class PixelPickupNode:SKNode {
    let item:PixelPickup
    private let art:PixelArt,scale:CGFloat,frameNode:SKSpriteNode,glyph:SKSpriteNode,group=SKNode()
    init(id:Int,pixelScale:CGFloat,art:PixelArt) throws {
        guard let item=art.manifest.pickups.first(where:{$0.id==id}) else {throw PixelArtError.missing("pickup \(id)")}
        self.item=item;self.art=art;scale=pixelScale
        frameNode=try art.sprite("px_pickup_frame_idle",scale:pixelScale);glyph=try art.sprite(item.texture,scale:pixelScale)
        super.init();name="pickup_"+item.key;addChild(group);group.addChild(frameNode);glyph.zPosition=1;group.addChild(glyph)
        if let value=item.displayNumber {
            let label=SKLabelNode(fontNamed:"Menlo-Bold");label.text=String(value);label.fontSize=7*pixelScale;label.fontColor = .white;label.position.y = -11*pixelScale;label.zPosition=2;group.addChild(label)
        }
        try update(phase:.idle,age:0)
    }
    required init?(coder:NSCoder){fatalError("Use registered pickup")}
    func update(phase:PixelPickupPhase,age:Double) throws {
        guard age>=0,age.isFinite else{throw PixelArtError.missing("pickup age")}
        frameNode.texture=try art.texture("px_pickup_frame_"+phase.rawValue);group.alpha=1;group.setScale(1);group.position = .zero;isHidden=false
        switch phase {
        case .spawning:group.alpha=min(1,age/0.25);group.setScale(0.75+0.25*min(1,age/0.25))
        case .idle:group.position.y=sin(age*2)*1.5*scale
        case .collecting:group.alpha=max(0,1-age/0.4);group.position.y=age*18*scale;isHidden=age>=0.4
        case .replacing:group.alpha=max(0,1-age/0.4);group.setScale(1+min(1,age/0.4)*0.2);isHidden=age>=0.4
        case .atLimit:group.alpha=0.85
        case .expired:isHidden=true
        }
    }
}

enum PixelMinePhase:String,CaseIterable {case placing,unarmed,arming,armed,triggered,disarming,detonating,removed}
enum PixelMineSurface:String,CaseIterable {case ground,water,ice}
@MainActor final class PixelMineNode:SKNode {
    let level:Int,owner:String,surface:PixelMineSurface
    private let art:PixelArt,scale:CGFloat,body:SKSpriteNode,badge:SKSpriteNode,warning:SKSpriteNode,water:SKSpriteNode
    private let hardware=SKNode(),number=SKLabelNode(fontNamed:"Menlo-Bold")
    private let blast:PixelEffectNode,impact:PixelEffectNode?
    private(set) var phase:PixelMinePhase = .unarmed
    init(level:Int,owner:String,surface:PixelMineSurface,pixelScale:CGFloat,art:PixelArt) throws {
        guard (0...3).contains(level),["player","enemy"].contains(owner) else {throw PixelArtError.missing("mine level/owner")}
        self.level=level;self.owner=owner;self.surface=surface;self.art=art;scale=pixelScale
        body=try art.sprite("px_mine_\(level)_dormant",scale:pixelScale)
        badge=try art.sprite("px_badge_"+owner,scale:pixelScale*0.6)
        warning=try art.sprite("px_status_mine_warning_0",scale:pixelScale*0.65)
        water=try art.sprite("px_status_shield_0",scale:pixelScale*0.55)
        blast=try PixelEffectNode(kind:.tankExplosion,pixelScale:pixelScale,art:art)
        impact=surface == .ground ? nil : try PixelEffectNode(kind:surface == .water ? .waterHit : .iceHit,pixelScale:pixelScale,art:art)
        super.init();name="mine_\(level)_\(owner)";addChild(hardware);hardware.addChild(body);hardware.addChild(badge);hardware.addChild(number)
        badge.position=CGPoint(x:9*scale,y:-8*scale);badge.zPosition=2
        number.text=String(level);number.fontSize=6*scale;number.fontColor = .white;number.position=CGPoint(x:-8*scale,y:5*scale);number.zPosition=3
        addChild(warning);warning.zPosition=4;addChild(water);water.zPosition = -1;addChild(blast);blast.zPosition=5
        if let impact {addChild(impact);impact.zPosition=6}
        try update(phase:.unarmed,age:0,progress:0)
    }
    required init?(coder:NSCoder){fatalError("Use registered mine")}
    func update(phase:PixelMinePhase,age:Double,progress:Double,revealed:Bool=true) throws {
        guard age>=0,age.isFinite,progress.isFinite,(0...1).contains(progress) else {throw PixelArtError.missing("mine snapshot")}
        self.phase=phase;isHidden = !revealed || phase == .removed
        hardware.isHidden=false;hardware.alpha=1;hardware.setScale(1);warning.isHidden=true;warning.alpha=1;warning.setScale(1)
        blast.isHidden=true;impact?.isHidden=true;water.isHidden=surface != .water || phase == .removed;water.alpha=0.55
        body.texture=try art.texture("px_mine_\(level)_"+([.armed,.triggered].contains(phase) ? "armed" : "dormant"))
        switch phase {
        case .placing:hardware.alpha=min(1,age/0.25);hardware.setScale(0.8+0.2*min(1,age/0.25))
        case .unarmed:hardware.alpha=0.6
        case .arming:warning.isHidden=false;warning.alpha=0.25+0.5*progress;warning.setScale(1.3-0.3*progress)
        case .armed:break
        case .triggered:warning.isHidden=false;warning.alpha=0.7+0.2*sin(age*3)
        case .disarming:hardware.alpha=1-progress;warning.isHidden=false;warning.alpha=1-progress;warning.setScale(1-0.5*progress)
        case .detonating:hardware.isHidden=true;water.isHidden=true;blast.isHidden=false;try blast.advance(to:age);impact?.isHidden=false;try impact?.advance(to:age)
        case .removed:break
        }
    }
    /// Presentation intentionally does not invent a blast radius from the level.
    var hardwareVisible:Bool {!isHidden && !hardware.isHidden && hardware.alpha>0.001}
}

enum PixelBaseShieldPhase:String,CaseIterable {case absent,appearing,active,warning,ending}
@MainActor final class PixelBaseNode:SKNode {
    private let body:SKSpriteNode,shield:SKSpriteNode,art:PixelArt
    init(pixelScale:CGFloat,art:PixelArt) throws {
        self.art=art;body=try art.sprite(art.manifest.baseStates[0],scale:pixelScale);shield=try art.sprite("px_base_shield_0",scale:pixelScale)
        super.init();addChild(body);addChild(shield);shield.zPosition=2;shield.isHidden=true
    }
    required init?(coder:NSCoder){fatalError("Use registered base")}
    func update(damageState:Int,shieldPhase:PixelBaseShieldPhase,age:Double) throws {
        guard (0..<4).contains(damageState),age.isFinite,age>=0 else {throw PixelArtError.missing("base snapshot")}
        body.texture=try art.texture(art.manifest.baseStates[damageState]);shield.texture=try art.texture("px_base_shield_\(Int(age*5)%5)")
        shield.isHidden=shieldPhase == .absent;shield.alpha=1;shield.setScale(1)
        switch shieldPhase {
        case .absent:break
        case .appearing:shield.alpha=min(1,age/0.4)
        case .active:shield.alpha=0.65
        case .warning:shield.alpha=0.5+0.25*sin(age*3)
        case .ending:shield.alpha=max(0,1-age/0.4)
        }
    }
}
