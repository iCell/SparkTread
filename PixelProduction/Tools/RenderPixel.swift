import Foundation
import SpriteKit
import AppKit
import CryptoKit

@main struct RenderPixel {
    @MainActor static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),mode=CommandLine.arguments.count>2 ? CommandLine.arguments[2] : "arena"
        let device=CommandLine.arguments.count>3 ? CommandLine.arguments[3] : "phone"
        let phase=CommandLine.arguments.count>4 ? Int(CommandLine.arguments[4])! : 0
        let framePhase=phase%4,animationTime=Double(phase)/12
        let size:CGSize = device=="compact" ? CGSize(width:667,height:375) : device=="tablet" ? CGSize(width:1194,height:834) : CGSize(width:844,height:390)
        let art=try PixelArt(root:root),scene=SKScene(size:size);scene.scaleMode = .aspectFit;scene.backgroundColor=SKColor(red:0.18,green:0.17,blue:0.15,alpha:1)
        var checks:[[String:Any]]=[],objects:[[String:Any]]=[],tanks:[PixelTankNode]=[]
        func check(_ name:String,_ value:Bool) { checks.append(["name":name,"passed":value]) }
        func label(_ text:String,_ x:CGFloat,_ y:CGFloat,_ font:CGFloat=12,_ color:SKColor = .white) {
            let n=SKLabelNode(fontNamed:"Menlo-Bold");n.text=text;n.fontSize=font;n.fontColor=color;n.position=CGPoint(x:x,y:y);n.zPosition=9200;scene.addChild(n)
        }
        func sprite(_ id:String,_ p:CGPoint,_ scale:CGFloat,_ z:CGFloat=0) throws -> SKSpriteNode {
            let n=try art.sprite(id,scale:scale);n.position=p;n.zPosition=z;scene.addChild(n);return n
        }
        func panel(_ state:String,_ rect:CGRect) throws {
            let n=try sprite("px_ui_panel_"+state,CGPoint(x:rect.midX,y:rect.midY),1,8900);n.size=rect.size;n.centerRect=CGRect(x:0.25,y:0.25,width:0.5,height:0.5)
        }
        let columns=48,rows=27
        let cell=min((size.width-28)/CGFloat(columns),(size.height-34)/CGFloat(rows)),width=CGFloat(columns)*cell,height=CGFloat(rows)*cell
        let origin=CGPoint(x:(size.width-width)/2,y:10+(size.height-34-height)/2)
        let arena=CGRect(origin:origin,size:CGSize(width:width,height:height)),scale=cell/16
        func point(_ x:CGFloat,_ y:CGFloat)->CGPoint { CGPoint(x:origin.x+x*cell,y:origin.y+(CGFloat(rows)-y)*cell) }
        if mode=="roster" {
            let kinds=["player","scout","standard","armored","heavy"],weapons=["normal","rapid","fire","ap","explosion","mine"]
            for (r,kind) in kinds.enumerated() { for (c,weapon) in weapons.enumerated() {
                let t=try PixelTankNode(kind:kind,weapon:weapon,direction:phase%4,pixelScale:1.65,art:art);t.position=CGPoint(x:CGFloat(c+1)*size.width/7,y:size.height-48-CGFloat(r)*(size.height-65)/5);scene.addChild(t);try t.setTreadPhase(phase);tanks.append(t)
                label(kind+" "+weapon,t.position.x,t.position.y-31,8)
            }}
        } else if mode=="directions" {
            for row in 0..<3 {for dir in 0..<4 {
                let t=try PixelTankNode(kind:row==0 ? "player" : "standard",weapon:row==2 ? "fire" : "normal",direction:dir,pixelScale:2,art:art)
                t.position=CGPoint(x:CGFloat(dir+1)*size.width/5,y:size.height-65-CGFloat(row)*105);scene.addChild(t);try t.setTreadPhase(phase);tanks.append(t)
                label(PixelTankNode.directions[dir],t.position.x,t.position.y-43,10)
            }}
        } else {
            // Complete fixed arena fixture, not an authored campaign or authority simulation.
            for y in stride(from:0,to:rows,by:3) {for x in stride(from:0,to:columns,by:3) {
                let n=try sprite("px_ground_frontier_\((x/3+y/3)%9)",point(CGFloat(x)+1.5,CGFloat(y)+1.5),scale,0)
                n.size=CGSize(width:cell*3,height:cell*3)
            }}
            var solids=Set<String>(),wallNodes:[String:(SKSpriteNode,String,Int)]=[:]
            func wall(_ x:Int,_ y:Int,_ kind:String="brick",_ remaining:Int=15) throws {
                let id=remaining==15 ? "px_\(kind)_connected_00" : String(format:"px_%@_remaining_%02d",kind,remaining)
                let n=try sprite(id,point(CGFloat(x)+0.5,CGFloat(y)+0.5),scale,100+CGFloat(y)*10);solids.insert("\(x),\(y)");wallNodes["\(x),\(y)"]=(n,kind,remaining)
            }
            for x in 0..<columns { try wall(x,0,x%5==0 ? "steel" : "brick");try wall(x,rows-1,x%5==0 ? "steel" : "brick") }
            for y in 1..<(rows-1) { try wall(0,y,y%5==0 ? "steel" : "brick");try wall(columns-1,y,y%5==0 ? "steel" : "brick") }
            for (y,ranges) in [(5,[12...18,25...29,36...40]),(11,[5...10,18...22,28...31]),(18,[8...13,21...25,35...40])] {
                for range in ranges { for x in range {try wall(x,y,x==range.lowerBound ? "steel" : "brick",mode=="arena" && phase==3 && y==11 && x==21 ? 3 : 15)} }
            }
            for y in 7...10 { try wall(15,y) };for y in 13...16 {try wall(29,y)}
            for y in 22...25 {try wall(21,y);try wall(27,y)};for x in 22...26 {try wall(x,25)}
            for (key,(node,kind,remaining)) in wallNodes {
                let xy=key.split(separator:",").map{Int($0)!};var mask=0
                for (bit,dx,dy) in [(1,0,-1),(2,1,0),(4,0,1),(8,-1,0)] where wallNodes["\(xy[0]+dx),\(xy[1]+dy)"]?.1==kind {mask |= bit}
                node.texture=try art.texture(String(format:"px_%@_joint_%02d_%02d",kind,mask,remaining))
            }
            let offsets=[(1,0,-1),(2,1,0),(4,0,1),(8,-1,0),(16,1,-1),(32,1,1),(64,-1,1),(128,-1,-1)]
            func liquid(_ kind:String,_ cells:Set<String>) throws {
                for s in cells.sorted() {
                    let xy=s.split(separator:",").map{Int($0)!};let x=xy[0],y=xy[1];var mask=0
                    for(bit,dx,dy) in offsets where cells.contains("\(x+dx),\(y+dy)"){mask |= bit}
                    for(diag,a,b) in [(16,1,2),(32,2,4),(64,4,8),(128,8,1)] where mask&a==0 || mask&b==0 { mask &= ~diag }
                    let id=String(format:"px_%@_%03d_%d",kind,mask,phase%4)
                    _=try sprite(id,point(CGFloat(x)+0.5,CGFloat(y)+0.5),scale,5)
                }
            }
            var waters=Set<String>()
            for (ox,oy) in [(4,5),(34,10)] {for y in 0..<5 {for x in 0..<7 where !(x==0 && (y==0 || y==4)) && !(x==6 && y<2) {waters.insert("\(ox+x),\(oy+y)")}}}
            try liquid("water",waters)
            // Small, deterministic scenic dressing stays below silhouettes and never creates solids.
            for i in 0..<115 {
                let x=1+(i*17+3)%46,y=1+(i*11+i/8)%25
                guard !solids.contains("\(x),\(y)"),!waters.contains("\(x),\(y)"),!(x>39 && y<7) else {continue}
                let name=i%11==0 ? "flowers" : i%4==0 ? "moss" : "pebbles"
                let n=try sprite("px_prop_"+name,point(CGFloat(x)+0.25,CGFloat(y)+0.6),scale*(i%4==0 ? 0.62 : 0.34),6);n.alpha=name=="pebbles" ? 0.72 : 0.92
            }
            for (key,_) in wallNodes where !key.hasPrefix("0,") {
                let xy=key.split(separator:",").map{Int($0)!};let x=xy[0],y=xy[1]
                if (x+y)%5==0 && y<25 && !solids.contains("\(x),\(y+1)") {
                    _=try sprite("px_prop_moss",point(CGFloat(x)+0.5,CGFloat(y)+1.15),scale*0.5,91+CGFloat(y)*10)
                }
            }
            var ice=Set<String>();for y in 3...6 {for x in 40...44 {ice.insert("\(x),\(y)")}};try liquid("ice",ice)
            for (i,xy) in [(3,3),(12,7),(18,12),(33,17),(40,20),(6,19),(30,8),(44,23),(17,23)].enumerated() {
                _=try sprite("px_prop_"+(i%3==0 ? "bush_sparse" : "bush_dense"),point(CGFloat(xy.0),CGFloat(xy.1)),scale*0.75,90+CGFloat(xy.1)*10)
            }
            _=try sprite("px_prop_lily",point(7,7),scale*0.5,10)
            _=try sprite("px_prop_rocks",point(32,22),scale*0.5,100)
            _=try sprite("px_prop_drain",point(42,8),scale*0.55,10)
            _=try sprite("px_prop_bridge_ns",point(37,10),scale*0.8,20)
            for x:CGFloat in [9,24,38] {_=try sprite("px_prop_spawn",point(x,2.5),scale*0.6,20)}
            let base=try sprite(art.manifest.baseStates[mode=="arena" && phase==3 ? 2 : 0],point(24,23.7),scale*0.82,337)
            objects.append(["kind":"base","rect":[base.frame.minX,base.frame.minY,base.frame.width,base.frame.height]])
            let specs:[(String,String,Int,CGFloat,CGFloat)]=[("player","normal",0,19,22),("scout","normal",2,9,3.3),("standard","rapid",2,23,3.2),("armored","fire",3,37,8),("heavy","ap",3,41,17),("scout","mine",1,12,15),("standard","explosion",0,32,21),("scout","normal",0,6,22),("heavy","fire",1,23,14)]
            for (i,s) in specs.enumerated() {
                var dir=s.2,tx=s.3,ty=s.4
                if mode=="battle" && i==0 {
                    let leg=(phase/6)%4,u=CGFloat(phase%6)/6;dir=[0,3,2,1][leg]
                    tx=[19,19-2*u,17,17+2*u][leg];ty=[22-2*u,20,20+2*u,22][leg]
                }
                let t=try PixelTankNode(kind:s.0,weapon:s.1,direction:dir,pixelScale:scale*0.82,art:art)
                t.position=point(tx,ty);t.zPosition=100+ty*10;scene.addChild(t);tanks.append(t);try t.setTreadPhase(phase)
                if i==0 {t.setRecoil(CGFloat(framePhase)/3)}
                let rect=t.visibleRect(in:scene);check("tank \(i) entirely visible",arena.contains(rect));check("tank \(i) no physics",t.physicsBody==nil)
                objects.append(["kind":i==0 ? "player" : "enemy","rect":[rect.minX,rect.minY,rect.width,rect.height]])
                if i==0 || i==3 || i==4 {
                    let name=s.1=="normal" ? "muzzle" : s.1
                    if let frames=art.manifest.effects[name] {
                        let flash=try sprite(frames[framePhase],t.muzzle(in:scene),scale*0.48,650);flash.zRotation = -CGFloat(dir) * .pi/2
                    }
                    let dx:[CGFloat]=[0,1,0,-1],dy:[CGFloat]=[1,0,-1,0]
                    for step in 1...2 {
                        let p=t.muzzle(in:scene),id="px_projectile_"+s.1,travel=CGFloat(step)*1.4+(mode=="battle" ? CGFloat(framePhase)*0.24 : 0)
                        let bullet=try sprite(id,CGPoint(x:p.x+dx[dir]*cell*travel,y:p.y+dy[dir]*cell*travel),scale*0.8,660)
                        let bounds=art.manifest.sprites[id]!.contentBounds!,rawWidth=(bounds[2]-bounds[0])*scale*0.8,minWidth:CGFloat=s.1=="normal" ? 1.8 : 2.2
                        bullet.xScale=max(1,min(4,minWidth/rawWidth));bullet.zRotation = -CGFloat(dir) * .pi/2
                        check("bullet readable \(i) \(step)",rawWidth*bullet.xScale>=minWidth-0.01)
                    }
                }
                if i==6 {try t.setEquipment("moon")}
            }
            for (i,p) in [(16.0,20.0),(33.0,15.0),(6.0,16.0),(31.0,6.0)].enumerated() {
                _=try sprite("px_mine_\(i)_armed",point(p.0,p.1),scale*0.65,600)
            }
            for (id,x,y) in [(1,17.0,8.5),(21,31.0,18.0),(7,11.0,21.0)] {
                let p=try PixelPickupNode(id:id,pixelScale:scale*0.65,art:art);p.position=point(x,y);p.zPosition=620;scene.addChild(p);try p.update(phase:.idle,age:animationTime)
            }
            if phase>0 && mode != "battle" {
                _=try sprite("px_fx_explosion_\(phase%4)",point(26,12.8),scale*0.85,670)
                _=try sprite("px_fx_splash_\(phase%4)",point(35,13),scale*0.7,670)
                _=try sprite("px_fx_smoke_\(phase%4)",point(24,23.1),scale*0.4,670)
            }
            if mode=="battle" {
                let fx=try PixelEffectNode(kind:.tankExplosion,pixelScale:scale*0.85,art:art);fx.position=point(26,12.8);fx.zPosition=670;scene.addChild(fx);try fx.advance(to:animationTime.truncatingRemainder(dividingBy:1.5))
                let wake=try PixelEffectNode(kind:.waterHit,pixelScale:scale*0.7,art:art);wake.position=point(35,13);wake.zPosition=670;scene.addChild(wake);try wake.advance(to:animationTime.truncatingRemainder(dividingBy:1.5))
            }
            // UI controls retain screen-space sizes when world art is made smaller.
            let j=try sprite("px_ui_joystick_normal",CGPoint(x:max(44,origin.x+18),y:origin.y+47),1,8000);j.size=CGSize(width:76,height:76);j.alpha=0.6
            let knob=try sprite("px_ui_control_knob",j.position,1,8100);knob.size=CGSize(width:52,height:52);knob.alpha=0.82
            for (i,p) in [("normal",CGPoint(x:arena.maxX-72,y:origin.y+40)),("fire",CGPoint(x:min(size.width-38,arena.maxX-11),y:origin.y+83))] {
                let button=try sprite(phase==2 ? "px_ui_joystick_cooldown" : "px_ui_control_"+(i=="normal" ? "normal" : "special"),p,1,8000);button.size=CGSize(width:62,height:62);button.alpha=0.84
                let icon=try sprite(i=="normal" ? "px_projectile_normal" : art.manifest.pickups[21].texture,p,1,8100);icon.size=CGSize(width:i=="normal" ? 74 : 36,height:i=="normal" ? 74 : 36);icon.zRotation=i=="normal" ? -.pi/4 : 0
            }
            let hudY=arena.maxY+1
            try panel("normal",CGRect(x:origin.x+4,y:hudY,width:width-8,height:22))
            label("♥ 3   ARMOR 6/8",origin.x+91,hudY+7,10)
            label("01 · FRONTIER",size.width/2,hudY+7,11)
            label("BASE 85   ENEMY 18",arena.maxX-95,hudY+7,10)
            check("whole fixed 48x27 arena",scene.camera==nil && arena.minX>=0 && arena.maxX<=size.width && arena.maxY<=size.height)
            if mode != "arena" && mode != "battle" {
                let w=min(size.width*0.58,440.0),h=min(size.height*0.76,330.0),rect=CGRect(x:(size.width-w)/2,y:(size.height-h)/2,width:w,height:h)
                try panel("normal",rect)
                let titles=["pause":"暂停","victory":"任务完成","defeat":"基地失守","settings":"设置","selection":"关卡选择","tutorial":"保卫方形基地","tutorial_move":"移动坦克","tutorial_normal":"普通火力","tutorial_special":"特殊火力","tutorial_equipment":"辅助装备","tutorial_base":"保卫方形基地"]
                label(titles[mode] ?? "素材预览",size.width/2,rect.maxY-43,22)
                if mode=="selection" {
                    for i in 0..<6 {
                        let x=rect.minX+50+CGFloat(i%3)*(w-100)/2,y=rect.maxY-95-CGFloat(i/3)*88
                        let n=try sprite("px_ui_card_"+(i>1 ? "locked" : "selected"),CGPoint(x:x,y:y),1,9100);n.size=CGSize(width:80,height:65)
                        label(i>1 ? "LOCKED" : "TEST \(i+1)",x,y-8,9)
                    }
                } else if mode.hasPrefix("tutorial") {
                    let center=CGPoint(x:size.width/2,y:rect.midY+12)
                    if mode=="tutorial_move" {
                        let n=try sprite("px_ui_control_knob",center,1.6,9100);n.zPosition=9100
                        label("拖动摇杆 · 松手停止",size.width/2,rect.minY+65,14)
                    } else if mode=="tutorial_normal" || mode=="tutorial_special" {
                        let special=mode=="tutorial_special",t=try PixelTankNode(kind:"player",weapon:special ? "fire" : "normal",direction:0,pixelScale:1.9,art:art);t.position=CGPoint(x:center.x-38,y:center.y);t.zPosition=9100;scene.addChild(t)
                        let n=try sprite(special ? "px_ui_control_special" : "px_ui_control_normal",CGPoint(x:center.x+61,y:center.y),1.3,9100);n.zPosition=9100
                        _=try sprite(special ? art.manifest.pickups[21].texture : "px_projectile_normal",n.position,special ? 1.3 : 2.8,9150)
                        label(special ? "独立开火键 · 消耗特殊弹药" : "普通射击 · 注意开火节奏",size.width/2,rect.minY+65,14)
                    } else if mode=="tutorial_equipment" {
                        for (i,id) in [5,6,7,8].enumerated(){_=try sprite(art.manifest.pickups[id].texture,CGPoint(x:center.x+CGFloat(i)*64-96,y:center.y),1.6,9100)}
                        label("两栖 · 防滑 · 月牙盾 · 彩圈",size.width/2,rect.minY+65,14)
                    } else {
                        _=try sprite(art.manifest.baseStates[0],center,1.3,9100)
                        label("挡住通往基地的敌军",size.width/2,rect.minY+65,14)
                    }
                } else if mode=="settings" {
                    for (i,text) in ["控件大小   ━━━━━●━━","界面透明度 ━━━●━━━━","低刺激效果       ✓"].enumerated(){label(text,size.width/2,rect.maxY-92-CGFloat(i)*46,14)}
                } else {
                    let options=mode=="pause" ? ["继续游戏","设置","返回选关"] : mode=="victory" ? ["得分 12850","下一关","返回选关"] : ["重新挑战","返回选关"]
                    for (i,text) in options.enumerated() {
                        let y=rect.maxY-91-CGFloat(i)*50;let n=try sprite("px_ui_button_normal",CGPoint(x:size.width/2,y:y),1,9100);n.size=CGSize(width:w*0.67,height:38);n.centerRect=CGRect(x:0.25,y:0.25,width:0.5,height:0.5);label(text,size.width/2,y-5,14)
                    }
                }
                label("UI 素材渲染验证 · 非完整菜单流程",size.width/2,rect.minY+14,8)
            }
        }
        for t in tanks {check("direction rig no rotation",t.zRotation==0);check("full tank texture registration",!t.visibleRect(in:scene).isNull)}
        _=NSApplication.shared;let view=SKView(frame:CGRect(origin:.zero,size:size));view.presentScene(scene)
        guard let texture=view.texture(from:scene,crop:CGRect(origin:.zero,size:size)),let png=NSBitmapImageRep(cgImage:texture.cgImage()).representation(using:.png,properties:[:]) else { throw PixelArtError.missing("SpriteKit capture") }
        let filename="pixel_\(mode)_\(device)_\(phase)";try png.write(to:root.appendingPathComponent("Previews/\(filename).png"))
        let report:[String:Any]=["renderer":"SpriteKit SKView.texture","mode":mode,"deviceFixture":device,"sizePoints":[size.width,size.height],"pixelSize":[texture.cgImage().width,texture.cgImage().height],"phase":phase,"arenaCells":[48,27],"tankCount":tanks.count,"objects":objects,"checks":checks,"passed":checks.allSatisfy{$0["passed"] as? Bool == true},"imageSHA256":SHA256.hash(data:png).map{String(format:"%02x",$0)}.joined(),"assetManifestSHA256":SHA256.hash(data:try Data(contentsOf:root.appendingPathComponent("Metadata/pixel_assets.json")) ).map{String(format:"%02x",$0)}.joined(),"scope":"scripted art fixture, not a playable campaign, iOS build or physical-device acceptance"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("Metadata/\(filename).json"))
        print("\(filename): \(tanks.count) tanks, \(checks.count) checks, \(texture.cgImage().width)x\(texture.cgImage().height)")
    }
}
