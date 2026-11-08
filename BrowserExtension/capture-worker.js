'use strict';
importScripts('capture-core.js', 'page-actions.js', 'capture-store.js');
const HOST = 'com.snapdrive.browser';
const MAX_PNG_BYTES = 40 * 1024 * 1024;
let activeSession = null, lastCaptureAt = 0, lastStatus = {busy:false, message:'', mode:null};
const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
function check(session) { if (session.cancelled || activeSession !== session) throw new Error('Capture cancelled.'); }
async function inject(session, func, args = []) {
  check(session);
  const results = await chrome.scripting.executeScript({target:{tabId:session.tabId}, func, args});
  check(session);
  if (!results.length || results[0].error) throw new Error(results[0]?.error || 'This page cannot be captured. Try Visible area.');
  return results[0].result;
}
async function ensureActive(session) {
  check(session);
  const tabs = await chrome.tabs.query({active:true, windowId:session.windowId});
  if (tabs[0]?.id !== session.tabId) throw new Error('The active tab changed. Return to the page and try again.');
}
async function screenshot(session) {
  await ensureActive(session);
  await wait(Math.max(0, 650 - (Date.now() - lastCaptureAt)));
  await ensureActive(session); lastCaptureAt = Date.now();
  const png = await chrome.tabs.captureVisibleTab(session.windowId, {format:'png'});
  await ensureActive(session);
  if (typeof png !== 'string' || !png.startsWith('data:image/png;base64,')) throw new Error('The browser did not return a PNG screenshot.');
  return png;
}
async function bitmap(png) { return createImageBitmap(await (await fetch(png)).blob()); }
async function progress(session, message, badge = '') {
  lastStatus = {busy:true, mode:session.mode, message, tabId:session.tabId};
  await chrome.action.setBadgeBackgroundColor({color:'#5937cf', tabId:session.tabId});
  await chrome.action.setBadgeText({text:badge, tabId:session.tabId});
}
function makeCanvas(width, height) {
  SnapCaptureCore.dimensions(width, height, 1, 1);
  const canvas = new OffscreenCanvas(width, height), context = canvas.getContext('2d', {alpha:false});
  if (!context) throw new Error('The browser could not create this image. Try a smaller capture.');
  context.imageSmoothingEnabled = false;
  return {canvas, context};
}
async function encode(canvas) {
  const blob = await canvas.convertToBlob({type:'image/png'});
  if (blob.size > MAX_PNG_BYTES) throw new Error('PNG exceeds 40 MB. Capture a smaller selected area.');
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = '';
  for (let offset=0; offset<bytes.length; offset+=32768) binary += String.fromCharCode(...bytes.subarray(offset, offset+32768));
  return 'data:image/png;base64,' + btoa(binary);
}
async function visible(session) {
  await progress(session, 'Capturing visible area…', '•');
  const png = await screenshot(session);
  const image = await bitmap(png);
  try { SnapCaptureCore.dimensions(image.width, image.height, 1, 1); } finally { image.close(); }
  if (png.length > Math.ceil(MAX_PNG_BYTES/3)*4+64) throw new Error('PNG exceeds 40 MB. Capture a smaller area.');
  return png;
}
async function selected(session) {
  await progress(session, 'Drag an area on the page. Esc cancels.', '▧');
  const png = await screenshot(session);
  // A frozen image is selected, so hover changes and animation cannot alter the selected pixels.
  const rect = await inject(session, snapSelectRegion, [png, session.token]);
  if (!rect) throw new Error('Selection cancelled.');
  const image = await bitmap(png);
  try {
    const crop = SnapCaptureCore.region(rect, rect.viewport, image.width, image.height);
    const {canvas, context} = makeCanvas(crop.width, crop.height);
    context.drawImage(image, crop.x, crop.y, crop.width, crop.height, 0, 0, crop.width, crop.height);
    return await encode(canvas);
  } finally { image.close(); }
}
async function fullPageAttempt(session) {
  let surface;
  try {
    await ensureActive(session);
    await inject(session, snapPreparePage, [session.token]);
    await progress(session, 'Loading page images…', '…');
    const page = await inject(session, snapWarmPage, [session.token]);
    await ensureActive(session);
    const plan = SnapCaptureCore.plan(page.width, page.height, page.viewportWidth, page.viewportHeight);
    let scaleX, scaleY, outputScaleX, outputScaleY, captured = 0;
    for (const tile of plan.tiles) {
      check(session); await ensureActive(session);
      const subject = page.targetKind === 'panel' ? 'panel' : 'page';
      await progress(session, `Capturing ${subject} ${captured+1}/${plan.tiles.length}… Keep this tab open.`, `${captured+1}/${plan.tiles.length}`);
      const state = await inject(session, snapScrollPage, [session.token, tile.x, tile.y, captured > 0]);
      if (Math.abs(state.viewportWidth-page.viewportWidth)>1 || Math.abs(state.viewportHeight-page.viewportHeight)>1 || Math.abs(state.windowWidth-page.windowWidth)>1 || Math.abs(state.windowHeight-page.windowHeight)>1) throw new Error('Browser size or zoom changed. Please try again.');
      if (Math.abs((state.sourceX||0)-(page.sourceX||0))>1 || Math.abs((state.sourceY||0)-(page.sourceY||0))>1) throw new Error('The scrolling panel moved. Let the page settle, then try again.');
      if (Math.abs(state.width-page.width)>1 || Math.abs(state.height-page.height)>1) {
        const error = new Error('The page keeps changing. Let it finish loading, then retry or use Selected area.');
        error.layoutChanged = true; throw error;
      }
      if (Math.abs(state.x-tile.x)>2 || Math.abs(state.y-tile.y)>2) throw new Error('This page blocks normal scrolling. Use Visible or Selected area.');
      const png = await screenshot(session), image = await bitmap(png);
      try {
        const nextScaleX=image.width/page.windowWidth, nextScaleY=image.height/page.windowHeight;
        if (!surface) {
          scaleX=nextScaleX; scaleY=nextScaleY;
          outputScaleX=session.resolution==='1x'?1:scaleX; outputScaleY=session.resolution==='1x'?1:scaleY;
          const dimensions=SnapCaptureCore.dimensions(page.width,page.height,outputScaleX,outputScaleY);
          surface=makeCanvas(dimensions.width,dimensions.height);
          if(session.resolution==='1x'){surface.context.imageSmoothingEnabled=true;surface.context.imageSmoothingQuality='high';}
        } else if (Math.abs(nextScaleX-scaleX)>0.002 || Math.abs(nextScaleY-scaleY)>0.002) throw new Error('Browser zoom changed. Please try again.');
        const p=SnapCaptureCore.placement(tile,state.x,state.y,scaleX,scaleY,outputScaleX,outputScaleY);
        p.sx += Math.round((state.sourceX||0)*scaleX);
        p.sy += Math.round((state.sourceY||0)*scaleY);
        if (p.sx+p.sw>image.width+1 || p.sy+p.sh>image.height+1) throw new Error('The capture area moved outside the browser. Please try again.');
        surface.context.drawImage(image,p.sx,p.sy,p.sw,p.sh,p.dx,p.dy,p.width,p.height);
      } finally { image.close(); }
      captured++;
    }
    await progress(session, 'Finishing PNG…', '…');
    return await encode(surface.canvas);
  } finally {
    // Release the large stitch surface as soon as it is encoded or abandoned.
    if(surface){surface.canvas.width=1;surface.canvas.height=1;}
    try { await chrome.scripting.executeScript({target:{tabId:session.tabId},func:snapRestorePage,args:[session.token]}); } catch (_) {}
  }
}
async function fullPage(session) {
  for(let attempt=0;attempt<2;attempt++){
    try {return await fullPageAttempt(session);}
    catch(error){
      if(!error.layoutChanged || attempt>0) throw error;
      check(session); await progress(session,'Page loaded more content. Retrying once…','↻');
    }
  }
}
function errorMessage(error) {
  const text=String(error?.message||error||'Capture failed.');
  if (/native messaging host|not found|forbidden|host has exited|disconnected/i.test(text)) return 'Connect the Mac app first: Image → Browser Extension… in Sanju’s SnapDrive.';
  if (/cannot access|extensions gallery|missing host permission|cannot be scripted|not allowed|chrome:\/\/|edge:\/\//i.test(text)) return 'This browser page blocks Full page and Selected area. Try Visible area or a normal website.';
  return text.slice(0,240);
}
async function run(message) {
  if (activeSession) return {ok:false,error:'A capture is already running. Cancel it or wait for it to finish.'};
  if (!['visible','region','full'].includes(message.mode) || !Number.isInteger(message.tabId) || !Number.isInteger(message.windowId)) return {ok:false,error:'Invalid capture request.'};
  if (message.delivery && !['editor','result','native'].includes(message.delivery)) return {ok:false,error:'Invalid capture destination.'};
  const session={...message,token:crypto.randomUUID(),cancelled:false}; activeSession=session;
  try {
    const png=await ({visible,region:selected,full:fullPage}[session.mode])(session);
    check(session);
    if (session.delivery === 'editor' || session.delivery === 'result') {
      await progress(session, 'Preparing your screenshot…', '…');
      check(session);
      const id = await SnapCaptureStore.put(await (await fetch(png)).blob(), session.mode);
      check(session);
      try {
        if (session.delivery === 'editor') await chrome.tabs.create({windowId:session.windowId,url:chrome.runtime.getURL('editor.html#'+id)});
        else await showResult(id);
        lastStatus={busy:false,mode:session.mode,message:'',success:true};
      } catch (_) {
        lastStatus={busy:false,mode:session.mode,message:'Screenshot ready. Open Latest capture.',success:true};
      }
    } else {
      // Compatibility with older popup clients while Chrome reloads the extension.
      await progress(session,'Opening native editor…','↗');
      const response=await chrome.runtime.sendNativeMessage(HOST,{version:1,action:'capture',png});
      if (!response?.ok) throw new Error(response?.error||'The Mac app could not open this capture.');
      lastStatus={busy:false,mode:session.mode,message:'Opened in SnapDrive. Ready to edit.',success:true};
    }
    await chrome.action.setBadgeText({text:'✓',tabId:session.tabId});
    setTimeout(()=>chrome.action.setBadgeText({text:'',tabId:session.tabId}).catch(()=>{}),4000);
    return {ok:true};
  } catch(error) {
    const message=errorMessage(error); lastStatus={busy:false,mode:session.mode,message,error:true};
    await chrome.action.setBadgeText({text:session.cancelled?'':'!',tabId:session.tabId}).catch(()=>{});
    return {ok:false,error:message};
  } finally {
    // A second cleanup is harmless, and covers cancellation while the selector was open.
    if(session.mode==='region') try {await chrome.scripting.executeScript({target:{tabId:session.tabId},func:snapCancelRegion});} catch(_){}
    if(activeSession===session) activeSession=null;
  }
}
async function showResult(id) {
  return chrome.windows.create({type:'popup',url:chrome.runtime.getURL('result.html#'+id),width:424,height:440,focused:true});
}
chrome.commands?.onCommand.addListener(async (command, tab) => {
  if (!['capture-visible','capture-region'].includes(command) || activeSession) return;
  const target = Number.isInteger(tab?.id) ? tab : (await chrome.tabs.query({active:true,lastFocusedWindow:true}))[0];
  if (!Number.isInteger(target?.id) || !Number.isInteger(target?.windowId)) return;
  await run({mode:command === 'capture-visible' ? 'visible' : 'region',tabId:target.id,windowId:target.windowId,delivery:'result'});
});
chrome.runtime.onMessage.addListener((message,sender,reply)=>{
  // Only extension pages may request capture; no page-external message listener exists.
  if(sender.id!==chrome.runtime.id) return false;
  if(message?.action==='status') {reply(lastStatus);return false;}
  if(message?.action==='showResult' && /^[0-9a-f-]{36}$/i.test(message.id || '')) {
    showResult(message.id).then(() => reply({ok:true}), () => reply({ok:false,error:'Could not open capture preview.'}));
    return true;
  }
  if(message?.action==='cancel') {
    if(activeSession) {activeSession.cancelled=true;if(activeSession.mode==='region') chrome.scripting.executeScript({target:{tabId:activeSession.tabId},func:snapCancelRegion}).catch(()=>{});}
    reply({ok:true});return false;
  }
  if(message?.action==='startCapture') {
    const wasBusy=Boolean(activeSession),operation=run(message);
    if(!wasBusy && message.detach===true && message.mode==='region' && activeSession?.tabId===message.tabId && !activeSession.cancelled) {
      // Acknowledge receipt before the popup closes; selection continues in this worker.
      reply({ok:true,started:true}); operation.catch(()=>{}); return false;
    }
    operation.then(reply);return true;
  }
  return false;
});
chrome.tabs.onRemoved.addListener(tabId=>{if(activeSession?.tabId===tabId) activeSession.cancelled=true;});
