import fs from 'node:fs';
import path from 'node:path';

const root = process.argv[2] || '_site';
const base = '/Football-PA-Core-Web';
const extensions = new Set(['.html','.css']);

function rewriteHtml(text){
  return text.replace(/(\s(?:href|src|action)=["'])\/(?!\/)/gi,(m,prefix)=>prefix+base+'/');
}
function rewriteCss(text){
  return text.replace(/url\((['"]?)\/(?!\/)/gi,(m,q)=>'url('+q+base+'/');
}
function walk(dir){
  for(const entry of fs.readdirSync(dir,{withFileTypes:true})){
    const full=path.join(dir,entry.name);
    if(entry.isDirectory()) walk(full);
    else if(extensions.has(path.extname(entry.name).toLowerCase())){
      let text=fs.readFileSync(full,'utf8');
      text=path.extname(entry.name).toLowerCase()==='.html'?rewriteHtml(text):rewriteCss(text);
      fs.writeFileSync(full,text);
    }
  }
}
walk(root);
fs.writeFileSync(path.join(root,'.nojekyll'),'');
console.log('Prepared GitHub Pages preview at '+base+'/');
