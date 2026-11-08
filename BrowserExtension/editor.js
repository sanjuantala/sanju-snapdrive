'use strict';
const core=SnapEditorCore,ui=SnapCaptureUI,$=id=>document.getElementById(id);
const canvas=$('canvas'),ctx=canvas.getContext('2d'),viewport=$('viewport'),status=$('status');
const tools=[
  ['select','Select','V','Select a mark to move or delete it.'],
  ['arrow','Arrow','A','Drag to point at a detail. Hold Shift for straight angles.'],
  ['text','Text','T','Click where the text should go. Click a text mark to edit.'],
  ['pen','Pen','P','Draw freehand directly on the screenshot.'],
  ['rectangle','Rectangle','R','Drag to outline a detail.'],
  ['ellipse','Ellipse','E','Drag to circle a detail.'],
  ['highlight','Highlight','I','Drag across the area you want to highlight.'],
  ['redact','Redact','X','Drag to cover sensitive pixels with an opaque block.'],
  ['crop','Crop','C','Draw a frame, then drag the handles or enter pixel insets.'],
  ['ocr','Copy text','O','Select text on the screenshot and choose Read text.'],
  ['hand','Hand','H','Drag to pan the canvas. Hold Space to pan with any tool.']
];
let entry,image,imageURL,history,tool='arrow',selected=null,gesture=null,textEdit=null,zoom=0,scale=1,repaint=0,exporting=false;
let spaceHeld=false,pan=null,selectionRect=null,reading=false;
const id=location.hash.slice(1), SVG='http://www.w3.org/2000/svg';
const list=$('tools');
const toolFamily={select:'navigate',hand:'navigate',crop:'refine',ocr:'refine',redact:'refine'};
const tints={select:'slate',hand:'blue',arrow:'violet',text:'blue',pen:'rose',rectangle:'indigo',ellipse:'mint',highlight:'amber',redact:'rose',crop:'violet',ocr:'mint'};
const shortLabel={rectangle:'Box',ellipse:'Oval',highlight:'Highlight',ocr:'Copy text'};
tools.forEach(([name,label,key]) => {
  const button=document.createElement('button');button.type='button';button.className='tool';
  button.dataset.tool=name;button.dataset.tint=tints[name];button.title=label+' ('+key+')';
  button.setAttribute('aria-label',label);button.setAttribute('aria-pressed','false');
  const tile=document.createElement('span');tile.className='tool-glyph';
  const icon=document.createElementNS(SVG,'svg'),use=document.createElementNS(SVG,'use');
  icon.setAttribute('aria-hidden','true');use.setAttribute('href','icons/toolkit.svg#'+name);icon.append(use);tile.append(icon);
  const caption=document.createElement('span');caption.className='tool-label';caption.textContent=shortLabel[name]||label;
  const shortcut=document.createElement('kbd');shortcut.setAttribute('aria-hidden','true');shortcut.textContent=key;
  button.append(tile,caption,shortcut);
  button.addEventListener('click',()=>setTool(name));$('tools-'+(toolFamily[name]||'annotate')).append(button);
});
const swatchList=[['Iris','#6141d3'],['Ocean','#2563ce'],['Mint','#168568'],['Amber','#f4b518'],['Coral','#ed4e62'],['Ink','#242136']];
const swatches=$('swatches'), colorInput=$('color');
function preference(name,fallback) { return localStorage.getItem('snapdrive.editor.'+name)||fallback; }
function savePreference(name,value) { localStorage.setItem('snapdrive.editor.'+name,value); }
$('width').value=preference('stroke','6');$('size').value=preference('font','32');
$('width').addEventListener('change',()=>{$('width').value=stroke();savePreference('stroke',$('width').value);});
$('size').addEventListener('change',()=>{$('size').value=fontSize();savePreference('font',$('size').value);});
for(const [name,hex] of swatchList) {
  const button=document.createElement('button');button.className='swatch';button.type='button';button.title=name;
  button.setAttribute('aria-label',name+' ink');button.dataset.color=hex;button.style.setProperty('--swatch',hex);
  button.addEventListener('click',()=>{colorInput.value=hex;updateColor();});
  swatches.append(button);
}
function colorKey(){return tool==='highlight'?'highlighter':'ink';}
function updateColor(){
  savePreference(colorKey(),colorInput.value);
  swatches.querySelectorAll('button').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.color===colorInput.value)));
}
colorInput.addEventListener('input',updateColor);
function styleControls(){
  const label=tools.find(item=>item[0]===tool)[1];
  const color=['arrow','text','pen','rectangle','ellipse','highlight'].includes(tool);
  $('style-panel').hidden=!color;
  $('style-title').textContent=label+' style';
  $('style-stroke').hidden=!color||tool==='text'||tool==='highlight';
  $('style-size').hidden=tool!=='text';
  colorInput.value=preference(colorKey(),tool==='highlight'?'#f4b518':'#6141d3');
  swatches.querySelectorAll('button').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.color===colorInput.value)));
}
function setTool(next) {
  commitText();
  if(next!==tool) {
    selectionRect=null;canvas.style.cursor='';
    $('read-result').hidden=true;
  }
  tool=next;canvas.dataset.tool=next;
  if(next!=='select'&&next!=='hand')selected=null;
  panCursor();
  list.querySelectorAll('button').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.tool===next)));
  $('hint').textContent=tools.find(item=>item[0]===next)[3];
  styleControls();schedule();
}
const selectionTools=new Set(['crop','ocr']);
const edgeFields=['w','n','e','s'];
function selectionUI() {
  $('selection-bar').hidden=!selectionTools.has(tool);
  if(!selectionTools.has(tool))return;
  $('selection-title').textContent=tool==='crop'?'Crop frame':'Text area';
  $('selection-size').textContent=selectionRect ? selectionRect.width+' × '+selectionRect.height+' px' : 'Drag to set a frame';
  $('selection-apply').textContent=tool==='crop'?'Apply crop':reading?'Reading…':'Read text';
  $('selection-apply').disabled=!selectionRect||reading;
  const insets=selectionRect ? core.selectionInsets(selectionRect,history.current.crop):{};
  for(const edge of edgeFields) {
    const field=$('inset-'+edge);field.disabled=!selectionRect||reading;
    if(document.activeElement!==field)field.value=insets[edge]??'';
  }
}
function sync() {
  if(!history)return;
  const {crop,marks}=history.current;
  $('meta').textContent=ui.modeName(entry.mode)+' · '+crop.width.toLocaleString()+' × '+crop.height.toLocaleString()+' px';
  $('undo').disabled=!history.canUndo;
  $('redo').disabled=!history.canRedo;
  $('delete').disabled=!marks.some(mark=>mark.id===selected);
  $('clear').disabled=!marks.length;
  ['mac','download','copy'].forEach(action=>$(action).disabled=exporting);
  selectionUI();
}
function schedule() {
  if(!repaint) repaint=requestAnimationFrame(()=>{repaint=0;draw();});
}
function draw() {
  if(!history)return;
  const doc=history.current,{crop}=doc;
  const fit=Math.min(1,Math.max(120,viewport.clientWidth-44)/crop.width);
  const shown=zoom||fit;
  const cssWidth=Math.max(1,Math.round(crop.width*shown)),cssHeight=Math.max(1,Math.round(crop.height*shown));
  canvas.style.width=cssWidth+'px';canvas.style.height=cssHeight+'px';
  // Keep long-page previews light. Exports render at native resolution separately.
  scale=Math.min(1,shown*devicePixelRatio,4096/Math.max(crop.width,crop.height),Math.sqrt(6000000/(crop.width*crop.height)));
  const w=Math.max(1,Math.ceil(crop.width*scale)),h=Math.max(1,Math.ceil(crop.height*scale));
  if(canvas.width!==w)canvas.width=w;
  if(canvas.height!==h)canvas.height=h;
  const moved=gesture?.type==='move'&&gesture.moved;
  const marks=moved?doc.marks.map(mark=>mark.id===selected?gesture.moved:mark):doc.marks;
  core.paint(ctx,image,{crop,marks},scale);
  if(gesture?.type==='draw')core.drawMark(ctx,gesture.mark);
  const chosen=marks.find(mark=>mark.id===selected);
  if(selectionTools.has(tool)) {
    const rect=gesture?.type==='region'&&gesture.edge==='new'?core.bounds(gesture.start,gesture.end):selectionRect;
    if(rect&&rect.width&&rect.height) {
      ctx.save();
      ctx.fillStyle='#19132e7d';
      ctx.beginPath();ctx.rect(crop.x,crop.y,crop.width,crop.height);ctx.rect(rect.x,rect.y,rect.width,rect.height);ctx.fill('evenodd');
      ctx.strokeStyle='#8465fb';ctx.lineWidth=2/shown;ctx.strokeRect(rect.x,rect.y,rect.width,rect.height);
      if(tool==='crop') {
        ctx.beginPath();ctx.lineWidth=1/shown;ctx.strokeStyle='#ffffffa0';
        for(const fraction of [1/3,2/3]) {
          ctx.moveTo(rect.x+rect.width*fraction,rect.y);ctx.lineTo(rect.x+rect.width*fraction,rect.y+rect.height);
          ctx.moveTo(rect.x,rect.y+rect.height*fraction);ctx.lineTo(rect.x+rect.width,rect.y+rect.height*fraction);
        }
        ctx.stroke();
      }
      ctx.fillStyle='#fff';ctx.strokeStyle='#6141d3';ctx.lineWidth=1.4/shown;
      for(const p of Object.values(core.handles(rect))) {
        ctx.beginPath();ctx.arc(p.x,p.y,4/shown,0,2*Math.PI);ctx.fill();ctx.stroke();
      }
      ctx.restore();
    }
  } else if(chosen) {
    const rect=core.frame(chosen,ctx),pad=5/shown;
    ctx.save();ctx.lineWidth=1.5/shown;ctx.strokeStyle='#6141d3';ctx.setLineDash([5/shown,4/shown]);ctx.strokeRect(rect.x-pad,rect.y-pad,rect.width+2*pad,rect.height+2*pad);ctx.restore();
  }
  $('fit').textContent=zoom?Math.round(zoom*100)+'%':'Fit · '+Math.round(fit*100)+'%';
  sync();
}
function commit(next) {history.commit(next);schedule();}
function pointer(event) {return core.point(canvas.getBoundingClientRect(),event.clientX,event.clientY,history.current.crop);}
function stroke() {return core.clamp(Number($('width').value)||6,1,100);}
function fontSize() {return core.clamp(Number($('size').value)||32,10,200);}
function beginText(point,mark=null) {
  commitText();
  textEdit={point,mark};$('draft').value=mark?.text||'';
  $('text-entry').hidden=false;$('draft').focus();$('draft').setSelectionRange($('draft').value.length,$('draft').value.length);
}
function commitText() {
  if(!textEdit||!history)return;
  const edit=textEdit, text=$('draft').value.trim();
  textEdit=null;$('text-entry').hidden=true;
  if(!text)return;
  const mark=edit.mark?{...edit.mark,text}:{id:crypto.randomUUID(),type:'text',a:edit.point,text,color:$('color').value,size:fontSize(),width:stroke()};
  const doc=history.current;
  commit({...doc,marks:edit.mark?doc.marks.map(item=>item.id===mark.id?mark:item):[...doc.marks,mark]});
}
function discardText(){textEdit=null;$('text-entry').hidden=true;canvas.focus({preventScroll:true});}
$('text-entry').addEventListener('submit',event=>{event.preventDefault();commitText();canvas.focus({preventScroll:true});});
$('discard-text').addEventListener('click',discardText);
$('draft').addEventListener('keydown',event=>{
  if(event.key==='Escape'){event.preventDefault();discardText();}
  if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();commitText();canvas.focus({preventScroll:true});}
});
document.addEventListener('pointerdown',event=>{if(textEdit&&!$('text-entry').contains(event.target))commitText();},true);
function panCursor() {
  viewport.dataset.pan=pan?'dragging':spaceHeld||tool==='hand'?'ready':'off';
}
function endPan(event) {
  if (!pan || (event && event.pointerId!==pan.pointer)) return;
  pan=null;panCursor();
}
viewport.addEventListener('pointerdown',event=>{
  if(!history||event.button!==0||gesture||(!spaceHeld&&tool!=='hand'))return;
  pan={pointer:event.pointerId,start:{x:event.clientX,y:event.clientY},origin:{x:viewport.scrollLeft,y:viewport.scrollTop}};
  viewport.setPointerCapture(event.pointerId);
  event.preventDefault();event.stopPropagation();panCursor();
},true);
viewport.addEventListener('pointermove',event=>{
  if(!pan||pan.pointer!==event.pointerId)return;
  const next=core.panOrigin(pan.origin,pan.start,{x:event.clientX,y:event.clientY},{x:viewport.scrollWidth-viewport.clientWidth,y:viewport.scrollHeight-viewport.clientHeight});
  viewport.scrollLeft=next.x;viewport.scrollTop=next.y;
});
for(const name of ['pointerup','pointercancel','lostpointercapture'])viewport.addEventListener(name,endPan);
window.addEventListener('blur',()=>{spaceHeld=false;endPan();panCursor();});
document.addEventListener('keyup',event=>{if(event.code==='Space'&&spaceHeld){spaceHeld=false;panCursor();}});
function markAt(point) {
  const shown=canvas.getBoundingClientRect().width/history.current.crop.width;
  return [...history.current.marks].reverse().find(mark=>core.hit(mark,point,7/shown,ctx));
}
canvas.addEventListener('pointerdown',event=>{
  if(!history||event.button!==0||gesture)return;
  const start=pointer(event);
  if(tool==='text') {
    event.preventDefault();
    const existing=markAt(start);
    if(existing?.type==='text')beginText(existing.a,existing);
    else beginText(start);
    return;
  }
  canvas.focus({preventScroll:true});canvas.setPointerCapture(event.pointerId);
  if(tool==='select') {
    const mark=markAt(start);selected=mark?.id||null;
    gesture=mark?{type:'move',start,mark,pointer:event.pointerId}:null;
  } else if(selectionTools.has(tool)) {
    if(reading)return;
    const tolerance=9/(canvas.getBoundingClientRect().width/history.current.crop.width);
    const edge=selectionRect && core.selectionHit(selectionRect,start,tolerance);
    gesture={type:'region',edge:edge||'new',before:selectionRect,start,end:start,pointer:event.pointerId};
    if(!edge)selectionRect=null;
    $('read-result').hidden=true;
  }
  else {
    const color=$('color').value;
    gesture={type:'draw',pointer:event.pointerId,mark:{id:crypto.randomUUID(),type:tool,a:start,b:start,color,width:stroke(),...(tool==='pen'?{points:[start]}:{})}};
  }
  event.preventDefault();schedule();
});
canvas.addEventListener('dblclick',event=>{
  if(!history||tool!=='select')return;
  const mark=markAt(pointer(event));
  if(mark?.type==='text'){gesture=null;beginText(mark.a,mark);}
});
function move(event) {
  if(!gesture||gesture.pointer!==event.pointerId) {
    if(!pan&&selectionTools.has(tool)&&selectionRect) {
      const edge=core.selectionHit(selectionRect,pointer(event),9/(canvas.getBoundingClientRect().width/history.current.crop.width));
      canvas.style.cursor=edge==='move'?'move':edge?edge+'-resize':'';
    }
    return;
  }
  if(gesture.type==='region' && event.type==='pointermove') {
    const bounds=viewport.getBoundingClientRect(), edge=24;
    viewport.scrollBy({
      left:event.clientX<bounds.left+edge?-14:event.clientX>bounds.right-edge?14:0,
      top:event.clientY<bounds.top+edge?-14:event.clientY>bounds.bottom-edge?14:0
    });
  }
  let end=pointer(event);
  if(gesture.type==='move') gesture.moved=core.shift(gesture.mark,end.x-gesture.start.x,end.y-gesture.start.y);
  if(gesture.type==='region') {
    gesture.end=end;
    if(gesture.edge!=='new')selectionRect=core.adjustSelection(gesture.before,gesture.edge,end.x-gesture.start.x,end.y-gesture.start.y,history.current.crop);
  }
  if(gesture.type==='draw') {
    const mark=gesture.mark;
    if(mark.type==='arrow'&&event.shiftKey) {
      const angle=Math.round(Math.atan2(end.y-mark.a.y,end.x-mark.a.x)/(Math.PI/4))*(Math.PI/4), length=core.distance(end,mark.a);
      const crop=history.current.crop,ux=Math.cos(angle),uy=Math.sin(angle);
      const bounded=Math.max(0,Math.min(length,ux>0?(crop.x+crop.width-mark.a.x)/ux:ux<0?(crop.x-mark.a.x)/ux:Infinity,uy>0?(crop.y+crop.height-mark.a.y)/uy:uy<0?(crop.y-mark.a.y)/uy:Infinity));
      end={x:mark.a.x+ux*bounded,y:mark.a.y+uy*bounded};
    }
    mark.b=end;
    if(mark.points && mark.points.length<2000 && core.distance(mark.points.at(-1),end)>1)mark.points.push(end);
  }
  schedule();
}
canvas.addEventListener('pointermove',move);
canvas.addEventListener('pointerup',event=>{
  if(gesture?.pointer!==event.pointerId)return;
  move(event);const g=gesture;gesture=null;
  const doc=history.current;
  if(g.type==='move'&&g.moved&&core.distance(g.mark.a,g.moved.a)>0.5)commit({...doc,marks:doc.marks.map(mark=>mark.id===g.mark.id?g.moved:mark)});
  if(g.type==='region'&&g.edge==='new')selectionRect=core.cropRect(g.start,g.end,doc.crop)||g.before;
  if(g.type==='draw') {
    const r=core.bounds(g.mark.a,g.mark.b);
    if(g.mark.points?.length>1|| (g.mark.type==='arrow'?core.distance(g.mark.a,g.mark.b)>=2:r.width>=2&&r.height>=2))commit({...doc,marks:[...doc.marks,g.mark]});
  }
  schedule();
});
function cancelGesture() {
  if(gesture?.type==='region')selectionRect=gesture.before;
  gesture=null;schedule();
}
canvas.addEventListener('pointercancel',cancelGesture);
canvas.addEventListener('lostpointercapture',()=>{if(gesture)cancelGesture();});
function deleteMark() {
  const doc=history?.current;
  if(!doc||!doc.marks.some(mark=>mark.id===selected))return;
  commit({...doc,marks:doc.marks.filter(mark=>mark.id!==selected)});selected=null;
}
function undo(redo=false) {commitText();if(!history)return;gesture=null;selected=null;selectionRect=null;canvas.style.cursor='';$('read-result').hidden=true;redo?history.redo():history.undo();schedule();}
$('undo').addEventListener('click',()=>undo());
$('redo').addEventListener('click',()=>undo(true));
$('delete').addEventListener('click',deleteMark);
$('clear').addEventListener('click',()=>{if(history?.current.marks.length){commit({...history.current,marks:[]});selected=null;}});
function changeZoom(factor) {
  if(!history)return;
  const current=canvas.getBoundingClientRect().width/history.current.crop.width;
  zoom=core.clamp(current*factor,.1,3);schedule();
}
$('minus').addEventListener('click',()=>changeZoom(1/1.25));
$('plus').addEventListener('click',()=>changeZoom(1.25));
$('fit').addEventListener('click',()=>{zoom=0;schedule();});
viewport.addEventListener('wheel',event=>{if(event.ctrlKey||event.metaKey){event.preventDefault();changeZoom(Math.exp(-event.deltaY*.008));}},{passive:false});
document.addEventListener('keydown',event=>{
  if(!history||event.target.matches?.('input,textarea,select,[contenteditable=true]'))return;
  const key=event.key.toLowerCase(),modifier=event.metaKey||event.ctrlKey;
  if(event.code==='Space'&&!modifier&&!event.altKey) {
    if(event.target.closest?.('button,a')&&!viewport.matches(':hover')&&tool!=='hand')return;
    event.preventDefault();spaceHeld=true;panCursor();return;
  }
  if(modifier&&key==='z'){event.preventDefault();undo(event.shiftKey);return;}
  if(modifier&&(key==='+'||key==='='||key==='-')){event.preventDefault();changeZoom(key==='-'?1/1.25:1.25);return;}
  if(modifier&&key==='0'){event.preventDefault();zoom=0;schedule();return;}
  if(modifier&&key==='s'){event.preventDefault();perform('download');return;}
  if(modifier&&key==='c'&&!window.getSelection()?.toString()){event.preventDefault();perform('copy');return;}
  if(modifier||event.altKey)return;
  if(selectionTools.has(tool)&&selectionRect&&['arrowleft','arrowright','arrowup','arrowdown'].includes(key)){
    event.preventDefault();const step=event.shiftKey?10:1;
    selectionRect=core.adjustSelection(selectionRect,'move',key==='arrowleft'?-step:key==='arrowright'?step:0,key==='arrowup'?-step:key==='arrowdown'?step:0,history.current.crop);
    schedule();return;
  }
  if(key==='delete'||key==='backspace'){event.preventDefault();deleteMark();}
  if(key==='escape'){if(pan||spaceHeld){endPan();spaceHeld=false;panCursor();return;}cancelGesture();setTool('select');}
  if(key==='enter'&&selectionTools.has(tool)&&selectionRect&&!event.target.closest?.('button')){event.preventDefault();applySelection();return;}
  const match=tools.find(item=>item[2].toLowerCase()===key);
  if(match)setTool(match[0]);
});
async function png(doc=history.current) {
  const {crop,marks}=doc;
  if(!marks.length&&crop.x===0&&crop.y===0&&crop.width===image.naturalWidth&&crop.height===image.naturalHeight)return entry.blob;
  const output=document.createElement('canvas');output.width=crop.width;output.height=crop.height;
  try {
    const context=output.getContext('2d');
    if(!context)throw new Error('Could not allocate the export. Crop to a smaller area.');
    core.paint(context,image,doc);
    return await new Promise((resolve,reject)=>output.toBlob(blob=>blob?resolve(blob):reject(new Error('Could not encode the image. Crop to a smaller area.')),'image/png'));
  } finally {output.width=1;output.height=1;}
}
for(const edge of edgeFields) $('inset-'+edge).addEventListener('change',event=>{
  if(!selectionRect||!event.target.value.trim())return;
  selectionRect=core.setInset(selectionRect,edge,Number(event.target.value),history.current.crop);
  event.target.value=core.selectionInsets(selectionRect,history.current.crop)[edge];schedule();
});
$('selection-cancel').addEventListener('click',()=>{cancelGesture();setTool('select');});
$('selection-apply').addEventListener('click',applySelection);
$('read-dismiss').addEventListener('click',()=>{$('read-result').hidden=true;});
$('read-copy').addEventListener('click',async ()=>{
  const text=$('recognized').value;
  if(!text.trim())return;
  try {await ui.copyText(text);ui.status(status,'Text copied. Ready to paste.','success');}
  catch(error){$('recognized').focus();$('recognized').select();ui.status(status,ui.failure(error),'error');}
});
async function applySelection() {
  if(!selectionRect||reading||gesture)return;
  const doc=history.current,rect=selectionRect;
  if(tool==='crop'){
    commit({...doc,crop:rect});setTool('select');viewport.scrollLeft=0;viewport.scrollTop=0;
    ui.status(status,'Crop applied. Undo to restore.','success');return;
  }
  if(tool!=='ocr')return;
  if(rect.width*rect.height>12000000||Math.max(rect.width,rect.height)>8192){
    ui.status(status,'Select a smaller area for sharper text recognition.','error');return;
  }
  reading=true;selectionUI();$('read-result').hidden=true;ui.status(status,'Reading selected text on this Mac…');
  try {
    const text=await ui.recognize(await png({...doc,crop:rect}));
    if(tool!=='ocr'||rect!==selectionRect||doc!==history.current)return;
    if(!text){ui.status(status,'No text found. Try a tighter selection.');return;}
    $('recognized').value=text;$('read-result').hidden=false;ui.status(status,'Text ready to review and copy.','success');
  } catch(error){if(tool==='ocr')ui.status(status,ui.failure(error),'error');}
  finally {reading=false;selectionUI();}
}
async function perform(action) {
  if(exporting||!history)return;
  commitText();exporting=true;sync();ui.status(status,action==='mac'?'Opening Mac editor…':'Preparing PNG…');
  try {
    const output=png();
    if(action==='copy'){await ui.copy(output);ui.status(status,'Copied. Paste it anywhere.','success');}
    if(action==='download'){ui.download(await output,entry.created);ui.status(status,'PNG downloaded.','success');}
    if(action==='mac'){await ui.openMac(await output);ui.status(status,'Opened in Mac App.','success');}
  } catch(error){ui.status(status,ui.failure(error),'error');}
  finally {exporting=false;sync();}
}
['mac','copy','download'].forEach(action=>$(action).addEventListener('click',()=>perform(action)));
new ResizeObserver(schedule).observe(viewport);
window.addEventListener('pagehide',()=>{if(imageURL)URL.revokeObjectURL(imageURL);});
(async()=>{
  try {
    entry=await SnapCaptureStore.get(id);
    if(!entry)throw new Error('This capture expired. Take a new screenshot to start editing.');
    image=new Image();imageURL=URL.createObjectURL(entry.blob);image.src=imageURL;await image.decode();
    history=core.history({crop:{x:0,y:0,width:image.naturalWidth,height:image.naturalHeight},marks:[]});
    $('empty').hidden=true;canvas.hidden=false;setTool('arrow');sync();
  } catch(error) { $('meta').textContent='No screenshot';$('empty').textContent=ui.failure(error); }
})();
