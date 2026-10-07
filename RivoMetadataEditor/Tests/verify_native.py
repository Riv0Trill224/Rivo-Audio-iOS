"""Independent TagLib/Mutagen verification. Uses only upstream tiny test fixtures."""
from pathlib import Path
import hashlib, json, struct, subprocess, sys
from mutagen import File
from mutagen.id3 import APIC,TXXX,POPM
from PIL import Image

root = Path(__file__).resolve().parents[1]
cli = Path(sys.argv[1])
scratch = Path(sys.argv[2]); scratch.mkdir(parents=True, exist_ok=True)
cover = scratch / 'cover.png'; Image.new('RGB',(32,32),(212,173,255)).save(cover)

def run(*args):
    return subprocess.run([str(cli),*map(str,args)],check=True,text=True,capture_output=True).stdout

def metadata(p):
    return dict(line.split('\t',1) for line in run('read',p).splitlines())

def digest_audio(p):
    d = p.read_bytes(); suffix = p.suffix
    if suffix == '.mp3':
        # ID3v2 length is syncsafe; ID3v1 / APE are absent from this fixture.
        start = 10 + sum(d[6+i] << (7*(3-i)) for i in range(4)) if d[:3] == b'ID3' else 0
        if d[-128:-125] == b'TAG': d=d[:-128]
        audio=d[start:]
    elif suffix == '.flac':
        offset=4
        while True:
            h=d[offset:offset+4]; offset += 4 + int.from_bytes(h[1:],'big')
            if h[0] & 128: break
        audio=d[offset:]
    elif suffix == '.m4a':
        offset=0; chunks=[]
        while offset+8 <= len(d):
            n=int.from_bytes(d[offset:offset+4],'big'); typ=d[offset+4:offset+8]; header=8
            if n==1:n=int.from_bytes(d[offset+8:offset+16],'big');header=16
            if n==0:n=len(d)-offset
            if typ==b'mdat':chunks.append(d[offset+header:offset+n])
            if n < header: raise ValueError('invalid mp4 atom')
            offset += n
        audio=b''.join(chunks)
    elif suffix in ('.wav','.aiff'):
        offset=12; chunks=[]; endian='little' if suffix=='.wav' else 'big'
        while offset+8<=len(d):
            typ=d[offset:offset+4]; n=int.from_bytes(d[offset+4:offset+8],endian)
            if typ in (b'data',b'SSND'):chunks.append(d[offset+8:offset+8+n])
            offset += 8 + n + n%2
        audio=b''.join(chunks)
    elif suffix == '.ogg':
        offset=0; packets=[]; partial=b''
        while offset < len(d):
            assert d[offset:offset+4]==b'OggS'
            n=d[offset+26]; laces=d[offset+27:offset+27+n]; pos=offset+27+n
            for length in laces:
                partial += d[pos:pos+length]; pos+=length
                if length<255:packets.append(partial);partial=b''
            offset=pos
        audio=b''.join(p for p in packets if not p.startswith((b'\x01vorbis',b'\x03vorbis',b'\x05vorbis')))
    else: raise ValueError(suffix)
    return hashlib.sha256(audio).hexdigest()

report=[]
for source in sorted((root/'Tests/Fixtures').glob('*')):
    p=scratch/source.name;p.write_bytes(source.read_bytes())
    original=metadata(p); digest=digest_audio(p)
    run('edit',p,cover,'1')
    edited=metadata(p)
    assert edited['TITLE']=='Canción de prueba Ø',(p,edited)
    assert edited['ITUNESADVISORY']=='1',(p,edited)
    assert int(edited['ARTWORK_BYTES'])==cover.stat().st_size,(p,edited)
    assert original['DURATION']==edited['DURATION']
    assert digest==digest_audio(p),f'Audio payload changed: {p}'
    independent=File(p)
    if p.suffix=='.m4a':assert independent.tags['rtng']==[1],independent.tags
    elif p.suffix in ('.mp3','.wav','.aiff'):assert str(independent.tags['TXXX:ITUNESADVISORY'])=='1'
    else:assert independent.tags['ITUNESADVISORY']==['1']
    run('rating',p,'2'); assert metadata(p)['ITUNESADVISORY']=='2'
    run('rating',p,'0'); assert metadata(p)['ITUNESADVISORY'] in ('','0')
    run('remove-cover',p); assert metadata(p)['ARTWORK_BYTES']=='0'
    run('erase',p); assert metadata(p)['TITLE']==''
    assert digest==digest_audio(p)
    report.append({'format':p.suffix,'unicode':True,'explicit_clean_none':True,'artwork_add_remove':True,'audio_payload_unchanged':True})
bad=scratch/'broken.mp3';bad.write_bytes(b'not an audio file')
result=subprocess.run([str(cli),'rating',str(bad),'1'],capture_output=True)
assert result.returncode!=0
p=scratch/'preserve.mp3';p.write_bytes((root/'Tests/Fixtures/lame_vbr.mp3').read_bytes())
f=File(p)
if f.tags is None:f.add_tags()
f.tags.add(TXXX(encoding=3,desc='RIVO_CUSTOM',text=['keep me']))
f.tags.add(POPM(email='test',rating=200,count=4))
f.tags.add(APIC(encoding=3,mime='image/png',type=4,desc='back',data=cover.read_bytes()))
f.save()
run('edit',p,cover,'1')
after=File(p)
assert str(after.tags['TXXX:RIVO_CUSTOM'])=='keep me'
assert after.tags.getall('POPM')[0].rating==200
assert sorted(int(x.type) for x in after.tags.getall('APIC'))==[3,4]
print(json.dumps({'passed':len(report),'formats':report,'invalid_file_rejected':True,'unknown_tags_star_rating_back_cover_preserved':True},ensure_ascii=False,indent=2))
