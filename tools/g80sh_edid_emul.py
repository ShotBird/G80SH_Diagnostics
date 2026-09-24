# g80sh_edid_emul.py — AMD EDID 에뮬레이션 켜기/끄기/상태 (ADL2)
#
#   python g80sh_edid_emul.py status          읽기 전용. 현재 상태 출력
#   python g80sh_edid_emul.py on [mode]       현재 REAL EDID 를 고정으로 심는다 (mode 기본 2)
#   python g80sh_edid_emul.py off             에뮬레이션 제거 (복구)
#
# mode: 2 = ON_DISCONNECTED (보수적), 3 = ALWAYS
#
# 경고: AMD 릴리스 노트에 "EDID 에뮬레이션 상태에서 Modern Standby 복귀 후 blank-out"
#       알려진 이슈가 있다. off 를 작업 스케줄러 onstart 에 걸어 두고 쓸 것.
import ctypes as C
import sys, time, os

ADL_MAX_PATH = 256
ADL_MAX_CONNECTION_TYPES = 32
ADL_MAX_DISPLAY_EDID_DATA_SIZE = 1024
ADL_OK = 0
ADL_CONNECTION_TYPE_DISPLAY_PORT = 4
EMUL = {0: "OFF", 1: "ON_CONNECTED", 2: "ON_DISCONNECTED", 3: "ALWAYS"}
QUERY = {0: "REAL", 1: "EMULATED", 2: "CURRENT"}
CONN_TYPE = {0: "UNKNOWN", 1: "VGA", 2: "DVI-D", 3: "DVI-I", 8: "HDMI-A", 9: "HDMI-B",
             10: "DisplayPort", 11: "eDP", 12: "miniDP", 13: "Virtual", 14: "USB-C"}
LOG = r"C:\dev\1_PC_Setup\_evidence\edid-emul.log"


def log(m):
    line = "%s %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), m)
    print(line)
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(line + "\n")
    except Exception:
        pass


class AdapterInfo(C.Structure):
    _fields_ = [("iSize", C.c_int), ("iAdapterIndex", C.c_int), ("strUDID", C.c_char * ADL_MAX_PATH),
                ("iBusNumber", C.c_int), ("iDeviceNumber", C.c_int), ("iFunctionNumber", C.c_int),
                ("iVendorID", C.c_int), ("strAdapterName", C.c_char * ADL_MAX_PATH),
                ("strDisplayName", C.c_char * ADL_MAX_PATH), ("iPresent", C.c_int), ("iExist", C.c_int),
                ("strDriverPath", C.c_char * ADL_MAX_PATH), ("strDriverPathExt", C.c_char * ADL_MAX_PATH),
                ("strPNPString", C.c_char * ADL_MAX_PATH), ("iOSDisplayIndex", C.c_int)]


class ADLMSTRad(C.Structure):
    _fields_ = [("iLinkNumber", C.c_int), ("rad", C.c_char * 15)]


class ADLDevicePort(C.Structure):
    _fields_ = [("iConnectorIndex", C.c_int), ("aMSTRad", ADLMSTRad)]


class ADLConnectionState(C.Structure):
    _fields_ = [("iEmulationStatus", C.c_int), ("iEmulationMode", C.c_int), ("iDisplayIndex", C.c_int)]


class ADLConnectionProperties(C.Structure):
    _fields_ = [("iValidProperties", C.c_int), ("iBitrate", C.c_int), ("iNumberOfLanes", C.c_int),
                ("iColorDepth", C.c_int), ("iStereo3DCaps", C.c_int), ("iOutputBandwidth", C.c_int)]


class ADLConnectionData(C.Structure):
    _fields_ = [("iConnectionType", C.c_int), ("aConnectionProperties", ADLConnectionProperties),
                ("iNumberofPorts", C.c_int), ("iActiveConnections", C.c_int), ("iDataSize", C.c_int),
                ("EdidData", C.c_ubyte * ADL_MAX_DISPLAY_EDID_DATA_SIZE)]


class ADLBracketSlotInfo(C.Structure):
    _fields_ = [("iSlotIndex", C.c_int), ("iWidth", C.c_int), ("iHeight", C.c_int)]


