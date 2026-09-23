"""g80sh-conn-ordinal.py — 티켓 20. 재연결(Q3) 후 몇 번째 GPU 복귀(일괄 재감지)에서 Q1 이 나는가.

가설 A (18): 재연결 후 약 32초라는 **시간** 경계가 가른다.
가설 B (20): 재연결 후 **첫 번째** 복귀는 무사하고 두 번째부터 끊긴다 — 시간이 아니라 순번.
두 가설은 "첫 복귀가 늦게(>32초) 온 경우"와 "두 번째 복귀가 일찍(<32초) 온 경우"에서 갈린다.

  python tools\\g80sh-conn-ordinal.py <events.csv> [...]
"""
import collections
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
conn = __import__('g80sh-conn')

tab = collections.defaultdict(lambda: [0, 0])      # (순번) -> [Q1, 조용]
rows = []
for path in sys.argv[1:]:
    conn.CSV = Path(path)
    sys.argv = [sys.argv[0], path]
    for f, ev in sorted(conn.load().items()):
        bs = conn.batches(ev)
        q3 = None
        n = 0
        for i, b in enumerate(bs):
            if b['kind'] == 'Q3':
                q3, n = b['t'], 0
            elif b['kind'] == 'sweep' and q3:
                n += 1
                nxt = next((x for x in bs[i + 1:] if x['kind'] in ('Q1', 'sweep')), None)
                hit = bool(nxt and nxt['kind'] == 'Q1' and (nxt['t'] - b['t']).total_seconds() < 5)
                tab[n][0 if hit else 1] += 1
                rows.append((n, (b['t'] - q3).total_seconds(), hit))
print('순번  Q1  조용')
for k in sorted(tab):
    print(f'{k:3d}  {tab[k][0]:4d} {tab[k][1]:4d}')
print()
print('가르는 경우:')
print('  첫 복귀가 32초 넘어서 온 것 :', [(round(t, 1), 'Q1' if h else '조용') for n, t, h in rows if n == 1 and t > 32])
print('  두 번째 이후가 32초 전에 온 것:', [(n, round(t, 1), 'Q1' if h else '조용') for n, t, h in rows if n >= 2 and t < 32])
