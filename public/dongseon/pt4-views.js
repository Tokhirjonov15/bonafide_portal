/* 4층 비급여 예약 — 화면 (pt4.html 에서 불러옴). visit-stats 의 app/schedule·m·treatments·charts·audit 를 옮김 (2026-10-07) */
'use strict';
const LOADING='<div class="loading">불러오는 중…</div>';
const A=s=>esc(s);   // 속성용

/* ═════════ 일별 스케줄 ═════════ */
function renderSchedule(){
  const date=R.q.date;
  if(DAYDOC===undefined)return LOADING;
  const D=dayView(date,DAYDOC,NEARDOC);window.DV=D;
  if(date===todayYmd()){watchBoard();setTimeout(sasoSync,0);}   // SASO 환자 → Manual Tx
  const {year,month,day:dd}=splitYmd(date);
  const slots=(D.endMin-DAY_START)/SLOT;D.slots=slots;
  const times=TIMES.slice(0,slots);
  const ed='editable';
  /* 치료사별 15분 칸 점유표 */
  const occ=new Map();
  for(const t of D.therapists){const arr=Array.from({length:slots},()=>({type:'free'}));
    for(const k of D.blocks.filter(x=>x.therapistId===t.id))for(let m=k.startMin;m<k.endMin;m+=SLOT){const i=(m-DAY_START)/SLOT;if(i>=0&&i<slots)arr[i]={type:'block',k};}
    for(const b of D.bookings.filter(x=>x.therapistId===t.id))for(let m=b.startMin;m<b.startMin+b.durationMin;m+=SLOT){const i=(m-DAY_START)/SLOT;if(i>=0&&i<slots)arr[i]={type:'booking',b};}
    occ.set(t.id,arr);}
  D.occ=occ;
  /* 하루 종일 회색(예약 없이 모든 칸이 비근무·차단)인 치료사 열 숨기기 — 화면에서만, 통계·데이터는 그대로 (2026-10-07 요청, 이 PC 에 기억) */
  const fullOff=D.therapists.filter(t=>occ.get(t.id).every(o=>o.type==='block'));
  D.allTherapists=D.therapists;
  if(HIDE_OFF&&fullOff.length&&fullOff.length<D.therapists.length)D.therapists=D.therapists.filter(t=>!fullOff.includes(t));
  const rendered=new Map(D.therapists.map(t=>[t.id,new Set()]));
  /* 전원 공통 차단(점심 등) — 띠 하나로 */
  const bands=[];
  if(D.therapists.length){const first=D.blocks.filter(b=>b.therapistId===D.therapists[0].id);
    for(const b of first){const same=D.therapists.map(t=>D.blocks.find(x=>x.therapistId===t.id&&x.startMin===b.startMin&&x.endMin===b.endMin&&x.kind===b.kind));
      if(same.every(Boolean))bands.push({startMin:b.startMin,endMin:b.endMin,kind:b.kind,text:b.text,color:b.color,blocks:same});}
    for(const band of bands)for(const t of D.therapists){const done=rendered.get(t.id);for(let m=band.startMin;m<band.endMin;m+=SLOT){const i=(m-DAY_START)/SLOT;if(i>=0&&i<slots)done.add(i);}}}
  D.bands=bands;
  const totalCols=D.therapists.reduce((a,t)=>a+(t.single?1:3),0);
  const cancelTh=D.therapists.filter(t=>!t.single);D.cancelTh=cancelTh;
  const cancelAt=new Map();for(const c of D.cancels)cancelAt.set(`${c.therapistName}|${c.startMin}`,c);
  const headerColor=(t,i)=>t.color||HEADER_FALLBACK[i%HEADER_FALLBACK.length];

  let h=`<div class="sheet-layout${PAINT?' painting':''}" tabindex="-1"><div class="sheet-main">`;
  h+=`<div class="daybar"><button class="pill" onclick="go('schedule',{date:'${shiftDate(date,-1)}'})">← 이전</button><h1>${esc(D.label)}</h1>
    <button class="pill" onclick="go('schedule',{date:'${shiftDate(date,1)}'})">다음 →</button>${jumpHtml(date,'schedule')}
    ${date!==todayYmd()?`<button class="pill small" onclick="go('schedule',{date:'${todayYmd()}'})">오늘</button>`:''}</div>`;
  const has=new Set(META.dataDays);const n=daysInMonth(year,month);
  h+=`<div class="days"><button class="pill small" onclick="go('schedule',{date:'${ymd(month===1?year-1:year,month===1?12:month-1,1)}'})">‹ 전달</button>`;
  for(let d=1;d<=n;d++){const s=ymd(year,month,d);h+=`<a href="${href('schedule',{date:s})}" class="day ${s===date?'on':''} ${has.has(s)?'has':''}">${d}</a>`;}
  h+=`<button class="pill small" onclick="go('schedule',{date:'${ymd(month===12?year+1:year,month===12?1:month+1,1)}'})">다음달 ›</button></div>`;
  h+=`<div class="sheet-title"><span class="sheet-title-text">비급여치료 예약리스트</span><span class="sheet-title-date">${month}월 ${dd}일 ${WEEKDAYS[new Date(year,month-1,dd).getDay()]}요일${D.shortDay?' · 17:30까지':''}</span></div>`;
  if(MSG&&!EDIT)h+=`<p class="err">${esc(MSG)}</p>`;
  h+=newPtBar(D);
  h+=hiddenBar(D);
  if(D.borrowedFrom)h+=`<div class="hint"><span>이 날은 아직 배치가 없어 <strong>${esc(D.borrowedFrom)}</strong> 의 치료사 명단으로 표시합니다. 예약이나 비근무를 저장하면 이 명단이 이 날에 확정됩니다.</span>
    <span class="row"><button type="button" class="ghost" onclick="copyLayout()">${esc(D.borrowedFrom)} 의 비근무까지 복사</button><button type="button" class="ghost" onclick="openEd({kind:'therapists'})">명단 직접 고르기</button></span></div>`;
  if(!D.therapists.length)h+=`<div class="empty"><p>치료사가 아직 없습니다. 먼저 치료사를 추가하세요.</p><button type="button" onclick="openEd({kind:'therapists'})">치료사 추가</button></div>`;
  if(fullOff.length&&fullOff.length<D.allTherapists.length){const names=fullOff.map(t=>esc(t.name)).join(', ');
    h+=`<div class="hint" style="margin:6px 0"><span>${HIDE_OFF?`휴무자 <b>${fullOff.length}명</b>을 숨겼습니다: ${names}`:`휴무자(하루 종일 회색) ${fullOff.length}명: ${names}`} <span class="who small">(화면에서만 — 통계는 그대로)</span></span><button type="button" class="ghost" onclick="toggleHideOff()">${HIDE_OFF?'휴무자 다시 보이기':'휴무자 숨기기'}</button></div>`;}
  if(D.therapists.length){
    const units=54+D.therapists.reduce((a,t)=>a+(t.single?44:122),0);const w=u=>`${((u/units)*100).toFixed(3)}%`;
    h+=`<div class="scroll"><table class="sheet grid fluid" style="width:100%"><colgroup><col style="width:${w(54)}">`;
    D.therapists.forEach(t=>{h+=t.single?`<col style="width:${w(44)}">`:`<col style="width:${w(62)}"><col style="width:${w(46)}"><col style="width:${w(14)}">`;});
    h+=`</colgroup><thead><tr><th rowspan="2">시간</th><th colspan="${totalCols}" class="section">비급여치료</th></tr><tr>`;
    D.therapists.forEach((t,i)=>{h+=`<th colspan="${t.single?1:3}" class="th-name" style="background:${A(headerColor(t,i))}" onclick="openEd({kind:'therapists'})" title="치료사 명단 바꾸기">${esc(t.name)}</th>`;});
    h+=`</tr></thead><tbody>`;
    times.forEach((min,i)=>{
      h+=`<tr class="${i%2===0?'half':'quarter'}">`;
      if(i%2===0)h+=`<td rowspan="2" class="time">${hm(min)}</td>`;
      const bi=bands.findIndex(b=>(b.startMin-DAY_START)/SLOT===i);
      if(bi>=0){const band=bands[bi];const span=(band.endMin-band.startMin)/SLOT;const bg=band.kind==='off'?'#999999':band.color||'#d9d9d9';
        h+=`<td colspan="${totalCols}" rowspan="${span}" class="block band ${ed}" style="background:${A(bg)}" title="전원 ${band.kind==='off'?'비근무':'차단'} ${hm(band.startMin)}~${hm(band.endMin)}" onclick="bandClick(${bi})">${esc(band.text)}</td>`;}
      for(const t of D.therapists){
        const arr=occ.get(t.id),done=rendered.get(t.id);if(done.has(i))continue;const o=arr[i];
        if(o.type==='booking'){const b=o.b;const span=b.durationMin/SLOT;for(let k=i;k<i+span;k++)done.add(k);
          if(t.single){const bg=b.visited?'#ffe599':b.color||'#ffffff';
            h+=`<td rowspan="${span}" class="pt single ${ed} ${b.note?'has-note':''}${SEL.has(b.id)?' sel':''}" data-bid="${b.id}" data-tid="${t.id}" data-min="${b.startMin}" style="background:${A(bg)}" onclick="bOpen(${b.id})">${esc(bookingText(b))}${notePop(b)}</td>`;}
          else h+=bookingCells(b,span);
          continue;}
        if(o.type==='block'){let span=0;while(i+span<slots&&arr[i+span].type==='block'&&arr[i+span].k.id===o.k.id)span++;for(let k=i;k<i+span;k++)done.add(k);
          const bg=o.k.kind==='off'?'#999999':o.k.color||'#d9d9d9';
          if(o.k.kind==='memo'&&!t.single){const s=DAY_START+i*SLOT;
            h+=`<td rowspan="${span}" class="block pt ${ed}" style="background:${A(bg)}" title="${A(o.k.text||'색 표시')}" onclick="blkOpen(${o.k.id})">${esc(o.k.text)}</td>
              <td rowspan="${span}" class="free ${ed}" onclick="memoNew(${t.id},${s},${span})"></td><td rowspan="${span}" class="free mark"></td>`;}
          else h+=`<td colspan="${t.single?1:3}" rowspan="${span}" class="block ${ed}" style="background:${A(bg)}" title="${A(o.k.kind==='off'?'비근무':o.k.text)}" onclick="blkOpen(${o.k.id})">${esc(o.k.text)}</td>`;
          continue;}
        const span=i%2===0&&i+1<slots&&arr[i+1].type==='free'&&!done.has(i+1)?2:1;for(let k=i;k<i+span;k++)done.add(k);
        const oc=`cellNew(${t.id},${min},${span})`;
        const dm=`data-tid="${t.id}" data-min="${min}"`;
        if(t.single)h+=`<td rowspan="${span}" class="free pt single ${ed}" ${dm} onclick="${oc}"></td>`;
        else h+=`<td rowspan="${span}" class="free pt ${ed}" ${dm} onclick="${oc}"></td><td rowspan="${span}" class="free ${ed}" ${dm} onclick="${oc}"></td><td rowspan="${span}" class="free mark" ${dm}></td>`;}
      h+=`</tr>`;});
    h+=`</tbody><tfoot><tr><td class="time">당월 누적<br>상담수</td>`;
    D.therapists.forEach(t=>{const v=D.consults[t.id]??0;h+=`<td colspan="${t.single?1:3}" class="center big"><input class="consult" value="${A(v)}" onblur="consultBlur(${t.id},this,${Number(v)})" onkeydown="if(event.key==='Enter')this.blur()"></td>`;});
    h+=`</tr><tr><td class="time">평균<br>내원률</td>`;
    D.therapists.forEach(t=>{const r=D.ratios.get(t.id);h+=`<td colspan="${t.single?1:3}" class="center ratio" title="${r?`방문 ${r.visit} / 근무 칸 ${r.usable}`:'근무 없음'}">${pct(r&&r.ratio)}</td>`;});
    h+=`</tr><tr><td class="time">예약<br>합계</td>`;
    D.therapists.forEach(t=>{h+=`<td colspan="${t.single?1:3}" class="center">${D.bookings.filter(b=>b.therapistId===t.id).length}</td>`;});
    h+=`</tr></tfoot></table></div>`;
  }
  if(D.therapists.length&&cancelTh.length){
    const cw=u=>`${((u/(54+cancelTh.length*90))*100).toFixed(3)}%`;
    h+=`<div class="scroll cancel-wrap"><table class="sheet grid cancel-grid fluid" style="width:100%"><colgroup><col style="width:${cw(54)}">${cancelTh.map(()=>`<col style="width:${cw(90)}">`).join('')}</colgroup>
      <thead><tr><th rowspan="2">시간</th><th colspan="${cancelTh.length}" class="section cancel-section">취소/변경</th></tr><tr>${cancelTh.map(t=>`<th class="th-cancel">${esc(t.name)}</th>`).join('')}</tr></thead><tbody>`;
    const cRend=new Map(cancelTh.map(t=>[t.name,new Set()]));
    times.forEach((min,i)=>{h+=`<tr class="${i%2===0?'half':'quarter'}">`;if(i%2===0)h+=`<td rowspan="2" class="time">${hm(min)}</td>`;
      cancelTh.forEach((t,ti)=>{const done=cRend.get(t.name);if(done.has(i))return;const c=cancelAt.get(`${t.name}|${min}`)||null;
        const span=i%2===0&&i+1<slots&&!cancelAt.has(`${t.name}|${min+SLOT}`)?2:1;for(let k=i;k<i+span;k++)done.add(k);
        h+=`<td rowspan="${span}" class="cancel ${c?(c.kind==='cancel'?'strike':'')+' cx-cell'+(cxMemo(c)?' has-note':''):'free'} ${ed}" style="${c&&c.color?`background:${A(c.color)}`:''}" title="${c?(c.kind==='cancel'?'취소':'변경'):''}" onclick="cxOpen(${ti},${min})"><span class="cx-text">${c?esc(c.text):''}</span>${c?cxNotePop(c):''}</td>`;});
      h+=`</tr>`;});
    h+=`</tbody><tfoot><tr><td class="time">취소 및<br>변경 합계</td>${cancelTh.map(t=>`<td class="center">${D.cancels.filter(c=>c.therapistName===t.name).length}</td>`).join('')}</tr>
      <tr><td class="time">총계</td><td colspan="${cancelTh.length}" class="center muted">총 ${D.cancels.length}건</td></tr></tfoot></table></div>`;}
  h+=`<p class="note">빈 칸을 누르면 예약을 넣고, 예약을 누르면 고칩니다. 표시 칸(세 번째 좁은 칸)을 누르면 점(.)이나 치료 시작 시각 숫자를 바로 적을 수 있고, 내용이 있으면 내원으로 인정되어 환자 칸이 노란색이 됩니다.
    회색은 비근무. 취소/변경 칸을 누르면 기록을 넣습니다. 다른 PC 에서 고친 내용도 바로 보입니다.</p></div>`;
  h+=sidePanel(D);
  h+=`</div>`;
  return h;}
function jumpHtml(date,page){const ym=date.slice(0,7);const list=[...new Set(META.dataDays.map(d=>d.slice(0,7)).concat([ym]))].sort();
  return `<div class="jump"><select title="달 선택" onchange="go('${page}',{date:this.value+'-01'})">${list.map(v=>`<option value="${v}" ${v===ym?'selected':''}>${Number(v.slice(0,4))}년 ${Number(v.slice(5))}월</option>`).join('')}</select>
    <input type="date" value="${date}" title="날짜로 이동" onchange="if(this.value)go('${page}',{date:this.value})"></div>`;}
const bookingText=b=>b.mrn||b.patientName?`${b.mrn}${b.room?`(${b.room})`:''}\n${b.patientName}${b.visitNo??''}`:(b.rawText||'');
function notePop(b){return `<div class="note-pop" onclick="event.stopPropagation()" onmousedown="event.stopPropagation()"><div class="note-head">메모 · ${esc(b.patientName||b.mrn||'예약')}</div>
  <textarea rows="6" placeholder="예: 11:00 CRYO10 수납 +20&#10;**항상 PT 먼저" onblur="bNoteBlur(${b.id},this)" onkeydown="event.stopPropagation();if(event.key==='Enter'&&(event.ctrlKey||event.metaKey))this.blur()">${esc(b.note||'')}</textarea>
  <div class="note-foot"><span class="who small">창 밖을 누르거나 Ctrl+Enter 로 저장</span></div></div>`;}
function bookingCells(b,span){const bg=b.visited?'#ffe599':b.color||'#ffffff';const shown=b.mark||(b.visited?'.':'');
  const dm=`data-bid="${b.id}" data-tid="${b.therapistId}" data-min="${b.startMin}"`,sc=SEL.has(b.id)?' sel':'';
  const du=dueInfo(b),dc=du?' due':'',dt=du?` title="${A(`${hm(du.start)} 시작 · ${du.mins}분 치료 → ${hm(du.end)} 끝 (지남) — 끝났으면 표시 칸에 점(.)`)}"`:'';
  return `<td rowspan="${span}" class="pt editable ${b.note?'has-note':''}${sc}${dc}"${dt} ${dm} style="background:${A(bg)}" onclick="bOpen(${b.id})">${esc(bookingText(b))}${notePop(b)}</td>
    <td rowspan="${span}" class="code editable${sc}${dc}"${dt} ${dm} style="background:${A(b.codeColor||'#ffffff')}" onclick="bOpen(${b.id})">${esc(b.code)}${(()=>{const x=txInfo(b);return x?`<div class="tx-end" title="${A(`${hm(x.start)} 시작 · ${x.mins}분`)}">~${hm(x.end)}</div>`:'';})()}</td>
    <td rowspan="${span}" class="mark editable${sc}" ${dm} title="클릭해서 점(.)이나 치료 시작 시각을 입력. 내용이 있으면 내원 · 두 번 누르면 방문 체크" onclick="markClick(${b.id},this,event)" ondblclick="event.stopPropagation();bVisit(${b.id})">${esc(shown)}</td>`;}

let HIDE_OFF=(()=>{try{return localStorage.getItem('pt4HideOff')==='1';}catch(e){return false;}})();
window.toggleHideOff=()=>{HIDE_OFF=!HIDE_OFF;try{localStorage.setItem('pt4HideOff',HIDE_OFF?'1':'0');}catch(e){}render();};
/* ═════ 치료 시간 지남 알림 (2026-10-07 요청) ═════
   표시 칸에 점(.) 대신 치료를 시작한 '분'(예: 35 = 그 시각의 35분, 1435·14:35 도 됨)을 적으면 치료 중으로 보고,
   시작 + 코드별 치료 시간이 지나면 이름 칸·치료코드 칸이 빨갛게 천천히 깜빡인다. 점(.)을 찍으면 끝(깜빡임 사라짐). 오늘 날짜만.
   치료 시간: 설정의 코드별 치료 시간표(가져오기 화면) → 없으면 임시로 코드 숫자 × 3분 (CM15 = 45분) */
function txMinutes(code){const c=normalizeCode(code);if(!c)return null;const t=META.txMinutes||{};if(t[c]!=null&&+t[c]>0)return +t[c];
  const m=/^(CME|CM|ES|CRYO|EES|CE)(\d+)$/.exec(c);return m?(+m[2])*3:null;}
function markStart(b){const s=String(b.mark||'').trim();if(!s||/^[.·]+$/.test(s))return null;let m;
  if((m=/^(\d{1,2})\s*[:시]\s*(\d{2})$/.exec(s)))return (+m[1])*60+(+m[2]);
  if((m=/^(\d{1,2})(\d{2})$/.exec(s))&&+m[1]>=8&&+m[1]<=21)return (+m[1])*60+(+m[2]);
  if((m=/^(\d{1,2})$/.exec(s))&&+m[1]<60){const mm=+m[1];
    const at=b.markAt?new Date(b.markAt):null;
    if(at&&localYmdOf(at)===R.q.date){const w=at.getHours()*60+at.getMinutes()+2;let t=Math.floor(w/60)*60+mm;if(t>w)t-=60;return t;}   // 적은 시각에서 가장 가까운 지난 '그 분' (늦게 들어온 환자도 맞게)
    let t=Math.floor(b.startMin/60)*60+mm;if(t<b.startMin-20)t+=60;return t;}
  return null;}
const localYmdOf=d=>ymd(d.getFullYear(),d.getMonth()+1,d.getDate());
/* 치료 중(표시 칸에 시작 분)이면 끝나는 시각 — 코드 칸에 작게 보여 준다 */
function txInfo(b){if(R.q.date!==todayYmd())return null;const start=markStart(b);if(start==null)return null;const mins=txMinutes(b.code);if(!mins)return null;return {start,mins,end:start+mins};}
function dueInfo(b){if(R.q.date!==todayYmd())return null;const start=markStart(b);if(start==null)return null;const mins=txMinutes(b.code);if(!mins)return null;
  const now=new Date(),nowMin=now.getHours()*60+now.getMinutes();return nowMin>=start+mins?{start,mins,end:start+mins}:null;}
setInterval(()=>{if(R.page==='schedule'&&R.q.date===todayYmd()&&!DRAG&&!EDIT)safeRender();},30000);   // 30초마다 시간 지남 다시 확인

/* ── 표 칸 동작 ── */
const D_=()=>window.DV;
function freeRun(tid,startMin){const arr=D_().occ.get(tid);let n=0;for(let i=(startMin-DAY_START)/SLOT;i<D_().slots&&arr[i].type==='free';i++)n+=SLOT;return n;}
window.cellNew=(tid,startMin,span)=>{if(eatClick())return;if(PAINT){paintFree(tid,startMin,startMin+span*SLOT);return;}openEd({kind:'choose',therapistId:tid,startMin,maxDuration:freeRun(tid,startMin)});};
window.memoNew=(tid,startMin,span)=>{if(PAINT){paintFree(tid,startMin,startMin+span*SLOT);return;}openEd({kind:'new',therapistId:tid,startMin,maxDuration:span*SLOT});};
window.bOpen=id=>{if(eatClick())return;const b=D_().bookings.find(x=>x.id===id);if(!b)return;if(PAINT){paintBooking(b);return;}openEd({kind:'booking',booking:b});};
window.bVisit=id=>{const b=D_().bookings.find(x=>x.id===id);if(!b)return;if(PAINT){paintBooking(b);return;}run(R.q.date,opBookingVisit(id),false);};
window.blkOpen=id=>{const k=D_().blocks.find(x=>x.id===id);if(!k)return;if(PAINT){paintBlock(k);return;}
  if(k.preview){openEd({kind:'off',therapistId:k.therapistId,startMin:k.startMin});return;}openEd({kind:'block',block:k});};
