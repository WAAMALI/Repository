"""Python ctypes wrapper for MotionTextEngine.dll.
Input/output frames are NumPy uint8 arrays in BGR layout (H, W, 3).
"""
import ctypes as C
from pathlib import Path
import numpy as np

class _Rect(C.Structure):
    _fields_ = [("x", C.c_int), ("y", C.c_int),
                ("width", C.c_int), ("height", C.c_int)]

class _Config(C.Structure):
    _fields_ = [("inpaint_radius", C.c_int), ("mask_padding", C.c_int),
                ("max_corners", C.c_int), ("min_tracked_points", C.c_int),
                ("inpaint_method", C.c_int), ("mask_mode", C.c_int)]

class MotionText:
    def __init__(self, dll_path=None, region=None, inpaint_radius=5, padding=2):
        path = Path(dll_path) if dll_path else Path(__file__).resolve().parents[1] / "bin" / "MotionTextEngine.dll"
        self.dll = C.CDLL(str(path))
        self._bind()
        self.handle = None
        self._size = None
        self._config = _Config(inpaint_radius, padding, 100, 12, 0, 0)
        self._initial_region = region

    def _bind(self):
        d = self.dll
        d.MTE_Create.restype = C.c_void_p
        d.MTE_Create.argtypes = [C.POINTER(C.c_uint8), C.c_int, C.c_int, C.c_int, _Rect, C.POINTER(_Config)]
        d.MTE_Process.restype = C.c_int
        d.MTE_Process.argtypes = [C.c_void_p, C.POINTER(C.c_uint8), C.c_int, C.c_int, C.c_int, C.POINTER(_Rect)]
        d.MTE_Destroy.argtypes = [C.c_void_p]
        d.MTE_Reset.restype = C.c_int
        d.MTE_Reset.argtypes = [C.c_void_p, C.POINTER(C.c_uint8), C.c_int, C.c_int, C.c_int, _Rect]

    @staticmethod
    def _validate(frame):
        a = np.ascontiguousarray(frame)
        if a.dtype != np.uint8 or a.ndim != 3 or a.shape[2] != 3:
            raise ValueError("frame must be a uint8 BGR array with shape (height, width, 3)")
        return a

    def start(self, first_frame, region=None):
        frame = self._validate(first_frame)
        region = region or self._initial_region
        if region is None or len(region) != 4:
            raise ValueError("region must be (x, y, width, height)")
        h, w = frame.shape[:2]
        self._size = (w, h)
        rect = _Rect(*map(int, region))
        ptr = frame.ctypes.data_as(C.POINTER(C.c_uint8))
        self.handle = self.dll.MTE_Create(ptr, w, h, int(frame.strides[0]), rect, C.byref(self._config))
        if not self.handle:
            raise RuntimeError("MTE_Create failed. Check region and frame dimensions.")
        return frame

    def process(self, frame):
        if not self.handle:
            raise RuntimeError("Call start(first_frame, region) before process().")
        a = self._validate(frame)
        h, w = a.shape[:2]
        if (w, h) != self._size:
            raise ValueError("All frames must have the same dimensions.")
        tracked = _Rect()
        ptr = a.ctypes.data_as(C.POINTER(C.c_uint8))
        rc = self.dll.MTE_Process(self.handle, ptr, w, h, int(a.strides[0]), C.byref(tracked))
        if rc != 0:
            raise RuntimeError(f"MTE_Process failed with code {rc}")
        return a, (tracked.x, tracked.y, tracked.width, tracked.height)

    def reset(self, frame, region):
        a = self._validate(frame)
        h, w = a.shape[:2]
        rect = _Rect(*map(int, region))
        ptr = a.ctypes.data_as(C.POINTER(C.c_uint8))
        rc = self.dll.MTE_Reset(self.handle, ptr, w, h, int(a.strides[0]), rect)
        if rc != 0:
            raise RuntimeError(f"MTE_Reset failed with code {rc}")

    def close(self):
        if self.handle:
            self.dll.MTE_Destroy(self.handle)
            self.handle = None

    def __enter__(self): return self
    def __exit__(self, *_): self.close()
