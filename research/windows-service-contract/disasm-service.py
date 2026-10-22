"""Offline x64 disassembly. Never loads or starts the subject executable."""
import sys,json,struct,pathlib
sys.path.insert(0,str(pathlib.Path('work/karing-feasibility/python-deps').resolve()))
from capstone import Cs,CS_ARCH_X86,CS_MODE_64
from capstone.x86 import X86_OP_IMM,X86_OP_MEM,X86_REG_RIP
b=pathlib.Path('work/karing-feasibility/targets/karingService.exe').read_bytes()
pe=struct.unpack_from('<I',b,0x3c)[0]; opt=pe+24
base=struct.unpack_from('<Q',b,opt+24)[0]
sections=[]
for i in range(struct.unpack_from('<H',b,pe+6)[0]):
 s=opt+struct.unpack_from('<H',b,pe+20)[0]+40*i
 size,rva,rawsize,raw=struct.unpack_from('<IIII',b,s+8)
 sections.append((rva,max(size,rawsize),raw,rawsize))
def offset(va):
 rva=va-base
 for start,size,raw,rawsize in sections:
  if start<=rva<start+rawsize:return raw+rva-start
 raise ValueError('Unmapped address')
funcs=json.loads(pathlib.Path('work/karing-feasibility/go-all-functions.json').read_text())
names={int(f['address'],16):f['name'] for f in funcs}
md=Cs(CS_ARCH_X86,CS_MODE_64);md.detail=True
selected=[]
for f in funcs:
 if f['name'] not in ['main.init','main.run','main.preRun','main.createHttpServer',
  'main.restartService','main.createService','main.create','main.runService','main.destroyAll','main.destroyService',
  'main.main','main.makeProcessSingleton'] and not f['name'].startswith(('main.createHttpServer.','main.init.','main.run.')):continue
 start=int(f['address'],16);o=offset(start);lines=[]
 decoded=list(md.disasm(b[o:o+f['size']],start))
 for idx,ins in enumerate(decoded):
  item={'pc':hex(ins.address),'asm':ins.mnemonic+' '+ins.op_str}
  if ins.mnemonic in ['call','jmp'] and len(ins.operands)==1 and ins.operands[0].type==X86_OP_IMM:
   dest=ins.operands[0].imm;item['target']=names.get(dest,hex(dest))
  for op in ins.operands:
   if op.type==X86_OP_MEM and op.mem.base==X86_REG_RIP:
    va=ins.address+ins.size+op.mem.disp;item['ripAddress']=hex(va)
    try:
     r=offset(va);data=b[r:r+80]
     pointer=struct.unpack_from('<Q',b,r)[0]
     if pointer in names:item['dataFunctionPointer']=names[pointer]
     for depth,location in [(0,va),(1,pointer)]:
      try:
       go=offset(location);ptr,length=struct.unpack_from('<QQ',b,go)
       if 0<length<=256:
        text=b[offset(ptr):offset(ptr)+length]
        if len(text)==length and all(v in [9,10,13] or 32<=v<127 for v in text):item['goString'+str(depth)]=text.decode('ascii')
      except (ValueError,struct.error):pass
     if all(32<=v<127 for v in data[:4]):
      item['literalPreview']=''.join(chr(v) if 32<=v<127 else '.' for v in data)
      if ins.mnemonic=='lea' and idx+1<len(decoded):
       nextins=decoded[idx+1]
       if nextins.mnemonic=='mov' and len(nextins.operands)==2 and nextins.operands[1].type==X86_OP_IMM:
        length=nextins.operands[1].imm
        if 0<length<=256:
         literal=b[r:r+length]
         if all(v in [9,10,13] or 32<=v<127 for v in literal):item['adjacentLengthLiteral']={'length':length,'value':literal.decode('ascii'),'caution':'length association must be checked against calling convention'}
    except ValueError:pass
  lines.append(item)
 selected.append({'name':f['name'],'address':f['address'],'size':f['size'],'instructions':lines})
out=pathlib.Path('outputs/veilor/research/windows-service-contract/service-disassembly.json')
out.write_text(json.dumps({'scope':'Capstone x64 decode and Go pclntab symbols; previews are not exact string boundaries; no dynamic execution','functions':selected},indent=2)+'\n')
for f in selected:
 if f['name'].startswith('main.init.'):
  refs=[x for x in f['instructions'] if 'adjacentLengthLiteral' in x or x.get('target','').startswith('github.com/spf13/')]
  if refs:print(json.dumps({'name':f['name'],'refs':refs}))
