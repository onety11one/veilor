"""Check config hook assignment, getters and conditional library discovery."""
exec(open('work/karing-feasibility/disasm-service.py',encoding='utf-8').read().split('selected=[]')[0])
import hashlib
folder=pathlib.Path('outputs/veilor/research/windows-service-contract')
document=json.loads((folder/'config-consumer-disassembly.json').read_text())
fs={f['name']:f['instructions'] for f in document['functions']};checks=[]
def check(label,value):
 if not value:raise ValueError(label)
 checks.append(label)
def at(fn,pc):return next(i for i in fs[fn] if i['pc']==pc)
lib='github.com/sagernet/sing-box/experimental/libbox.'
hook=lib+'init.0';wrapper=lib+'SentryInit';private=lib+'SentryInitPrivate'
check('Subject SHA-256',hashlib.sha256(b).hexdigest()=='023ed74fa5015aacf09d83ac7d4a80f9d48dbc0459018e8d75303d7d80d6a9ea')
check('Private callback function value',at(hook,'0x1415db2a6')['functionValue']==private)
check('Callback assignment matches wrapper read',at(hook,'0x1415db2ad')['ripAddress']==at(wrapper,'0x1415db0f3')['ripAddress'])
check('Wrapper uses callback',at(wrapper,'0x1415db102')['asm']=='call rcx')
check('Private reads service file',at(private,'0x1415db3f6')['target']=='os.ReadFile')
check('Private parses JSON',at(private,'0x1415db452')['target'].endswith('(*Parser).Parse'))
for pc,key in [('0x1415db484','core_path'),('0x1415db4ff','log_path'),('0x1415db57f','id'),('0x1415db5e1','version'),('0x1415db641','sentry_minversion')]:
 va=int(at(private,pc)['ripAddress'],16)
 check('Private JSON key '+key,b[offset(va):offset(va)+len(key)]==key.encode())
check('Minimum version comparison exists',at(private,'0x1415db716')['target']==lib+'compareVersion')
check('SDK telemetry initialization exists',at(private,'0x1415dbb91')['target']=='github.com/getsentry/sentry-go.Init')
cronet='github.com/sagernet/cronet-go/internal/cronet.'
check('Cronet locates DLL',at(cronet+'doLoadLibrary','0x140bba060')['target']==cronet+'findLibrary')
check('Cronet dynamic LoadLibrary',at(cronet+'doLoadLibrary','0x140bba078')['target']=='syscall.LoadLibrary')
va=int(at(cronet+'findLibrary','0x140bba320')['ripAddress'],16)
check('Cronet DLL basename',b[offset(va):offset(va)+13]==b'libcronet.dll')
check('Cronet checks filesystem',at(cronet+'findLibrary','0x140bba34f')['target']=='os.Stat')
observed=json.loads((folder/'local-schema-observation.json').read_text())['serviceConfigSchema']
direct=json.loads((folder/'service-field-xrefs.json').read_text())
setUp={'base_dir','work_dir','cache_dir','core_path','err_path'}
sdk={'core_path','log_path','id','version','sentry_minversion'}
manifest=[]
for row in observed:
 key=row['field'];readers=[]
 if key in setUp:readers.append('main.setUpDir')
 if key in sdk:readers.append(private)
 manifest.append({'field':key,'observedType':row['type'],'confirmedReaders':readers,
  'requirement':'nonempty string checked by setUpDir' if key=='core_path' else 'not established',
  'absenceOfReaderIsNotProofOfUnused':not bool(readers)})
check('25 observed fields retained',len(manifest)==25)
check('Nine fields have confirmed reader',sum(bool(x['confirmedReaders']) for x in manifest)==9)
result={'scope':'Observed types and confirmed readers, not a complete SDK schema; defaults unresolved',
 'fields':manifest,'checksPassed':checks,'liveCoreExecution':False}
(folder/'service-config-contract.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'staticChecksPassed':len(checks),'observedFields':len(manifest),'confirmedReaderFields':sum(bool(x['confirmedReaders']) for x in manifest)}))
