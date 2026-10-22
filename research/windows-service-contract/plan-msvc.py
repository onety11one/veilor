"""Fetch public manifests, stop before license acceptance or package download."""
import sys,pathlib,json,hashlib
source=pathlib.Path(__file__).with_name('portable-msvc.py')
sys.argv=[str(source),'--vs','2022','--msvc-version','14.44','--sdk-version','26100']
scope={'__name__':'__metadata_only__'}
exec(compile(source.read_text(encoding='utf-8').split('### agree to license')[0],str(source),'exec'),scope)
manifest=scope['manifest'];packages=scope['packages'];first=scope['first']
tools=first(manifest['channelItems'],lambda x:x['id']=='Microsoft.VisualStudio.Product.BuildTools')
resource=first(tools['localizedResources'],lambda x:x['language']=='en-us')
ids=['microsoft.visualcpp.dia.sdk']
v=scope['msvc_ver']
ids += [f'microsoft.vc.{v}.{s}' for s in ['crt.headers.base','crt.source.base','asan.headers.base','pgo.headers.base','tools.hostx64.targetx64.base','tools.hostx64.targetx64.res.base','crt.x64.desktop.base','crt.x64.store.base','premium.tools.hostx64.targetx64.base','pgo.x64.base','asan.x64.base']]
redist=f'microsoft.vc.{v}.crt.redist.x64.base'
if redist not in packages:
 redist=first(first(packages['microsoft.visualcpp.crt.redist.x64'])['dependencies'],lambda x:x.endswith('.base')).lower()
ids.append(redist)
msvc=[]
for key in ids:
 if key not in packages:continue
 p=first(packages[key],lambda p:p.get('language') in (None,'en-US'))
 msvc.extend({'id':key,'file':x['fileName'],'bytes':x['size'],'sha256':x['sha256'],'url':x['url']} for x in p['payloads'])
sdk=packages[scope['sdk_pid']][0]
sdkPayloads=packages[first(sdk['dependencies']).lower()][0]['payloads']
result={'scope':'Planning only; Microsoft license not accepted and packages not downloaded',
 'msvcVersion':v,'windowsSdkFamily':scope['sdk_ver'],'licenseUrl':resource['license'],
 'msvcDownloads':msvc,'msvcDownloadBytes':sum(x['bytes'] for x in msvc),
 'sdkAllPayloadBytesUpperBound':sum(x['size'] for x in sdkPayloads),
 'sdkPayloadCount':len(sdkPayloads),'downloaderSha256':hashlib.sha256(source.read_bytes()).hexdigest(),
 'outputDirectory':str(source.parent.resolve()/'msvc'),
 'plannedDownloadCommand':['portable-msvc.py','--vs','2022','--msvc-version','14.44','--sdk-version','26100','--host','x64','--target','x64']}
pathlib.Path(__file__).with_name('msvc-plan.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['msvcVersion','windowsSdkFamily','licenseUrl','msvcDownloadBytes','sdkAllPayloadBytesUpperBound','sdkPayloadCount','outputDirectory']}))
