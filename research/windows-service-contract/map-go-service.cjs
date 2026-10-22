// Offline Go 1.20+ pclntab decoder for this read-only PE snapshot.
const fs=require('fs'),crypto=require('crypto');
const file='work/karing-feasibility/targets/karingService.exe',b=fs.readFileSync(file);
const magic=Buffer.from([0xf1,0xff,0xff,0xff,0,0,1,8]);
const pe=b.readUInt32LE(0x3c),opt=pe+24,sec=opt+b.readUInt16LE(pe+20);
const imageBase=Number(b.readBigUInt64LE(opt+24));let textBase;const sectionMap=[];
for(let i=0;i<b.readUInt16LE(pe+6);i++){
 const s=sec+i*40;sectionMap.push({rva:b.readUInt32LE(s+12),raw:b.readUInt32LE(s+20),size:b.readUInt32LE(s+16)});if(b.toString('ascii',s,s+8).replace(/\0.*$/,'')==='.text')textBase=imageBase+b.readUInt32LE(s+12);
}
if(!textBase)throw Error('Missing text section');
const candidates=[];
for(let p=b.indexOf(magic);p>=0;p=b.indexOf(magic,p+1)){
 try{
  const u64=o=>Number(b.readBigUInt64LE(o));
  const count=u64(p+8),headerText=u64(p+24),names=p+u64(p+32),funcs=p+u64(p+64);
  const section=sectionMap.find(s=>p>=s.raw&&p<s.raw+s.size);
  if(!section)continue;
  const headerVa=imageBase+section.rva+p-section.raw,needle=Buffer.alloc(8);needle.writeBigUInt64LE(BigInt(headerVa));
  const modules=[];
  for(let m=b.indexOf(needle);m>=0;m=b.indexOf(needle,m+8)){
   const min=u64(m+160),max=u64(m+168),text=u64(m+176),etext=u64(m+184);
   if(text===min&&text>=textBase&&text<textBase+0x10000&&etext>=max&&etext-max<0x1000)modules.push({offset:m,text});
  }
  if(modules.length!==1)throw Error('Expected unique moduledata text base');
  const text=headerText||modules[0].text;
  if(count<100||count>100000||names>b.length||funcs+count*8>b.length)continue;
  const found=[],all=[];
  for(let i=0;i<count;i++){
   const entry=b.readUInt32LE(funcs+i*8),f=funcs+b.readUInt32LE(funcs+i*8+4);
   const nameStart=names+b.readInt32LE(f+4),end=b.indexOf(0,nameStart);
   if(nameStart<names||end<nameStart||end-nameStart>65536)throw Error('Bad symbol at '+i);
   const name=b.toString('utf8',nameStart,end);
   const item={name,address:'0x'+(text+entry).toString(16),size:b.readUInt32LE(funcs+(i+1)*8)-entry};
   all.push(item);if(name.startsWith('main.'))found.push(item);
  }
  if(found.some(x=>x.name==='main.createHttpServer')){fs.writeFileSync('work/karing-feasibility/go-all-functions.json',JSON.stringify(all));candidates.push({pclntabFileOffset:p,functionCount:count,headerTextStart:headerText,moduledataFileOffset:modules[0].offset,textStart:'0x'+text.toString(16),textBasis:headerText?'header':'runtime moduledata.text, cross-checked against minpc/etext and PE .text',functions:found});}
 }catch(error){console.error('Candidate',p,error.message);}
}
if(candidates.length!==1)throw Error('Expected exactly one validated pclntab');
const result={scope:'Static pclntab names/entry PCs, not recovered function behavior',
 sha256:crypto.createHash('sha256').update(b).digest('hex'),...candidates[0]};
fs.writeFileSync('outputs/veilor/research/windows-service-contract/go-service-functions.json',JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({functionCount:result.functionCount,selected:result.functions.filter(x=>/main\.(createHttpServer|restartService|destroyService|createService|run$|main$|init$|preRun$|readConfig|makeProcessSingleton|terminateCurrentProcess)/.test(x.name))},null,2));
