"""Publish only selected VPN method metadata and static machine-code disassembly."""
import pathlib,sys,re,json,hashlib
base=pathlib.Path(__file__).resolve().parent
sys.path.insert(0,str(base/'python-deps'))
from capstone import Cs,CS_ARCH_X86,CS_MODE_64
from elftools.elf.elffile import ELFFile
root=base.parents[1];out=root/'outputs/veilor/research/windows-service-contract'
dump=base/'aot-pool-diagnostic/dump';repeat=base/'aot-pool-repeat/dump'
selected=['vpn_service_platform_interface.dart','vpn_service_method_channel_pc.dart','proxy_manager.dart','state.dart']
rows=[]
for name in selected:
    path=pathlib.Path('asm/vpn_service')/name
    text=(dump/path).read_text()
    assert text==(repeat/path).read_text(),f'Nonrepeatable metadata: {name}'
    cls=None;signature=None
    for line in text.splitlines():
        m=re.match(r'(?:abstract )?(?:class|enum) (\w+)',line)
        if m:cls=m[1]
        if line.startswith('  ') and line.rstrip().endswith('{'):signature=line.strip()[:-1].strip()
        m=re.search(r'addr: (0x[0-9a-f]+), size: (0x[0-9a-f]+)',line)
        if m:rows.append({'file':name,'class':cls,'signature':signature,'address':m[1],'size':int(m[2],16)})
target=base/'targets/app.so';blob=target.read_bytes()
assert hashlib.sha256(blob).hexdigest()=='38c1b08f0f12c0934f3e25a2dd7c4f276c690be457a4b24377d1cea36c740882'
lines=['# Static x64 disassembly; no inferred field names/defaults; addresses are ELF virtual addresses.']
with target.open('rb') as stream:
    elf=ELFFile(stream);sections=list(elf.iter_sections());cs=Cs(CS_ARCH_X86,CS_MODE_64)
    for row in rows:
        if row['class']!='VpnServiceConfig':continue
        addr=int(row['address'],16);size=row['size']
        section=next(s for s in sections if s['sh_addr']<=addr and addr+size<=s['sh_addr']+s['sh_size'] and s['sh_type']!='SHT_NOBITS')
        offset=section['sh_offset']+addr-section['sh_addr'];code=blob[offset:offset+size]
        instructions=list(cs.disasm(code,addr));assert sum(i.size for i in instructions)==size
        row['codeSha256']=hashlib.sha256(code).hexdigest()
        lines.append('\n'+row['signature']+' @ '+row['address'])
        lines.extend(f'{i.address:#x}: {i.mnemonic} {i.op_str}' for i in instructions)
report={'inputSha256':hashlib.sha256(blob).hexdigest(),'metadataMatchesTwoRuns':True,'classSize':{'VpnServiceConfig':208},'methods':rows,'limitations':['No Dart source recovery','No field/default interpretation yet','No standalone fromJson method observed in selected class; tree shaking/inlining not ruled out','Initial analyzer run crashed with 0xC0000005; subsequent diagnostic build completed twice; root cause not established']}
(out/'vpn-aot-methods.json').write_text(json.dumps(report,indent=2)+'\n')
(out/'vpn-config-x64.txt').write_text('\n'.join(lines)+'\n')
print(json.dumps({'methods':len(rows),'configMethods':sum(r['class']=='VpnServiceConfig' for r in rows),'repeatable':True}))
