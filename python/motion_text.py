"""Standard-library-only Python wrapper for MotionTextEngine 0.3.0.
No NumPy or OpenCV-Python dependency. Video I/O and frame processing are native.
"""
import ctypes as C
from pathlib import Path

MTE_SOURCE_FILE = 0
MTE_SOURCE_RTSP = 1
MTE_SOURCE_UDP = 2
MTE_SOURCE_CAPTURE_DEVICE = 3
MTE_MODE_LIVE_BALANCED = 0
MTE_MODE_MOVIE_QUALITY = 1

class Rect(C.Structure):
    _fields_ = [("x", C.c_int), ("y", C.c_int), ("width", C.c_int), ("height", C.c_int)]

class Config(C.Structure):
    _fields_ = [("mode", C.c_int), ("inpaint_radius", C.c_int), ("mask_padding", C.c_int),
                ("max_corners", C.c_int), ("min_tracked_points", C.c_int),
                ("inpaint_method", C.c_int), ("live_buffer_size", C.c_int),
                ("reconnect_attempts", C.c_int), ("reconnect_delay_ms", C.c_int),
                ("movie_temporal_radius", C.c_int), ("reacquire_search_radius", C.c_int), ("reacquire_min_score", C.c_float), ("ocr_interval_frames", C.c_int),
                ("max_instances", C.c_int), ("max_absent_seconds", C.c_int),
                ("min_ocr_confidence", C.c_int)]

Progress = C.CFUNCTYPE(None, C.c_int, C.c_void_p)

class MotionText:
    def __init__(self, dll_path=None):
        path = Path(dll_path) if dll_path else Path(__file__).resolve().with_name("MotionTextEngine.dll")
        self.dll = C.WinDLL(str(path))
        self.dll.MTE_Process.argtypes = [C.c_int, C.c_wchar_p, C.c_wchar_p, Rect, C.c_wchar_p,
                                         C.POINTER(Config), Progress, C.c_void_p]
        self.dll.MTE_Process.restype = C.c_int
        self.dll.MTE_LastError.restype = C.c_char_p
        self.dll.MTE_Version.restype = C.c_char_p

    @property
    def version(self):
        return self.dll.MTE_Version().decode("ascii")

    def process(self, target_text, source, output, region=(0,0,0,0), source_type="file", mode="live",
                progress_callback=None, reconnect_attempts=3, max_instances=8, ocr_interval_frames=8):
        types = {"file": MTE_SOURCE_FILE, "rtsp": MTE_SOURCE_RTSP,
                 "udp": MTE_SOURCE_UDP, "capture": MTE_SOURCE_CAPTURE_DEVICE}
        if source_type not in types:
            raise ValueError("source_type must be file, rtsp, udp, or capture")
        if len(region) != 4:
            raise ValueError("region must be (x, y, width, height) in first-frame pixels")
        mode_id = MTE_MODE_MOVIE_QUALITY if mode == "movie" else MTE_MODE_LIVE_BALANCED
        cfg = Config(mode_id, 5, 3, 100, 12, 0, 1, reconnect_attempts, 700, 2, 160, 0.58, ocr_interval_frames, max_instances, 0, 65)
        rect = Rect(*map(int, region))
        if progress_callback:
            @Progress
            def callback(pct, _):
                progress_callback(pct)
        else:
            callback = Progress(lambda _pct, _user: None)
        rc = self.dll.MTE_Process(types[source_type], str(source), str(output),
                                  rect, str(target_text), C.byref(cfg), callback, None)
        if rc:
            message = self.dll.MTE_LastError()
            raise RuntimeError(f"MotionTextEngine error {rc}: {message.decode('utf-8', 'replace') if message else 'unknown'}")
        return output
