# g80sh-hz.ps1 — G80SH 주사율 전환. \\.\DISPLAYn 번호가 재열거로 계속 바뀌므로
#                모니터 ID(SAM7B0C)로 찾아서 적용한다.
#   powershell -File g80sh-hz.ps1 -Hz 240
param([Parameter(Mandatory)][int]$Hz)
$ErrorActionPreference = 'Continue'
$mmt = 'C:\dev\PC\RemoteDisplaySwitch\MultiMonitorTool.exe'
$tmp = Join-Path $env:TEMP ("mmt_" + [guid]::NewGuid().ToString("N") + ".csv")

& $mmt /scomma $tmp
Start-Sleep -Seconds 3
if (-not (Test-Path $tmp)) { Write-Output "MultiMonitorTool 출력 실패"; exit 1 }
$rows = Import-Csv $tmp
$g = $rows | Where-Object { $_.'Monitor ID' -match 'SAM7B0C' } | Select-Object -First 1
if (-not $g) { Write-Output "G80SH 를 찾지 못했다"; exit 1 }
$name = $g.Name
Write-Output ("G80SH = {0}   현재 {1} @ {2}Hz" -f $name, $g.Resolution, $g.Frequency)

& $mmt /SetMonitors ("Name=" + $name + " Width=3840 Height=2160 DisplayFrequency=" + $Hz + " BitsPerPixel=32")
Start-Sleep -Seconds 6

$tmp2 = Join-Path $env:TEMP ("mmt_" + [guid]::NewGuid().ToString("N") + ".csv")
& $mmt /scomma $tmp2
Start-Sleep -Seconds 3
$g2 = (Import-Csv $tmp2) | Where-Object { $_.'Monitor ID' -match 'SAM7B0C' } | Select-Object -First 1
Write-Output ("적용 후: {0}   {1} @ {2}Hz   ({3})" -f $g2.Name, $g2.Resolution, $g2.Frequency, (Get-Date -Format 'HH:mm:ss'))
Remove-Item $tmp, $tmp2 -Force -ErrorAction SilentlyContinue
