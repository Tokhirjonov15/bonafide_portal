import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import { buildDgamtUrl, parseDgamtXml, itemWarning, safeMessage } from "../../src/hira.js";

const sample = fs.readFileSync(new URL("../fixtures/hira-getDgamtList.xml", import.meta.url), "utf8");
const wrap = (items, extra = "") => `<?xml version="1.0" encoding="UTF-8"?><response><header><resultCode>00</resultCode><resultMsg>NORMAL SERVICE.</resultMsg></header><body>${items}${extra}</body></response>`;

test("샘플 응답을 읽는다", () => {
  const r = parseDgamtXml(sample);
  assert.equal(r.ok, true);
  assert.equal(r.total, 1);
  assert.deepEqual(r.items[0], {
    code: "G03900131", name: "레스피렌정", maker: "건일제약", unit: "정", spec: "1", price: 0,
    payType: "삭제", changedCode: "G09900011", startDate: "20050401", route: "내복", kind: "전문",
  });
});

test("결과 0건: items 가 비었거나 없어도 정상", () => {
  assert.deepEqual(parseDgamtXml(wrap("<items/>", "<totalCount>0</totalCount>")).items, []);
  const r = parseDgamtXml(wrap("", "<totalCount>0</totalCount>"));
  assert.equal(r.ok, true); assert.equal(r.total, 0); assert.deepEqual(r.items, []);
});

test("여러 건은 순서대로", () => {
  const it = (c, n) => `<item><mdsCd>${c}</mdsCd><itmNm>${n}</itmNm></item>`;
  const r = parseDgamtXml(wrap(`<items>${it("A1", "가")}${it("B2", "나")}</items>`, "<totalCount>2</totalCount>"));
  assert.deepEqual(r.items.map((x) => x.code), ["A1", "B2"]);
  assert.equal(r.total, 2);
});

test("XML 엔티티는 풀어서 읽는다", () => {
  const r = parseDgamtXml(wrap("<items><item><mdsCd>A1</mdsCd><itmNm>A&amp;B정</itmNm></item></items>"));
  assert.equal(r.items[0].name, "A&B정");
});

test("resultCode 가 00 이 아니면 오류", () => {
  const r = parseDgamtXml(`<response><header><resultCode>30</resultCode><resultMsg>SERVICE KEY IS NOT REGISTERED ERROR.</resultMsg></header></response>`);
  assert.equal(r.ok, false);
  assert.match(r.message, /SERVICE KEY IS NOT REGISTERED/);
});

test("포털 공통 오류 형식(OpenAPI_ServiceResponse)도 오류", () => {
  const r = parseDgamtXml(`<OpenAPI_ServiceResponse><cmmMsgHeader><errMsg>SERVICE ERROR</errMsg><returnAuthMsg>SERVICE_KEY_IS_NOT_REGISTERED_ERROR</returnAuthMsg><returnReasonCode>30</returnReasonCode></cmmMsgHeader></OpenAPI_ServiceResponse>`);
  assert.equal(r.ok, false);
  assert.match(r.message, /SERVICE_KEY_IS_NOT_REGISTERED_ERROR/);
});

test("XML 이 아닌 응답은 오류", () => {
  assert.equal(parseDgamtXml("<html>gateway</html>").ok, false);
  assert.equal(parseDgamtXml("").ok, false);
});

test("URL: 인증키는 인코딩되고 이미 인코딩된 키는 그대로", () => {
  assert.match(buildDgamtUrl({ key: "a+b/c=", code: "G1" }), /serviceKey=a%2Bb%2Fc%3D(&|$)/);
  assert.match(buildDgamtUrl({ key: "a%2Bb%2Fc%3D", code: "G1" }), /serviceKey=a%2Bb%2Fc%3D(&|$)/);
});

test("URL: 한글은 인코딩, 빈 값은 생략, 기본 10건·1쪽", () => {
  const u = buildDgamtUrl({ key: "k", name: "피렌정", code: "", maker: "" });
  assert.ok(u.startsWith("https://apis.data.go.kr/B551182/dgamtCrtrInfoService1.2/getDgamtList?"));
  assert.match(u, /itmNm=%ED%94%BC%EB%A0%8C%EC%A0%95/);
  assert.doesNotMatch(u, /mdsCd=|mnfEntpNm=/);
  assert.match(u, /numOfRows=10/);
  assert.match(u, /pageNo=1/);
});

test("경고: 삭제·변경 코드", () => {
  assert.equal(itemWarning({ code: "A", payType: "삭제", changedCode: "" }), "삭제된 코드입니다");
  assert.equal(itemWarning({ code: "A", payType: "급여", changedCode: "B" }), "변경 코드: B");
  assert.equal(itemWarning({ code: "A", payType: "삭제", changedCode: "B" }), "삭제된 코드입니다 · 변경 코드: B");
  assert.equal(itemWarning({ code: "A", payType: "급여", changedCode: "A" }), "");
  assert.equal(itemWarning({ code: "A", payType: "급여", changedCode: "" }), "");
});

test("오류 메시지에서 인증키(원문·인코딩)를 지우고 200자로 자른다", () => {
  const m = safeMessage("bad key a+b/c= and a%2Bb%2Fc%3D here", "a+b/c=");
  assert.ok(!m.includes("a+b/c=") && !m.includes("a%2Bb%2Fc%3D"));
  assert.ok(m.includes("***"));
  assert.equal(safeMessage("x".repeat(500), "k").length, 200);
  assert.equal(safeMessage(null, "k"), "");
});

test("URL: 검색어는 100자까지만", () => {
  const u = buildDgamtUrl({ key: "k", name: "가".repeat(300) });
  const v = decodeURIComponent(/itmNm=([^&]*)/.exec(u)[1]);
  assert.equal(v.length, 100);
});
