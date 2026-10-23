"""Offline config evidence from pinned AOT bytes and two saved pool dumps.
No VM, application, network, credentials or user configuration is accessed.
"""
import pathlib,sys,re,json,hashlib
base=pathlib.Path(__file__).resolve().parent
sys.path.insert(0,str(base/'python-deps'))
from capstone import Cs,CS_ARCH_X86,CS_MODE_64
from elftools.elf.elffile import ELFFile
out=base.parents[1]/'outputs/veilor/research/windows-service-contract'
target=base/'targets/app.so';blob=target.read_bytes()
expected='38c1b08f0f12c0934f3e25a2dd7c4f276c690be457a4b24377d1cea36c740882'
assert hashlib.sha256(blob).hexdigest()==expected
with target.open('rb') as f:sections=list(ELFFile(f).iter_sections())
cs=Cs(CS_ARCH_X86,CS_MODE_64)
def instructions(address,size):
    s=next(s for s in sections if s['sh_type']!='SHT_NOBITS' and s['sh_addr']<=address and address+size<=s['sh_addr']+s['sh_size'])
    offset=s['sh_offset']+address-s['sh_addr'];code=blob[offset:offset+size]
    result=list(cs.disasm(code,address));assert sum(i.size for i in result)==size
    return result
def pool(folder):
    return {int(m[1],16):m[2] for m in re.finditer(r'^\[pp\+(0x[0-9a-f]+)\] (.*)$',(base/folder/'dump/pp.txt').read_text(encoding="utf-8-sig"),re.M)}
p=pool('aot-pool-diagnostic');q=pool('aot-pool-repeat');used={}
def entry(displacement):
    # PP is a tagged pointer; dumper offsets are measured from untagged base.
    offset=displacement+1
    assert p[offset]==q[offset]
    used[hex(offset)]=p[offset]
    return p[offset]
body=instructions(0xd86650,0x4e0);fields=[]
for index,i in enumerate(body):
    m=re.fullmatch(r'r11, qword ptr \[r15 \+ (0x[0-9a-f]+)\]',i.op_str)
    if i.mnemonic!='mov' or not m:continue
    value=entry(int(m[1],16))
    if not value.startswith('String: '):continue
    key=json.loads(value.removeprefix('String: '))
    assert body[index+1].mnemonic=='mov'
    assert body[index+1].op_str==f'qword ptr [rcx + {hex(0x17+16*len(fields))}], r11'
    following=body[index+1:index+7]
    load=next(j for j in following if re.fullmatch(r'(?:rax|rdx), qword ptr \[rsi \+ (?:0x[0-9a-f]+|[0-9]+)\]',j.op_str))
    disp=int(re.search(r'\+ ([^\]]+)\]',load.op_str)[1],0)
    fields.append({'key':key,'objectOffset':hex(disp+1),'keyInstruction':hex(i.address),'loadInstruction':hex(load.address),'poolOffset':hex(int(m[1],16)+1)})
assert len(fields)==25 and len({f['key'] for f in fields})==25
assert any(i.mnemonic=='mov' and i.op_str=='r10d, 0x64' for i in body)
assert any(i.mnemonic=='call' and i.op_str=='0xa50bc8' for i in body)
wrapper=instructions(0xd8662a,0x26)
assert any(i.mnemonic=='call' and i.op_str=='0xd86650' for i in wrapper)
assert entry(0x271f)=='TypeArguments: <String, dynamic>'
observed=json.loads((out/'service-config-contract.json').read_text(encoding="utf-8-sig"))
assert {f['key'] for f in fields}=={f['field'] for f in observed['fields']}
ctor=instructions(0xd8652c,0xe8)
# Match the exact AOT/product/x64/no-compressed-pointers offsets block.
sdk=base.parents[1]/'work/toolchains/blutter-windows/dartsdk/v3.12.2/runtime/vm/compiler/runtime_offsets_extracted.h'
source=sdk.read_text(encoding="utf-8-sig")
blocks=re.findall(r'#if defined\(PRODUCT\) && defined\(TARGET_ARCH_X64\) &&\s*\\\s*!defined\(DART_COMPRESSED_POINTERS\)(.*?)#endif',source,re.S)
assert len(blocks)==2  # JIT and AOT; choose the block containing AOT names.
block=next(b for b in blocks if 'AOT_Thread_bool_true_offset' in b)
offsets={name:int(re.search(r'AOT_Thread_'+name+r'_offset\s*=\s*(0x[0-9a-f]+)',block)[1],16) for name in ['bool_true','bool_false','object_null']}
assert offsets=={'bool_true':0x90,'bool_false':0x98,'object_null':0x80}
registers={};stores={}
for i in ctor:
    if i.mnemonic=='xor' and i.op_str=='esi, esi':registers['rsi']={'value':0,'kind':'integer'}
    if i.mnemonic=='mov':
        m=re.fullmatch(r'(rdx|rcx|rax), qword ptr \[r14 \+ (0x[0-9a-f]+)\]',i.op_str)
        if m:
            offset=int(m[2],16)
            if offset in (0x90,0x98):registers[m[1]]={'value':offset==0x90,'kind':'boolean'}
            elif offset==0x80:registers[m[1]]={'value':None,'kind':'null'}
        m=re.fullmatch(r'rdx, qword ptr \[r15 \+ (0x[0-9a-f]+)\]',i.op_str)
        if m:
            assert entry(int(m[1],16))=='String: ""'
            registers['rdx']={'value':'','kind':'string'}
        m=re.fullmatch(r'qword ptr \[(?:rbx|rcx) \+ (0x[0-9a-f]+|[0-9]+)\], (rsi|rdx|rcx|rax)',i.op_str)
        if m:
            offset=int(m[1],0)+1
            if m[2] in registers:stores[offset]={**registers[m[2]],'instruction':hex(i.address)}
    if i.mnemonic=='call':
        # Do not propagate register values across calls, even write barriers.
        registers={k:v for k,v in registers.items() if k=='rsi'}
