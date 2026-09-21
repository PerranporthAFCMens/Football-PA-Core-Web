import fs from 'node:fs';
import path from 'node:path';

const root = process.argv[2] || '_site';
const base = '/Football-PA-Core-Web';
const extensions = new Set(['.html','.js','.css','.json','.webmanifest']);

function walk(dir){
  for(const entry of fs.readdirSync(dir,{withFileTypes:true})){
    const full=path.join(dir,entry.name);
    if(entry.isDirectory()) walk(full);
    else if(extensions.has(path.extname(entry.name).toLowerCase())){
      let text=fs.readFileSync(full,'utf8');
      text=text.replace(/(["'`])\/(?!\/)/g,(m,q)=>q+base+'/');
      fs.writeFileSync(full,text);
    }
  }
}
walk(root);
fs.writeFileSync(path.join(root,'.nojekyll'),'');
console.log('Prepared GitHub Pages preview at '+base+'/');
