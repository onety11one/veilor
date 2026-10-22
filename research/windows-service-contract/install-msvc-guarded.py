"""Run pinned downloader with user-approved terms and confined cleanup."""
import pathlib,sys,shutil,hashlib,json,datetime
base=pathlib.Path(__file__).resolve().parent
source=base/'portable-msvc.py';plan=json.loads((base/'msvc-plan.json').read_text())
if pathlib.Path.cwd().resolve()!=base:raise SystemExit('Unexpected working directory')
if hashlib.sha256(source.read_bytes()).hexdigest()!=plan['downloaderSha256']:raise SystemExit('Downloader changed')
roots=[(base/name).resolve() for name in ['msvc','downloads']]
def check(path):
 target=pathlib.Path(path).resolve()
 if not any(target!=root and target.is_relative_to(root) for root in roots):
  raise RuntimeError('Refusing cleanup/move outside workspace toolchain children')
 return target
originalRemove=shutil.rmtree;originalReplace=pathlib.Path.replace;originalUnlink=pathlib.Path.unlink
def remove(path,*args,**kwargs):check(path);return originalRemove(path,*args,**kwargs)
def replace(self,target):check(self);check(target);return originalReplace(self,target)
def unlink(self,*args,**kwargs):check(self);return originalUnlink(self,*args,**kwargs)
shutil.rmtree=remove;pathlib.Path.replace=replace;pathlib.Path.unlink=unlink
receipt={'accepted':True,'authorization':'User explicitly approved required licenses and continuation in this task',
 'licenseUrl':plan['licenseUrl'],'msvcVersion':plan['msvcVersion'],'sdkFamily':plan['windowsSdkFamily'],
 'timestampUtc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'cleanupRoots':[str(r) for r in roots]}
(base/'license-acceptance.json').write_text(json.dumps(receipt,indent=2)+'\n')
sys.argv=[str(source),'--vs','2022','--msvc-version','14.44','--sdk-version','26100','--host','x64','--target','x64','--accept-license']
exec(compile(source.read_text(encoding='utf-8'),str(source),'exec'),{'__name__':'__main__','__file__':str(source)})
