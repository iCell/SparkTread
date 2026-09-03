"""Summarize actual current captures, make a GIF from them, package clean exports.

Requires Pillow. Does not generate game artwork or modify any exported texture.
"""
from pathlib import Path
from PIL import Image
import collections,hashlib,json,zipfile

root=Path(__file__).resolve().parents[1]
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
manifest_path=root/'Metadata/pixel_assets.json'
manifest=json.loads(manifest_path.read_text());manifest_sha=digest(manifest_path)
runtime=json.loads((root/'Metadata/pixel_runtime_checks.json').read_text())
assert runtime['passed'] and runtime['assetManifestSHA256']==manifest_sha
render_reports=[]
for p in sorted((root/'Metadata').glob('pixel_*.json')):
    report=json.loads(p.read_text())
    if report.get('renderer')!='SpriteKit SKView.texture':continue
    assert report['passed'] and report['assetManifestSHA256']==manifest_sha,p.name
    png=root/'Previews'/(p.stem+'.png')
    assert digest(png)==report['imageSHA256'],p.name
    render_reports.append(report)
assert len(render_reports)>=52,len(render_reports)
frames=[Image.open(root/f'Previews/pixel_battle_phone_{i}.png').convert('RGB') for i in range(24)]
sample=Image.new('RGB',(422*6,195*4))
for i,frame in enumerate(frames):sample.paste(frame.resize((422,195),Image.Resampling.NEAREST),((i%6)*422,(i//6)*195))
palette=sample.quantize(colors=256)
gif_frames=[f.quantize(palette=palette,dither=Image.Dither.NONE) for f in frames]
gif_frames[0].save(root/'Previews/pixel_battle.gif',save_all=True,append_images=gif_frames[1:],duration=[80,80,90]*8,loop=0,optimize=False,disposal=2)
film=Image.new('RGB',(844*2,390*2))
for i,index in enumerate([0,6,12,18]):film.paste(frames[index].resize((844,390),Image.Resampling.NEAREST),((i%2)*844,(i//2)*390))
film.save(root/'Previews/pixel_animation_filmstrip.png')
counts=dict(sorted(collections.Counter(s['atlas'] for s in manifest['sprites'].values()).items()))
readability={}
for device in ['compact','phone','tablet']:
    r=next(r for r in render_reports if r['mode']=='arena' and r['deviceFixture']==device and r['phase']==1)
    rects=[o['rect'] for o in r['objects'] if o['kind'] in ['player','enemy']]
    minimum=[min(v[2] for v in rects),min(v[3] for v in rects)]
    readability[device]={'sizePoints':r['sizePoints'],'minVisibleTankWHPoints':minimum,'old28x28GatePassed':min(minimum)>=28,'physicalDeviceTested':False}
summary={'scope':'core art prototype, not final game or physical-device acceptance','assetManifestSHA256':manifest_sha,'textureCount':len(manifest['sprites']),'atlasCount':len(counts),'atlasCounts':counts,'decodedRGBABytes':sum(s['pixelSize'][0]*s['pixelSize'][1]*4 for s in manifest['sprites'].values()),'resourceAndStateChecks':runtime['checkCount'],'resourceAndStateChecksPassed':runtime['passed'],'sceneCaptures':len(render_reports),'sceneChecks':sum(len(r['checks']) for r in render_reports),'sceneChecksPassed':all(r['passed'] for r in render_reports),'galleryCaptures':len(runtime['captures']),'gifFrames':24,'gifDurationMilliseconds':2000,'gifSHA256':digest(root/'Previews/pixel_battle.gif'),'readability':readability,'notAccepted':['small-phone readability','iOS compiled atlases','UIKit build','physical-device input/performance','complete gameplay interactions','campaign thumbnails','full menu/HUD/tutorial behavior'],'generativeMethod':'built-in imagegen plus user-authorized deterministic local finishing','runtimeUsesGeneratedSourceSheets':False}
(root/'Metadata/delivery_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
archive=root.parent/'SparkTreadPixelAssets.zip'
allowed_roots={'Atlases','Runtime','Metadata','Docs','Previews','Tools'}
allowed_files={'README.md','GENERATION_BATCH_02.md'}
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(root.rglob('*')):
        if not p.is_file():continue
        rel=p.relative_to(root)
        if '__pycache__' in rel.parts or p.name=='.DS_Store':continue
        if rel.parts[0] in allowed_roots or str(rel) in allowed_files:z.write(p,Path('PixelProduction')/rel)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    names=z.namelist()
    assert sum('/Atlases/' in n and n.endswith('.png') for n in names)==len(manifest['sprites'])
    assert not any('/Current/' in n for n in names)
print(json.dumps({'textures':len(manifest['sprites']),'resourceAndStateChecks':runtime['checkCount'],'sceneCaptures':len(render_reports),'sceneChecks':summary['sceneChecks'],'galleryCaptures':len(runtime['captures']),'archive':str(archive),'archiveBytes':archive.stat().st_size,'archiveSHA256':digest(archive)},ensure_ascii=False))
