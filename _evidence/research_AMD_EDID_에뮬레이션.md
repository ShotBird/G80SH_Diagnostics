# AMD 드라이버 EDID 에뮬레이션 조사 — G80SH PnP 재열거 차단 후보 검증

조사일: 2026-09-19
대상 PC: Windows 11 Pro 10.0.26200 / AMD Radeon RX 9070 XT (`PCI\VEN_1002&DEV_7550`, 드라이버 `32.0.31041.1004`) / DisplayPort 1.4 + DSC
조사 방법: 1차 출처(Microsoft Learn·WDK 문서, AMD 공식 SDK/릴리스 노트 PDF) + **이 PC의 설치된 AMD 드라이버 실측**

---

## 0. 결론 요약

| # | 질문 | 답 | 확신도 |
|---|---|---|---|
| 1 | AMD 드라이버에 EDID 고정/에뮬레이트 기능이 실제로 있는가 | **있다.** "EDID Emulation" (= EDID Management). ADL SDK의 `ADL2_Adapter_ConnectionData_Set` + `ADL2_Adapter_EmulationMode_Set`, UI는 AMD Software → Displays → EDID Emulation | 1차 출처 확인 |
| 2 | RX 9070 XT + Adrenalin(소비자용)에서 쓸 수 있는가 | **쓸 수 있다.** 이 PC에서 `ADL2_Adapter_EDIDManagement_Caps` → **supported = 1**. UI 코드도 설치된 `RadeonSoftware.exe`에 포함됨. (Pro 전용인 것은 *Global EDID Persistence* 쪽이고, 그건 이 PC에서 `-8 NOT_SUPPORTED`) | 로컬 실측 |
| 3 | **에뮬레이트된 EDID가 장치 열거 시점에 적용되는가** | **적용된다고 보는 것이 타당하다 — `EDID_OVERRIDE`와 계층이 다르다.** 단, "AMD가 그렇게 명시한 문장"은 못 찾았다(미확인). 근거는 4장 참조 | 강한 정황 추론 |
| 4 | DP 1.4 + DSC 링크에서 별도 제약 | DSC 캐퍼빌리티는 EDID가 아니라 **DPCD 0x060~0x06F**에서 읽으므로 EDID 에뮬레이션과 직교. 실질 제약은 ADL EDID 버퍼 **1024바이트**(이 모니터 EDID는 384바이트라 여유 있음)와, AMD가 공식 릴리스 노트에 적어 둔 **Modern Standby 복귀 시 blank-out 알려진 이슈** | 부분 확인 |
| 5 | Windows 측 열거 시점 고정 수단 | **없다.** monitor INF도 `EDID_OVERRIDE`도 전부 "이미 만들어진 monitor devnode의 hardware key"에 작용한다. IDD(가상 모니터)는 별개 장치를 추가하는 것이지 물리 모니터를 고정하는 수단이 아님 | 1차 출처 확인 |

**한 줄로:** `EDID_OVERRIDE`는 "이미 만들어진 monitor PDO"에 붙는 반면, AMD EDID Emulation은 **display miniport(DAL) 안**에서 EDID를 바꿔치기한다. Windows는 monitor PDO의 PnP hardware ID를 **miniport가 돌려준 EDID block 0**에서 뽑으므로, AMD 에뮬레이션은 원리상 열거 시점 상류에 있다. 따라서 `EDID_OVERRIDE`를 무너뜨린 논리가 이 후보에는 그대로 적용되지 않는다.

---

## 1. Windows가 모니터를 열거하는 정확한 순서 (전제 검증)

Microsoft WDK 문서 `Enumerating Child Devices of a Display Adapter`의 5단계, 원문 그대로:

> **Note:** During initialization, the display port driver calls *DxgkDdiQueryDeviceDescriptor* for each monitor to obtain the first 128-byte block of the monitor's EDID. **That gives the display port driver what it needs at initialization time: PnP hardware ID, instance ID, compatible IDs, and device text.** At a later time, the monitor class function driver (Monitor.sys) calls *DxgkDdiQueryDeviceDescriptor* for each monitor to obtain the first 128-byte EDID block and additional 128-byte EDID extension blocks.

