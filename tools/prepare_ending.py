"""Export the pinned KR1 end comics, without running the game."""
import csv, hashlib, json, math, os, subprocess
from pathlib import Path
from PIL import Image
from dove_source import verify, provenance
from prepare_level01 import write

ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path('D:/projects/KingdomRushDove')

def prepare():
    verify(SOURCE)
    tmp=ROOT/'output/ending-evaluated.json'
    subprocess.run(['D:/王国保卫战Dove版/love.exe',str(ROOT/'tools/ending_export')],env=dict(os.environ,DOVE_SOURCE_DIR=str(SOURCE),DOVE_EXPORT_PATH=str(tmp)),check=True,timeout=30)
    evaluated=json.loads(tmp.read_text(encoding='utf-8'))
    wanted=set();comics=[];inputs=['kr1/screen_kr1_end.lua','all/screen_comics.lua','_assets/kr1-desktop/strings/zh-Hans.lua']
    for name in ('01','02'):
        relative=f'kr1-desktop/data/comics/{name}.csv';inputs.append(relative)
        pages=[];sprites={};order=[];labels=[];global_order=[]
        for row in csv.reader((SOURCE/relative).read_text(encoding='utf-8-sig').splitlines()):
            if not row:continue
            if row[0]=='PAGE_END':
                pages.append(dict(end_frame=int(row[1]),sprites=sprites,order=order,labels=labels));sprites={};order=[];labels=[]
            elif row[0]=='ORDER':global_order=row[1:]
            elif row[0]=='TEXT':
                key=row[1]+'_KR1'
                item=dict(key=key,sprite=row[2],pos=list(map(float,row[3:5])),size=list(map(float,row[5:7])),rotation=-float(row[7])*math.pi/180,color=list(map(int,row[8:11])),fit_lines=int(float(row[11])),text=evaluated['strings'][key])
                if not any(x['key']==key and x['sprite']==item['sprite'] for x in labels):labels.append(item)
            else:
                sid=row[0];image=row[2].removesuffix('.png');wanted.add(image)
                item=sprites.setdefault(sid,dict(image=image,anchor=[float(row[9]),1-float(row[10])],keys=[]))
                item['keys'].append([int(row[1]),*map(float,row[3:9])])
        assert pages and not sprites,relative
        for page in pages:
            page['order']=[sid for sid in global_order if sid in page['sprites']]
            assert set(page['sprites']) <= set(page['order']), 'Missing comic sprite layer'
            assert all(s in page['sprites'] or s.startswith('frame_') for s in page['order'])
        comics.append(pages)
    assets=ROOT/'assets/kingdom_rush'
    groups={name:json.loads((assets/f'data/atlases/{name}.json').read_text(encoding='utf-8')) for name in ['comic_end','ballon']}
    out=ROOT/'data/kr1_end';out.mkdir(parents=True,exist_ok=True)
    frames={};aliases={};hashes={};pages=[];page=Image.new('RGBA',(2048,2048));x=y=row_h=0
    for name in sorted(wanted):
        group=next((g for g,a in groups.items() if name in a.get('lookup',{})),None)
        assert group,('Missing ending frame',name)
        a=groups[group];key=a['lookup'][name];f=a['frames'][key]
        path=ROOT/a['texture_directory'].removeprefix('res://')/f['sheet'];hashes[path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
        sx,sy,w,h=f['region'];left,top=math.floor(sx),math.floor(sy);width,height=math.ceil(sx+w)-left,math.ceil(sy+h)-top
        assert width<=2044 and height<=2044
        if x+width+4>2048:x=0;y+=row_h;row_h=0
        if y+height+4>2048:pages.append(page);page=Image.new('RGBA',(2048,2048));x=y=row_h=0
        with Image.open(path) as original:page.paste(original.crop((left,top,left+width,top+height)),(x+2,y+2))
        frames[name]=dict(f,sheet=f'atlas_{len(pages)}.png',region=[x+2+sx-left,y+2+sy-top,w,h],source_group=group,source_frame=key)
        aliases[name]=name;x+=width+4;row_h=max(row_h,height+4)
    pages.append(page)
    for i,page in enumerate(pages):page.save(out/f'atlas_{i}.png',compress_level=6);page.close()
    all_sounds=json.loads((assets/'data/sounds.json').read_text(encoding='utf-8'))
    sounds={k:all_sounds[k] for k in ['MusicEndCredits','MusicSuspense','GUINotificationPaperOver']}
    source=provenance(SOURCE,inputs)
    write(out/'definition.json',dict(schema_version=1,source=source,comics=comics,adaptations=['credits omitted at user request']))
    write(out/'atlas.json',dict(schema_version=1,group='kr1_end',texture_directory='res://data/kr1_end/',frames=frames,lookup=aliases,aliases={}))
    write(out/'sounds.json',sounds)
    write(out/'catalog.json',dict(schema_version=1,groups={'kr1_end':{'path':'res://data/kr1_end/atlas.json'}},static={'sounds':'res://data/kr1_end/sounds.json'},audio_directory='res://assets/kingdom_rush/kr1-desktop/sounds/files/'))
    media=[f'res://data/kr1_end/atlas_{i}.png' for i in range(len(pages))]+sorted({'res://assets/kingdom_rush/kr1-desktop/sounds/files/'+f for s in sounds.values() for f in s['files']})
    assert all((ROOT/p.removeprefix('res://')).is_file() for p in media)
    write(out/'manifest.json',dict(schema_version=1,source=source,resources=media+['res://scripts/ui/kr1_ending.gd'],data=[f'res://data/kr1_end/{f}.json' for f in ['definition','atlas','catalog','sounds']],frames=len(frames),source_texture_hashes=hashes))
    print(dict(comic_pages=[len(p) for p in comics],frames=len(frames),atlas_pages=len(pages)))

if __name__=='__main__':prepare()