window.bandClick=i=>{const band=D_().bands[i];if(!band)return;if(PAINT){paintBlock(band.blocks[0]);return;}openEd({kind:'band',band});};
/* 취소/변경 칸 메모 — Manual Tx 메모처럼 마우스를 올리면 말풍선, 바로 적고 창 밖을 누르면 저장 (2026-10-08 요청) */
/* 예전 방식으로 취소한 칸은 메모 자리에 '코드 CM15' 가 들어 있다(되돌리기용) — 취소 메모로는 보이지 않게 */
const CX_CODE=/^코드\s*[A-Za-z0-9]+$/;
function cxMemo(c){const n=String(c.note||'');return CX_CODE.test(n.trim())?'':n;}
function cxNotePop(c){return `<div class="note-pop" onclick="event.stopPropagation()" onmousedown="event.stopPropagation()"><div class="note-head">메모 · ${esc(c.patientName||c.text)}</div><textarea rows="5" placeholder="메모" onblur="cxNoteBlur(${c.id},this)" onkeydown="event.stopPropagation();if(event.key==='Enter'&&(event.ctrlKey||event.metaKey))this.blur()">${esc(cxMemo(c))}</textarea>
    <div class="note-foot"><span class="who small">창 밖을 누르거나 Ctrl+Enter 로 저장</span></div></div>`;}
window.cxNoteBlur=(id,ta)=>{const c=D_().cancels.find(x=>x.id===id);if(!c||ta.value===cxMemo(c))return;run(R.q.date,opCancelNote(id,ta.value),false);};
window.cxOpen=(ti,startMin)=>{const t=D_().cancelTh[ti];if(!t)return;const c=D_().cancels.find(x=>x.therapistName===t.name&&x.startMin===startMin)||null;
  if(PAINT){if(c)run(R.q.date,opCancelSave({id:c.id,therapistName:c.therapistName,startMin:c.startMin,kind:c.kind,text:c.text,color:PAINT==='#ffffff'?'':PAINT}),false);return;}
  openEd({kind:'cancel',therapistName:t.name,startMin,cancel:c});};
window.markClick=(id,td,ev)=>{ev.stopPropagation();if(eatClick())return;if(PAINT){bVisit(id);return;}if(td.classList.contains('editing'))return;
  const b=D_().bookings.find(x=>x.id===id);if(!b)return;const shown=b.mark||(b.visited?'.':'');
  td.classList.add('editing');td.innerHTML=`<input value="${A(shown)}" maxlength="10" title="점(.) 또는 숫자. 비우면 내원 해제">`;
  const inp=td.querySelector('input');inp.focus();inp.select();let gone=false;
  const fin=save=>{if(gone)return;gone=true;const v=inp.value.trim();td.classList.remove('editing');td.textContent=shown;
    if(save&&v!==shown)run(R.q.date,opBookingMark(id,v),false);else safeRender();};
  inp.addEventListener('keydown',e=>{e.stopPropagation();if(e.key==='Enter')fin(true);if(e.key==='Escape')fin(false);});
  inp.addEventListener('blur',()=>fin(true));inp.addEventListener('click',e=>e.stopPropagation());};
window.bNoteBlur=(id,ta)=>{const b=D_().bookings.find(x=>x.id===id);if(!b||ta.value===(b.note||''))return;run(R.q.date,opBookingNote(id,ta.value),false);};
window.consultBlur=(tid,inp,orig)=>{if(String(inp.value)===String(orig))return;runMeta(saveConsult(R.q.date,tid,Number(inp.value)),false);};
window.copyLayout=async()=>{const from=D_().borrowedFrom;if(!from)return;const s=await C.day.doc(from).get();if(!s.exists)return;run(R.q.date,opCopyLayout(normDay(s.data(),from)));};

/* ═════ 엑셀처럼 복사·붙여넣기 (2026-10-07 요청) ═════
   예약 칸을 끌어서(드래그) 여러 개 고르거나 Ctrl+클릭으로 하나씩 고른 뒤 Ctrl+C → 다른 날(또는 같은 날) 칸을 누르고 Ctrl+V (또는 [여기에 붙여넣기]).
   누른 칸이 붙여넣을 자리의 왼쪽 위 — 고른 예약들의 치료사 간격·시간 간격을 그대로 유지. 칸을 고르지 않고 Ctrl+V 면 같은 치료사·같은 시간으로.
   다른 날에 붙이면 방문수 +1, 내원 표시는 지움, 메모는 함께. 겹치는 자리는 건너뛰고 알려 준다. 고른 것은 Esc 로 해제 */
let SEL=new Set(),CLIP=(()=>{try{return JSON.parse(localStorage.getItem('pt4Clip')||'null');}catch(e){return null;}})(),DRAG=null,EAT=false;
function eatClick(){if(EAT){EAT=false;return true;}return false;}
function selPaint(){document.querySelectorAll('table.grid td[data-bid]').forEach(td=>td.classList.toggle('sel',SEL.has(Number(td.dataset.bid))));}
/* 드래그 선택 (2026-10-07: 매끄럽게) — 칸 위를 지날 때가 아니라 마우스 좌표로 치료사 열·시간 줄을 바로 계산한다.
   회색(비근무)·점심 띠 위를 지나도 끊기지 않고, 끄는 동안 파란 네모로 범위를 보여 준다. 5px 넘게 움직여야 드래그(그 전엔 보통 클릭) */
function gridGeom(){const tb=document.querySelector('table.grid:not(.cancel-grid)');if(!tb)return null;
  const cols=[...tb.querySelectorAll('thead th.th-name')].map(th=>th.getBoundingClientRect());const rows=[...tb.querySelectorAll('tbody tr')].map(tr=>tr.getBoundingClientRect());
  return cols.length&&rows.length?{cols,rows}:null;}
function pick(list,v,lo,hi){if(v<=list[0][lo])return 0;if(v>=list[list.length-1][hi])return list.length-1;for(let i=0;i<list.length;i++)if(v<list[i][hi])return i;return list.length-1;}
function dragUpdate(){DRAG.raf=0;const g=gridGeom();if(!g)return;const D=D_();if(!D)return;
  const c1=pick(g.cols,DRAG.x0,'left','right'),c2=pick(g.cols,DRAG.x,'left','right'),r1=pick(g.rows,DRAG.y0,'top','bottom'),r2=pick(g.rows,DRAG.y,'top','bottom');
  const ci=Math.min(c1,c2),cj=Math.max(c1,c2),ri=Math.min(r1,r2),rj=Math.max(r1,r2);
  const key=[ci,cj,ri,rj].join();
  let box=document.getElementById('selBox');if(!box){box=document.createElement('div');box.id='selBox';document.body.appendChild(box);}
  Object.assign(box.style,{left:g.cols[ci].left+'px',top:g.rows[ri].top+'px',width:(g.cols[cj].right-g.cols[ci].left)+'px',height:(g.rows[rj].bottom-g.rows[ri].top)+'px',display:'block'});
  if(key===DRAG.key)return;DRAG.key=key;
  const tids=D.therapists.slice(ci,cj+1).map(t=>t.id),m1=DAY_START+ri*SLOT,m2=DAY_START+(rj+1)*SLOT;
  SEL=new Set(DRAG.base);D.bookings.forEach(x=>{if(tids.includes(x.therapistId)&&x.startMin<m2&&m1<x.startMin+x.durationMin)SEL.add(x.id);});selPaint();}
function dragEnd(){const box=document.getElementById('selBox');if(box)box.style.display='none';}
document.addEventListener('mousedown',e=>{EAT=false;if(R.page!=='schedule'||PAINT||e.button!==0)return;
  const t=e.target;if(!t||!t.closest||t.closest('.note-pop')||/^(INPUT|TEXTAREA|SELECT|BUTTON)$/.test(t.tagName))return;
  const td=t.closest('table.grid:not(.cancel-grid) tbody td');if(!td||td.classList.contains('time'))return;
  const bid=td.dataset.bid?Number(td.dataset.bid):null;
  if((e.ctrlKey||e.metaKey)&&bid!=null){e.preventDefault();SEL.has(bid)?SEL.delete(bid):SEL.add(bid);selPaint();EAT=true;selHint();return;}
  DRAG={x0:e.clientX,y0:e.clientY,x:e.clientX,y:e.clientY,moved:false,raf:0,key:'',base:(e.shiftKey?[...SEL]:[]),td};});
document.addEventListener('mousemove',e=>{if(!DRAG)return;DRAG.x=e.clientX;DRAG.y=e.clientY;
  if(!DRAG.moved){if(Math.abs(DRAG.x-DRAG.x0)+Math.abs(DRAG.y-DRAG.y0)<10)return;DRAG.moved=true;}   // 클릭하며 손이 조금 떨려도 끌기가 아니게 (5 → 10px, 2026-10-11)
  e.preventDefault();if(!DRAG.raf)DRAG.raf=requestAnimationFrame(dragUpdate);});
document.addEventListener('mouseup',e=>{if(!DRAG)return;let moved=DRAG.moved;
  if(moved&&!DRAG.base.length){const t=document.elementFromPoint(e.clientX,e.clientY);const td=t&&t.closest&&t.closest('td');if(td&&td===DRAG.td){moved=false;SEL.clear();selPaint();}}   // 같은 칸 안에서 떼면 클릭으로 본다if(DRAG.raf){cancelAnimationFrame(DRAG.raf);dragUpdate();}DRAG=null;dragEnd();
  if(moved){EAT=true;setTimeout(()=>{EAT=false;},0);selHint();}});   // 드래그를 끝낸 바로 그 클릭만 무시
function selHint(){if(SEL.size)toast(`예약 ${SEL.size}건 골랐습니다 — Ctrl+C 복사 · Delete 지우기 · Esc 해제`,2600);}
function copySel(){const D=D_();if(!D||!SEL.size)return false;const ids=D.therapists.map(t=>t.id);
  const items=D.bookings.filter(b=>SEL.has(b.id)).map(b=>({therapistId:b.therapistId,ti:ids.indexOf(b.therapistId),startMin:b.startMin,durationMin:b.durationMin,mrn:b.mrn,room:b.room,patientName:b.patientName,
    visitNo:b.visitNo,code:b.code,codeColor:b.codeColor,color:b.color==='#ffe599'?'':b.color,note:b.note||''}));
  CLIP={date:D.date,items};try{localStorage.setItem('pt4Clip',JSON.stringify(CLIP));}catch(e){}
  toast(`예약 ${items.length}건 복사했습니다 — 붙여넣을 날의 칸을 누르고 Ctrl+V (또는 [여기에 붙여넣기])`,3500);return true;}
window.pasteClip=async anchor=>{const D=D_();if(!D||!CLIP||!CLIP.items.length)return;const date=R.q.date;const ids=D.therapists.map(t=>t.id);
  const ti0=Math.min(...CLIP.items.map(x=>x.ti)),m0=Math.min(...CLIP.items.map(x=>x.startMin));const other=CLIP.date!==date;
  const plan=[],skip=[];
  for(const x of CLIP.items){let tid,st;
    if(anchor){const ai=ids.indexOf(anchor.tid);tid=ids[ai+(x.ti-ti0)];st=anchor.min+(x.startMin-m0);}else{tid=x.therapistId;st=x.startMin;}
    const who=x.patientName||x.mrn;
    if(tid==null||(!anchor&&!ids.includes(tid))){skip.push(`${who}(치료사 없음)`);continue;}
    if(st<DAY_START||st+x.durationMin>D.endMin){skip.push(`${who}(시간 밖)`);continue;}
    plan.push({therapistId:tid,startMin:st,durationMin:x.durationMin,mrn:x.mrn,room:x.room,patientName:x.patientName,visitNo:x.visitNo==null?null:(other?x.visitNo+1:x.visitNo),
      code:x.code,codeColor:x.codeColor,color:x.color,visited:false,note:x.note});}
  let added=0;
  const r=await commitDay(date,ctx=>{added=0;const sk=[];for(const p of plan){const res=opBookingSave(p)(ctx);if(res.ok)added++;else sk.push(`${p.patientName||p.mrn}(${/겹|이미/.test(res.message)?'자리 겹침':res.message})`);}
    ctx.extra.skipped=sk;return added?{ok:true}:{ok:false,message:'붙여넣을 수 있는 예약이 없습니다'+(sk.length?': '+sk.join(', '):'')};});
  const sk2=skip.concat((r.extra&&r.extra.skipped)||[]);
  if(!r.ok){toast(r.message||'붙여넣지 못했습니다',4500);return;}
  EDIT=null;renderEditor();SEL.clear();
  toast(`${added}건 붙여넣었습니다${sk2.length?` · 건너뜀: ${sk2.join(', ')}`:''}`,sk2.length?6000:3000);safeRender();};
document.addEventListener('keydown',e=>{if(R.page!=='schedule'||!(e.ctrlKey||e.metaKey))return;const a=document.activeElement;if(a&&/^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName))return;
  const k=e.key.toLowerCase();
  if(k==='c'&&SEL.size){if(copySel())e.preventDefault();}
  else if(k==='v'&&CLIP&&CLIP.items.length){e.preventDefault();pasteClip(EDIT&&EDIT.kind==='choose'?{tid:EDIT.therapistId,min:EDIT.startMin}:null);}});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&SEL.size){SEL.clear();selPaint();}});
/* Delete(또는 Backspace) — 고른 예약을 한꺼번에 지우기 (2026-10-07 요청). 입력 중에는 동작하지 않음 */
document.addEventListener('keydown',async e=>{if(R.page!=='schedule'||!SEL.size||!(e.key==='Delete'||e.key==='Backspace'))return;
  const a=document.activeElement;if(a&&/^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName))return;e.preventDefault();
  const D=D_();const list=D.bookings.filter(b=>SEL.has(b.id));if(!list.length){SEL.clear();return;}
  if(!confirm(`예약 ${list.length}건을 지울까요?\n${list.slice(0,8).map(b=>`${hm(b.startMin)} ${b.patientName||b.mrn} ${b.code||''}`).join('\n')}${list.length>8?'\n…':''}`))return;
  const ids=list.map(b=>b.id);
  const r=await commitDay(R.q.date,ctx=>{let n=0;ids.forEach(id=>{if(opBookingDelete(id)(ctx).ok)n++;});return n?{ok:true}:{ok:false,message:'이미 지워진 예약입니다'};});
  SEL.clear();toast(r.ok?`예약 ${ids.length}건을 지웠습니다`:(r.message||'지우지 못했습니다'));safeRender();});

/* ── 칠하기 모드 ── */
function paintFree(tid,s,e){if(PAINT==='#ffffff')return;run(R.q.date,opBlockSet({therapistId:tid,startMin:s,endMin:e,kind:PAINT==='#999999'?'off':'memo',text:'',color:PAINT}),false);}
function paintBlock(k){if(PAINT==='#ffffff')run(R.q.date,opBlockClear(k.therapistId,k.startMin,k.endMin),false);
  else run(R.q.date,opBlockSet({therapistId:k.therapistId,startMin:k.startMin,endMin:k.endMin,kind:PAINT==='#999999'?'off':'memo',text:k.text,color:PAINT}),false);}
function paintBooking(b){if(PAINT==='#999999'){MSG='예약 칸은 비근무(회색)로 칠할 수 없습니다. 예약을 먼저 옮기세요.';toast(MSG);return;}
  if(PAINT==='#ffe599'){run(R.q.date,opBookingVisit(b.id),false);return;}run(R.q.date,opBookingColor(b.id,PAINT==='#ffffff'?'':PAINT),false);}
window.setPaint=hex=>{PAINT=PAINT===hex?null:hex;render();};

/* 메모 말풍선: Manual Tx·표는 스크롤 칸 안이라 옆으로 띄우면 잘렸다 → 마우스를 올린 칸 옆에 화면 기준(fixed)으로, 화면 밖으로 나가지 않게 (2026-10-07) */
function placePop(td,pop){const r=td.getBoundingClientRect();const host=td.closest('.sheet-side');const z=host?(parseFloat(getComputedStyle(host).zoom)||1):1;   // 오른쪽 칸은 80%로 줄여 그린다(zoom) — 화면 좌표로 계산한 뒤 zoom 으로 나눠 넣는다 (2026-10-11)
  const W=400*z,H=(pop.getBoundingClientRect().height||340*z);pop.classList.add('fixed');
  const leftSide=td.classList.contains('name-cell');let left=leftSide?r.left-W-6:r.right+6;
  if(left+W>innerWidth-8)left=r.left-W-6;if(left<8)left=Math.max(8,Math.min(innerWidth-W-8,r.right+6));
  const top=Math.max(8,Math.min(r.top,innerHeight-H-8));pop.style.left=(left/z)+'px';pop.style.top=(top/z)+'px';}
function popHost(e){const td=e.target&&e.target.closest&&e.target.closest('td.pt, td.name-cell, td.cx-cell');if(!td)return;const pop=td.querySelector(':scope > .note-pop');if(!pop||pop.contains(e.target))return;placePop(td,pop);}
document.addEventListener('mouseover',popHost);document.addEventListener('focusin',popHost);

/* ═════════ 오른쪽 구역: 환자 검색 · 달력 · 범례 · 특이사항 · Manual Tx ═════════ */
let SEARCH={q:'',rows:null,busy:false};
let MAN={no:null,id:null,f:{mrn:'',patientName:'',therapistName:''},colorFor:null};
function sidePanel(D){
  return `<aside class="sheet-side"><div class="side-col">${searchPanel()}${calendarPanel(D.date)}${legendPanel()}${notePanel(D)}</div><div class="side-col">${manualPanel(D)}</div></aside>`;}
function searchPanel(){let h=`<section class="panel"><div class="panel-head"><h2>환자 검색</h2></div><div class="row">
  <input id="srchQ" value="${A(SEARCH.q)}" placeholder="차트번호 또는 이름" oninput="SEARCH.q=this.value" onkeydown="if(event.key==='Enter')doSearch()">
  <button type="button" class="ghost" ${SEARCH.busy?'disabled':''} onclick="doSearch()">${SEARCH.busy?'…':'검색'}</button>${SEARCH.rows||SEARCH.q?`<button type="button" class="ghost" title="검색 결과 닫기" onclick="SEARCH={q:'',rows:null,busy:false};render()">✕</button>`:''}</div>`;
  if(SEARCH.rows&&!SEARCH.rows.length)h+=`<p class="small">기록 없음</p>`;
  if(SEARCH.rows&&SEARCH.rows.length)h+=`<ul class="list search" style="margin-top:8px">${SEARCH.rows.map((r,i)=>`<li><div class="search-row"><div>
      <div><strong>${esc(r.date)}</strong> <span class="who small">${esc(r.therapist)} · ${hm(r.startMin)} · ${r.durationMin}분</span></div>
      <div>${esc(r.mrn)}${r.room?`(${esc(r.room)})`:''} ${esc(r.patientName)}${r.visitNo??''} ${r.code?`<span class="who small">${esc(r.code)}</span>`:''} ${r.visited?'<span class="who small">내원</span>':''}</div>
      ${r.note?`<div class="search-note">${esc(r.note)}</div>`:''}</div>
      <button type="button" class="ghost" onclick="pickPast(${i})">이 날로<br>가져오기</button></div></li>`).join('')}</ul>`;
  return h+`</section>`;}
let ALLDOCS={at:0,docs:null};
async function recentDocs(){if(ALLDOCS.docs&&Date.now()-ALLDOCS.at<60000)return ALLDOCS.docs;
  const s=await C.day.where('date','>=',shiftDate(todayYmd(),-400)).get();ALLDOCS={at:Date.now(),docs:s.docs.map(d=>normDay(d.data(),d.id))};return ALLDOCS.docs;}
window.doSearch=async()=>{const q=SEARCH.q.trim().slice(0,30);if(q.length<2)return;SEARCH.busy=true;render();
  try{const docs=await recentDocs();const isNum=/^\d+$/.test(q);const rows=[];
    docs.forEach(d=>d.bookings.forEach(b=>{const hit=isNum?(b.mrn===q||String(b.rawText||'').startsWith(q)):(String(b.patientName||'').includes(q)||String(b.rawText||'').includes(q));
      if(hit){const t=thById(b.therapistId);rows.push(Object.assign({},b,{date:d.date,therapist:t?t.name:'#'+b.therapistId}));}}));
    rows.sort((a,b)=>a.date<b.date?1:a.date>b.date?-1:b.startMin-a.startMin);SEARCH.rows=rows.slice(0,60);}
  catch(e){toast('검색하지 못했습니다');}
  SEARCH.busy=false;render();};
window.pickPast=i=>{const p=SEARCH.rows&&SEARCH.rows[i];if(!p)return;const D=D_();
  const same=D.therapists.find(t=>t.name===p.therapist);const startMin=p.startMin+p.durationMin<=D.endMin?p.startMin:DAY_START;
  openEd({kind:'copyin',source:p,draft:{therapistId:same?same.id:(D.therapists[0]||{}).id,startMin,durationMin:p.durationMin,mrn:p.mrn,room:p.room,patientName:p.patientName,
    visitNo:p.visitNo==null?null:p.visitNo+1,code:p.code,codeColor:p.codeColor,color:p.color==='#ffe599'?'':p.color,visited:false,note:p.note||''}});};
function calendarPanel(date){const {year,month}=splitYmd(date);const n=daysInMonth(year,month);const firstDow=new Date(year,month-1,1).getDay();
  const cells=[...Array(firstDow).fill(null),...Array.from({length:n},(_,i)=>i+1)];while(cells.length%7)cells.push(null);
  const has=new Set(META.dataDays),today=todayYmd();
  return `<section class="panel cal"><div class="cal-head">${year}년 ${month}월</div><div class="cal-grid">${WEEKDAYS.map((w,i)=>`<div class="cal-dow ${i===0?'sun':i===6?'sat':''}">${w}</div>`).join('')}
    ${cells.map((d,i)=>{if(d==null)return '<div></div>';const s=ymd(year,month,d);const dow=i%7;
      return `<a href="${href('schedule',{date:s})}" class="cal-day ${s===date?'on':''} ${s===today?'today':''} ${has.has(s)?'has':''} ${dow===0||isHoliday(s)?'sun':dow===6?'sat':''}" ${isHoliday(s)?'title="공휴일"':''}>${d}</a>`;}).join('')}</div></section>`;}
function legendPanel(){return `<section class="panel legend ${PAINT?'painting':''}">${LEGEND.map(l=>`<button type="button" class="legend-row ${PAINT===l.hex?'on':''}" onclick="setPaint('${l.hex}')" title="누르면 칠하기 모드"><span class="legend-swatch" style="background:${l.hex}"></span><span>${esc(l.label)}</span></button>`).join('')}
  <div class="legend-hint">${PAINT?`칠하기 모드: <strong>${esc((LEGEND.find(l=>l.hex===PAINT)||{}).label)}</strong> · 표의 칸을 누르면 바로 칠해집니다. 다시 누르거나 Esc 로 해제`:'색을 누르면 표에 칠할 수 있습니다'}</div></section>`;}
function notePanel(D){return `<section class="panel"><div class="panel-head"><h2>특이사항</h2></div>
  <textarea id="dayNote" rows="4" placeholder="예: 추석 연휴, Zoe OT 휴무">${esc(D.note)}</textarea>
  <div class="row"><button type="button" onclick="saveDayNote()">저장</button></div>${D.note?`<p class="special">${esc(D.note)}</p>`:''}</section>`;}