- 출처: <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/enumerating-child-devices-of-a-display-adapter>
- 출처(원문 md): <https://github.com/MicrosoftDocs/windows-driver-docs/blob/staging/windows-driver-docs-pr/display/enumerating-child-devices-of-a-display-adapter.md>

같은 문서 4단계: PDO는 `DxgkDdiQueryChildStatus`가 "연결됨"을 보고했을 때(또는 `HpdAwarenessAlwaysConnected`일 때) 생성된다.

`DxgkDdiQueryDeviceDescriptor` 문서도 같은 내용을 반복한다:

> For a child device that has a connected monitor, **the display port driver calls DxgkDdiQueryDeviceDescriptor during initialization to obtain the first 128-byte block of a monitor's EDID.** Later the monitor class function driver (Monitor.sys) calls DxgkDdiQueryDeviceDescriptor to obtain selected portions ... of that same monitor's EDID.

- 출처: <https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/dispmprt/nc-dispmprt-dxgkddi_query_device_descriptor>

그리고 monitor INF 문서가 hardware ID의 출처를 못 박는다:

> Hardware identification -- for example, the expression **Monitor\MON12AB** combines the device class (Monitor) and **the device identification (MON12AB) as it appears in the device's EDID**.

- 출처: <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/monitor-inf-file-sections> (아카이브 문서)

**따라서 인과 사슬은 이렇다:**
```
[모니터/싱크] --EDID--> [AMD display miniport = DAL] --DxgkDdiQueryDeviceDescriptor--> [dxgkrnl/display port driver]
                                                                                        └→ PnP hardware ID = MONITOR\SAM7B0C 결정
                                                                                        └→ monitor PDO / devnode 생성
                                                                                            └→ hardware key 생성
                                                                                                └→ [EDID_OVERRIDE]는 여기서야 읽힘 (Monitor.sys 초기화 시)
```

`edidProductCodeId`(CCD API)도 같은 EDID에서 온다:

> `edidProductCodeId` — The product code from the monitor EDID. This member is set only when the **edidIdsValid** bit-field is set in the **flags** member.

- 출처: <https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-displayconfig_target_device_name>

---

## 2. `EDID_OVERRIDE` "근본 차단 불가" 결론 재검증 → **기존 결론이 맞다**

Microsoft 문서 원문:

> 2. Device installation reads the updated EDID information from the INF file and **stores the information as values under the hardware key of the monitor device**. Each EDID override is stored under a separate key under the hardware key of the device.
> 3. **The monitor driver checks the registry during initialization** and uses any EDID information stored there instead of the corresponding information on EEPROM.

- 출처: <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/overriding-monitor-edids>

즉 `EDID_OVERRIDE`는
1. **monitor device의 hardware key**(= `HKLM\SYSTEM\CurrentControlSet\Enum\DISPLAY\SAM7B0C\<inst>\Device Parameters`)가 이미 존재해야 하고,
2. **monitor 드라이버(Monitor.sys)** 초기화 때 읽히며,
3. INF의 매칭은 `MONITOR\SAM7B0C` 같은 hardware ID로 이뤄진다.

대기 EDID가 `0x7B0B`/`0x7B11`을 내면 hardware ID가 `MONITOR\SAM7B0B`가 되어 **다른 devnode**가 되고, 기존 `SAM7B0C` 키의 override는 애초에 매칭되지 않는다. 또 override가 읽히는 시점은 PDO 생성 **이후**라 PDO 생성 자체를 막을 수 없다.
→ **"override는 이미 열거된 장치 인스턴스에만 적용된다"는 기존 결론은 1차 출처로 확인됨.**

참고(이 PC 실측): 현재 monitor devnode 6개 전부 `EDID_OVERRIDE` 없음.

---

## 3. AMD의 EDID 에뮬레이션 기능 — 무엇이 어디에 있는가

