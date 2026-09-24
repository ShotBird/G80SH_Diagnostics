# g80sh-exp-regseq.ps1 — 티켓 23. 설정 하나로 GPU 런타임 D3 를 막을 수 있는가 — 후보를 순서대로 시험한다.
#
# 22 에서 AMD ULPS·PowerDown 값은 D3 를 못 막았다. D3 는 Windows 그래픽 커널(dxgkrnl)의 런타임 전원 관리가 건다(19).
# dxgkrnl.sys 가 실제로 읽는 이름(09-24 문자열 확인): DisableD3Requests, EnableRuntimePowerManagement,
#   DefaultD3TransitionLatencyIdleMonitorOff … (공식 문서 없음 — 위치는 GraphicsDrivers\Power 로 추정)
# 후보마다: 폭풍 확인 → 값 설정 → GPU 재시작 → 30초 여유 → 3분 관측(폭풍 1건이면 즉시 파기, D3 진입 수 기록)
#           → 원복(값 삭제/복구) → GPU 재시작. 한 후보가 통과하면 거기서 멈춘다.
# 화면 꺼짐: VIDEOIDLE 60 임시, 폭풍이 안 오면 PC 잠금으로 화면을 끈다. 끝나면 VIDEOIDLE 복구.
# 사용자 세션·관리자 권한 임시 작업 'G80SH Exp RegSeq'. 사용자 지시: ffmpeg 제외.
param([int]$Min = 3, [int]$GraceSec = 30)
$gpu = 'PCI\VEN_1002&DEV_7550&SUBSYS_E4891DA2&REV_C0\6&8916a45&0&00000009'
$pw  = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Power'
$amd = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000'
$cands = @(
    @{ Path = $pw;  Name = 'DisableD3Requests';                        Value = 1 },
    @{ Path = $pw;  Name = 'EnableRuntimePowerManagement';             Value = 0 },
    @{ Path = $pw;  Name = 'DefaultD3TransitionLatencyIdleMonitorOff'; Value = 1 },
    @{ Path = $amd; Name = 'KMD_RTPMEnabled';                          Value = 0 }
)
$x   = 'C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe'
$d   = 'C:\dev\1_PC_Setup\_evidence\exp-regseq'
$log = Join-Path $d 'exp.log'
New-Item -ItemType Directory -Force $d | Out-Null
function Log($m) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }
function Cyc($t0) { @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Device Management'; Id = 1010; StartTime = $t0 } -ErrorAction SilentlyContinue | Where-Object Message -match 'SAM7B0C').Count }
function Restart-Gpu { $r = pnputil /restart-device "$gpu" 2>&1; Log ("  GPU restart: " + (($r | Select-Object -Last 1) -join ' ')); Start-Sleep -Seconds 20 }
function Wait-Storm {
    $w0 = Get-Date; $locked = $false
    while ((Cyc (Get-Date).AddSeconds(-120)) -lt 2) {
        Start-Sleep -Seconds 10
        $m = ((Get-Date) - $w0).TotalMinutes
        if (-not $locked -and $m -gt 4) { rundll32.exe user32.dll,LockWorkStation; $locked = $true; Log '  폭풍 없음 4분 — PC 잠금으로 화면 끄기' }
        if ($m -gt 25) { return $false }
    }
    return $true
}
$idle = [Convert]::ToInt32(((powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE | Select-String 'AC.*(0x[0-9a-fA-F]{8})\s*$' | Select-Object -First 1).Matches.Groups[1].Value), 16)
Log "armed — 후보 $($cands.Count)개, VIDEOIDLE AC $idle → 60 임시"
powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 60; powercfg /setactive SCHEME_CURRENT
try {
    foreach ($c in $cands) {
        Log ("=== 후보: {0}\{1} = {2}" -f (Split-Path $c.Path -Leaf), $c.Name, $c.Value)
        if (-not (Wait-Storm)) { Log '  25분 기다려도 폭풍 없음 — 시험 중단'; break }
        Log '  storm 확인'
        if (-not (Test-Path $c.Path)) { New-Item -Path $c.Path -Force | Out-Null; $made = $true } else { $made = $false }
        $had = $null -ne (Get-ItemProperty $c.Path -Name $c.Name -ErrorAction SilentlyContinue)
        $old = (Get-ItemProperty $c.Path -Name $c.Name -ErrorAction SilentlyContinue).($c.Name)
        try {
            Set-ItemProperty $c.Path -Name $c.Name -Value $c.Value -Type DWord
            Log ("  set (이전: {0})" -f $(if ($had) { $old } else { '없음' }))
            Restart-Gpu
            powercfg /setactive SCHEME_CURRENT
            $etl = Join-Path $d ("g80sh-exp-{0}.etl" -f $c.Name)
            & $x -start G80SHExp -on "802EC45A-1E99-4B83-9920-87C98277BA9D:0x101:5+9C205A39-1250-487D-ABD7-E831C6290539:0xffffffffffffffff:5" -f $etl -BufferSize 1024 -MinBuffers 64 -MaxBuffers 512 -MaxFile 4096 -FileMode Sequential 2>&1 | Out-Null
            Start-Sleep -Seconds $GraceSec
            $t1 = Get-Date; $v = '통과'
            while (((Get-Date) - $t1).TotalMinutes -lt $Min) { Start-Sleep -Seconds 5; if ((Cyc $t1) -ge 1) { $v = '파기 — 폭풍 발생'; break } }
            & $x -stop G80SHExp 2>&1 | Out-Null
            $d3 = @(Get-WinEvent -Path $etl -Oldest -FilterXPath '*[System[(EventID=154)]]' -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -like '*DxgKrnl*' -and $_.Properties[2].Value -eq 4 -and $_.TimeCreated -ge $t1 }).Count
            Log ("  결과: {0} — {1:N1}분, 사이클 {2}, GPU D3 진입 {3}" -f $v, ((Get-Date) - $t1).TotalMinutes, (Cyc $t1), $d3)
        }
        finally {
            & $x -stop G80SHExp 2>&1 | Out-Null
            if ($had) { Set-ItemProperty $c.Path -Name $c.Name -Value $old -Type DWord } else { Remove-ItemProperty $c.Path -Name $c.Name -ErrorAction SilentlyContinue }
            if ($made) { Remove-Item $c.Path -ErrorAction SilentlyContinue }
            Log ("  원복: {0} = {1}" -f $c.Name, $(if ($null -ne (Get-ItemProperty $c.Path -Name $c.Name -ErrorAction SilentlyContinue)) { (Get-ItemProperty $c.Path -Name $c.Name).($c.Name) } else { '없음' }))
            Restart-Gpu
        }
        if ($v -eq '통과') { Log "★ 통과 — 후보 $($c.Name) 에서 멈춤"; break }
    }
}
finally {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE $idle; powercfg /setactive SCHEME_CURRENT
    Log ("VIDEOIDLE AC 복구 $idle / monitors: " + ((Get-PnpDevice -Class Monitor -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object { ($_.InstanceId -split '\\')[1] + ':' + $_.Status }) -join ','))
    Log 'done — task unregister'
    Unregister-ScheduledTask -TaskName 'G80SH Exp RegSeq' -Confirm:$false -ErrorAction SilentlyContinue
}