window.saveDayNote=()=>{const v=document.getElementById('dayNote').value;if(v===D_().note)return;run(R.q.date,opNote(v),false);};
function manualPanel(D){
  const byNo=new Map();for(const m of D.manual)byNo.set(m.no,[...(byNo.get(m.no)||[]),m]);
  const maxNo=Math.max(0,...D.manual.map(m=>m.no));const rowCount=maxNo<20?20:20+5*(Math.floor((maxNo-20)/5)+1);
  const names=[...new Set([...D.manualTherapists,...D.manual.map(m=>String(m.therapistName||'').trim()).filter(Boolean)])];
  const countOf=n=>D.manual.filter(m=>String(m.therapistName||'').trim().toUpperCase()===n.toUpperCase()).length;
  const singleIds=new Set(D.therapists.filter(t=>t.single).map(t=>t.id));const cancelled=D.cancels.length;
  const total=D.bookings.filter(b=>b.visited&&!singleIds.has(b.therapistId)).length;
  const edRow=no=>`<tr class="editing-row"><td>${no}</td>
    <td><input id="mnMrn" value="${A(MAN.f.mrn)}" inputmode="numeric" placeholder="환자번호" oninput="this.value=this.value.replace(/\\D/g,'').slice(0,7);MAN.f.mrn=this.value" onkeydown="manKey(event)"></td>
    <td><input value="${A(MAN.f.patientName)}" placeholder="성함" oninput="MAN.f.patientName=this.value" onkeydown="manKey(event)"></td>
    <td><input value="${A(MAN.f.therapistName)}" placeholder="치료사" list="manNames" oninput="MAN.f.therapistName=this.value" onkeydown="manKey(event)"></td>
    <td class="nowrap"><button type="button" class="icon" onclick="manSave()">저장</button> <button type="button" class="ghost icon" onclick="manCancel()">취소</button></td></tr>`;
  let rows='';
  for(let no=1;no<=rowCount;no++){const list=byNo.get(no)||[];
    if(!list.length){rows+=MAN.no===no&&MAN.id==null?edRow(no):`<tr class="blank editable" onclick="manNew(${no})"><td>${no}</td><td></td><td></td><td></td><td></td></tr>`;continue;}
    for(const m of list){if(MAN.id===m.id){rows+=edRow(no);continue;}
      rows+=`<tr style="${m.color?`background:${A(m.color)}`:''}" class="${m.color?'colored':''} ${PAINT?'paintable':''}" title="${A(manSrcTitle(m))}" onclick="manRowClick(${m.id})">
        <td>${m.no}${manSrcTag(m)}</td><td class="ed" onclick="manEdit(${m.id},event)">${esc(m.mrn)}</td>
        <td class="name-cell ${m.note?'has-note':''}"><span class="ed" onclick="manEdit(${m.id},event)">${esc(m.patientName)}</span>
          <div class="note-pop" onclick="event.stopPropagation()"><div class="note-head">메모 · ${esc(m.patientName||m.mrn)}</div><textarea rows="5" placeholder="메모" onblur="manNoteBlur(${m.id},this)" onkeydown="event.stopPropagation();if(event.key==='Enter'&&(event.ctrlKey||event.metaKey))this.blur()">${esc(m.note||'')}</textarea>
          <div class="note-foot"><span class="who small">창 밖을 누르거나 Ctrl+Enter 로 저장</span></div></div></td>
        <td class="ed" onclick="manEdit(${m.id},event)">${esc(m.therapistName)}</td>
        <td class="nowrap">${PAINT?'':`<button type="button" class="swatch tiny" title="줄 색 바꾸기" style="background:${A(m.color||'#ffffff')}" onclick="event.stopPropagation();MAN.colorFor=MAN.colorFor===${m.id}?null:${m.id};render()"></button><button type="button" class="ghost danger icon" title="삭제" onclick="event.stopPropagation();manDel(${m.id})">✕</button>`}
          ${MAN.colorFor===m.id?`<div class="swatch-row pop" onclick="event.stopPropagation()">${PALETTE.map(c=>`<button type="button" title="${A(c.label)}" class="swatch ${(m.color||'#ffffff')===c.hex?'on':''}" style="background:${c.hex}" onclick="manColor(${m.id},'${c.hex}')"></button>`).join('')}</div>`:''}</td></tr>`;}}
  return `<section class="panel"><div class="panel-head"><h2>Manual Tx</h2></div><p class="small">TA, Finger, Sprain 외에는 모두 진행 · 빈 줄을 누르면 입력, 성함에 마우스를 올리면 메모</p>
    <datalist id="manNames">${names.map(n=>`<option value="${A(n)}">`).join('')}</datalist>
    <div class="manual-scroll"><table class="mini manual"><thead><tr><th>번호</th><th>환자번호</th><th>성함</th><th>치료사</th><th title="색 / 삭제">색</th></tr></thead><tbody>${rows}</tbody></table></div>${manHiddenHtml()}
    <table class="mini manual-count"><tbody>${names.map((n,i)=>`<tr><td class="no">${i+1}</td><td>${esc(n)}</td><td class="${countOf(n)?'hit':''}">${countOf(n)}</td></tr>`).join('')}
      <tr class="sum"><td></td><td title="취소/변경 칸에 들어간 기록 수">취소</td><td>${cancelled}</td></tr>
      <tr class="sum"><td></td><td title="취소 ÷ 오늘 비급여 치료 수">취소율</td><td>${total?Math.round(cancelled/total*100):0}%</td></tr>
      <tr class="sum"><td></td><td title="오늘 비급여 치료 수 (내원 점이 찍힌 예약)">비급여 치료</td><td>${total}</td></tr></tbody></table>
    <table class="mini manual-count summary"><tbody>
      <tr><td class="lbl green">도수+충격파</td><td>${D.bookings.filter(b=>b.visited&&!/^CRYO/i.test(normalizeCode(b.code))).length}</td></tr>
      <tr><td class="lbl blue">신장분사+Hilt</td><td>${D.bookings.filter(b=>b.visited&&/^CRYO/i.test(normalizeCode(b.code))).length}</td></tr></tbody></table></section>`;}
/* ═════ 겹쳐서 안 보이는 예약 (2026-10-07: 빈 칸인데 '이미 예약이 있다'고 막힘) ═════
   표는 한 칸에 예약 하나만 그린다 — 같은 치료사의 같은 시간에 예약이 둘 이상이거나, 명단에서 빠진(숨긴·전체 삭제) 치료사의 예약,
   표 시간 밖 예약은 화면에 안 보이지만 자리를 차지한다. 그런 예약을 표 위에 빨간 줄로 보여 주고, 누르면 그 예약 창을 연다(옮기거나 지우기) */
function hiddenBookings(D){const out=[];const shown=new Set(D.therapists.map(t=>t.id));const allIds=new Set((D.allTherapists||D.therapists).map(t=>t.id));
  const seen=new Map();
  D.bookings.slice().sort((a,b)=>a.startMin-b.startMin||a.id-b.id).forEach(b=>{
    if(!allIds.has(b.therapistId)){out.push({b,why:'명단에 없는 치료사'});return;}
    if(!shown.has(b.therapistId))return;   // 휴무자 숨기기로 가린 열 — 일부러 숨긴 것
    if(b.startMin<DAY_START||b.startMin+b.durationMin>D.endMin){out.push({b,why:'표 시간 밖'});return;}
    const prev=seen.get(b.therapistId);
    if(prev&&b.startMin<prev.startMin+prev.durationMin){out.push({b,why:'다른 예약과 겹침 ('+hm(prev.startMin)+' '+(prev.patientName||prev.mrn||'')+')'});}
    if(!prev||b.startMin+b.durationMin>prev.startMin+prev.durationMin)seen.set(b.therapistId,b);});
  return out;}
function hiddenBar(D){const L=hiddenBookings(D);if(!L.length)return '';const nm=id=>(thById(id)||{}).name||('#'+id);
  return `<div class="hint" style="margin:6px 0;border-color:#fca5a5;background:#fef2f2;justify-content:flex-start"><b style="color:#b91c1c;white-space:nowrap">⚠ 표에 안 보이는 예약 ${L.length}건</b>${L.map(x=>`<span class="np-chip" style="border-color:#fca5a5;background:#fff">${esc(nm(x.b.therapistId))} ${hm(x.b.startMin)}~${hm(x.b.startMin+x.b.durationMin)} <b>${esc(x.b.patientName||x.b.mrn||'(이름 없음)')}</b> <span class="who small">${esc(x.b.code||'')} · ${esc(x.why)}</span> <button type="button" class="ghost" onclick="openHidden(${x.b.id})">열기</button></span>`).join('')}<span class="who small">자리를 차지해서 그 칸에 새 예약이 안 들어갑니다 — 열어서 옮기거나 지우세요</span></div>`;}
window.openHidden=id=>{const b=D_().bookings.find(x=>x.id===id);if(b)openEd({kind:'booking',booking:b});};

/* ═════ 처방 나온 첫 방문(1회차) 환자 → [추가] (2026-10-07 요청) ═════
   오늘 보드에서 동선에 신장분사·충격파가 있거나 그 처방(CRYO·EES·CE·ES 코드)이 나온 환자 중, 예약표에 예전 예약이 하나도 없는 환자(1회차)를
   제목 아래에 '이름 차트번호 [추가]' 로 띄운다. 누르면 이름·차트번호·진료실·치료코드·시간(지금 다음 15분 칸, 그때 비어 있는 치료사)·방문수 1 을 채운 새 예약 창.
   오늘 예약표에 이미 있으면 빠진다. 오늘 날짜에만 */
let RXT={at:0,docs:null,loading:false};
function todayRx(){const today=todayYmd();if(RXT.docs&&RXT.day===today&&Date.now()-RXT.at<60000)return RXT.docs;
  if(!RXT.loading){RXT.loading=true;DB.collection('bitRx').where('date','==',today).get().then(s=>{RXT={at:Date.now(),day:today,docs:s.docs.map(d=>d.data()||{}),loading:false};safeRender();})
    .catch(e=>{console.warn('bitRx',e);RXT={at:Date.now(),day:today,docs:[],loading:false};});}
  return RXT.docs||[];}
const RX4=/^(CRYO|EES|CE|ES)\d+$/;
/* 1회차 = 그 치료(신장분사 / 충격파)를 예약표에서 처음 받는 환자 (2026-10-07 고침: 예전에 도수만 받았던 환자도 신장분사는 1회차).
   치료 갈래: CRYO… = 신장분사, EES·CE·ES… = 충격파. 처방 코드가 아직 없으면 동선의 방(신장분사·충격파)으로. 오늘 예약표에 이미 있으면 빠짐 */
const txFam=c=>{c=normalizeCode(c);return /^CRYO\d/.test(c)?'신장분사':/^(EES|CE|ES)\d/.test(c)?'충격파':'';};
function newPtCands(D){if(D.date!==todayYmd()||!BOARD)return [];const hist=ALLDOCS.docs;if(!hist){recentDocs().then(()=>safeRender()).catch(()=>{});return [];}
  const rx=todayRx();const had=new Map();   // 차트번호 → 예전에 받은 치료 갈래
  hist.forEach(d=>{if(d.date>=D.date)return;(d.bookings||[]).forEach(b=>{const m=mrnKey(b.mrn),fm=txFam(b.code);if(m&&fm){if(!had.has(m))had.set(m,new Set());had.get(m).add(fm);}});});
  const today=new Set((DAYDOC?DAYDOC.bookings:[]).map(b=>mrnKey(b.mrn)).concat(DAYDOC&&DAYDOC.npHide||[]).filter(Boolean));   // npHide: ✕ 로 지운 환자 (2026-10-10)
  const out=[],seen=new Set();
  BOARD.forEach(p=>{if(p.discharged)return;const mrn=mrnKey(p.mrn);if(!mrn||seen.has(mrn)||today.has(mrn))return;const route=Array.isArray(p.route)?p.route:[];
    const codes=[];let cryo3=false;rx.filter(r=>mrnKey(r.mrn)===mrn).forEach(r=>(r.items||[]).forEach(it=>{const c=normalizeCode(it.cod);if(c==='CRYO3'){cryo3=true;return;}if(RX4.test(c)&&!codes.includes(c))codes.push(c);}));
    if(!codes.length&&(cryo3||!route.some(r=>r==='신장분사'||r==='충격파')))return;   // CRYO3 만 나온 환자는 빼기 (2026-10-07 요청)
    const fams=codes.length?[...new Set(codes.map(txFam).filter(Boolean))]:route.filter(r=>r==='신장분사'||r==='충격파');
    const prev=had.get(mrn)||new Set();const first=fams.filter(fm=>!prev.has(fm));
    if(!first.length)return;   // 그 치료를 예전에 받은 적이 있음 — 1회차 아님
    const fc=codes.filter(c=>first.includes(txFam(c)));
    const clinic=[...route].reverse().find(r=>/^진료실\s*\d/.test(r));
    const past=[];hist.forEach(d=>{if(d.date>=D.date)return;(d.bookings||[]).forEach(b=>{if(mrnKey(b.mrn)===mrn)past.push(Object.assign({},b,{date:d.date,therapist:(thById(b.therapistId)||{}).name||('#'+b.therapistId)}));});});
    past.sort((a,b)=>a.date<b.date?1:a.date>b.date?-1:b.startMin-a.startMin);
    out.push({allPast:past.map(x=>Number(x.visitNo)||0),past:past.slice(0,2),mrn,name:String(p.name||'').trim(),room:clinic?clinic.replace(/\D/g,''):'',code:(fc[0]||codes[0]||''),codes:fc.length?fc:codes,fams:first});seen.add(mrn);});
  return out;}
function newPtBar(D){const L=newPtCands(D);if(!L.length)return '';
  const withPast=L.map((c,i)=>Object.assign({i},c)).filter(c=>c.past.length),none=L.map((c,i)=>Object.assign({i},c)).filter(c=>!c.past.length);
  let h='';
  /* 예전 예약이 있는 환자 — 환자 검색 결과처럼: 날짜·치료사·시간, 이름·코드, 메모, [이 날로 가져오기] (2026-10-07 요청) */
  if(withPast.length)h+=`<div class="hint np-past" style="margin:6px 0;display:block"><b>처방 나온 1회차</b> <span class="who small">— 예전 예약이 있는 환자는 그 기록을 바탕으로 가져오세요 (치료코드는 예전 기록 그대로 · 안 할 환자는 ✕)</span>
    <ul class="list search np-list">${withPast.map(c=>`<li><div class="np-who"><button type="button" class="ghost np-x" title="이 목록에서 지우기 (오늘 안 함) — 모든 PC" onclick="npHide('${esc(c.mrn)}','${A(c.name)}')">✕</button><b>${esc(c.name)}</b> <span class="who small">${esc(c.mrn)}${c.room?' · 진료실'+esc(c.room):''} · 오늘 ${esc(c.codes.join(' ')||c.fams.join('·'))} 1회차</span></div>
      ${c.past.map((r,k)=>`<div class="search-row"><div>
        <div><strong>${esc(r.date)}</strong> <span class="who small">${esc(r.therapist)} · ${hm(r.startMin)} · ${r.durationMin}분</span></div>
        <div>${esc(r.mrn)}${r.room?`(${esc(r.room)})`:''} ${esc(r.patientName)}${r.visitNo??''} ${r.code?`<span class="who small">${esc(r.code)}</span>`:''} ${r.visited?'<span class="who small">내원</span>':''}</div>
        ${r.note?`<div class="search-note">${esc(r.note)}</div>`:''}</div>
        <button type="button" class="ghost" onclick="newPtPast(${c.i},${k})">이 날로<br>가져오기</button></div>`).join('')}</li>`).join('')}</ul></div>`;
  /* 예전 기록이 아예 없는 환자 — 지금처럼 */
  if(none.length)h+=`<div class="hint" style="margin:6px 0;justify-content:flex-start"><b style="white-space:nowrap">처방 나온 1회차</b>${none.map(c=>`<span class="np-chip">${esc(c.name)} <span class="who small">${esc(c.mrn)}${c.room?' · 진료실'+esc(c.room):''}${c.code?' · '+esc(c.codes.join(' ')):' · '+esc(c.fams.join('·'))} 1회차</span> <button type="button" class="ghost" onclick="newPtAdd(${c.i})">+ 추가</button><button type="button" class="ghost np-x" title="이 목록에서 지우기 (오늘 안 함) — 모든 PC" onclick="npHide('${esc(c.mrn)}','${A(c.name)}')">✕</button></span>`).join('')}</div>`;
  return h;}
/* 예전 기록으로 가져오기 — 환자 검색의 [이 날로 가져오기]와 같다: 치료코드·길이는 예전 치료 그대로 (2026-10-10 요청: 오늘 처방(CRYO10 등)으로 바뀌었다), 진료실은 오늘 진료실 */
window.newPtPast=(i,k)=>{const D=D_();const c=newPtCands(D)[i];const p=c&&c.past[k];if(!p)return;
  const same=D.therapists.find(t=>t.name===p.therapist);const code=p.code;const dur=p.durationMin;
  const startMin=p.startMin+dur<=D.endMin?p.startMin:DAY_START;
  openEd({kind:'copyin',source:p,draft:{therapistId:same?same.id:(D.therapists[0]||{}).id,startMin,durationMin:dur,mrn:p.mrn,room:c.room||p.room,patientName:p.patientName||c.name,
    visitNo:Math.max(0,...(c.allPast||[]))+1,code,codeColor:p.codeColor||'',color:'',visited:false,note:p.note||''}});};   // 방문수 = 예전 기록의 마지막 방문수 + 1 (환자 검색과 이어지게)
/* 처방 나온 1회차 목록에서 지우기 (2026-10-10 요청: 한다고 했다가 안 하면 지울 수 없었다) — 그 날 문서의 npHide 에 차트번호, 모든 PC 에서 빠진다 */
window.npHide=(mrn,name)=>{if(!mrn||!confirm((name||mrn)+' 님을 처방 나온 1회차 목록에서 지울까요? (오늘만, 모든 PC)'))return;
  run(R.q.date,ctx=>{const L=ctx.d.npHide||[];if(!L.includes(mrn))ctx.d.npHide=L.concat(mrn);aud(ctx,'update','day',ctx.d.date,null,{npHide:mrn,patientName:name||''});return {ok:true};},false);};
window.newPtAdd=i=>{const D=D_();const c=newPtCands(D)[i];if(!c)return;
  const now=new Date();let st=Math.ceil((now.getHours()*60+now.getMinutes())/SLOT)*SLOT;st=Math.max(DAY_START,Math.min(st,D.endMin-SLOT));
  const dur=Math.min(codeMinutes(c.code)||30,D.endMin-st);
  const occ=D.occ||new Map();const free=t=>{const a=occ.get(t.id);if(!a)return false;for(let m=st;m<st+dur;m+=SLOT){const k=(m-DAY_START)/SLOT;if(!a[k]||a[k].type!=='free')return false;}return true;};
  const th=D.therapists.find(free)||D.therapists[0];if(!th){toast('이 날 치료사 명단이 없습니다');return;}
  openEd({kind:'new',therapistId:th.id,startMin:st,maxDuration:dur,draft:{therapistId:th.id,startMin:st,durationMin:dur,mrn:c.mrn,room:c.room,patientName:c.name,visitNo:1,code:c.code,codeColor:'',color:'',visited:false,note:''}});
  MSG=`처방 나온 1회차 환자입니다. 치료사(${th.name})·시간(${hm(st)})을 확인하고 저장하세요.`;renderEditor();};

/* ═════ SASO 환자 → Manual Tx 자동 (2026-10-07 요청: Manual Tx = SASO 명단) ═════
   오늘 날짜를 보고 있으면, 동선관리 보드에서 동선에 SASO 가 있는 환자를 Manual Tx 에 넣는다(차트번호로 한 번만).
   치료사: 카드에서 SASO 방 담당으로 고른 사람(없으면 SASO 에서 [진행]을 누른 사람). 이미 있는 줄은 치료사가 비었거나 'null' 일 때만 채운다.
   보드에서 빠지거나 SASO 가 지워져도 줄은 지우지 않는다(직원이 ✕ 로) */
/* 2026-10-09 요청으로 'SASO 환자 전부' 자동은 껐다. 2026-10-11 요청: 주사 혜택 환자만 자동으로 —
   오늘 4층 관리에서 무료 치료(SASO·아쿠아·롤러 중 1개)를 고른 환자만 (2026-10-11 다시 좁힘 — 리뷰만 한 환자·기본물리치료 환자는 넣지 않음).
   보너스 기록 = 동선관리 patientboard_v3/…/bonus/{차트번호} (injDays·review·uses). 직원이 ✕ 로 지운 환자는 그 날 다시 넣지 않는다(manNo).
   예전 규칙(SASO 전부)으로 들어와 아무도 손대지 않은 오늘 줄 중 위 조건이 아닌 것은 뺀다 */
const SASO_AUTO=true;
let BONUS4={},BONUS4_SUB=null,BONUS4_READY=false;
const BONUS_DAYS4=3, BONUS_ROOMS4=['SASO','아쿠아','롤러','기본물리치료'];
function injRecent4(b,today){const t=new Date(today+'T12:00:00').getTime();return (Array.isArray(b&&b.injDays)?b.injDays:[]).some(d=>{const g=Math.round((t-new Date(String(d)+'T12:00:00').getTime())/864e5);return g>=0&&g<BONUS_DAYS4;});}
let BOARD=null,BOARD_SUB=null,SASO_BUSY=false;
const nullTh=s=>!String(s||'').trim()||/^null$/i.test(String(s).trim());
const mrnKey=s=>String(s||'').replace(/\D/g,'');
function watchBoard(){if(!BONUS4_SUB)BONUS4_SUB=DB.collection('patientboard_v3').doc('반듯한정형외과').collection('bonus').onSnapshot(s=>{const m={};s.docs.forEach(d=>{const v=d.data()||{};const k=mrnKey(v.mrn||d.id);if(k)m[k]=v;});BONUS4=m;BONUS4_READY=true;sasoSync();safeRender();},e=>console.warn('bonus',e));
  if(BOARD_SUB)return;
  BOARD_SUB=DB.collection('patientboard_v3').doc('반듯한정형외과').collection('patients').onSnapshot(s=>{BOARD=s.docs.map(d=>d.data()||{});sasoSync();},e=>console.warn('board',e));}
