import os,pathlib
def compiler_environment(base):
 base=pathlib.Path(base).resolve();toolchain=base/'msvc'
 msvc=sorted((toolchain/'VC/Tools/MSVC').iterdir())[-1]
 kit=toolchain/'Windows Kits/10';sdkVersion=sorted((kit/'Include').iterdir())[-1].name
 cmake=base/'python-deps/cmake/data/bin';ninja=base/'python-deps/bin'
 for required in [msvc/'bin/Hostx64/x64/cl.exe',kit/'Lib'/sdkVersion/'um/x64/kernel32.lib',kit/'Include'/sdkVersion/'ucrt/stdio.h']:
  if not required.exists():raise RuntimeError('Incomplete portable compiler or SDK')
 environment=os.environ.copy()
 environment['PATH']=os.pathsep.join(str(p) for p in [msvc/'bin/Hostx64/x64',kit/'bin'/sdkVersion/'x64',cmake,ninja,base.parent/'blutter-windows/bin'])+os.pathsep+environment['PATH']
 environment['INCLUDE']=os.pathsep.join(str(p) for p in [msvc/'include',*[kit/'Include'/sdkVersion/n for n in ['ucrt','shared','um','winrt']]])
 environment['LIB']=os.pathsep.join(str(p) for p in [msvc/'lib/x64',kit/'Lib'/sdkVersion/'ucrt/x64',kit/'Lib'/sdkVersion/'um/x64'])
 environment['CC']='cl.exe';environment['CXX']='cl.exe';environment['VSCMD_ARG_TGT_ARCH']='x64'
 return environment