### 3.1 기능 이름과 API (AMD 공식 SDK = 1차 출처)

AMD Display Library(ADL) SDK의 **"EDID Management APIs"** 그룹.

| 함수 | AMD 공식 설명(원문) |
|---|---|
| `ADL2_Adapter_EDIDManagement_Caps` | "Function to retrieve EDID management feature support. ... If the specified adapter supports EDID Management then returns ADL_TRUE else ADL_FALSE" |
| `ADL2_Adapter_ConnectionData_Set` | "**Function to set the emulation data to on specified connector.** ... `ConnectionData` contains connection data including the EDID data" |
| `ADL2_Adapter_ConnectionData_Get` | "Function to gets the emulation data on specified connector." (`iQueryType` = REAL / EMULATED / CURRENT) |
| `ADL2_Adapter_ConnectionData_Remove` | "Function to remove emulation on specified connector." |
| `ADL2_Adapter_EmulationMode_Set` | "**Function to sets the emulation mode of given connector.** This function set the emulation mode **to the driver**" |
| `ADL2_Adapter_ConnectionState_Get` | "Function to get the current emulation state of a given connector." |
| `ADL2_Workstation_GlobalEDIDPersistence_Get/Set` | "Function to get/set the EDID Persistence state of the system." |

- 출처: <https://gpuopen-librariesandsdks.github.io/adl/group__EDIDAPI.html>
- SDK 소스: <https://github.com/GPUOpen-LibrariesAndSDKs/display-library>

### 3.2 에뮬레이션 모드 정의 (`include/adl_defines.h`, AMD 공식 헤더)

```c
/// \defgroup define_emulation_mode
#define ADL_EMUL_MODE_OFF              0   // Indicates if no emulation is used
#define ADL_EMUL_MODE_ON_CONNECTED     1   // Indicates if emulation is used when display connected
#define ADL_EMUL_MODE_ON_DISCONNECTED  2   // Indicates if emulation is used when display dis connected
#define ADL_EMUL_MODE_ALWAYS           3   // Indicates if emulation is used always

/// \defgroup define_emulation_status
#define ADL_EMUL_STATUS_REAL_DEVICE_CONNECTED   0x1
#define ADL_EMUL_STATUS_EMULATED_DEVICE_PRESENT 0x2
#define ADL_EMUL_STATUS_EMULATED_DEVICE_USED    0x4
#define ADL_EMUL_STATUS_LAST_ACTIVE_DEVICE_USED 0x8
// "In case when last active real/emulated device used (when persistence is enabled
//  but no emulation enforced then persistence will use last connected/emulated device)."

/// \defgroup define_persistence_state
#define ADL_EDID_PERSISTANCE_DISABLED 0
#define ADL_EDID_PERSISTANCE_ENABLED  1
```

- 출처: <https://raw.githubusercontent.com/GPUOpen-LibrariesAndSDKs/display-library/master/include/adl_defines.h>

`ADL_EMUL_MODE_ON_DISCONNECTED`("디스플레이가 끊겼을 때 에뮬레이션 사용")와 `ADL_EMUL_MODE_ALWAYS`("항상 에뮬레이션 사용")가 이 케이스의 핵심이다.

### 3.3 UI 위치

- AMD 공식 릴리스 노트(PDF): "**EDID management has moved from Radeon Pro Advanced Settings to Radeon Pro Settings, and can be located under Display tab.**"
  - 출처: <https://drivers.amd.com/relnotes/amd-radeon-pro-software-for-enterprise-20.Q2.1.pdf> (동일 문장이 20.Q3/20.Q4 릴리스 노트에도 있음: <https://drivers.amd.com/relnotes/amd-radeon-pro-software-for-enterprise-20.Q3.pdf>)
- AMD 공식 릴리스 노트(PDF, 23.Q1) 알려진 이슈: "Unable to navigate to **EDID tab on AMD Software: PRO Edition**"
  - 출처: <https://drivers.amd.com/relnotes/amd-software-pro-edition-23.Q1.pdf>