function sasoCands(){const today=todayYmd();
  return (BOARD||[]).filter(p=>mrnKey(p.mrn)&&Array.isArray(p.route)).filter(p=>{const b=BONUS4[mrnKey(p.mrn)];if(!b)return false;
      const usedToday=(Array.isArray(b.uses)?b.uses:[]).some(u=>u&&u.date===today);
      return usedToday;})   // 2026-10-11 요청: 4층 관리에서 무료 치료(SASO·아쿠아·롤러 중 1개)를 고른 환자만 — 나머지는 직원이 손으로
    .map(p=>{const b=BONUS4[mrnKey(p.mrn)]||{};const th=BONUS_ROOMS4.map(r=>((p.roomDocs||{})[r])||((p.progLog||{})[r])).find(Boolean)||'';
      const used=(Array.isArray(b.uses)?b.uses:[]).filter(u=>u&&u.date===today).map(u=>u.item);const inj=(Array.isArray(b.injDays)?b.injDays:[]).slice().sort().pop()||'';
      const why=used.length?'오늘 무료 '+used.join('·'):('주사 '+inj.slice(5).replace('-','/')+(b.review?' + 리뷰':'')+(p.route.includes('기본물리치료')?' · 기본물리치료':''));
      return {mrn:mrnKey(p.mrn),name:String(p.name||'').trim(),th:String(th).trim(),why};});}
/* 자동으로 들어와 아무도 손대지 않은 줄 (메모·색 없음, 마지막으로 고친 게 자동) */
const autoUntouched=m=>(m.auto==='saso'||m.auto==='bonus')&&(m.updatedBy==='SASO 자동'||m.updatedBy==='주사 혜택 자동')&&nullTh(m.therapistName)&&!String(m.note||'').trim()&&!m.color;   // 치료사 이름이 들어간 줄은 그대로 둔다 (2026-10-11 요청)
/* 치료사 이름이 있는데 숨겨진 줄 — 다시 보이게 (2026-10-11: 치료사를 바꿔 둔 줄까지 숨겼다) */
const sasoThBack=d=>(d?d.manual:[]).filter(m=>m.hidden&&!m.bonusBack&&!nullTh(m.therapistName));
/* 빼야 할 자동 줄: 주사 혜택 환자가 아님 (빨간 SASO = 예전 규칙 줄 포함).
   지우지 않고 숨긴다(hidden) — 아직 켜져 있는 예전 4층 창은 '그 환자 줄이 있다'고 보고 다시 넣지 않는다 (2026-10-11: 지우면 예전 창이 곧바로 다시 넣었다) */
const sasoStale=(d,cands)=>(d?d.manual:[]).filter(m=>!m.hidden&&autoUntouched(m)&&!cands.some(c=>c.mrn===mrnKey(m.mrn)));
/* 빨간 SASO 줄인데 주사 혜택 환자면 파란 주사 줄로 바꾼다 (2026-10-11 요청) */
const sasoRedOk=(d,cands)=>(d?d.manual:[]).filter(m=>!m.hidden&&m.auto==='saso'&&autoUntouched(m)&&cands.some(c=>c.mrn===mrnKey(m.mrn)));
function sasoTodo(d,cands){const no=(d&&d.manNo)||[];const out=[];for(const c of cands){if(no.includes(c.mrn))continue;const m=(d?d.manual:[]).find(x=>mrnKey(x.mrn)===c.mrn);if(!m||m.hidden&&!m.bonusBack)out.push(c);else if(c.th&&nullTh(m.therapistName))out.push(c);}return out;}
const opSaso=cands=>ctx=>{const d=ctx.d;let no=Math.max(0,...d.manual.filter(m=>!m.hidden).map(m=>Number(m.no)||0));let n=0;const now=new Date().toISOString();
  sasoRedOk(d,cands).forEach(m=>{const c=cands.find(x=>x.mrn===mrnKey(m.mrn));m.auto='bonus';m.why=c.why||'';m.updatedBy='주사 혜택 자동';m.updatedAt=now;if(c.th&&nullTh(m.therapistName))m.therapistName=c.th;aud(ctx,'update','manual_tx',m.id,{auto:'saso'},{auto:'bonus',why:m.why});n++;});
  {const tb=sasoThBack(d);tb.forEach(m=>{m.hidden=false;m.updatedBy='자동 (치료사 있음)';m.updatedAt=now;   /* 고친 사람 표시를 바꿔 두어야 아직 새 버전을 안 받은 다른 PC 화면이 다시 숨기지 않는다 (2026-10-11: 서로 숨기고 꺼내며 깜빡였다) */
    aud(ctx,'update','manual_tx',m.id,{hidden:true},{hidden:false,reason:'치료사 있음 — 다시 보임'});n++;});
   if(tb.length){let k=0;d.manual.filter(m=>!m.hidden).sort((a,b)=>(a.no||0)-(b.no||0)).forEach(m=>{m.no=++k;});no=k;}}
  {const st=sasoStale(d,cands);st.forEach(m=>{m.hidden=true;m.updatedAt=now;aud(ctx,'delete','manual_tx',m.id,m,{hidden:true,reason:'주사 혜택 환자 아님 (자동 정리 · 숨김)'});n++;});
   if(st.length){let k=0;d.manual.filter(m=>!m.hidden).sort((a,b)=>(a.no||0)-(b.no||0)).forEach(m=>{m.no=++k;});no=k;}}   // 숨긴 줄 자리를 비워 두지 않고 번호를 1부터 다시 (빈칸 없게)
  for(const c of sasoTodo(d,cands)){let m=d.manual.find(x=>mrnKey(x.mrn)===c.mrn);
    if(m&&m.hidden){m.hidden=false;m.bonusBack=true;m.no=++no;m.auto='bonus';m.why=c.why||'';m.updatedBy='주사 혜택 자동';m.updatedAt=now;if(c.th&&nullTh(m.therapistName))m.therapistName=c.th;aud(ctx,'update','manual_tx',m.id,{hidden:true},{hidden:false,why:m.why});n++;continue;}   // 숨겼던 환자가 오늘 무료 치료를 골랐으면 다시 보이게
    if(!m){const row={id:newId(d),no:++no,mrn:c.mrn,patientName:c.name,therapistName:c.th,color:'',note:'',auto:'bonus',why:c.why||'',updatedBy:'주사 혜택 자동',createdAt:now,updatedAt:now};d.manual.push(row);aud(ctx,'create','manual_tx',row.id,null,row);}
    else{const bf=m.therapistName;m.therapistName=c.th;m.updatedBy=m.auto==='bonus'?'주사 혜택 자동':'SASO 자동';m.updatedAt=now;aud(ctx,'update','manual_tx',m.id,{therapistName:bf},{therapistName:c.th});}
    if(c.th)ctx.extra.manualName=c.th;n++;}
  return n?{ok:true}:{ok:false,noop:true};};
async function sasoSync(){const date=R.q.date;if(!SASO_AUTO||SASO_BUSY||!BOARD||!(R.page==='schedule'||R.page==='m')||date!==todayYmd()||DAYDOC===undefined)return;
  const cands=sasoCands();if(!sasoTodo(DAYDOC,cands).length&&!sasoStale(DAYDOC,cands).length&&!sasoRedOk(DAYDOC,cands).length&&!sasoThBack(DAYDOC).length)return;
  SASO_BUSY=true;NO_UNDO=true;try{await commitDay(date,opSaso(cands));}catch(e){console.warn('saso',e);}NO_UNDO=false;SASO_BUSY=false;}
/* Manual Tx 줄이 어디서 왔는지 (2026-10-11 요청: 주사 맞은 환자인지, 동선관리 SASO 목록인지 확인)
   주사 = 지금 규칙(주사 혜택 환자)으로 자동 · SASO = 예전 규칙(동선에 SASO 가 있는 환자 전부)으로 자동 · 표시 없음 = 직원이 직접 넣음 */
const hhmm4=v=>{const d=new Date(v||'');return isNaN(d)?'':String(d.getHours()).padStart(2,'0')+':'+String(d.getMinutes()).padStart(2,'0');};
function manSrcTag(m){return m.auto==='bonus'?'<span class="man-src b">주사</span>':m.auto==='saso'?'<span class="man-src s">SASO</span>':'';}
function manSrcTitle(m){const t=hhmm4(m.createdAt||m.updatedAt);
  return m.auto==='bonus'?`주사 혜택 환자 — 동선관리에서 자동 (${m.why||''})${t?' · '+t:''}`
    :m.auto==='saso'?`예전 규칙: 동선관리 SASO 목록에서 자동${t?' · '+t:''}${m.updatedBy&&m.updatedBy!=='SASO 자동'?' · 고친 사람 '+m.updatedBy:''}`
    :`직접 입력${m.updatedBy?' · '+m.updatedBy:''}${t?' · '+t:''}`;}
/* 숨긴 자동 줄 (2026-10-11) — 주사 혜택 환자가 아니라서 숨긴 자동 줄을 보고, 필요하면 [되살리기]. 되살린 줄은 직원 줄로 보고 다시 숨기지 않는다 */
let MAN_HID_OPEN=false;
/* 지난 날짜 자동 줄 정리 (2026-10-11 요청) — 오늘과 같은 기준: 치료사·메모·색 없는 자동 줄은 숨기고, 그 날 4층 관리에서 무료 치료를 고른 환자 줄은 파란 '주사'로 남긴다 */
const MAN_AUTO_FROM='2026-10-07';   // 자동 넣기가 생긴 날
function bonusCandsOn(date){return Object.entries(BONUS4||{}).map(([mrn,b])=>{const used=(Array.isArray(b.uses)?b.uses:[]).filter(u=>u&&u.date===date).map(u=>u.item);
  return used.length?{mrn,why:date.slice(5).replace('-','/')+' 무료 '+used.join('·'),th:''}:null;}).filter(Boolean);}
const opManClean=cands=>ctx=>{const d=ctx.d;const now=new Date().toISOString();let n=0;
  sasoRedOk(d,cands).forEach(m=>{const c=cands.find(x=>x.mrn===mrnKey(m.mrn));m.auto='bonus';m.why=c.why;m.updatedBy='주사 혜택 자동';m.updatedAt=now;n++;});
  const st=sasoStale(d,cands);st.forEach(m=>{m.hidden=true;m.updatedAt=now;aud(ctx,'delete','manual_tx',m.id,m,{hidden:true,reason:'지난 날짜 자동 줄 정리'});n++;});
  if(st.length){let k=0;d.manual.filter(m=>!m.hidden).sort((a,b)=>(a.no||0)-(b.no||0)).forEach(m=>{m.no=++k;});}
  return n?{ok:true,n:st.length}:{ok:false,noop:true,message:'정리할 자동 줄이 없습니다.'};};
function manCleanCount(d,date){return d?sasoStale(d,bonusCandsOn(date)).length:0;}
window.manCleanDay=()=>{const date=R.q.date;const k=manCleanCount(DAYDOC,date);if(!k)return;
  if(!confirm(date+' Manual Tx 에서 치료사·메모·색이 없는 자동 줄 '+k+'개를 숨길까요?\n(그 날 4층 관리에서 무료 치료를 고른 환자는 남깁니다 · 숨긴 줄은 아래에서 되살릴 수 있습니다)'))return;
  run(date,opManClean(bonusCandsOn(date)),false);};
window.manCleanAll=async()=>{const today=todayYmd();const days=(META.dataDays||[]).filter(x=>x>=MAN_AUTO_FROM&&x<today).sort();
  if(!days.length){toast('정리할 지난 날짜가 없습니다');return;}
  if(!confirm(MAN_AUTO_FROM.slice(5).replace('-','/')+'부터 어제까지 '+days.length+'일의 Manual Tx 에서, 치료사·메모·색이 없는 자동 줄을 모두 숨길까요?\n(그 날 무료 치료를 고른 환자는 남깁니다 · 숨긴 줄은 그 날짜에서 되살릴 수 있습니다)'))return;
  let total=0,dn=0;for(const day of days){const r=await commitDay(day,opManClean(bonusCandsOn(day)));if(r&&r.ok){total+=r.n||0;dn++;}}
  toast(total?(dn+'일에서 자동 줄 '+total+'개를 숨겼습니다'):'정리할 자동 줄이 없었습니다',4000);safeRender();};
function manHiddenHtml(){const L=((DAYDOC&&DAYDOC.manual)||[]).filter(m=>m.hidden);const date=R.q.date,today=todayYmd();
  if(date<today&&!BONUS4_READY)watchBoard();   // 지난 날짜 정리에 쓸 보너스 기록 — 다 받기 전엔 정리 버튼을 내지 않는다
  const k=date<today&&BONUS4_READY?manCleanCount(DAYDOC,date):0;
  const tools=(k?`<button type="button" class="ghost" onclick="manCleanDay()" title="이 날 치료사·메모·색이 없는 자동 줄을 숨깁니다">이 날 자동 줄 정리 (${k})</button> `:'')+(date<today&&BONUS4_READY?'<button type="button" class="ghost" onclick="manCleanAll()" title="자동 넣기가 생긴 10/7부터 어제까지 한꺼번에">지난 날짜 모두 정리</button>':'');
  if(!L.length)return tools?`<div class="man-hid">${tools}</div>`:'';
  return `<div class="man-hid">${tools}<button type="button" class="ghost" onclick="MAN_HID_OPEN=!MAN_HID_OPEN;render()">${MAN_HID_OPEN?'▾':'▸'} 숨긴 자동 줄 ${L.length}개</button>
    ${MAN_HID_OPEN?`<ul>${L.map(m=>`<li>${manSrcTag(m)} ${esc(m.mrn)} <b>${esc(m.patientName)}</b> ${esc(m.therapistName||'')} <button type="button" class="ghost" onclick="manUnhide(${m.id})">되살리기</button></li>`).join('')}</ul>`:''}</div>`;}
window.manUnhide=id=>run(R.q.date,ctx=>{const d=ctx.d;const m=d.manual.find(x=>x.id===id);if(!m)return {ok:false,message:'줄을 찾지 못했습니다.'};
  m.hidden=false;m.no=Math.max(0,...d.manual.filter(x=>!x.hidden&&x!==m).map(x=>Number(x.no)||0))+1;m.updatedBy=ME.name;m.updatedAt=new Date().toISOString();
  aud(ctx,'update','manual_tx',id,{hidden:true},{hidden:false,patientName:m.patientName});return {ok:true};},false);
const focusMan=()=>setTimeout(()=>{const e=document.getElementById('mnMrn');if(e)e.focus();},0);
window.manNew=no=>{if(PAINT)return;MAN={no,id:null,f:{mrn:'',patientName:'',therapistName:''},colorFor:null};render();focusMan();};
window.manEdit=(id,ev)=>{if(PAINT)return;ev.stopPropagation();const m=D_().manual.find(x=>x.id===id);if(!m)return;MAN={no:m.no,id,f:{mrn:m.mrn,patientName:m.patientName,therapistName:m.therapistName},colorFor:null};render();focusMan();};
window.manCancel=()=>{MAN.no=null;MAN.id=null;render();};
window.manKey=e=>{e.stopPropagation();if(e.key==='Enter'){e.preventDefault();manSave();}if(e.key==='Escape')manCancel();};
window.manSave=async()=>{if(MAN.no==null)return;const old=MAN.id?D_().manual.find(x=>x.id===MAN.id):null;
  const body=Object.assign({id:MAN.id||undefined,no:MAN.no,color:old?old.color||'':''},MAN.f);
  document.activeElement&&document.activeElement.blur&&document.activeElement.blur();
  if(await run(R.q.date,opManualSave(body),false)){MAN.no=null;MAN.id=null;render();}};
window.manDel=id=>{if(confirm('삭제할까요?'))run(R.q.date,opManualDelete(id),false);};
window.manColor=(id,hex)=>{MAN.colorFor=null;run(R.q.date,opManualPatch(id,{color:hex==='#ffffff'?'':hex}),false);};
window.manRowClick=id=>{if(PAINT)run(R.q.date,opManualPatch(id,{color:PAINT==='#ffffff'?'':PAINT}),false);};
window.manNoteBlur=(id,ta)=>{const m=D_().manual.find(x=>x.id===id);if(!m||ta.value===(m.note||''))return;run(R.q.date,opManualPatch(id,{note:ta.value}),false);};

/* ═════════ 입력창 (예약·비근무/차단·전원 띠·취소/변경·치료사 명단) ═════════ */
window.openEd=e=>{EDIT=e;MSG='';
  const D=D_();
  if(e.kind==='new'&&!e.draft)e.draft={therapistId:e.therapistId,startMin:e.startMin,durationMin:Math.min(30,e.maxDuration)||15,mrn:'',room:'',patientName:'',visitNo:null,code:'',codeColor:'',color:'',visited:false,note:''};
  if(e.kind==='booking')e.draft=Object.assign({},e.booking);
  if(e.kind==='restore'){const c=e.cancel;const m=/^\s*(\d{1,7})\s*(?:\(\s*(\d{1,2})\s*\))?\s*([^\d\n]+?)?\s*(\d{1,3})?\s*$/.exec(String(c.text||'').replace(/\r?\n/g,' '));
    const code=(/코드\s*([A-Za-z0-9]+)/.exec(c.note||'')||[])[1]||'';
    e.draft={therapistId:(D.therapists.find(t=>t.name===c.therapistName)||D.therapists[0]||{}).id,startMin:c.startMin,durationMin:30,mrn:(m&&m[1])||c.mrn||'',room:(m&&m[2])||'',
      patientName:String((m&&m[3])||c.patientName||'').replace(/\s+/g,''),visitNo:m&&m[4]?Number(m[4]):null,code,codeColor:'',color:c.color&&c.color!=='#ffe599'?c.color:'',visited:false,note:''};
    const k=c.bk;if(k){const x=e.draft;const th=D.therapists.find(t=>t.id===k.therapistId);if(th)x.therapistId=th.id;   // 취소할 때 기억해 둔 예약 그대로 (메모·코드·길이·방문수) — 2026-10-08
      Object.assign(x,{durationMin:k.durationMin||30,room:k.room||x.room,visitNo:k.visitNo??x.visitNo,code:k.code||x.code,codeColor:k.codeColor||'',color:k.color||x.color,note:k.note||''});}}
  if(e.kind==='off'||e.kind==='memo')e.draft={therapistId:e.therapistId,startMin:e.startMin,endMin:Math.min(e.startMin+(e.kind==='off'?60:30),D.endMin),kind:e.kind,text:'',color:e.kind==='memo'?'#d9d9d9':'#999999',all:false};
  if(e.kind==='block')e.draft=Object.assign({},e.block,{kind:e.block.kind==='memo'?'memo':'off',all:false});
  if(e.kind==='band')e.draft={therapistId:D.therapists[0].id,startMin:e.band.startMin,endMin:e.band.endMin,kind:e.band.kind==='memo'?'memo':'off',text:e.band.text,color:e.band.color||'#999999',all:true};
  if(e.kind==='cancel'){const c=e.cancel;e.draft={therapistName:c?c.therapistName:e.therapistName,startMin:c?c.startMin:e.startMin,kind:c?c.kind:'cancel',text:c?c.text:'',color:c?c.color||'':''};}
  if(e.kind==='therapists')e.draft={ids:D.therapists.map(t=>t.id),name:''};
  renderEditor();
  setTimeout(()=>{const f=document.querySelector('#editor [autofocus]');if(f)f.focus();},0);};
window.closeEd=()=>{EDIT=null;MSG='';renderEditor();};
/* 치료코드 → 예약 시간 (2026-10-07 요청: 프로그램이 바뀌면 시간도 맞춰서). 9~10월 실제 예약에서 뽑은 규칙:
   CRYO·EES·CE(충격파·신장분사) = 30분 / CM·CME·ES 뒤 숫자 ≤10 → 30분, ≤20 → 60분, ≤30 → 90분, 그 위 → 120분. 모르는 코드는 그대로 */
function codeMinutes(code){const c=normalizeCode(code);if(/^(CRYO|EES|CE)\d/.test(c))return 30;
  const m=/^(CME|CM|ES)(\d+)$/.exec(c);if(!m)return null;const n=+m[2];return n<=10?30:n<=20?60:n<=30?90:120;}
window.codeDur=v=>{if(!EDIT||!EDIT.draft)return;const want=codeMinutes(v);if(!want||want===EDIT.draft.durationMin)return;const D=D_();
  if(EDIT.draft.startMin+want>D.endMin){MSG=`${normalizeCode(v)} 는 ${want}분인데 마감 시간을 넘습니다. 시작 시간을 당겨 주세요.`;renderEditor();return;}
  const from=EDIT.draft.durationMin;EDIT.draft.durationMin=want;MSG=`치료코드에 맞춰 길이를 ${from}분 → ${want}분으로 바꿨습니다.`;renderEditor();};
window.dset=(k,v,re)=>{if(!EDIT||!EDIT.draft)return;EDIT.draft[k]=v;if(re)renderEditor();};
/* 치료코드 드롭다운 (CODE_LIST = 예전 시트 목록). 목록에 없는 지금 값(예: CRYO24(PT-))은 맨 위에 그대로 두고, [직접 입력…]으로 다른 코드도 넣을 수 있다 */
function codeSelect(cur,set){const c=String(cur||'');const extra=c&&!CODE_LIST.includes(c)?[c]:[];
  return `<select class="code-sel" onchange="let v=this.value;if(v==='__other'){v=(prompt('치료코드를 입력하세요','')||'').trim().toUpperCase();if(!v){this.value='${A(c)}';return;}const o=document.createElement('option');o.value=o.textContent=v;this.insertBefore(o,this.options[1]);this.value=v;}${A(set)}">${opt('',c,'— 선택 —')}${extra.concat(CODE_LIST).map(x=>opt(x,c,x)).join('')}<option value="__other">직접 입력…</option></select>`;}
