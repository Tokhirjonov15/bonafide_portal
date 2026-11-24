# -*- coding: utf-8 -*-
"""
비트 저장 승인 시스템 - 서브 PC 측 에이전트 (v3, 3계층)

토폴로지
  [간호 PC]  nurse_pc_request.py → HTTP /enqueue
  [서브 PC]  이 파일: 요청 수신 → 저장 버튼 클릭 → 팝업 처리  ← 간호가 미러링으로 입력
  [원장 PC]  doctor_button.py → HTTP /approve

역할
 - 간호가 미러링으로 입력을 마치고 [입력 완료]를 누르면 이 PC의 대기열에 들어온다
 - 원장님 승인 버튼이 눌리면 그 1건만 실행한다
 - 원장 판단이 필요한 팝업(DUR·산정특례·미확인)이 뜨면 즉시 중단하고 보고한다
 - 실행 전/후 화면을 logs/ 에 남긴다

실행:  python sub_pc_agent.py            (실제)
       python sub_pc_agent.py --dry-run  (탐지만, 클릭·입력 없음)
"""

import json
import os
import sys
import threading
import time
import traceback
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import tkinter as tk
from tkinter import font as tkfont

BASE = os.path.dirname(os.path.abspath(__file__))
TPL_DIR = os.path.join(BASE, "templates")
LOG_DIR = os.path.join(BASE, "logs")
os.makedirs(TPL_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)

with open(os.path.join(BASE, "config.json"), encoding="utf-8") as f:
    CFG = json.load(f)

DRY_RUN = "--dry-run" in sys.argv

try:
    import pyautogui
    import pygetwindow as gw
    pyautogui.FAILSAFE = True
    pyautogui.PAUSE = 0.05
except Exception as e:  # noqa: BLE001
    print("[FATAL] pyautogui / pygetwindow 로드 실패:", e)
    print("        pip install pyautogui opencv-python pillow pygetwindow pywin32")
    sys.exit(1)

LOCK = threading.Lock()
STATE = {"pending": [], "running": False, "last": None, "halt": None}
SEQ = {"n": 0}
GUI = {}


def now():
    return datetime.now().strftime("%H:%M:%S")


def shot(tag):
    p = os.path.join(LOG_DIR, f"{datetime.now():%Y%m%d_%H%M%S}_{tag}.png")
    try:
        pyautogui.screenshot(p)
        return p
    except Exception:  # noqa: BLE001
        return None


def get_bit_window():
    kw = CFG["window_keyword"].lower()
    wins = [w for w in gw.getAllWindows() if w.visible and kw in (w.title or "").lower()]
    if not wins:
        return None
    w = sorted(wins, key=lambda x: x.width * x.height, reverse=True)[0]
    try:
        if w.isMinimized:
            w.restore()
        w.activate()
        time.sleep(CFG["delays"]["after_activate"])
        return w
    except Exception:  # noqa: BLE001
        return None


def find(file_name, win):
    """비트 창 내부에서만 이미지 탐색."""
    path = os.path.join(TPL_DIR, file_name)
    if not os.path.exists(path):
        return None
    region = None
    if win is not None:
        try:
            region = (max(win.left, 0), max(win.top, 0), int(win.width), int(win.height))
        except Exception:  # noqa: BLE001
            region = None
    try:
        box = pyautogui.locateOnScreen(path, confidence=CFG["confidence"], region=region)
    except Exception:  # noqa: BLE001
        return None
    return pyautogui.center(box) if box else None