for field in fields:
    default=stores.get(int(field['objectOffset'],16))
    field['constructorDefault']=default or {'kind':'unresolved','reason':'No supported explicit constructor store; allocation/helper must be inspected'}
    field['scope']='constructor default only; caller can overwrite before serialization'
assert sum(f['constructorDefault']['kind']!='unresolved' for f in fields)==23
assert entry(0x100f)=='TypeArguments: <String>'
factory=instructions(0xa579f8,0x80)
allocator=instructions(0x1533420,0x54)
def has(seq,mnemonic,operands):return any(i.mnemonic==mnemonic and i.op_str==operands for i in seq)
assert has(ctor,'call','0xa579f8') and has(ctor,'mov','qword ptr [rcx + 0x7f], rax')
assert has(factory,'mov','qword ptr [rdx + 0xf], 0')
assert has(factory,'cmp','rcx, 0') and has(factory,'jle','0xa57a67')
assert has(factory,'mov','rax, rdx')
length=int(re.search(r'AOT_GrowableObjectArray_length_offset\s*=\s*(0x[0-9a-f]+)',block)[1],16)
assert length==0x10
# Constructor RSI is zero and remains so on this normal path until the factory.
assert not any(i.address<0xd865d7 and i.mnemonic not in ('xor',) and i.op_str.startswith(('rsi,','esi,')) for i in ctor)
listField=next(f for f in fields if f['key']=='allowed_sender_packages')
assert listField['objectOffset']=='0x80'
listField['constructorDefault']={'value':[],'kind':'list<string>','evidence':'zero RSI length, String type arguments, GrowableList factory, length store at 0xa57a38, result store at 0xd865e0'}
# Allocation fills all instance fields with the canonical null object.
assert has(allocator,'mov','r10, qword ptr [r14 + 0x80]')
assert has(allocator,'mov','qword ptr [rdi], r10')
assert has(allocator,'mov','qword ptr [rdi + 8], r10')
assert has(allocator,'add','rdi, 0x10')
last=next(f for f in fields if f['key']=='sentry_minversion')
assert last['objectOffset']=='0xc8' and 0xc8 not in stores
last['constructorDefault']={'value':None,'kind':'null','evidence':'allocation null-initialization; no constructor overwrite of object offset 0xc8'}
report={'inputSha256':expected,'sourceVersion':'Karing 1.2.25+2802 / Dart 3.12.2','mode':'offline only','fieldCount':25,'explicitScalarDefaultsRecovered':23,'helperOrAllocationDefaultsRecovered':2,'poolEntries':used,'threadOffsets':offsets,'fields':fields,'limitations':['Not evidence for active source version 1.2.26+2908','Constructor defaults are not valid launch configuration','No native consumer or launch behavior inferred from key names','Slow allocation uses VM runtime semantics; no live allocation invoked']}
(out/'vpn-config-recovered.json').write_text(json.dumps(report,indent=2)+'\n')
lines=['# Selected constructor dependencies; static x64 disassembly only.']
for addr,size,name in [(0xa579f8,0x80,'GrowableList factory'),(0xd86b50,0xc,'VpnServiceConfig allocation stub'),(0x1533420,0x54,'Generic allocation stub')]:
    lines.append('\n'+name)
    lines.extend(f'{i.address:#x}: {i.mnemonic} {i.op_str}'.rstrip() for i in instructions(addr,size))
(out/'vpn-config-helper-x64.txt').write_text('\n'.join(lines)+'\n')
print(json.dumps({'fields':len(fields),'scalarDefaults':23,'helperOrAllocationDefaults':2,'unresolved':[f['key'] for f in fields if f['constructorDefault']['kind']=='unresolved']}))
