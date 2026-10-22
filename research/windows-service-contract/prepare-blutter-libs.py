"""Fetch official open-source release archives into workspace; never install."""
import urllib.request,zipfile,pathlib,hashlib,json,io,shutil
root=pathlib.Path(__file__).resolve().parent.parent/'blutter-windows'
external=root/'external';external.mkdir(exist_ok=True)
def extract(blob,destination):
 destination.mkdir(exist_ok=True)
 with zipfile.ZipFile(io.BytesIO(blob)) as z:
  for entry in z.infolist():
   target=(destination/entry.filename).resolve()
   if not target.is_relative_to(destination.resolve()):raise ValueError('Archive path escaped')
  if z.testzip() is not None:raise ValueError('Archive CRC failure')
  z.extractall(destination)
records=[]
icuUrl='https://github.com/unicode-org/icu/releases/download/release-73-2/icu4c-73_2-Win64-MSVC2019.zip'
capUrl='https://github.com/capstone-engine/capstone/releases/download/4.0.2/capstone-4.0.2-win64.zip'
for name,url in [('icu',icuUrl),('capstone',capUrl)]:
 archive=external/(name+'-upstream.zip')
 if not archive.exists():
  with urllib.request.urlopen(url,timeout=60) as response:archive.write_bytes(response.read())
 blob=archive.read_bytes();destination=external/('icu-windows' if name=='icu' else 'capstone-unpacked')
 if not destination.exists():
  if name=='icu':
   with zipfile.ZipFile(io.BytesIO(blob)) as z:
    inner=[x for x in z.namelist() if x.endswith('.zip')]
    if len(inner)!=1:raise ValueError('Unexpected ICU outer archive')
    blobInner=z.read(inner[0]);extract(blobInner,destination)
  else:extract(blob,destination)
 records.append({'name':name,'url':url,'bytes':len(blob),'sha256':hashlib.sha256(blob).hexdigest(),'verification':'ZIP CRC and path checks; digest recorded, not a publisher signature'})
capRoot=next((external/'capstone-unpacked').iterdir())
if not (external/'capstone').exists():capRoot.rename(external/'capstone')
binDir=root/'bin';binDir.mkdir(exist_ok=True)
for source in [external/'capstone/capstone.dll',external/'icu-windows/bin64/icuuc73.dll',external/'icu-windows/bin64/icudt73.dll']:
 shutil.copy2(source,binDir/source.name)
pathlib.Path(__file__).with_name('open-source-libs.json').write_text(json.dumps(records,indent=2)+'\n')
print(json.dumps(records))