### 3.4 이 PC에 설치된 AMD Software 바이너리 실측 (2차 확인이 아니라 실물 확인)

`C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe` 안에 EDID Emulation UI가 **그대로 들어있다**:

```
Displays / EDID Emulation / "Manage EDID emulation for display connections..."
qrc:/Qml/RSX/Settings/EDID.qml , EDIDMain.qml , EDIDEmulate.qml
ADL2_Adapter_EDIDManagement_Caps , ADL2_Display_EdidData_Get
ImportEdidData / ExportEdidData / ApplyEmulationFile
"EDID Emulation: Set emulation: adapterIndex: %d connectorIndex: %d, emulationMode: %d"
"EDID Emulation: Applied / Removed / Connection type not supported"
"EDID UI support set to true (called from ConnectModel)" / "... set to false"
"EdidSupported_ is %d" , "Initialize (EDID NOT SUPPORTED)"
"EDID Emulation Source Selection" , "gaming/edid wizard"
```

레지스트리 게이팅 값도 존재:
`HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000\edid_ui_component_NA = false`
(0000 = RX 9070 XT). **다만 이 `_NA` 플래그의 정확한 의미(“Not Available”의 true/false 방향)는 AMD 문서에 없다 — 미확인.**

---

## 4. 【핵심】 열거 시점 적용 여부

### 4.1 계층 비교

| | `EDID_OVERRIDE` | AMD EDID Emulation |
|---|---|---|
| 저장 위치 | `Enum\DISPLAY\<PnPID>\<inst>\Device Parameters\EDID_OVERRIDE` (**monitor devnode의 hardware key**) | GPU 드라이버 쪽. 이 PC의 DAL 저장 경로 실측: `...\Class\{4d36e968-...}\0000\DAL2_DATA__2_0\DisplayPath_0\EDID_2D4C_7B0C` (**display adapter class key**) |
| 읽는 주체 | **Monitor.sys** (monitor class function driver), 초기화 시 | **AMD display miniport(DAL)** — `EmulationMode_Set` 설명 그대로 "set the emulation mode **to the driver**" |
| 시점 | monitor PDO가 **이미 만들어진 뒤** | miniport가 `DxgkDdiQueryDeviceDescriptor`에 EDID를 돌려주는 **그 자리** |
| hardware ID에 영향 | **없음** (ID는 이미 확정됨) | **원리상 있음** (ID는 miniport가 준 EDID block 0에서 파생) |

### 4.2 판단

1장(Microsoft) + 3장(AMD)을 합치면, AMD 에뮬레이션은 Windows가 hardware ID를 뽑아내는 지점보다 **상류**에 있다. `ADL_EMUL_MODE_ON_DISCONNECTED`의 존재 자체가 "실제 싱크가 사라져도 드라이버가 디스플레이를 계속 들고 있는다"는 뜻이고, 그건 miniport가 child status를 connected로, descriptor를 에뮬레이트된 EDID로 계속 보고해야만 성립한다.

AMD 공식 릴리스 노트의 다음 두 줄도 이 기능이 **커널 디스플레이 드라이버(DAL) 계층**에서 동작함을 뒷받침한다:

> "Display blank out observed after waking system from MSB state with EDID emulation on below display combination: ... **Workaround: Add Regkey `DalEdidReadDeferralTime` with value 1.**"
> "Very sporadically system not entering MSB state with EDID Emulation"

- 출처: <https://drivers.amd.com/relnotes/windows_catalyst_driver_10_30_2021_release_notes.pdf> (AMD Embedded Q321 Windows Catalyst Driver Release Notes, Oct 2021)
  - `Dal*` 레지스트리 키 = AMD Display Abstraction Layer. EDID 읽기 타이밍이 커널 드라이버 관심사임을 AMD가 스스로 문서화.
  - **MSB = Modern Standby.** 즉 AMD 자신이 "EDID 에뮬레이션 + 절전 복귀" 조합의 알려진 이슈를 공개 문서에 적어 두었다. 이 케이스가 정확히 "화면 절전 중" 시나리오이므로 반드시 감안할 것.

