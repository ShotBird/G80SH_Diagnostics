# 04 — AMD EDID 에뮬레이션이 실재하는가

Type: research
Status: resolved
Blocked by: —

## Question

보고서 9-4는 AMD 드라이버의 EDID 에뮬레이션을 **"유일한 소프트웨어 근원 후보"**로
지목했지만 실재 여부를 확인하지 않았다. 근원개선 후보 ②의 전제다.

확인할 것:
1. AMD 드라이버에 모니터 EDID를 고정·에뮬레이트하는 기능이 실제로 있는가.
   (소비자용 Adrenalin / Radeon Pro / `AMD EDID Emulator` 계열 도구 / 레지스트리)
2. 있다면 **이 PC의 GPU와 드라이버 버전에서 쓸 수 있는가.** Pro 전용이면 ②는 무너진다.
3. 에뮬레이트한 EDID가 **장치 열거 시점**에 적용되는가, 아니면 `EDID_OVERRIDE`처럼
   이미 열거된 장치에만 적용되는가. 후자면 9-1과 같은 이유로 근본 차단이 불가하다.
   — 이 3번이 ②의 성패를 가른다.
4. DSC/DP 1.4 링크에서 EDID 에뮬레이션이 동작하는지에 별도 제약이 있는가.

1차 출처 위주로 확인한다: AMD 공식 문서, 드라이버 릴리스 노트, Microsoft 디스플레이
드라이버 문서(EDID override / monitor INF). 포럼 글은 1차 출처로 치지 않는다.

먼저 이 PC의 GPU 모델과 드라이버 버전을 확인하고 시작할 것.

## Answer

**후보 ②는 무너지지 않는다.** 전문: `_evidence\research_AMD_EDID_에뮬레이션.md`

### 1. 기능은 실재한다

AMD **EDID Emulation / EDID Management**. ADL SDK의 `ADL2_Adapter_ConnectionData_Set` +
`ADL2_Adapter_EmulationMode_Set`, UI는 AMD Software → Displays → EDID Emulation.
AMD 공식 SDK 문서·헤더(`adl_defines.h`)로 확인.

### 2. 이 PC에서 쓸 수 있다 — 실측

`atiadlxx.dll`을 직접 호출해 읽기 전용으로 확인:

```
adapter idx=5  AMD Radeon RX 9070 XT
    ADL2_Adapter_EDIDManagement_Caps -> rc=0  supported=1     ← 소비자용 드라이버에서 지원
adapter idx=0  AMD Radeon(TM) Graphics (iGPU)
    ADL2_Adapter_EDIDManagement_Caps -> rc=0  supported=0
ADL2_Workstation_GlobalEDIDPersistence_Get -> rc=-8 (NOT_SUPPORTED)   ← Pro 전용은 이쪽
```

Pro 전용인 것은 *Global EDID Persistence*이지 EDID Management가 아니다. 혼동하지 말 것.
설치된 `RadeonSoftware.exe`에 `EDID.qml` / `EDIDEmulate.qml`과
"Manage EDID emulation for display connections…" 문자열이 실물로 들어 있다.

### 3. 【핵심】 `EDID_OVERRIDE`보다 상류다

| | `EDID_OVERRIDE` | AMD EDID Emulation |
|---|---|---|
| 저장 위치 | monitor devnode의 hardware key | display adapter class key (`DAL2_DATA__2_0\DisplayPath_0\EDID_2D4C_7B0C`) |
| 읽는 주체 | **Monitor.sys** (monitor PDO가 생긴 뒤) | **AMD display miniport(DAL)** |
| 시점 | 열거 **후** | miniport가 `DxgkDdiQueryDeviceDescriptor`에 EDID를 돌려주는 **그 자리** |
| hardware ID 영향 | **없음** | **원리상 있음** |

Windows는 열거 시 miniport가 준 EDID block 0에서 PnP hardware ID / instance ID를 뽑는다(WDK).
따라서 AMD 에뮬레이션은 ID가 정해지는 지점보다 위에 있다.
→ **보고서 9-1의 `EDID_OVERRIDE` "근본 차단 불가" 결론은 그대로 맞고, ②는 다른 계층이다.**

### 4. 미확인 — 이 한 점이 성패를 가른다

AMD 1차 문서 어디에도 "에뮬레이트된 EDID가 OS의 monitor PnP hardware ID를 결정한다"고
**명시한 문장은 없다.** 특히 `ADL_EMUL_MODE_ON_DISCONNECTED`가 **child status(HPD)까지
connected로 고정**하는지가 문서화돼 있지 않다.

- HPD까지 고정한다면 → 재열거 자체가 사라진다. 근원개선 성립.
- EDID 내용만 대체한다면 → HPD가 끊기는 순간 `EDID_OVERRIDE`와 같은 이유로 무력.

이 PC에서 직접 확인해야 한다. → **06 티켓**

### 5. 경고 — AMD가 스스로 적어둔 알려진 이슈

> "Display blank out observed after waking system from **MSB** state with **EDID emulation** on…
> Workaround: Add Regkey `DalEdidReadDeferralTime` with value 1."
> "Very sporadically system not entering MSB state with EDID Emulation"

출처: AMD Embedded Q321 Windows Catalyst Driver Release Notes (2021-10).
**MSB = Modern Standby.** 이 케이스가 정확히 "화면 절전" 시나리오라 정면으로 겹친다.
06을 설계할 때 반드시 감안한다.

### 6. 부수 제약 — DSC는 문제가 아니다

DSC 캐퍼빌리티는 EDID가 아니라 DPCD `0x060~0x06F`에서 읽힌다.
이 모니터 EDID는 384바이트이고 ADL 에뮬레이션 버퍼는 1024바이트라 확장 블록까지 손실 없이
담긴다.

### 7. Windows 측 정식 대안은 없다

monitor INF도 `EDID_OVERRIDE`도 전부 hardware key 계층이고, IDD는 가상 모니터 추가일 뿐이다.
`HpdAwarenessAlwaysConnected`는 miniport만 선언할 수 있다.

### 8. 부수 발견 — 기존 기전 가설의 무게중심이 틀렸을 수 있다

최근 3일 1010 분포:

```
SAM7B0C         1495
Default_Monitor  413      ← EDID 읽기 실패/미확정
SAM79DF           48
```

보고서 8항이 기전으로 지목한 대기 EDID(`SAM7B0B` / `SAM7B11`)는 09-08 이후 전체
4,098건 중 각각 **2건 / 1건**뿐이다. 실제로 지배적인 패턴은 **EDID를 아예 못 읽는 것**이다.
(단, 7B0B/7B11은 CCD API 조회에서 관측된 값이고 1010 이벤트와 같은 축이 아니다.
같은 축으로 놓고 비교하지 말 것.)

이는 오히려 ②에 유리한 정황이다 — 에뮬레이션이 켜져 있으면 EDID 읽기 실패 구간에서도
드라이버가 고정 EDID를 내주므로 `Default_Monitor` 폴백이 생길 이유가 없다.
