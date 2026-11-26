/* 건강보험심사평가원 약가기준정보조회서비스(getDgamtList) — URL 만들기 · XML 응답 읽기 (순수 함수, 2026-11-26)
   인증키는 호출하는 쪽(서버)이 환경변수에서 넘겨주며, 이 파일은 키를 저장하거나 기록하지 않는다. */
const BASE = "https://apis.data.go.kr/B551182/dgamtCrtrInfoService1.2/getDgamtList";

const txt = (v) => (v == null ? "" : String(v).trim());

/* 인증키: 포털의 'Encoding 키'(%2B 등 이미 인코딩)와 'Decoding 키'(+ / =) 어느 쪽이든 한 번만 인코딩 */
function encKey(key) {
  let k = txt(key);
  if (/%[0-9A-Fa-f]{2}/.test(k)) { try { k = decodeURIComponent(k); } catch (_) { /* 그대로 */ } }
  return encodeURIComponent(k);
}

export function buildDgamtUrl(o) {
  const p = o || {};
  const q = [`serviceKey=${encKey(p.key)}`, `numOfRows=${Math.max(1, parseInt(p.rows, 10) || 10)}`, `pageNo=${Math.max(1, parseInt(p.page, 10) || 1)}`];
  const add = (name, v) => { const t = txt(v).slice(0, 100); if (t) q.push(`${name}=${encodeURIComponent(t)}`); };   // 검색어는 100자까지
  add("mdsCd", p.code);
  add("itmNm", p.name);
  add("mnfEntpNm", p.maker);
  return BASE + "?" + q.join("&");
}

const unesc = (s) => s
  .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'")
  .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(+d))
  .replace(/&#x([0-9a-fA-F]+);/g, (_, h) => String.fromCodePoint(parseInt(h, 16)))
  .replace(/&amp;/g, "&");

function tag(block, name) {
  const m = new RegExp(String.raw`<${name}>([\s\S]*?)</${name}>`).exec(block);
  return m ? unesc(m[1].replace(/^<!\[CDATA\[|\]\]>$/g, "")).trim() : "";
}

export function parseDgamtXml(xml) {
  const x = txt(xml);
  if (x.includes("<OpenAPI_ServiceResponse")) {
    const msg = tag(x, "returnAuthMsg") || tag(x, "errMsg") || "서비스 오류";
    return { ok: false, resultCode: tag(x, "returnReasonCode"), message: msg, total: 0, items: [] };
  }
  if (!x.includes("<response")) return { ok: false, resultCode: "", message: "응답을 읽을 수 없습니다.", total: 0, items: [] };
  const code = tag(x, "resultCode");
  if (code && code !== "00") return { ok: false, resultCode: code, message: tag(x, "resultMsg") || "서비스 오류", total: 0, items: [] };
  const items = [...x.matchAll(/<item>([\s\S]*?)<\/item>/g)].map((m) => {
    const b = m[1];
    return {
      code: tag(b, "mdsCd"), name: tag(b, "itmNm"), maker: tag(b, "mnfEntpNm"), unit: tag(b, "unit"), spec: tag(b, "nomNm"),
      price: parseInt(tag(b, "mxCprc"), 10) || 0, payType: tag(b, "payTpNm"), changedCode: tag(b, "chgAfMdsCd"),
      startDate: tag(b, "adtStaDd"), route: tag(b, "injcPthNm"), kind: tag(b, "spcGnlTpNm"),
    };
  });
  const total = parseInt(tag(x, "totalCount"), 10);
  return { ok: true, resultCode: "00", message: "", total: Number.isFinite(total) ? total : items.length, items };
}

/* 삭제된 코드 / 변경 코드 안내 */
export function itemWarning(item) {
  const it = item || {};
  const w = [];
  if (it.payType === "삭제") w.push("삭제된 코드입니다");
  if (it.changedCode && it.changedCode !== it.code) w.push("변경 코드: " + it.changedCode);
  return w.join(" · ");
}

/* 상위 서비스 오류 메시지를 화면에 내보내기 전에 정리: 인증키(원문·인코딩 형태)를 지우고 200자로 자른다 */
export function safeMessage(msg, key) {
  let m = txt(msg);
  const k = txt(key);
  if (k) {
    let dec = k;
    if (/%[0-9A-Fa-f]{2}/.test(k)) { try { dec = decodeURIComponent(k); } catch (_) { /* 그대로 */ } }
    for (const v of new Set([k, dec, encodeURIComponent(dec)])) if (v) m = m.split(v).join("***");
  }
  return m.slice(0, 200);
}
