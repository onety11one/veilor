exec(open('work/karing-feasibility/disasm-service.py',encoding='utf-8').read().split('selected=[]')[0])
import bisect
starts=[int(f['address'],16) for f in funcs]
targetNames={'main.createHttpServer','main.createService','main.destroyAll','main.preRun','main.runService'}
targets={addr:name for addr,name in names.items() if name in targetNames}
refs=[]
text=next(s for s in sections if s[0]==0x1000);rva,_,raw,length=text
at=b.find(b'\xe8',raw,raw+length)
while at>=0 and at<raw+length-5:
 va=base+rva+at-raw;dest=va+5+struct.unpack_from('<i',b,at+1)[0]
 if dest in targets:
  index=bisect.bisect_right(starts,va)-1
  if index>=0:
   f=funcs[index];start=starts[index];off=offset(start)
   if any(i.address==va and i.mnemonic=='call' for i in md.disasm(b[off:off+f['size']],start)):
    refs.append({'owner':f['name'],'pc':hex(va),'target':targets[dest]})
 at=b.find(b'\xe8',at+1,raw+length)
pathlib.Path('outputs/veilor/research/windows-service-contract/service-call-xrefs.json').write_text(json.dumps(refs,indent=2)+'\n')
print(json.dumps(refs,indent=2))