class ADLConnectorInfo(C.Structure):
    _fields_ = [("iConnectorIndex", C.c_int), ("iConnectorId", C.c_int), ("iSlotIndex", C.c_int),
                ("iType", C.c_int), ("iOffset", C.c_int), ("iLength", C.c_int)]


MALLOC = C.CFUNCTYPE(C.c_void_p, C.c_int)
_bufs = []


@MALLOC
def adl_malloc(n):
    b = C.create_string_buffer(n)
    _bufs.append(b)
    return C.cast(b, C.c_void_p).value


def edid_id(b, size):
    if size < 12:
        return "", ""
    m = (b[8] << 8) | b[9]
    mfg = "".join(chr(((m >> s) & 0x1F) + 64) for s in (10, 5, 0))
    return mfg, "0x%02X%02X" % (b[11], b[10])


def open_adl():
    dll = C.CDLL("atiadlxx.dll")
    dll.ADL2_Adapter_ConnectionData_Get.argtypes = [C.c_void_p, C.c_int, ADLDevicePort, C.c_int,
                                                    C.POINTER(ADLConnectionData)]
    dll.ADL2_Adapter_ConnectionData_Set.argtypes = [C.c_void_p, C.c_int, ADLDevicePort, ADLConnectionData]
    dll.ADL2_Adapter_ConnectionData_Remove.argtypes = [C.c_void_p, C.c_int, ADLDevicePort]
    dll.ADL2_Adapter_EmulationMode_Set.argtypes = [C.c_void_p, C.c_int, ADLDevicePort, C.c_int]
    dll.ADL2_Adapter_ConnectionState_Get.argtypes = [C.c_void_p, C.c_int, ADLDevicePort,
                                                     C.POINTER(ADLConnectionState)]
    ctx = C.c_void_p()
    rc = dll.ADL2_Main_Control_Create(adl_malloc, 1, C.byref(ctx))
    if rc != ADL_OK:
        raise SystemExit("ADL2_Main_Control_Create rc=%d" % rc)
    return dll, ctx


def find_target(dll, ctx):
    """G80SH 가 붙은 어댑터와 커넥터를 찾는다. EDID 제조사 SAM + 제품코드로 식별."""
    n = C.c_int(0)
    dll.ADL2_Adapter_NumberOfAdapters_Get(ctx, C.byref(n))
    arr = (AdapterInfo * n.value)()
    dll.ADL2_Adapter_AdapterInfo_Get(ctx, arr, C.sizeof(arr))
    gpu = None
    for a in arr:
        if b"7550" in a.strPNPString:
            gpu = a
            break
    if gpu is None:
        raise SystemExit("RX 9070 XT (DEV_7550) 어댑터를 찾지 못했다")
    idx = gpu.iAdapterIndex

    valid = C.c_int(0); nslots = C.c_int(0); nconn = C.c_int(0)
    pslot = C.POINTER(ADLBracketSlotInfo)(); pconn = C.POINTER(ADLConnectorInfo)()
    rc = dll.ADL2_Adapter_BoardLayout_Get(ctx, idx, C.byref(valid), C.byref(nslots),
                                          C.byref(pslot), C.byref(nconn), C.byref(pconn))
    if rc != ADL_OK:
        raise SystemExit("BoardLayout_Get rc=%d" % rc)

    conns = []
    for i in range(nconn.value):
        ci = pconn[i]
        dp = ADLDevicePort(); dp.iConnectorIndex = ci.iConnectorIndex
        st = ADLConnectionState()
        dll.ADL2_Adapter_ConnectionState_Get(ctx, idx, dp, C.byref(st))
        info = {"i": i, "connIdx": ci.iConnectorIndex, "type": CONN_TYPE.get(ci.iType, str(ci.iType)),
                "dp": dp, "state": st, "edid": {}}
        for q in (0, 1, 2):
            cd = ADLConnectionData()
            rc2 = dll.ADL2_Adapter_ConnectionData_Get(ctx, idx, dp, q, C.byref(cd))
            if rc2 == ADL_OK and cd.iDataSize:
                mfg, prod = edid_id(bytes(cd.EdidData), cd.iDataSize)
                info["edid"][q] = (cd, mfg, prod, cd.iDataSize)
        conns.append(info)
    return gpu, idx, conns


