# Black Uniforms and Police Cars | Author: Joe "Gambit" Bradford
import bisect
import io
import json
import struct
import sys
import zipfile
from pathlib import Path

from PIL import Image


class Reader:
    def __init__(self, data, pos=0):
        self.data = data
        self.pos = pos

    def read(self, count):
        result = self.data[self.pos:self.pos + count]
        assert len(result) == count
        self.pos += count
        return result

    def u32(self):
        return struct.unpack('<I', self.read(4))[0]

    def array(self):
        n = self.u32()
        assert n < 100000
        return [self.u32() for _ in range(n)]


def metadata(data):
    marker = struct.pack('<7I', 1, 1, 1, 1, 128, 4, 1)
    start = data.find(marker)
    assert start >= 0
    r = Reader(data, start)
    cooked, layers, xb, yb, tile, border = [r.u32() for _ in range(6)]
    strides = r.array()
    mips, width, height = [r.u32() for _ in range(3)]
    chunk_ids, bases = r.array(), r.array()
    offsets = []
    for _ in range(r.u32()):
        w, h, a = [r.u32() for _ in range(3)]
        offsets.append(dict(w=w, h=h, a=a, addresses=r.array(), offsets=r.array()))
    assert r.array() == []
    assert r.array() == []
    assert r.array() == []
    fmt = r.read(r.u32()).decode().rstrip('\0')
    fallback_offset = r.pos
    fallback = struct.unpack('<4f', r.read(16))
    chunks = []
    for _ in range(r.u32()):
        digest = r.read(20).hex()
        size, payload = r.u32(), r.u32()
        codec = r.read(1)[0]
        payload_offset = r.u32()
        index = r.u32()
        chunks.append(dict(hash=digest, size=size, payload=payload, codec=codec, payload_offset=payload_offset, index=index))
    assert len(chunk_ids) == len(bases) == len(offsets) == mips
    assert fmt == 'PF_DXT1', fmt
    assert all(c['codec'] == 4 for c in chunks)
    return dict(start=start, end=r.pos, mips=mips, width=width, height=height, tile=tile, border=border, strides=strides, chunk_ids=chunk_ids, bases=bases, offsets=offsets, chunks=chunks, fallback=fallback, fallback_offset=fallback_offset)


def decode_bc1(data, size):
    head = struct.pack('<7I', 124, 0x81007, size, size, len(data), 0, 0)
    head += bytes(44)
    head += struct.pack('<II4sIIIII', 32, 4, b'DXT1', 0, 0, 0, 0, 0)
    head += struct.pack('<5I', 0x1000, 0, 0, 0, 0)
    assert len(head) == 124
    return Image.open(io.BytesIO(b'DDS ' + head + data)).convert('RGB')


def unmorton(value):
    result = 0
    for i in range(16):
        result |= ((value >> (2 * i)) & 1) << i
    return result


def decode(asset, bulk, mip=0):
    m = metadata(asset)
    assert sum(c['size'] for c in m['chunks']) == len(bulk)
    chunk_start = sum(c['size'] for c in m['chunks'][:m['chunk_ids'][mip]])
    o = m['offsets'][mip]
    tile, border, stride = m['tile'], m['border'], m['strides'][0]
    result = Image.new('RGB', (o['w'] * tile, o['h'] * tile))
    count = 0
    for address in range(o['a']):
        x, y = unmorton(address), unmorton(address >> 1)
        if x >= o['w'] or y >= o['h']:
            continue
        i = bisect.bisect_right(o['addresses'], address) - 1
        offset = o['offsets'][i]
        assert offset != 0xFFFFFFFF
        at = chunk_start + m['bases'][mip] + (offset + address - o['addresses'][i]) * stride
        piece = decode_bc1(bulk[at:at + stride], tile + 2 * border)
        piece = piece.crop((border, border, border + tile, border + tile))
        result.paste(piece, (x * tile, y * tile))
        count += 1
    assert count == o['w'] * o['h']
    return result, m


if __name__ == '__main__':
    folder = Path(__file__).parent / 'originals'
    folder.mkdir(exist_ok=True)
    selections = {
        'Workers.zip': lambda n: n.endswith('_Diffuse.uasset') and 'Worker_02_M/' in n,
        'PoliceCar.zip': lambda n: n.endswith('T_Police01_Body_BC.uasset') or n.endswith('T_PoliceCar_Body_Damage_BC.uasset'),
    }
    for archive, select in selections.items():
        with zipfile.ZipFile(Path('upload') / archive) as z:
            for name in z.namelist():
                if select(name):
                    im, m = decode(z.read(name), z.read(name[:-7] + '.ubulk'))
                    stem = Path(name).stem
                    im.save(folder / (stem + '.png'))
                    (folder / (stem + '.json')).write_text(json.dumps(m, indent=2))
                    print(stem, im.size, len(m['chunks']))
