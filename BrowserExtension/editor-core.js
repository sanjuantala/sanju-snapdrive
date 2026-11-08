'use strict';
(function(root) {
  const clamp=(n,min,max) => Math.min(max,Math.max(min,n));
  function bounds(a,b) {return {x:Math.min(a.x,b.x),y:Math.min(a.y,b.y),width:Math.abs(a.x-b.x),height:Math.abs(a.y-b.y)};}
  function point(rect, clientX, clientY, crop) {
    return {x:crop.x+clamp((clientX-rect.left)/rect.width,0,1)*crop.width,y:crop.y+clamp((clientY-rect.top)/rect.height,0,1)*crop.height};
  }
  function panOrigin(origin,start,end,limit) {
    return {x:clamp(origin.x+start.x-end.x,0,Math.max(0,limit.x)),y:clamp(origin.y+start.y-end.y,0,Math.max(0,limit.y))};
  }
  function cropRect(a,b,clip) {
    const r=bounds(a,b), x=clamp(Math.round(r.x),clip.x,clip.x+clip.width), y=clamp(Math.round(r.y),clip.y,clip.y+clip.height);
    const right=clamp(Math.round(r.x+r.width),x,clip.x+clip.width), bottom=clamp(Math.round(r.y+r.height),y,clip.y+clip.height);
    return right-x>=2 && bottom-y>=2 ? {x,y,width:right-x,height:bottom-y} : null;
  }
  function handles(r) {
    const l=r.x,t=r.y,b=r.y+r.height,z=r.x+r.width,x=(l+z)/2,y=(t+b)/2;
    return {nw:{x:l,y:t},ne:{x:z,y:t},sw:{x:l,y:b},se:{x:z,y:b},n:{x,y:t},s:{x,y:b},w:{x:l,y},e:{x:z,y}};
  }
  function selectionHit(r,p,tolerance) {
    for (const [key,point] of Object.entries(handles(r))) if (distance(p,point)<=tolerance) return key;
    return p.x>=r.x&&p.x<=r.x+r.width&&p.y>=r.y&&p.y<=r.y+r.height?'move':null;
  }
  function adjustSelection(r,edge,dx,dy,limit) {
    if (edge==='move') return {...r,x:clamp(Math.round(r.x+dx),limit.x,limit.x+limit.width-r.width),y:clamp(Math.round(r.y+dy),limit.y,limit.y+limit.height-r.height)};
    let l=r.x,t=r.y,z=r.x+r.width,b=r.y+r.height;
    if(edge.includes('w'))l=clamp(Math.round(l+dx),limit.x,z-2);
    if(edge.includes('e'))z=clamp(Math.round(z+dx),l+2,limit.x+limit.width);
    if(edge.includes('n'))t=clamp(Math.round(t+dy),limit.y,b-2);
    if(edge.includes('s'))b=clamp(Math.round(b+dy),t+2,limit.y+limit.height);
    return {x:l,y:t,width:z-l,height:b-t};
  }
  function selectionInsets(r,limit) {
    return {w:r.x-limit.x,n:r.y-limit.y,e:limit.x+limit.width-r.x-r.width,s:limit.y+limit.height-r.y-r.height};
  }
  function setInset(r,edge,value,limit) {
    if(!Number.isFinite(value))return r;
    const delta=value-selectionInsets(r,limit)[edge];
    return adjustSelection(r,edge,edge==='w'?delta:edge==='e'?-delta:0,edge==='n'?delta:edge==='s'?-delta:0,limit);
  }
  function distance(a,b) {return Math.hypot(a.x-b.x,a.y-b.y);}
  function segmentDistance(p,a,b) {
    const dx=b.x-a.x,dy=b.y-a.y,len=dx*dx+dy*dy;
    const t=len ? clamp(((p.x-a.x)*dx+(p.y-a.y)*dy)/len,0,1) : 0;
    return distance(p,{x:a.x+t*dx,y:a.y+t*dy});
  }
  function arrow(a,b,width) {
    const length=distance(a,b);
    if(length<1) return null;
    const ux=(b.x-a.x)/length,uy=(b.y-a.y)/length;
    const head=Math.min(length*.58,Math.max(10,width*3.8)), spread=Math.min(head*.52,Math.max(5,width*1.75));
    const stem={x:b.x-ux*head*.7,y:b.y-uy*head*.7};
    const base={x:b.x-ux*head,y:b.y-uy*head};
    return {stem,left:{x:base.x-uy*spread,y:base.y+ux*spread},right:{x:base.x+uy*spread,y:base.y-ux*spread}};
  }
  const font = size => '650 '+size+'px system-ui, sans-serif';
  const rows = mark => mark.text.split('\n');
  function frame(mark,ctx) {
    if(mark.type==='text') {
      ctx.save();ctx.font=font(mark.size);
      const width=Math.max(...rows(mark).map(row=>ctx.measureText(row).width),1);
      ctx.restore();
      return {x:mark.a.x,y:mark.a.y,width,height:mark.size*1.2*rows(mark).length};
    }
    if(mark.type==='pen') {
      const xs=mark.points.map(p=>p.x),ys=mark.points.map(p=>p.y);
      const x=Math.min(...xs),y=Math.min(...ys);
      return {x,y,width:Math.max(...xs)-x,height:Math.max(...ys)-y};
    }
    return bounds(mark.a,mark.b);
  }
  function hit(mark,p,tolerance,ctx) {
    const t=tolerance+mark.width/2;
    if(mark.type==='arrow') {
      const h=arrow(mark.a,mark.b,mark.width);
      return segmentDistance(p,mark.a,mark.b)<=t || Boolean(h&&(segmentDistance(p,h.left,mark.b)<=t||segmentDistance(p,h.right,mark.b)<=t||segmentDistance(p,h.left,h.right)<=t));
    }
    if(mark.type==='pen') return mark.points.some((q,i)=>segmentDistance(p,mark.points[Math.max(0,i-1)],q)<=t);
    const r=frame(mark,ctx);
    return p.x>=r.x-t && p.x<=r.x+r.width+t && p.y>=r.y-t && p.y<=r.y+r.height+t;
  }
  function shift(mark,dx,dy) {
    const move=p=>({x:p.x+dx,y:p.y+dy});
    return {...mark,a:move(mark.a),...(mark.b?{b:move(mark.b)}:{}),...(mark.points?{points:mark.points.map(move)}:{})};
  }
  function drawMark(ctx,mark) {
    ctx.save();
    ctx.strokeStyle=mark.color;ctx.fillStyle=mark.color;ctx.lineWidth=mark.width;
    ctx.lineCap='round';ctx.lineJoin='round';
    const {a,b}=mark;
    if(mark.type==='text') {
      ctx.font=font(mark.size);ctx.textBaseline='top';
      rows(mark).forEach((line,i)=>ctx.fillText(line,a.x,a.y+i*mark.size*1.2));
    } else if(mark.type==='pen') {
      ctx.beginPath();ctx.moveTo(a.x,a.y);
      mark.points.forEach(p=>ctx.lineTo(p.x,p.y));
      ctx.stroke();
    } else if(mark.type==='arrow') {
      const h=arrow(a,b,mark.width);
      if(h) {
        ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(h.stem.x,h.stem.y);ctx.stroke();
        ctx.beginPath();ctx.moveTo(b.x,b.y);ctx.lineTo(h.left.x,h.left.y);ctx.lineTo(h.right.x,h.right.y);ctx.closePath();ctx.fill();
      }
    } else {
      const r=bounds(a,b);
      if(mark.type==='rectangle') ctx.strokeRect(r.x,r.y,r.width,r.height);
      if(mark.type==='ellipse' && r.width && r.height) {ctx.beginPath();ctx.ellipse(r.x+r.width/2,r.y+r.height/2,r.width/2,r.height/2,0,0,2*Math.PI);ctx.stroke();}
      if(mark.type==='highlight') {ctx.globalAlpha=.28;ctx.fillRect(r.x,r.y,r.width,r.height);}
      if(mark.type==='redact') {ctx.fillStyle='#16141d';ctx.fillRect(r.x,r.y,r.width,r.height);}
    }
    ctx.restore();
  }
  function paint(ctx,image,doc,scale=1) {
    const {crop,marks}=doc;
    ctx.setTransform(scale,0,0,scale,0,0);
    ctx.clearRect(0,0,crop.width,crop.height);
    ctx.drawImage(image,crop.x,crop.y,crop.width,crop.height,0,0,crop.width,crop.height);
    ctx.translate(-crop.x,-crop.y);
    marks.forEach(mark=>drawMark(ctx,mark));
  }
  function history(initial,limit=48) {
    let current=initial, past=[], future=[];
    return {
      get current(){return current;}, get canUndo(){return past.length>0;},get canRedo(){return future.length>0;},
      commit(next){if(next===current)return;past.push(current);if(past.length>limit)past.shift();current=next;future=[];},
      undo(){if(past.length){future.push(current);current=past.pop();}return current;},
      redo(){if(future.length){past.push(current);current=future.pop();}return current;}
    };
  }
  root.SnapEditorCore={bounds,point,cropRect,arrow,distance,frame,hit,shift,drawMark,paint,history,clamp,panOrigin,handles,selectionHit,adjustSelection,selectionInsets,setInset};
})(globalThis);
