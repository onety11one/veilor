"""Static HTTP checks plus allowlisted enum extraction receipt validation."""
import pathlib,runpy,re,json,csv,hashlib
base=pathlib.Path(__file__).resolve().parent
ctx=runpy.run_path(str(base/'inspect-config-callers.py'))
text=(base/'config-callers-annotated.txt').read_text(encoding='utf-8')
ins={int(a,16):line for a,line in re.findall(r'^(0x[0-9a-f]+): (.*)$',text,re.M)}
out=base.parents[1]/'outputs/veilor/research/windows-service-contract'
checks=[]
def check(addr,code):
    assert ins[addr].split(' ; ')[0]==code,(hex(addr),code)
    checks.append({'address':hex(addr),'instruction':code})
for address,code in [(0xc4b002,'call 0xc68f40'),(0xc4b09a,'call 0xc50d80'),(0xc50ea5,'mov r11, qword ptr [r15 + 0x16ff]'),(0xc50eb1,'mov r11, qword ptr [r15 + 0x30177]'),(0xc50ee5,'mov rsi, qword ptr [r15 + 0xb61f]'),(0xc50eec,'call 0xc50f10'),(0xc4b0bd,'call 0xc50d18'),(0xc50d49,'call 0xdd707c'),(0xc4b0e4,'call 0xc50cac'),(0xc50ceb,'call 0xa77f48'),(0xc4b15b,'call 0xc48e00'),(0xc4b221,'cmp rdx, 0x190'),(0xc4b2fe,'call 0x10211b4'),(0xc4b30d,'call 0xc4b7b8'),(0xc4b377,'mov qword ptr [rcx + 0xf], rax'),(0xc4b4d4,'call 0xc4bb40'),(0xc6a6e0,'mov rax, qword ptr [r15 + 0xc3c7]'),(0xca97d5,'call 0xca97fc'),(0xca9829,'mov rax, qword ptr [rax + 0x4290]'),(0xca9842,'call 0xc48d9c'),(0xc48ddd,'mov rax, qword ptr [r15 + 0xd2ff]'),(0xc48de9,'mov rax, qword ptr [r15 + 0xd317]'),(0xc48bc0,'mov r11, qword ptr [r15 + 0x2fc5f]'),(0xd84a3d,'mov rdx, qword ptr [r15 + 0x3057f]'),(0xd84c58,'mov r11, qword ptr [r15 + 0xd2ff]'),(0xc48ce5,'mov r11, qword ptr [r15 + 0xd317]')]:check(address,code)
repeat=(base/'aot-pool-repeat/dump/pp.txt').read_text(encoding='utf-8')
for offset,value in [(0x1700,'http'),(0x30178,'127.0.0.1'),(0xb620,'get'),(0xc3c8,'DIRECT')]:
    expected='String: '+json.dumps(value)
    assert ctx['pool'][offset]==expected and f'[pp+{hex(offset)}] '+expected in repeat
# Blutter uses C++ escaping: \? represents a single question mark, not JSON.
assert ctx['pool'][0x1a20]=='String: "\\?"'
enumFile=base/'aot-enums-first/dump/pp.txt.vpn-enums.tsv'
rows=list(csv.DictReader(enumFile.read_text().splitlines(),delimiter='\t'))
expected={8311:{0:'invalid',1:'disconnected',2:'connecting',3:'connected',4:'reasserting',5:'disconnecting'},8310:{0:'processExit',1:'timeout',2:'err',3:'done'}}
enumRows=[]
for row in rows:
    cid=int(row['classId']);index=int(row['index']);assert expected[cid][index]==row['name']
    # First successful exporter used tagged-pointer displacement, normalize +1.
    offset=int(row['poolOffset'],16)+1
    assert ctx['pool'][offset].startswith('Obj!'+('FlutterVpnServiceState' if cid==8311 else 'VpnServiceWaitType'))
    enumRows.append({'poolOffset':hex(offset),'classId':cid,'index':index,'name':row['name']})
assert len(enumRows)==10 and len({(r['classId'],r['index']) for r in enumRows})==10
enumRows.sort(key=lambda r:(r['classId'],r['index']))
runs=[]
for folder in ['aot-enums-first','aot-enums-verified','aot-enums-repeat']:
    receipt=json.loads((base/folder/'receipt.json').read_text())
    runs.append({'run':folder,'returnCode':receipt['returnCode'],'analyzerSha256':receipt['analyzerSha256'],'inputSha256':receipt['inputSha256']})
assert runs[0]['returnCode']==0
report={'scope':'Karing 1.2.25+2802 HTTP static checks; enum names from one successful isolated VM load','inputSha256':hashlib.sha256(ctx['blob']).hexdigest(),'instructionChecks':checks,'http':{'method':'get','scheme':'http','host':'127.0.0.1','port':'caller-supplied service HTTP port','pathConstruction':'action + question mark, then SDK HttpClient.open normalization','syntheticStopUri':'http://127.0.0.1:12345/stop','proxySelector':'DIRECT','statusRequired':200,'body':'UTF-8 text joined and returned, no JSON decode at this layer','deadlineLimitation':'response-close race is after await open; body join has no explicit timer in inspected range','stopCallerConsumesBody':False,'bearerHeader':'no explicit setup identified in inspected path; do not confuse with Clash API'},'enums':enumRows,'enumRuns':runs,'limitations':['Two later loads crashed with 0xC0000005 at/after Dart_CreateIsolateGroup; VM stability unresolved','Enum map has one successful extraction, not two repeatable runtime extractions','No live HTTP/redirect/auth/network validation','No complete current-version lifecycle proof','invalid/reasserting names recovered, their transitions not traced']}
(out/'windows-http-state.json').write_text(json.dumps(report,indent=2)+'\n')
selected=[]
for part in text.split('\n# '):
    if part.split('\n')[0] in ('HttpRequest.request','HttpClient.open','HttpRequest.waitDone','HttpUtils.waitResponseTimeout','HttpRequest.proxySelector','MethodChannel.currentState','PC.currentState','FlutterVpnServiceState.enumToString','VpnServiceWaitType.enumToString'):selected.append('# '+part.strip())
(out/'windows-http-state-x64.txt').write_text('\n\n'.join(selected)+'\n',encoding='utf-8')
print(json.dumps({'instructionChecks':len(checks),'enumValues':len(enumRows),'successfulEnumExtractions':1,'failedLaterLoads':2,'httpRequestsSent':False}))
