import Foundation
import SpriteKit

/// Visual event identifiers only. Gameplay chooses when and where they occur.
/// The mine kinds and `PixelMineNode` left with the mechanic (R5, ADR-0018);
/// the delivery still carries their recipes and sprites, unreferenced.
enum PixelEffectKind:String,CaseIterable {
    case brickHit,steelHit,armorHit,shieldHit,waterHit,projectileCancel
    case tankExplosion,groundExplosion,apEntry,apExit,fireIgnite,fireBurn,fireExtinguish,waterExtinguish
    case spawnWarning,spawnComplete,pickupSpawn,pickupCollect,upgrade
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
            // Reserve a separate caption row instead of printing over the cup.
            glyph.setScale(0.83);glyph.position.y=3*pixelScale
            let label=SKLabelNode(fontNamed:"Menlo-Bold");label.name="score_caption";label.text=String(value);label.fontSize=7*pixelScale;label.fontColor = .white;label.position.y = -14*pixelScale;label.zPosition=2;group.addChild(label)
        }
        try update(phase:.idle,age:0)
    }
    required init?(coder:NSCoder){fatalError("Use registered pickup")}
    var scoreCaptionClearOfGlyph:Bool {
        guard let caption=group.childNode(withName:"score_caption") else{return true}
        return caption.frame.maxY < art.visibleRect(glyph,id:item.texture,in:group).minY
    }
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
