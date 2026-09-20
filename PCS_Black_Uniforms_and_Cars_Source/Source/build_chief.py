# Black Uniforms and Police Cars | Author: Joe "Gambit" Bradford
import hashlib
import json
import struct
import subprocess
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

from build_mod import BASE, INPUT, RETOC, REPAK, write_job, hash_name, chunk_id, container_header
from decode_vt import decode, metadata


def clothing_mask(mesh):
    assert hashlib.sha256(mesh).hexdigest()=='c4318301990114b0d0196eb44d7b21073762a6fa8ef421c4f2b0f8192ef1f675', 'Chief mesh differs from the reviewed UV layout.'
    count=42694
    assert struct.unpack_from('<II',mesh,314988)==(12,count)
    assert struct.unpack_from('<II',mesh,54896)==(2,130038)
    assert struct.unpack_from('<II',mesh,1168902)==(4,count)
    vertices=np.frombuffer(mesh,dtype='<f4',count=count*3,offset=314996).reshape(-1,3)
    uv=np.frombuffer(mesh,dtype='<f2',count=count*2,offset=1168910).reshape(-1,2).astype(float)
    triangles=np.frombuffer(mesh,dtype='<u2',count=130038,offset=54904).reshape(-1,3)
    _,inverse=np.unique(np.round(vertices,3),axis=0,return_inverse=True)
    t=inverse[triangles]
    a=np.concatenate([t[:,0],t[:,1],t[:,2]])
    b=np.concatenate([t[:,1],t[:,2],t[:,0]])
    _,labels=connected_components(coo_matrix((np.ones(len(a)),(a,b)),shape=(inverse.max()+1,)*2),directed=False)
    component=labels[inverse]
    assert np.count_nonzero(component==1)==2431
    assert np.count_nonzero(component==10)==2111
    assert vertices[component==1,2].min()>108 and vertices[component==1,2].max()<166
    assert vertices[component==10,2].min()<8 and vertices[component==10,2].max()<117
    mask=Image.new('L',(2048,2048))
    draw=ImageDraw.Draw(mask)
    for triangle in triangles:
        c=component[triangle[0]]
        if (component[triangle]!=c).any(): continue
        if c not in (1,10) and triangle.min()<28636: continue
        if np.ptp(uv[triangle],axis=0).max()>.5: continue
        draw.polygon([tuple(p) for p in uv[triangle]*2048],fill={1:1,10:2}.get(c,3))
    pixels=np.array(mask)
    _,indices=distance_transform_edt(pixels==0,return_indices=True)
    return pixels[tuple(indices)]


def build():
    source=BASE/'chief_input'
    source.mkdir(exist_ok=True)
    output=BASE/'chief_assets'
    output.mkdir(exist_ok=True)
    items=[]
    report=[]
    with zipfile.ZipFile(INPUT/'Chief Player Dump.zip') as z:
        mesh=z.read(next(n for n in z.namelist() if n.endswith('/PlayerPoliceCR.uasset')))
        mask=clothing_mask(mesh)
        for name in z.namelist():
            if not name.endswith(('Shirt_Diffuse.uasset','__meshes_Merge_0_Diffuse.uasset')): continue
            original=z.read(name)
            bulk=z.read(name[:-7]+'.ubulk')
            m=metadata(original)
            mode=2 if name.endswith('/Shirt_Diffuse.uasset') else 3
            key=Path(name).stem
            job=source/(key+'.bin')
            write_job(job,m,mode,[])
            if mode==3:
                with job.open('ab') as f: f.write(mask.tobytes())
            old=source/(key+'.ubulk')
            old.write_bytes(bulk)
            rel=name.split('Chief Player Dump/',1)[1]
            dest=output/rel
            dest.parent.mkdir(parents=True,exist_ok=True)
            result=subprocess.run([str(BASE/'recolor_assets'),str(job),str(old),str(dest.with_suffix('.ubulk'))],check=True,capture_output=True,text=True)
            newbulk=dest.with_suffix('.ubulk').read_bytes()
            asset=original
            at=0
            for chunk in m['chunks']:
                oldhash=hashlib.sha1(bulk[at:at+chunk['size']]).digest()
                assert oldhash.hex()==chunk['hash'] and asset.count(oldhash)==1
                asset=asset.replace(oldhash,hashlib.sha1(newbulk[at:at+chunk['size']]).digest())
                at+=chunk['size']
            assert at==len(bulk)==len(newbulk)
            image,_=decode(asset,newbulk)
            rgb=np.asarray(image,dtype=np.float32)/255
            linear=np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)
            fallback=list(linear.mean(axis=(0,1),dtype=np.float64))+[1.0]
            asset=bytearray(asset)
            struct.pack_into('<4f',asset,m['fallback_offset'],*fallback)
            dest.write_bytes(asset)
            package='/Game/'+rel.split('/Content/',1)[1].removesuffix('.uasset')
            items.append((package,rel.removesuffix('.uasset')))
            preview=BASE/'inspection'/(key+'_white.png')
            preview.parent.mkdir(exist_ok=True)
            image.resize((1000,1000)).save(preview)
            report.append(dict(asset=rel,mode=mode,source_asset_sha256=hashlib.sha256(original).hexdigest(),source_bulk_sha256=hashlib.sha256(bulk).hexdigest(),mesh_sha256=hashlib.sha256(mesh).hexdigest(),**json.loads(result.stdout)))
    name='zz_PCS_Chief_Uniform_P'
    raw=BASE/'chief_raw'
    chunks=raw/'chunks'
    chunks.mkdir(parents=True,exist_ok=True)
    paths={}
    identifiers=[]
    for package,rel in items:
        ident=hash_name(package)
        identifiers.append(ident)
        for kind,ext in [(1,'.uasset'),(2,'.ubulk')]:
            key=chunk_id(ident,kind)
            (chunks/key).write_bytes((output/(rel+ext)).read_bytes())
            paths[key]='../../../'+rel+ext
    assert len(items)==2
    (chunks/chunk_id(hash_name(name),6)).write_bytes(container_header(name,identifiers))
    (raw/'manifest.json').write_text(json.dumps(dict(chunk_paths=paths,version='RemovedOnDemandMetaData',mount_point='../../../'),indent=2))
    dest=BASE/'package/~mods'/(name+'.utoc')
    dest.parent.mkdir(parents=True,exist_ok=True)
    subprocess.run([RETOC,'pack-raw',str(raw),str(dest)],check=True)
    subprocess.run([RETOC,'verify',str(dest)],check=True)
    empty=BASE/'empty_pak'
    empty.mkdir(exist_ok=True)
    subprocess.run([REPAK,'pack','--version','V11',str(empty),str(dest.with_suffix('.pak'))],check=True)
    (BASE/'chief_build_report.json').write_text(json.dumps(report,indent=2))


if __name__=='__main__':
    build()
