"""Offline, allowlisted metadata only. Does not load the snapshot into a VM."""
import pathlib,struct,json,hashlib,re
p=pathlib.Path('work/karing-feasibility/targets/app.so');b=p.read_bytes()
assert b[:6]==b'\x7fELF\x02\x01','Expected ELF64 little-endian'
shoff=struct.unpack_from('<Q',b,40)[0];entsize,count,shstr=struct.unpack_from('<HHH',b,58)
rows=[struct.unpack_from('<IIQQQQIIQQ',b,shoff+i*entsize) for i in range(count)]
strings=rows[shstr];names=b[strings[4]:strings[4]+strings[5]]
def cstr(data,pos):return data[pos:data.index(b'\0',pos)].decode('utf-8',errors='replace')
sections=[{'name':cstr(names,r[0]),'type':r[1],'address':hex(r[3]),'offset':r[4],'size':r[5]} for r in rows]
symbols=[]
for r in rows:
 if r[1] not in [2,11]:continue
 sr=rows[r[6]];st=b[sr[4]:sr[4]+sr[5]]
 for at in range(r[4],r[4]+r[5],r[9]):
  name,info,other,index,value,size=struct.unpack_from('<IBBHQQ',b,at)
  symbols.append({'name':cstr(st,name),'address':hex(value),'size':size,'section':index})
allow=['VpnServiceConfig','FlutterVpnService','control_port','secret','install_refer','service-config','service-http-port','connected-port','prepareConfig','currentState','vpn_service.dart','vpn_service_platform_interface.dart','vpn_service_windows.dart','proxy_manager.dart','getSecret','toJson','fromJson']
hits=[]
for text in allow:
 found=[];at=b.find(text.encode())
 while at>=0:
  found.append(at);at=b.find(text.encode(),at+1)
 hits.append({'text':text,'offsets':found})
engine=pathlib.Path('C:/Program Files/Karing/flutter_windows.dll').read_bytes()
versions=sorted(set(m.group().decode() for m in re.finditer(rb'\b3\.\d+\.\d+ \(stable\) [^\x00\r\n]{1,100}',engine)))
snapshotSymbols=[s for s in symbols if 'Snapshot' in s['name']]
headers=[]
for s in snapshotSymbols:
 va=int(s['address'],16)
 section=next((r for r in rows if r[3]<=va<r[3]+r[5] and r[1]!=8),None)
 if not section:continue
 off=section[4]+va-section[3]
 if b[off:off+4]==b'\xf5\xf5\xdc\xdc':
  # Snapshot header: magic, uint64 length, int64 kind, 32-byte version hash,
  # followed by NUL-terminated features. Layout verified separately.
  headers.append({'symbol':s['name'],'offset':off,'prefixHex':b[off:off+20].hex(),
    'hashCandidate':b[off+20:off+52].decode('ascii',errors='replace'),
    'featureCandidate':cstr(b,off+52)[:256]})
out={'scope':'Offline ELF/allowlisted names; substring offsets are not function mappings or recovered defaults',
 'sha256':hashlib.sha256(b).hexdigest(),'machine':struct.unpack_from('<H',b,18)[0],
 'sections':sections,'snapshotSymbols':snapshotSymbols,'symbolCount':len(symbols),'allowlistedStrings':hits,
 'engineVersionCandidates':versions,'snapshotHeaders':headers}
folder=pathlib.Path('outputs/veilor/research/windows-service-contract');(folder/'dart-aot-inventory.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps({'sha256':out['sha256'],'machine':out['machine'],'symbols':snapshotSymbols,'versions':versions,'snapshotHeaders':headers,'strings':hits},indent=2))
