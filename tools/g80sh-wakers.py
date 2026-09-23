"""g80sh-wakers.py — 티켓 19/20. xperf 덤프(구간)에서 GPU 를 D0 로 깨운 프로세스를 찾는다.

xperf -a dumper 출력의 ReadyThread/CSwitch 스택 중
  dxgkrnl!DpiRequestDevicePowerState ← AcquireCoreResourceShared (프로그램이 GPU 를 건드림)
를 찾아 그 이벤트의 프로세스 이름과 진입 경로(DxgkEscape / DisplayConfig 등)를 뽑는다.
PopFx 유휴 타이머 경로(DevicePowerNotRequired = D3 진입)는 제외한다.

  python tools\\g80sh-wakers.py <dump.txt> [...]
"""
import sys


def scan(path):
    lines = open(path, encoding='utf-8', errors='replace').read().split('\n')
    out = []
    for i, l in enumerate(lines):
        s = l.lstrip()
        if not (s.startswith('ReadyThread,') or s.startswith('CSwitch,')):
            continue
        st = []
        j = i + 1
        while j < len(lines) and lines[j].lstrip().startswith('Stack,'):
            q = lines[j].split(',')
            if len(q) > 5:
                st.append(q[5].strip())
            j += 1
        if not any('DpiRequestDevicePowerState' in x for x in st):
            continue
        if any('PowerNotRequired' in x for x in st):
            continue
        p = [x.strip() for x in s.split(',')]
        entry = next((x for x in st if x.startswith('dxgkrnl.sys!Dxgk') or 'NtGdiDdDDI' in x or 'NtUser' in x), '')
        out.append((int(p[1]), p[2], entry))
    return out


if __name__ == '__main__':
    for f in sys.argv[1:]:
        seen = set()
        for ts, proc, entry in scan(f):
            k = (proc, entry)
            if k in seen:
                continue
            seen.add(k)
            print(f'{f}\t{ts}\t{proc}\t{entry}')
