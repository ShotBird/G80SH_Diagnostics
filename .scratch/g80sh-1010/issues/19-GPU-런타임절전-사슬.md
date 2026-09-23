# 19 — "AMD 점검"의 정체: 화면이 꺼진 동안 GPU 가 D3 ↔ D0 를 오가고, 깨어날 때마다 포트를 재감지한다

Type: task
Status: resolved
Blocked by: 18

## Question

18 이 남긴 두 질문을 PC 에서 볼 수 있는 데까지 본다.
1. AMD 전 포트 점검은 왜 도는가
2. 점검 1.39초 뒤 "분리→연결" 보고는 인터럽트(= 모니터 HPD)에서 오는가, AMD 소프트웨어 판단에서 오는가

## 방법 (2026-09-24 02:38 ~ 02:41, 폭풍 진행 중)

xperf 150초: 커널 `PROC_THREAD+LOADER+CSWITCH+DISPATCHER+INTERRUPT+DPC`, 스택 `CSwitch+ReadyThread`,
DxgKrnl `0x301`(Base+StatusChange+**Power**, 스택) + Kernel-PnP. 1.79GB, 사이클 4회.
`tools\g80sh-deep-capture.ps1`. ETL 은 `_evidence\deeptest\`(로컬, git 제외).

핵심 기법: **ReadyThread 스택** — "누가 이 스레드를 깨웠나"가 호출 스택으로 남는다.
AMD 드라이버(`amdkmdag`)는 심볼이 없어도 **Windows 쪽 프레임(ntoskrnl/dxgkrnl)은 이름이 나온다.**

## Answer

### 1. AMD 점검 = GPU 런타임 절전(D3)에서 깨어나는 순간의 재감지 — 6/6

```
GPU D3 진입     D0 복귀         전 포트 점검(AMD)
02:38:30.884 → 31.042 (+0.16) → 31.110 (+68ms)
02:39:04.057 → 04.177 (+0.12) → 04.236 (+59ms)
02:39:14.467 → 14.524 (+0.06) → 14.585 (+61ms)
02:39:46.270 → 46.483 (+0.21) → 46.546 (+63ms)
02:39:57.919 → 58.300 (+0.38) → 58.363 (+63ms)
02:40:36.180 → 36.667 (+0.49) → 36.726 (+59ms)
```

(`DxgKrnl DdiSetPowerState` DevicePowerState 4 = D3, 1 = D0)

- **D3 진입은 Windows 런타임 전원 관리의 유휴 타이머**가 건다:
  `PopFxIdleTimeoutDpcRoutine → DxgkPowerRuntimeDevicePowerNotRequiredCallback → DpiRequestDevicePowerState`.
  화면이 모두 꺼져 GPU 가 한가해지면 Windows 가 GPU 를 D3 로 내린다.
- **D0 복귀는 GPU 를 건드린 프로그램이 건다** — 잠든 GPU 에 요청이 오면 dxgkrnl 이 먼저 깨운다
  (`AcquireCoreResourceShared → DpiRequestDevicePowerState → PoRequestPowerIrp`):

| 사이클 | 깨운 프로그램 | 경로 |
|---|---|---|
| 1, 5 | **HWiNFO** | AMD ADL 센서 조회(`atiadlxx.dll → DxgkEscape`) |
| 4 | **powershell.exe**(PID 1964, 로그온 시 관리자 권한 기동 — RemoteDisplaySwitch 감시자로 추정) | `DxgkDisplayConfigDeviceInfo` (화면 구성 조회) |
| 6 | **logioptionsplus_agent.exe**(Logitech Options+) | `DxgkDisplayConfigDeviceInfo` |
| 2, 3 | 창 밖 — 미확인 | |

그 밖에 이 PC 에서 GPU/화면을 주기적으로 조회하는 상주 프로그램: LibreHardwareMonitor·CaseDisplay, TRCC.

- 깨어난 AMD 드라이버는 약 60ms 뒤 **모든 포트를 다시 감지**해 보고한다(= 18 의 "일괄 점검").
  이때 G80SH 는 매번 "연결"이다.

### 2. 1.39초 뒤 보고는 AMD 의 타이머 구동 스레드가 올린다 — 인터럽트가 아니다

```
22.394511  AMD 시스템 스레드 1388:
           amdkmdag(시작 루틴) → … → dxgkrnl!DpIndicateConnectorChange → IoQueueWorkItemEx   ← Q1 발신