### 4.3 **미확인으로 남는 것 (정직하게)**

- AMD의 1차 문서 어디에도 "에뮬레이트된 EDID가 OS의 monitor PnP hardware ID를 결정한다" 혹은 "`DxgkDdiQueryDeviceDescriptor`에 에뮬레이트된 EDID를 돌려준다"고 **명시한 문장은 찾지 못했다.** ADL 문서는 드라이버 내부 동작을 기술하지 않는다.
- `ADL_EMUL_MODE_ON_DISCONNECTED`가 **child status(HPD)까지 connected로 고정**하는지, 아니면 "연결된 동안에만 EDID를 대체"하는지도 문서화되어 있지 않다. 이 한 가지가 후보의 성패를 최종적으로 가른다.
- → 따라서 **결정적 검증은 이 PC에서 직접 해봐야 한다.** 절차는 6장.

---

## 5. 이 PC에서의 실측 결과 (재현 가능)

스크립트: `C:\Users\hans1\AppData\Local\Temp\claude\C--dev-PC\e597398e-f376-46ca-8aa8-1a8c1f89f66d\scratchpad\adl_edid_probe.py`, `adl_edid_probe2.py`
(`atiadlxx.dll`을 ctypes로 직접 호출. 읽기 전용 호출만 수행했다.)

```
ADL2_Main_Control_Create -> 0 (OK)

adapter idx=0  AMD Radeon(TM) Graphics   PCI\VEN_1002&DEV_13C0...
    ADL2_Adapter_EDIDManagement_Caps -> rc=0  supported=0
adapter idx=5  AMD Radeon RX 9070 XT     PCI\VEN_1002&DEV_7550&SUBSYS_E4891DA2&REV_C0
    ADL2_Adapter_EDIDManagement_Caps -> rc=0  supported=1      <<<< 소비자용 드라이버에서 지원됨

ADL2_Workstation_GlobalEDIDPersistence_Get -> rc=-8 (ADL_ERR_NOT_SUPPORTED)   <<<< Pro 전용 기능은 막힘

ADL2_Adapter_BoardLayout_Get(adapter 5) -> connectors=4
 connector[0] DisplayPort  emulStatus=0x1(REAL_DEVICE_CONNECTED) emulMode=0(OFF) displayIndex=0
    ConnectionData[REAL]     rc=0 edidSize=384  mfg=SAM product=0x7B0C
                             head=00ffffffffffff00 4c2d 0c7b 43323331 1f24 0104
    ConnectionData[EMULATED] rc=-8 (에뮬레이션 미설정이므로 없음)
    ConnectionData[CURRENT]  rc=0 edidSize=384  mfg=SAM product=0x7B0C
 connector[1] DisplayPort  emulStatus=0x1 emulMode=0  → SAM 0x79DF (G50F)
 connector[2] HDMI-A       emulStatus=0x0 emulMode=0
 connector[3] HDMI-A       emulStatus=0x1 emulMode=0
```

**해석**
- 소비자용 Adrenalin 32.0.31041.1004 + RX 9070 XT에서 **EDID Management는 "지원됨"으로 보고된다.** → 질문 2의 답은 "무너지지 않는다".
- Pro 전용인 것은 *Global EDID Persistence*(시스템 전역 EDID 유지) 쪽이며 이 PC에서는 `ADL_ERR_NOT_SUPPORTED(-8)`. 두 기능을 혼동하면 안 된다.
- 현재 DP 0번 커넥터의 실제 EDID는 384바이트(base + extension 2개), SAM/0x7B0C. ADL 에뮬레이션 버퍼는 1024바이트(`ADL_MAX_DISPLAY_EDID_DATA_SIZE`)이므로 **384바이트 전체를 그대로 담을 수 있다** — DSC/HDR용 DisplayID·CTA 확장 블록까지 손실 없이 에뮬레이트 가능.

