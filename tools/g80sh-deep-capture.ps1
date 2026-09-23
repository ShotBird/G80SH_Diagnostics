# g80sh-deep-capture.ps1 — 티켓 19. 폭풍 중 커널 스케줄러·인터럽트까지 담는다(xperf).
#
# 18 이 남긴 두 질문:
#   (1) 점검 후 1.39초 뒤 "분리" 보고는 인터럽트(= 모니터 HPD) 문맥에서 오는가, AMD 스레드 판단에서 오는가
#       → CSWITCH + DISPATCHER(ReadyThread) 스택: DpiIndicateConnectorChangeWorkItem 을 돌린
#         작업자 스레드를 **누가 깨웠는지**가 스택으로 남는다. ISR/DPC 면 하드웨어, 일반 스레드면 소프트웨어.
#       → INTERRUPT + DPC: 그 시각 amdkmdag ISR/DPC 가 있었는가
#   (2) AMD 전 포트 점검은 왜 도는가 → DxgKrnl_Power(0x200) 런타임 전원 이벤트와 맞물리는가
# 무겁다(150초에 수백 MB). 관리자 권한 — RemoteDisplaySwitch\admin_hook.ps1 에서 & 로 부른다.
param([int]$Sec = 150, [string]$Tag = (Get-Date -Format 'MMdd-HHmm'))
$x = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$d = 'C:\dev\PC\_evidence\deeptest'
New-Item -ItemType Directory -Force $d | Out-Null
$k   = "$d\$Tag-kernel.etl"
$usr = "$d\$Tag-user.etl"
$out = "$d\g80sh-deep-$Tag.etl"
& $x -on PROC_THREAD+LOADER+CSWITCH+DISPATCHER+INTERRUPT+DPC -stackwalk CSwitch+ReadyThread -f $k -BufferSize 1024 -MinBuffers 256 -MaxBuffers 1024 -MaxFile 4096 -FileMode Sequential *> "$d\$Tag-start.txt"
& $x -start G80SHDeep -on "802EC45A-1E99-4B83-9920-87C98277BA9D:0x301:5:'stack'+9C205A39-1250-487D-ABD7-E831C6290539:0xffffffffffffffff:5" -f $usr -BufferSize 1024 -MinBuffers 64 -MaxBuffers 512 -MaxFile 2048 -FileMode Sequential *>> "$d\$Tag-start.txt"
Start-Sleep -Seconds $Sec
& $x -stop G80SHDeep -stop -d $out *> "$d\$Tag-stop.txt"
Remove-Item $k, $usr -ErrorAction SilentlyContinue