```

스레드 1388 을 깨운 것은 **전부 타이머 만료**(`KiTimerExpiration` / `KiTimer2Expiration`)였고,
인터럽트 DPC 가 깨운 적은 없다. D0 복귀 약 0.66초 뒤부터 깨어나, 22.04~22.37초에는
**2~3ms 제한 대기를 반복**(폴링 루프 모양)하다가 22.394초에 "분리→연결"을 올렸다.

실제 분리(Q2, 22.658초)는 **다른 AMD 시스템 스레드(1340)**가 다른 호출 경로로 올렸다.

→ **Q1 은 AMD 드라이버가 복귀 후 G80SH 를 확인하는 소프트웨어 루틴의 결론이다.**
그 루틴이 무엇을 읽다가 그런 결론을 냈는지(AUX 응답? HPD 레지스터 폴링?)는 심볼 없이 못 본다.

부수: Q1 작업자(12396)는 LibreHardwareMonitor 의 `DxgkEscape` 가 어댑터 잠금을 쥐고 있어
약 30ms 기다렸다. 17 에서 본 "Q1 직전 LibreHardwareMonitor"는 **잠금 경합**이었지 원인이 아니다.

### 3. 전체 사슬 (PC 쪽에서 본 것 전부)

```
화면 꺼짐 → 모든 출력 꺼짐 → GPU 유휴
 → Windows 런타임 PM 이 GPU 를 D3 로 (유휴 타이머)
 → 0.1~0.5초 안에 상주 프로그램(HWiNFO·화면 구성 조회 등)이 GPU 를 건드림 → D0 복귀
 → +60ms  AMD 가 전 포트 재감지 (G80SH "연결")
 → +0.66s AMD 타이머 스레드가 G80SH 확인 루프
 → +1.39s "분리→연결" 보고 (Q1)            ← G80SH 가 재연결 후 32~36초 넘었을 때만 (18)
 → +1.63s 실제 분리 (Q2) → +3.3s 재연결 (Q3)
```

**같은 D3↔D0 순환을 G50F 도 똑같이 겪는다** — 6회 재감지 모두 G50F "연결", 분리 보고 0건.

### 4. 이것이 바꾸는 것

- 16 의 "격자"와 18 의 "점검 간격 10~30초" = **GPU 가 D3 로 내려갔다가 깨워지는 간격**이다.
  깨우는 프로그램이 많을수록, GPU 가 자주 D3 로 갈수록 폭풍이 잦아진다.
  **09-22 부터 두 배가 된 발생률**을 이쪽(상주 프로그램 변화)에서 찾아볼 근거가 생겼다.
- **원인은 여전히 모니터다.** 같은 전원 순환에서 G50F 는 멀쩡하다. 다만 PC 쪽 **방아쇠의 빈도**는
  GPU 런타임 절전과 그것을 깨우는 프로그램들이 정한다.

## 다음 — 단일 변수 시험 후보 (사용자 결정)

상시규칙 1 에 따라 이것들은 **해결책이 아니라 사슬 검증용 시험**이다.

| 시험 | 기대 | 비고 |
|---|---|---|
| 화면 끈 동안 HWiNFO 만 종료 | D0 복귀 빈도 감소 → 발생률 감소 | 가장 싸다. 변수 하나 |
| + Logitech Options+ / LibreHardwareMonitor·CaseDisplay | 추가 감소 | 하나씩 |
| GPU 런타임 D3 자체를 막기 | 재감지 소멸 → 폭풍 소멸 예상 | AMD/Windows 에 사용자 설정이 있는지부터 조사 필요 |