def run_save(ticket):
    tid = ticket["id"]
    win = get_bit_window()
    if win is None:
        return False, f"비트 창을 찾지 못했습니다 (키워드: {CFG['window_keyword']})", None

    shot(f"{tid:04d}_before")

    pt = None
    for _ in range(CFG["retry"]["save_attempts"]):
        pt = find(CFG["templates"]["save"], win)
        if pt:
            break
        time.sleep(CFG["retry"]["save_interval"])
    if not pt:
        return False, "저장 버튼을 확인하지 못해 중단 (클릭 안 함)", None
    if DRY_RUN:
        return True, "[DRY-RUN] 저장 버튼 위치 확인 완료. 클릭하지 않았습니다.", None

    pyautogui.click(pt)
    time.sleep(CFG["delays"]["after_save_click"])

    handled = []
    quiet = CFG["retry"]["popup_quiet"]
    total = CFG["retry"]["popup_total_timeout"]
    stuck_limit = CFG["retry"].get("popup_stuck_limit", 3)
    max_actions = CFG["retry"].get("max_popup_actions", 20)
    stuck = {}
    start = last_hit = time.time()
    slip_print = ticket.get("slip_print", CFG["slip"]["default_print"])

    def halt(popup, reason):
        s = shot(f"{tid:04d}_halt_{popup}")
        return False, reason, {"id": tid, "patient": ticket["patient"],
                               "popup": popup, "shot": s}

    while (time.time() - start) < total and (time.time() - last_hit) < quiet:
        if len(handled) >= max_actions:
            return halt("반복", f"팝업이 {len(handled)}건 넘게 반복되어 중단했습니다.")
        hit = False
        for p in CFG["popups"]:
            name, mode = p["name"], p.get("mode", "auto")
            if not find(p["file"], win):
                continue

            # 팝업이 떴다는 사실 자체를 증빙으로 남긴다 (DUR 사유·경고 문구 포함)
            shot(f"{tid:04d}_pop{len(handled) + 1:02d}_{name}")

            if mode == "manual":
                return halt(name, f"'{name}' 팝업 — 원장님 확인 필요. 자동 진행 중단.")

            if mode == "auto":
                ok_btn = p.get("ok")
                clicked = None
                if ok_btn:
                    clicked = find(ok_btn, win)
                if clicked:
                    pyautogui.click(clicked)
                elif CFG.get("popup_input_method") == "enter":
                    pyautogui.press("enter")
                else:
                    pyautogui.click(pyautogui.center(find(p["file"], win)))

                time.sleep(CFG["delays"].get("after_popup_verify", 0.5))
                if find(p["file"], win):
                    # 확인을 눌렀는데도 안 닫힘 → 사유 입력 초기화·필수 선택 등
                    stuck[name] = stuck.get(name, 0) + 1
                    if stuck[name] >= stuck_limit:
                        return halt(name, (
                            f"'{name}' 팝업이 {stuck[name]}회 확인 후에도 닫히지 않았습니다. "
                            "사유 입력이 초기화됐거나 선택이 필요한 상태입니다. 중단합니다."))
                    last_hit = time.time()
                    hit = True
                    break
                stuck[name] = 0
                handled.append(name)

            elif mode == "choice":
                btn = CFG["slip"]["yes_button"] if slip_print else CFG["slip"]["no_button"]
                c = find(btn, win)
                if not c:
                    return halt("슬립지인쇄", "슬립지 인쇄 선택 버튼을 찾지 못해 중단했습니다.")
                pyautogui.click(c)
                handled.append("슬립지:" + ("인쇄" if slip_print else "안함"))

            last_hit = time.time()
            hit = True
            time.sleep(CFG["delays"]["after_popup_action"])
            break
        if not hit:
            time.sleep(0.25)

    shot(f"{tid:04d}_after")
    if handled:
        msg = (f"저장 완료 · 팝업 {len(handled)}건 자동확인 "
               f"({'→'.join(dict.fromkeys(handled))})")
    else:
        msg = "저장 완료 · 팝업 없음"
    return True, msg, None


