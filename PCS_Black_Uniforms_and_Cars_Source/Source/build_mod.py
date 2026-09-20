# Black Uniforms and Police Cars | Author: Joe "Gambit" Bradford
import bisect
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import zipfile
from pathlib import Path

import numpy as np
from cityhash import CityHash64

from decode_vt import decode, metadata, unmorton

BASE = Path(__file__).resolve().parent
ROOT = BASE.parent
INPUT = Path(os.environ.get('PCS_ASSET_INPUT', ROOT/'upload'))
RETOC = os.environ.get('RETOC') or shutil.which('retoc') or '/tmp/cosmetic-tools/retoc'
REPAK = os.environ.get('REPAK') or shutil.which('repak') or '/tmp/cosmetic-tools/repak'
CAR_INK = [(425,717,741,781),(600,700,742,725),(360,714,416,780),(386,1058,699,1118),(384,1042,522,1064),(706,1051,766,1118)]


def hash_name(name):
    return CityHash64(name.lower().encode('utf-16-le'))


def chunk_id(identifier, kind):
    return struct.pack('<QHBB', identifier, 0, 0, kind).hex()


def write_job(path, m, mode, rects):
    b = struct.pack('<5I', 0x31504342, mode, m['width'], m['height'], len(rects))
    for rect in rects:
        b += struct.pack('<4f', *rect)
    b += struct.pack('<I', m['mips'])
    for mip, o in enumerate(m['offsets']):
        items = []
        start = sum(c['size'] for c in m['chunks'][:m['chunk_ids'][mip]])
        for address in range(o['a']):
            x, y = unmorton(address), unmorton(address >> 1)
            if x >= o['w'] or y >= o['h']:
                continue
            i = bisect.bisect_right(o['addresses'], address) - 1
            off = o['offsets'][i]
            assert off != 0xFFFFFFFF
            at = start + m['bases'][mip] + (off + address - o['addresses'][i]) * m['strides'][0]
            items.append(struct.pack('<IIQ', x, y, at))
        b += struct.pack('<III', max(m['width'] >> mip, 1), max(m['height'] >> mip, 1), len(items))
        b += b''.join(items)
    path.write_bytes(b)


def container_header(name, identifiers):
    ids = sorted(identifiers)
    b = struct.pack('<IIQI', 0x496f436e, 5, hash_name(name), len(ids))
    b += b''.join(struct.pack('<Q', i) for i in ids)
    b += struct.pack('<I', len(ids)*16) + bytes(len(ids)*16)
    b += struct.pack('<5I', 0, 0, 0, 0, 0)
    b += struct.pack('<qqI', len(b)+16, 4, 0)
    return b


def build():
    source = BASE / 'asset_input'
    source.mkdir(exist_ok=True)
    output = BASE / 'replacement_assets'
    output.mkdir(exist_ok=True)
    groups = {'Uniforms': [], 'PoliceCar': []}
    report = []
    for archive in ['Workers.zip', 'PoliceCar.zip']:
        with zipfile.ZipFile(INPUT / archive) as z:
            names = [n for n in z.namelist() if n.endswith('__meshes_Merge_0_Diffuse.uasset')] if archive == 'Workers.zip' else [n for n in z.namelist() if n.endswith(('T_Police01_Body_BC.uasset', 'T_PoliceCar_Body_Damage_BC.uasset'))]
            for name in names:
                key = name.split('/')[1] if archive == 'Workers.zip' else Path(name).stem
                mode = int(archive == 'PoliceCar.zip')
                rects = [] if mode == 0 else [tuple(v/1200 for v in r) for r in CAR_INK]
                asset = z.read(name)
                bulk = z.read(name[:-7]+'.ubulk')
                package = re.findall(rb'/Game/[A-Za-z0-9_./]+', asset)
                assert len(package) == 1
                package = package[0].decode()
                m = metadata(asset)
                old = source / (key+'.ubulk')
                old.write_bytes(bulk)
                job = source / (key+'.bin')
                write_job(job, m, mode, rects)
                rel = 'PoliceChiefSimulator/Content/'+package.removeprefix('/Game/')
                dest = output / (rel+'.ubulk')
                dest.parent.mkdir(parents=True, exist_ok=True)
                result = subprocess.run([str(BASE/'recolor_assets'),str(job),str(old),str(dest)],check=True,capture_output=True,text=True)
                patched = dest.read_bytes()
                at = 0
                for c in m['chunks']:
                    original_hash = hashlib.sha1(bulk[at:at+c['size']]).digest()
                    assert original_hash.hex() == c['hash']
                    new_hash = hashlib.sha1(patched[at:at+c['size']]).digest()
                    assert asset.count(original_hash) == 1
                    asset = asset.replace(original_hash,new_hash)
                    at += c['size']
                assert at == len(patched) == len(bulk)
                image, _ = decode(asset, patched)
                rgb = np.asarray(image, dtype=np.float32)/255.0
                linear = np.where(rgb <= 0.04045, rgb/12.92, ((rgb+0.055)/1.055)**2.4)
                fallback = [float(x) for x in linear.mean(axis=(0,1), dtype=np.float64)] + [1.0]
                asset = bytearray(asset)
                struct.pack_into('<4f', asset, m['fallback_offset'], *fallback)
                asset = bytes(asset)
                (output / (rel+'.uasset')).write_bytes(asset)
                imported_names = struct.unpack_from('<I', asset, 48)[0]
                assert struct.unpack_from('<I', asset, imported_names)[0] == 0
                groups['PoliceCar' if mode else 'Uniforms'].append((package,rel))
                report.append(dict(key=key,package=package,mode='car_body' if mode else 'shirt_and_pants_components',source_asset_sha256=hashlib.sha256(z.read(name)).hexdigest(),source_bulk_sha256=hashlib.sha256(bulk).hexdigest(),fallback=fallback,**json.loads(result.stdout)))
                print(key,result.stdout.strip(),flush=True)
    for group,items in groups.items():
        name='zz_PCS_Black_'+group+'_P'
        raw=BASE/'raw'/group
        chunks=raw/'chunks'
        chunks.mkdir(parents=True,exist_ok=True)
        paths={}
        ids=[]
        for package,rel in items:
            ident=hash_name(package);ids.append(ident)
            for kind,ext in [(1,'.uasset'),(2,'.ubulk')]:
                key=chunk_id(ident,kind)
                (chunks/key).write_bytes((output/(rel+ext)).read_bytes())
                paths[key]='../../../'+rel+ext
        (chunks/chunk_id(hash_name(name),6)).write_bytes(container_header(name,ids))
        (raw/'manifest.json').write_text(json.dumps(dict(chunk_paths=paths,version='RemovedOnDemandMetaData',mount_point='../../../'),indent=2))
        dest=BASE/'package'/'~mods'/(name+'.utoc')
        dest.parent.mkdir(parents=True,exist_ok=True)
        subprocess.run([RETOC,'pack-raw',str(raw),str(dest)],check=True)
        subprocess.run([RETOC,'verify',str(dest)],check=True)
        subprocess.run([RETOC,'info',str(dest)],check=True)
        empty = BASE/'empty_pak'
        empty.mkdir(exist_ok=True)
        subprocess.run([REPAK,'pack','--version','V11',str(empty),str(dest.with_suffix('.pak'))],check=True)
    (BASE/'build_report.json').write_text(json.dumps(report,indent=2))


if __name__ == '__main__':
    build()
