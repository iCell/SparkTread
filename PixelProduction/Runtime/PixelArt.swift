import Foundation
import SpriteKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

enum PixelArtError: Error { case missing(String) }
struct PixelSpriteSpec: Decodable {
    let id: String, path: String, atlas: String, role: String, sha256: String
    let pixelSize: [Double], anchorTopLeft: [Double]
    let contentBounds: [Double]?
}
struct PixelRigSpec: Decodable {
    let hull: String, treads: [[String]]
    let anchor: [Double], mountOffset: [Double], bodyBounds: [Double]
}
struct PixelTurretSpec: Decodable {
    let texture: String, anchor: [Double], muzzles: [[Double]], rearDeploy: [Double]
}
struct PixelPickup: Decodable { let id: Int, key: String, labelZH: String, texture: String; let displayNumber: Int? }
struct PixelFXPartSpec:Decodable {let frames:[String];let delay:Double,duration:Double;let offset:[Double],travel:[Double];let scale:Double;let fade:Bool}
struct PixelFXRecipe:Decodable {let loop:Bool;let parts:[PixelFXPartSpec]}
struct PixelManifest: Decodable {
    let formatVersion: Int, logicalCellPixels: Int, tankCanvasPixels: Int
    let sprites: [String:PixelSpriteSpec], rigs: [String:PixelRigSpec], turrets: [String:PixelTurretSpec]
    let baseStates: [String], equipment: [String:String], effects: [String:[String]], pickups: [PixelPickup]
    let canonicalTopologyMasks: [Int]
    let eventRecipes:[String:PixelFXRecipe]
}

/// Presentation adapter only. No collision or authority state is inferred from art.
@MainActor final class PixelArt {
    let root: URL?, manifest: PixelManifest
    private let bundle:Bundle
    private var cache: [String:SKTexture] = [:]
    private var atlases:[String:SKTextureAtlas]=[:]
    init(root: URL? = nil,bundle:Bundle = .main) throws {
        self.root=root;self.bundle=bundle
        guard let url=root?.appendingPathComponent("Metadata/pixel_assets.json") ?? bundle.url(forResource:"pixel_assets",withExtension:"json",subdirectory:"Metadata") ?? bundle.url(forResource:"pixel_assets",withExtension:"json") else {throw PixelArtError.missing("pixel_assets.json")}
        manifest=try JSONDecoder().decode(PixelManifest.self,from:Data(contentsOf:url))
    }
    func texture(_ id: String) throws -> SKTexture {
        if let t=cache[id] { return t }
        guard let s=manifest.sprites[id] else {throw PixelArtError.missing(id)}
        let t:SKTexture
        if let root {
            let cg:CGImage?
            #if canImport(UIKit)
            cg=UIImage(contentsOfFile:root.appendingPathComponent(s.path).path)?.cgImage
            #else
            cg=NSImage(contentsOf:root.appendingPathComponent(s.path))?.cgImage(forProposedRect:nil,context:nil,hints:nil)
            #endif
            guard let cg else {throw PixelArtError.missing(id)};t=SKTexture(cgImage:cg)
        } else {
            // Xcode compiles the .atlas folders. Texture names remain extensionless IDs.
            let atlas=atlases[s.atlas] ?? SKTextureAtlas(named:s.atlas);atlases[s.atlas]=atlas
            guard atlas.textureNames.contains(id) || atlas.textureNames.contains(id+".png") else {throw PixelArtError.missing(id)}
            t=atlas.textureNamed(id)
        }
        t.filteringMode = .nearest;cache[id]=t;return t
    }
    func sprite(_ id: String, scale: CGFloat = 1) throws -> SKSpriteNode {
        guard let s=manifest.sprites[id] else { throw PixelArtError.missing(id) }
        let n=SKSpriteNode(texture:try texture(id));n.name=id
        n.size=CGSize(width:s.pixelSize[0]*scale,height:s.pixelSize[1]*scale)
        n.anchorPoint=CGPoint(x:s.anchorTopLeft[0]/s.pixelSize[0],y:1-s.anchorTopLeft[1]/s.pixelSize[1])
        return n
    }
    func visibleRect(_ node: SKSpriteNode, id: String, in scene: SKNode) -> CGRect {
        guard let s=manifest.sprites[id],let b=s.contentBounds else { return .null }
        let sx=node.size.width/s.pixelSize[0],sy=node.size.height/s.pixelSize[1]
        let p=[CGPoint(x:(b[0]-s.anchorTopLeft[0])*sx,y:(s.anchorTopLeft[1]-b[1])*sy),CGPoint(x:(b[2]-s.anchorTopLeft[0])*sx,y:(s.anchorTopLeft[1]-b[3])*sy)].map{node.convert($0,to:scene)}
        return CGRect(x:min(p[0].x,p[1].x),y:min(p[0].y,p[1].y),width:abs(p[0].x-p[1].x),height:abs(p[0].y-p[1].y))
    }
}