def worker():
    while True:
        ticket = None
        with LOCK:
            if not STATE["running"] and STATE["pending"]:
                ticket = STATE["pending"].pop(0)
                STATE["running"] = True
        if not ticket:
            time.sleep(0.2)
            continue
        ok, msg, halt = False, "오류", None
        try:
            ok, msg, halt = run_save(ticket)
        except pyautogui.FailSafeException:
            msg = "안전 중단(마우스 좌상단) — 실행 취소"
        except Exception:  # noqa: BLE001
            msg = "예외: " + traceback.format_exc(limit=2).replace("\n", " ")[:200]
        with LOCK:
            STATE["running"] = False
            STATE["last"] = {"id": ticket["id"], "ok": ok, "msg": msg, "at": now()}
            STATE["halt"] = halt
        print(f"[{now()}] #{ticket['id']} {ticket['patient']} → {'OK' if ok else 'STOP'} {msg}")
        refresh()


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.startswith("/status"):
            with LOCK:
                self._send(200, {
                    "pending": len(STATE["pending"]), "running": STATE["running"],
                    "next": STATE["pending"][0]["patient"] if STATE["pending"] else None,
                    "last": STATE["last"], "halt": STATE["halt"], "dry_run": DRY_RUN})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        try:
            data = json.loads((self.rfile.read(n) if n else b"{}").decode("utf-8") or "{}")
        except Exception:  # noqa: BLE001
            data = {}

        if self.path.startswith("/approve"):
            with LOCK:
                if STATE["running"]:
                    self._send(200, {"ok": False, "reason": "실행 중"})
                elif not STATE["pending"]:
                    self._send(200, {"ok": False, "reason": "대기 없음"})
                else:
                    t = STATE["pending"][0]
                    self._send(200, {"ok": True, "id": t["id"], "target": t["patient"]})
            return
        if self.path.startswith("/enqueue"):
            with LOCK:
                SEQ["n"] += 1
                STATE["pending"].append({
                    "id": SEQ["n"],
                    "patient": (data.get("patient") or "").strip() or "(미지정)",
                    "slip_print": bool(data.get("slip_print", CFG["slip"]["default_print"])),
                    "at": now()})
                STATE["halt"] = None
            refresh()
            self._send(200, {"ok": True, "id": SEQ["n"]})
            return
        if self.path.startswith("/ack"):
            with LOCK:
                STATE["halt"] = None
            refresh()
            self._send(200, {"ok": True})
            return
        self._send(404, {"error": "not found"})


def serve():
    ThreadingHTTPServer(("0.0.0.0", CFG["port"]), Handler).serve_forever()


# ── 서브 PC 상태창 (작게, 항상 위) ──
def refresh():
    r = GUI.get("root")
    if r is None:
        return
    try:
        with LOCK:
            n = len(STATE["pending"]); running = STATE["running"]
            halt = STATE["halt"]; last = STATE["last"]
        if halt:
            GUI["lbl"].config(text=f"⚠ 중단 · {halt['patient']} · {halt['popup']}", bg="#f9a825", fg="#212121")
        elif running:
            GUI["lbl"].config(text="저장 실행 중…", bg="#1a73e8", fg="white")
        elif n:
            GUI["lbl"].config(text=f"대기 {n}건 · 원장님 승인 대기", bg="#c62828", fg="white")
        else:
            GUI["lbl"].config(text="대기 없음", bg="#2e7d32", fg="white")
        msg = ""
        if last:
            msg = f"최근 #{last['id']} {'완료' if last['ok'] else '중단'} ({last['at']})"
        GUI["sub"].config(text=msg + ("\n※ DRY-RUN" if DRY_RUN else ""))
        r.bell() if halt else None
    except Exception:  # noqa: BLE001
        pass


def small_window():
    root = tk.Tk(); GUI["root"] = root
    root.title("서브PC 저장 대기")
    root.geometry("340x132+20+20")
    root.attributes("-topmost", True); root.configure(bg="#202124")
    f = tkfont.Font(family="맑은 고딕", size=12, weight="bold")
    s = tkfont.Font(family="맑은 고딕", size=9)
    GUI["lbl"] = tk.Label(root, text="대기 없음", font=f, bg="#2e7d32", fg="white")
    GUI["lbl"].pack(fill="x", padx=10, pady=(10, 6), ipady=10)

    def ack():
        with LOCK:
            STATE["halt"] = None
        refresh()

    tk.Button(root, text="중단 해제 (원장님 확인 후)", command=ack, font=s, bg="#303134",
              fg="#e8eaed", relief="flat", cursor="hand2").pack(fill="x", padx=10)
    GUI["sub"] = tk.Label(root, text="", font=s, bg="#202124", fg="#9aa0a6", justify="left")
    GUI["sub"].pack(fill="x", padx=12, pady=6)
    refresh()
    root.mainloop()


if __name__ == "__main__":
    threading.Thread(target=serve, daemon=True).start()
    threading.Thread(target=worker, daemon=True).start()
    small_window()
