"""Pinned static stop/state evidence; never sends commands or kills processes."""
import pathlib,runpy,re,json,hashlib
base=pathlib.Path(__file__).resolve().parent
ctx=runpy.run_path(str(base/'inspect-config-callers.py'))
text=(base/'config-callers-annotated.txt').read_text(encoding='utf-8')
ins={int(a,16):line for a,line in re.findall(r'^(0x[0-9a-f]+): (.*)$',text,re.M)}
out=base.parents[1]/'outputs/veilor/research/windows-service-contract'
checks=[]
def check(addr,code):
    assert ins[addr].split(' ; ')[0]==code,(hex(addr),code)
    checks.append({'address':hex(addr),'instruction':code})
for address,code in [
 (0xc48b78,'mov qword ptr [rax + 0x4290], rdx'),(0xc48bef,'call 0xc490a8'),(0xc48bff,'call 0xc49028'),(0xc48c67,'call 0xc48e00'),(0xc48c8c,'mov qword ptr [rcx + 0x4290], rdx'),(0xc48d0b,'call 0xc48d9c'),
 (0xc49221,'mov rax, qword ptr [rax + 0x4280]'),(0xc49232,'cmp rax, 0'),(0xc4923f,'mov rdi, qword ptr [r15 + 0x2fc7f]'),(0xc4924d,'mov rbx, qword ptr [r15 + 0x2fc87]'),(0xc49254,'call 0xc4af14'),(0xc49275,'mov qword ptr [rax + 0x4268], rdx'),(0xc49287,'call 0xc4ad68'),(0xc492c1,'call 0xa79990'),(0xc492e2,'call 0xc4ac50'),(0xc492e7,'mov rdi, qword ptr [r15 + 0xafcf]'),(0xc492f2,'call 0xc49028'),(0xc4935a,'call 0xc48e00'),(0xc49385,'call 0xc4ac08'),(0xc49395,'mov qword ptr [rax + 0x4260], rdx'),(0xc493e3,'call 0xc49450'),(0xc49423,'call 0xc49450'),
 (0xc49469,'call 0xc496a4'),(0xc4951d,'mov rax, qword ptr [rbx + 0xf]'),(0xc4955c,'mov rdx, qword ptr [rcx + 7]'),(0xc49582,'call 0xc49614'),
 (0xd86bf7,'call 0xc490a8'),(0xd86c04,'call 0xc49028'),(0xd86c6c,'call 0xc48e00'),
 (0xd86281,'mov qword ptr [rax + 0x4260], rdx'),(0xd86293,'mov qword ptr [rax + 0x4268], rdx'),(0xd8629e,'mov rax, qword ptr [rax + 0x4290]'),(0xd862ac,'jne 0xd8638a'),(0xd862b6,'mov rax, qword ptr [rax + 0x4298]'),
 (0xc48dc9,'mov rcx, qword ptr [rcx + 0x4260]'),(0xc48dd7,'je 0xc48de9'),(0xc48ddd,'mov rax, qword ptr [r15 + 0xd2ff]'),(0xc48de9,'mov rax, qword ptr [r15 + 0xd317]'),
 (0x10c1309,'cmp rax, qword ptr [r15 + 0xd317]'),(0x10c1316,'call 0xc6ab78'),(0x10c1339,'call 0xc6aa34'),(0x10c13e4,'call 0xa77240'),(0x10c13ed,'mov rax, qword ptr [rax + 0x3498]'),(0x10c1523,'call rcx'),(0xc6ab3d,'mov r11, qword ptr [r15 + 0x301c7]'),(0xc6ab4c,'call 0x150c724'),
 (0xc49067,'call 0xa77f48'),(0xc490fc,'call rcx')]:check(address,code)
repeat=(base/'aot-pool-repeat/dump/pp.txt').read_text(encoding='utf-8')
def duration(offset,expected):
    pattern=r'\[pp\+'+hex(offset)+r'\] Obj!Duration[^\n]*\n\s*off_8: int\((0x[0-9a-f]+)\)'
    for file in ['aot-pool-diagnostic','aot-pool-repeat']:
        data=(base/file/'dump/pp.txt').read_text(encoding='utf-8')
        assert int(re.search(pattern,data)[1],16)==expected
for offset,micros in [(0x2fc50,8000000),(0x2fc88,200000),(0xafd0,10000000)]:duration(offset,micros)
for offset,value in [(0x2fc80,'stop'),(0x301c8,'cleanSystemProxy')]:
    expected='String: '+json.dumps(value)
    assert ctx['pool'][offset]==expected and f'[pp+{hex(offset)}] '+expected in repeat
assert ctx['pool'][0x30a20].startswith('AnonymousClosure: static (0xd86264), in [package:vpn_service/vpn_service_method_channel_pc.dart]')
assert '[pp+0x30a20] '+ctx['pool'][0x30a20] in repeat
closure=ctx['pool'][0x2fc68]
assert "Function '_stop@" in closure and 'static.' in closure
report={'scope':'Static stop/state contract, Karing 1.2.25+2802; no runtime cleanup validation','inputSha256':hashlib.sha256(ctx['blob']).hexdigest(),'instructionChecks':checks,'durationsMicroseconds':{'outerStopRace':8000000,'httpRequestArgument':200000,'internalExitRace':10000000},'behavior':{'httpStop':'request stop if service HTTP port is nonzero','processFallback':'wait exit/timeout, killPid captured PID, clear handle, then enumerate/filter processes and attempt kill','scopeWarning':'name-based fallback is broader than own child; do not execute it on host','exitCallback':'clears process/started; suppresses callback when operation slot 0x4290 non-null','stateQuery':'branches on process reference, not a verified socket/traffic/network cleanup check','proxyCleanup':'state callback compares enum object at pp+0xd318; conditionally calls cleanSystemProxy, catches/logs failure, then forwards events'},'limitations':['Human-readable enum names not recovered from indices','Exact case semantics of dynamic name comparison not resolved','HTTP method/URL/auth and response consumption require separate verification','No confirmed wait after final kill or completed proxy restoration','No guarantees outer Future.any cancels losing operation','Other versions not established']}
(out/'windows-stop-state.json').write_text(json.dumps(report,indent=2)+'\n')
selected=[]
for part in text.split('\n# '):
    if part.split('\n')[0] in ('PC.stop','PC._stop','PC._killProcesses','PC._stopWithoutUpdateState','PC.exitCallback','VPNService.stateCallback','PC._currentState','PC.cleanSystemProxy','FlutterVpnWait.waitTimeout','FlutterVpnWait.wait','FlutterVpnWait.waitProcessExit'):selected.append('# '+part.strip())
(out/'windows-stop-state-x64.txt').write_text('\n\n'.join(selected)+'\n',encoding='utf-8')
print(json.dumps({'instructionChecks':len(checks),'durationConstants':3,'coreExecuted':False,'commandsSent':False}))
