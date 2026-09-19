# g80sh-ddc.py — DDC/CI 로 모니터 펌웨어/컨트롤러 정보를 읽는다 (설치 불필요)
#   VCP 0xC9 Display Firmware Level
#   VCP 0xC8 Display Controller Type
#   VCP 0xDF VCP Version
# 모니터가 절전 중이면 실패할 수 있다.
import ctypes as C
from ctypes import wintypes

user32 = C.windll.user32
dxva2 = C.windll.dxva2

class PHYSICAL_MONITOR(C.Structure):
    _fields_ = [("hPhysicalMonitor", wintypes.HANDLE),
                ("szPhysicalMonitorDescription", wintypes.WCHAR * 128)]

MONITORENUMPROC = C.WINFUNCTYPE(wintypes.BOOL, wintypes.HMONITOR, wintypes.HDC,
                                C.POINTER(wintypes.RECT), wintypes.LPARAM)

handles = []

def cb(hmon, hdc, lprc, data):
    n = wintypes.DWORD()
    if not dxva2.GetNumberOfPhysicalMonitorsFromHMONITOR(hmon, C.byref(n)):
        return True
    arr = (PHYSICAL_MONITOR * n.value)()
    if dxva2.GetPhysicalMonitorsFromHMONITOR(hmon, n.value, arr):
        for p in arr:
            handles.append((p.hPhysicalMonitor, p.szPhysicalMonitorDescription))
    return True

user32.EnumDisplayMonitors(None, None, MONITORENUMPROC(cb), 0)
print("physical monitors: %d" % len(handles))

VCP = {0xC9: "Display Firmware Level", 0xC8: "Display Controller Type",
       0xDF: "VCP Version", 0xB2: "Display Technology", 0xAC: "Horizontal Frequency",
       0xAE: "Vertical Frequency", 0xD6: "Power Mode"}

CTRL = {0x01: "Conexant", 0x02: "Genesis", 0x03: "Macronix", 0x04: "IDT", 0x05: "Mstar",
        0x06: "Myson", 0x07: "Phillips", 0x08: "PixelWorks", 0x09: "RealTek",
        0x0A: "Sage", 0x0B: "Silicon Image", 0x0C: "SmartASIC", 0x0D: "STMicro",
        0x0E: "Techwell", 0x0F: "Trumpion", 0x10: "Welltrend", 0x11: "Samsung",
        0x12: "Novatek", 0x13: "STK", 0xFF: "Not defined"}

for h, desc in handles:
    print("\n=== %s ===" % desc)
    n = C.c_uint32(0)
    if dxva2.GetCapabilitiesStringLength(h, C.byref(n)) and n.value:
        buf = C.create_string_buffer(n.value)
        if dxva2.CapabilitiesRequestAndCapabilitiesReply(h, buf, n.value):
            s = buf.value.decode("ascii", "replace")
            print("  caps(%d): %s" % (len(s), s[:400]))
    else:
        print("  caps: 읽기 실패")
    for code, name in VCP.items():
        typ = C.c_uint32(0); cur = C.c_uint32(0); mx = C.c_uint32(0)
        ok = dxva2.GetVCPFeatureAndVCPFeatureReply(h, C.c_ubyte(code),
                                                   C.byref(typ), C.byref(cur), C.byref(mx))
        if ok:
            extra = ""
            if code == 0xC8:
                extra = "  (%s)" % CTRL.get(cur.value & 0xFF, "?")
            print("  0x%02X %-26s cur=%-6d max=%-6d%s" % (code, name, cur.value, mx.value, extra))
        else:
            print("  0x%02X %-26s 읽기 실패" % (code, name))
    dxva2.DestroyPhysicalMonitor(h)
