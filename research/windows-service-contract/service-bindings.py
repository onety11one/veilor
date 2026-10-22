exec(open('work/karing-feasibility/disasm-service.py',encoding='utf-8').read().split('selected=[]')[0])
def q(va):return struct.unpack_from('<Q',b,offset(va))[0]
def gostring(va):
 ptr,length=struct.unpack_from('<QQ',b,offset(va))
 if length>256:return None
 return b[offset(ptr):offset(ptr)+length].decode('ascii')
bindings=[]
for label,globalva in [('root',0x143502348),('run2',0x143502428)]:
 obj=q(globalva);callbacks=[]
 for field in range(0,0x200,8):
  try:
   value=q(obj+field)
   if value in names:callbacks.append({'fieldOffset':hex(field),'function':names[value],'indirection':0})
   elif q(value) in names:callbacks.append({'fieldOffset':hex(field),'function':names[q(value)],'indirection':1})
  except (ValueError,struct.error):pass
 bindings.append({'label':label,'global':hex(globalva),'object':hex(obj),'use':gostring(obj),'callbacks':callbacks})
# createHttpServer initializes a router itab referenced at this address.
getaddr=next(addr for addr,name in names.items() if name=='github.com/go-chi/chi/v5.(*Mux).Get')
matches=[];needle=struct.pack('<Q',getaddr);pos=b.find(needle)
while pos>=0:
 for rva,size,raw,rawsize in sections:
  if raw<=pos<raw+rawsize:
   va=base+rva+pos-raw
   if q(va-8) in names and q(va+8) in names:matches.append(va-0x30)
 pos=b.find(needle,pos+8)
if len(matches)!=1:raise ValueError('Expected unique Router itab Get slot')
itab=matches[0]
slots=[]
for slot in range(24,200,8):
 try:
  ptr=q(itab+slot)
  if ptr not in names:break
  slots.append({'offset':hex(slot),'function':names[ptr]})
 except (ValueError,struct.error):pass
result={'scope':'Static Cobra command object/function-value pointers and router interface table; not executed',
 'commands':bindings,'routerItabCandidate':hex(itab),'routerSlots':slots}
pathlib.Path('outputs/veilor/research/windows-service-contract/service-static-bindings.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
