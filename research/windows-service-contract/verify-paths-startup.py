"""Offline path/startup evidence. Never calls the inspected application."""
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
repeat=(base/'aot-pool-repeat/dump/pp.txt').read_text(encoding='utf-8')
strings={0xdba0:'profiles',0xda98:'__test_dir__',0xda10:'cache',0x30948:'service_error.log',0x30cc8:'service_core.log',0x30cd0:'service_core.json',0x30cd8:'service.json',0x30c90:'karingService.exe',0x1a28:'data',0x309d8:'run2',0x309e0:'--service-config=',0x309e8:'--service-http-port=',0x309f0:'--connected-port='}
for offset,value in strings.items():
    expected='String: '+json.dumps(value)
    assert ctx['pool'][offset]==expected
    assert f'[pp+{hex(offset)}] '+expected in repeat
for address,code in [
 (0xa85761,'call 0xa85774'),(0xa85706,'call 0xa8572c'),(0xa8570e,'mov rsi, qword ptr [r15 + 0xdb9f]'),
 (0xa7f896,'call 0xa856f8'),(0xa7f8e2,'call 0xa855bc'),(0xa7f909,'mov rsi, qword ptr [r15 + 0xda97]'),(0xa7f96c,'call 0xa84d30'),(0xa7f98d,'call 0xa84cd0'),(0xa7f9d1,'call 0xa7fa08'),(0xa7fa31,'call 0xa7fad0'),(0xa7fb20,'call 0xa7fb60'),(0xa7fbaa,'call 0xa7fbf4'),(0xa7fc1d,'call 0xa7fc44'),
 (0xd8800f,'call 0xa8572c'),(0xd88025,'mov rsi, qword ptr [r15 + 0x1a27]'),(0xdb50f6,'call 0xa8572c'),(0xdb50fe,'mov rsi, qword ptr [r15 + 0x30c8f]'),
 (0xcb103d,'call 0xa7f850'),(0xcb1056,'mov rsi, qword ptr [r15 + 0xda0f]'),(0xd8447d,'call 0xa7f850'),(0xd84496,'mov rsi, qword ptr [r15 + 0x30947]'),(0xd87f4d,'call 0xa7f850'),(0xd87f66,'mov rsi, qword ptr [r15 + 0x30cc7]'),(0xd87fad,'call 0xa7f850'),(0xd87fc6,'mov rsi, qword ptr [r15 + 0x30ccf]'),(0xd8807d,'call 0xa7f850'),(0xd88096,'mov rsi, qword ptr [r15 + 0x30cd7]'),
 (0xd84e07,'xor esi, esi'),(0xd84e09,'call 0xcdf434'),(0xd84f00,'call 0xfb1ecc'),(0xd84fde,'cmp rsi, 2'),(0xd85107,'call 0xd81ae0'),(0xd851d9,'cmp rax, 4'),(0xd8535c,'call 0xcdf3f8'),(0xd85383,'mov qword ptr [rcx + 0x4278], rdx'),(0xd85397,'mov rbx, qword ptr [r15 + 0x309cf]'),(0xd853b8,'call 0x1424178'),(0xd853dd,'mov rdx, qword ptr [rax + 0x1f]'),(0xd853e5,'mov qword ptr [rax + 0x4280], rdx'),
 (0xd85458,'mov r11, qword ptr [r15 + 0x309d7]'),(0xd85476,'mov r11, qword ptr [r15 + 0x309df]'),(0xd8553e,'mov r11, qword ptr [r15 + 0x309e7]'),(0xd8560d,'mov r11, qword ptr [r15 + 0x309ef]'),(0xd8572c,'call 0xa85774'),(0xd85774,'call 0xce32e8'),(0xd8579b,'mov qword ptr [rcx + 0x4260], rdx'),
 (0xd85892,'call 0xc4ac50'),(0xd8589e,'call 0xd85ebc'),(0xd858b1,'call 0xc49028'),(0xd85933,'call 0xc48e00'),(0xd85975,'call 0xd81a34'),(0xd8598c,'mov qword ptr [rcx + 0x4278], rdx'),
 (0xd85ef3,'mov rax, qword ptr [rax + 0x4288]'),(0xd85f21,'mov rsi, qword ptr [r15 + 0x526f]'),(0xd85f2c,'call 0xa77f48'),(0xd86b94,'mov rdx, qword ptr [r14 + 0x90]'),(0xd86b9f,'mov qword ptr [rcx + 0x4288], rdx'),(0xd85cb0,'mov qword ptr [rax + 0x4268], rdx')]:check(address,code)
