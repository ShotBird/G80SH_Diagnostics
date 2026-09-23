# g80sh-exp-busy.ps1 — 티켓 20. 가설 H-D3: GPU 가 D3 에 못 들어가게 가벼운 일을 계속 시키면 재감지가 사라져 폭풍이 멎는가.
#
# 19~20 의 사슬: 화면 꺼짐 → GPU 유휴 → Windows 가 D3 로 → 아무 앱이나 깨움 → 재감지 → (재연결 32초 뒤면) G80SH 분리.
# 깨우는 쪽은 없앨 수 없다(20-5: 전부 멈춰도 chrome 이 깨움). 남은 지렛대는 D3 진입 자체.
# ffmpeg(TRCC 동봉) 로 320x240 2fps 영상을 AMD 하드웨어 인코더(h264_amf)에 계속 넣어 GPU 를 D0 에 붙잡는다.
# 모니터에는 아무것도 그리지 않는다. 끝나면 ffmpeg 를 끈다. 사슬 검증용 — 해결책이 아니다(상시규칙 1).
param([int]$Min = 30)
$x   = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$ff  = 'C:\Program Files\TRCCCAP\ffmpeg.exe'
$d   = 'C:\dev\PC\_evidence\exp-busy'
$log = Join-Path $d 'exp.log'
New-Item -ItemType Directory -Force $d | Out-Null
function Log($m) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }

$p = Start-Process $ff -ArgumentList '-hide_banner -loglevel error -re -f lavfi -i testsrc=size=320x240:rate=2 -c:v h264_amf -f null -' -WindowStyle Hidden -PassThru `
        -RedirectStandardError (Join-Path $d 'ffmpeg.err')
Start-Sleep -Seconds 10
Log ("ffmpeg pid {0} alive={1}" -f $p.Id, (-not $p.HasExited))
try {
    $etl = Join-Path $d 'g80sh-exp-busy.etl'
    & $x -start G80SHExp -on "802EC45A-1E99-4B83-9920-87C98277BA9D:0x101:5+9C205A39-1250-487D-ABD7-E831C6290539:0xffffffffffffffff:5" -f $etl -BufferSize 1024 -MinBuffers 64 -MaxBuffers 512 -MaxFile 4096 -FileMode Sequential 2>&1 | Out-Null
    Log 'capture start'
    for ($i = 0; $i -lt $Min; $i++) {
        Start-Sleep -Seconds 60
        if ($p.HasExited) { Log "ffmpeg exited (code $($p.ExitCode)) — 재시작"; $p = Start-Process $ff -ArgumentList '-hide_banner -loglevel error -re -f lavfi -i testsrc=size=320x240:rate=2 -c:v h264_amf -f null -' -WindowStyle Hidden -PassThru }
    }
    & $x -stop G80SHExp 2>&1 | Out-Null
    Log ("capture stop {0:N0} bytes" -f (Get-Item $etl -ErrorAction SilentlyContinue).Length)
}
finally {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Log 'ffmpeg stopped'
    Log 'done — task unregister'
    Unregister-ScheduledTask -TaskName 'G80SH Exp Busy' -Confirm:$false -ErrorAction SilentlyContinue
}
