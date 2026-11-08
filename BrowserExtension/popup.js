'use strict';
const byId = id => document.getElementById(id);
const buttons = [...document.querySelectorAll('[data-mode]')];
const status = byId('status'), cancel = byId('cancel'), settings = byId('settings'), setup = byId('setup');
let pending = false, latestId = null;
const resolution = byId('resolution');
resolution.value = localStorage.getItem('snapdrive.fullPageQuality') === '1x' ? '1x' : 'native';
resolution.addEventListener('change', () => localStorage.setItem('snapdrive.fullPageQuality', resolution.value));
settings.addEventListener('click', () => {
  setup.hidden = !setup.hidden;
  settings.setAttribute('aria-expanded', String(!setup.hidden));
});
byId('shortcuts').addEventListener('click', () => chrome.tabs.create({url:'chrome://extensions/shortcuts'}));
byId('latest').addEventListener('click', async () => {
  if (latestId) await chrome.runtime.sendMessage({action:'showResult',id:latestId});
  window.close();
});
function display(state) {
  const busy = Boolean(state?.busy) || pending;
  buttons.forEach(button => button.disabled = busy);
  byId('latest').disabled = busy || !latestId;
  cancel.hidden = !busy;
  status.hidden = !state?.message;
  status.textContent = state?.message || '';
  status.className = 'status' + (state?.error ? ' error' : state?.success ? ' success' : '');
}
async function capture(mode) {
  if (pending) return;
  pending = true; display({busy:true,message:'Preparing capture…'});
  try {
    const [tab] = await chrome.tabs.query({active:true,currentWindow:true});
    if (!Number.isInteger(tab?.id) || !Number.isInteger(tab?.windowId)) throw new Error('No active browser tab.');
    const result = await chrome.runtime.sendMessage({action:'startCapture',mode,tabId:tab.id,windowId:tab.windowId,resolution:resolution.value,delivery:'editor',detach:mode==='region'});
    pending = false;
    if (result?.started || result?.ok) { window.close(); return; }
    display({error:true,message:result?.error || 'Capture did not finish. Try again.'});
  } catch(error) { pending = false; display({error:true,message:error.message}); }
}
buttons.forEach(button => button.addEventListener('click', () => capture(button.dataset.mode)));
cancel.addEventListener('click', async () => {
  await chrome.runtime.sendMessage({action:'cancel'});
  display({busy:true,message:'Cancelling capture…'});
});
async function update() {
  try { const state = await chrome.runtime.sendMessage({action:'status'}); if (state?.busy || !pending) display(state); } catch (_) {}
}
SnapCaptureStore.latest().then(entry => { latestId = entry?.id || null; update(); }, update);
update(); setInterval(update,700);