G80SH_CODES = ("0x7B0C", "0x7B0B", "0x7B11")


def pick_g80sh(conns):
    for c in conns:
        for q in (0, 2):
            if q in c["edid"]:
                _, mfg, prod, _ = c["edid"][q]
                if mfg == "SAM" and prod in G80SH_CODES:
                    return c
    return None


def cmd_status(dll, ctx):
    gpu, idx, conns = find_target(dll, ctx)
    log("adapter idx=%d %s" % (idx, gpu.strAdapterName.decode(errors="replace")))
    for c in conns:
        st = c["state"]
        log("  connector[%d] connIdx=%d %-12s emulStatus=0x%x emulMode=%d(%s) displayIndex=%d"
            % (c["i"], c["connIdx"], c["type"], st.iEmulationStatus, st.iEmulationMode,
               EMUL.get(st.iEmulationMode, "?"), st.iDisplayIndex))
        for q in sorted(c["edid"]):
            _, mfg, prod, size = c["edid"][q]
            log("      %-9s size=%-5d mfg=%s product=%s" % (QUERY[q], size, mfg, prod))
    t = pick_g80sh(conns)
    log("  => G80SH connector: %s" % ("connIdx=%d" % t["connIdx"] if t else "찾지 못함"))
    return 0


def cmd_on(dll, ctx, mode):
    gpu, idx, conns = find_target(dll, ctx)
    t = pick_g80sh(conns)
    if t is None:
        log("ON 실패: G80SH 커넥터를 찾지 못했다")
        return 1
    if 0 not in t["edid"]:
        log("ON 실패: REAL EDID 를 읽지 못했다 (모니터가 지금 응답하지 않는다)")
        return 1
    real, mfg, prod, size = t["edid"][0]
    log("ON: connIdx=%d 에 REAL EDID %d바이트 (%s %s) 를 mode=%d(%s) 로 심는다"
        % (t["connIdx"], size, mfg, prod, mode, EMUL.get(mode, "?")))

    cd = ADLConnectionData()
    cd.iConnectionType = ADL_CONNECTION_TYPE_DISPLAY_PORT
    cd.aConnectionProperties = real.aConnectionProperties
    cd.iDataSize = size
    for i in range(size):
        cd.EdidData[i] = real.EdidData[i]

    rc = dll.ADL2_Adapter_ConnectionData_Set(ctx, idx, t["dp"], cd)
    log("  ConnectionData_Set rc=%d" % rc)
    if rc != ADL_OK:
        return 1
    rc = dll.ADL2_Adapter_EmulationMode_Set(ctx, idx, t["dp"], mode)
    log("  EmulationMode_Set(%d) rc=%d" % (mode, rc))
    return 0 if rc == ADL_OK else 1


def cmd_off(dll, ctx):
    gpu, idx, conns = find_target(dll, ctx)
    rcs = []
    for c in conns:
        st = c["state"]
        if st.iEmulationMode == 0 and not (st.iEmulationStatus & 0x2):
            continue
        r1 = dll.ADL2_Adapter_EmulationMode_Set(ctx, idx, c["dp"], 0)
        r2 = dll.ADL2_Adapter_ConnectionData_Remove(ctx, idx, c["dp"])
        log("OFF: connIdx=%d EmulationMode_Set(0) rc=%d  ConnectionData_Remove rc=%d"
            % (c["connIdx"], r1, r2))
        rcs.append((r1, r2))
    if not rcs:
        log("OFF: 에뮬레이션이 걸린 커넥터가 없다 (이미 정상)")
    return 0


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "status"
    mode = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    dll, ctx = open_adl()
    try:
        if what == "status":
            return cmd_status(dll, ctx)
        if what == "on":
            return cmd_on(dll, ctx, mode)
        if what == "off":
            return cmd_off(dll, ctx)
        log("알 수 없는 명령: %s" % what)
        return 2
    finally:
        dll.ADL2_Main_Control_Destroy(ctx)


if __name__ == "__main__":
    sys.exit(main())
