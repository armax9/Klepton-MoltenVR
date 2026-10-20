"""Apply the Ryujinx image/view lifetime workaround to the exact bundled ARM64 MoltenVK.
Original dylib remains untouched; all instruction edits are fingerprint guarded.
Reference: https://github.com/V380-Ori/Ryujinx.MoltenVK/blob/main/0005-Do-not-retain-VkImage.patch
"""
from pathlib import Path
import struct,hashlib,json
import argparse
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('source',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args()
src=args.source
out=args.output
source_bytes=src.read_bytes()
expected_sha256='aef00b13bcc808adf15b85bef9ae67393d92be7ed5dfe41cad16fa809e4a4c5f'
if hashlib.sha256(source_bytes).hexdigest()!=expected_sha256:
 raise RuntimeError('Unsupported MoltenVK binary: image-view lifetime patch requires the bundled 1.4.2 build')
b=bytearray(source_bytes);assert b[:4]==bytes.fromhex('cafebabe')
base=None
for i in range(struct.unpack_from('>I',b,4)[0]):
 cpu,sub,off,size,align=struct.unpack_from('>IIIII',b,8+20*i)
 if cpu==0x100000c:base=off
assert base is not None
# Constructor: omit the inlined _image->retain(). Destructor: skip precisely
# the matching _image->release() block, preserving plane destruction and cleanup.
patches=[(0x409c4,bytes.fromhex('080129b8'),bytes.fromhex('1f2003d5')),
         (0x40fa4,bytes.fromhex('601640f9'),struct.pack('<I',0x1400000a))]
for addr,old,new in patches:
 actual=bytes(b[base+addr:base+addr+4])
 assert actual==old,(hex(addr),actual.hex(),old.hex())
 b[base+addr:base+addr+4]=new
out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(b)
(out.parent/'patch.json').write_text(json.dumps({'source':str(src),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'architecture':'arm64','reference':__doc__.split('Reference: ')[1].strip(),'changes':[{'virtual_address':hex(a),'before':o.hex(),'after':n.hex()} for a,o,n in patches]},indent=2))
print(out)
