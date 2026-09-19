# 01 — ETW 캡처 확보

Type: task
Status: claimed
Blocked by: —

## Question

1010 전후의 선후 관계를 담은 ETW 원자료를 확보한다. 이것 없이는 02를 시작할 수 없다.

필요한 것:
- provider `Dxgkrnl_StatusChangeNotify` (0x100) + `Kernel-PnP` verbose
- SAM7B0C 1010 각 건의 -6초 ~ +2초 구간
- 최소 1회, 1010이 10건 이상 포함된 12분 캡처

09-18에 "구성해 뒀다"고 기록된 측정 장치가 실제로는 디스크에 없었다. 이번에는
파일·작업·프로세스의 실재를 확인한 뒤 기록한다(맵 Notes 상시규칙 2).

## Answer

**장치 복구 완료 — 09-19 16:41:08 무장.** 실재 확인까지 마쳤다.

| 항목 | 확인 방법 | 결과 |
|---|---|---|
| `C:\dev\PC\tools\g80sh-etw-capture.ps1` | `Test-Path` | 있음 |
| `C:\dev\PC\tools\g80sh-etw-auto.ps1` | `Test-Path` | 있음 |
| 작업 `G80SH ETW Auto` | `schtasks /create` rc=0, `/query` rc=0 | 등록됨 (SYSTEM / HIGHEST / onstart) |
| 상주 프로세스 | `Get-Process powershell` | **PID 8784, 세션 0** |
| `_evidence\auto.log` | 내용 확인 | `16:41:08 auto armed (captures=6 cool=40m)` |

provider는 09-18 실측(60초 525,469건 분석)으로 선별한 것을 그대로 썼다. 재선별하지 않는다.

```
Dxgkrnl_StatusChangeNotify  0x100   0/초    채택 — 상태 변경 시에만
Kernel-PnP  verbose                273/초   채택 — 220/222/808/1010
Kernel-Power (verbose)           8,020/초   제외 — CPU 유휴 전이만
DxgKrnl Base                     2,381/초   제외
DxgKrnl_Power                      465/초   제외 — GPU 전원 잡음
```

**바뀐 것 — 트리거를 `onstart`로.** 09-18판은 로그온 트리거였고,
`재부팅_기준선.md`가 "잠금화면에 머물면 실행되지 않는다"는 약점을 지적해 두었다.
`onstart` + `SYSTEM` 이면 로그인 없이도 뜬다.

**캡처 조건**: 증상은 화면이 꺼져 있을 때만 난다(아래 03 참조). 09-19 16:45:18에
`SC_MONITORPOWER`로 화면을 강제로 꺼서 관측 창을 열었다. 감시자가
"90초에 SAM7B0C 1010 2건 이상"을 보면 12분 캡처를 자동으로 돌린다.

산출물: `_evidence\g80sh-dxg-<tag>.etl` / `.csv` / `g80sh-dxg-agg-<tag>.txt`
