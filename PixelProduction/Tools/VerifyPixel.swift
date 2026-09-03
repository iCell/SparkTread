import Foundation
import SpriteKit
import AppKit
import CryptoKit

/// Exhaustive resource and presentation fixtures; not a gameplay or iPhone acceptance test.
@main struct VerifyPixel {
    @MainActor static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),art=try PixelArt(root:root)
        _=NSApplication.shared
        var checks:[[String:Any]]=[],captures:[String]=[]
        func check(_ name:String,_ ok:Bool){checks.append(["name":name,"passed":ok])}
        func cellLabel(_ text:String,_ node:SKNode,_ y:CGFloat = -40){let l=SKLabelNode(fontNamed:"Menlo-Bold");l.text=text;l.fontSize=10;l.position.y=y;l.fontColor = .white;l.zPosition=100;node.addChild(l)}
        func makeScene(_ count:Int,_ cols:Int,_ spacing:CGSize=CGSize(width:155,height:125))->(SKScene,[SKNode]) {
            let rows=(count+cols-1)/cols,size=CGSize(width:CGFloat(cols)*spacing.width,height:CGFloat(rows)*spacing.height)
            let s=SKScene(size:size);s.backgroundColor=SKColor(red:0.22,green:0.23,blue:0.21,alpha:1)
            var nodes:[SKNode]=[]
            for i in 0..<count {let n=SKNode();n.position=CGPoint(x:(CGFloat(i%cols)+0.5)*spacing.width,y:size.height-(CGFloat(i/cols)+0.48)*spacing.height);s.addChild(n);nodes.append(n)}
            return(s,nodes)
        }
        func capture(_ scene:SKScene,_ name:String)throws {
            let view=SKView(frame:CGRect(origin:.zero,size:scene.size));view.presentScene(scene)
            guard let t=view.texture(from:scene,crop:CGRect(origin:.zero,size:scene.size)),let png=NSBitmapImageRep(cgImage:t.cgImage()).representation(using:.png,properties:[:]) else {throw PixelArtError.missing("capture \(name)")}
            try png.write(to:root.appendingPathComponent("Previews/\(name).png"));captures.append(name)
        }
        for (id,s) in art.manifest.sprites.sorted(by:{$0.key<$1.key}) {
            let t=try art.texture(id),data=try Data(contentsOf:root.appendingPathComponent(s.path))
            check("hash "+id,SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()==s.sha256)
            check("dimensions/filter "+id,t.cgImage().width==Int(s.pixelSize[0]) && t.cgImage().height==Int(s.pixelSize[1]) && t.filteringMode == .nearest)
        }
        check("all 25 pickup IDs",Set(art.manifest.pickups.map(\.id))==Set(0..<25))
        check("32 FX events",Set(art.manifest.eventRecipes.keys)==Set(PixelEffectKind.allCases.map(\.rawValue)))
        // Equipment is actually layered with the body, in all four screen directions.
        let (equipmentScene,equipmentSlots)=makeScene(16,4)
        for (r,name) in ["amphi","anti_skid","moon","memory"].enumerated(){for dir in 0..<4 {
            let t=try PixelTankNode(kind:"player",weapon:"normal",direction:dir,pixelScale:1.8,art:art)
            try t.setEquipment(name);equipmentSlots[r*4+dir].addChild(t);cellLabel(name+" "+PixelTankNode.directions[dir],equipmentSlots[r*4+dir],-47)
            let before=t.muzzle(in:t);try t.setTreadPhase(3);check("track muzzle invariant \(name) \(dir)",before==t.muzzle(in:t))
            try t.setDirection((dir+1)%4);try t.setDirection(dir);check("direction roundtrip \(name) \(dir)",before==t.muzzle(in:t))
        }}
        try capture(equipmentScene,"pixel_equipment_spritekit")
        let (pickupScene,pickupSlots)=makeScene(25,5)
        for id in 0..<25 {
            let p=try PixelPickupNode(id:id,pixelScale:1.5,art:art);pickupSlots[id].addChild(p);cellLabel("\(id) "+p.item.key,pickupSlots[id])
            for state in PixelPickupPhase.allCases {try p.update(phase:state,age:1);check("pickup terminal \(id) \(state)",p.isHidden==[.expired,.collecting,.replacing].contains(state))}
            try p.update(phase:.idle,age:0);check("pickup reuse \(id)",!p.isHidden)
        }
        try capture(pickupScene,"pixel_pickups_spritekit")
        let (fxScene,fxSlots)=makeScene(32,8)
        for (i,kind) in PixelEffectKind.allCases.enumerated() {
            let fx=try PixelEffectNode(kind:kind,pixelScale:1.6,art:art);fxSlots[i].addChild(fx);cellLabel(kind.rawValue,fxSlots[i])
            try fx.advance(to:fx.duration+1);check("FX terminal "+kind.rawValue,fx.loops || fx.visiblePartCount==0)
            try fx.advance(to:0.15);check("FX visible "+kind.rawValue,fx.visiblePartCount>0 && fx.physicsBody==nil)
            let stopped=try PixelEffectNode(kind:kind,pixelScale:1,art:art);stopped.stop();try stopped.advance(to:4);check("FX stop "+kind.rawValue,stopped.children.isEmpty && stopped.visiblePartCount==0)
        }
        try capture(fxScene,"pixel_effects_spritekit")
        let (baseScene,baseSlots)=makeScene(20,5)
        for state in 0..<4 {for (i,shield) in PixelBaseShieldPhase.allCases.enumerated(){
            let b=try PixelBaseNode(pixelScale:1.7,art:art);try b.update(damageState:state,shieldPhase:shield,age:0.2);baseSlots[state*5+i].addChild(b);cellLabel("\(state) "+shield.rawValue,baseSlots[state*5+i],-49)
        }}
        try capture(baseScene,"pixel_base_spritekit")
        let (mineScene,mineSlots)=makeScene(32,8)
        for level in 0..<4 {for (i,phase) in PixelMinePhase.allCases.enumerated(){
            let m=try PixelMineNode(level:level,owner:level%2==0 ? "player" : "enemy",surface:level==2 ? .water : level==3 ? .ice : .ground,pixelScale:1.6,art:art)
            try m.update(phase:phase,age:0.15,progress:0.5);mineSlots[level*8+i].addChild(m);cellLabel("L\(level) "+phase.rawValue,mineSlots[level*8+i])
        }}
        try capture(mineScene,"pixel_mines_spritekit")
        for level in 0..<4 {for owner in ["player","enemy"] {for surface in PixelMineSurface.allCases {
            let m=try PixelMineNode(level:level,owner:owner,surface:surface,pixelScale:1,art:art)
            for phase in PixelMinePhase.allCases {
                try m.update(phase:phase,age:1,progress:1)
                check("mine hardware \(level) \(owner) \(surface) \(phase)",m.hardwareVisible == ![.removed,.detonating,.disarming].contains(phase))
                try m.update(phase:.armed,age:1,progress:1);check("mine reuse \(level) \(owner) \(surface) \(phase)",m.hardwareVisible)
                try m.update(phase:.armed,age:1,progress:1,revealed:false);check("mine unrevealed",m.isHidden)
            }
        }}}
        let (topologyScene,topologySlots)=makeScene(47*3,12,CGSize(width:65,height:70))
        for (k,kind) in ["water","ice","foliage"].enumerated(){for (i,mask) in art.manifest.canonicalTopologyMasks.enumerated(){
            let id=String(format:"px_%@_%03d_0",kind,mask),n=try art.sprite(id,scale:2.1);topologySlots[k*47+i].addChild(n);cellLabel("\(kind.prefix(1)) \(mask)",topologySlots[k*47+i],-30)
        }}
        try capture(topologyScene,"pixel_topology_spritekit")
        let (wallScene,wallSlots)=makeScene(64,16,CGSize(width:65,height:70))
        for (k,kind) in ["brick","steel"].enumerated(){for mask in 0..<16 {for (r,mode) in ["remaining","connected"].enumerated(){
            let n=try art.sprite(String(format:"px_%@_%@_%02d",kind,mode,mask),scale:2.1);wallSlots[k*32+r*16+mask].addChild(n);cellLabel("\(kind.prefix(1))\(mode.prefix(1)) \(mask)",wallSlots[k*32+r*16+mask],-30)
        }}}
        try capture(wallScene,"pixel_walls_spritekit")
        let failures=checks.filter{$0["passed"] as? Bool != true}
        let manifestHash=SHA256.hash(data:try Data(contentsOf:root.appendingPathComponent("Metadata/pixel_assets.json"))).map{String(format:"%02x",$0)}.joined()
        let report:[String:Any]=["passed":failures.isEmpty,"checkCount":checks.count,"failures":failures,"checks":checks,"captures":captures,"assetManifestSHA256":manifestHash,"renderer":"SpriteKit SKView.texture on macOS","physicalDeviceAccepted":false,"campaignAccepted":false]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("Metadata/pixel_runtime_checks.json"))
        print("\(checks.count) checks; \(failures.count) failures; \(captures.count) SpriteKit captures")
        if !failures.isEmpty {throw PixelArtError.missing("runtime verification failed")}
    }
}
