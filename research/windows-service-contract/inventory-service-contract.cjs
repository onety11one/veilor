// Read-only, offline contract evidence. Never loads user configuration values.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const repo='outputs/veilor',out=repo+'/research/windows-service-contract';
fs.mkdirSync(out,{recursive:true});
const inventory=JSON.parse(fs.readFileSync('outputs/veilor-compatibility/ast-inventory.json','utf8'));
const calls={};
for(const era of ['historical','current']){
 calls[era]={calls:inventory[era].calls.filter(x=>x.target==='FlutterVpnService'),
  properties:inventory[era].memberReferences.filter(x=>x.target==='FlutterVpnService')};
}
const wrapper=fs.readFileSync(repo+'/research/karing-vpn-service-reference/lib/app/local_services/vpn_service.dart','utf8');
const configBlock=wrapper.slice(wrapper.indexOf('static Future<bool> _prepareConfig()'),wrapper.indexOf('static Duration getTimeoutByOutboundCount('));
const configAssignments=[...configBlock.matchAll(/\bconfig\.([a-z_]+)\s*=/g)].map(x=>x[1]);
const binary=fs.readFileSync('work/karing-feasibility/targets/vpn_service_plugin.dll');
const pe=binary.readUInt32LE(0x3c),opt=pe+24,sections=opt+binary.readUInt16LE(pe+20),imageBase=binary.readBigUInt64LE(opt+24);
function offset(va){const rva=Number(BigInt(va)-imageBase);for(let i=0;i<binary.readUInt16LE(pe+6);i++){const s=sections+i*40,v=binary.readUInt32LE(s+12),size=binary.readUInt32LE(s+16);if(rva>=v&&rva<v+size)return binary.readUInt32LE(s+20)+rva-v;}throw Error('Unmapped RVA');}
const vtable='0x180012c68',start=offset(vtable);
const pointers=Array.from({length:6},(_,i)=>({slot:i,address:'0x'+binary.readBigUInt64LE(start+i*8).toString(16)}));
const strings=[...binary.toString('latin1').matchAll(/[\x20-\x7e]{4,120}/g)]
 .filter(x=>/^(isRunAsAdmin|cleanSystemProxy|setSystemProxy|getSystemProxyEnable|firewallAddApp|firewallAddPorts|autoStartCreate|autoStartDelete|autoStartIsActive|bypassDomains|appPath|appName|ports|taskName|processPath|processArgs|runElevated)$/.test(x[0]))
 .map(x=>({offset:x.index,text:x[0]}));
const result={scope:'Existing parser AST inventory (comments excluded); no missing-package resolution. Binary strings and vtable pointers are static evidence, not executed commands.',
 baseCommit:'1f52c28e062fe55d7c3ccc254f1a90d53fd8c103',historicalCommit:'e3c19f1eb1225dbd48a4862f0983b82d0af8de69',
 calls,publicHistoricalMethods:inventory.historical.classes.VPNService?.methods,
 historicalServiceConfigAssignments:[...new Set(configAssignments)],
 native:{sha256:crypto.createHash('sha256').update(binary).digest('hex'),channel:'vpn_service_plugin',
 methodCallbackVtable:vtable,pointers,selectedExactStrings:strings},
 limitations:['Method call arity is observed at callers; missing callee declarations are not recovered.',
 'Current call sites include multiple platforms; platform branch conditions must be checked before Windows implementation.',
 'No service CLI, RPC endpoint or numeric native state enum is inferred from these strings.']};
fs.writeFileSync(out+'/source-and-native-inventory.json',JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({uniqueCurrentMethods:[...new Set(calls.current.calls.map(x=>x.method))],
 uniqueHistoricalMethods:[...new Set(calls.historical.calls.map(x=>x.method))],configAssignments:result.historicalServiceConfigAssignments,pointers},null,2));