### 5.1 현재 증상 실측 (배경 확인)

```
Microsoft-Windows-Kernel-PnP/Device Management, Event ID 1010, 최근 3일
  SAM7B0C         1495
  Default_Monitor  413
  SAM79DF           48
  합계             2028   (최신 2026-09-19 16:52:18)
```

현재 등록된 monitor devnode: `DISPLAY\SAM7B0C\7&16B8DDB4&0&UID256`(OK), `DISPLAY\DEFAULT_MONITOR\7&16B8DDB4&0&UID256`(**Unknown — 같은 UID256의 잔재**), `DISPLAY\SAM79DF\...`, `DISPLAY\BBC0104\...`.
최근 3일 구간에서는 `SAM7B0B`/`SAM7B11`보다 **`Default_Monitor`(= EDID 읽기 실패/미확정)** 로 떨어지는 패턴이 지배적이다.
→ 이는 오히려 EDID 에뮬레이션 후보에 **유리한** 정황이다. 에뮬레이션이 켜져 있으면 EDID 읽기 실패 구간에서도 드라이버가 고정 EDID를 내주므로 `Default_Monitor` 폴백이 발생할 이유가 사라진다. (단, HPD 자체가 끊기는 경우까지 덮는지는 4.3의 미확인 항목.)

---

## 6. 결정적 검증 실험 (아직 실행하지 않음 — 시스템 변경이므로)

> 주의: 아래는 **쓰기 동작**이다. 화면이 일시적으로 꺼지거나 해상도가 바뀔 수 있고, AMD 공식 릴리스 노트에 "EDID 에뮬레이션 상태에서 Modern Standby 복귀 시 blank-out" 알려진 이슈가 있다. 복구 수단(`ADL2_Adapter_ConnectionData_Remove`, 또는 AMD Software의 Remove 버튼, 최악의 경우 안전 모드)을 준비하고 진행할 것.

1. **UI 경로 먼저 확인** — AMD Software 열고 `Displays` 탭에 `EDID Emulation` 항목이 보이는지 본다. 보이면 GUI만으로 끝난다.
2. 현재 EDID를 그대로 내보낸다 (`ConnectionData[REAL]`의 384바이트, `SAM`/`0x7B0C`).
3. DP connector 0에 그 EDID를 `ADL2_Adapter_ConnectionData_Set`으로 넣고, `ADL2_Adapter_EmulationMode_Set(..., ADL_EMUL_MODE_ALWAYS /*3*/)` 적용. (보수적으로 가려면 `ADL_EMUL_MODE_ON_DISCONNECTED /*2*/` 부터.)
4. **판정 기준** — 화면을 절전으로 보낸 뒤:
   - `Microsoft-Windows-Kernel-PnP/Device Management` ID 1010 이 `SAM7B0C` / `Default_Monitor` 에 대해 **더 이상 찍히지 않으면 → 질문 3의 답은 "열거 시점에 적용된다"이고 후보는 성립**한다.
   - 여전히 48초 주기로 찍히면 → 에뮬레이션은 EDID 내용만 바꾸고 HPD/child-status는 못 막는다는 뜻 → `EDID_OVERRIDE`와 같은 이유로 후보 폐기.
5. 되돌리기: `ADL2_Adapter_ConnectionData_Remove(ctx, adapterIndex=5, devicePort{connectorIndex=0})` → `EmulationMode_Set(..., 0)`.

---

## 7. DP 1.4 + DSC 관련 (질문 4)

