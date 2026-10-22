"""Candidate direct RIP-relative references, validated at function boundaries."""
exec(open('work/karing-feasibility/disasm-service.py',encoding='utf-8').read().split('selected=[]')[0])
import bisect,re
folder=pathlib.Path('outputs/veilor/research/windows-service-contract')
fields=[s['field'] for s in json.loads((folder/'local-schema-observation.json').read_text())['serviceConfigSchema']]
targets={}
for key in fields:
 for section in sections:
  rva,_,raw,length=section
  if rva==0x1000:continue
  pos=b.find(key.encode(),raw,raw+length)
  while pos>=0:
   targets.setdefault(base+rva+pos-raw,[]).append(key)
   pos=b.find(key.encode(),pos+1,raw+length)
starts=[int(f['address'],16) for f in funcs]
rva,_,raw,length=next(s for s in sections if s[0]==0x1000)
candidates={}
for m in re.finditer(rb'[\x48-\x4f][\x8d\x8b][\x05\x0d\x15\x1d\x25\x2d\x35\x3d]',b[raw:raw+length-4]):
 pos=raw+m.start();pc=base+rva+pos-raw;dest=pc+7+struct.unpack_from('<i',b,pos+3)[0]
 if dest not in targets:continue
 idx=bisect.bisect_right(starts,pc)-1
 if idx>=0:candidates.setdefault(idx,[]).append((pc,dest))
refs=[]
for idx,items in candidates.items():
 f=funcs[idx];start=starts[idx];off=offset(start)
 decoded={i.address:i for i in md.disasm(b[off:off+f['size']],start)}
 for pc,dest in items:
  i=decoded.get(pc)
  if i is not None and i.size==7:
   refs.append({'function':f['name'],'pc':hex(pc),'keys':targets[dest],'address':hex(dest),'asm':i.mnemonic+' '+i.op_str})
result={'scope':'Direct references are candidates, not complete JSON consumer proof; reflection, indirect pointers and other binaries not covered',
 'fields':[{ 'field':key,'directReferences':[r for r in refs if key in r['keys']]} for key in fields]}
(folder/'service-field-xrefs.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({key:sorted(set(r['function'] for r in refs if key in r['keys'])) for key in fields},indent=2))