# Closure must be linked to this callback, not guessed from neighbouring names.
assert ctx['pool'][0x309d0].startswith('AnonymousClosure: static (0xd86b5c), in [package:vpn_service/vpn_service_method_channel_pc.dart]')
assert '[pp+0x309d0] '+ctx['pool'][0x309d0] in repeat
assert re.search(r'\[pp\+0x5270\] Obj!Duration[^\n]*\n\s*off_8: int\(0x493e0\)',repeat)
assert re.search(r'\[pp\+0x2fc78\] Obj!VpnServiceWaitType[^\n]*\n\s*Super!_Enum : \{\n\s*off_8: int\(0x3\)',repeat)
paths={'exeDir':'dirname(Platform.resolvedExecutable)','portableCandidate':'exeDir/profiles; existing directory plus create/delete __test_dir__ probe','nonPortable':'getApplicationSupportDirectory through FlutterVpnService/MethodChannel/PC','base_dir':'selected profileDir','work_dir':'exeDir/data','cache_dir':'profileDir/cache','serviceConfig':'profileDir/service.json','core_path':'profileDir/service_core.json','log_path':'profileDir/service_core.log','err_path':'profileDir/service_error.log','serviceExecutable':'exeDir/karingService.exe','processWorkingDirectory':'dirname(serviceExecutable)'}
report={'scope':'Static Windows Karing 1.2.25+2802; not live VPN validation','inputSha256':hashlib.sha256(ctx['blob']).hexdigest(),'paths':paths,'instructionChecks':checks,'poolStrings':{hex(k):v for k,v in strings.items()},'startup':{'selectedPortCount':2,'temporarySocketLeasesClosedBeforeRebind':True,'connectedPort':'first selected port, rebound as loopback listener before Process.start','serviceHttpPort':'second selected port, passed via --service-http-port=','arguments':['run2','--service-config=<path>','--service-http-port=<port>','--connected-port=<port>'],'waitRace':['process exit','waitConnect','timeout'],'waitPollDelayMicroseconds':300000,'socketCallback':'sets static slot 0x4288=true; no socket reads or sender authentication in this callback','waitSuccessEnumIndex':3,'connectedFlagSlot':'0x4288','startedFlagSlot':'0x4268'},'limitations':['No complete stop/restart cleanup verified','Port release/rebind has TOCTOU window','TCP signal is not authenticated and does not independently prove useful VPN traffic','Native support-directory final absolute path not resolved or read','Other versions not established','Enum indices are preserved; human-readable names not inferred from indices']}
(out/'windows-paths-startup.json').write_text(json.dumps(report,indent=2)+'\n')
selected=[]
for part in text.split('\n# '):
    name=part.split('\n')[0]
    if name.startswith('PathUtils.') or name in ('FlutterVpnService.getAppGroupDirectory','MethodChannel.getAppGroupDirectory','PC.getAppGroupDirectory','PC._start','PC.waitConnect','PC.socketCallback'):selected.append('# '+part.strip())
(out/'windows-paths-startup-x64.txt').write_text('\n\n'.join(selected)+'\n',encoding='utf-8')
print(json.dumps({'instructionChecks':len(checks),'pathEntries':len(paths),'selectedPoolStrings':len(strings),'installedCoreExecuted':False}))
