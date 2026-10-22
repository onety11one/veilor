"""Detection only in a reviewed/pinned Blutter fork; no build or VM load."""
import sys,pathlib
sys.path.insert(0,str(pathlib.Path('work/karing-feasibility/python-deps').resolve()))
sys.path.insert(0,str(pathlib.Path('work/toolchains/blutter-windows').resolve()))
import blutter
blutter.main2(str(pathlib.Path('work/karing-feasibility/targets/app.so').resolve()),
 'C:/Program Files/Karing/flutter_windows.dll',
 str(pathlib.Path('work/karing-feasibility/aot-dump-not-created').resolve()),
 rebuild_blutter=False,create_vs_sln=False,no_analysis=True,detect_only=True)
