import { readFile, writeFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { evaluatePage } from './lib/cdp-page.mjs';
const targets=await (await fetch('http://127.0.0.1:9223/json/list')).json();
const banks=[['tbank','www.tbank.ru'],['alfa','web.alfabank.ru'],['ozon','finance.ozon.ru'],['yandex','sp.yandex.ru'],['sber','online.sberbank.ru'],['vtb','online.sbpvtb.ru']];
const helper=await readFile(new URL('../browser_extension/adapters/monthly-confirmation.ts',import.meta.url),'utf8');
const results=[];
const snapshot={schemaVersion:1,generatedAt:new Date().toISOString(),requestedBanks:banks.map(([id])=>id),banks:[]};
for(const [bank,host] of banks){
 const target=targets.find(t=>t.type==='page'&&new URL(t.url).hostname===host);
 const source=await readFile(new URL(`../browser_extension/adapters/${bank}/cashback.ts`,import.meta.url),'utf8');
 const js=stripTypeScriptTypes(helper+source.replace(/^import .*monthly-confirmation.*\n/m,'')).replace(/export /g,'');
 const name=`extract${bank[0].toUpperCase()+bank.slice(1)}CashbackCategories`;
 const read = bank === 'tbank' ? '(await fetchTbankCashbackFromPage())?.categories ?? []' : `${name}()`;
 const raw=await evaluatePage(target,`(async () => {${js}\n return (${read}); })()`);
 const categories=raw.map(c=>({name:c.name,percent:c.percent,selected:c.selected,confirmed:c.confirmed===true,type:c.type}));
 if(!categories.some(c=>c.confirmed))throw new Error(`${bank}: no bank confirmation detected`);
 results.push({bank,categories,confirmedCount:categories.filter(c=>c.confirmed).length});
 snapshot.banks.push({bankId:bank,collectionStatus:'ready',authenticationStatus:'authenticated',collectedAt:new Date().toISOString(),selection:{isLocked:null},categories:raw});
}
await writeFile(new URL('../.local/live-bank-confirmation.json',import.meta.url),JSON.stringify(results,null,2));
await writeFile(new URL('../.local/live-bank-confirmation-snapshot.json',import.meta.url),JSON.stringify(snapshot,null,2));
console.log(JSON.stringify(results,null,2));
