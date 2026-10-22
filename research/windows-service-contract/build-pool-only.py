"""Workspace-only build driver. Never downloads/accepts Microsoft terms,
never starts an analyzer or application; --prepare-only needs no compiler."""
import argparse,pathlib,subprocess,sys,os,json,ast,hashlib,shutil
base=pathlib.Path(__file__).resolve().parent
blutter=base.parent/'blutter-windows';sdk=blutter/'dartsdk/v3.12.2'
ap=argparse.ArgumentParser();ap.add_argument('--prepare-only',action='store_true');args=ap.parse_args()
def run(command,*,cwd=sdk,env=None):subprocess.run([str(x) for x in command],cwd=cwd,env=env,check=True)
run([sys.executable,base/'verify-dart-source.py'],cwd=base)
# Official generator computes its own source hash; no hash override is supplied.
run([sys.executable,'tools/make_version.py','--input','runtime/vm/version_in.cc','--output','runtime/vm/version.cc'])
template=(blutter/'scripts/CMakeLists.txt').read_text()
(sdk/'CMakeLists.txt').write_text(template.replace('VERSION_PLACE_HOLDER','3.12.2').replace('CXX_STD_PLACE_HOLDER','20'))
(sdk/'Config.cmake.in').write_text('@PACKAGE_INIT@\ninclude("${CMAKE_CURRENT_LIST_DIR}/dartvmTarget.cmake")\n')
run([sys.executable,blutter/'scripts/dartvm_create_srclist.py',sdk])
sys.path.insert(0,str(blutter));import blutter as driver
compat=base/'compat-headers';vmHeaders=compat/'dartvm3.12.2/vm';vmHeaders.mkdir(parents=True,exist_ok=True)
for name in ['class_id.h','class_table.h','stub_code_list.h','object_store.h','object.h']:
 shutil.copy2(sdk/'runtime/vm'/name,vmHeaders/name)
driver.PKG_INC_DIR=str(compat) # Detect macros from source before VM install.
macros=driver.find_compat_macro('3.12.2',True)
cmake=base/'python-deps/cmake/data/bin/cmake.exe';ninja=base/'python-deps/bin/ninja.exe'
vmBuild=blutter/'build/dartvm3.12.2_windows_x64'
analyzerBuild=blutter/'build/blutter_dartvm3.12.2_windows_x64_no-compressed-ptrs_no-analysis'
commands=[
 [cmake,'-S',sdk,'-B',vmBuild,'-G','Ninja','-DTARGET_OS=windows','-DTARGET_ARCH=x64','-DCOMPRESSED_PTRS=0','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_CXX_FLAGS=/Zc:preprocessor'],
 [cmake,'--build',vmBuild,'--parallel','4'],[cmake,'--install',vmBuild],
 [cmake,'-S',blutter/'blutter','-B',analyzerBuild,'-G','Ninja','-DDARTLIB=dartvm3.12.2_windows_x64','-DNAME_SUFFIX=_no-compressed-ptrs_no-analysis','-DBLUTTER_ARCH=x64','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_CXX_FLAGS=/Zc:preprocessor /EHsc',*macros],
 [cmake,'--build',analyzerBuild,'--parallel','4'],[cmake,'--install',analyzerBuild],
]
manifest={'scope':'Prepared build commands only; analyzer is not executed by this driver',
 'sourceHashVerified':True,'cxxStandard':20,'compressedPointers':False,'analysis':'pool-only',
 'compatMacros':macros,'commands':[[str(v) for v in c] for c in commands],
 'msvcPresent':(base/'msvc/VC/Tools/MSVC').is_dir(),
 'licenseAccepted':json.loads((base/'license-acceptance.json').read_text()).get('accepted',False) if (base/'license-acceptance.json').exists() else False}
(base/'pool-build-plan.json').write_text(json.dumps(manifest,indent=2)+'\n')
if args.prepare_only:
 print(json.dumps({'prepared':True,'msvcPresent':manifest['msvcPresent'],'analyzerExecuted':False}));raise SystemExit()
if not manifest['msvcPresent']:raise SystemExit('MSVC missing: explicit Microsoft license confirmation required before download')
from portable_env import compiler_environment
environment=compiler_environment(base)
for command in commands:run(command,cwd=blutter,env=environment)
print('Build complete; analyzer deliberately not executed')
