'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('assert'),path=require('path'),crypto=require('crypto');
const root=path.join(__dirname,'..','BrowserExtension');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'manifest.json')));
assert.deepStrictEqual(manifest.permissions.sort(),['activeTab','nativeMessaging','scripting']);
assert(!manifest.host_permissions&&!manifest.content_scripts&&!manifest.externally_connectable);
assert.strictEqual(manifest.background.service_worker,'capture-worker.js');
const id=crypto.createHash('sha256').update(Buffer.from(manifest.key,'base64')).digest('hex').slice(0,32).split('').map(c=>String.fromCharCode(97+parseInt(c,16))).join('');
assert.strictEqual(id,'onchblaldmgmldajccljklnjonkicpnf');
for(const file of ['popup.html','popup.css','popup.js','capture-worker.js','capture-core.js','page-actions.js','capture-store.js','capture-ui.js','ui.css','editor.html','editor.js','editor-core.js','editor.css','result.html','result.js','result.css','icons/interface.svg','icons/toolkit.svg',...Object.values(manifest.icons)]) assert(fs.existsSync(path.join(root,file)));
const C=require(path.join(root,'capture-core.js'));let checks=0;
function test(value,message){assert(value,message);checks++;}
function equal(actual,expected,message){assert.deepStrictEqual(actual,expected,message);checks++;}
// Every destination pixel must be covered exactly once, including the last overlapping scroll.
function coverage(width,height,vw,vh,scale){
  const plan=C.plan(width,height,vw,vh),size=C.dimensions(width,height,scale,scale);
  const pixels=new Uint8Array(size.width*size.height);
  for(const tile of plan.tiles){const p=C.placement(tile,tile.x,tile.y,scale,scale);test(p.sx>=0&&p.sy>=0,'Nonnegative source crop');test(p.sx+p.sw<=Math.round(vw*scale)+1&&p.sy+p.sh<=Math.round(vh*scale)+1,'Crop remains in viewport');for(let y=p.dy;y<p.dy+p.height;y++)for(let x=p.dx;x<p.dx+p.width;x++)pixels[y*size.width+x]++;}
  test(pixels.every(value=>value===1),`No seams or duplicate pixels: ${width}x${height} @${scale}`);
}
for(const scale of [1,1.25,1.5,2]){coverage(91,257,91,100,scale);coverage(251,257,100,100,scale);coverage(43,29,100,100,scale);coverage(200,200,100,100,scale);}
equal(C.placement({left:0,top:200,right:100,bottom:257},0,157,1.5,1.5).sy,64,'Fractional DPR last tile avoids one-pixel origin drift');
equal(C.axis(250,100),[{scroll:0,start:0,end:100},{scroll:100,start:100,end:200},{scroll:150,start:200,end:250}],'Last tile crops overlap');
equal(C.region({x:10.2,y:20.4,width:50.3,height:30.3},{width:100,height:100},125,125),{x:13,y:26,width:63,height:37},'Fractional density region endpoints');
equal(C.region({x:-5,y:-5,width:20,height:20},{width:100,height:100},200,200),{x:0,y:0,width:30,height:30},'Region clamps to viewport');
for(const block of [()=>C.plan(100,100000,100,100),()=>C.plan(0,100,100,100),()=>C.dimensions(40000,20,1,1),()=>C.dimensions(10000,10000,1,1),()=>C.dimensions(NaN,10,1,1),()=>C.region({x:10,y:10,width:0,height:1},{width:100,height:100},100,100)]) {assert.throws(block);checks++;}
// Popup delegates to worker, prevents duplicate starts, exposes cancellation, and displays progress.
let handlers={},requests=[],poll;const buttons=['full','visible','region'].map(mode=>({dataset:{mode},disabled:false,addEventListener(_,f){handlers[mode]=f;}}));
const nodes={};
for(const id of ['status','cancel','setup','settings','latest','shortcuts','resolution'])nodes[id]={textContent:'',className:'',hidden:true,value:'',addEventListener(_,f){handlers[id]=f;},setAttribute(){}};
const {status,setup}=nodes;
let workerResponse={ok:true},pendingResolve,closedPopup=0;
const popupContext={window:{close(){closedPopup++;}},document:{querySelectorAll(){return buttons;},getElementById(id){return nodes[id];}},localStorage:{getItem(){return '1x';},setItem(){}},SnapCaptureStore:{async latest(){return {id:'recent'};}},setInterval(f){poll=f;},chrome:{tabs:{async query(){return [{id:3,windowId:7}];}},runtime:{async sendMessage(message){requests.push(message);if(message.action==='status')return {busy:false,message:''};if(message.action==='cancel'||message.action==='showResult')return {ok:true};if(pendingResolve)return new Promise(resolve=>pendingResolve.push(resolve));return workerResponse;}}}};
vm.runInNewContext(fs.readFileSync(path.join(root,'popup.js'),'utf8'),popupContext);
(async()=>{
  await Promise.resolve();const first=handlers.full(),duplicate=handlers.visible();await Promise.all([first,duplicate]);
  equal(requests.filter(r=>r.action==='startCapture').length,1,'Duplicate popup starts suppressed');
  test(requests.find(r=>r.action==='startCapture').mode==='full','Full page requested');test(closedPopup===1,'Popup closes after editor opens');
  equal(requests.find(r=>r.action==='startCapture').delivery,'editor','Browser editor is the default');
  equal(requests.find(r=>r.action==='startCapture').resolution,'1x','Saved quality preference used');
  await handlers.latest();test(requests.some(r=>r.action==='showResult'&&r.id==='recent'),'Latest opens a compact preview');
  workerResponse={ok:false,error:'Cannot capture this tab'};await handlers.region();test(status.className.includes('error')&&!status.hidden,'Capture errors visible');
  handlers.settings();test(!setup.hidden,'Settings open on demand');
  pendingResolve=[];const pending=handlers.visible();await Promise.resolve();await handlers.cancel();test(requests.some(r=>r.action==='cancel'),'Cancel sent');pendingResolve[0]({ok:false,error:'Capture cancelled.'});await pending;pendingResolve=null;
  test(buttons.every(button=>button.disabled===false),'Buttons recover after cancellation');
  workerResponse={ok:true,started:true};await handlers.region();test(closedPopup===3,'Region popup closes after worker acknowledgement');test(requests.filter(r=>r.action==='startCapture').at(-1).detach===true,'Region requests detached background selection');
  console.log(`PASS: ${checks} browser geometry/popup checks + permissions, fixed identity, complete packaged files`);
})().catch(error=>{console.error(error);process.exit(1);});