- **DSC 캐퍼빌리티는 EDID가 아니라 DPCD에서 읽힌다.** DP 1.4 DSC 캐퍼빌리티 레지스터는 DPCD `0x060`(`DP_DSC_SUPPORT`) ~ `0x06F`(`DP_DSC_BITS_PER_PIXEL_INC`)에 있다.
  - 출처(커널 소스, 1차): <https://raw.githubusercontent.com/torvalds/linux/master/include/drm/display/drm_dp.h> — `#define DP_DSC_SUPPORT 0x060 /* DP 1.4 */`
  - AMD 자사 디스플레이 코어가 실제로 그 주소를 읽는 코드: <https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/amd/display/dc/link/protocols/link_dp_capability.c> (`core_link_read_dpcd(link, DP_DSC_SUPPORT, ...)` → `link->dpcd_caps.dsc_caps`)
  - → **EDID를 에뮬레이트해도 DSC 협상 경로는 건드리지 않는다.** (HDMI는 EDID의 CTA HF-SCDB에 DSC 정보가 있어 사정이 다르지만, 이 PC는 DP.)
- **EDID 크기 제약**: ADL 에뮬레이션 버퍼 `ADL_MAX_DISPLAY_EDID_DATA_SIZE = 1024` 바이트. 이 모니터 EDID는 384바이트라 문제없음.
  - 출처: <https://raw.githubusercontent.com/GPUOpen-LibrariesAndSDKs/display-library/master/include/adl_defines.h>
- **실질적 위험 요소(AMD 공식 문서에 기재된 것)**: Modern Standby 진입 실패 / 복귀 후 blank-out, 재부팅 후 Radeon Pro Settings UI 미기동. 우회 regkey `DalEdidReadDeferralTime=1`.
  - 출처: <https://drivers.amd.com/relnotes/windows_catalyst_driver_10_30_2021_release_notes.pdf>
- **미확인**: VESA DisplayPort 1.4 / DSC 1.2 규격 원문은 유료라 직접 확인하지 못했다. 위 DPCD 주소는 Linux 커널(AMD 기여 코드 포함) 소스로 교차확인한 것이다.
- **미확인**: 실제 싱크가 절전으로 링크를 내린 상태에서 에뮬레이션이 활성일 때, AMD 드라이버가 DSC 파라미터를 무엇으로 유지하는지(마지막 값 유지 vs 재협상)는 문서화되어 있지 않다.

---

## 8. Windows 측 대안 (질문 5)

| 수단 | 열거 시점 고정 가능? | 근거 |
|---|---|---|
| **`EDID_OVERRIDE` (monitor INF `AddReg`)** | **불가.** monitor device의 hardware key에 저장 → Monitor.sys가 초기화 때 읽음. PDO 생성 이후 | <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/overriding-monitor-edids> |
| **monitor INF의 `MODES` / `MaxResolution` / `PreferredMode` / `DPMS` / `ICMProfile`** | **불가.** 동일하게 `HKR`(= hardware key). 게다가 `[Models]`가 `Monitor\MON12AB` hardware ID로 매칭되므로 product code가 바뀌면 애초에 매칭 실패. 참고로 이 override는 `EDID_OVERRIDE`보다 우선순위가 높다 — "This override receives higher precedence than the EDID override described in this article" (출처는 overriding-monitor-edids 쪽) | <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/monitor-inf-file-sections> + <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/overriding-monitor-edids> |
| **IDD (Indirect Display Driver)** | 목적이 다름. 물리 모니터를 고정하는 게 아니라 **별개의 가상 모니터를 추가**하는 user-mode 드라이버 모델 | <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/indirect-display-driver-model-overview> |
| **`HpdAwarenessAlwaysConnected`** | 개념상 정확히 원하는 것(= 항상 연결로 취급)이지만 **display miniport가 `DxgkDdiQueryChildRelations`에서 선언하는 값**이라 사용자가 설정할 수 없다. 즉 이것도 결국 GPU 드라이버 쪽 수단 | <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/enumerating-child-devices-of-a-display-adapter> |
| 장치 설치 제한 정책(Device Installation Restrictions) | **불가.** 드라이버 *설치*를 막을 뿐 PnP 열거/PDO 생성 자체는 그대로 일어난다 | (개념 확인, 별도 인용 생략 — 열거와 설치는 분리된 단계임이 위 문서들로 확인됨) |

**결론: Windows가 공식으로 제공하는 "열거 시점 EDID/식별 고정" 수단은 없다.** 그 지점은 전부 display miniport(= GPU 벤더 드라이버)의 영역이다. 그래서 AMD EDID Emulation이 유일하게 남는 정식 후보다.

