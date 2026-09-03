"""Build current pixel art from approved generated sheets; deterministic local finishing.

No original-game assets. No changes to the pre-migration runtime package.
Source images are read-only; runtime exports have explicit alpha, registration and hashes.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import numpy as np
import hashlib, json, math, random, sys

ROOT=Path(__file__).resolve().parents[1]
WORK=Path(sys.argv[1]).resolve()
ATLAS=ROOT/'Atlases'
for p in [ATLAS,ROOT/'Metadata',ROOT/'Previews']:p.mkdir(parents=True,exist_ok=True)
N=Image.Resampling.NEAREST
sprites={}; sources={}; extracts={}
DIRS=['up','right','down','left']
KINDS=['player','scout','standard','armored','heavy']
WEAPONS=['normal','rapid','fire','ap','explosion','mine']

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def rgba(size):return Image.new('RGBA',size)
def crop_alpha(im):
    b=im.getchannel('A').getbbox()
    if not b:raise ValueError('Empty sprite')
    return im.crop(b),b
def finish(im,colors=40):
    a=np.array(im.getchannel('A'))
    rgb=im.convert('RGB').quantize(colors=colors,method=Image.Quantize.MEDIANCUT).convert('RGB')
    out=np.array(rgb.convert('RGBA'));out[:,:,3]=np.where(a>=100,255,0)
    out[out[:,:,3]==0,:3]=0
    return Image.fromarray(out)
def key_image(p):
    im=Image.open(p).convert('RGB');v=np.array(im).astype(np.int16)
    key=(v[:,:,0]>120)&(v[:,:,2]>100)&(v[:,:,1]<0.55*np.minimum(v[:,:,0],v[:,:,2]))
    a=np.concatenate([v.astype(np.uint8),np.where(key,0,255).astype(np.uint8)[:,:,None]],axis=2)
    a[key,:3]=0
    return Image.fromarray(a)
def groups(mask,count,axis):
    coords=np.flatnonzero(mask.any(axis=axis))
    if len(coords)<count:raise ValueError('Missing grid row/column')
    gaps=np.diff(coords)
    cuts=sorted((np.argsort(gaps)[-(count-1):]+1).tolist()) if count>1 else []
    parts=np.split(coords,cuts)
    return [(int(p[0]),int(p[-1])+1) for p in parts]
def sheet(name,rows,cols):
    p=WORK/(name+'.png');sources[name]={'path':str(p),'sha256':sha(p)}
    im=key_image(p);a=np.array(im.getchannel('A'))>0
    ys=groups(a,rows,axis=1);out=[];bs=[]
    for y0,y1 in ys:
        xs=groups(a[y0:y1],cols,axis=0)
        for x0,x1 in xs:
            box=(max(0,x0-1),max(0,y0-1),min(im.width,x1+1),min(im.height,y1+1))
            item=im.crop(box);item,b=crop_alpha(item);out.append(item)
            bs.append([box[0]+b[0],box[1]+b[1],box[0]+b[2],box[1]+b[3]])
    extracts[name]=bs
    return out
def place(im,target=(30,28),canvas=(64,64),center=(32,35),colors=40):
    s=min(target[0]/im.width,target[1]/im.height)
    size=(max(1,round(im.width*s)),max(1,round(im.height*s)))
    tile=finish(im.resize(size,Image.Resampling.BOX),colors)
    out=rgba(canvas);out.alpha_composite(tile,(round(center[0]-size[0]/2),round(center[1]-size[1]/2)))
    return out
def save(id,im,atlas,role,anchor=None,origin='derived'):
    if id in sprites:raise ValueError('Duplicate '+id)
    p=ATLAS/(atlas+'.atlas')/(id+'.png');p.parent.mkdir(exist_ok=True)
    im.save(p)
    b=im.getchannel('A').getbbox()
    sprites[id]={'id':id,'path':str(p.relative_to(ROOT)),'atlas':atlas,'pixelSize':list(im.size),'anchorTopLeft':anchor or [im.width/2,im.height/2], 'contentBounds':list(b) if b else None,'role':role,'origin':origin,'sha256':sha(p)}
    return id
def tint(im,color,amount=.6):
    a=np.array(im).copy();lum=np.mean(a[:,:,:3],axis=2)/255
    for c in range(3):a[:,:,c]=np.clip(a[:,:,c]*(1-amount)+color[c]*lum*amount,0,255)
    return Image.fromarray(a)

# Directional hulls and independent rolling track strips.
hulls=sheet('hulls',5,4);rigs={}
for r,kind in enumerate(KINDS):
    for di,direction in enumerate(DIRS):
        full=place(hulls[r*4+di],(30,28),center=(32,35))
        a=np.array(full);b=full.getchannel('A').getbbox();x0,y0,x1,y1=b
        xx,yy=np.meshgrid(np.arange(64),np.arange(64))
        if di%2==0:
            left=(xx<x0+(x1-x0)*.23);right=(xx>=x1-(x1-x0)*.23)
        else:
            left=(yy<y0+(y1-y0)*.23);right=(yy>=y1-(y1-y0)*.29)
        masks=[left&(a[:,:,3]>0),right&(a[:,:,3]>0)]
        body=a.copy();body[masks[0]|masks[1]]=0
        hid=save(f'px_hull_{kind}_{direction}',Image.fromarray(body),'PixelTanks','hull',[32,35],'hulls')
        tracks=[]
        for side,mask in zip(['left','right'],masks):
            ids=[]
            for phase in range(4):
                v=a.copy();v[~mask]=0
                # Animate only interior dark rubber shade; never translate an alpha edge.
                interior=mask.copy()
                for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:interior &= np.roll(mask,(dy,dx),(0,1))
                dark=(a[:,:,:3].max(axis=2)<135)&interior
                coord=yy if di%2==0 else xx
                change=np.where((coord+phase)%4<2,11,-9)
                for c in range(3):v[:,:,c]=np.where(dark,np.clip(v[:,:,c].astype(int)+change,0,255),v[:,:,c])
                ids.append(save(f'px_tread_{kind}_{direction}_{side}_{phase}',Image.fromarray(v),'PixelTreads','tread',[32,35],'hulls + shade phase'))
            tracks.append(ids)
        rigs[kind+'_'+direction]={'hull':hid,'treads':tracks,'anchor':[32,35],'mountOffset':[0,-3],'bodyBounds':list(b)}

ta=sheet('turrets_a',4,4);tb=sheet('turrets_b',3,4)
turrets={}
for row,(family,arr,width) in enumerate([
    ('player_normal',ta[0:4],17),('enemy_normal',ta[4:8],17),('rapid',ta[8:12],20),('fire',ta[12:16],20),
    ('ap',tb[0:4],16),('explosion',tb[4:8],20),('mine',tb[8:12],21)]):
    factor=width/arr[0].width
    for di,(direction,im) in enumerate(zip(DIRS,arr)):
        bw=arr[0].width;w,h=im.size
        if di==0:pivot=(w/2,h-bw*.49)
        elif di==1:pivot=(bw*.49,h*.52)
        elif di==2:pivot=(w/2,bw*.48)
        else:pivot=(w-bw*.49,h*.52)
        tile=finish(im.resize((max(1,round(w*factor)),max(1,round(h*factor))),Image.Resampling.BOX))
        out=rgba((64,64));pos=(round(32-pivot[0]*factor),round(32-pivot[1]*factor))
        if min(pos)<0 or pos[0]+tile.width>64 or pos[1]+tile.height>64:raise ValueError('Turret overflow')
        out.alpha_composite(tile,pos);id=save(f'px_turret_{family}_{direction}',out,'PixelTurrets','turret',[32,32],family)
        aa=np.array(out.getchannel('A'))>0;ys,xs=np.where(aa)
        if di==0:e=int(ys.min());coords=np.where(aa[e])[0];tips=[[float(coords.mean()),float(e)]]
        elif di==1:e=int(xs.max());coords=np.where(aa[:,e])[0];tips=[[float(e),float(coords.mean())]]
        elif di==2:e=int(ys.max());coords=np.where(aa[e])[0];tips=[[float(coords.mean()),float(e)]]
        else:e=int(xs.min());coords=np.where(aa[:,e])[0];tips=[[float(e),float(coords.mean())]]
        if family=='rapid':
            mid=float(coords.mean());parts=[coords[coords<mid],coords[coords>=mid]]
            if all(len(z) for z in parts):tips=[[float(z.mean()),float(e)] if di%2==0 else [float(e),float(z.mean())] for z in parts]
        turrets[family+'_'+direction]={'texture':id,'anchor':[32,32],'muzzles':tips,'rearDeploy':[32,43] if di==0 else [21,32] if di==1 else [32,21] if di==2 else [43,32]}

# Background-cleaned square base. One shared scale and ground baseline for all damage states.
bases=sheet('base',1,4);baseids=[];base_scale=40/bases[0].width
for index,item in enumerate(bases):
    tile=finish(item.resize((round(item.width*base_scale),round(item.height*base_scale)),Image.Resampling.BOX),36)
    out=rgba((64,64));out.alpha_composite(tile,(32-tile.width//2,54-tile.height))
    baseids.append(save('px_base_'+['healthy','damaged','critical','destroyed'][index],out,'PixelBase','base',[32,35],'base, fixed scale and ground baseline'))

# Catalog preserves all 25 distinct gameplay IDs.
icons=sheet('pickups',5,5);catalog=json.loads((ROOT/'Metadata/pickup_catalog.json').read_text())['items']
for i,item in enumerate(catalog):
    item['texture']=save('px_pickup_'+item['key'],place(icons[i],(22,22),(32,32),(16,16),32),'PixelPickups','pickup',origin='pickups')

equipment=sheet('equipment',4,4);equipmentIds={}
for r,kind in enumerate(['amphi','anti_skid','moon','memory']):
    for di,d in enumerate(DIRS):
        target=(40,34) if r<2 else (16,18) if r==2 else (11,11)
        center=(32,35) if r<2 else (48,32) if r==2 else [(32,42),(22,35),(32,27),(42,35)][di]
        equipmentIds[kind+'_'+d]=save(f'px_equipment_{kind}_{d}',place(equipment[r*4+di],target,(64,64),center,32),'PixelEquipment','equipment',[32,35],'equipment')

proj=sheet('projectiles',4,5);projectiles={}
for i,w in enumerate(WEAPONS[:5]):
    size=[(4,8),(3,10),(7,10),(3,16),(7,11)][i]
    body=save('px_projectile_'+w,place(proj[i],size,(32,32),(16,16),24),'PixelProjectiles','projectile',origin='projectiles')
    trail=save('px_trail_'+w,place(proj[5+i],(5,17),(32,32),(16,20),24),'PixelProjectiles','trail',origin='projectiles')
    projectiles[w]={'body':body,'trail':trail,'minimumWidthPixels':size[0]}
for level in range(4):
    for row,state in [(2,'armed'),(3,'dormant')]:
        save(f'px_mine_{level}_{state}',place(proj[row*5+level],(18+level,17+level),(32,32),(16,17),32),'PixelMines','mine',[16,17],'projectiles')
for row,kind in [(2,'metal'),(3,'brick')]:save('px_debris_'+kind,place(proj[row*5+4],(16,12),(32,32),(16,16)),'PixelEffects','debris',origin='projectiles')

# Animation frames preserve row-relative size rather than filling every frame independently.
fx=sheet('effects',6,4);fxnames=['muzzle','fire','explosion','smoke','splash','spark'];fxIds={}
for r,name in enumerate(fxnames):
    arr=fx[r*4:r*4+4];mw=max(x.width for x in arr);mh=max(x.height for x in arr);scale=30/max(mw,mh)
    ids=[]
    for f,im in enumerate(arr):
        tile=finish(im.resize((max(1,round(im.width*scale)),max(1,round(im.height*scale))),Image.Resampling.BOX),28)
        out=rgba((48,48));cy=33-tile.height if r<2 else 24-tile.height//2
        out.alpha_composite(tile,(24-tile.width//2,cy))
        ids.append(save(f'px_fx_{name}_{f}',out,'PixelEffects','effect',[24,33] if r<2 else [24,24],'effects'))
    fxIds[name]=ids
for name,col in [('rapid',(140,220,70)),('ap',(192,154,255)),('shield',(130,240,255)),('ice',(190,226,255)),('brick_dust',(190,123,75)),('steam',(218,227,225))]:
    parent='muzzle' if name in ['rapid','ap'] else 'splash' if name in ['shield','ice'] else 'smoke'
    fxIds[name]=[]
    for f,id in enumerate(fxIds[parent]):
        im=Image.open(ROOT/sprites[id]['path']).convert('RGBA')
        fxIds[name].append(save(f'px_fx_{name}_{f}',tint(im,col,.7),'PixelEffects','effect',sprites[id]['anchorTopLeft'],'derived '+parent))

terrain=sheet('terrain',4,4)
environment=sheet('environment',4,4)
THEMES=['frontier','floodplain','frozen','citadel']
for ti,theme in enumerate(THEMES):
    raw=terrain[[0,1,3,2][ti]].resize((48,48),Image.Resampling.BOX).convert('RGB')
    arr=np.array(raw);base=np.median(arr.reshape(-1,3),axis=0)
    # Quiet matching perimeter suppresses tile seams; middle retains generated texture.
    for y in range(48):
        for x in range(48):
            t=min(1,min(x,y,47-x,47-y)/4)
            arr[y,x]=base*(1-t)+arr[y,x]*t
    raw=Image.fromarray(arr).quantize(colors=12).convert('RGBA')
    for variant in range(9):
        im=raw.copy()
        if variant:im=im.transpose([Image.Transpose.FLIP_LEFT_RIGHT,Image.Transpose.FLIP_TOP_BOTTOM,Image.Transpose.ROTATE_180][variant%3])
        save(f'px_ground_{theme}_{variant}',im,'PixelGround','ground',origin='terrain floor + seam finishing')

for name,index in [('bush_sparse',8),('bush_dense',9),('rocks',10),('rubble',11),('lily',13),('drain',14),('spawn',15),('bridge',7)]:
    target=(30,30) if name in ['spawn','bridge'] else (28,24)
    save('px_prop_'+name,place(terrain[index],target,(40,40),(20,22),32),'PixelTerrain','prop',[20,22],'terrain')
for name,index,target in [('clay_rubble',2,(22,20)),('steel_rubble',3,(22,20)),('moss',4,(30,25)),('pebbles',5,(26,22)),('earth_cracks',6,(30,25)),('flowers',7,(22,22)),('bridge_ns',10,(28,36)),('bridge_ew',11,(36,28)),('border_corner',12,(32,30)),('border_straight',13,(36,22)),('bank_straight',14,(32,30)),('bank_corner',15,(32,30))]:
    save('px_prop_'+name,place(environment[index],target,(48,48),(24,26),32),'PixelTerrain','prop',[24,26],'environment')
fxIds['leaves']=[]
for f in range(4):
    im=place(environment[4],(12+f*4,10+f*3),(48,48),(24,24),16)
    fxIds['leaves'].append(save(f'px_fx_leaves_{f}',im,'PixelEffects','effect',[24,24],'environment moss scatter'))

def canonical(v):
    for diagonal,a,b in [(16,1,2),(32,2,4),(64,4,8),(128,8,1)]:
        if v&a==0 or v&b==0:v &= ~diagonal
    return v
MASKS=sorted({canonical(v) for v in range(256)})
assert len(MASKS)==47
def connected_mask(v,size=16):
    m=Image.new('L',(size,size),255);d=ImageDraw.Draw(m)
    # N/E/S/W missing edges use a two-pixel curved corner inset.
    for a,b,rect in [(1,8,(0,0,2,2)),(1,2,(size-3,0,size-1,2)),(4,2,(size-3,size-3,size-1,size-1)),(4,8,(0,size-3,2,size-1))]:
        if not v&a and not v&b:d.rectangle(rect,fill=0)
    for bit,a,b,rect in [(16,1,2,(size-2,0,size-1,1)),(32,2,4,(size-2,size-2,size-1,size-1)),(64,4,8,(0,size-2,1,size-1)),(128,8,1,(0,0,1,1))]:
        if v&a and v&b and not v&bit:d.rectangle(rect,fill=0)
    return m
def inset_material(im):
    w,h=im.size
    return finish(im.crop((round(w*.12),round(h*.12),round(w*.88),round(h*.88))).resize((16,16),Image.Resampling.BOX),12)
water=inset_material(environment[8])
ice=inset_material(environment[9])
for kind,raw,frames in [('water',water,4),('ice',ice,4)]:
    for mask in MASKS:
        for f in range(frames):
            im=raw.copy();d=ImageDraw.Draw(im)
            if kind=='water':
                for x,y in [(3,5),(11,12)]:d.line([(x+f%2,y),(x+3+f%2,y)],fill=(99,184,188,255),width=1)
            else:
                d.point((4+f*2,7),fill=(233,250,249,255))
            edge=(222,184,114,255) if kind=='water' else (218,239,241,255)
            for bit,line,inner in [(1,[(0,0),(15,0)],[(0,1),(15,1)]),(2,[(15,0),(15,15)],[(14,0),(14,15)]),(4,[(0,15),(15,15)],[(0,14),(15,14)]),(8,[(0,0),(0,15)],[(1,0),(1,15)])]:
                if not mask&bit:
                    d.line(inner,fill=(108,92,65,255) if kind=='water' else (151,194,203,255),width=1)
                    d.line(line,fill=edge,width=1)
            im.putalpha(connected_mask(mask));save(f'px_{kind}_{mask:03}_{f}',im,'PixelLiquids',kind,origin='terrain + canonical topology')

for kind,src in [('brick',environment[0]),('steel',environment[1])]:
    full=finish(src.resize((16,16),Image.Resampling.BOX),20)
    for rem in range(16):
        im=full.copy();a=np.array(im);quads=[(0,0,8,8),(8,0,16,8),(0,8,8,16),(8,8,16,16)]
        for bit,(x0,y0,x1,y1) in enumerate(quads):
            if not rem&(1<<bit):a[y0:y1,x0:x1]=0
        im=Image.fromarray(a);d=ImageDraw.Draw(im)
        # Exposed cut edges receive a dark front edge inside surviving quadrants.
        if rem&1 and not rem&4:d.line([(0,7),(7,7)],fill=(94,55,39,255) if kind=='brick' else (60,67,73,255))
        if rem&2 and not rem&8:d.line([(8,7),(15,7)],fill=(94,55,39,255) if kind=='brick' else (60,67,73,255))
        save(f'px_{kind}_remaining_{rem:02}',im,'PixelWalls','wall',origin='terrain + quadrant cut finishing')
    for conn in range(16):
        im=full.copy();d=ImageDraw.Draw(im);col=(107,66,43,255) if kind=='brick' else (55,62,65,255)
        for bit,line in [(1,[(0,0),(15,0)]),(2,[(15,0),(15,15)]),(4,[(0,15),(15,15)]),(8,[(0,0),(0,15)])]:
            if not conn&bit:d.line(line,fill=col)
        save(f'px_{kind}_connected_{conn:02}',im,'PixelWalls','wall',origin='terrain + edge finishing')
    for state in ['hit','scorch']:
        im=full.copy();d=ImageDraw.Draw(im)
        d.line([(3,3),(7,6),(5,9),(12,13)],fill=(237,195,128,255) if state=='hit' else (60,47,40,255),width=2)
        save(f'px_{kind}_{state}',im,'PixelWalls','wall overlay',origin='derived damage')
    # Joint state: preserve quarter destruction AND cardinal connections.
    for conn in range(16):
        edge=np.array(Image.open(ROOT/sprites[f'px_{kind}_connected_{conn:02}']['path']))
        for rem in range(16):
            a=np.array(Image.open(ROOT/sprites[f'px_{kind}_remaining_{rem:02}']['path']))
            active=a[:,:,3]>0;perimeter=np.zeros((16,16),dtype=bool)
            perimeter[0,:]=True;perimeter[-1,:]=True;perimeter[:,0]=True;perimeter[:,-1]=True
            apply=active&perimeter;a[apply,:3]=edge[apply,:3]
            save(f'px_{kind}_joint_{conn:02}_{rem:02}',Image.fromarray(a),'PixelWalls','wall',origin='joint cardinal connection and remaining quadrant mask')

foliage=finish(terrain[9].resize((16,16),Image.Resampling.BOX),14)
for mask in MASKS:
    for f in range(3):
        im=foliage.copy();im.putalpha(Image.fromarray(np.minimum(np.array(im.getchannel('A')),np.array(connected_mask(mask)))));d=ImageDraw.Draw(im)
        for x,y in [(3,4),(10,11),(12,5)]:d.point((x+(f%2),y),fill=(154,159,55,255))
        save(f'px_foliage_{mask:03}_{f}',im,'PixelFoliage','foliage',origin='terrain + canonical topology')
for state in ['burned','sparse']:
    im=tint(foliage,(80,55,40),.85) if state=='burned' else Image.open(ROOT/sprites['px_prop_bush_sparse']['path']).resize((16,16),N)
    save('px_foliage_'+state,im,'PixelFoliage','foliage',origin='derived foliage state')

# Code-native geometric overlays and UI: crisp at the logical pixel grid.
ringColors={'spawn':(118,223,249),'danger':(243,101,62),'shield':(123,227,255),'freeze':(187,233,248),'slow':(180,151,226),'upgrade':(255,219,99),'elite':(253,128,65),'pickup':(235,201,101),'mine_warning':(239,106,65),'repair':(128,216,137)}
for name,col in ringColors.items():
    for f in range(5):
        im=rgba((64,64));d=ImageDraw.Draw(im);inset=9+f%3
        d.ellipse((inset,19+f%2,63-inset,49-f%2),outline=col+(210,),width=1 if f in [0,4] else 2)
        if name in ['danger','elite','mine_warning']:d.polygon([(30,8),(34,8),(32,14)],fill=col+(255,))
        save(f'px_status_{name}_{f}',im,'PixelStatus','status',[32,35],'code-native geometry')
for level in range(4):
    for kind in ['armor','power','speed','damage']:
        im=rgba((64,64));d=ImageDraw.Draw(im)
        if kind=='damage':
            for i in range(level+1):d.line([(22+i*4,29),(24+i*4,31),(23+i*4,34)],fill=(51,38,36,230))
        else:
            col={'armor':(186,203,217,255),'power':(252,203,83,255),'speed':(95,217,235,255)}[kind]
            for i in range(level+1):d.rectangle((25+i*4,47,27+i*4,49),fill=col)
        save(f'px_status_{kind}_{level}',im,'PixelStatus','status',[32,35],'code-native geometry')
for kind,col in [('scorch',(63,47,34,140)),('crack',(75,55,40,180)),('tread',(94,73,45,100)),('ice_skid',(207,239,241,180))]:
    for f in range(3):
        im=rgba((32,32));d=ImageDraw.Draw(im);rng=random.Random(f+44)
        if kind=='scorch':d.ellipse((6,9,25,23),fill=col)
        elif kind=='crack':d.line([(5,8),(14,13),(11,20),(26,23)],fill=col)
        else:
            for y in range(4,28,4):
                for x in [8,22]:d.line([(x,y),(x+2,y)],fill=col)
        save(f'px_decal_{kind}_{f}',im,'PixelDecals','decal',origin='code-native geometry')

uiColors={'normal':(81,75,64,220),'pressed':(138,103,44,245),'disabled':(73,74,72,150),'cooldown':(65,84,91,205),'empty':(120,65,51,220),'selected':(65,126,139,225),'locked':(58,61,63,210)}
for state,col in uiColors.items():
    for shape in ['button','panel','card','joystick']:
        im=rgba((48,48));d=ImageDraw.Draw(im)
        if shape=='joystick':d.ellipse((3,3,44,44),fill=col,outline=(223,205,154,220),width=2)
        else:d.rounded_rectangle((3,3,44,44),radius=4,fill=col,outline=(216,193,140,240),width=2)
        save(f'px_ui_{shape}_{state}',im,'PixelUI','ui',origin='code-native geometry')
for name in ['pause','play','retry','settings','exit','up','right','down','left','warning','check','lock','controller','save','timer']:
    im=rgba((24,24));d=ImageDraw.Draw(im);col=(248,236,200,255)
    if name=='pause':d.rectangle((7,5,9,19),fill=col);d.rectangle((14,5,16,19),fill=col)
    elif name in ['play','up','right','down','left']:
        d.polygon([(7,5),(18,12),(7,19)],fill=col)
        if name in ['up','down','left']:im=im.rotate({'up':90,'down':-90,'left':180}[name],resample=N)
    elif name=='timer':d.ellipse((4,4,20,20),outline=col,width=2);d.line([(12,6),(12,12),(17,12)],fill=col,width=2)
    elif name=='retry':d.arc((4,4,20,20),35,310,fill=col,width=2);d.polygon([(18,3),(21,10),(14,8)],fill=col)
    elif name=='settings':
        d.ellipse((6,6,18,18),outline=col,width=3)
        for x,y in [(10,3),(10,18),(3,10),(18,10)]:d.rectangle((x,y,x+3,y+3),fill=col)
    elif name=='save':d.rectangle((4,4,20,20),outline=col,width=2);d.rectangle((8,4,16,10),fill=col);d.rectangle((8,14,16,20),outline=col)
    elif name=='check':d.line([(4,12),(10,18),(20,6)],fill=col,width=3)
    elif name=='warning':d.polygon([(12,3),(22,21),(2,21)],outline=col);d.line([(12,8),(12,14)],fill=col,width=2);d.point((12,18),fill=col)
    elif name=='lock':d.arc((7,3,17,15),180,360,fill=col,width=2);d.rectangle((5,11,19,21),outline=col,width=2)
    elif name=='exit':d.line([(5,5),(19,19)],fill=col,width=3);d.line([(19,5),(5,19)],fill=col,width=3)
    else:d.rounded_rectangle((3,6,21,19),radius=3,outline=col,width=2);d.line([(7,9),(7,16)],fill=col);d.line([(4,12),(10,12)],fill=col);d.point((17,11),fill=col)
    save('px_ui_icon_'+name,im,'PixelUI','ui icon',origin='code-native geometry')

# Shared state layers are composed at runtime, not duplicated once per object.
for owner in ['player','enemy']:
    im=rgba((16,16));d=ImageDraw.Draw(im)
    if owner=='player':d.ellipse((2,2,13,13),fill=(88,192,211,255),outline=(29,52,62,255));d.line([(5,7),(8,10),(11,6)],fill=(240,244,215,255),width=2)
    else:d.polygon([(8,1),(14,8),(8,14),(1,8)],fill=(232,107,60,255));d.line([(5,5),(11,11)],fill=(61,33,31,255),width=2);d.line([(5,11),(11,5)],fill=(61,33,31,255),width=2)
    save('px_badge_'+owner,im,'PixelStatus','status',origin='code-native shape ownership')
for f in range(5):
    im=rgba((64,64));d=ImageDraw.Draw(im);inset=9+f%2
    d.rounded_rectangle((inset,13,63-inset,55),radius=4,outline=(119,225,242,200 if f!=3 else 120),width=2)
    save(f'px_base_shield_{f}',im,'PixelBase','base shield',[32,35],'code-native square field')
for style,col in [('knob',(46,111,130,240)),('normal',(184,132,39,240)),('special',(203,94,42,240))]:
    im=rgba((48,48));d=ImageDraw.Draw(im)
    d.ellipse((3,3,44,44),fill=(56,49,38,255),outline=(205,179,113,255),width=2)
    d.ellipse((7,7,40,40),fill=col,outline=(235,197,112,255),width=2)
    if style=='knob':
        for p in [[(24,9),(21,13),(27,13)],[(24,38),(21,34),(27,34)],[(9,24),(13,21),(13,27)],[(38,24),(34,21),(34,27)]]:d.polygon(p,fill=(159,209,211,255))
    save('px_ui_control_'+style,im,'PixelUI','ui',origin='code-native control')
for phase in ['spawning','idle','collecting','replacing','atLimit','expired']:
    im=rgba((40,40));d=ImageDraw.Draw(im)
    if phase!='expired':
        d.rounded_rectangle((5,5,34,34),radius=5,fill=(59,60,53,210),outline=(217,188,116,255),width=2)
        if phase=='atLimit':d.line([(12,29),(28,29)],fill=(248,227,168,255),width=2)
        elif phase=='replacing':d.arc((2,2,37,37),30,300,fill=(143,221,214,255),width=1)
    save('px_pickup_frame_'+phase,im,'PixelPickups','pickup frame',origin='code-native shared container')

event_families={
 'brickHit':['brick_dust','spark'],'steelHit':['spark'],'armorHit':['spark'],'shieldHit':['ring_shield'],'waterHit':['splash'],
 'projectileCancel':['spark'],'tankExplosion':['explosion','smoke'],'groundExplosion':['explosion','brick_dust'],
 'apEntry':['ap','spark'],'apExit':['ap'],'fireIgnite':['fire'],'fireBurn':['fire','smoke'],
 'fireExtinguish':['smoke'],'waterExtinguish':['steam','splash'],'mineArming':['upgrade'],'mineTrigger':['danger'],
 'mineDisarm':['repair'],'spawnWarning':['danger'],'spawnComplete':['spawn'],'pickupSpawn':['pickup'],
 'pickupCollect':['pickup','spark'],'upgrade':['upgrade','spark'],'repair':['repair'],'baseHit':['spark','danger'],
 'baseCritical':['danger'],'baseShieldAppear':['square_shield'],'baseShieldEnd':['square_shield'],'freezeBurst':['freeze','ice'],
 'iceHit':['ice'],'foliageHit':['leaves'],'amphiWake':['splash'],'skidTrail':['decal_skid']}
event_recipes={}
for event,families in event_families.items():
    parts=[]
    for j,family in enumerate(families):
        ids=[f'px_status_shield_{f}' for f in range(5)] if family=='ring_shield' else [f'px_base_shield_{f}' for f in range(5)] if family=='square_shield' else [f'px_decal_ice_skid_{f}' for f in range(3)] if family=='decal_skid' else fxIds.get(family,[f'px_status_{family}_{f}' for f in range(5)])
        parts.append({'frames':ids,'delay':j*.07,'duration':.65 if family in ['smoke','steam','brick_dust','repair'] else .4,'offset':[0,0],'travel':[0,6 if family in ['smoke','steam'] else 0],'scale':.85 if j else 1,'fade':True})
    event_recipes[event]={'loop':event in ['fireBurn','spawnWarning','repair','baseCritical','amphiWake'],'parts':parts}
assert len(event_recipes)==32

# Verification and registered output manifest.
for id,s in sprites.items():
    im=Image.open(ROOT/s['path']);a=np.array(im)
    assert im.mode=='RGBA',id
    assert not ((a[:,:,0]>220)&(a[:,:,2]>220)&(a[:,:,1]<40)&(a[:,:,3]>0)).any(),id+' magenta leak'
    assert not a[0,:,3].any() and not a[-1,:,3].any() and not a[:,0,3].any() and not a[:,-1,3].any() or s['role'] in ['ground','wall','wall overlay','water','ice','foliage'],id+' clipping'
for rig in rigs.values():
    for ids in rig['treads']:
        arrs=[np.array(Image.open(ROOT/sprites[id]['path']).getchannel('A')) for id in ids]
        assert all(np.array_equal(arrs[0],a) for a in arrs[1:])
manifest={'formatVersion':1,'scope':'pixel asset presentation prototype; not final campaign or device acceptance','logicalCellPixels':16,'tankCanvasPixels':64,'sprites':sprites,'rigs':rigs,'turrets':turrets,'baseStates':baseids,'equipment':equipmentIds,'projectiles':projectiles,'effects':fxIds,'eventRecipes':event_recipes,'pickups':catalog,'canonicalTopologyMasks':MASKS,'sources':sources,'sourceCropBoxes':extracts}
(ROOT/'Metadata/pixel_assets.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
report={'passed':True,'textureCount':len(sprites),'atlasCount':len(list(ATLAS.glob('*.atlas'))),'allRGBA':True,'magentaLeak':False,'treadAlphaInvariant':True,'directionalHulls':20,'directionalTurrets':28,'tankCombinations':30,'baseStates':4,'pickupIDs':25,'topologyMasks':47,'effectRecipes':len(event_recipes),'runtimeDeviceAccepted':False}
(ROOT/'Metadata/asset_checks.json').write_text(json.dumps(report,indent=2)+'\n')

# Review contact sheets are not game art or final phone acceptance.
font=ImageFont.load_default()
def preview(name,ids,columns,cell=(180,150)):
    out=Image.new('RGB',(columns*cell[0],math.ceil(len(ids)/columns)*cell[1]),'#cbbb9c');d=ImageDraw.Draw(out)
    for i,id in enumerate(ids):
        im=Image.open(ROOT/sprites[id]['path']).convert('RGBA');ratio=min((cell[0]-12)/im.width,(cell[1]-28)/im.height);im=im.resize((int(im.width*ratio),int(im.height*ratio)),N)
        x=(i%columns)*cell[0];y=(i//columns)*cell[1]
        out.paste(im,(x+(cell[0]-im.width)//2,y+3),im);d.text((x+5,y+cell[1]-20),id.replace('px_',''),fill='#202525',font=font)
    out.save(ROOT/'Previews'/name)
preview('pixel_asset_catalog.png',list(sprites)[:220],8)
preview('pixel_pickups.png',[x['texture'] for x in catalog],5)
preview('pixel_terrain.png',[id for id,s in sprites.items() if s['role'] in ['prop','base']] + [f'px_brick_remaining_{v:02}' for v in [15,7,3,1]] + ['px_water_000_0','px_water_255_0','px_ice_000_0','px_foliage_000_0'],6)
print(json.dumps(report))
