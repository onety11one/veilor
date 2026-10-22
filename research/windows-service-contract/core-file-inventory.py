"""Offline PE imports and public asset filenames only; no profile reads."""
exec(open('work/karing-feasibility/disasm-service.py',encoding='utf-8').read().split('selected=[]')[0])
imports=[]
importRva=struct.unpack_from('<I',b,opt+112+8)[0]
if importRva:
 pos=offset(base+importRva)
 for _ in range(256):
  row=struct.unpack_from('<IIIII',b,pos)
  if not any(row):break
  at=offset(base+row[3]);end=b.index(b'\0',at)
  imports.append(b[at:end].decode('ascii'));pos+=20
assets=pathlib.Path('outputs/veilor/assets/datas')
files=[{'path':p.relative_to(assets).as_posix(),'bytes':p.stat().st_size} for p in sorted(assets.rglob('*')) if p.is_file()]
installed=pathlib.Path('C:/Program Files/Karing/data/flutter_assets/assets/datas')
installedNames=[p.relative_to(installed).as_posix() for p in sorted(installed.rglob('*')) if p.is_file()]
result={'scope':'PE static imports and public asset file names/sizes; neither import completeness nor universal runtime requirements',
 'staticPeImports':imports,'repoDataFiles':files,'installedDataFileCount':len(installedNames),
 'installedOnlyNames':sorted(set(installedNames)-{x['path'] for x in files}),
 'repoOnlyNames':sorted({x['path'] for x in files}-set(installedNames))}
folder=pathlib.Path('outputs/veilor/research/windows-service-contract')
(folder/'core-file-inventory.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'staticPeImports':imports,'repoDataFileCount':len(files),'installedDataFileCount':len(installedNames),'installedOnlyCount':len(result['installedOnlyNames']),'repoOnlyCount':len(result['repoOnlyNames'])}))
