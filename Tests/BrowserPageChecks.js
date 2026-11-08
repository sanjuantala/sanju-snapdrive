'use strict';
const fs=require('fs'),vm=require('vm'),assert=require('assert'),path=require('path');
let checks=0;
const elements=[{name:'fixed',position:'fixed',visibility:'visible',original:'color:red'},{name:'hidden-fixed',position:'fixed',visibility:'hidden',original:'visibility:hidden'},{name:'sticky',position:'sticky',visibility:'visible',original:null},{name:'plain',position:'static',visibility:'visible',original:null}].map(item=>({...item,isConnected:true,attribute:item.original,properties:{},getAttribute(){return this.attribute;},setAttribute(_,value){this.attribute=value;this.properties={};},removeAttribute(){this.attribute=null;this.properties={};},getBoundingClientRect(){return {left:0,top:0,right:100,bottom:20};}}));
for(const element of elements)element.style={setProperty(name,value){element.properties[name]=value;}};
let styleRemoved=false,scrollCalls=[],timers=[],fontsWaited=false;
const document={scrollingElement:{scrollWidth:300,scrollHeight:700,clientWidth:100,clientHeight:100},contentType:'text/html',fonts:{get ready(){fontsWaited=true;return Promise.resolve();}},images:[],createElement(name){assert.strictEqual(name,'style');return {textContent:'',remove(){styleRemoved=true;}};},head:{append(){}},querySelectorAll(){return elements;}};
const window={scrollTo(value){scrollCalls.push(value);context.scrollX=value.left;context.scrollY=value.top;}};
const context={window,document,scrollX:5,scrollY:12,innerWidth:117,innerHeight:100,getComputedStyle:element=>element,requestAnimationFrame:fn=>fn(),setTimeout(fn,delay){if(delay<=1000)queueMicrotask(fn);else timers.push(fn);return fn;},clearTimeout(){},console};
vm.createContext(context);vm.runInContext(fs.readFileSync(path.join(__dirname,'..','BrowserExtension','page-actions.js'),'utf8'),context);
(async()=>{
 const page=await context.snapPreparePage('one');assert.strictEqual(page.width,300);assert.strictEqual(page.height,700);checks+=2;assert(fontsWaited);checks++;
 assert.strictEqual(elements[2].properties.position,'relative');assert.strictEqual(elements[2].properties.top,'auto');checks+=2;
 let state=await context.snapScrollPage('one',100,400,true);assert.strictEqual(state.x,100);assert.strictEqual(state.y,400);assert.strictEqual(state.windowWidth,117);checks+=3;
 assert.strictEqual(elements[0].properties.visibility,'hidden');assert(!elements[1].properties.visibility);checks+=2;
 context.snapRestorePage('wrong');assert(window.__snapDrivePageCapture);checks++;
 context.snapRestorePage('one');assert(!window.__snapDrivePageCapture);assert(styleRemoved);assert.strictEqual(context.scrollX,5);assert.strictEqual(context.scrollY,12);checks+=4;
 for(const element of elements){assert.strictEqual(element.attribute,element.original);assert.strictEqual(Object.keys(element.properties).length,0);checks+=2;}
 await context.snapPreparePage('two');timers[timers.length-1]();assert(!window.__snapDrivePageCapture);checks++;
 await assert.rejects(()=>context.snapScrollPage('expired',0,0,false));checks++;
 await assert.rejects(()=>context.snapWarmPage('expired'));checks++;
 // A desktop-style web app may scroll its main panel while the root document fits.
 const root=document.scrollingElement;
 Object.assign(root,{scrollWidth:1200,scrollHeight:800,clientWidth:1200,clientHeight:800});context.innerWidth=1200;context.innerHeight=800;
 function panel(name,left,top,width,height){
  const result={name,position:'static',visibility:'visible',display:'block',overflowY:'auto',isConnected:true,attribute:'color:blue',properties:{},clientWidth:width,clientHeight:height,clientLeft:2,clientTop:2,scrollWidth:width,scrollHeight:2000,scrollLeft:0,scrollTop:123,calls:[],getAttribute(){return this.attribute;},setAttribute(_,value){this.attribute=value;this.properties={};},removeAttribute(){this.attribute=null;this.properties={};},getBoundingClientRect(){return {left,top,right:left+width+4,bottom:top+height+4};},scrollTo(value){this.scrollLeft=Math.max(0,Math.min(value.left,this.scrollWidth-this.clientWidth));this.scrollTop=Math.max(0,Math.min(value.top,this.scrollHeight-this.clientHeight));this.calls.push({x:this.scrollLeft,y:this.scrollTop});if(this.onScroll)this.onScroll();}};
  result.style={setProperty(key,value){result.properties[key]=value;}};return result;
 }
 const mainPanel=panel('main',200,80,900,650),smallPanel=panel('small',0,0,300,300),clippedPanel=panel('clipped',300,0,1000,700);
 mainPanel.position='fixed';
 const appShell=panel('shell',0,0,1200,800);appShell.overflowY='visible';appShell.position='fixed';appShell.contains=element=>element===mainPanel;
 document.querySelectorAll=()=>[...elements,smallPanel,clippedPanel,appShell,mainPanel];
 const main=await context.snapPreparePage('panel');
 assert.strictEqual(main.targetKind,'panel');assert.strictEqual(main.width,900);assert.strictEqual(main.height,2000);assert.strictEqual(main.viewportWidth,900);assert.strictEqual(main.viewportHeight,650);checks+=5;
 assert.strictEqual(main.sourceX,202);assert.strictEqual(main.sourceY,82);assert.strictEqual(main.windowWidth,1200);assert.strictEqual(main.windowHeight,800);checks+=4;
 const windowBefore={x:context.scrollX,y:context.scrollY};
 const panelScroll=await context.snapScrollPage('panel',0,400,true);
 assert.strictEqual(panelScroll.y,400);assert.strictEqual(panelScroll.sourceX,202);assert.strictEqual(context.scrollY,windowBefore.y);checks+=3;
 assert(!mainPanel.properties.visibility);assert(!appShell.properties.visibility);checks+=2;
 let grew=false,waitedImages=0;const listeners=new Map();
 const lazyImage={complete:false,getBoundingClientRect(){return {left:230,right:500,top:110,bottom:300};},addEventListener(name,fn){listeners.set(name,fn);if(name==='load')queueMicrotask(()=>{this.complete=true;waitedImages++;fn();});},removeEventListener(name){listeners.delete(name);}};
 mainPanel.onScroll=()=>{
  if(mainPanel.scrollTop>=650)document.images=[lazyImage];
  if(!grew&&mainPanel.scrollTop>=mainPanel.scrollHeight-mainPanel.clientHeight){grew=true;mainPanel.scrollHeight+=700;}
 };
 const warm=await context.snapWarmPage('panel');
 assert.strictEqual(warm.height,2700);assert.strictEqual(warm.y,0);assert.strictEqual(warm.sourceY,82);assert.strictEqual(warm.targetKind,'panel');checks+=4;
 assert(warm.warmSteps>=5&&warm.warmSteps<60);assert.strictEqual(warm.warmIncomplete,false);assert(mainPanel.calls.some(call=>call.y>=2050));checks+=3;
 assert(waitedImages>0);assert.strictEqual(listeners.size,0);checks+=2;
 context.snapRestorePage('panel');
 assert.strictEqual(mainPanel.scrollTop,123);assert.strictEqual(context.scrollX,windowBefore.x);assert.strictEqual(context.scrollY,windowBefore.y);assert(!window.__snapDrivePageCapture);checks+=4;
 // Incomplete/infinite feeds remain bounded instead of hanging a capture forever.
 document.images=[];mainPanel.onScroll=()=>{if(mainPanel.scrollTop>0)mainPanel.scrollHeight+=1000;};
 await context.snapPreparePage('infinite');const infinite=await context.snapWarmPage('infinite');
 assert.strictEqual(infinite.warmSteps,60);assert.strictEqual(infinite.warmIncomplete,true);assert.strictEqual(infinite.y,0);checks+=3;
 context.snapRestorePage('infinite');mainPanel.onScroll=null;
 // Scrolling documents take priority; a clipped or small panel is never substituted.
 root.scrollHeight=1600;let fallback=await context.snapPreparePage('document');
 assert.strictEqual(fallback.targetKind,'document');assert.strictEqual(fallback.sourceX,0);assert.strictEqual(fallback.sourceY,0);assert.strictEqual(fallback.height,1600);checks+=4;
 context.snapRestorePage('document');root.scrollHeight=800;document.querySelectorAll=()=>[...elements,smallPanel,clippedPanel];
 fallback=await context.snapPreparePage('clipped');assert.strictEqual(fallback.targetKind,'document');checks++;
 context.snapRestorePage('clipped');document.querySelectorAll=()=>elements;
 // Frozen selection blocks underlying wheel/key scrolling and removes its listeners on Esc.
 const windowEvents=new Map(),nodeEvents=new Map();let removed=false;
 window.addEventListener=(name,fn)=>windowEvents.set(name,fn);window.removeEventListener=name=>windowEvents.delete(name);
 document.documentElement={append(){}};
 document.createElement=name=>({style:{},setPointerCapture(){},attachShadow(){return {append(){}};},addEventListener(event,fn){if(name==='div'&&!nodeEvents.has(event))nodeEvents.set(event,fn);},remove(){removed=true;}});
 const selection=context.snapSelectRegion('data:image/png;base64,fixture','region');
 let prevented=0,stopped=0;const event={preventDefault(){prevented++;},stopImmediatePropagation(){stopped++;}};
 nodeEvents.get('wheel')(event);assert.strictEqual(prevented,1);assert.strictEqual(stopped,1);checks+=2;
 windowEvents.get('keydown')({...event,key:'PageDown'});assert.strictEqual(prevented,2);checks++;
 windowEvents.get('keydown')({...event,key:'Escape'});assert.strictEqual(await selection,null);assert(removed);assert(!windowEvents.has('keydown')&&!windowEvents.has('resize'));assert(!window.__snapDriveRegionCleanup);checks+=4;
 console.log(`PASS: ${checks} page preparation/restoration checks (main scroll panels, border-aware source crop, lazy growth/images, finite warm-up, root fallback, sticky/fixed, exact styles, watchdog, expired session, frozen selection)`);
})().catch(error=>{console.error(error);process.exit(1);});
