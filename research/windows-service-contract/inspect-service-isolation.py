"""Static instructions for singleton and service-config consumers."""
exec(open('work/karing-feasibility/disasm-service.py',encoding='utf-8').read().split('selected=[]')[0])
wanted={'main.makeProcessSingleton','main.terminateProcess','main.terminateCurrentProcess',
 'main.getResolvedExePath','main.setUpDir','main.createService',
 'github.com/sagernet/sing-box/experimental/libbox.NewService',
 'github.com/sagernet/sing-box/experimental/libbox.SentryInit',
 'github.com/sagernet/sing-box/experimental/libbox.SentryInitPrivate',
 'github.com/sagernet/sing-box/experimental/libbox.Setup',
 'github.com/sagernet/sing-box/experimental/libbox.StderrRedirect',
 'github.com/sagernet/sing-box/daemon.NewStartedService',
 'github.com/sagernet/sing-box/experimental/libbox.(*BoxService).Start'}
selected=[]
for f in funcs:
 if f['name'] not in wanted:continue
 start=int(f['address'],16);o=offset(start);lines=[]
 for ins in md.disasm(b[o:o+f['size']],start):
  item={'pc':hex(ins.address),'asm':ins.mnemonic+' '+ins.op_str}
  if ins.mnemonic in ['call','jmp'] and len(ins.operands)==1 and ins.operands[0].type==X86_OP_IMM:
   item['target']=names.get(ins.operands[0].imm,hex(ins.operands[0].imm))
  for op in ins.operands:
   if op.type==X86_OP_MEM and op.mem.base==X86_REG_RIP:
    va=ins.address+ins.size+op.mem.disp;item['ripAddress']=hex(va)
    try:
     data=b[offset(va):offset(va)+100]
     if all(32<=v<127 for v in data[:4]):item['preview']=''.join(chr(v) if 32<=v<127 else '.' for v in data)
    except ValueError:pass
  lines.append(item)
 selected.append({**f,'instructions':lines})
folder=pathlib.Path('outputs/veilor/research/windows-service-contract')
(folder/'isolation-disassembly.json').write_text(json.dumps({'scope':'Static x64 evidence; previews are not exact strings; subject not executed','functions':selected},indent=2)+'\n')
for f in selected:
 print(json.dumps({'name':f['name'],'refs':[i for i in f['instructions'] if i.get('preview') or (i.get('target') and i['asm'].startswith('call'))]}))
