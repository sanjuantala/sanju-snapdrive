'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('assert'),path=require('path');
const extension=path.join(__dirname,'..','BrowserExtension');
const HOST='com.snapdrive.browser';let checks=0;
function equal(a,b,message){assert.deepStrictEqual(a,b,message);checks++;}
function good(a,message){assert(a,message);checks++;}
function environment(options={}){
  let onMessage,onCommand,clock=1000,scroll={x:0,y:0},restored=0,captureCount=0,queryCount=0,canvasCount=0,closed=0,native=[],saved=[],opened=[],warmCount=0,scrollCount=0,grew=false;
  const density=options.density||2,page={width:options.width||15,height:options.height||25,viewportWidth:10,viewportHeight:10,windowWidth:10,windowHeight:10,sourceX:options.panel?2:0,sourceY:options.panel?1:0,targetKind:options.panel?'panel':'document'};
  if(options.panel){page.viewportWidth=6;page.viewportHeight=7;}
  function png(info){return 'data:image/png;base64,'+Buffer.from(JSON.stringify(info)).toString('base64');}
  const screenshotValue=()=>png({width:Math.round(10*density),height:Math.round(10*density),originX:Math.round(scroll.x*density)-Math.round(page.sourceX*density),originY:Math.round(scroll.y*density)-Math.round(page.sourceY*density)});
  const state={get restored(){return restored;},get captures(){return captureCount;},get canvases(){return canvasCount;},get closed(){return closed;},native,saved,opened,page,screenshotValue};
  const context={console,Blob,Uint8Array,Date:{now:()=>clock},crypto:{randomUUID:()=> 'session-token'},fetch:async data=>({blob:async()=>new Blob([Buffer.from(data.split(',')[1],'base64')],{type:'image/png'})}),btoa:value=>Buffer.from(value,'binary').toString('base64'),setTimeout(fn,delay){clock+=delay;queueMicrotask(fn);return 1;},OffscreenCanvas:class{
    constructor(width,height){canvasCount++;this.width=width;this.height=height;this.pixels=new Array(width*height).fill(-1);}
    getContext(){const canvas=this;return {imageSmoothingEnabled:false,drawImage(image,sx,sy,sw,sh,dx,dy,dw,dh){for(let y=0;y<dh;y++)for(let x=0;x<dw;x++){const ix=Math.min(image.width-1,Math.floor(sx+(x+.5)*sw/dw)),iy=Math.min(image.height-1,Math.floor(sy+(y+.5)*sh/dh));canvas.pixels[(dy+y)*canvas.width+dx+x]=image.pixels?image.pixels[iy*image.width+ix]:(image.originY+iy)*1000+image.originX+ix;}}};}
    async convertToBlob(){return new Blob([JSON.stringify({width:this.width,height:this.height,pixels:this.pixels})],{type:'image/png'});}
  },createImageBitmap:async blob=>{const image=JSON.parse(await blob.text());image.close=()=>closed++;return image;},chrome:{commands:{onCommand:{addListener(fn){onCommand=fn;}}},windows:{async create(details){opened.push(details);}},runtime:{getURL:file=>'chrome-extension://extension-id/'+file,id:'extension-id',onMessage:{addListener(fn){onMessage=fn;}},async sendNativeMessage(host,request){equal(host,HOST,'Correct native host');if(options.nativeError)throw new Error(options.nativeError);native.push(request);return {ok:true};}},action:{async setBadgeBackgroundColor(){},async setBadgeText(){}},tabs:{async create(details){opened.push(details);},onRemoved:{addListener(){}},async query(){queryCount++;return [{id:options.changeTab&&queryCount>2?9:3,windowId:7}];},async captureVisibleTab(windowId,format){captureCount++;equal(windowId,7,'Correct browser window');equal(format.format,'png','Lossless browser capture');if(options.cancelOnCapture)onMessage({action:'cancel'},{id:'extension-id'},()=>{});return screenshotValue();}},scripting:{async executeScript(injection){const name=injection.func.name,args=injection.args||[];let result;if(name==='snapPreparePage')result={...page,original:{x:2,y:4}};else if(name==='snapWarmPage'){warmCount++;scroll={x:0,y:0};result={...page};}else if(name==='snapScrollPage'){scrollCount++;scroll={x:args[1],y:args[2]};if(options.growOnce&&!grew&&scrollCount===2){page.height+=3;grew=true;}result={...page,x:scroll.x,y:scroll.y,height:page.height+(options.resize?100:0)};}else if(name==='snapRestorePage'){restored++;scroll={x:2,y:4};}else if(name==='snapSelectRegion')result={token:'session-token',x:2,y:3,width:4,height:5,viewport:{width:10,height:10}};else if(name==='snapCancelRegion')result=null;else throw new Error('Unexpected injection '+name);return [{result}];}}}};
  vm.createContext(context);context.importScripts=(...files)=>files.forEach(file=>vm.runInContext(fs.readFileSync(path.join(extension,file),'utf8'),context));
  vm.runInContext(fs.readFileSync(path.join(extension,'capture-worker.js'),'utf8'),context);
  context.SnapCaptureStore={async put(blob,mode){saved.push({blob,mode});return '11111111-1111-4111-8111-111111111111';}};
  state.command=(name,tab={id:3,windowId:7})=>onCommand(name,tab);
  state.send=message=>new Promise(resolve=>onMessage(message,{id:'extension-id'},resolve));
  state.run=(mode,resolution='native')=>state.send({action:'startCapture',mode,tabId:3,windowId:7,resolution});
  return state;
}
(async()=>{
  let e=environment();let response=await e.run('full');good(response.ok,'Full page succeeds');good(e.restored>0,'Full page restores page');equal(e.captures,6,'Horizontal and vertical tiles captured');equal(e.closed,6,'Every bitmap released');
  let final=JSON.parse(Buffer.from(e.native[0].png.split(',')[1],'base64'));equal([final.width,final.height],[30,50],'Native density retained');
  good(final.pixels.every((pixel,index)=>pixel===Math.floor(index/30)*1000+index%30),'Stitched pixels exactly match full virtual page');
  e=environment({density:1.5,width:15,height:27});response=await e.run('full');good(response.ok,'Fractional density capture succeeds');final=JSON.parse(Buffer.from(e.native[0].png.split(',')[1],'base64'));equal([final.width,final.height],[23,41],'Fractional dimensions rounded consistently');good(final.pixels.every((pixel,index)=>pixel===Math.floor(index/23)*1000+index%23),'Last overlap at fractional DPR contains correct source pixels');
  e=environment();response=await e.run('full','1x');good(response.ok,'Explicit1x capture succeeds');final=JSON.parse(Buffer.from(e.native[0].png.split(',')[1],'base64'));equal([final.width,final.height],[15,25],'Explicit1x has CSS resolution');
  e=environment();const original=e.screenshotValue();response=await e.run('visible');good(response.ok,'Visible capture succeeds');equal(e.native[0].png,original,'Visible PNG bytes unchanged');equal(e.canvases,0,'Visible capture does not allocate an output canvas');
  e=environment();response=await e.run('region');good(response.ok,'Region capture succeeds');final=JSON.parse(Buffer.from(e.native[0].png.split(',')[1],'base64'));equal([final.width,final.height],[8,10],'Region preserves native density');good(final.pixels.every((pixel,index)=>pixel===(6+Math.floor(index/8))*1000+4+index%8),'Frozen region contains exact selected pixels');
  for(const option of [{cancelOnCapture:true},{changeTab:true},{resize:true},{nativeError:'Specified native messaging host not found.'}]){e=environment(option);response=await e.run('full');good(!response.ok,'Capture failure returned');good(e.restored>0,'Failure/cancellation restores page');if(!option.nativeError)equal(e.native.length,0,'Failed/cancelled capture is not sent to app');}
  e=environment({width:10000,height:10000});response=await e.run('full');good(!response.ok,'Excessive tile count rejected');equal(e.canvases,0,'Excessive page does not allocate canvas');good(e.restored>0,'Oversize failure restores page');
  e=environment();response=await e.send({action:'startCapture',mode:'region',tabId:3,windowId:7,detach:true});good(response.ok&&response.started,'Region acknowledges before detached capture completes');
  for(let i=0;i<30&&e.native.length===0;i++)await new Promise(resolve=>setImmediate(resolve));good(e.native.length===1,'Detached region finishes after sender acknowledgement');
  e=environment({panel:true,width:9,height:16});response=await e.run('full');good(response.ok,'Internal scrolling panel capture succeeds');final=JSON.parse(Buffer.from(e.native[0].png.split(',')[1],'base64'));equal([final.width,final.height],[18,32],'Panel output excludes surrounding browser chrome');good(final.pixels.every((pixel,index)=>pixel===Math.floor(index/18)*1000+index%18),'Panel crop offsets retain exact full content pixels');
  e=environment({growOnce:true});response=await e.run('full');good(response.ok,'A lazy layout change retries once and succeeds');equal(e.native.length,1,'Abandoned partial capture is never handed off');good(e.restored>=2,'Both attempts restore the page');final=JSON.parse(Buffer.from(e.native[0].png.split(',')[1],'base64'));equal([final.width,final.height],[30,56],'Small lazy height increase is included rather than truncated');good(final.pixels.every((pixel,index)=>pixel===Math.floor(index/30)*1000+index%30),'Retried page has exact pixels without stale partial tiles');
  e=environment();response=await e.send({action:'startCapture',mode:'execute',tabId:3,windowId:7});good(!response.ok,'Unsupported operation rejected');
  e=environment();response=await e.send({action:'startCapture',mode:'full',tabId:3,windowId:7,delivery:'editor'});
  good(response.ok,'Browser editor capture completes');
  equal(e.saved.length,1,'A local PNG is retained');
  equal(e.native.length,0,'The Mac helper is not required to edit in Chrome');
  good(e.opened[0].url.includes('/editor.html#'),'Capture opens the extension editor');
  e=environment();await e.command('capture-visible');
  equal(e.saved[0].mode,'visible','Shortcut captures the visible tab');
  equal(e.native.length,0,'Shortcut does not open the Mac app automatically');
  good(e.opened[0].type==='popup'&&e.opened[0].url.includes('/result.html#'),'Shortcut opens the compact result');
  e=environment({changeTab:true});await e.command('capture-visible');
  equal(e.saved.length,0,'A tab change prevents saving unrelated pixels');
  equal(e.opened.length,0,'Failed shortcut does not open a stale result');
  console.log(`PASS: ${checks} worker orchestration/pixel checks (native, fractional DPR,1x, horizontal/vertical overlap, region, errors, tab switch, cancel, restore, memory bounds)`);
})().catch(error=>{console.error(error);process.exit(1);});
