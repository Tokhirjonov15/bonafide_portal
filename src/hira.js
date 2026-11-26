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

/* 작은 시간제한 캐시 (서버 인스턴스 메모리) — 공공데이터 서비스 응답이 10~18초 걸려서 같은 검색을 잠시 기억한다.
   now 는 시험용으로 바꿀 수 있다. 가득 차면 가장 먼저 넣은 것부터 버린다. */
export function createCache(o) {
  const ttl = (o && o.ttlMs) || 3600000, max = (o && o.max) || 200, now = (o && o.now) || Date.now;
  const m = new Map();
  return {
    get(k) {
      const e = m.get(k);
      if (!e) return undefined;
      if (now() >= e.until) { m.delete(k); return undefined; }
      return e.v;
    },
    set(k, v) {
      if (m.has(k)) m.delete(k);
      m.set(k, { v, until: now() + ttl });
      while (m.size > max) m.delete(m.keys().next().value);
    },
  };
}

/* 상위 서비스 오류 메시지를 사용자용 한국어 안내로 (알려진 것만, 나머지는 그대로) */
export function friendlyMessage(msg) {
  const m = txt(msg);
  if (/ResourceLimitException|No resources currently available|pool/i.test(m)) return "공공데이터 서비스가 혼잡합니다. 잠시 후 다시 검색해 주세요.";
  if (/NOT REGISTERED/i.test(m)) return "인증키가 아직 등록되지 않았거나 승인 대기 중입니다. 신청 승인 후 잠시 뒤 다시 시도해 주세요.";
  if (/EXCEEDS|LIMITED NUMBER/i.test(m)) return "오늘 조회 한도를 넘었습니다. 내일 다시 시도해 주세요.";
  return m;
}
