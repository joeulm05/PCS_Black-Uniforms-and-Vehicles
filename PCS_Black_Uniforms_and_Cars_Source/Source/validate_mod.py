# Black Uniforms and Police Cars | Author: Joe "Gambit" Bradford
import hashlib
import json
import struct
import subprocess
import zipfile
from pathlib import Path

import numpy as np
from scipy.ndimage import label, binary_erosion, binary_dilation

from build_mod import INPUT, RETOC, REPAK
from decode_vt import decode, metadata


def main():
    base=Path(__file__).resolve().parent
    results=[]
    for archive in ['Workers.zip','PoliceCar.zip']:
        with zipfile.ZipFile(INPUT/archive) as z:
            for name in z.namelist():
                if not name.endswith(('__meshes_Merge_0_Diffuse.uasset','T_Police01_Body_BC.uasset','T_PoliceCar_Body_Damage_BC.uasset')):
                    continue
                old=z.read(name)
                paths=list((base/'replacement_assets').rglob(Path(name).name))
                target=next(p for p in paths if str(p).endswith(name))
                new=target.read_bytes()
                m=metadata(old)
                new_bulk=target.with_suffix('.ubulk').read_bytes()
                old_bulk=z.read(name[:-7]+'.ubulk')
                assert len(new)==len(old)
                assert len(new_bulk)==len(old_bulk)
                allowed=set(range(m['fallback_offset'],m['fallback_offset']+16))
                off=0
                for c in m['chunks']:
                    start=old.index(bytes.fromhex(c['hash']))
                    allowed.update(range(start,start+20))
                    assert new[start:start+20]==hashlib.sha1(new_bulk[off:off+c['size']]).digest()
                    off+=c['size']
                assert all(a==b or i in allowed for i,(a,b) in enumerate(zip(old,new)))
                a=np.asarray(decode(old,old_bulk)[0]).astype(np.int16)
                b=np.asarray(decode(new,new_bulk)[0]).astype(np.int16)
                changed=np.any(a!=b,axis=2)
                result=dict(asset=name,asset_bytes_preserved_except_hashes_and_fallback=True,bulk_chunk_hashes_verified=True)
                if archive=='Workers.zip':
                    r,g,blue=a[:,:,0],a[:,:,1],a[:,:,2]
                    mask=(r>45)&(g>65)&(blue>85)&(g>r*1.07)&(blue>r*1.2)
                    labs,n=label(mask)
                    counts=np.bincount(labs.ravel())
                    ids=np.flatnonzero((counts>1000)&(counts<20000))
                    ids=ids[ids!=0]
                    badge_blue=np.isin(labs,ids)
                    result['small_blue_detail_components']=len(ids)
                    result['small_blue_detail_pixels_changed']=int((changed&badge_blue).sum())
                    gold=(r>140)&(g>80)&(blue<r*.7)
                    result['gold_pixels_changed']=int((changed&gold).sum())
                    cloth=np.isin(labs,np.flatnonzero((counts>20000)&(np.arange(len(counts))!=0)))
                    result['cloth_pixels']=int(cloth.sum())
                    result['mean_shirt_rgb_before']=a[cloth].mean(axis=0).round(2).tolist()
                    result['mean_shirt_rgb_after']=b[cloth].mean(axis=0).round(2).tolist()
                    assert result['small_blue_detail_pixels_changed']==0
                    assert result['gold_pixels_changed']==0
                    assert max(result['mean_shirt_rgb_after'])<35
                    navy=(r<70)&(g<80)&(blue>12)&(blue<120)&(blue>r*1.3)&(blue>g*1.2)
                    labels,count=label(navy)
                    pants=np.zeros(navy.shape,dtype=bool)
                    protected=np.zeros(navy.shape,dtype=bool)
                    for idx in np.flatnonzero(np.bincount(labels.ravel())>20000):
                        if idx==0: continue
                        yy,xx=np.where(labels==idx)
                        if len(xx)>20000:
                            if xx.mean()>a.shape[1]*.5 and yy.max()>a.shape[0]*.8:
                                pants[yy,xx]=True
                            else:
                                protected[yy,xx]=True
                    assert pants.sum()>300000
                    result['pants_pixels']=int(pants.sum())
                    result['mean_pants_rgb_before']=a[pants].mean(axis=0).round(2).tolist()
                    result['mean_pants_rgb_after']=b[pants].mean(axis=0).round(2).tolist()
                    assert max(result['mean_pants_rgb_after'])<35
                    assert max(result['mean_pants_rgb_after'])-min(result['mean_pants_rgb_after'])<5
                    result['protected_navy_interior_pixels_changed']=int((changed&protected&~binary_dilation(cloth,iterations=6)).sum())
                    assert result['protected_navy_interior_pixels_changed']==0, (name, result)

                for level in [3,5,7,9,m['mips']-1]:
                    preview,meta=decode(new,new_bulk,level)
                    assert preview.width>0 and preview.height>0
                results.append(result)
    for toc in sorted((base/'package'/'~mods').glob('*.utoc')):
        (base/'inspection').mkdir(exist_ok=True)
        subprocess.run([RETOC,'verify',str(toc)],check=True)
        subprocess.run([RETOC,'manifest',str(toc)],cwd=base/'inspection',check=True)
        j=json.loads((base/'inspection'/'pakstore.json').read_text())
        expected=12 if 'Uniforms' in toc.name else 2
        assert len(j['oplog']['entries'])==expected
        subprocess.run([REPAK,'info',str(toc.with_suffix('.pak'))],check=True)
    report=dict(status='offline_checks_passed',in_game_test='shirts and cars confirmed by author; added pants verified offline',textures=len(results),checks=results)
    (base/'validation.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))


if __name__=='__main__':
    main()
