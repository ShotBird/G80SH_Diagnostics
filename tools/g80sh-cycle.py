"""g80sh-cycle.py — 폭풍 사이클을 GPU 버스 조회 단위로 쪼개 집계한다 (티켓 16).

입력: _evidence\\g80sh-cycle-events.csv (tools\\g80sh-cycle-extract.ps1 로 생성)

사이클 = GPU(PCI\\VEN_1002&DEV_7550) 버스 관계 조회 3회
  Q1  SAM7B0C 제거 (+ Default_Monitor 추가)   ← 직전 5초에 10011 없음 = 링크 이벤트 없이 시작
  Q2  Default_Monitor 제거                   ← 10011 Type 9/10 무더기 뒤
  Q3  SAM7B0C 재추가                          ← Q2 뒤 약 3.57초
수명 = Q3(추가) -> 다음 Q1(제거).  이 값의 분포가 "45~48초 타이머"의 정체다.

  python tools\\g80sh-cycle.py            요약
  python tools\\g80sh-cycle.py <etl이름>   그 캡처의 조회 목록
"""
import collections
import csv
import math
import random
import statistics as st
import sys
from datetime import datetime
from pathlib import Path

BS = chr(92)
CSV = Path(__file__).resolve().parent.parent / '_evidence' / 'g80sh-cycle-events.csv'
GPU = 'PCI' + BS + 'VEN_1002&DEV_7550'


def load():
    rows = list(csv.DictReader(open(CSV, encoding='utf-8-sig')))
    byf = collections.defaultdict(list)
    for r in rows:
        r['t'] = datetime.strptime(r['time'], '%Y-%m-%d %H:%M:%S.%f')
        byf[r['file']].append(r)
    return byf


def short(d):
    p = d.split(BS)
    return p[1] if len(p) > 1 else d


def queries(ev):
    out, cur = [], None
    for r in ev:
        if r['id'] == '220' and r['a'].startswith(GPU):
            cur = {'t': r['t'], 'rm': [], 'add': [], 'pre': collections.Counter()}
            out.append(cur)
        elif cur and r['id'] == '1010':
            cur['rm'].append(short(r['a']))
        elif cur and r['id'] == '807' and 'monitor' in r['a']:
            cur['add'].append(short(r['b']))
    for q in out:
        for r in ev:
            if r['id'] == '10011' and 0 < (q['t'] - r['t']).total_seconds() <= 5:
                q['pre'][r['a']] += 1
    return out


def cycles(byf):
    """(file, add_time, lifetime, q1, 10011-in-quiet) per SAM7B0C removal."""
    res = []
    for f, ev in sorted(byf.items()):
        if 'baseline' in f:
            continue
        qs = queries(ev)
        for i, q in enumerate(qs):
            if 'SAM7B0C' not in q['rm']:
                continue
            for j in range(i - 1, -1, -1):
                if 'SAM7B0C' in qs[j]['add']:
                    a = qs[j]['t']
                    L = (q['t'] - a).total_seconds()
                    if L < 300:
                        late = [r for r in ev if r['id'] == '10011' and a < r['t'] < q['t']
                                and (r['t'] - a).total_seconds() > 3]
                        res.append((f, a, L, q, qs[i + 1:i + 3], late))
                    break
    return res


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))]


def summary(byf):
    cy = cycles(byf)
    life = [c[2] for c in cy]
    q1pre = collections.Counter(sum(c[3]['pre'].values()) > 0 for c in cy)
    q12 = [(c[4][0]['t'] - c[3]['t']).total_seconds() for c in cy if c[4]]
    q23 = [(c[4][1]['t'] - c[4][0]['t']).total_seconds() for c in cy
           if len(c[4]) > 1 and 'SAM7B0C' in c[4][1]['add']]
    late = sum(1 for c in cy if c[5])
    print(f"사이클 {len(cy)}건 (캡처 {len(byf)}개)")
    print(f"Q1 직전 5초에 10011 있음/없음: {q1pre[True]}/{q1pre[False]}")
    print(f"추가 후 3초~제거 사이에 10011 이 있는 사이클: {late}/{len(cy)}")
    for name, xs in (('수명 Q3->Q1', life), ('Q1->Q2', q12), ('Q2->Q3', q23)):
        print(f"  {name:12s} n={len(xs):3d} min={min(xs):7.3f} p10={pct(xs, .1):7.3f} "
              f"med={st.median(xs):7.3f} p90={pct(xs, .9):7.3f} max={max(xs):7.3f}")
    print('수명 0.5초 히스토그램 (<62s):')
    h = collections.Counter(round(x * 2) / 2 for x in life if x < 62)
    for k in sorted(h):
        print(f"  {k:5.1f} {'#' * h[k]}")
    # 격자 검정: 주 봉우리(36.8s)를 뺀 꼬리가 36.8 + k*P 에 몰리는가
    tail = [x for x in life if 39.5 < x < 62]
    if len(tail) >= 10:
        def R(xs, P):
            return sum(math.cos(2 * math.pi * (x - 36.8) / P) for x in xs) / len(xs)
        print(f"격자 검정 (꼬리 n={len(tail)}, 기준 36.8s):")
        for P in (8.0, 8.5, 9.0, 9.5, 10.0):
            print(f"  P={P:4.1f}s  정렬도={R(tail, P):.3f}")
        random.seed(1)
        obs = R(tail, 9.0)
        sims = [R([random.uniform(39.5, 62) for _ in tail], 9.0) for _ in range(20000)]
        print(f"  P=9.0 균등분포 대조 p = {sum(s >= obs for s in sims) / len(sims):.5f}")
    print('일자별 수명 중앙값:')
    bd = collections.defaultdict(list)
    for c in cy:
        bd[c[0][10:14]].append(c[2])
    for d, xs in sorted(bd.items()):
        print(f"  {d}  n={len(xs):3d}  med={st.median(xs):5.1f}  min={min(xs):5.1f}")


if __name__ == '__main__':
    byf = load()
    if len(sys.argv) > 1:
        prev = None
        for q in queries(byf[sys.argv[1]]):
            d = (q['t'] - prev).total_seconds() if prev else 0
            prev = q['t']
            print(q['t'].strftime('%H:%M:%S.%f')[:-3], f"{d:8.3f}", '-', q['rm'], '+', q['add'], dict(q['pre']))
    else:
        summary(byf)
