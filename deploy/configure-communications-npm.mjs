// Run inside the existing NPM container as its operator. Update only this host.
import fs from 'node:fs';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import jwt from '/app/node_modules/jsonwebtoken/index.js';

const directory='/data/widows-sons-vm20000';
fs.mkdirSync(directory,{recursive:true,mode:0o700});
const keys=JSON.parse(fs.readFileSync('/data/keys.json','utf8'));
const token=jwt.sign({iss:'api',attrs:{id:1},scope:['user']},keys.key,{algorithm:'RS256',expiresIn:300});
async function api(path,options={}) {
  const result=await fetch('http://127.0.0.1:3000'+path,{...options,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'}});
  const data=await result.json();
  if(!result.ok) throw new Error('NPM API failed: '+result.status);
  return data;
}
const hosts=await api('/nginx/proxy-hosts');
const host=hosts.find(item=>item.domain_names.includes('wsmba.the-grange.uk'));
if(!host || host.forward_host!=='10.44.0.200' || host.forward_port!==8080) throw new Error('Dedicated Widows Sons proxy host not found');
const hashes=Object.fromEntries(fs.readdirSync('/data/nginx/proxy_host').filter(name=>name.endsWith('.conf')&&name!==host.id+'.conf').map(name=>[name,crypto.createHash('sha256').update(fs.readFileSync('/data/nginx/proxy_host/'+name)).digest('hex')]));
const backup=directory+'/before-communications-'+Date.now()+'.sqlite';
execFileSync('python3',['-c',"import sqlite3,os;src=sqlite3.connect('/data/database.sqlite');dst=sqlite3.connect("+JSON.stringify(backup)+");src.backup(dst);dst.close();os.chmod("+JSON.stringify(backup)+",0o600)"]);
const payload={};
for(const field of ['domain_names','forward_scheme','forward_host','forward_port','access_list_id','certificate_id','ssl_forced','caching_enabled','block_exploits','allow_websocket_upgrade','http2_support','hsts_enabled','hsts_subdomains','enabled','locations','meta','advanced_config']) {
  if(field in host) payload[field]=host[field];
}
payload.allow_websocket_upgrade=true;
if(!(payload.advanced_config||'').includes('# Widows Sons intercom signalling')) {
  payload.advanced_config=(payload.advanced_config||'')+`
# Widows Sons intercom signalling; bearer JWTs must not enter request logs.
location ^~ /rtc {
    proxy_pass http://10.44.0.200:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 75s;
    access_log off;
    error_log /dev/null crit;
}
`;
  await api('/nginx/proxy-hosts/'+host.id,{method:'PUT',body:JSON.stringify(payload)});
}
execFileSync('/usr/local/openresty/nginx/sbin/nginx',['-t'],{stdio:'pipe'});
for(const [name,hash] of Object.entries(hashes)) {
  if(crypto.createHash('sha256').update(fs.readFileSync('/data/nginx/proxy_host/'+name)).digest('hex')!==hash) throw new Error('Unrelated proxy changed: '+name);
}
console.log(JSON.stringify({project:'widows-sons',proxy_host:host.id,websocket_route:'/rtc',request_logging:false,unrelated_proxies_verified:Object.keys(hashes).length,cloudflare_changed:false}));
