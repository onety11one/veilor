"""Metadata/source assertions only. Does not claim to recover Dart methods."""
import pathlib,json,struct,hashlib,re,sys,shutil,subprocess
sys.path.insert(0,str(pathlib.Path('work/karing-feasibility/python-deps').resolve()))
sys.path.insert(0,str(pathlib.Path('work/toolchains/blutter-windows').resolve()))
from extract_dart_info import extract_snapshot_hash_flags,extract_libflutter_info_pe
folder=pathlib.Path('outputs/veilor/research/windows-service-contract')
inventory=json.loads((folder/'dart-aot-inventory.json').read_text())
subject=pathlib.Path('work/karing-feasibility/targets/app.so');b=subject.read_bytes();checks=[]
def check(label,value):
 if not value:raise ValueError(label)
 checks.append(label)
check('Snapshot SHA-256 pinned',hashlib.sha256(b).hexdigest()=='38c1b08f0f12c0934f3e25a2dd7c4f276c690be457a4b24377d1cea36c740882')
check('ELF64 little endian',b[:6]==b'\x7fELF\x02\x01')
check('ELF EM_X86_64',inventory['machine']==62)
check('Two snapshot data headers',len(inventory['snapshotHeaders'])==2)
for h in inventory['snapshotHeaders']:
 off=h['offset'];check(h['symbol']+' magic',struct.unpack_from('<I',b,off)[0]==0xdcdcf5f5)
 check(h['symbol']+' FullAOT kind',struct.unpack_from('<q',b,off+12)[0]==3)
check('Both VM/isolate hashes match',len({h['hashCandidate'] for h in inventory['snapshotHeaders']})==1)
hashValue,flags=extract_snapshot_hash_flags(str(subject))
check('Independent extractor agrees on snapshot hash',hashValue==inventory['snapshotHeaders'][0]['hashCandidate'])
check('Independent extractor x64 Windows no compressed pointers',all(f in flags for f in ['x64','windows','no-compressed-pointers']))
_,version,arch,target=extract_libflutter_info_pe('C:/Program Files/Karing/flutter_windows.dll')
check('Engine reports Dart 3.12.2 Windows x64',(version,arch,target)==('3.12.2','x64','windows'))
for text in ['VpnServiceConfig','FlutterVpnService','control_port','secret','service-config','service-http-port','connected-port','prepareConfig','proxy_manager.dart']:
 check('Allowlisted AOT name '+text,any(r['text']==text and r['offsets'] for r in inventory['allowlistedStrings']))
setting=pathlib.Path('work/karing-feasibility/matching-source/lib/app/modules/setting_manager.dart').read_text(encoding='utf-8')
check('Matching source default port 3057','controlPortDefault = 3057;' in setting)
check('Matching source missing control_port becomes zero','controlPort = map["control_port"] ?? 0;' in setting)
check('Matching source zero reset to default',bool(re.search(r'if \(controlPort == 0\)\s*\{\s*controlPort = controlPortDefault;',setting)))
archive=pathlib.Path('outputs/veilor/research/karing-vpn-service-reference/lib/app')
clash=(archive/'utils/clash_api.dart').read_text(encoding='utf-8')
wrapper=(archive/'local_services/vpn_service.dart').read_text(encoding='utf-8')
builder=(archive/'utils/singbox_config_builder.dart').read_text(encoding='utf-8')
check('Historical getSecret derives substring from Did.getDid',bool(re.search(r'getSecret\(\).*?Did.getDid\(\).*?substring\(8, 24\)',clash,re.S)))
check('Historical service config receives API secret','config.secret = await ClashApi.getSecret();' in wrapper)
check('Historical builder receives same secret argument','exp.clash_api.secret = secret;' in builder)
check('Historical core export uses getSecret when empty',bool(re.search(r'if \(secret.isEmpty\)\s*\{\s*secret = await ClashApi.getSecret\(\);',wrapper)))
check('No snapshot dump directory created',not pathlib.Path('work/karing-feasibility/aot-dump-not-created').exists())
commit=subprocess.check_output(['git','-C','work/toolchains/blutter-windows','rev-parse','HEAD'],text=True).strip()
result={'scope':'AOT metadata plus version-labelled source facts, not method decompilation',
 'snapshotSha256':hashlib.sha256(b).hexdigest(),'dartVersion':version,'snapshotHash':hashValue,'target':target,'arch':arch,
 'compressedPointers':False,'blutterSourceCommit':commit,'analysisMode':'detect-only',
 'toolchainDetected':{name:bool(shutil.which(name)) for name in ['cl.exe','clang-cl.exe','cmake.exe','ninja.exe']},
 'sourceFacts':{'controlPortDefault':{'value':3057,'commit':'0c320dc182d095ec0d483f852169421e749c2bac'},
 'secretDerivation':{'expression':'(await Did.getDid()).substring(8,24)','commit':'e3c19f1eb1225dbd48a4862f0983b82d0af8de69','currentAotVerified':False}},
 'checksPassed':checks,'snapshotLoadedIntoVm':False,'karingExecuted':False,
 'unresolved':['AOT methods and serializer defaults not decoded.','Current native event enum/wire not recovered.','Matching 3.12.2 analyzer needs a build toolchain and compatibility verification.']}
(folder/'dart-aot-verified.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'checksPassed':len(checks),'mode':'detect-only','methodRecovery':False,'toolchainDetected':result['toolchainDetected']}))
