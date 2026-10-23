"""Verify pinned offline disassembly, publish a selected preparation contract."""
import pathlib,runpy,re,json,hashlib
base=pathlib.Path(__file__).resolve().parent
ctx=runpy.run_path(str(base/'inspect-config-callers.py'))
out=base.parents[1]/'outputs/veilor/research/windows-service-contract'
text=(base/'config-callers-annotated.txt').read_text(encoding='utf-8')
instructions={int(a,16):line for a,line in re.findall(r'^(0x[0-9a-f]+): (.*)$',text,re.M)}
checks=[]
def expect(addr,code):
    assert instructions[addr].split(' ; ')[0]==code,(hex(addr),code)
    checks.append({'address':hex(addr),'instruction':code})
def keyload(key,offset,section):
    part=text.split('# '+section+'\n')[1].split('\n# ')[0]
    lines=part.splitlines()
    index=next(i for i,line in enumerate(lines) if '; String: '+json.dumps(key) in line)
    assert any(re.search(r'(?:rax|rdx), qword ptr \[(?:rsi|rcx) \+ '+hex(offset-1)+r'\]',line) for line in lines[index+1:index+7]),key
    m=re.search(r'\[r15 \+ (0x[0-9a-f]+)\]',lines[index]);pp=int(m[1],16)+1
    repeat=(base/'aot-pool-repeat/dump/pp.txt').read_text(encoding='utf-8')
    assert f'[pp+{hex(pp)}] String: '+json.dumps(key) in repeat
    return {'serializer':section,'keyInstruction':lines[index].split(':')[0],'sourceOffset':hex(offset),'poolOffset':hex(pp)}
sources={
 'control_port':('settings.proxy.control_port',0xd87756,'mov qword ptr [rdi + 7], rdx'),
 'base_dir':('await PathUtils.profileDir()',0xd8777a,'mov qword ptr [rdi + 0xf], rax'),
 'work_dir':('PathUtils.appAssetsDir()',0xd877a1,'mov qword ptr [rdi + 0x17], rax'),
 'cache_dir':('await PathUtils.cacheDir()',0xd877dc,'mov qword ptr [rdi + 0x1f], rax'),
 'core_path':('await PathUtils.serviceCoreConfigFilePath()',0xd87817,'mov qword ptr [rdi + 0x27], rax'),
 'log_path':('await PathUtils.serviceLogFilePath()',0xd87852,'mov qword ptr [rdi + 0x2f], rax'),
 'err_path':('await PathUtils.serviceStdErrorFilePath()',0xd8788d,'mov qword ptr [rdi + 0x37], rax'),
 'id':('await Did.getDid(); value not read or computed',0xd878c8,'mov qword ptr [rdi + 0x3f], rax'),
 'version':('compiled public version 1.2.25.2802',0xd878ea,'mov qword ptr [rdi + 0x47], rax'),
 'name':('compiled public name Karing',0xd878f5,'mov qword ptr [rdi + 0x4f], rax'),
 'secret':('await ClashApi.getSecret(); value not read or computed',0xd87919,'mov qword ptr [rdi + 0x57], rax'),
 'install_refer':('await InstallReferrerUtils.getString()',0xd8793b,'mov qword ptr [rdi + 0x5f], rax'),
 'prepare':('await VPNService.getTunMode(); settings.tun.enable AND cached isRunAsAdmin result on Windows',0xd8795d,'mov qword ptr [rdi + 0x67], rax'),
 'wake_lock':('settings.ui.wake_lock',0xd879f7,'mov qword ptr [rdi + 0x6f], rdx'),
 'auto_connect_at_boot':('settings.auto_connect_at_boot',0xd87a02,'mov qword ptr [rdi + 0x77], rax'),
 'allowed_sender_packages':('settings.allowed_sender_packages; direct reference assignment',0xd87a0d,'mov qword ptr [rdi + 0x7f], rax'),
 'disconnect_after_sleep_seconds':('settings Duration at root 0xf8 converted to seconds; null becomes 0',0xd879e8,'mov qword ptr [rdi + 0xbf], rax'),
 'sentry_minversion':('remote_config.sentry_min_version, then conditional version/build-age policy; full policy not yet verified',0xd87aab,'mov qword ptr [rdi + 0xc7], rax')}
for index,key in enumerate(['include_all_networks','exclude_local_networks','exclude_cellular_services','exclude_apns','exclude_device_communication','enforce_routes','auto_route_use_sub_ranges_by_default']):
    stores=[0xd87a30,0xd87a3b,0xd87a46,0xd87a51,0xd87a5c,0xd87a67,0xd87a72]
    sources[key]=('settings.tun.'+key,stores[index],f'mov qword ptr [rdi + {hex(0x87+index*8)}], rdx')
