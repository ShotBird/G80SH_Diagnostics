# g80sh-stack-capture.ps1 — 티켓 17. 폭풍 중에 DxgKrnl 이벤트를 호출 스택과 함께 한 번 담는다(xperf).
#
# 관리자 권한 필요 — RemoteDisplaySwitch\admin_hook.ps1 에서 이 파일을 & 로 부른다.
# 폭풍이 도는 중에 실행할 것(사이클 약 45초, 기본 100초면 2회).
#
# 왜 xperf 인가: WPR 커스텀 프로파일(.wprp)은 09-23 에 이벤트 수집기 세션만 뜨고 provider 가
#   붙지 않아 PnP·DxgKrnl 이벤트가 0건이었다. xperf -on '...:stack' 은 정상 동작했다.
# 왜 DxgKrnl Base(0x1) 인가: Kernel-PnP 810 의 스택은 커널 작업자 스레드
#   (IopInvalidateBusRelationsWorker)에서 끝나 원 호출자가 안 보인다. Q1 의 진짜 앞단은
#   DxgKrnl DdiQueryConnectionChange(Base 키워드)이고, 그 페이로드에 AMD 가 보고한
#   ConnectionStatus 가 들어 있다. Base 는 양이 많아 100초에 약 120MB 가 된다.
#
# 풀기: _NT_SYMBOL_PATH=srv*C:\symbols*https://msdl.microsoft.com/download/symbols
#       xperf -i <etl> -o out.txt -symbols -a dumper
#   amdkmdag.sys 는 공개 심볼이 없어 주소로만 나온다.
param([int]$Sec = 100, [string]$Tag = (Get-Date -Format 'MMdd-HHmm'))
$x   = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$d   = 'C:\dev\PC\_evidence\stacktest'
New-Item -ItemType Directory -Force $d | Out-Null
$usr = "$d\$Tag-user.etl"
$out = "$d\g80sh-xperf-$Tag.etl"
& $x -on PROC_THREAD+LOADER
& $x -start G80SHC -on "802EC45A-1E99-4B83-9920-87C98277BA9D:0x101:5:'stack'+9C205A39-1250-487D-ABD7-E831C6290539:0xffffffffffffffff:5" -f $usr -BufferSize 1024 -MinBuffers 64 -MaxBuffers 256
Start-Sleep -Seconds $Sec
& $x -stop G80SHC -stop -d $out
Remove-Item $usr -ErrorAction SilentlyContinue
