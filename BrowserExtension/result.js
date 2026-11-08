'use strict';
const id=location.hash.slice(1), ui=SnapCaptureUI;
const byId=id=>document.getElementById(id), status=byId('status'), preview=byId('preview');
let entry,url;
async function load() {
  try {
    entry=await SnapCaptureStore.get(id);
    if (!entry) throw new Error('This preview expired. Capture a new screenshot.');
    url=URL.createObjectURL(entry.blob); preview.src=url; preview.hidden=false;
    await preview.decode();
    byId('meta').textContent=ui.modeName(entry.mode)+' · '+preview.naturalWidth+' × '+preview.naturalHeight+' px';
    ['copy','edit','mac','download'].forEach(action => byId(action).disabled=false);
    if (document.activeElement === document.body) byId('copy').focus();
  } catch(error) {byId('meta').textContent='No screenshot available';ui.status(status,ui.failure(error),'error');}
}
byId('copy').addEventListener('click',async () => {
  try {await ui.copy(entry.blob); ui.status(status,'Copied. Paste it anywhere.','success');byId('copy').lastChild.textContent=' Copied';}
  catch(error){ui.status(status,ui.failure(error),'error');}
});
byId('edit').addEventListener('click',async () => {
  try {
    const current=await chrome.windows.getCurrent();
    await chrome.tabs.create({url:chrome.runtime.getURL('editor.html#'+id),...(current.type==='popup'?{windowId:(await chrome.windows.getLastFocused({windowTypes:['normal']})).id}:{})});
    if(current.type==='popup') window.close();
  } catch (_) {
    // A normal browser window is not guaranteed to exist.
    location.replace(chrome.runtime.getURL('editor.html#'+id));
  }
});
byId('mac').addEventListener('click',async () => {
  byId('mac').disabled=true;
  try {ui.status(status,'Opening Mac editor…');await ui.openMac(entry.blob);ui.status(status,'Opened in Mac App.','success');}
  catch(error){ui.status(status,ui.failure(error),'error');}
  finally {byId('mac').disabled=false;}
});
byId('download').addEventListener('click',() => ui.download(entry.blob,entry.created));
window.addEventListener('pagehide',() => {if(url)URL.revokeObjectURL(url);});
load();
