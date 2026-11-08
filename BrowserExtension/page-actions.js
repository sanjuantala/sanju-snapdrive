/* Each function is injected into the active tab's isolated world; no page code is evaluated. */
async function snapPreparePage(token) {
  if (window.__snapDrivePageCapture?.cleanup) window.__snapDrivePageCapture.cleanup();
  const root = document.scrollingElement || document.documentElement;
  if (!root || document.contentType === 'application/pdf') throw new Error('Use Visible area for this page.');
  const original = {x: scrollX, y: scrollY};
  const style = document.createElement('style');
  style.textContent = '*{scroll-behavior:auto!important;scroll-snap-type:none!important;animation-play-state:paused!important;transition:none!important}html,body{scroll-behavior:auto!important}';
  (document.head || document.documentElement).append(style);
  const changed = [], fixed = [];
  const rootFits = root.scrollHeight <= root.clientHeight + 2 && root.scrollWidth <= root.clientWidth + 2;
  let target = root, targetArea = 0, visited = 0;
  for (const element of document.querySelectorAll('*')) {
    if (++visited > 30000) break;
    const computed = getComputedStyle(element), position = computed.position;
    if (rootFits && element !== root && element !== document.body && /^(auto|scroll|overlay)$/.test(computed.overflowY) && element.scrollHeight > element.clientHeight + 2 && computed.visibility !== 'hidden' && computed.display !== 'none') {
      const r = element.getBoundingClientRect(), area = element.clientWidth * element.clientHeight;
      if (area >= innerWidth * innerHeight * 0.5 && area > targetArea && r.left >= -0.5 && r.top >= -0.5 && r.right <= innerWidth + 0.5 && r.bottom <= innerHeight + 0.5) { target = element; targetArea = area; }
    }
    if (position === 'fixed' || position === 'sticky') {
      changed.push([element, element.getAttribute('style')]);
      if (position === 'fixed' && computed.visibility === 'visible') fixed.push(element);
      else { element.style.setProperty('position', 'relative', 'important'); for (const edge of ['top','bottom','left','right']) element.style.setProperty(edge, 'auto', 'important'); }
    }
  }
  const targetKind = target === root ? 'document' : 'panel';
  // App shells and the scroll panel itself may be fixed. Hiding either would
  // blank every tile after the first; only unrelated floating content is hidden.
  const floating = targetKind === 'panel' ? fixed.filter(element => element !== target && !element.contains?.(target)) : fixed;
  const targetOriginal = {x: target.scrollLeft || 0, y: target.scrollTop || 0};
  let timer;
  const cleanup = () => {
    clearTimeout(timer);
    for (const [element, value] of changed) if (element.isConnected) { if (value === null) element.removeAttribute('style'); else element.setAttribute('style', value); }
    style.remove();
    if (targetKind === 'panel' && target.isConnected !== false) target.scrollTo({left: targetOriginal.x, top: targetOriginal.y, behavior: 'instant'});
    window.scrollTo({left: original.x, top: original.y, behavior: 'instant'});
    if (window.__snapDrivePageCapture?.token === token) delete window.__snapDrivePageCapture;
  };
  timer = setTimeout(cleanup, 120000);
  window.__snapDrivePageCapture = {token, original, targetOriginal, target, targetKind, fixed:floating, changed, cleanup};
  const fonts = document.fonts?.ready;
  if (fonts) await Promise.race([fonts, new Promise(resolve => setTimeout(resolve, 1000))]);
  const rect = targetKind === 'panel' ? target.getBoundingClientRect() : {left:0,top:0};
  return {x: targetKind === 'panel' ? target.scrollLeft : scrollX, y: targetKind === 'panel' ? target.scrollTop : scrollY, width: Math.max(target.scrollWidth, target.clientWidth), height: Math.max(target.scrollHeight, target.clientHeight), viewportWidth: target.clientWidth, viewportHeight: target.clientHeight, windowWidth: innerWidth, windowHeight: innerHeight, sourceX: rect.left + (targetKind === 'panel' ? target.clientLeft || 0 : 0), sourceY: rect.top + (targetKind === 'panel' ? target.clientTop || 0 : 0), targetKind, original};
}
async function snapScrollPage(token, x, y, hideFixed) {
  const state = window.__snapDrivePageCapture;
  if (!state || state.token !== token || state.target.isConnected === false) throw new Error('Capture session ended. Please try again.');
  for (const element of state.fixed) element.style.setProperty('visibility', hideFixed ? 'hidden' : 'visible', 'important');
  if (state.targetKind === 'panel') state.target.scrollTo({left:x,top:y,behavior:'instant'});
  else window.scrollTo({left:x,top:y,behavior:'instant'});
  await Promise.race([new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))),new Promise(resolve => setTimeout(resolve,500))]);
  const r = state.targetKind === 'panel' ? state.target.getBoundingClientRect() : {left:0,top:0};
  let sourceX = r.left + (state.targetKind === 'panel' ? state.target.clientLeft || 0 : 0), sourceY = r.top + (state.targetKind === 'panel' ? state.target.clientTop || 0 : 0);
  const visibleImages = Array.from(document.images).filter(image => !image.complete && (() => {const r = image.getBoundingClientRect(); return r.bottom > sourceY && r.top < sourceY + state.target.clientHeight && r.right > sourceX && r.left < sourceX + state.target.clientWidth;})());
  if (visibleImages.length) await Promise.race([Promise.all(visibleImages.map(image => new Promise(resolve => {image.addEventListener('load', resolve, {once:true}); image.addEventListener('error', resolve, {once:true});}))), new Promise(resolve => setTimeout(resolve, 700))]);
  await new Promise(resolve => setTimeout(resolve, 120));
  if (window.__snapDrivePageCapture !== state) throw new Error('Capture session ended. Please try again.');
  const target = state.target;
  const finalRect = state.targetKind === 'panel' ? target.getBoundingClientRect() : {left:0,top:0};
  sourceX = finalRect.left + (state.targetKind === 'panel' ? target.clientLeft || 0 : 0); sourceY = finalRect.top + (state.targetKind === 'panel' ? target.clientTop || 0 : 0);
  return {x: state.targetKind === 'panel' ? target.scrollLeft : scrollX, y: state.targetKind === 'panel' ? target.scrollTop : scrollY, width: Math.max(target.scrollWidth,target.clientWidth), height: Math.max(target.scrollHeight,target.clientHeight), viewportWidth: target.clientWidth, viewportHeight: target.clientHeight, windowWidth: innerWidth, windowHeight: innerHeight, sourceX, sourceY, targetKind:state.targetKind};
}
async function snapWarmPage(token) {
  const state = window.__snapDrivePageCapture;
  if (!state || state.token !== token) throw new Error('Capture session ended. Please try again.');
  const deadline = Date.now() + 8000, target = state.target;
  const measure = () => {
    const r = state.targetKind === 'panel' ? target.getBoundingClientRect() : {left:0,top:0};
    return {x:state.targetKind === 'panel' ? target.scrollLeft : scrollX,y:state.targetKind === 'panel' ? target.scrollTop : scrollY,width:Math.max(target.scrollWidth,target.clientWidth),height:Math.max(target.scrollHeight,target.clientHeight),viewportWidth:target.clientWidth,viewportHeight:target.clientHeight,windowWidth:innerWidth,windowHeight:innerHeight,sourceX:r.left+(state.targetKind === 'panel' ? target.clientLeft || 0:0),sourceY:r.top+(state.targetKind === 'panel' ? target.clientTop || 0:0),targetKind:state.targetKind};
  };
  const scroll = y => state.targetKind === 'panel' ? target.scrollTo({left:0,top:y,behavior:'instant'}) : window.scrollTo({left:0,top:y,behavior:'instant'});
  const pause = milliseconds => new Promise(resolve => setTimeout(resolve,Math.max(0,Math.min(milliseconds,deadline-Date.now()))));
  if (document.fonts?.ready) await Promise.race([document.fonts.ready,pause(300)]);
  let y=0,steps=0,bottomPasses=0,lastHeight=-1,completed=false;
  while (steps<60 && Date.now()<deadline) {
    if (window.__snapDrivePageCapture !== state || target.isConnected === false) throw new Error('Capture session ended. Please try again.');
    scroll(y);steps++;
    await Promise.race([new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))),pause(500)]);
    await pause(65);
    let geometry=measure();
    const images=Array.from(document.images).filter(image => !image.complete && (() => {const r=image.getBoundingClientRect();return r.bottom>geometry.sourceY && r.top<geometry.sourceY+geometry.viewportHeight && r.right>geometry.sourceX && r.left<geometry.sourceX+geometry.viewportWidth;})());
    if (images.length) {
      const listeners=[];
      await Promise.race([Promise.all(images.map(image=>new Promise(resolve=>{const done=()=>resolve();listeners.push([image,done]);image.addEventListener('load',done,{once:true});image.addEventListener('error',done,{once:true});}))),pause(300)]);
      for (const [image,done] of listeners) {image.removeEventListener?.('load',done);image.removeEventListener?.('error',done);}
    }
    geometry=measure();
    const bottom=Math.max(0,geometry.height-geometry.viewportHeight),actual=geometry.y || 0;
    if (actual>=bottom-1) {
      await pause(100);geometry=measure();
      if (geometry.height===lastHeight) bottomPasses++; else bottomPasses=0;
      if (bottomPasses>=1) {completed=true;break;}
    } else bottomPasses=0;
    lastHeight=geometry.height;
    y=Math.min(actual+Math.max(1,geometry.viewportHeight),Math.max(0,geometry.height-geometry.viewportHeight));
  }
  if (window.__snapDrivePageCapture !== state || target.isConnected === false) throw new Error('Capture session ended. Please try again.');
  scroll(0);
  await Promise.race([new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))),pause(200)]);
  return {...measure(),warmSteps:steps,warmIncomplete:!completed};
}
function snapRestorePage(token) {
  if (window.__snapDrivePageCapture?.token === token) window.__snapDrivePageCapture.cleanup();
}
function snapSelectRegion(png, token) {
  return new Promise(resolve => {
    if (window.__snapDriveRegionCleanup) window.__snapDriveRegionCleanup();
    const host = document.createElement('div');
    host.style.cssText = `position:fixed!important;left:0!important;top:0!important;width:${innerWidth}px!important;height:${innerHeight}px!important;z-index:2147483647!important;cursor:crosshair!important;touch-action:none!important`;
    const shadow = host.attachShadow({mode:'closed'});
    const image = document.createElement('img'); image.src = png; image.draggable = false;
    image.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;object-fit:fill;pointer-events:none;user-select:none';
    const dim = document.createElement('div'); dim.style.cssText = 'position:absolute;inset:0;background:#08071155;pointer-events:none';
    const box = document.createElement('div'); box.style.cssText = 'position:absolute;border:2px solid #bbaaff;box-sizing:border-box;box-shadow:0 0 0 1px #211934;pointer-events:none;display:none';
    const help = document.createElement('div'); help.textContent = 'Drag to select an area · Esc to cancel'; help.style.cssText = 'position:absolute;top:18px;left:50%;transform:translateX(-50%);font:600 13px -apple-system,sans-serif;background:#201b31;color:white;padding:12px 18px;border:1px solid #bbaaff66;border-radius:12px;pointer-events:none';
    shadow.append(image,dim,box,help); document.documentElement.append(host);
    let start, done = false, timer;
    const stop = (result = null) => { if (done) return; done = true; clearTimeout(timer); host.remove(); window.removeEventListener('keydown', key, true); window.removeEventListener('resize', resized); delete window.__snapDriveRegionCleanup; resolve(result); };
    const key = event => {
      if (event.key === 'Escape') {event.preventDefault(); event.stopImmediatePropagation(); stop();}
      else if ([' ', 'Spacebar', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'PageUp', 'PageDown', 'Home', 'End'].includes(event.key)) {event.preventDefault(); event.stopImmediatePropagation();}
    };
    host.addEventListener('wheel', event => {event.preventDefault();event.stopImmediatePropagation();}, {passive:false});
    host.addEventListener('touchmove', event => {event.preventDefault();event.stopImmediatePropagation();}, {passive:false});
    const resized = () => stop();
    window.addEventListener('keydown', key, true); window.addEventListener('resize', resized);
    window.__snapDriveRegionCleanup = stop;
    timer = setTimeout(stop, 90000);
    host.addEventListener('pointerdown', event => {if(event.button !== 0) return; event.preventDefault(); event.stopImmediatePropagation(); start={x:event.clientX,y:event.clientY}; host.setPointerCapture(event.pointerId); box.style.display='block';});
    host.addEventListener('pointermove', event => {if(!start) return; event.preventDefault(); const left=Math.min(start.x,event.clientX),top=Math.min(start.y,event.clientY); Object.assign(box.style,{left:left+'px',top:top+'px',width:Math.abs(event.clientX-start.x)+'px',height:Math.abs(event.clientY-start.y)+'px'});});
    host.addEventListener('pointerup', event => {if(!start) return; event.preventDefault(); event.stopImmediatePropagation(); stop({token,x:Math.min(start.x,event.clientX),y:Math.min(start.y,event.clientY),width:Math.abs(event.clientX-start.x),height:Math.abs(event.clientY-start.y),viewport:{width:innerWidth,height:innerHeight}});});
    host.addEventListener('pointercancel', () => stop());
  });
}
function snapCancelRegion() { window.__snapDriveRegionCleanup?.(); }
