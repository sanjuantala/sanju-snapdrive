'use strict';
(function(root) {
  function failure(error) {
    const text=String(error?.message || error || 'Try again.');
    return /native messaging host|not found|forbidden|host has exited|disconnected/i.test(text)
      ? 'Connect the Mac app: Image › Browser Extension…'
      : text.slice(0,240);
  }
  function dataURL(blob) {
    return new Promise((resolve,reject) => {
      const reader=new FileReader();
      reader.onload=() => resolve(reader.result);
      reader.onerror=() => reject(reader.error);
      reader.readAsDataURL(blob);
    });
  }
  async function openMac(blob) {
    if (blob.size > SnapCaptureStore.MAX_BYTES) throw new Error('The Mac app accepts PNGs up to 40 MB. Crop the screenshot first.');
    const response=await chrome.runtime.sendNativeMessage('com.snapdrive.browser',{version:1,action:'capture',png:await dataURL(blob)});
    if (!response?.ok) throw new Error(response?.error || 'The Mac app could not open this screenshot.');
  }
  async function recognize(blob) {
    if (blob.size > SnapCaptureStore.MAX_BYTES) throw new Error('Select a smaller area to read text.');
    const result=await chrome.runtime.sendNativeMessage('com.snapdrive.browser',{version:1,action:'recognize',png:await dataURL(blob)});
    if (!result?.ok) throw new Error(/unsupported browser request/i.test(result?.error || '')?'Update the SnapDrive Mac app to use Copy text.':result?.error || 'Could not read text.');
    return typeof result.text==='string' ? result.text.trim() : '';
  }
  function copyText(text) {
    if (!navigator.clipboard?.writeText) throw new Error('Select the text and use your keyboard copy shortcut.');
    return navigator.clipboard.writeText(text);
  }
  function copy(png) {
    if (!navigator.clipboard?.write || typeof ClipboardItem === 'undefined') throw new Error('Clipboard is unavailable. Download the PNG instead.');
    // Start during the button click, even when the edited PNG still needs encoding.
    return navigator.clipboard.write([new ClipboardItem({'image/png':png})]);
  }
  function download(blob, date) {
    const url=URL.createObjectURL(blob), link=document.createElement('a');
    link.href=url; link.download='SnapDrive-'+new Date(date).toISOString().slice(0,19).replace(/:/g,'-')+'.png';
    link.click(); setTimeout(() => URL.revokeObjectURL(url),1000);
  }
  function modeName(mode) { return ({visible:'Visible tab',region:'Selected area',full:'Full page'})[mode] || 'Screenshot'; }
  function status(node, message, type='') {
    node.className='status'+(type ? ' '+type : '');
    node.textContent=message;
  }
  root.SnapCaptureUI={failure,openMac,recognize,copyText,copy,download,modeName,status};
})(globalThis);
