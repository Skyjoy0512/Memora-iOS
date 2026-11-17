import {build} from 'esbuild';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,readdirSync,existsSync} from 'node:fs';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {catalog,directives} from './catalog.mjs';
import {example} from './example.mjs';
import {stringify as yaml} from 'yaml';
const base=dirname(fileURLToPath(import.meta.url));process.chdir(base);
const output=resolve(base,'../../App/Resources');mkdirSync(output,{recursive:true});
const result=await build({entryPoints:['runtime.jsx'],bundle:true,minify:true,write:false,metafile:true,format:'iife',platform:'browser',target:'safari18',define:{'process.env.NODE_ENV':'"production"'},legalComments:'eof'});
const script=result.outputFiles[0].text.replaceAll('</script','<\\/script');
execFileSync(process.execPath,['node_modules/@tailwindcss/cli/dist/index.mjs','-i','styles.css','-o','.runtime.css','--minify'],{stdio:'pipe'});
const style=readFileSync('.runtime.css','utf8');
const scriptHash=createHash('sha256').update(script).digest('base64');
const csp=`default-src 'none'; script-src 'sha256-${scriptHash}'; style-src 'unsafe-inline'; img-src data: blob:; font-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'`;
writeFileSync(join(output,'JSONRenderRuntime.html'),`<!doctype html><html lang="ja"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="${csp}"><style>${style}</style></head><body><div id="root"></div><script>${script}</script></body></html>`);
const rules=[
  '通常の回答は短い日本語のMarkdown。フォーム、比較、操作や図表が有用な場合だけ、回答本文の後に生成UIを付ける。UIだけに重要な根拠を隠さない。',
  '記録・ツール結果にない値や架空の実績・人物・統計を作らない。サンプルデータを補う指示よりこのルールを優先する。入力フォームは空で始めてよい。',
  '生成UIの状態は回答内だけ。アプリの記録変更・メール送信・カレンダー登録を実行したと主張しない。変更には既存ツールと承認カードが必要。',
  '画像はdata URLかplaceholder。外部ネットワークは直接利用できない。HTTPSリンクは人が確認してから開く。任意のJavaScript、HTML、外部コードや認証情報を含めない。',
  '承認・質問・処理の進行表示はMemoraの既存カードに任せる。架空の進捗・件数・完了表示を作らない。',
  '最大256要素、状態64KiB、JSON合計256KiB、配列200件、表示の深さ16段まで。操作は宣言されたアクションのみ。',
];
writeFileSync(join(output,'JSONRenderPrompt.txt'),catalog.prompt({mode:'inline',directives,editModes:['patch','merge','diff'],customRules:rules}));
writeFileSync(join(output,'JSONRenderCatalog.json'),JSON.stringify({version:'0.23.1',components:catalog.componentNames,actions:catalog.actionNames,schema:catalog.jsonSchema()},null,2));
writeFileSync(join(output,'JSONRenderExample.txt'),'表示検証用の架空データです。入力や操作はこの回答の中だけで動きます。\n\n```json-render\n'+JSON.stringify(example)+'\n```');
const patches=[{op:'add',path:'/root',value:example.root},{op:'add',path:'/state',value:example.state},...Object.entries(example.elements).map(([key,value])=>({op:'add',path:'/elements/'+key,value}))];
writeFileSync(join(output,'JSONRenderPatchExample.txt'),'JSON Patchの表示検証です。架空のデータを使います。\n\n```spec\n'+patches.map(patch=>JSON.stringify(patch)).join('\n')+'\n```');
writeFileSync(join(output,'JSONRenderYAMLExample.txt'),'YAMLの表示検証です。架空のデータを使います。\n\n```yaml-spec\n'+yaml(example)+'\n```');

// Include the notices for every package actually present in the shipped bundle.
const packages=new Map();
for(const input of Object.keys(result.metafile.inputs)) {
  const marker='node_modules/'; const at=input.lastIndexOf(marker); if(at<0)continue;
  const parts=input.slice(at+marker.length).split('/');const name=parts[0].startsWith('@')?parts.slice(0,2).join('/'):parts[0];
  const folder=join(base,'node_modules',name);if(packages.has(name)||!existsSync(join(folder,'package.json')))continue;
  const info=JSON.parse(readFileSync(join(folder,'package.json'),'utf8'));
  const files=readdirSync(folder).filter(name=>/^(license|licence|notice)(\.|$)/i.test(name));
  packages.set(name,`${info.name} ${info.version}\nLicense: ${info.license??'See notice'}\n`+files.map(file=>readFileSync(join(folder,file),'utf8')).join('\n'));
}
writeFileSync(join(output,'JSONRenderLicenses.txt'),[...packages.values()].join('\n\n----------------\n\n'));
console.log(`Bundled ${catalog.componentNames.length} components; ${packages.size} package notices; ${script.length} JS bytes.`);
