# g80sh-exp-ulps.ps1 — 티켓 22. AMD EnableUlps(=GPU 전원 차단 기능) 를 끄면 D3 가 없어지고 폭풍이 멎는가.
#
# 사용자 요구: 별도 프로그램(ffmpeg) 없이 설정만으로 D3 를 막는다. 폭풍이 나면 즉시 파기.
# 참고: Guru3D(2025-06) "ULPS 끄기 = 장치 전원 차단 기능 끄기", 블로그(2026-07) EnableUlps·EnableUlps_NA 를 0 으로.
#       AMD 포럼 1건(날짜 미상) — 9070 XT 에서 끄면 영상 디코더 먹통, HAGS 끄면 해결. 드문 보고.
# 순서: 폭풍 확인 → 두 값 백업·0 → VIDEOIDLE 60 임시 → GPU 재시작 → 30초 여유 → $Min 분 관측(폭풍 1건이면 즉시 파기)
#       → 원복(finally): 두 값 복구 → VIDEOIDLE 복구 → GPU 재시작.
# 사용자 세션·관리자 권한 임시 작업 'G80SH Exp Ulps'.
param([int]$Min = 3, [int]$GraceSec = 30)
$key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000'
$gpu = 'PCI\VEN_1002&DEV_7550&SUBSYS_E4891DA2&REV_C0\6&8916a45&0&00000009'
$x   = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$d   = 'C:\dev\PC\_evidence\exp-ulps0'
$log = Join-Path $d 'exp.log'
New-Item -ItemType Directory -Force $d | Out-Null
function Log($m) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }
function Cyc($t0) { @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Device Management'; Id = 1010; StartTime = $t0 } -ErrorAction SilentlyContinue | Where-Object Message -match 'SAM7B0C').Count }
function Restart-Gpu { $r = pnputil /restart-device "$gpu" 2>&1; Log ("GPU restart: " + (($r | Select-Object -Last 1) -join ' ')); Start-Sleep -Seconds 20 }
$names = 'EnableUlps', 'EnableUlps_NA'
$orig = @{}; foreach ($n in $names) { $orig[$n] = (Get-ItemProperty $key -Name $n -ErrorAction SilentlyContinue).$n }
$idle = [Convert]::ToInt32(((powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE | Select-String 'AC.*(0x[0-9a-fA-F]{8})\s*$' | Select-Object -First 1).Matches.Groups[1].Value), 16)
Log ("armed — 백업 EnableUlps={0} EnableUlps_NA={1} / VIDEOIDLE AC {2}" -f $orig['EnableUlps'], $orig['EnableUlps_NA'], $idle)
$changed = $false
try {
    $w0 = Get-Date
    while ((Cyc (Get-Date).AddSeconds(-120)) -lt 2) { Start-Sleep -Seconds 10; if (((Get-Date) - $w0).TotalMinutes -gt 30) { Log '30분 기다려도 폭풍 없음 — 중단'; return } }
    Log 'storm 확인'
    foreach ($n in $names) { Set-ItemProperty $key -Name $n -Value 0 -Type DWord }
    $changed = $true
    Log ("set EnableUlps={0} EnableUlps_NA={1}" -f (Get-ItemProperty $key).EnableUlps, (Get-ItemProperty $key).EnableUlps_NA)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 60; powercfg /setactive SCHEME_CURRENT
    Restart-Gpu
    powercfg /setactive SCHEME_CURRENT
    $etl = Join-Path $d 'g80sh-exp-ulps0.etl'
    & $x -start G80SHExp -on "802EC45A-1E99-4B83-9920-87C98277BA9D:0x101:5+9C205A39-1250-487D-ABD7-E831C6290539:0xffffffffffffffff:5" -f $etl -BufferSize 1024 -MinBuffers 64 -MaxBuffers 512 -MaxFile 4096 -FileMode Sequential 2>&1 | Out-Null
    Start-Sleep -Seconds $GraceSec
    $t1 = Get-Date; Log "관측 시작 (재시작 후 여유 ${GraceSec}초)"
    $verdict = '통과'
    while (((Get-Date) - $t1).TotalMinutes -lt $Min) {
        Start-Sleep -Seconds 5
        if ((Cyc $t1) -ge 1) { $verdict = '파기 — 폭풍 발생'; break }
    }
    & $x -stop G80SHExp 2>&1 | Out-Null
    $d3 = @(Get-WinEvent -Path $etl -Oldest -FilterXPath '*[System[(EventID=154)]]' -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -like '*DxgKrnl*' -and $_.Properties[2].Value -eq 4 -and $_.TimeCreated -ge $t1 }).Count
    Log ("결과: {0} — {1:N1}분 관측, 사이클 {2}, GPU D3 진입 {3}" -f $verdict, ((Get-Date) - $t1).TotalMinutes, (Cyc $t1), $d3)
}
finally {
    & $x -stop G80SHExp 2>&1 | Out-Null
    foreach ($n in $names) { if ($null -ne $orig[$n]) { Set-ItemProperty $key -Name $n -Value $orig[$n] -Type DWord } }
    Log ("restored EnableUlps={0} EnableUlps_NA={1}" -f (Get-ItemProperty $key).EnableUlps, (Get-ItemProperty $key).EnableUlps_NA)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE $idle; powercfg /setactive SCHEME_CURRENT
    Log "VIDEOIDLE AC 복구 $idle"
    if ($changed) { Restart-Gpu }
    Log ("monitors: " + ((Get-PnpDevice -Class Monitor -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { ($_.InstanceId -split '\\')[1] + ':' + $_.Status }) -join ','))
    Log 'done — task unregister'
    Unregister-ScheduledTask -TaskName 'G80SH Exp Ulps' -Confirm:$false -ErrorAction SilentlyContinue
}