---

## 9. 출처 목록

**Microsoft (1차)**
- Enumerating Child Devices of a Display Adapter — <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/enumerating-child-devices-of-a-display-adapter>
- DXGKDDI_QUERY_DEVICE_DESCRIPTOR — <https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/dispmprt/nc-dispmprt-dxgkddi_query_device_descriptor>
- Using an INF File to Override EDIDs — <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/overriding-monitor-edids>
- Monitor INF File Sections — <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/monitor-inf-file-sections>
- DISPLAYCONFIG_TARGET_DEVICE_NAME — <https://learn.microsoft.com/en-us/windows/win32/api/wingdi/ns-wingdi-displayconfig_target_device_name>
- Indirect Display Driver Model Overview — <https://learn.microsoft.com/en-us/windows-hardware/drivers/display/indirect-display-driver-model-overview>

**AMD (1차)**
- ADL EDID Management APIs — <https://gpuopen-librariesandsdks.github.io/adl/group__EDIDAPI.html>
- ADL SDK `adl_defines.h` / `adl_structures.h` — <https://github.com/GPUOpen-LibrariesAndSDKs/display-library>
- Radeon Pro Software for Enterprise 20.Q2.1 릴리스 노트 — <https://drivers.amd.com/relnotes/amd-radeon-pro-software-for-enterprise-20.Q2.1.pdf>
- AMD Software: PRO Edition 23.Q1 릴리스 노트 — <https://drivers.amd.com/relnotes/amd-software-pro-edition-23.Q1.pdf>
- AMD Embedded Q321 Windows Catalyst Driver 릴리스 노트 — <https://drivers.amd.com/relnotes/windows_catalyst_driver_10_30_2021_release_notes.pdf>

**소스 코드 (1차)**
- Linux DRM DisplayPort 헤더 (DSC DPCD 주소) — <https://raw.githubusercontent.com/torvalds/linux/master/include/drm/display/drm_dp.h>
- AMD Display Core DP capability 읽기 — <https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/amd/display/dc/link/protocols/link_dp_capability.c>

**로컬 실측 (이 PC)**
- `atiadlxx.dll` ADL 호출 결과 (5장)
- `C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe` 문자열 (3.4)
- `HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-...}\0000` (DAL2_DATA, edid_ui_component_NA)
- `Microsoft-Windows-Kernel-PnP/Device Management` ID 1010 집계

**의도적으로 배제한 것**: community.amd.com 포럼 글, 7thSense·Green Hippo·Hippotizer·VIOSO 등 3rd-party 매뉴얼, Reddit/블로그. (EDID Emulation의 UI 절차 설명은 이들 문서에 풍부하지만 1차 출처가 아니므로 본문 결론 근거로 쓰지 않았다.)

---

## 10. 미확인 항목 정리

1. AMD가 "에뮬레이트된 EDID = OS가 보는 EDID = PnP hardware ID 결정 근거"라고 **명시한 1차 문서** — 찾지 못함.
2. `ADL_EMUL_MODE_ON_DISCONNECTED` / `ALWAYS`가 **HPD/child-status까지 고정**하는지 — 문서화 없음. (6장 실험으로만 판정 가능)
3. `edid_ui_component_NA` 레지스트리 값의 true/false 의미 방향 — AMD 문서 없음.
4. AMD Software Adrenalin UI에서 EDID Emulation 항목이 **실제로 표시되는지** — 바이너리에 코드·문자열은 있고 caps는 1이지만, 화면을 직접 열어 확인하지는 않음.
5. VESA DP 1.4 / DSC 1.2 규격 원문 — 유료라 미확인 (Linux 커널 소스로 대체 확인).
6. `AMDEDIDEmulation.exe`(AMD Embedded용 별도 유틸리티) — 존재 흔적은 검색에 나오나 AMD 공식 배포 페이지가 404여서 미확인.