defaults=json.loads((out/'vpn-config-recovered.json').read_text())
assert set(sources)=={f['key'] for f in defaults['fields']}
rows=[]
for field in defaults['fields']:
    source,address,code=sources[field['key']];expect(address,code)
    rows.append({'key':field['key'],'objectOffset':field['objectOffset'],'source':source,'storeInstruction':hex(address)})
keyEvidence=[]
for section,items in [('SettingConfig.toJson',{'proxy':0x40,'tun':0x50,'ui':0x28,'auto_connect_at_boot':0xb0,'allowed_sender_packages':0xb8,'disconnect_after_sleep_seconds':0xf8}),('SettingConfigItemProxy.toJson',{'control_port':0x50}),('SettingConfigItemUI.toJson',{'wake_lock':0x28}),('SettingConfigItemTUN.toJson',dict(zip(['include_all_networks','exclude_local_networks','exclude_cellular_services','exclude_apns','exclude_device_communication','enforce_routes','auto_route_use_sub_ranges_by_default'],range(0x50,0x88,8)))),('RemoteConfig.toJson',{'sentry_min_version':0x20})]:
    for key,offset in items.items():keyEvidence.append({'key':key,**keyload(key,offset,section)})
for address,code in [(0xd87747,'mov rcx, qword ptr [rax + 0x3f]'),(0xd8774b,'mov rdx, qword ptr [rcx + 0x4f]'),(0xd878f9,'call 0xd84824'),(0xd8484d,'call 0xca1c04'),(0xd84863,'mov qword ptr [rsp], 0x30'),(0xd8486e,'mov esi, 8'),(0xd8487a,'call 0xa5b760'),(0xd916c9,'mov rcx, qword ptr [rax + 0x4f]'),(0xd916cd,'mov rdx, qword ptr [rcx + 7]'),(0xd916da,'mov rax, qword ptr [r14 + 0x98]'),(0xd916ea,'mov rax, qword ptr [rax + 0x3480]'),(0x10c0d13,'call 0x10c113c'),(0x10c0d30,'mov qword ptr [rax + 0x3480], rdx'),(0xd87c34,'call 0xd87d1c'),(0xd87d76,'mov qword ptr [rcx + 0x4248], rdx'),(0xd87d85,'mov qword ptr [rcx + 0x4258], rdx'),(0xd87d94,'mov qword ptr [rcx + 0x4250], rdx'),(0xd87da3,'mov qword ptr [rcx + 0x4270], rdx'),(0xd87c8a,'call 0xff65e4'),(0xd87cb2,'call 0xc95810'),(0xd87be6,'mov qword ptr [rdi + 0xc7], rax')]:expect(address,code)
for address,name in [(0xd8775a,'profileDir'),(0xd87795,'appAssetsDir'),(0xd877bc,'cacheDir'),(0xd877f7,'serviceCoreConfigFilePath'),(0xd87832,'serviceLogFilePath'),(0xd8786d,'serviceStdErrorFilePath'),(0xd878a8,'getDid'),(0xd8770c,'getString'),(0xd876cc,'getTunMode')]:
    assert '::'+name+'_' in instructions[address]
assert ctx['pool'][0x97a0]=='String: "1.2.25.2802"'
assert ctx['pool'][0xa6d8]=='String: "Karing"'
report={'scope':'Windows Karing 1.2.25+2802 preparation; not production launch config','inputSha256':hashlib.sha256(ctx['blob']).hexdigest(),'fields':rows,'sourceFieldEvidence':keyEvidence,'instructionChecks':checks,'secretAlgorithm':{'currentAotVerified':True,'description':'await Did.getDid(), substring(8,24); optional end argument Smi 0x30 = 24','actualValueComputed':False},'platformStorage':{'0x4248':'config object','0x4258':'service exe path','0x4250':'service config file path','0x4270':'excluded port list'},'unresolved':['sentry version/build-age policy full semantics','PathUtils full path resolution and permissions','port reservations and readiness authentication','core JSON and complete lifecycle','compatibility with 1.2.26+2908']}
(out/'vpn-config-preparation.json').write_text(json.dumps(report,indent=2)+'\n')
selected=[]
for part in text.split('\n# '):
    if part.split('\n')[0] in ('VPNService._prepareConfig','FlutterVpnService.prepareConfig','ClashApi.getSecret','VPNService.getTunMode','VPNService.init'):selected.append('# '+part.strip())
(out/'vpn-config-preparation-x64.txt').write_text('\n\n'.join(selected)+'\n',encoding='utf-8')
print(json.dumps({'fieldAssignments':len(rows),'sourceFieldsChecked':len(keyEvidence),'instructionChecks':len(checks),'actualSecretComputed':False}))
