"""Offline selected code; annotated private output, allowlisted pool values only."""
import pathlib,sys,re,hashlib,json
base=pathlib.Path(__file__).resolve().parent
sys.path.insert(0,str(base/'python-deps'))
from capstone import Cs,CS_ARCH_X86,CS_MODE_64
from elftools.elf.elffile import ELFFile
blob=(base/'targets/app.so').read_bytes()
assert hashlib.sha256(blob).hexdigest()=='38c1b08f0f12c0934f3e25a2dd7c4f276c690be457a4b24377d1cea36c740882'
with (base/'targets/app.so').open('rb') as f:sections=list(ELFFile(f).iter_sections())
dump=base/'aot-pool-diagnostic/dump'
names={int(a,16):n for a,n in re.findall(r'idaapi.set_name\((0x[0-9a-f]+), "([^"]+)"\)',(dump/'ida_script/addNames.py').read_text(encoding='utf-8'))}
pool={int(a,16):v for a,v in re.findall(r'^\[pp\+(0x[0-9a-f]+)\] (.*)$',(dump/'pp.txt').read_text(encoding='utf-8'),re.M)}
allowed={'','127.0.0.1','localhost','service.json','service_core.json','run2','--service-config','--service-http-port','--connected-port','control_port','secret'}
sourceRoot=base.parents[1]/'outputs/veilor/lib/app/modules'
for filename in ['setting_manager.dart','remote_config.dart']:
    allowed.update(re.findall(r'''["']([a-z][a-z0-9_]*)["']\s*:''',(sourceRoot/filename).read_text(encoding='utf-8')))
allowed.update({'karing','Karing','1.2.25','1.2.25+2802','1.2.25.2802','data','cache','service.log','service_stderr.log'})
allowed.update({'get','http','DIRECT','profiles','__test_dir__','service_error.log','service_core.log','karingService.exe','--service-config=','--service-http-port=','--connected-port='})
def annotation(i):
    if i.mnemonic in ('call','jmp') and i.op_str.startswith('0x'):return names.get(int(i.op_str,16),'')
    m=re.search(r'\[r15 \+ (0x[0-9a-f]+)\]',i.op_str)
    if not m:return ''
    value=pool.get(int(m[1],16)+1,'')
    if value.startswith(('Field ','Code: ','Function: ','TypeArguments: ','Type: ','Stub: ')):return value
    if value.startswith('String: '):
        try:text=json.loads(value[8:])
        except json.JSONDecodeError:return 'String: [non-JSON encoding; not exported]'
        return value if text in allowed else 'String: [not exported]'
    return value if value in ('Null','true','false') else '[pool value not exported]'
cs=Cs(CS_ARCH_X86,CS_MODE_64)
lines=[]
ranges=[(0xd874fc,0x820,'VPNService._prepareConfig'),(0xd84a10,0x2b4,'PC.start'),(0xd84cc4,0x11a4,'PC._start'),(0xd87d1c,0xa4,'FlutterVpnService.prepareConfig'),(0xd84824,0x6c,'ClashApi.getSecret'),(0xd9167c,0x84,'VPNService.getTunMode'),(0xc6cc98,0x6fc,'SettingConfig.toJson'),(0xc6fa30,0x43c,'SettingConfigItemProxy.toJson'),(0xc6edd0,0x3e0,'SettingConfigItemTUN.toJson'),(0xca2580,0x788,'RemoteConfig.toJson')]
ranges.extend([(0xc70418,0x13c,'SettingConfigItemUI.toJson'),(0x10c0cd0,0x17c,'VPNService.init')])
ranges.extend([(0xa7f850,0x1b8,'PathUtils.profileDir'),(0xa7fa08,0xc8,'PathUtils.profileDirNonPortable'),(0xa856f8,0x34,'PathUtils.profileDirForPortableMode'),(0xcb1014,0x84,'PathUtils.cacheDir'),(0xd84454,0x60,'PathUtils.serviceStdErrorFilePath'),(0xd87f24,0x60,'PathUtils.serviceLogFilePath'),(0xd87f84,0x60,'PathUtils.serviceCoreConfigFilePath'),(0xd87fe4,0x70,'PathUtils.appAssetsDir'),(0xd88054,0x60,'PathUtils.serviceConfigFilePath'),(0xdb50e8,0x34,'PathUtils.serviceExePath'),(0xd85ebc,0xd0,'PC.waitConnect'),(0xd86b5c,0x60,'PC.socketCallback')])
ranges.extend([(0xa8572c,0x48,'PathUtils.exeDir'),(0xa7fad0,0x74,'FlutterVpnService.getAppGroupDirectory'),(0xa7fbf4,0x50,'PC.getAppGroupDirectory')])
ranges.append((0xa7fb60,0x94,'MethodChannel.getAppGroupDirectory'))
ranges.extend([(0xc48b44,0x258,'PC.stop'),(0xc491f0,0x260,'PC._stop'),(0xc49450,0x1c4,'PC._killProcesses'),(0xd86bbc,0xd8,'PC._stopWithoutUpdateState'),(0xd86264,0x140,'PC.exitCallback'),(0x10c12b8,0x2d8,'VPNService.stateCallback'),(0xc48d9c,0x64,'PC._currentState'),(0xc6aafc,0x7c,'PC.cleanSystemProxy')])
ranges.extend([(0xc49028,0x74,'FlutterVpnWait.waitTimeout'),(0xc490a8,0x78,'FlutterVpnWait.wait'),(0xc4ac50,0xc0,'FlutterVpnWait.waitProcessExit'),(0xc4af14,0x628,'HttpRequest.request')])
ranges.extend([(0x13b877c,0x58,'FlutterVpnServiceState.enumToString'),(0x13b87d4,0x58,'VpnServiceWaitType.enumToString')])
ranges.extend([(0xc50d80,0x190,'HttpClient.open'),(0xc50d18,0x68,'HttpRequest.waitDone'),(0xc50cac,0x6c,'HttpUtils.waitResponseTimeout'),(0xca97a8,0x54,'MethodChannel.currentState'),(0xca97fc,0x6c,'PC.currentState')])
ranges.append((0xc6a6e0,0x8,'HttpRequest.proxySelector'))
for address,size,name in ranges:
    section=next(s for s in sections if s['sh_type']!='SHT_NOBITS' and s['sh_addr']<=address and address+size<=s['sh_addr']+s['sh_size'])
    offset=section['sh_offset']+address-section['sh_addr'];instructions=list(cs.disasm(blob[offset:offset+size],address))
    assert sum(i.size for i in instructions)==size
    lines.append('\n# '+name)
    for i in instructions:
        extra=annotation(i)
        lines.append(f'{i.address:#x}: {i.mnemonic} {i.op_str}'+(' ; '+extra if extra else ''))
(base/'config-callers-annotated.txt').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(json.dumps({'functions':len(ranges),'output':'work/karing-feasibility/config-callers-annotated.txt'}))
