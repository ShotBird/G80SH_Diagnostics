# G80SH 증상 기록 수집기 (읽기 전용)
# 작업 스케줄러 "G80SH 증상 기록"이 15분마다 실행한다. 사용자 권한, UAC 없음.
# 마지막 수집 시각을 state 파일에 남기고, 그 이후의 장치 제거 이벤트만 센다.
# 2026-09-26 이후에는 스스로 작업을 지운다 (삼성 검토 기간 대비용).

$dir   = 'C:\dev\PC\_evidence'
$log   = Join-Path $dir 'g80sh-evidence.log'
$state = Join-Path $dir 'last-run.txt'
New-Item -ItemType Directory -Force $dir | Out-Null

function Write-Log($m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }

# 기한이 지나면 스스로 정리
if ((Get-Date) -gt (Get-Date '2026-09-26 23:59')) {
    Write-Log 'collection period over - unregistering task'
    Unregister-ScheduledTask -TaskName 'G80SH 증상 기록' -Confirm:$false -ErrorAction SilentlyContinue
    return
}

$now = Get-Date
$since = $now.AddMinutes(-15)
if (Test-Path $state) {
    try { $since = [datetime]::ParseExact((Get-Content $state -First 1), 'yyyy-MM-dd HH:mm:ss', $null) } catch { }
}
if (($now - $since).TotalHours -gt 24) { $since = $now.AddHours(-24) }   # 오래 꺼져 있었으면 24시간까지만

$ev = @(Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Kernel-PnP/Device Management'; StartTime=$since; EndTime=$now} -ErrorAction SilentlyContinue)
$g80 = @($ev | Where-Object { $_.Message -match 'SAM7B0C' })
$g50 = @($ev | Where-Object { $_.Message -match 'SAM79DF' })
$ghostEv = @($ev | Where-Object { $_.Message -match 'Default_Monitor' })

# 해제 간격
$iv = @()
$sorted = @($g80 | Sort-Object TimeCreated)
for ($i = 1; $i -lt $sorted.Count; $i++) { $iv += ($sorted[$i].TimeCreated - $sorted[$i-1].TimeCreated).TotalSeconds }
$ivTxt = if ($iv.Count) { "{0:n0}s avg ({1:n0}~{2:n0})" -f ($iv | Measure-Object -Average).Average, ($iv | Measure-Object -Minimum).Minimum, ($iv | Measure-Object -Maximum).Maximum } else { '-' }

# 화면 전원 상태 (CaseDisplay 로그의 마지막 display power 줄)
$power = '?'
$cd = 'C:\ProgramData\CaseDisplay.log'
if (Test-Path $cd) {
    $line = Select-String -Path $cd -Pattern 'display power' -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($line) { $power = ($line.Line -split 'display power: ')[1] }
}
$ghosts = @(Get-PnpDevice -Class Monitor -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'OK' }).Count

Write-Log ("{0:HH:mm}-{1:HH:mm} G80SH={2} G50F={3} ghostEv={4} interval={5} screen={6} ghosts={7}" -f $since, $now, $g80.Count, $g50.Count, $ghostEv.Count, $ivTxt, $power, $ghosts)
Set-Content -Path $state -Value $now.ToString('yyyy-MM-dd HH:mm:ss') -Encoding UTF8

if ((Get-Item $log).Length -gt 2MB) { Get-Content $log -Tail 3000 | Set-Content $log -Encoding UTF8 }
