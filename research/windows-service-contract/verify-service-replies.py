"""Offline verification of JSON assignments, not live service requests."""
exec(open('work/karing-feasibility/disasm-service.py',encoding='utf-8').read().split('selected=[]')[0])
import hashlib
folder=pathlib.Path('outputs/veilor/research/windows-service-contract')
dis=json.loads((folder/'service-disassembly.json').read_text())
fs={f['name']:f['instructions'] for f in dis['functions']}
checks=[]
def check(label,value):
 if not value:raise ValueError(label)
 checks.append(label)
def at(fn,pc):return next(i for i in fs[fn] if i['pc']==pc)
def asm(fn,pc,value):check(pc+' '+value,at(fn,pc)['asm']==value)
def literal(fn,pc,value):
 va=int(at(fn,pc)['ripAddress'],16)
 check(pc+' literal '+value,b[offset(va):offset(va)+len(value)]==value.encode())
r='main.createHttpServer.func1.1';s='main.createHttpServer.func2.1';later='main.createHttpServer.func1.1.1'
check('Subject hash',hashlib.sha256(b).hexdigest()=='023ed74fa5015aacf09d83ac7d4a80f9d48dbc0459018e8d75303d7d80d6a9ea')
check('Reload invokes restart',at(r,'0x141608241')['target']=='main.restartService')
asm(r,'0x141608246','test rbx, rbx');asm(r,'0x141608249','je 0x14160835d')
literal(r,'0x141608296','err');asm(r,'0x14160829d','mov edi, 3')
check('Error converted to string',at(r,'0x141608280')['target']=='runtime.convTstring')
literal(r,'0x1416082e7','extra');asm(r,'0x1416082ee','mov edi, 5')
literal(r,'0x14160836d','err');asm(r,'0x141608385','mov qword ptr [rax], 0');asm(r,'0x1416083a1','mov qword ptr [rax + 8], 0')
literal(r,'0x1416083b5','extra');asm(r,'0x1416083c6','mov qword ptr [rax], 0');asm(r,'0x1416083e2','mov qword ptr [rax + 8], 0')
literal(s,'0x14160852d','err');asm(s,'0x141608545','mov qword ptr [rax], 0');asm(s,'0x141608561','mov qword ptr [rax + 8], 0')
check('Both reload branches and stop render JSON',all(at(fn,pc)['target']=='github.com/go-chi/render.JSON' for fn,pc in [(r,'0x141608346'),(r,'0x141608405'),(s,'0x141608584')]))
check('Reload failure schedules goroutine',at(r,'0x141608352')['target']=='runtime.newproc')
va=int(at(r,'0x14160834b')['ripAddress'],16)
check('Goroutine function value resolves to delayed handler',struct.unpack_from('<Q',b,offset(va))[0]==int(next(f['address'] for f in dis['functions'] if f['name']==later),16))
asm(later,'0x14160844e','mov eax, 0x3b9aca00')
check('Delayed handler sleeps',at(later,'0x141608453')['target']=='time.Sleep')
check('Delayed handler sends channel event',at(later,'0x141608466')['target']=='runtime.chansend1')
check('Same channel as stop',at(later,'0x141608458')['ripAddress']==at(s,'0x141608509')['ripAddress'])
result={'scope':'Static map assignments in Karing 1.2.25+2802; no HTTP execution',
 'subjectSha256':hashlib.sha256(b).hexdigest(),
 'reloadSuccess':{'err':None,'extra':None},'stopReply':{'err':None},
 'reloadError':{'err':'error.Error() string','extra':'returned auxiliary value; schema unresolved'},
 'reloadErrorDelayedAction':{'sleepNanoseconds':1000000000,'channel':'same as stop handler'},
 'checksPassed':checks,'runtimeStatusCodeAndDeliveryVerified':False}
(folder/'reply-static-verified.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'staticChecksPassed':len(checks),'liveRequests':0}))
