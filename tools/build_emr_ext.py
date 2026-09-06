# -*- coding: utf-8 -*-
"""EMR(비트플러스) ↔ 동선관리 크롬 확장 빌드
협력 지점 확장을 기반으로 주소만 우리 포털로 바꿔 public/dongseon/emr-ext.zip 생성.
실행: python tools/build_emr_ext.py <원본 확장 폴더>
"""
import os, sys, io, zipfile, re

SRC = sys.argv[1] if len(sys.argv) > 1 else r'C:\Users\user\AppData\Local\Temp\claude\c--Users-user-Desktop-JS-PACS---\6c828a89-d98f-4eea-bb95-a43d31886acd\scratchpad\emr-ext'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ZIP = os.path.join(ROOT, 'public', 'dongseon', 'emr-ext.zip')

OLD_ORIGIN = 'https://bonafidekcs-path.pages.dev'
NEW_ORIGIN = 'https://bonafide-portal.seoulgijibae.workers.dev'
NEW_BOARD = NEW_ORIGIN + '/dongseon/'

def read(name):
    with open(os.path.join(SRC, name), encoding='utf-8') as f:
        return f.read()

files = {}

# manifest: 우리 포털 도메인, 동선 경로만 매칭
m = read('manifest.json')
m = m.replace('"name": "EMR↔동선 통합 연동"', '"name": "EMR↔동선 연동 (반듯한정형외과)"')
m = m.replace('"https://bonafidekcs-path.pages.dev/*"', '"%s/dongseon/*"' % NEW_ORIGIN)
files['manifest.json'] = m

# emr.js: 기본 동선 주소
e = read('emr.js')
e = e.replace(OLD_ORIGIN + '/', NEW_BOARD)
files['emr.js'] = e

# bg.js: 기본 주소 + 탭 탐색을 동선 경로(/dongseon/*)로 한정(재고관리 탭과 혼동 방지)
b = read('bg.js')
b = b.replace("'" + OLD_ORIGIN + "/'", "'" + NEW_BOARD + "'")
b = b.replace("origin='" + OLD_ORIGIN + "'", "origin='" + NEW_ORIGIN + "'")
b = b.replace("chrome.tabs.query({url:origin+'/*'}", "chrome.tabs.query({url:origin+'/dongseon/*'}")
files['bg.js'] = b

# options.js / options.html: 기본값·placeholder
o = read('options.js').replace(OLD_ORIGIN + '/', NEW_BOARD)
files['options.js'] = o
h = read('options.html').replace(OLD_ORIGIN + '/', NEW_BOARD)
files['options.html'] = h

files['board.js'] = read('board.js')

# 설치안내: 파일명이 zip 안에서 깨져 있을 수 있어 .txt 하나를 찾아 읽음
txt_name = [n for n in os.listdir(SRC) if n.lower().endswith('.txt')][0]
g = read(txt_name)
g = g.replace('동선(경로)은 접수자가 그 창에서 직접 선택.', '접수자는 [저장]만 누르면 됩니다(기본 3층 대기실에서 시작).')
g = g.replace('동선을 선택하고 [저장]을 누르세요.', '[저장]을 누르세요 (환자는 3층 대기실에 등록됩니다).')
g = g.replace('EMR ↔ 동선 통합 연동 크롬 확장 — 설치 안내', 'EMR ↔ 동선 연동 크롬 확장 — 설치 안내 (반듯한정형외과)')
g += '\n■ 동선관리 주소\n  ' + NEW_BOARD + '\n  (확장 설정의 "동선관리 주소"가 위 주소인지 확인)\n'
files['설치안내.txt'] = g

os.makedirs(os.path.dirname(OUT_ZIP), exist_ok=True)
with zipfile.ZipFile(OUT_ZIP, 'w', zipfile.ZIP_DEFLATED) as z:
    for name, content in files.items():
        info = zipfile.ZipInfo('EMR연동_확장/' + name)
        info.flag_bits |= 0x800   # UTF-8 파일명
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, content.encode('utf-8'))

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
print('OK ->', OUT_ZIP, os.path.getsize(OUT_ZIP), 'bytes')
for name in files:
    left = files[name].count(OLD_ORIGIN)
    print(('  ' if left == 0 else '  !! ') + name, '(eski manzil qoldi: %d)' % left)
