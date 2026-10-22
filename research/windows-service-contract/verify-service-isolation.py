"""Verify offline evidence only; never executes or contacts the subject."""
exec(open('work/karing-feasibility/disasm-service.py',encoding='utf-8').read().split('selected=[]')[0])
import hashlib
folder=pathlib.Path('outputs/veilor/research/windows-service-contract')
document=json.loads((folder/'isolation-disassembly.json').read_text())
functions={f['name']:f for f in document['functions']}
checks=[]
def check(label,condition):
 if not condition:raise ValueError(label)
 checks.append(label)
def instructions(name):return functions[name]['instructions']
def calls(name):return [i.get('target','') for i in instructions(name) if i['asm'].startswith('call ')]
def at(name,pc):return next(i for i in instructions(name) if i['pc']==pc)
check('Subject SHA-256',hashlib.sha256(b).hexdigest()=='023ed74fa5015aacf09d83ac7d4a80f9d48dbc0459018e8d75303d7d80d6a9ea')
singleton='main.makeProcessSingleton'
check('Own PID queried','syscall.getCurrentProcessId' in calls(singleton))
check('Toolhelp process enumeration',all(any(t.endswith(s) for t in calls(singleton)) for s in ['CreateToolhelp32Snapshot','Process32First','Process32Next']))
check('Two basename calls',calls(singleton).count('internal/filepathlite.Base')==2)
check('Case-insensitive comparison','strings.EqualFold' in calls(singleton))
check('Termination invoked','main.terminateProcess' in calls(singleton))
terminate='main.terminateProcess'
check('Terminate attempted',any(t.endswith('.TerminateWithContext') for t in calls(terminate)))
check('Kill fallback',any(t.endswith('.KillWithContext') for t in calls(terminate)))
check('Successful terminate skips kill',at(terminate,'0x141607df0')['asm']=='je 0x141607f55')
check('No full-path query in termination helper',not any('ExeWithContext' in t or 'ResolvedExePath' in t for t in calls(terminate)))
setup='main.setUpDir'
check('Service JSON parsed',any(t.endswith('(*Parser).Parse') for t in calls(setup)))
for pc,key in [('0x1415f8487','core_path'),('0x1415f84de','err_path'),('0x1415f8604','base_dir'),('0x1415f865e','work_dir'),('0x1415f86bb','cache_dir')]:
 va=int(at(setup,pc)['ripAddress'],16)
 check('JSON key '+key,b[offset(va):offset(va)+len(key)]==key.encode())
check('Empty core_path branch',at(setup,'0x1415f852d')['asm']=='je 0x1415f87de')
va=int(at(setup,'0x1415f87f7')['ripAddress'],16)
check('Explicit core_path error',b[offset(va):offset(va)+21]==b' : core_path is empty')
check('Stderr configured',any(t.endswith('libbox.StderrRedirect') for t in calls(setup)))
check('SDK setup invoked',any(t.endswith('libbox.Setup') for t in calls(setup)))
check('Setup creates directories',calls('github.com/sagernet/sing-box/experimental/libbox.Setup').count('os.MkdirAll')==2)
check('Stderr opens file','os.OpenFile' in calls('github.com/sagernet/sing-box/experimental/libbox.StderrRedirect'))
result={'scope':'Offline instruction assertions for this binary version; not runtime compatibility tests',
 'subjectSha256':hashlib.sha256(b).hexdigest(),'checksPassed':checks,
 'launchPerformed':False,'sameFilenameDifferentDirectoryIsIsolated':False,
 'explicitlyRequiredAtSetUpDir':['core_path'],
 'otherObservedPathKeys':['err_path','base_dir','work_dir','cache_dir'],
 'completeServiceConfigSchemaRecovered':False}
(folder/'isolation-verified.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'staticChecksPassed':len(checks),'launchPerformed':False}))
