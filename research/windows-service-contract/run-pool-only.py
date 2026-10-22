"""Analyze the pinned saved snapshot, never the installed Karing executables."""
import pathlib, hashlib, subprocess, os, json, sys
base=pathlib.Path(__file__).resolve().parent
root=base.parents[2]
target=root/'work/karing-feasibility/targets/app.so'
expected='38c1b08f0f12c0934f3e25a2dd7c4f276c690be457a4b24377d1cea36c740882'
assert hashlib.sha256(target.read_bytes()).hexdigest()==expected
subprocess.run([sys.executable,str(base/'verify-dart-source.py')],check=True)
exe=base.parent/'blutter-windows/bin/blutter_dartvm3.12.2_windows_x64_no-compressed-ptrs_no-analysis.exe'
run=root/('work/karing-feasibility/'+(sys.argv[1] if len(sys.argv)>1 else 'aot-pool-run'))
run.mkdir(exist_ok=False)
env=os.environ.copy()
for key in ('APPDATA','LOCALAPPDATA','TEMP','TMP','USERPROFILE'):
    folder=run/key.lower();folder.mkdir();env[key]=str(folder)
with (run/'analyzer.log').open('w',encoding='utf-8') as log:
    result=subprocess.run([str(exe),'-i',str(target),'-o',str(run/'dump')],cwd=run,env=env,stdout=log,stderr=subprocess.STDOUT)
files=[{'path':str(p.relative_to(run)), 'bytes':p.stat().st_size} for p in run.rglob('*') if p.is_file()]
(run/'receipt.json').write_text(json.dumps({'returnCode':result.returncode,'inputSha256':expected,'analyzerSha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'files':files,'installedExecutablesStarted':False},indent=2))
print(json.dumps({'returnCode':result.returncode,'fileCount':len(files),'log':str(run/'analyzer.log')}))
