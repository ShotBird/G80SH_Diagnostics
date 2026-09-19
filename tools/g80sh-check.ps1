# 부팅 후 감시 상태 한 번에 확인 — powershell -File C:\dev\PC\tools\g80sh-check.ps1
$ErrorActionPreference='SilentlyContinue'
$out='C:\dev\PC\_evidence'
Write-Output ("=== " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + " ===")
Write-Output ("부팅        : " + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime)
Write-Output ("감시 프로세스: " + (((Get-Process powershell | Where-Object { $_.SI -eq 0 }).Id) -join ',' ))
Write-Output ("ETW 세션    : " + ((& logman query -ets 2>&1 | Select-String 'G80SH') -join ' ').Trim())
$live = Join-Path $out 'g80sh-live.etl'
if (Test-Path $live) { Write-Output ("순환 버퍼   : {0:N0} bytes" -f (Get-Item $live).Length) } else { Write-Output "순환 버퍼   : 없음" }
Write-Output ("화면 상태   : " + ((Get-Content C:\ProgramData\CaseDisplay.log -Tail 1)))
Write-Output "--- auto.log ---"
Get-Content (Join-Path $out 'auto.log') -Tail 6
Write-Output "--- 부팅 이후 1010 ---"
$b = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$e = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Kernel-PnP/Device Management'; Id=1010; StartTime=$b} -ErrorAction SilentlyContinue
Write-Output ("총 " + @($e).Count + "건")
@($e) | Group-Object { if($_.Message -match 'DISPLAY\([A-Za-z0-9_]+)\'){$matches[1]}else{'?'} } | Sort-Object Count -Desc | ForEach-Object { "  {0,-16} {1,5}" -f $_.Name,$_.Count }
@($e) | Sort-Object TimeCreated | Select-Object -Last 6 | ForEach-Object { "  {0}  {1}" -f $_.TimeCreated.ToString('HH:mm:ss.fff'), $(if($_.Message -match 'DISPLAY\([A-Za-z0-9_]+)\'){$matches[1]}) }
Write-Output "--- 캡처 산출물 ---"
Get-ChildItem $out -Filter 'g80sh-dxg-agg-*.txt' | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize
