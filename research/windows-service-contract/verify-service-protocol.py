exec(open('work/karing-feasibility/disasm-service.py',encoding='utf-8').read().split('selected=[]')[0])
folder=pathlib.Path('outputs/veilor/research/windows-service-contract')
dis=json.loads((folder/'service-disassembly.json').read_text())
functions={f['name']:f for f in dis['functions']}
bindings=json.loads((folder/'service-static-bindings.json').read_text())
checks=[]
def check(name,value):
 if not value:raise ValueError(name)
 checks.append(name)
check('Go function count',len(funcs)==66932)
check('runtime.text base',funcs[0]['address']=='0x1400013e0')
command=next(c for c in bindings['commands'] if c['label']=='run2')
check('Cobra run2 command Use',command['use']=='run2')
check('run2 callback',any(c['function']=='main.init.func27' for c in command['callbacks']))
check('run2 callback calls runService',any(i.get('target')=='main.runService' for i in functions['main.init.func27']['instructions']))
for target in ['main.createService','main.createHttpServer','main.destroyAll']:
 check('runService calls '+target,any(i.get('target')==target for i in functions['main.runService']['instructions']))
check('Router interface slot 0x30 is GET',any(s['offset']=='0x30' and s['function'].endswith('(*Mux).Get') for s in bindings['routerSlots']))
routes=[]
http=functions['main.createHttpServer']['instructions']
for path,number in [('/reload',1),('/stop',2),('/clashiApiConnections',3)]:
 route=next(i for i in http if i.get('adjacentLengthLiteral',{}).get('value')==path)
 check('route literal '+path,route['adjacentLengthLiteral']['length']==len(path))
 fn=functions[f'main.createHttpServer.func{number}']
 pathInstruction=next(i for i in fn['instructions'] if i['asm'].startswith('lea rbx, [rip'))
 check('subpath slash '+path,b[offset(int(pathInstruction['ripAddress'],16))]==ord('/'))
 check('GET interface invocation '+path,any(i['asm']=='mov rdx, qword ptr [rax + 0x30]' for i in fn['instructions']))
 check('handler callback '+path,any(i.get('dataFunctionPointer')==f'main.createHttpServer.func{number}.1' for i in fn['instructions']))
 routes.append({'method':'GET','group':path,'subpath':'/','handler':f'main.createHttpServer.func{number}.1','registrationPc':route['pc']})
check('reload calls restartService',any(i.get('target')=='main.restartService' for i in functions['main.createHttpServer.func1.1']['instructions']))
check('stop sends channel event',any(i.get('target')=='runtime.chansend1' for i in functions['main.createHttpServer.func2.1']['instructions']))
check('connections invokes BoxService.GetConnections',any(i.get('target','').endswith('(*BoxService).GetConnections') for i in functions['main.createHttpServer.func3.1']['instructions']))
for flag in ['service-config','service-http-port','connected-port']:
 check('persistent flag '+flag,any(i.get('literalPreview','').startswith(flag) for i in functions['main.init.1']['instructions']))
connections=functions['main.createHttpServer.func3.1']['instructions']
check('includeConnections query key',any(i.get('literalPreview','').startswith('includeConnections') for i in connections))
check('true boolean comparison',any(i['asm']=='cmp dword ptr [rcx], 0x65757274' for i in connections))
result={'scope':'Static checked bindings only; no request sent, argv template is not observed Dart argv',
 'launchCommand':'run2','longFlags':['service-config','service-http-port','connected-port'],
 'listenAddressFormat':'127.0.0.1:%d','routes':routes,
 'query':{'connections':'includeConnections','booleanTrueLiteral':'true'},
 'checksPassed':checks,'limitations':['Slash/no-slash HTTP normalization not exercised.','Port allocation, credentials and full event mapping remain unverified.']}
(folder/'service-protocol-verified.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'staticChecksPassed':len(checks),'routes':routes},indent=2))
