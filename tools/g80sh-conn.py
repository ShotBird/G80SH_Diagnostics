"""g80sh-conn.py — 티켓 18. AMD 연결 변경 보고와 폭풍 사이클의 시간 관계를 집계한다.

입력: _evidence\\conntest\\g80sh-conn-events.csv (tools\\g80sh-conn-extract.ps1)

DdiQueryConnectionChange 보고를 5ms 안에서 묶어 "배치"로 본다.
  일괄(sweep)  한 배치에 대상 8개 이상 — AMD 가 전 포트 상태를 다시 올린 것
  Q1           대상 260(G80SH) 이 8(분리) → 10(연결) 을 한 배치에
  Q2           260 이 8 만
  Q3           260 이 10 만
질문: Q1 은 항상 일괄 보고 약 1.4초 뒤에 오는가 (17 에서 표본 2).
      어떤 일괄 보고가 Q1 을 부르는가 — 재연결(Q3) 후 경과 시간으로 가른다.
"""
import collections
import csv
import statistics as st
from datetime import datetime
from pathlib import Path

CSV = Path(__file__).resolve().parent.parent / '_evidence' / 'conntest' / 'g80sh-conn-events.csv'
G80 = '260'


def load():
    byf = collections.defaultdict(list)
    for r in csv.DictReader(open(CSV, encoding='utf-8-sig')):
        r['t'] = datetime.strptime(r['time'], '%Y-%m-%d %H:%M:%S.%f')
        byf[r['file']].append(r)
    return byf


def batches(ev):
    out, cur = [], None
    for r in ev:
        if r['id'] != '1099' or r['c'] == '0':
            continue
        if cur and (r['t'] - cur['t1']).total_seconds() <= 0.005:
            cur['items'].append((r['a'], r['b']))
            cur['t1'] = r['t']
        else:
            cur = {'t': r['t'], 't1': r['t'], 'items': [(r['a'], r['b'])]}
            out.append(cur)
    for b in out:
        g = [s for tid, s in b['items'] if tid == G80]
        if len(b['items']) >= 8:
            b['kind'] = 'sweep'
        elif g == ['8', '10']:
            b['kind'] = 'Q1'
        elif g == ['8']:
            b['kind'] = 'Q2'
        elif g == ['10']:
            b['kind'] = 'Q3'
        else:
            b['kind'] = 'other:' + ' '.join(f'{t}={s}' for t, s in b['items'])
        b['g80'] = g
    return out


def main():
    byf = load()
    q1_after_sweep, sweep_gap = [], []
    fired, idle = [], []          # 일괄 보고의 Q3 후 경과 시간: Q1 을 불렀나 / 안 불렀나
    kinds = collections.Counter()
    sweep_g80 = collections.Counter()
    for f, ev in sorted(byf.items()):
        bs = batches(ev)
        print(f'--- {f}  배치 {len(bs)}')
        prev_sweep = prev_q3 = None
        for i, b in enumerate(bs):
            kinds[b['kind'].split(':')[0]] += 1
            if b['kind'] == 'sweep':
                sweep_g80[tuple(b['g80'])] += 1
                if prev_sweep:
                    sweep_gap.append((b['t'] - prev_sweep).total_seconds())
                prev_sweep = b['t']
                nxt = next((x for x in bs[i + 1:] if x['kind'] in ('Q1', 'sweep')), None)
                hit = bool(nxt and nxt['kind'] == 'Q1' and (nxt['t'] - b['t']).total_seconds() < 5)
                if prev_q3:
                    (fired if hit else idle).append((b['t'] - prev_q3).total_seconds())
                print(f"  일괄 {b['t'].strftime('%H:%M:%S.%f')[:-3]}  Q3 후 "
                      f"{'   -  ' if not prev_q3 else f'{(b[chr(116)] - prev_q3).total_seconds():6.1f}s'}"
                      f"  → {'Q1' if hit else '조용'}")
            if b['kind'] == 'Q1':
                d = (b['t'] - prev_sweep).total_seconds() if prev_sweep else None
                q1_after_sweep.append(d)
            if b['kind'] == 'Q3':
                prev_q3 = b['t']
    print()
    print('배치 종류:', dict(kinds))
    print('일괄 보고 안의 G80SH 상태:', dict(sweep_g80))
    ok = [d for d in q1_after_sweep if d is not None]
    if ok:
        print(f'Q1 ← 직전 일괄 보고: n={len(ok)} (직전 일괄 없음 {len(q1_after_sweep) - len(ok)}) '
              f'min={min(ok):.3f} med={st.median(ok):.3f} max={max(ok):.3f}')
    print(f'일괄 보고 → 5초 안에 Q1: {len(fired)}/{len(fired) + len(idle)} (Q3 이후 것만)')
    if fired:
        print(f"  Q1 을 부른 일괄의 Q3 후 경과:   {' '.join(f'{x:.1f}' for x in sorted(fired))}")
    if idle:
        print(f"  조용했던 일괄의 Q3 후 경과:     {' '.join(f'{x:.1f}' for x in sorted(idle))}")
    if sweep_gap:
        print(f'일괄 보고 간격: n={len(sweep_gap)} med={st.median(sweep_gap):.2f}')


if __name__ == '__main__':
    main()