/// Directional texture swaps preserve ground pivot. Only turret receives recoil.
@MainActor final class PixelTankNode: SKNode {
    static let directions=["up","right","down","left"]
    let art: PixelArt, kind: String, pixelScale: CGFloat
    private(set) var weapon: String, direction: Int, phase: Int=0
    private var hull: SKSpriteNode!, left: SKSpriteNode!, right: SKSpriteNode!, turret: SKSpriteNode!
    private var rig: PixelRigSpec!, gun: PixelTurretSpec!
    private var equipmentName:String?,equipmentNode:SKSpriteNode?
    init(kind: String, weapon: String, direction: Int, pixelScale: CGFloat, art: PixelArt) throws {
        self.kind=kind;self.weapon=weapon;self.direction=direction;self.pixelScale=pixelScale;self.art=art
        super.init();name="\(kind)_\(weapon)";try rebuild()
    }
    required init?(coder: NSCoder) { fatalError("Use registered art") }
    private func rebuild() throws {
        let d=Self.directions[direction]
        guard let r=art.manifest.rigs[kind+"_"+d],let g=art.manifest.turrets[(weapon=="normal" ? (kind=="player" ? "player_normal" : "enemy_normal") : weapon)+"_"+d] else { throw PixelArtError.missing(name ?? "rig") }
        rig=r;gun=g
        for n in [hull,left,right,turret] { n?.removeFromParent() }
        left=try art.sprite(r.treads[0][phase],scale:pixelScale);right=try art.sprite(r.treads[1][phase],scale:pixelScale)
        hull=try art.sprite(r.hull,scale:pixelScale);turret=try art.sprite(g.texture,scale:pixelScale)
        left.zPosition=1;right.zPosition=1;hull.zPosition=2;turret.zPosition=3
        for n in [left,right,hull,turret] { addChild(n!) }
        setRecoil(0)
        try setEquipment(equipmentName)
    }
    func setDirection(_ value: Int) throws { precondition((0..<4).contains(value));if value != direction { direction=value;try rebuild() } }
    func setWeapon(_ value: String) throws { if value != weapon { weapon=value;try rebuild() } }
    func setTreadPhase(_ value: Int) throws {
        phase=(value%4+4)%4;left.texture=try art.texture(rig.treads[0][phase]);right.texture=try art.texture(rig.treads[1][phase])
    }
    func setEquipment(_ name:String?) throws {
        let id:String?
        if let name {guard let found=art.manifest.equipment[name+"_"+Self.directions[direction]] else {throw PixelArtError.missing(name)};id=found} else {id=nil}
        equipmentNode?.removeFromParent();equipmentNode=nil;equipmentName=name
        if let id {
            let n=try art.sprite(id,scale:pixelScale);n.zPosition=(name=="amphi" || name=="anti_skid") ? 0 : 4;addChild(n);equipmentNode=n
        }
    }
    func setRecoil(_ value: CGFloat) {
        let t=max(0,min(1,value)),distance=sin(t * .pi)*2*pixelScale
        let dx:[CGFloat]=[0,1,0,-1],dy:[CGFloat]=[1,0,-1,0]
        turret.position=CGPoint(x:rig.mountOffset[0]*pixelScale-dx[direction]*distance,y:-rig.mountOffset[1]*pixelScale-dy[direction]*distance)
    }
    func muzzle(_ index: Int=0, in target: SKNode) -> CGPoint {
        let p=gun.muzzles[min(index,gun.muzzles.count-1)]
        return turret.convert(CGPoint(x:(p[0]-gun.anchor[0])*pixelScale,y:(gun.anchor[1]-p[1])*pixelScale),to:target)
    }
    var muzzleCount: Int { gun.muzzles.count }
    func visibleRect(in target: SKNode) -> CGRect {
        var r=CGRect.null
        for (node,id) in [(hull!,rig.hull),(left!,rig.treads[0][phase]),(right!,rig.treads[1][phase]),(turret!,gun.texture)] { r=r.union(art.visibleRect(node,id:id,in:target)) }
        if let node=equipmentNode,let id=node.name {r=r.union(art.visibleRect(node,id:id,in:target))}
        return r
    }
}