const opt=(v,cur,label)=>`<option value="${A(v)}" ${String(v)===String(cur)?'selected':''}>${esc(label)}</option>`;
function msgHtml(){return MSG?`<p class="${/남겼습니다|복사했습니다|바꿨습니다|확인하고 저장|옮겼습니다/.test(MSG)?'info':'err'}">${esc(MSG)}</p>`:'';}
function renderEditor(){const box=document.getElementById('editor');if(!EDIT||R.page!=='schedule'){box.innerHTML='';return;}
  const e=EDIT,D=D_();if(!D){box.innerHTML='';return;}
  const head=t=>`<div class="editor-head"><strong>${t}</strong><button type="button" class="ghost" onclick="closeEd()">닫기</button></div>`;
  const thName=id=>(D.therapists.find(t=>t.id===id)||{}).name||'';
  let h='';
  if(e.kind==='choose'){h=head(`${esc(thName(e.therapistId))} · ${hm(e.startMin)}`)+`<div class="row wrap">
      <button type="button" onclick="openEd({kind:'new',therapistId:${e.therapistId},startMin:${e.startMin},maxDuration:${e.maxDuration}})">예약 입력</button>
      <button type="button" class="ghost" onclick="openEd({kind:'off',therapistId:${e.therapistId},startMin:${e.startMin}})">비근무 (회색)</button>
      <button type="button" class="ghost" onclick="openEd({kind:'memo',therapistId:${e.therapistId},startMin:${e.startMin}})">메모 / 차단 (색+글자)</button>
      ${CLIP&&CLIP.items.length?`<button type="button" class="ghost" style="border-color:var(--accent);color:var(--accent)" onclick="pasteClip({tid:${e.therapistId},min:${e.startMin}})">여기에 붙여넣기 (${CLIP.items.length}건)</button>`:''}
      <span class="who small">점심시간처럼 전원에게 칠하려면 비근무를 고른 뒤 전원 적용에 체크</span></div>`;}
  else if(['new','booking','restore','copyin'].includes(e.kind)){const d=e.draft;const isEdit=e.kind==='booking';
    const title=e.kind==='restore'?'취소/변경에서 스케줄로 되돌리기':e.kind==='copyin'?`${esc(e.source.date)} 기록을 이 날로 가져오기`:isEdit?'예약 수정':'새 예약';
    h=head(`${title} · ${esc(thName(d.therapistId))} · ${hm(d.startMin)}`)+`<div class="form-grid" onkeydown="if(event.key==='Enter'&&(event.ctrlKey||event.metaKey))edSaveBooking()">
      <label>치료사<select onchange="dset('therapistId',Number(this.value),1)">${D.therapists.map(t=>opt(t.id,d.therapistId,t.name)).join('')}</select></label>
      <label>시작<select onchange="dset('startMin',Number(this.value),1)">${TIMES.filter(m=>m<D.endMin).map(m=>opt(m,d.startMin,hm(m))).join('')}</select></label>
      <label>길이<select onchange="dset('durationMin',Number(this.value))">${DURATIONS.filter(x=>d.startMin+x<=D.endMin).map(x=>opt(x,d.durationMin,x+'분')).join('')}</select></label>
      <label>차트번호<input autofocus value="${A(d.mrn)}" inputmode="numeric" placeholder="32750" oninput="this.value=this.value.replace(/\\D/g,'').slice(0,7);dset('mrn',this.value)"></label>
      <label>진료실<input value="${A(d.room)}" inputmode="numeric" placeholder="1" oninput="this.value=this.value.replace(/\\D/g,'').slice(0,2);dset('room',this.value)"></label>
      <label>이름<input value="${A(d.patientName)}" placeholder="함수진" oninput="dset('patientName',this.value)"></label>
      <label>방문수<input value="${A(d.visitNo??'')}" inputmode="numeric" placeholder="1" oninput="this.value=this.value.replace(/\\D/g,'').slice(0,3);dset('visitNo',this.value===''?null:Number(this.value))"></label>
      <label>치료코드${codeSelect(d.code,"dset('code',v);codeDur(v)")}</label>
      <label class="wide">메모<textarea rows="5" class="ed-note" oninput="dset('note',this.value)">${esc(d.note||'')}</textarea></label></div>
      <div class="swatch-row"><span class="who small">코드 색</span>${PALETTE.map(p=>`<button type="button" title="${A(p.label)}" class="swatch ${(d.codeColor||'#ffffff')===p.hex?'on':''}" style="background:${p.hex}" onclick="dset('codeColor','${p.hex==='#ffffff'?'':p.hex}',1)"></button>`).join('')}</div>
      <div class="swatch-row"><span class="who small">환자 칸 색</span>${PALETTE.filter(p=>p.hex!=='#ffe599'&&p.hex!=='#999999').map(p=>`<button type="button" title="${A(p.label)}" class="swatch ${(d.color||'#ffffff')===p.hex?'on':''}" style="background:${p.hex}" onclick="dset('color','${p.hex==='#ffffff'?'':p.hex}',1)"></button>`).join('')}</div>
      <div class="row" style="justify-content:space-between;flex-wrap:wrap"><label class="check" style="margin:0"><input type="checkbox" ${d.visited?'checked':''} onchange="dset('visited',this.checked)"> 내원 (표시 "." + 환자 칸 노란색)</label>
        ${(d.mrn||d.patientName)?`<button type="button" class="pt-info-btn" onclick="openPatientInfo()" title="동선관리 환자 정보 창 (보드에 카드가 있으면 그 카드, 없으면 보기 전용)">👤 환자 정보</button>`:''}</div>
      ${e.kind==='restore'?'<p class="info">시간·치료사를 확인하고 저장하면 예약이 다시 생기고 취소/변경 기록은 지워집니다.</p>':''}
      ${e.kind==='copyin'?'<p class="info">과거 기록의 환자 정보·치료코드·메모가 채워져 있습니다. 시간과 치료사를 확인하고 저장하세요.</p>':''}
      ${isEdit?`<div class="row wrap cp-row"><span class="who small">다른 날로 (메모 포함)</span><input type="date" id="cpDate">
        <select id="cpTime" title="시작 시간">${TIMES.map(m=>opt(m,e.booking.startMin,hm(m))).join('')}</select>
        <select id="cpTh" title="치료사">${activeTh().map(t=>opt(t.id,e.booking.therapistId,t.name)).join('')}</select>
        <button type="button" class="ghost" ${BUSY?'disabled':''} onclick="edCopy(false)" title="원래 예약은 그대로 두고 그 날에 하나 더 (방문수 +1)">복사</button>
        <button type="button" class="ghost" ${BUSY?'disabled':''} onclick="edCopy(true)" title="그 날·시간으로 옮기고 원래 예약은 지움 (방문수 그대로)">옮기기</button></div>`:''}
      ${msgHtml()}
      <div class="editor-actions"><button type="button" ${BUSY?'disabled':''} onclick="edSaveBooking()">${BUSY?'저장 중...':'저장'}</button>
        ${isEdit?`<button type="button" class="ghost" ${BUSY?'disabled':''} onclick="edVisit()">${e.booking.visited?'방문 체크 해제':'✔ 방문 체크'}</button>`:''}
        ${e.kind==='new'?`<button type="button" class="ghost" onclick="openEd({kind:'off',therapistId:${d.therapistId},startMin:${d.startMin}})">이 시간을 비근무로</button>`:''}
        ${isEdit?`<button type="button" class="ghost" ${BUSY?'disabled':''} onclick="edCancelMove('cancel')">취소로 옮기기</button><button type="button" class="ghost" ${BUSY?'disabled':''} onclick="edCancelMove('change')">변경 기록 남기기</button>
          <button type="button" class="ghost danger" ${BUSY?'disabled':''} onclick="edDelete()">삭제</button>`:''}
        <span class="who small">Ctrl+Enter 저장 · Esc 닫기</span></div>`;}
  else if(['off','memo','block','band'].includes(e.kind)){const d=e.draft;const band=e.kind==='band';
    h=head(band?'전원 공통 구간 (점심 등)':`비근무 / 차단 · ${esc(thName(d.therapistId))}`)+`<div class="form-grid">
      <label>종류<select onchange="dset('kind',this.value,1)">${opt('off',d.kind,'비근무 (회색)')}${opt('memo',d.kind,'메모/차단 (색+글자)')}</select></label>
      <label>시작<select onchange="dset('startMin',Number(this.value),1)">${TIMES.filter(m=>m<D.endMin).map(m=>opt(m,d.startMin,hm(m))).join('')}</select></label>
      <label>끝<select onchange="dset('endMin',Number(this.value))">${TIMES.map(m=>m+SLOT).filter(m=>m>d.startMin&&m<=D.endMin).map(m=>opt(m,d.endMin,hm(m))).join('')}</select></label>
      ${d.kind==='memo'?`<label class="wide">글자<input value="${A(d.text)}" placeholder="예: ot30분, 1진 모니터링" oninput="dset('text',this.value)"></label>`:''}</div>
      ${d.kind==='memo'?`<div class="swatch-row"><span class="who small">색</span>${PALETTE.map(p=>`<button type="button" title="${A(p.label)}" class="swatch ${d.color===p.hex?'on':''}" style="background:${p.hex}" onclick="dset('color','${p.hex}',1)"></button>`).join('')}</div>`:''}
      ${band?'<p class="info">전원에게 같은 구간이 들어가 있는 띠입니다. 시간을 바꾸면 전원에게 적용되고, 해제하면 전원에게서 빠집니다.</p>':`<label class="check"><input type="checkbox" ${d.all?'checked':''} onchange="dset('all',this.checked)"> 그날 치료사 전원에게 적용 (점심시간 등)</label>`}
      ${msgHtml()}
      <div class="editor-actions"><button type="button" ${BUSY?'disabled':''} onclick="edSaveBlock()">${BUSY?'저장 중...':'저장'}</button>
        <button type="button" class="ghost" ${BUSY?'disabled':''} onclick="edClearBlock()">${band?'전원 해제 (근무 가능)':'이 구간 차단 해제 (근무 가능)'}</button></div>`;}
  else if(e.kind==='cancel'){const d=e.draft;const c=e.cancel;
    h=head(`취소/변경 · ${esc(d.therapistName)} · ${hm(d.startMin)}`)+`<div class="form-grid" onkeydown="if(event.key==='Enter'&&(event.ctrlKey||event.metaKey))edSaveCancel()">
      <label>치료사<select onchange="dset('therapistName',this.value,1)">${D.cancelTh.map(t=>opt(t.name,d.therapistName,t.name)).join('')}</select></label>
      <label>시간<select onchange="dset('startMin',Number(this.value),1)">${TIMES.filter(m=>m<D.endMin).map(m=>opt(m,d.startMin,hm(m))).join('')}</select></label>
      <label>종류<select onchange="dset('kind',this.value)">${opt('cancel',d.kind,'취소 (취소선)')}${opt('change',d.kind,'변경')}</select></label>
      <label class="wide">내용<input autofocus value="${A(d.text)}" placeholder="예: 31223(1) 정주현46" oninput="dset('text',this.value)"></label></div>
      <div class="swatch-row"><span class="who small">색</span>${PALETTE.map(p=>`<button type="button" title="${A(p.label)}" class="swatch ${(d.color||'#ffffff')===p.hex?'on':''}" style="background:${p.hex}" onclick="dset('color','${p.hex==='#ffffff'?'':p.hex}',1)"></button>`).join('')}</div>
      ${msgHtml()}
      <div class="editor-actions"><button type="button" ${BUSY?'disabled':''} onclick="edSaveCancel()">${BUSY?'저장 중...':'저장'}</button>
        ${c?`<button type="button" class="ghost" onclick="openEd({kind:'restore',cancel:EDIT.cancel})">스케줄로 되돌리기</button><button type="button" class="ghost danger" ${BUSY?'disabled':''} onclick="edDelCancel()">삭제</button>`:''}</div>`;}
  else if(e.kind==='therapists'){const d=e.draft;const pool=activeTh();const nm=id=>(thById(id)||{}).name||id;
    h=head(`${esc(R.q.date)} 치료사 명단`)+`<ol class="th-list">${d.ids.map((id,i)=>{const t=thById(id)||{};return `<li><span>${esc(nm(id))}</span>
        <label class="check small"><input type="checkbox" ${t.single?'checked':''} onchange="thFlag(${id},'single',this.checked)"> 한 칸</label>
        <label class="check small" title="내원률 통계·그래프에서 뺌 (스케줄에는 표시)"><input type="checkbox" ${t.inStats===false?'checked':''} onchange="thFlag(${id},'inStats',!this.checked)"> 통계 제외</label>
        <button type="button" class="ghost" onclick="thMove(${i},-1)">↑</button><button type="button" class="ghost" onclick="thMove(${i},1)">↓</button>
        <button type="button" class="ghost danger" onclick="thDrop(${id})">이 날만 빼기</button><button type="button" class="ghost danger" onclick="thRemove(${id})">전체 삭제</button></li>`;}).join('')}</ol>
      <div class="row wrap">${pool.filter(p=>!d.ids.includes(p.id)).map(p=>`<button type="button" class="ghost" onclick="thAddId(${p.id})">+ ${esc(p.name)}</button>`).join('')}</div>
      <div class="row"><input id="thNew" value="${A(d.name)}" placeholder="새 치료사 이름" oninput="dset('name',this.value)" onkeydown="if(event.key==='Enter')thNew()"><button type="button" class="ghost" ${BUSY?'disabled':''} onclick="thNew()">추가</button></div>
      ${msgHtml()}
      <div class="editor-actions"><button type="button" ${BUSY?'disabled':''} onclick="run(R.q.date,opDayTherapists(EDIT.draft.ids))">${BUSY?'저장 중...':'저장'}</button></div>`;}
  box.innerHTML=`<div class="editor">${h}</div>`;}
/* [환자 정보] — 동선관리의 환자 정보 창(4층 화면 위로 뜸). 이 스케줄을 따로 연 창이면 동선관리에서 열어 달라고 안내 (2026-10-07 요청) */
window.openPatientInfo=()=>{const d=EDIT&&EDIT.draft;if(!d)return;const P=window.parent;
  if(P&&P!==window&&typeof P.mxOpenPatient==='function'){try{P.mxOpenPatient('',String(d.mrn||''),String(d.patientName||''));return;}catch(e){console.warn(e);}}
  toast('환자 정보는 동선관리 안에서 연 스케줄([4층 비급여 치료])에서 볼 수 있습니다',3500);};
window.edSaveBooking=async()=>{const e=EDIT;const d=Object.assign({},e.draft);if(e.kind==='booking')d.id=e.booking.id;if(e.kind==='restore')d.fromCancelId=e.cancel.id;
  const ok=await run(R.q.date,opBookingSave(d));
  if(ok&&e.kind==='copyin'&&SEARCH.rows&&SEARCH.rows.includes(e.source)){SEARCH={q:'',rows:null,busy:false};safeRender();}};   // 검색 결과에서 가져와 저장했으면 검색 결과를 닫는다 (2026-10-11 요청)
window.edVisit=()=>run(R.q.date,opBookingVisit(EDIT.booking.id));
window.edDelete=()=>{if(confirm('이 예약을 삭제할까요?'))run(R.q.date,opBookingDelete(EDIT.booking.id));};
window.edCancelMove=async kind=>{const id=EDIT.booking.id;
  if(kind==='cancel'){if(confirm('이 예약을 취소/변경 칸으로 옮기고 표에서 지울까요?'))run(R.q.date,opBookingCancel(id,'cancel'));return;}
  if(await run(R.q.date,opBookingCancel(id,'change'),false)){MSG='변경 기록을 남겼습니다. 이제 새 시간(또는 치료사)을 고르고 저장하세요.';renderEditor();}};
/* 다른 날로 복사·옮기기 (2026-10-07: 시간·치료사도 고를 수 있게 — 전에는 같은 시간으로만 복사됐다) */
window.edCopy=async move=>{const to=(document.getElementById('cpDate')||{}).value;const b=EDIT.booking;if(!to){MSG='날짜를 고르세요.';renderEditor();return;}
  const st=Number((document.getElementById('cpTime')||{}).value||b.startMin),tid=Number((document.getElementById('cpTh')||{}).value||b.therapistId);
  if(!isValidDate(to)){MSG='잘못된 날짜입니다.';renderEditor();return;}
  if(st+b.durationMin>dayEndMin(to)){MSG=`그 날은 ${hm(dayEndMin(to))} 마감이라 ${hm(st)}부터 ${b.durationMin}분은 넣을 수 없습니다. 시간을 당겨 주세요.`;renderEditor();return;}
  if(move&&to===R.q.date){MSG='같은 날 안에서 옮기려면 위의 치료사·시작 시간을 바꾸고 [저장]하세요.';renderEditor();return;}
  const tn0=(thById(tid)||{}).name||'';
  const r=await run(to,ctx=>{ensureTh(ctx);if(ctx.d.th.length&&!ctx.d.th.includes(tid))return {ok:false,message:tn0+' 는 '+to+' 치료사 명단에 없습니다 — 그 날 명단에 먼저 넣거나 다른 치료사를 고르세요.'};return opBookingSave({therapistId:tid,startMin:st,durationMin:b.durationMin,mrn:b.mrn,room:b.room,patientName:b.patientName,visitNo:b.visitNo==null?null:(move?b.visitNo:b.visitNo+1),
    code:b.code,codeColor:b.codeColor,color:b.color==='#ffe599'?'':b.color,visited:false,note:b.note})(ctx);},false);
  if(!r)return;
  const tn=(thById(tid)||{}).name||'';
  if(move){const d2=await commitDay(R.q.date,opBookingDelete(b.id));EDIT=null;MSG='';renderEditor();safeRender();
    toast(d2.ok?`${to} ${hm(st)} ${tn} 로 옮겼습니다`:`${to} 로 넣었지만 원래 예약을 지우지 못했습니다 — 직접 지워 주세요`,4000);return;}
  MSG=`${to} ${hm(st)} ${tn} 로 복사했습니다 (메모 포함).`;renderEditor();};
window.edSaveBlock=async()=>{const e=EDIT,d=Object.assign({},e.draft);
  if(e.kind==='band'){const old=e.band;const tids=(D_().allTherapists||D_().therapists).map(t=>t.id);
    const r=await commitDay(R.q.date,ctx=>{const c1=opBandClear(tids,old.startMin,old.endMin)(ctx);if(!c1.ok)return c1;return opBlockSet(Object.assign(d,{all:true}))(ctx);});
    if(!r.ok){MSG=r.message;renderEditor();return;}EDIT=null;renderEditor();safeRender();return;}
  run(R.q.date,opBlockSet(d));};
window.edClearBlock=()=>{const e=EDIT,d=e.draft;
  if(e.kind==='band'){run(R.q.date,opBandClear((D_().allTherapists||D_().therapists).map(t=>t.id),d.startMin,d.endMin));return;}
  run(R.q.date,opBlockClear(d.therapistId,d.startMin,d.endMin));};
window.edSaveCancel=()=>{const e=EDIT;run(R.q.date,opCancelSave(Object.assign({},e.draft,{id:e.cancel?e.cancel.id:undefined})));};
window.edDelCancel=()=>{if(confirm('삭제할까요?'))run(R.q.date,opCancelDelete(EDIT.cancel.id));};
window.thMove=(i,dir)=>{const ids=EDIT.draft.ids;const j=i+dir;if(j<0||j>=ids.length)return;[ids[i],ids[j]]=[ids[j],ids[i]];renderEditor();};
window.thDrop=id=>{EDIT.draft.ids=EDIT.draft.ids.filter(x=>x!==id);renderEditor();};
window.thAddId=id=>{EDIT.draft.ids.push(id);renderEditor();};
window.thFlag=async(id,k,v)=>{await runMeta(setThFlag(id,k,v),false);renderEditor();};
window.thRemove=async id=>{if(!confirm('이 치료사를 모든 날짜의 표에서 뺄까요? (기존 예약 기록은 남습니다)'))return;
  await runMeta(setThFlag(id,'active',false),false);EDIT.draft.ids=EDIT.draft.ids.filter(x=>x!==id);renderEditor();};
window.thNew=async()=>{const n=String(EDIT.draft.name||'').trim();if(!n)return;const r=await runMeta(addTherapist(n),false);
  if(r&&r.value){EDIT.draft.ids.push(r.value.id);EDIT.draft.name='';}renderEditor();};

/* ═════════ 간단 모드 (스마트폰) ═════════ */
let MOB={tid:0,ed:null,f:null};
function renderMobile(){
  const date=R.q.date;if(DAYDOC===undefined)return LOADING;
  const D=dayView(date,DAYDOC,NEARDOC);window.DV=D;
  if(date===todayYmd()){watchBoard();setTimeout(sasoSync,0);}   // SASO 환자 → Manual Tx
  if(!D.therapists.some(t=>t.id===MOB.tid))MOB.tid=Number(R.q.t)||(D.therapists[0]||{}).id||0;
  const t=D.therapists.find(x=>x.id===MOB.tid);
  const rows=[];
  if(t){const items=[...D.bookings.filter(b=>b.therapistId===t.id).map(b=>({kind:'booking',startMin:b.startMin,endMin:b.startMin+b.durationMin,b})),
      ...D.blocks.filter(k=>k.therapistId===t.id).map(k=>({kind:'block',startMin:k.startMin,endMin:k.endMin,k}))].sort((a,b)=>a.startMin-b.startMin);
    let cur=DAY_START;
    for(const it of items){while(cur+30<=it.startMin){rows.push({kind:'free',startMin:cur,endMin:cur+30});cur+=30;}
      if(cur<it.startMin){rows.push({kind:'free',startMin:cur,endMin:it.startMin});cur=it.startMin;}
      if(it.startMin>=cur){rows.push(it);cur=it.endMin;}}
    while(cur<D.endMin){const e=Math.min(cur+30,D.endMin);rows.push({kind:'free',startMin:cur,endMin:e});cur=e;}}
  D.mobRows=rows;
  const count=id=>({n:D.bookings.filter(b=>b.therapistId===id).length,v:D.bookings.filter(b=>b.therapistId===id&&b.visited).length});
  let h=`<div class="mob"><div class="mob-head"><button class="mob-nav" onclick="go('m',{date:'${shiftDate(date,-1)}',t:${MOB.tid}})">‹</button>
    <div class="mob-date"><input type="date" value="${date}" onchange="if(this.value)go('m',{date:this.value,t:${MOB.tid}})"><div class="mob-label">${esc(D.label)}${D.shortDay?' · 17:30까지':''}</div></div>
    <button class="mob-nav" onclick="go('m',{date:'${shiftDate(date,1)}',t:${MOB.tid}})">›</button></div>
    <div class="mob-chips">${D.therapists.map(x=>{const c=count(x.id);return `<button type="button" class="chip ${x.id===MOB.tid?'on':''}" style="${x.id===MOB.tid&&x.color?`background:${A(x.color)};color:#1f2328`:''}" onclick="MOB.tid=${x.id};MOB.ed=null;render()">${esc(x.name)} <span class="chip-n">${c.v}/${c.n}</span></button>`;}).join('')}</div>`;
  if(!D.therapists.length)h+=`<p class="note">이 날은 치료사 명단이 없습니다. 일별 스케줄에서 명단을 먼저 정하세요.</p>`;
  if(t)h+=`<div class="mob-list">${rows.map((r,i)=>{
      if(r.kind==='block')return `<div class="mob-row block ${r.k.kind}" style="${r.k.kind==='memo'&&r.k.color?`background:${A(r.k.color)}`:''}" onclick="mobClear(${i})"><div class="mob-time">${hm(r.startMin)}<br><span>~${hm(r.endMin)}</span></div><div class="mob-body">${esc(r.k.text||(r.k.kind==='off'?'비근무':''))}</div></div>`;
      if(r.kind==='booking'){const b=r.b;const bg=b.visited?'#ffe599':b.color||'';
        return `<div class="mob-row booking" style="${bg?`background:${A(bg)}`:''}"><div class="mob-time" onclick="mobEdit(${b.id})">${hm(b.startMin)}<br><span>${b.durationMin}분</span></div>
          <div class="mob-body" onclick="mobEdit(${b.id})"><div class="mob-name">${esc(b.mrn)}${b.room?`(${esc(b.room)})`:''} <strong>${esc(b.patientName)}</strong>${b.visitNo??''}${!b.mrn&&!b.patientName?esc(b.rawText||''):''}</div>
          <div class="mob-sub">${b.code?`<span class="code" style="${b.codeColor?`background:${A(b.codeColor)}`:''}">${esc(b.code)}</span>`:''}${b.note?`<span class="mob-note">${esc(b.note)}</span>`:''}</div></div>
          <button type="button" class="mob-visit ${b.visited?'on':''}" ${BUSY?'disabled':''} onclick="run(R.q.date,opBookingVisit(${b.id}),false)" title="방문 체크">${b.visited?'✔':'○'}</button></div>`;}
      return `<div class="mob-row free" onclick="mobNew(${r.startMin})"><div class="mob-time">${hm(r.startMin)}</div><div class="mob-body muted">+ 예약</div></div>`;}).join('')}</div>`;
  if(MOB.ed&&t){const f=MOB.f,ed=MOB.ed;
    h+=`<div class="editor" style="position:fixed;left:0;right:0;bottom:0;border-radius:16px 16px 0 0;z-index:30;max-height:85vh;overflow:auto">
      <div class="editor-head"><strong>${ed.b?'예약 수정':'새 예약'} · ${esc(t.name)} · ${hm(ed.startMin)}</strong><button type="button" class="ghost" onclick="MOB.ed=null;render()">닫기</button></div>
      <div class="mob-form"><label>차트번호<input inputmode="numeric" value="${A(f.mrn)}" oninput="this.value=this.value.replace(/\\D/g,'').slice(0,7);MOB.f.mrn=this.value"></label>
        <label>진료실<input inputmode="numeric" value="${A(f.room)}" oninput="this.value=this.value.replace(/\\D/g,'').slice(0,2);MOB.f.room=this.value"></label>
        <label>이름<input value="${A(f.patientName)}" oninput="MOB.f.patientName=this.value"></label>
        <label>방문수<input inputmode="numeric" value="${A(f.visitNo)}" oninput="this.value=this.value.replace(/\\D/g,'').slice(0,3);MOB.f.visitNo=this.value"></label>
        <label>치료코드${codeSelect(f.code,"MOB.f.code=v")}</label>
        <label>길이<select onchange="MOB.f.durationMin=Number(this.value)">${[15,30,45,60,90].filter(x=>ed.b||x<=ed.maxMin).map(x=>opt(x,f.durationMin,x+'분')).join('')}</select></label>
        <label class="wide">메모<textarea rows="2" oninput="MOB.f.note=this.value">${esc(f.note)}</textarea></label></div>
      ${MSG?`<p class="err">${esc(MSG)}</p>`:''}
      <div class="row wrap"><button type="button" ${BUSY?'disabled':''} onclick="mobSave()">${BUSY?'저장 중...':'저장'}</button>
        ${!ed.b?`<button type="button" class="ghost" onclick="mobOff()">이 30분 비근무</button>`:`<button type="button" class="ghost" onclick="mobVisit()">${ed.b.visited?'방문 해제':'✔ 방문 체크'}</button><button type="button" class="ghost danger" onclick="mobDel()">삭제</button>`}</div></div>`;}
  h+=`<p class="note">칸을 누르면 예약을 넣고, 예약을 누르면 고칩니다. 오른쪽 ○ 를 누르면 방문 체크. 일별 스케줄과 같은 데이터라 어느 쪽에서 고쳐도 바로 반영됩니다.</p></div>`;
  return h;}
