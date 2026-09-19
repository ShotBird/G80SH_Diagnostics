# PC 묶음 폴더

이 PC의 모니터·케이스 화면·원격 접속 환경을 관리하는 도구 모음. 업무 프로젝트(`C:\dev\*`)와 섞지 않는다.

| 폴더 | 하는 일 | 작업 스케줄러 | 로그 | GitHub |
|---|---|---|---|---|
| `CaseDisplay\` | 케이스 화면(DarkFlash USB LCD) 구동 + 웹 설정 화면 http://127.0.0.1:8765/ | `CaseDisplay` (로그온, 사용자 권한) | `C:\ProgramData\CaseDisplay.log` | [DarkFlash_CaseDisplay](https://github.com/hans10102-droid/DarkFlash_CaseDisplay) |
| `RemoteDisplaySwitch\` | 크롬 원격 접속 때만 더미 동글로 화면 전환, 끝나면 평소 구성 복원. `docs\` G80SH 분석 보고서, `tools\` HDR 인증 스크립트(현재 적용 중) | `Remote Display Switch`, `Remote Display Restore (logon)`, `Remote Display Restore (unlock)` (관리자) | `C:\ProgramData\RemoteDisplaySwitch.log` | [G80SH_RemoteDisplaySwitch](https://github.com/hans10102-droid/G80SH_RemoteDisplaySwitch) |
| `_archive\` | 더 쓰지 않지만 바로 지우지 않은 것 | — | — | 올리지 않음 (시리얼 포함) |

- 폴더를 옮기면 작업 스케줄러 경로가 깨진다. 옮길 때는 작업도 같이 고칠 것.
- 관리자 작업: `RemoteDisplaySwitch\admin_hook.ps1`을 쓰고 `Remote Display Restore (logon)` 작업을 실행하면 관리자 권한으로 한 번 돌고 지워진다.
- `RemoteDisplaySwitch\MultiMonitorTool.exe`, `home.cfg`, `remote.cfg`는 저장소에 없다(지우면 감시자가 시작하지 않음).

## 보관 폴더 삭제 예정

`_archive\2026-09-18_개인설정\` (옛 `Desktop\개인설정`에서 온 것: G80SH 근거 자료, DarkFlashProtocol, EDID_Override, GhostMonitorClean, RemoteDisplaySwitch 옛 사본)

- **2026-10-16 이후**, 그리고 2026-09-18 이후 원격 전환이 한 번 이상 정상으로 돈 것이 로그로 확인되면(`REMOTE layout ... ok=True` → `remote ended` → `apply HOME`) 폴더를 통째로 지운다.
- 2026-10-16에 알림 창이 한 번 뜬다(작업 `PC 보관 폴더 삭제 알림`, 뜬 뒤 스스로 지워짐).
- 자동으로 지우지 않는다. Claude에게 "보관 폴더 지워"라고 하면 조건을 확인하고 지운다.
