# g80sh-mode.ps1 — G80SH 주사율 전환 (DSC 축 실험용)
#   list            사용 가능 모드 확인
#   set <Hz>        주사율 변경
# 되돌리기: set 240
param([string]$Cmd = 'list', [int]$Hz = 0)
$ErrorActionPreference = 'Continue'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
public struct DEVMODE {
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
  public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
  public int dmFields; public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation;
  public int dmDisplayFixedOutput; public short dmColor; public short dmDuplex; public short dmYResolution;
  public short dmTTOption; public short dmCollate;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
  public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
  public int dmDisplayFlags; public int dmDisplayFrequency;
  public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType;
  public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
}
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
public struct DISPLAY_DEVICE {
  public int cb;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)]  public string DeviceName;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
  public int StateFlags;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
}
public class Disp {
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern bool EnumDisplayDevices(string dev, uint n, ref DISPLAY_DEVICE d, uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, uint flags, IntPtr p);
}
'@ -ErrorAction SilentlyContinue

function Find-G80SH {
  for ($i = 0; $i -lt 16; $i++) {
    $d = New-Object DISPLAY_DEVICE; $d.cb = [Runtime.InteropServices.Marshal]::SizeOf($d)
    if (-not [Disp]::EnumDisplayDevices($null, $i, [ref]$d, 0)) { break }
    if (($d.StateFlags -band 1) -eq 0) { continue }   # attached to desktop
    $m = New-Object DISPLAY_DEVICE; $m.cb = [Runtime.InteropServices.Marshal]::SizeOf($m)
    if ([Disp]::EnumDisplayDevices($d.DeviceName, 0, [ref]$m, 0)) {
      if ($m.DeviceID -match 'SAM7B0C') { return $d.DeviceName }
    }
  }
  return $null
}

$dev = Find-G80SH
if (-not $dev) { Write-Output "G80SH 를 찾지 못했다"; exit 1 }
Write-Output ("G80SH = " + $dev)

$cur = New-Object DEVMODE; $cur.dmSize = [short][Runtime.InteropServices.Marshal]::SizeOf($cur)
[void][Disp]::EnumDisplaySettings($dev, -1, [ref]$cur)
Write-Output ("현재: {0}x{1} @ {2}Hz {3}bpp" -f $cur.dmPelsWidth, $cur.dmPelsHeight, $cur.dmDisplayFrequency, $cur.dmBitsPerPel)

if ($Cmd -eq 'list') {
  $seen = @{}
  for ($i = 0; $i -lt 400; $i++) {
    $m = New-Object DEVMODE; $m.dmSize = [short][Runtime.InteropServices.Marshal]::SizeOf($m)
    if (-not [Disp]::EnumDisplaySettings($dev, $i, [ref]$m)) { break }
    if ($m.dmPelsWidth -eq $cur.dmPelsWidth -and $m.dmPelsHeight -eq $cur.dmPelsHeight -and $m.dmBitsPerPel -eq 32) {
      $k = $m.dmDisplayFrequency
      if (-not $seen.ContainsKey($k)) { $seen[$k] = $true }
    }
  }
  Write-Output ("같은 해상도의 주사율: " + (($seen.Keys | Sort-Object) -join ', '))
  exit 0
}

if ($Cmd -eq 'set' -and $Hz -gt 0) {
  $n = $cur
  $n.dmDisplayFrequency = $Hz
  $n.dmFields = 0x400000 -bor 0x80000 -bor 0x100000 -bor 0x40000   # FREQUENCY|BITSPERPEL|PELSWIDTH|PELSHEIGHT
  $rc = [Disp]::ChangeDisplaySettingsEx($dev, [ref]$n, [IntPtr]::Zero, 0x00000001, [IntPtr]::Zero)  # CDS_UPDATEREGISTRY
  Write-Output ("ChangeDisplaySettingsEx({0}Hz) rc={1}   (0=성공, -2=모드 불가)" -f $Hz, $rc)
  Start-Sleep -Seconds 3
  $v = New-Object DEVMODE; $v.dmSize = [short][Runtime.InteropServices.Marshal]::SizeOf($v)
  [void][Disp]::EnumDisplaySettings($dev, -1, [ref]$v)
  Write-Output ("적용 후: {0}x{1} @ {2}Hz" -f $v.dmPelsWidth, $v.dmPelsHeight, $v.dmDisplayFrequency)
  exit 0
}
Write-Output "사용법: list | set <Hz>"
