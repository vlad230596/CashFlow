import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import { evaluatePage } from './lib/cdp-page.mjs';
const targets = await (await fetch('http://127.0.0.1:9223/json/list')).json();
const target = targets.find(t=>t.type==='page'&&t.url.startsWith('https://finance.ozon.ru/'));
if (!target) throw new Error('Open the Ozon bank tab for DOM regression checks.');
const cases = [
  {bank:'ozon', extract:'extractOzonCashbackCategories', html:'<div data-testid="selection-title">Ваши категории в сентябре</div><div data-testid="favorite-category-list"><div data-testid="carousel-item"><div><div>10% Test</div></div><img src="https://example.test/icon.png"></div></div>', expected:true},
  {bank:'ozon', extract:'extractOzonCashbackCategories', html:'<div data-testid="selection-title">Выберите категории</div><div data-testid="favorite-category-list"><div><div>10% Test</div><input type="checkbox" checked></div></div>', expected:false},
  {bank:'ozon', extract:'extractOzonCashbackCategories', html:'<div data-testid="selection-title">Ваши категории в сентябре</div><div data-testid="favorite-category-list"><div><div>10% Test</div><input type="checkbox" checked></div></div>', expected:false},
  {bank:'alfa', extract:'extractAlfaCashbackCategories', html:'<div data-test-id="chosen-category-item"><span>10% Test</span></div>', expected:true},
  {bank:'alfa', extract:'extractAlfaCashbackCategories', html:'<div><span>10% Test</span><input data-test-id="checkbox-select-cashback-test" type="checkbox" checked></div>', expected:false},
  {bank:'alfa', extract:'extractAlfaCashbackCategories', html:'<section data-test-id="cashback-programs-item"><header><div><h4 data-test-id="cashback-programs-item-title">3%</h4><p data-test-id="cashback-program-card-subtitle">Красота в сентябре</p></div></header><footer><div data-test-id="icon-view-group-item-wrapper"><img src="https://example.test/beauty.png"></div></footer></section>', expected:true},
  {bank:'alfa', extract:'extractAlfaCashbackCategories', html:'<section data-test-id="cashback-programs-item"><header><h4 data-test-id="cashback-programs-item-title">3%</h4><p data-test-id="cashback-program-card-subtitle">Красота в сентябре</p></header><footer><div data-test-id="icon-view-group-item-wrapper"></div><button>Активировать</button></footer></section>', expected:false},
  {bank:'alfa', extract:'extractAlfaCashbackCategories', html:'<section data-test-id="cashback-programs-item"><h4 data-test-id="cashback-programs-item-title">3%</h4><p data-test-id="cashback-program-card-subtitle">Красота в октябре</p><div data-test-id="icon-view-group-item-wrapper"></div></section>', expected:false},
  {bank:'sber', extract:'extractSberCashbackCategories', html:'<h1>Мои категории В сентябре</h1> <div><p>10% Test</p><p>Conditions</p></div>', expected:true},
  {bank:'sber', extract:'extractSberCashbackCategories', html:'<h1>Мои категории В сентябре</h1> <div><p>10% Test</p><input type="checkbox" checked></div>', expected:false},
  {bank:'vtb', extract:'extractVtbCashbackCategories', html:'<div role="radiogroup"><button aria-checked="true">Сентябрь</button></div><div role="button" aria-label="10% в категории Test"><p>10% Test</p><button>Подробнее</button></div>', expected:true},
  {bank:'vtb', extract:'extractVtbCashbackCategories', html:'<div role="radiogroup"><button aria-checked="true">Октябрь</button></div><div role="button" aria-label="10% в категории Test"><p>10% Test</p><button>Подробнее</button></div>', expected:false, expectedSelected:false, expectedCount:0},
];
for (const [index, test] of cases.entries()) {
  const source=await readFile(new URL(`../browser_extension/adapters/${test.bank}/cashback.ts`,import.meta.url),'utf8');
  const helper=await readFile(new URL('../browser_extension/adapters/monthly-confirmation.ts',import.meta.url),'utf8');
  const js=stripTypeScriptTypes(helper+source.replace(/^import .*monthly-confirmation.*\n/m,'')).replace(/export /g,'');
  const host={sber:'online.sberbank.ru',vtb:'online.sbpvtb.ru'}[test.bank];
  const testTarget=host?targets.find(t=>t.type==='page'&&new URL(t.url).hostname===host):target;
  const result=await evaluatePage(testTarget, `(() => { ${js}\n const fixture=new DOMParser().parseFromString(${JSON.stringify(test.html)},'text/html'); return ${test.extract}(fixture).map(c=>({selected:c.selected,confirmed:c.confirmed===true})); })()`);
  if (result.length!==(test.expectedCount??1) || result.some(c=>c.confirmed!==test.expected || c.selected!==(test.expectedSelected??true))) throw new Error(`Fixture ${index+1} failed: ${JSON.stringify(result)}`);
  console.log(`PASS ${test.bank} ${test.expected?'saved choice':'unconfirmed checkbox'} fixture ${index+1}`);
}
