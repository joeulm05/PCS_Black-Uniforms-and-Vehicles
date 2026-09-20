# Black Uniforms and Police Cars | Author: Joe "Gambit" Bradford
import hashlib
import json
import zipfile
from pathlib import Path

import numpy as np
from scipy.ndimage import binary_dilation

from build_mod import BASE, INPUT
from build_chief import clothing_mask
from decode_vt import decode, metadata


def main():
    results=[]
    with zipfile.ZipFile(INPUT/'Chief Player Dump.zip') as z:
        mesh=z.read(next(n for n in z.namelist() if n.endswith('/PlayerPoliceCR.uasset')))
        mask=clothing_mask(mesh)
        for name in z.namelist():
            if not name.endswith(('Shirt_Diffuse.uasset','__meshes_Merge_0_Diffuse.uasset')): continue
            original=z.read(name)
            bulk=z.read(name[:-7]+'.ubulk')
            target=BASE/'chief_assets'/name.split('Chief Player Dump/',1)[1]
            asset=target.read_bytes()
            newbulk=target.with_suffix('.ubulk').read_bytes()
            m=metadata(original)
            assert len(asset)==len(original) and len(bulk)==len(newbulk)
            allowed=set(range(m['fallback_offset'],m['fallback_offset']+16))
            at=0
            for c in m['chunks']:
                p=original.index(bytes.fromhex(c['hash']))
                allowed.update(range(p,p+20))
                assert asset[p:p+20]==hashlib.sha1(newbulk[at:at+c['size']]).digest()
                at+=c['size']
            assert all(a==b or i in allowed for i,(a,b) in enumerate(zip(original,asset)))
            a=np.asarray(decode(original,bulk)[0]).astype(float)
            b=np.asarray(decode(asset,newbulk)[0]).astype(float)
            r,g,blue=a[:,:,0],a[:,:,1],a[:,:,2]
            navy=(r<70)&(g<80)&(blue>12)&(blue<120)&(blue>r*1.3)&(blue>g*1.2)
            fullbody=name.endswith('__meshes_Merge_0_Diffuse.uasset')
            shirt=navy&(mask==1) if fullbody else navy
            pants=navy&(mask==2) if fullbody else np.zeros(navy.shape,dtype=bool)
            selected=shirt|pants
            changed=np.any(a!=b,axis=2)
            assert shirt.sum()>100000
            mean=b[shirt].mean(0)
            assert mean.min()>200 and mean.max()-mean.min()<6
            assert not np.any(changed&~binary_dilation(selected,iterations=6))
            gold=(r>140)&(g>80)&(blue<r*.7)
            assert not np.any(changed&gold)
            record=dict(asset=Path(name).name,white_shirt_pixels=int(shirt.sum()),mean_shirt_rgb=mean.round(2).tolist(),gold_pixels_changed=0,changes_confined_to_clothing_blocks=True,metadata_preserved_except_hashes_and_fallback=True,bulk_hashes_verified=True)
            if fullbody:
                assert pants.sum()>300000
                pmean=b[pants].mean(0)
                assert pmean.max()<35 and pmean.max()-pmean.min()<6
                record.update(black_pants_pixels=int(pants.sum()),mean_pants_rgb=pmean.round(2).tolist())
            for level in range(m['mips']):
                image,_=decode(asset,newbulk,level)
                assert image.width>0 and image.height>0
            record['mips_verified']=m['mips']
            results.append(record)
    assert len(results)==2
    report=dict(version='1.1.0',status='offline_checks_passed',in_game='Chief clothing not run in game here',checks=results)
    (BASE/'chief_validation.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2))


if __name__=='__main__':
    main()