function mobFreeAfter(startMin){let m=0;for(const r of D_().mobRows){if(r.kind==='free'&&r.startMin>=startMin&&r.startMin===startMin+m)m+=r.endMin-r.startMin;else if(r.startMin>startMin&&r.kind!=='free')break;}return m||30;}
window.mobNew=s=>{const mx=mobFreeAfter(s);MOB.f={mrn:'',room:'',patientName:'',visitNo:'',code:'',durationMin:Math.min(30,mx),note:''};MOB.ed={startMin:s,maxMin:mx};MSG='';render();};
window.mobEdit=id=>{const b=D_().bookings.find(x=>x.id===id);if(!b)return;MOB.f={mrn:b.mrn,room:b.room,patientName:b.patientName,visitNo:b.visitNo==null?'':String(b.visitNo),code:b.code,durationMin:b.durationMin,note:b.note||''};MOB.ed={startMin:b.startMin,maxMin:b.durationMin,b};MSG='';render();};
window.mobSave=async()=>{const ed=MOB.ed,f=MOB.f;const b=ed.b;
  const r=await run(R.q.date,opBookingSave({id:b?b.id:undefined,therapistId:MOB.tid,startMin:ed.startMin,durationMin:f.durationMin,mrn:f.mrn,room:f.room,patientName:f.patientName,
    visitNo:f.visitNo===''?null:Number(f.visitNo),code:f.code,codeColor:b?b.codeColor:'',color:b?b.color:'',visited:b?b.visited:false,note:f.note}),false);
  if(r){MOB.ed=null;render();}else render();};
window.mobOff=async()=>{const s=MOB.ed.startMin;if(await run(R.q.date,opBlockSet({therapistId:MOB.tid,startMin:s,endMin:Math.min(s+30,D_().endMin),kind:'off',text:'',color:''}),false)){MOB.ed=null;render();}else render();};
window.mobVisit=async()=>{if(await run(R.q.date,opBookingVisit(MOB.ed.b.id),false)){MOB.ed=null;render();}};
window.mobDel=async()=>{if(!confirm('삭제할까요?'))return;if(await run(R.q.date,opBookingDelete(MOB.ed.b.id),false)){MOB.ed=null;render();}};
window.mobClear=i=>{const r=D_().mobRows[i];if(!r)return;if(confirm(`${hm(r.startMin)}~${hm(r.endMin)} ${r.k.kind==='off'?'비근무':'차단'}을 해제할까요?`))run(R.q.date,opBlockClear(MOB.tid,r.startMin,r.endMin),false);};

/* ═════════ 통계용 데이터 (월별 문서 묶음) ═════════ */
const MONTHS={};   // ym → {at, docs}
function listMonths(){return [...new Set(META.dataDays.map(d=>d.slice(0,7)))].sort().map(v=>({year:Number(v.slice(0,4)),month:Number(v.slice(5)),ym:v}));}
function monthDocs(ym){const c=MONTHS[ym];if(c&&c.docs&&Date.now()-c.at<60000)return c.docs;
  if(!c||!c.loading){MONTHS[ym]=Object.assign(c||{},{loading:true});
    C.day.where('ym','==',ym).get().then(s=>{MONTHS[ym]={at:Date.now(),docs:s.docs.map(d=>normDay(d.data(),d.id)).sort((a,b)=>a.date<b.date?-1:1)};safeRender();})
      .catch(e=>{console.warn(e);MONTHS[ym]={at:Date.now(),docs:[]};safeRender();});}
  return c&&c.docs?c.docs:null;}
function pickYm(q){const months=listMonths();const now=new Date();let year=now.getFullYear(),month=now.getMonth()+1;
  const m=/^(\d{4})-(\d{1,2})$/.exec(q.ym||'');if(m){year=Number(m[1]);month=Number(m[2]);}
  else if(months.length&&!months.some(x=>x.year===year&&x.month===month))({year,month}=months[months.length-1]);
  return {year,month,ym:`${year}-${pad2(month)}`,months};}
function monthMatrix(docs){
  const ths=[];docs.forEach(d=>thOfDay(d.th,d.bookings).forEach(t=>{if(t.inStats&&!ths.some(x=>x.id===t.id))ths.push({id:t.id,name:t.name});}));
  const days=docs.filter(d=>d.th.length).map(d=>{const present=thOfDay(d.th,d.bookings).map(t=>t.id);const r=dayRatios(present,d.bookings,d.blocks,dayEndMin(d.date));
    const cells=ths.map(t=>present.includes(t.id)?r.get(t.id)||null:null);const pos=cells.filter(c=>c&&c.ratio>0).map(c=>c.ratio);
    return {date:d.date,day:Number(d.date.slice(8)),cells,average:pos.length?pos.reduce((a,b)=>a+b,0)/pos.length:null};});
  const monthly=ths.map((_,i)=>{const v=days.map(d=>d.cells[i]).filter(c=>c&&c.ratio>0).map(c=>c.ratio);return v.length?v.reduce((a,b)=>a+b,0)/v.length:null;});
  return {therapists:ths,days,monthly};}
function monthPills(page,cur,extra){return listMonths().map(x=>`<a href="${href(page,Object.assign({ym:`${x.year}-${x.month}`},extra||{}))}" class="pill ${x.ym===cur?'on':''}">${x.year}년 ${x.month}월</a>`).join(' ');}

/* ═════════ 내원률 통계 ═════════ */
function renderStatsPage(){const {year,month,ym}=pickYm(R.q);const docs=monthDocs(ym);
  let h=`<div class="daybar"><h1>내원률 통계</h1><div class="days" style="margin:0">${monthPills('stats',ym)}</div></div>`;
  if(!docs)return h+LOADING;const mx=monthMatrix(docs);
  if(!mx.days.length)return h+`<p class="note">이 달에는 데이터가 없습니다.</p>`;
  h+=`<div class="scroll"><table class="plain"><thead><tr><th>날짜</th>${mx.therapists.map(t=>`<th>${esc(t.name)}</th>`).join('')}<th>평균</th></tr></thead><tbody>
    ${mx.days.map(d=>`<tr><td><a href="${href('schedule',{date:d.date})}">${d.day}일</a></td>${d.cells.map(c=>`<td class="${c==null?'muted':''}" title="${c?`방문 ${c.visit} / 근무 칸 ${c.usable}`:'근무 없음'}">${pct(c&&c.ratio,1)}</td>`).join('')}<td><strong>${pct(d.average,1)}</strong></td></tr>`).join('')}
    </tbody><tfoot><tr><td>월 평균</td>${mx.monthly.map(v=>`<td><strong>${pct(v,1)}</strong></td>`).join('')}<td></td></tr></tfoot></table></div>
    <p class="note">어떤 치료를 몇 번 했는지는 <a href="${href('treat',{ym:`${year}-${month}`})}">치료 통계</a> 에서 월 합계와 일자별로 볼 수 있습니다.</p>
    <p class="note">내원률 = 내원 예약 수 ÷ 근무 칸 수. 비근무(회색)는 제외, 예약·메모는 칸 1개, 빈 시간은 30분마다 칸 1개로 셉니다 (시트 수식과 같은 규칙). 평균은 0%보다 큰 값만으로 계산합니다.</p>`;
  return h;}

/* ═════════ 치료 통계 (시트 '통계' 탭 형식) ═════════ */
function emptyTables(n){return CODE_GROUPS.map(g=>({group:g.name,codes:g.codes.slice(),counts:g.codes.map(()=>Array(n).fill(0)),rowTotals:Array(g.codes.length).fill(0),colTotals:Array(n).fill(0),total:0}));}
function addCount(tables,code,ti){for(const t of tables){const ri=t.codes.indexOf(code);if(ri<0)continue;t.counts[ri][ti]++;t.rowTotals[ri]++;t.colTotals[ti]++;t.total++;return true;}return false;}
function breakdown(docs){
  const ths=[];docs.forEach(d=>thOfDay(d.th,d.bookings).forEach(t=>{if(!t.single&&!ths.some(x=>x.id===t.id))ths.push({id:t.id,name:t.name});}));
  docs.forEach(d=>d.bookings.forEach(b=>{const t=thById(b.therapistId);if(t&&!t.single&&!ths.some(x=>x.id===b.therapistId))ths.push({id:b.therapistId,name:t.name});}));
  const ti=new Map(ths.map((t,i)=>[t.id,i]));const monthT=emptyTables(ths.length);const dayMap=new Map();const other=new Map();
  docs.forEach(d=>d.bookings.forEach(b=>{const t=thById(b.therapistId);if(!t||t.single||!b.visited)return;const code=normalizeCode(b.code);
    if(!ALL_CODES.has(code)){const k=code||'(없음)';other.set(k,(other.get(k)||0)+1);return;}
    const i=ti.get(b.therapistId);addCount(monthT,code,i);if(!dayMap.has(d.date))dayMap.set(d.date,emptyTables(ths.length));addCount(dayMap.get(d.date),code,i);}));
  const dates=[...new Set(docs.filter(d=>d.th.length).map(d=>d.date).concat([...dayMap.keys()]))].sort();
  const days=dates.map(date=>{const tables=dayMap.get(date)||emptyTables(ths.length);return {date,day:Number(date.slice(8)),tables,total:tables.reduce((a,t)=>a+t.total,0)};});
  return {therapists:ths,month_:monthT,days,other:[...other.entries()].map(([code,total])=>({code,total})).sort((a,b)=>b.total-a.total)};}
function codeTable(t,ths,label){return `<table class="codes"><thead><tr><th class="grp" rowspan="2">${esc(label)}</th><th>${esc(t.group)}</th>${ths.map(x=>`<th>${esc(x.name)}</th>`).join('')}<th>총합</th></tr>
  <tr class="sum"><th>총합</th>${t.colTotals.map(n=>`<th>${n}</th>`).join('')}<th>${t.total}</th></tr></thead><tbody>
  ${t.codes.map((code,ri)=>`<tr class="${t.rowTotals[ri]?'nz':''}">${ri===0?`<td class="grp" rowspan="${t.codes.length}"></td>`:''}<td class="code">${esc(code)}</td>${t.counts[ri].map(n=>`<td class="${n?'hit':''}">${n}</td>`).join('')}<td class="${t.rowTotals[ri]?'hit':''}">${t.rowTotals[ri]}</td></tr>`).join('')}</tbody></table>`;}
let TREAT_OPEN=false;
function renderTreatPage(){const {year,month,ym}=pickYm(R.q);const docs=monthDocs(ym);
  let h=`<div class="daybar"><h1>치료 통계 · ${year}년 ${month}월</h1><div class="days" style="margin:0">${monthPills('treat',ym)}</div></div>`;
  if(!docs)return h+LOADING;const b=breakdown(docs);
  h+=`<div class="days"><span class="who small">표시 칸에 점(.)이 찍힌 내원 예약만 셉니다.</span><button class="pill" onclick="TREAT_OPEN=!TREAT_OPEN;render()">${TREAT_OPEN?'일자별 모두 접기':'일자별 모두 펼치기'}</button></div>
    <h2 class="h2">월 합계</h2><div class="code-tables">${b.month_.map(t=>codeTable(t,b.therapists,'합계')).join('')}</div>
    ${b.other.length?`<p class="note">목록에 없는 코드: ${b.other.map(o=>`${esc(o.code)} ${o.total}건`).join(', ')}. 예약 입력창에서 코드를 목록대로 고쳐 주세요.</p>`:''}
    <h2 class="h2">일자별</h2>
    ${b.days.map(d=>`<details class="day-details" ${TREAT_OPEN?'open':''}><summary><strong>${d.day}일</strong> <span class="who small">${d.date}</span> · 총 ${d.total}건 <a href="${href('schedule',{date:d.date})}" class="pill small">스케줄 보기</a></summary>
      <div class="code-tables">${d.tables.map(t=>codeTable(t,b.therapists,String(d.day))).join('')}</div></details>`).join('')}
    <p class="note">시트의 통계 탭과 같은 코드 목록입니다. 0이 아닌 칸은 초록으로 표시됩니다. 예약만 잡힌 것은 세지 않고, 방문 체크(점)가 된 것만 올라갑니다.</p>`;
  return h;}

/* ═════════ 그래프 ═════════ */
function svgMonthBars(name,labels,values){const W=220,H=120,padL=30,padB=22,padT=18,padR=6;const iw=W-padL-padR,ih=H-padT-padB;const n=values.length;
  const bw=Math.min(28,(iw/Math.max(n,1))*.6);const x=i=>padL+(iw/n)*(i+.5);const y=v=>padT+ih-v*ih;
  return `<figure class="viz small"><figcaption>${esc(name)}</figcaption><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${A(name)} 월별 평균 내원률">
    ${[0,.5,1].map(g=>`<line x1="${padL}" x2="${W-padR}" y1="${y(g)}" y2="${y(g)}" class="grid"/><text x="${padL-4}" y="${y(g)+3}" class="tick" text-anchor="end">${g*100}%</text>`).join('')}
    ${values.map((v,i)=>`${v!=null?`<rect x="${x(i)-bw/2}" y="${y(v)}" width="${bw}" height="${Math.max(0,y(0)-y(v))}" rx="3" class="bar"><title>${esc(labels[i])} · ${pct(v,1)}</title></rect><text x="${x(i)}" y="${y(v)-4}" class="val" text-anchor="middle">${pct(v,0)}</text>`:''}<text x="${x(i)}" y="${H-6}" class="tick" text-anchor="middle">${esc(labels[i])}</text>`).join('')}
    <line x1="${padL}" x2="${W-padR}" y1="${y(0)}" y2="${y(0)}" class="axis"/></svg></figure>`;}
function svgCountBars(name,labels,values,max){const W=220,H=120,padL=32,padB=22,padT=18,padR=6;const iw=W-padL-padR,ih=H-padT-padB;const n=values.length;
  const top=Math.max(10,Math.ceil(max/20)*20);const bw=Math.min(28,(iw/Math.max(n,1))*.6);const x=i=>padL+(iw/n)*(i+.5);const y=v=>padT+ih-(v/top)*ih;
  return `<figure class="viz small"><figcaption>${esc(name)}</figcaption><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${A(name)} 월별 치료 건수">
    ${[0,top/2,top].map(g=>`<line x1="${padL}" x2="${W-padR}" y1="${y(g)}" y2="${y(g)}" class="grid"/><text x="${padL-4}" y="${y(g)+3}" class="tick" text-anchor="end">${g}</text>`).join('')}
    ${values.map((vs,i)=>{const man=vs[0]||0,sh=vs[1]||0,tot=man+sh;return `${man>0?`<rect x="${x(i)-bw/2}" y="${y(man)}" width="${bw}" height="${Math.max(0,y(0)-y(man))}" rx="2" class="bar s1"><title>${esc(labels[i])} 도수 ${man}건</title></rect>`:''}
      ${sh>0?`<rect x="${x(i)-bw/2}" y="${y(tot)}" width="${bw}" height="${Math.max(0,y(man)-y(tot)-1)}" rx="2" class="bar s3"><title>${esc(labels[i])} 충격파 ${sh}건</title></rect>`:''}
      <text x="${x(i)}" y="${y(tot)-4}" class="val" text-anchor="middle">${tot}</text><text x="${x(i)}" y="${H-6}" class="tick" text-anchor="middle">${esc(labels[i])}</text>`;}).join('')}
    <line x1="${padL}" x2="${W-padR}" y1="${y(0)}" y2="${y(0)}" class="axis"/></svg></figure>`;}
function svgDailyLine(name,days,values){const W=760,H=220,padL=40,padB=26,padT=16,padR=12;const iw=W-padL-padR,ih=H-padT-padB;const n=days.length;
  const x=i=>padL+(n<=1?iw/2:(iw*i)/(n-1));const y=v=>padT+ih-v*ih;const pts=values.map((v,i)=>v==null?null:[x(i),y(v)]);
  const segs=[];let cur=[];pts.forEach(p=>{if(p)cur.push(`${p[0].toFixed(1)},${p[1].toFixed(1)}`);else{if(cur.length)segs.push(cur.join(' '));cur=[];}});if(cur.length)segs.push(cur.join(' '));
  return `<figure class="viz"><figcaption>${esc(name)} · 일별 내원률</figcaption><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${A(name)} 일별 내원률">
    ${[0,.25,.5,.75,1].map(g=>`<line x1="${padL}" x2="${W-padR}" y1="${y(g)}" y2="${y(g)}" class="grid"/><text x="${padL-6}" y="${y(g)+3}" class="tick" text-anchor="end">${g*100}%</text>`).join('')}
    ${segs.map(s=>`<polyline points="${s}" class="line"/>`).join('')}
    ${pts.map((p,i)=>p?`<circle cx="${p[0]}" cy="${p[1]}" r="4" class="dot"><title>${days[i]}일 · ${pct(values[i],1)}</title></circle>`:'').join('')}
    ${days.map((d,i)=>(n<=16||i%2===0)?`<text x="${x(i)}" y="${H-8}" class="tick" text-anchor="middle">${d}</text>`:'').join('')}
    <line x1="${padL}" x2="${W-padR}" y1="${y(0)}" y2="${y(0)}" class="axis"/></svg></figure>`;}
function renderChartsPage(){const months=listMonths();let h=`<h1>내원률 그래프</h1>`;
  const all=months.map(m=>monthDocs(m.ym));if(all.some(x=>!x))return h+LOADING;
  const labels=months.map(m=>`${String(m.year).slice(2)}.${pad2(m.month)}`);
  const mats=all.map(monthMatrix);
  const series=[];mats.forEach((mx,mi)=>mx.therapists.forEach((t,ti)=>{let r=series.find(x=>x.id===t.id);if(!r){r={id:t.id,name:t.name,values:Array(months.length).fill(null)};series.push(r);}r.values[mi]=mx.monthly[ti];}));
  const bds=all.map(breakdown);const cnt=[];
  bds.forEach((b,mi)=>b.therapists.forEach((t,ti)=>{let r=cnt.find(x=>x.id===t.id);
    if(!r){r={id:t.id,name:t.name,values:months.map(()=>[0,0])};cnt.push(r);}b.month_.forEach((tb,gi)=>{r.values[mi][gi]=tb.colTotals[ti]||0;});}));
  const maxC=Math.max(1,...cnt.flatMap(c=>c.values.map(v=>v[0]+v[1])));
  const {year,month,ym}=pickYm(R.q);const mi=months.findIndex(m=>m.ym===ym);const mx=mi>=0?mats[mi]:null;
  let tid=Number(R.q.t)||(mx&&mx.therapists[0]?mx.therapists[0].id:0);if(mx&&!mx.therapists.some(x=>x.id===tid))tid=mx.therapists[0]?mx.therapists[0].id:0;
  const ti=mx?mx.therapists.findIndex(x=>x.id===tid):-1;
  h+=`<h2 class="h2">치료사별 월 평균 내원률</h2>${series.length?`<div class="viz-grid">${series.map(s=>svgMonthBars(s.name,labels,s.values)).join('')}</div>`:'<p class="note">데이터가 없습니다.</p>'}
    <details class="day-details"><summary>표로 보기</summary><table class="mini plain"><thead><tr><th>치료사</th>${labels.map(l=>`<th>${l}</th>`).join('')}</tr></thead><tbody>${series.map(s=>`<tr><td>${esc(s.name)}</td>${s.values.map(v=>`<td>${pct(v,1)}</td>`).join('')}</tr>`).join('')}</tbody></table></details>
    <h2 class="h2">일별 내원률</h2><div class="days">${months.map(m=>`<a href="${href('charts',{ym:`${m.year}-${m.month}`,t:tid})}" class="pill ${m.ym===ym?'on':''}">${m.year}년 ${m.month}월</a>`).join(' ')}</div>
    ${mx?`<div class="days">${mx.therapists.map(x=>`<a href="${href('charts',{ym:`${year}-${month}`,t:x.id})}" class="pill small ${x.id===tid?'on':''}">${esc(x.name)}</a>`).join(' ')}</div>`:''}
    ${mx&&ti>=0?svgDailyLine(mx.therapists[ti].name,mx.days.map(d=>d.day),mx.days.map(d=>d.cells[ti]?d.cells[ti].ratio:null)):''}
    <p class="note">내원률 = 내원 예약 수 ÷ 근무 칸 수. 월 평균은 0%보다 큰 날만으로 계산합니다. 점이나 막대에 마우스를 올리면 값이 보입니다.</p>
    <h2 class="h2">치료사별 월 치료 건수</h2><div class="legend-inline"><span class="sw s1"></span> 도수 <span class="sw s3"></span> 충격파 <span class="who small">(치료 통계 코드 표의 총합, 내원 점이 찍힌 예약)</span></div>
    ${cnt.length?`<div class="viz-grid">${cnt.map(c=>svgCountBars(c.name,labels,c.values,maxC)).join('')}</div>`:'<p class="note">데이터가 없습니다.</p>'}
    <details class="day-details"><summary>표로 보기</summary><table class="mini plain"><thead><tr><th>치료사</th>${labels.map(l=>`<th colspan="2">${l}</th>`).join('')}<th>합계</th></tr>
      <tr><th></th>${labels.map(()=>'<th>도수</th><th>충격파</th>').join('')}<th></th></tr></thead>
      <tbody>${cnt.map(c=>`<tr><td>${esc(c.name)}</td>${c.values.map(v=>`<td>${v[0]}</td><td>${v[1]}</td>`).join('')}<td><strong>${c.values.reduce((a,v)=>a+v[0]+v[1],0)}</strong></td></tr>`).join('')}</tbody></table></details>
    <p class="note">세로축 최대값을 모든 그래프에 같게 맞춰 치료사끼리 비교할 수 있습니다. 막대에 마우스를 올리면 도수·충격파 건수가 따로 보입니다.</p>`;
  return h;}

