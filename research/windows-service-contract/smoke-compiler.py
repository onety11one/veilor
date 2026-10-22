import pathlib,subprocess,json,shutil
from portable_env import compiler_environment
base=pathlib.Path(__file__).resolve().parent;out=base/'compiler-smoke';out.mkdir(exist_ok=True)
source=out/'main.cpp'
source.write_text('#include <windows.h>\n#include <format>\n#include <iostream>\nint main(){static_assert(sizeof(void*)==8);if(!GetCurrentProcessId())return 1;std::cout << std::format("MSVC-SDK-OK {:x}", DWORD{42});}\n')
env=compiler_environment(base)
subprocess.run([shutil.which('cl.exe',path=env['PATH']),'/nologo','/std:c++20','/EHsc','/MD',str(source),'/Fe:'+str(out/'smoke.exe')],cwd=out,env=env,check=True)
result=subprocess.run([str(out/'smoke.exe')],capture_output=True,text=True,check=True)
if result.stdout!='MSVC-SDK-OK 2a':raise RuntimeError('Unexpected smoke result')
record={'x64':True,'cxx20Format':True,'windowsSdkHeaderAndLink':True,'executedBinary':'own synthetic compiler test only','result':result.stdout}
(base/'compiler-smoke.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record))
