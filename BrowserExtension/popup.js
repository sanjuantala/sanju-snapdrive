'use strict';
const buttons=Array.from(document.querySelectorAll('[data-mode]'));
const status=document.getElementById('status'), cancel=document.getElementById('cancel');
let pending=false;
function display(state) {
  const busy=Boolean(state?.busy)||pending;
  buttons.forEach(button=>button.disabled=busy); cancel.hidden=!busy;
  if(state?.message) status.textContent=state.message;
  status.className=state?.error?'error':state?.success?'success':'';
  if(state?.error && /connect|connection/i.test(state.message)) document.getElementById('setup').open=true;
}
async function capture(mode) {
  if(pending) return; pending=true; display({busy:true,message:'Preparing capture…'});
  try {
    const [tab]=await chrome.tabs.query({active:true,currentWindow:true});
    if(!Number.isInteger(tab?.id)||!Number.isInteger(tab?.windowId)) throw new Error('No active browser tab.');
    const result=await chrome.runtime.sendMessage({action:'startCapture',mode,tabId:tab.id,windowId:tab.windowId,resolution:document.getElementById('resolution').value,detach:mode==='region'});
    if(result?.started){pending=false;window.close();return;}
    pending=false; display(result?.ok?{success:true,message:'Opened in SnapDrive. Ready to edit.'}:{error:true,message:result?.error||'Capture could not finish. Please try again.'});
  } catch(error) {pending=false;display({error:true,message:String(error?.message||error)});}
}
buttons.forEach(button=>button.addEventListener('click',()=>capture(button.dataset.mode)));
cancel.addEventListener('click',async()=>{await chrome.runtime.sendMessage({action:'cancel'});status.textContent='Cancelling… Restoring the page.';});
async function update() {try{const state=await chrome.runtime.sendMessage({action:'status'});if(state?.busy||!pending) display(state);}catch(_){} }
update(); setInterval(update,700);