/* ═════════ 변경 기록 ═════════ */
let AUDIT={at:0,rows:null,loading:false};
const ACTION_L={create:'추가',update:'수정',delete:'삭제',import:'가져오기',mirror:'시트 반영','mirror-failed':'시트 반영 실패',view:'조회'};
const ENTITY_L={bookings:'예약',work_blocks:'비근무/차단',cancels:'취소/변경',manual_tx:'Manual Tx',day_notes:'참고사항',month_consults:'상담수',day_therapists:'치료사 명단',therapists:'치료사',sheet:'시트',month:'월',day:'날짜'};
function brief(v){if(v==null)return '';if(typeof v!=='object')return String(v);const keys=['patientName','mrn','code','visited','startMin','durationMin','text','count','detail','bookings','days','name','note','color','mark'];
  const parts=keys.filter(k=>k in v).map(k=>`${k}=${String(v[k]).slice(0,40)}`);return parts.join(' ')||JSON.stringify(v).slice(0,80);}
function renderAuditPage(){
  if((!AUDIT.rows||Date.now()-AUDIT.at>30000)&&!AUDIT.loading){AUDIT.loading=true;
    C.audit.orderBy('at','desc').limit(300).get().then(s=>{AUDIT={at:Date.now(),rows:s.docs.map(d=>d.data()),loading:false};safeRender();}).catch(e=>{AUDIT.loading=false;AUDIT.rows=[];console.warn(e);safeRender();});}
  let h=`<h1>변경 기록</h1><p class="sub">최근 300건. 누가 언제 무엇을 바꿨는지 남습니다.</p>`;
  if(!AUDIT.rows)return h+LOADING;
  return h+`<div class="scroll"><table><thead><tr><th>시각</th><th>사용자</th><th>동작</th><th>대상</th><th>날짜</th><th>이전</th><th>이후</th></tr></thead><tbody>
    ${AUDIT.rows.map(r=>`<tr><td class="nowrap">${esc(new Date(r.at).toLocaleString('ko-KR',{hour12:false}))}</td><td>${esc(r.user||r.email||'')}</td><td>${esc(ACTION_L[r.action]||r.action)}</td>
      <td>${esc(ENTITY_L[r.entity]||r.entity)} ${r.entityId?`<span class="who small">#${esc(r.entityId)}</span>`:''}</td>
      <td class="nowrap">${r.date?`<a href="${href('schedule',{date:r.date})}">${esc(r.date)}</a>`:''}</td><td class="small">${esc(brief(r.before))}</td><td class="small">${esc(brief(r.after))}</td></tr>`).join('')}</tbody></table></div>`;}

/* ═════════ 구글 시트(예약리스트) 링크로 가져오기 (2026-10-07 요청) ═════════
   visit-stats 의 lib/sheet-import.ts 와 같은 규칙. 시트를 xlsx 로 내려받아(링크 공유된 시트, 구글이 브라우저에서 받게 허용) 날짜 탭(1일~31일)마다 읽는다.
   4행 치료사(B·E·H… 3칸 = 환자·치료코드·표시), 6~53행 = 9:00부터 15분, 병합 행 수 = 치료 시간, 회색 #999999 = 비근무, 노랑 #ffe599 또는 표시 칸 글자 = 내원,
   AU~BC 취소/변경(취소선 = 취소), BK~BN Manual Tx, 55행 당월 누적 상담수. 연·월은 '1일' 탭 BD1(연)·BG1(월) */
const SH={rowFrom:6,rowTo:53,headerRow:4,bFrom:1,bTo:45,W:3,cancelFrom:46,cancelTo:54,manualFrom:62,consultRow:55,gray:'#999999'};
function sheetIdOf(s){const m=/\/spreadsheets\/d\/([A-Za-z0-9_-]{20,})/.exec(String(s||''))||/^([A-Za-z0-9_-]{30,})$/.exec(String(s||'').trim());return m?m[1]:'';}
function loadXlsxLib(){if(window.XLSX)return Promise.resolve();return new Promise((ok,no)=>{const s=document.createElement('script');s.src='https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js';s.onload=ok;s.onerror=()=>no(new Error('엑셀 읽기 도구를 불러오지 못했습니다'));document.head.appendChild(s);});}
function zipText(f){if(!f)return '';if(typeof f.asText==='function')return f.asText();const c=f.content||f._data;if(!c)return '';if(typeof c==='string')return c;return new TextDecoder().decode(c instanceof Uint8Array?c:new Uint8Array(c));}
function parsePatientSheet(text){const m=/^\s*(\d{1,7})\s*\(\s*(\d{1,2})\s*\)\s*([^\d\n]+?)\s*(\d{1,3})?\s*$/.exec(String(text).replace(/\r?\n/g,' '));
  return m?{mrn:m[1],room:m[2],name:m[3].replace(/\s+/g,''),visit:m[4]?parseInt(m[4],10):null}:null;}
/* 2026-10-08: 치료사 수가 달마다·날마다 달라 열 위치가 밀린다(5월 시트는 취소/변경이 AR, 8월 1일은 AX) → 탭마다 머리글로 위치를 찾는다.
   '취소/변경'(1~4행) = 취소 칸 시작, 그 앞까지 치료사 칸 / 2행 '일'(달력) 앞까지 취소 칸 / 2행 'Manual Tx' = Manual Tx 칸.
   연·월은 '취소/변경' 위 1행 칸의 날짜(엑셀 날짜 숫자), 없으면 달력 위 연·월 칸. 머리글을 못 찾으면 위 고정 위치(SH) */
function sheetLayout(ws){
  const cell=(r,c)=>ws[XLSX.utils.encode_cell({r:r-1,c})];
  const textOf=(r,c)=>{const x=cell(r,c);if(!x)return '';return String(x.w!=null?x.w:(x.v!=null?x.v:'')).trim();};
  const L={bTo:SH.bTo,cancelFrom:SH.cancelFrom,cancelTo:SH.cancelTo,manualFrom:SH.manualFrom,year:0,month:0};
  let cc=-1;for(let r=1;r<=4&&cc<0;r++)for(let c=4;c<160;c++){if(textOf(r,c).replace(/\s+/g,'')==='취소/변경'){cc=c;break;}}
  if(cc<0)return L;
  L.cancelFrom=cc;L.bTo=cc-1;
  let cal=-1;for(let c=cc+1;c<cc+40;c++)if(textOf(2,c)==='일'){cal=c;break;}
  L.cancelTo=cal>0?cal-1:cc+8;
  for(let c=cc+1;c<cc+60;c++)if(/^Manual\s*Tx/i.test(textOf(2,c))){L.manualFrom=c;break;}
  const v=(cell(1,cc)||{}).v;
  if(typeof v==='number'&&v>40000){const d=XLSX.SSF.parse_date_code(v);if(d){L.year=d.y;L.month=d.m;}}
  if(!L.year&&cal>0){const y=parseInt(textOf(1,cal),10),m=parseInt(textOf(1,cal+3),10);if(y>2000&&m>=1&&m<=12){L.year=y;L.month=m;}}
  return L;}
/* 탭 하나 → {therapists, bookings, blocks, cancels, manual, consults} */
function parseSheetDay(ws,strikeAt){
  const cell=(r,c)=>ws[XLSX.utils.encode_cell({r:r-1,c})];
  const textOf=(r,c)=>{const x=cell(r,c);if(!x)return '';return String(x.w!=null?x.w:(x.v!=null?x.v:'')).trim();};
  const L=sheetLayout(ws),MF=L.manualFrom;
  const consultOk=!textOf(SH.consultRow,0)||/상담/.test(textOf(SH.consultRow,0));   // 55행이 '당월 누적 상담수' 줄일 때만 (5월 시트는 안내 문구)
  const bgOf=(r,c)=>{const x=cell(r,c);const s=x&&x.s;if(!s||s.patternType!=='solid'||!s.fgColor||!s.fgColor.rgb)return '';const h='#'+String(s.fgColor.rgb).slice(-6).toLowerCase();return h==='#ffffff'?'':h;};
  const noteOf=(r,c)=>{const x=cell(r,c);return x&&Array.isArray(x.c)?x.c.map(n=>n.t||'').join('\n').trim():'';};
  const mergeAt=new Map();(ws['!merges']||[]).forEach(m=>{const mm={r1:m.s.r+1,r2:m.e.r+1,c1:m.s.c,c2:m.e.c};for(let r=mm.r1;r<=mm.r2;r++)for(let c=mm.c1;c<=mm.c2;c++)mergeAt.set(r+','+c,mm);});
  const isStart=(r,c)=>{const m=mergeAt.get(r+','+c);return !m||(m.r1===r&&m.c1===c);};
  const spanRows=(r,c)=>{const m=mergeAt.get(r+','+c);return m?m.r2-m.r1+1:1;};
  const wideMerge=(r,c)=>{const m=mergeAt.get(r+','+c);return !!m&&m.c1<=SH.bFrom&&m.c2>=L.bTo;};
  const minOfRow=r=>DAY_START+(r-SH.rowFrom)*SLOT;
  const out={therapists:[],bookings:[],blocks:[],cancels:[],manual:[],consults:[]};
  for(let c=SH.bFrom;c+SH.W-1<=L.bTo;c+=SH.W){
    const name=textOf(SH.headerRow,c);if(!name)continue;
    out.therapists.push({name,color:bgOf(SH.headerRow,c)});
    let grayStart=null;const flush=endRow=>{if(grayStart!=null){out.blocks.push({therapist:name,startMin:minOfRow(grayStart),endMin:minOfRow(endRow),kind:'off',text:'',color:SH.gray,note:''});grayStart=null;}};
    for(let r=SH.rowFrom;r<=SH.rowTo;r++){
      if(wideMerge(r,c)){const m=mergeAt.get(r+','+c);if(r===m.r1){flush(r);out.blocks.push({therapist:name,startMin:minOfRow(m.r1),endMin:minOfRow(m.r2+1),kind:'memo',text:textOf(m.r1,m.c1),color:bgOf(m.r1,m.c1)||SH.gray,note:''});}continue;}
      if(!isStart(r,c))continue;
      const text=textOf(r,c),color=bgOf(r,c),rows=spanRows(r,c);
      if(!text){if(color===SH.gray){if(grayStart==null)grayStart=r;}else flush(r);continue;}
      flush(r);const p=parsePatientSheet(text);
      if(!p||color===SH.gray){out.blocks.push({therapist:name,startMin:minOfRow(r),endMin:minOfRow(r+rows),kind:'memo',text,color,note:noteOf(r,c)});continue;}
      const mark=textOf(r,c+2);
      out.bookings.push({therapist:name,startMin:minOfRow(r),durationMin:rows*SLOT,rawText:text,mrn:p.mrn,room:p.room,patientName:p.name,visitNo:p.visit,
        code:textOf(r,c+1),codeColor:bgOf(r,c+1),color,visited:mark!==''||color==='#ffe599',mark,note:noteOf(r,c)});}
    flush(SH.rowTo+1);
    const cnt=consultOk?textOf(SH.consultRow,c):'';if(/^\d+$/.test(cnt))out.consults.push({therapist:name,count:parseInt(cnt,10)});}
  for(let c=L.cancelFrom;c<=L.cancelTo;c++){const th=textOf(SH.headerRow,c);
    for(let r=SH.rowFrom;r<=SH.rowTo;r++){const tx=textOf(r,c);if(!tx||!isStart(r,c))continue;const q=parsePatientSheet(tx);
      out.cancels.push({therapist:th,startMin:minOfRow(r),kind:strikeAt(XLSX.utils.encode_cell({r:r-1,c}))?'cancel':'change',text:tx,mrn:q?q.mrn:'',patientName:q?q.name:'',color:bgOf(r,c),note:noteOf(r,c)});}}
  for(let r=SH.rowFrom;r<=SH.rowTo+20;r++){const mrn=textOf(r,MF+1).replace(/\.0+$/,''),nm=textOf(r,MF+2);
    if(!mrn&&!nm)continue;if(!/^[가-힣A-Za-z]/.test(nm)||/^(null|0)$/i.test(mrn))continue;
    out.manual.push({no:parseInt(textOf(r,MF),10)||0,mrn,patientName:nm,therapist:textOf(r,MF+3),
      color:bgOf(r,MF+2)||bgOf(r,MF+1),note:noteOf(r,MF+2)||noteOf(r,MF+1)});}
  return out;}
