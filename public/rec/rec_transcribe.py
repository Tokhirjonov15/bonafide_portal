# -*- coding: utf-8 -*-
"""진료 녹음 받아쓰기 (2026-10-12) — 진료실 PC 에서 돈다.

동선관리 [녹음]이 외장하드 폴더에 저장한 '녹음 … .webm' 을 지켜보다가, 녹음이 끝난 파일(90초 넘게 그대로인 것)을
faster-whisper 로 한국어 글로 바꿔 같은 이름의 .txt 를 옆에 만든다. 인터넷으로 소리를 보내지 않는다(모델은 처음 한 번만 내려받음).
동선관리 화면이 그 .txt 를 읽어 환자 정보 창 '녹음기록' 에 올린다 — 이 프로그램은 동선관리에 접속하지 않는다.

  python rec_transcribe.py --dir "E:\\진료녹음"            # 계속 지켜보기
  python rec_transcribe.py --dir "E:\\진료녹음" --once     # 지금 있는 것만 바꾸고 끝
  python rec_transcribe.py --warmup                        # 모델만 내려받기(설치 때)
"""
import argparse, ctypes, os, sys, time, traceback, datetime

APP = os.path.join(os.environ.get('LOCALAPPDATA', os.path.expanduser('~')), 'rec_transcribe')
os.makedirs(APP, exist_ok=True)
LOG = os.path.join(APP, 'log.txt')
QUIET_SEC = 90          # 녹음은 10초마다 이어 쓰므로, 90초 넘게 그대로면 끝난 것으로 본다
MAX_TRY = 3             # 같은 파일이 이만큼 실패하면 건너뛴다(.err 에 횟수)
PROMPT = '정형외과 진료실 대화입니다. 무릎, 어깨, 허리, 목, 발목, 손목, 통증, 주사, 물리치료, 도수치료, 체외충격파, 엑스레이, MRI, 처방, 약.'


def log(*a):
    line = datetime.datetime.now().strftime('%m-%d %H:%M:%S ') + ' '.join(str(x) for x in a)
    try:
        print(line, flush=True)
    except Exception:
        pass
    try:
        if os.path.exists(LOG) and os.path.getsize(LOG) > 2_000_000:
            os.replace(LOG, LOG + '.old')
        with open(LOG, 'a', encoding='utf-8') as f:
            f.write(line + '\n')
    except Exception:
        pass


def low_priority():
    """다른 일(비트·브라우저)이 느려지지 않게 '낮음' 우선순위로"""
    try:
        BELOW_NORMAL = 0x4000
        ctypes.windll.kernel32.SetPriorityClass(ctypes.windll.kernel32.GetCurrentProcess(), BELOW_NORMAL)
    except Exception:
        pass


_model = None
def model(name, threads):
    global _model
    if _model is None:
        from faster_whisper import WhisperModel
        log('모델 불러오는 중:', name)
        _model = WhisperModel(name, device='cpu', compute_type='int8', cpu_threads=threads)
        log('모델 준비됨')
    return _model


def mmss(t):
    t = int(t); return f'{t // 60:02d}:{t % 60:02d}'


def transcribe(path, name, threads):
    m = model(name, threads)
    t0 = time.time()
    segs, info = m.transcribe(path, language='ko', vad_filter=True, beam_size=1,
                              condition_on_previous_text=False, initial_prompt=PROMPT)
    lines = [f'[{mmss(s.start)}] {s.text.strip()}' for s in segs if s.text.strip()]
    log(f'  {info.duration:.0f}초 녹음 → {len(lines)}줄, {time.time() - t0:.0f}초 걸림')
    return '\n'.join(lines)


def todo(folder):
    out = []
    now = time.time()
    for fn in os.listdir(folder):
        if not fn.lower().endswith('.webm'):
            continue
        p = os.path.join(folder, fn)
        base = p[:-5]
        try:
            st = os.stat(p)
        except OSError:
            continue
        if st.st_size < 2000 or now - st.st_mtime < QUIET_SEC:
            continue                                    # 아직 녹음 중이거나 너무 짧음
        txt = base + '.txt'
        if os.path.exists(txt) and os.path.getmtime(txt) >= st.st_mtime:
            continue                                    # 이미 바꿈 (시험 녹음처럼 다시 녹음했으면 다시)
        err = base + '.err'
        if os.path.exists(err):
            try:
                if int(open(err, encoding='utf-8').read().strip() or 0) >= MAX_TRY:
                    continue
            except Exception:
                pass
        out.append((st.st_mtime, p))
    return [p for _, p in sorted(out)]                  # 오래된 것부터


def run_one(p, name, threads):
    base = p[:-5]
    log('바꾸는 중:', os.path.basename(p))
    try:
        text = transcribe(p, name, threads)
        tmp = base + '.txt.part'
        with open(tmp, 'w', encoding='utf-8') as f:
            f.write(text if text else '(말소리를 찾지 못했습니다)')
        os.replace(tmp, base + '.txt')                  # 다 쓴 뒤 이름을 바꿔, 화면이 반쯤 쓴 글을 읽지 않게
        if os.path.exists(base + '.err'):
            os.remove(base + '.err')
    except Exception as e:
        log('  실패:', e)
        log(traceback.format_exc())
        n = 0
        try:
            n = int(open(base + '.err', encoding='utf-8').read().strip() or 0)
        except Exception:
            pass
        try:
            with open(base + '.err', 'w', encoding='utf-8') as f:
                f.write(str(n + 1))
        except Exception:
            pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dir', help='녹음 폴더(외장하드)')
    ap.add_argument('--model', default='large-v3-turbo', help='large-v3-turbo(기본) / medium / small — 느리면 small')
    ap.add_argument('--threads', type=int, default=4)
    ap.add_argument('--once', action='store_true')
    ap.add_argument('--warmup', action='store_true')
    a = ap.parse_args()
    low_priority()
    if a.warmup:
        model(a.model, a.threads); log('모델 내려받기 끝'); return
    if not a.dir:
        log('--dir 로 녹음 폴더를 알려 주세요'); sys.exit(2)
    log('시작 — 폴더:', a.dir, '· 모델:', a.model)
    while True:
        try:
            if os.path.isdir(a.dir):
                for p in todo(a.dir):
                    run_one(p, a.model, a.threads)
            elif not a.once:
                time.sleep(60)                          # 외장하드가 빠져 있음 — 꽂히면 이어서
        except Exception as e:
            log('오류:', e)
        if a.once:
            break
        time.sleep(20)


if __name__ == '__main__':
    main()
