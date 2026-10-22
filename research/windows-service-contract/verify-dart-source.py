"""Verify real snapshot format hash from the official Dart source files."""
import ast,pathlib,hashlib,subprocess,json
root=pathlib.Path(__file__).resolve().parent.parent/'blutter-windows/dartsdk/v3.12.2'
tree=ast.parse((root/'tools/make_version.py').read_text())
files=next(ast.literal_eval(node.value) for node in tree.body if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='VM_SNAPSHOT_FILES' for t in node.targets))
disk=hashlib.md5();blob=hashlib.md5()
for filename in files:
 path='runtime/vm/'+filename
 disk.update((root/path).read_bytes())
 blob.update(subprocess.check_output(['git','-C',str(root),'show','HEAD:'+path]))
result={'dartCommit':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),
 'files':files,'diskSnapshotFormatHash':disk.hexdigest(),'gitBlobSnapshotFormatHash':blob.hexdigest(),
 'targetSnapshotFormatHash':'ace654289f5abc240509fc941453ebc5',
 'exactDiskSourceMatch':disk.hexdigest()=='ace654289f5abc240509fc941453ebc5',
 'exactGitSourceMatch':blob.hexdigest()=='ace654289f5abc240509fc941453ebc5',
 'hashWasForced':False}
pathlib.Path(__file__).with_name('dart-source-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
if not result['exactGitSourceMatch']:raise SystemExit('Snapshot source mismatch')