/* 통합 문서 → {year, month, days:[{date, parsed}]} */
function parseSheetBook(wb){
  const one=wb.Sheets['1일'];if(!one)throw new Error("'1일' 탭이 없습니다. 예약리스트 시트가 맞는지 확인하세요.");
  const L1=sheetLayout(one);let year=L1.year,month=L1.month;
  if(!year){year=parseInt(String((one.BD1||{}).v||''),10);month=parseInt(String((one.BG1||{}).v||''),10);}
  if(!(year>2000&&month>=1&&month<=12))throw new Error("'1일' 탭에서 날짜를 찾지 못했습니다. '취소/변경' 칸 바로 위(1행)에 그 날 날짜가 있어야 합니다.");
  /* 취소선: 스타일 표(styles.xml)의 글꼴 → 칸의 스타일 번호 */
  const files=wb.files||{};const sx=zipText(files['xl/styles.xml']);
  const fontsXml=(/<fonts[^>]*>([\s\S]*?)<\/fonts>/.exec(sx)||[])[1]||'';const fonts=[...fontsXml.matchAll(/<font>([\s\S]*?)<\/font>|<font\/>/g)].map(m=>/<strike(?!\s+val="(0|false)")/.test(m[0]));
  const xfXml=(/<cellXfs[^>]*>([\s\S]*?)<\/cellXfs>/.exec(sx)||[])[1]||'';const xfStrike=[...xfXml.matchAll(/<xf\b[^>]*>/g)].map(m=>{const f=/fontId="(\d+)"/.exec(m[0]);return !!(f&&fonts[+f[1]]);});
  const days=[];const last=daysInMonth(year,month);
  wb.SheetNames.forEach((name,idx)=>{const m=/^(\d{1,2})일$/.exec(name);if(!m)return;const day=+m[1];if(day<1||day>last)return;
    const path=String((wb.Directory&&wb.Directory.sheets||[])[idx]||'').replace(/^\//,'');const xml=zipText(files[path]);
    const strikeSet=new Set();for(const c of xml.matchAll(/<c r="([A-Z]+\d+)"[^>]*?\ss="(\d+)"/g))if(xfStrike[+c[2]])strikeSet.add(c[1]);
    days.push({date:ymd(year,month,day),parsed:parseSheetDay(wb.Sheets[name],a=>strikeSet.has(a))});});
  days.sort((a,b)=>a.date<b.date?-1:1);
  return {year,month,days};}
/* 시트에서 읽은 것 → 가져오기 계획(planImport 와 같은 모양). 치료사는 이름으로 맞춘다.
   포털에 없는 이름 = 퇴사자 (2026-10-08) → 숨김(active:false)으로만 만들어 명단·새 날짜엔 안 나오고, 그 날 예약이 있는 날에만 열이 보인다(thOfDay). 환자는 모두 가져온다 */
function planFromSheets(books){
  const ths=META.therapists.map(t=>Object.assign({},t));let nextId=Math.max(Number(META.nextTid)||0,0,...ths.map(t=>t.id));
  const idOf=name=>{let t=ths.find(x=>x.name===name);if(!t){t={id:++nextId,name,color:'',single:false,inStats:true,active:false,sortOrder:ths.length};ths.push(t);NEWTH.push(name);}return t;};
  const consults={};const out=[];const manualNames={};const NEWTH=[];
  books.forEach(bk=>bk.days.forEach(({date,parsed})=>{const d=emptyDay(date);let nid=0;const id=()=>++nid;
    parsed.therapists.forEach(t=>{const x=idOf(t.name);if(t.color)x.color=t.color;d.th.push(x.id);});
    const tid=name=>idOf(name).id;
    parsed.bookings.forEach(b=>d.bookings.push({id:id(),therapistId:tid(b.therapist),startMin:b.startMin,durationMin:b.durationMin,mrn:b.mrn,room:b.room,patientName:b.patientName,visitNo:b.visitNo,
      rawText:b.rawText,code:b.code,codeColor:b.codeColor,color:b.color,visited:b.visited,mark:b.mark,note:b.note,createdBy:'시트 가져오기',updatedBy:'시트 가져오기'}));
    parsed.blocks.forEach(k=>d.blocks.push({id:id(),therapistId:tid(k.therapist),startMin:k.startMin,endMin:k.endMin,kind:k.kind,text:k.text,color:k.color,note:k.note,updatedBy:'시트 가져오기'}));
    parsed.cancels.forEach(c=>d.cancels.push({id:id(),therapistName:c.therapist,startMin:c.startMin,kind:c.kind,text:c.text,mrn:c.mrn,patientName:c.patientName,color:c.color,note:c.note,updatedBy:'시트 가져오기'}));
    parsed.manual.forEach(m=>{d.manual.push({id:id(),no:m.no,mrn:m.mrn,patientName:m.patientName,therapistName:m.therapist,color:m.color,note:m.note,updatedBy:'시트 가져오기'});
      const n=String(m.therapist||'').trim();if(n){const L=manualNames[d.ym]=manualNames[d.ym]||[];if(!L.includes(n))L.push(n);}});
    parsed.consults.forEach(c=>{const ym=d.ym;consults[ym]=consults[ym]||{};consults[ym][tid(c.therapist)]=c.count;});
    d.nid=nid;d.updatedAt=new Date().toISOString();d.updatedBy='시트 가져오기';
    if(d.th.length||d.bookings.length)out.push(d);}));
  const meta={therapists:ths,nextTid:nextId,consults:Object.assign({},META.consults,consults),manualNames:Object.assign({},META.manualNames,manualNames),dataDays:out.filter(d=>d.th.length).map(d=>d.date)};
  const sum=k=>out.reduce((a,d)=>a+d[k].length,0);
  return {meta,days:out,audits:[],sheet:true,newTh:NEWTH,n:{bookings:sum('bookings'),blocks:sum('blocks'),cancels:sum('cancels'),manual:sum('manual'),notes:0,consults:Object.values(consults).reduce((a,o)=>a+Object.keys(o).length,0)}};}
window.impLinks=async()=>{const txt=(document.getElementById('impLinks')||{}).value||'';IMP={name:'',links:txt};
  const ids=[...new Set(txt.split(/[\s,]+/).map(sheetIdOf).filter(Boolean))];
  if(!ids.length){IMP.err='구글 시트 링크를 넣어 주세요 (https://docs.google.com/spreadsheets/d/…).';render();return;}
  IMP.busy=true;IMP.log='엑셀 읽기 도구 불러오는 중…';render();
  try{await loadXlsxLib();const books=[];
    for(let i=0;i<ids.length;i++){IMP.log=`시트 ${i+1}/${ids.length} 내려받는 중…`;render();
      const res=await fetch(`https://docs.google.com/spreadsheets/d/${ids[i]}/export?format=xlsx`);
      if(!res.ok)throw new Error(`시트를 내려받지 못했습니다 (${res.status}). 공유 설정이 '링크가 있는 모든 사용자'인지 확인하세요.`);
      IMP.log=`시트 ${i+1}/${ids.length} 읽는 중… (몇 초 걸립니다)`;render();await new Promise(r=>setTimeout(r,30));
      const wb=XLSX.read(new Uint8Array(await res.arrayBuffer()),{type:'array',cellStyles:true,bookFiles:true});
      books.push(parseSheetBook(wb));}
    IMP.name=books.map(b=>`${b.year}년 ${b.month}월 시트`).join(' · ');IMP.plan=planFromSheets(books);IMP.mode='merge';IMP.pv=await previewMerge(IMP.plan);}
  catch(e){console.error(e);IMP.err=(e&&e.message)||String(e);if(/Failed to fetch|NetworkError/i.test(IMP.err))IMP.err='시트를 내려받지 못했습니다. 공유 설정이 \'링크가 있는 모든 사용자 — 뷰어\'인지 확인하세요.';}
  IMP.busy=false;IMP.log='';render();};

/* ═════════ 가져오기 (관리자·물리치료 직원) — 구글 시트 링크 또는 visit-stats 데이터베이스 백업(JSON) → 포털 ═════════ */
let IMP=null;   // {name, plan, busy, done, log}
function renderImportPage(){
  if(!canImport())return `<p class="err">관리자와 물리치료 직원만 쓸 수 있습니다.</p>`;
  let h=`<h1>가져오기</h1>
    <div class="panel"><h2>구글 시트 링크로</h2><p class="sub">비급여 예약리스트 시트 링크를 붙여 넣으세요. 여러 달이면 한 줄에 하나씩 (예: 9월 시트, 10월 시트). 시트를 읽은 뒤 <b>빠진 것만 추가</b>(포털에서 넣고 고친 내용은 그대로)와 통째로 덮어쓰기 중에 고릅니다.</p>
      <textarea id="impLinks" rows="3" style="width:100%" placeholder="https://docs.google.com/spreadsheets/d/…/edit?usp=sharing">${esc(IMP&&IMP.links||'')}</textarea>
      <div class="row"><button type="button" ${IMP&&IMP.busy?'disabled':''} onclick="impLinks()">${IMP&&IMP.busy&&IMP.log?esc(IMP.log):'시트 읽기'}</button></div></div>
    <div class="panel" style="margin-top:10px"><h2>visit-stats 백업 파일로</h2><p class="sub">visit-stats 데이터베이스 백업(JSON). 파일에 있는 날짜는 포털의 그 날짜를 통째로 덮어씁니다.</p>
      <div class="row"><input type="file" accept=".json,application/json" onchange="impFile(this.files[0])"></div></div>
    <div class="panel" style="margin-top:10px"><h2>코드별 치료 시간</h2><p class="sub">표시 칸에 시작 분(예: 35)을 적은 예약이 이 시간을 넘으면 빨갛게 깜빡입니다. 한 줄에 하나: <code>CM15 45</code>. 적지 않은 코드는 임시로 숫자 × 3분.</p>
      <textarea id="txMinTa" rows="8" style="width:100%" placeholder="CM10 30&#10;CM15 45&#10;CME15 45&#10;CRYO10 30">${esc(Object.entries(META.txMinutes||{}).sort().map(([k,v])=>k+' '+v).join('\n'))}</textarea>
      <div class="row"><button type="button" onclick="saveTxMin()">저장</button></div></div>`;
  if(IMP&&IMP.err)h+=`<p class="err">${esc(IMP.err)}</p>`;
  if(IMP&&IMP.plan){const p=IMP.plan;
    h+=`<div class="panel" style="margin-top:12px"><h2>${esc(IMP.name)}</h2><ul class="list">
      <li>날짜 ${p.days.length}일 (${esc(p.days[0]?p.days[0].date:'')} ~ ${esc(p.days.length?p.days[p.days.length-1].date:'')})</li>
      <li>예약 ${p.n.bookings} · 비근무/차단 ${p.n.blocks} · 취소/변경 ${p.n.cancels} · Manual Tx ${p.n.manual} · 특이사항 ${p.n.notes}</li>
      ${p.newTh&&p.newTh.length?`<li>포털에 없는 치료사 ${p.newTh.length}명(${esc(p.newTh.join(', '))}) — 퇴사자로 보고 <b>명단에는 넣지 않고</b>, 그 사람 환자 예약은 그 날짜에 가져옵니다</li>`:''}
      <li>치료사 ${p.meta.therapists.length}명 · 상담수 ${p.n.consults}건 · 변경 기록 ${p.audits.length}건</li></ul>
      ${p.sheet&&IMP.pv&&!IMP.done?`<div class="imp-mode">
        <label><input type="radio" name="impMode" ${IMP.mode==='merge'?'checked':''} onchange="IMP.mode='merge';render()"> <b>빠진 것만 추가 (권장)</b> — 포털 내용은 그대로 두고 시트에만 있는 것을 넣습니다</label>
        ${IMP.mode==='merge'?`<ul class="list"><li>추가할 것: 예약 <b>${IMP.pv.tot.b}</b> · 비근무/차단 ${IMP.pv.tot.k} · 취소/변경 ${IMP.pv.tot.c} · Manual Tx ${IMP.pv.tot.m}${IMP.pv.tot.whole?` (포털에 아직 없는 날 ${IMP.pv.tot.whole}일 포함)`:''}</li>
          <li>이미 포털에 있거나 포털에서 옮김·취소·삭제한 예약 ${IMP.pv.tot.same}건은 건드리지 않습니다</li>
          ${IMP.pv.skip.length?`<li class="err">자리가 겹쳐 넣지 못하는 예약 ${IMP.pv.skip.length}건 — 가져온 뒤 직접 넣어 주세요 (아래 목록)</li>`:''}</ul>`:''}
        <label><input type="radio" name="impMode" ${IMP.mode==='all'?'checked':''} onchange="IMP.mode='all';render()"> 통째로 덮어쓰기 — 포털에서 넣거나 고친 내용(표시·메모·취소 등)이 <b>사라집니다</b></label></div>`:''}
      ${(()=>{const sk=IMP.done?(IMP.result&&IMP.result.skip)||[]:(p.sheet&&IMP.mode==='merge'&&IMP.pv?IMP.pv.skip:[]);
        return sk.length?`<table class="imp-skip"><tr><th>날짜</th><th>환자</th><th>시트 자리</th><th>못 넣은 이유</th></tr>${sk.map(x=>`<tr><td><a href="#" onclick="go('schedule',{date:'${x.date}'});return false">${esc(x.date.slice(5))}</a></td><td>${esc(x.who)}</td><td>${esc(x.at)}</td><td>${esc(x.why)}</td></tr>`).join('')}</table>`:'';})()}
      ${IMP.done&&IMP.result?`<p class="info">추가했습니다: 예약 ${IMP.result.tot.b} · 비근무/차단 ${IMP.result.tot.k} · 취소/변경 ${IMP.result.tot.c} · Manual Tx ${IMP.result.tot.m}${IMP.result.skip.length?` · 자리가 겹쳐 못 넣은 ${IMP.result.skip.length}건은 위 목록을 보고 직접 넣어 주세요`:''}</p>`:''}
      ${IMP.done?`<p class="info">가져오기를 마쳤습니다. 일별 스케줄에서 확인하세요.</p>`:`<div class="row"><button type="button" ${IMP.busy?'disabled':''} onclick="impRun()">${IMP.busy?esc(IMP.log||'옮기는 중…'):'포털로 가져오기'}</button></div>`}</div>`;}
  return h;}
window.saveTxMin=async()=>{const t={};const bad=[];String((document.getElementById('txMinTa')||{}).value||'').split(/\r?\n/).forEach(l=>{l=l.trim();if(!l)return;const m=/^([A-Za-z]+\s*\d+)\s*[:=\s]\s*(\d{1,3})\s*분?$/.exec(l);if(!m){bad.push(l);return;}t[normalizeCode(m[1])]=+m[2];});
  if(bad.length){toast('알아볼 수 없는 줄: '+bad.join(', '),4000);return;}
  const r=await commitMeta(m=>{m.txMinutes=t;return {ok:true};},[{action:'update',entity:'therapists',entityId:'치료 시간표',after:{codes:Object.keys(t).length}}]);toast(r.ok?`치료 시간 ${Object.keys(t).length}개 저장했습니다`:(r.message||'저장하지 못했습니다'));};
window.impFile=async f=>{IMP={name:f?f.name:''};render();if(!f)return;
  try{const j=JSON.parse(await f.text());IMP.plan=planImport(j);}catch(e){IMP.err='파일을 읽지 못했습니다: '+e.message;}render();};
function planImport(j){
  const need=['therapists','day_therapists','bookings','work_blocks','cancels','manual_tx'];need.forEach(k=>{if(!Array.isArray(j[k]))throw new Error(k+' 표가 없습니다 (visit-stats 백업 파일이 맞는지 확인)');});
  const D10=s=>String(s||'').slice(0,10);
  const meta={therapists:j.therapists.map(t=>({id:Number(t.id),name:t.name,color:t.color||'',single:!!t.single,inStats:t.in_stats!==false,active:t.active!==false,sortOrder:Number(t.sort_order)||0})),
    consults:{},dataDays:[],manualNames:{},nextTid:Math.max(0,...j.therapists.map(t=>Number(t.id)))};
  (j.month_consults||[]).forEach(c=>{const ym=`${c.year}-${pad2(c.month)}`;meta.consults[ym]=meta.consults[ym]||{};meta.consults[ym][c.therapist_id]=Number(c.count)||0;});
  const days=new Map();const day=d=>{if(!days.has(d))days.set(d,emptyDay(d));return days.get(d);};
  const dts=j.day_therapists.slice().sort((a,b)=>(a.sort_order||0)-(b.sort_order||0));dts.forEach(x=>day(D10(x.date)).th.push(Number(x.therapist_id)));
  j.bookings.forEach(b=>day(D10(b.date)).bookings.push({id:Number(b.id),therapistId:Number(b.therapist_id),startMin:Number(b.start_min),durationMin:Number(b.duration_min),mrn:b.mrn||'',room:b.room||'',
    patientName:b.patient_name||'',visitNo:b.visit_no==null?null:Number(b.visit_no),rawText:b.raw_text||'',code:b.code||'',codeColor:b.code_color||'',color:b.color||'',visited:!!b.visited,mark:b.mark||'',note:b.note||'',
    createdBy:b.created_by||'',updatedBy:b.updated_by||'',createdAt:b.created_at||'',updatedAt:b.updated_at||''}));
  j.work_blocks.forEach(k=>day(D10(k.date)).blocks.push({id:Number(k.id),therapistId:Number(k.therapist_id),startMin:Number(k.start_min),endMin:Number(k.end_min),kind:k.kind==='memo'?'memo':'off',text:k.text||'',color:k.color||'',note:k.note||'',updatedBy:k.updated_by||'',updatedAt:k.updated_at||''}));
  j.cancels.forEach(c=>day(D10(c.date)).cancels.push({id:Number(c.id),therapistName:c.therapist_name||'',startMin:Number(c.start_min),kind:c.kind==='change'?'change':'cancel',text:c.text||'',mrn:c.mrn||'',patientName:c.patient_name||'',color:c.color||'',note:c.note||'',updatedBy:c.updated_by||'',updatedAt:c.updated_at||''}));
  j.manual_tx.forEach(m=>day(D10(m.date)).manual.push({id:Number(m.id),no:Number(m.no)||0,mrn:m.mrn||'',patientName:m.patient_name||'',therapistName:m.therapist_name||'',color:m.color||'',note:m.note||'',updatedBy:m.updated_by||'',updatedAt:m.updated_at||''}));
  (j.day_notes||[]).forEach(n=>{day(D10(n.date)).note=n.text||'';});
  const list=[...days.values()].sort((a,b)=>a.date<b.date?-1:1);
  list.forEach(d=>{d.nid=Math.max(0,...d.bookings.map(x=>x.id),...d.blocks.map(x=>x.id),...d.cancels.map(x=>x.id),...d.manual.map(x=>x.id));
    d.updatedAt=new Date().toISOString();d.updatedBy='가져오기';
    if(d.th.length)meta.dataDays.push(d.date);
    d.manual.forEach(m=>{const n=String(m.therapistName||'').trim();if(!n)return;const L=meta.manualNames[d.ym]=meta.manualNames[d.ym]||[];if(!L.includes(n))L.push(n);});});
  const audits=(j.audit_log||[]).map(a=>({at:a.at,user:a.user_email||'',email:a.user_email||'',action:a.action,entity:a.entity,entityId:String(a.entity_id||''),date:a.date?D10(a.date):null,before:a.before??null,after:a.after??null,legacy:true}));
  const sum=k=>list.reduce((a,d)=>a+d[k].length,0);
  return {meta,days:list,audits,n:{bookings:sum('bookings'),blocks:sum('blocks'),cancels:sum('cancels'),manual:sum('manual'),notes:list.filter(d=>d.note).length,consults:(j.month_consults||[]).length}};}
/* ═════ 시트에서 빠진 것만 추가 (2026-10-09 요청) ═════
   포털을 쓰기 시작한 뒤에도 시트에 예약이 더 들어갔다 → 시트를 통째로 덮어쓰면 포털에서 고친 것(표시·메모·옮김·취소)이 사라지므로,
   포털 하루 문서는 그대로 두고 시트에만 있는 것만 넣는다. 환자는 병록번호(없으면 이름)로 맞춘다.
   · 같은 환자가 포털에 같은 시각으로 있으면 = 이미 있음. 시각이 다르면 포털에서 옮긴 것으로 보고 넣지 않는다.
   · 포털에서 취소/변경·삭제(다른 날로 옮김 포함)한 환자도 다시 넣지 않는다 (변경 기록으로 확인).
   · 넣을 자리에 이미 다른 예약·비근무가 있으면 넣지 않고 목록으로 알린다 → 직접 넣기.
   · 비근무/차단은 그 칸이 비어 있고 포털에서 지운 적이 없을 때만, 취소/변경·Manual Tx 는 같은 환자가 없을 때만 넣는다. 특이사항은 포털 것 그대로 */
const pkey=x=>{const m=String(x.mrn||'').trim();if(m)return 'm'+m;const n=String(x.patientName||'').replace(/\s+/g,'');if(n)return 'n'+n;const r=String(x.rawText||x.text||'').replace(/\s+/g,'');return r?'r'+r:'';};
function groupBy(arr,f){const g=new Map();arr.forEach(x=>{const k=f(x);if(!k)return;if(!g.has(k))g.set(k,[]);g.get(k).push(x);});return g;}
const dayEmpty=d=>!d||!(d.th.length||d.bookings.length||d.blocks.length||d.cancels.length||d.manual.length);
async function portalDeletes(date){   // 포털에서 한 삭제 (visit-stats 에서 옮겨 온 예전 기록은 빼고)
  const s=await C.audit.where('date','==',date).get();return s.docs.map(x=>x.data()).filter(a=>a.action==='delete'&&!a.legacy);}
function mergeSheetDay(cur,s,auds){
  const add={b:0,k:0,c:0,m:0},skip=[];let same=0;
  if(dayEmpty(cur))return {d:jclone(s),add:{b:s.bookings.length,k:s.blocks.length,c:s.cancels.length,m:s.manual.length},skip,same,whole:true};
  const d=jclone(cur);const nm=x=>String(x.patientName||x.mrn||x.rawText||'').trim();
  const delB=groupBy(auds.filter(a=>a.entity==='bookings'&&a.before&&!a.after).map(a=>a.before),pkey);   // 그냥 삭제·다른 날로 옮김 (취소/변경으로 간 것은 취소 칸으로 센다)
  const delC=groupBy(auds.filter(a=>a.entity==='cancels'&&a.before).map(a=>a.before),pkey);
  const delM=groupBy(auds.filter(a=>a.entity==='manual_tx'&&a.before).map(a=>a.before),pkey);
  const delK=auds.filter(a=>a.entity==='work_blocks').map(a=>String(a.entityId||''));
  const sheetCx=groupBy(s.cancels,pkey),portCx=groupBy(d.cancels,pkey),portB=groupBy(d.bookings,pkey);
  const thName=id=>(thById(id)||{}).name||'';
  const hit=(tid,a,e)=>d.bookings.find(x=>x.therapistId===tid&&x.startMin<e&&a<x.startMin+x.durationMin)||d.blocks.find(x=>x.therapistId===tid&&x.startMin<e&&a<x.endMin);
  for(const [k,list] of groupBy(s.bookings,pkey)){const pb=(portB.get(k)||[]).slice();const rest=[];
    list.forEach(b=>{const i=pb.findIndex(x=>x.startMin===b.startMin);if(i>=0){pb.splice(i,1);same++;}else rest.push(b);});
    let spare=pb.length+Math.max(0,(portCx.get(k)||[]).length-(sheetCx.get(k)||[]).length)+(delB.get(k)||[]).length;
    rest.forEach(b=>{if(spare>0){spare--;same++;return;}
      const h=hit(b.therapistId,b.startMin,b.startMin+b.durationMin);
      if(h){skip.push({date:d.date,who:nm(b),at:`${thName(b.therapistId)} ${hm(b.startMin)}`,why:h.endMin!=null?`그 자리가 ${h.text||'비근무'}`:`그 자리에 ${nm(h)} 예약`});return;}
      d.bookings.push(Object.assign({},b,{id:newId(d)}));if(!d.th.includes(b.therapistId))d.th.push(b.therapistId);add.b++;});}
  s.blocks.forEach(k=>{if(!d.th.includes(k.therapistId)||hit(k.therapistId,k.startMin,k.endMin))return;
    if(delK.some(e=>e.startsWith(k.therapistId+':')||e.startsWith('전원:')))return;
    d.blocks.push(Object.assign({},k,{id:newId(d)}));add.k++;});
  s.cancels.forEach(c=>{const k=pkey(c);if(d.cancels.some(x=>x.therapistName===c.therapistName&&x.startMin===c.startMin)||(k&&(portCx.has(k)||delC.has(k))))return;
    d.cancels.push(Object.assign({},c,{id:newId(d)}));add.c++;});
  const nos=new Set(d.manual.map(m=>m.no));const portM=groupBy(d.manual,pkey);
  s.manual.forEach(m=>{const k=pkey(m);if(k&&(portM.has(k)||delM.has(k)))return;
    let no=m.no;if(nos.has(no))no=Math.max(0,...nos)+1;nos.add(no);d.manual.push(Object.assign({},m,{id:newId(d),no}));add.m++;});
  return {d,add,skip,same,whole:false};}
/* 미리보기: 지금 포털 상태로 무엇이 들어가는지 (실제 넣을 때는 그 순간의 포털 문서로 다시 계산) */
async function previewMerge(p){const tot={b:0,k:0,c:0,m:0,same:0,whole:0},skip=[];
  for(let i=0;i<p.days.length;i++){const s=p.days[i];IMP.log=`포털과 비교 중… ${i+1}/${p.days.length}`;if(i%5===0)render();
    const snap=await C.day.doc(s.date).get();const cur=snap.exists?normDay(snap.data(),s.date):null;
    const r=mergeSheetDay(cur,s,dayEmpty(cur)?[]:await portalDeletes(s.date));
    tot.b+=r.add.b;tot.k+=r.add.k;tot.c+=r.add.c;tot.m+=r.add.m;tot.same+=r.same;if(r.whole)tot.whole++;skip.push(...r.skip);}
  return {tot,skip};}
/* 설정 문서(치료사·상담수·Manual Tx 이름·데이터 있는 날) — 통째로 바꾸지 않고 합친다 (치료 시간표 등 다른 설정이 지워지지 않게).
   빠진 것만 추가할 때는 포털의 치료사 색·상담수를 그대로 둔다 */
function mergeMeta(m,pm,keep){
  const ths=Array.isArray(m.therapists)?m.therapists:[];
  (pm.therapists||[]).forEach(t=>{const x=ths.find(y=>y.id===t.id);if(!x)ths.push(t);else if(!keep)Object.assign(x,t);});
  m.therapists=ths;m.nextTid=Math.max(Number(m.nextTid)||0,Number(pm.nextTid)||0,...ths.map(t=>t.id));
  const cs=m.consults||{};Object.entries(pm.consults||{}).forEach(([ym,o])=>{cs[ym]=cs[ym]||{};Object.entries(o).forEach(([tid,n])=>{if(!keep||cs[ym][tid]==null)cs[ym][tid]=n;});});m.consults=cs;
  const mn=m.manualNames||{};Object.entries(pm.manualNames||{}).forEach(([ym,L])=>{mn[ym]=[...new Set([...(mn[ym]||[]),...L])];});m.manualNames=mn;
  m.dataDays=[...new Set([...(m.dataDays||[]),...(pm.dataDays||[])])].sort();return m;}
window.impRun=async()=>{if(!IMP||!IMP.plan||IMP.busy)return;const p=IMP.plan;const merge=!!(p.sheet&&IMP.mode==='merge');
  if(!confirm(merge?'시트에만 있는 예약 등을 포털에 추가할까요? 포털에 이미 있는 것과 포털에서 고친 내용은 그대로 둡니다.':`${p.days.length}일치를 포털로 가져올까요? 포털의 같은 날짜는 통째로 덮어써서, 포털에서 넣거나 고친 내용(표시·메모·취소 등)이 사라집니다.`))return;
  IMP.busy=true;IMP.err='';render();
  try{
    if(merge){const tot={b:0,k:0,c:0,m:0},skip=[];
      for(let i=0;i<p.days.length;i++){const s=p.days[i];IMP.log=`날짜 ${i+1}/${p.days.length}`;render();
        const auds=await portalDeletes(s.date);
        const r=await DB.runTransaction(async t=>{const ref=C.day.doc(s.date);const snap=await t.get(ref);const cur=snap.exists?normDay(snap.data(),s.date):null;
          const m=mergeSheetDay(cur,s,auds);
          if(m.add.b+m.add.k+m.add.c+m.add.m){m.d.updatedAt=new Date().toISOString();m.d.updatedBy=ME.name+' (시트에서 추가)';t.set(ref,JSON.parse(JSON.stringify(m.d)));}
          return m;});
        tot.b+=r.add.b;tot.k+=r.add.k;tot.c+=r.add.c;tot.m+=r.add.m;skip.push(...r.skip);}
      IMP.result={tot,skip};}
    else for(let i=0;i<p.days.length;i+=20){const b=DB.batch();p.days.slice(i,i+20).forEach(d=>b.set(C.day.doc(d.date),JSON.parse(JSON.stringify(d))));IMP.log=`날짜 ${Math.min(i+20,p.days.length)}/${p.days.length}`;render();await b.commit();}
    const mr=await commitMeta(m=>{mergeMeta(m,p.meta,merge);return {ok:true};});if(!mr.ok)throw new Error(mr.message||'설정을 저장하지 못했습니다');
    for(let i=0;i<p.audits.length;i+=200){const b=DB.batch();p.audits.slice(i,i+200).forEach(a=>b.set(C.audit.doc(),JSON.parse(JSON.stringify(a))));await b.commit();}
    writeAudits([{action:'import',entity:'sheet',entityId:IMP.name,date:null,before:null,after:merge?Object.assign({mode:'빠진 것만 추가'},IMP.result.tot):{days:p.days.length,bookings:p.n.bookings}}]);
    Object.keys(MONTHS).forEach(k=>delete MONTHS[k]);ALLDOCS={at:0,docs:null};IMP.done=true;}
  catch(e){console.error(e);IMP.err='가져오지 못했습니다: '+e.message;}
  IMP.busy=false;IMP.log='';render();};
/* ═════ 새 버전 자동 적용 (2026-10-11) — 10분마다 pt4.html·pt4-views.js 를 다시 받아 바뀌었으면, 입력 중이 아닐 때 스스로 새로고침.
   동선관리 안에 띄운 4층 화면은 동선관리가 새로고침하며 같이 바뀌지만, '새 창'으로 따로 연 4층 화면은 이게 없으면 예전 코드로 계속 돈다 ═════ */
let PT4_SIG='';
async function pt4CheckBuild(){try{
  const t=(await Promise.all(['pt4.html','pt4-views.js'].map(u=>fetch(u,{cache:'no-store'}).then(r=>r.ok?r.text():'')))).join('|');
  if(t.length<10000)return;let h=0;for(let i=0;i<t.length;i+=89)h=(h*31+t.charCodeAt(i))>>>0;const sig=t.length+'-'+h;
  if(!PT4_SIG){PT4_SIG=sig;return;}if(sig===PT4_SIG)return;
  const a=document.activeElement;const busy=EDIT||DRAG||(typeof MAN!=='undefined'&&MAN&&MAN.no!=null)||(a&&/^(INPUT|TEXTAREA|SELECT)$/.test(a.tagName||''));
  if(busy){setTimeout(pt4CheckBuild,2*60000);return;}
  try{writeAudits([{action:'view',entity:'page',entityId:'새 버전 자동 새로고침',date:null,before:null,after:null}]);}catch(e){}
  setTimeout(()=>location.reload(),600);}catch(e){}}
setTimeout(pt4CheckBuild,20000);setInterval(pt4CheckBuild,10*60000);
