"""ctypes wrapper for MotionTextEngine 0.3.0-live.

Frames: uint8 BGR NumPy arrays (H, W, 3).
Masks: uint8 grayscale arrays (H, W), non-zero pixels are removed.
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
    def __init__(self, dll_path=None, region=None, inpaint_radius=4,
                 padding=2, max_corners=250, min_tracked_points=20):
        path = (Path(dll_path) if dll_path else
                Path(__file__).resolve().parents[1] / "bin" / "MotionTextEngine.dll")
        self.dll = C.CDLL(str(path))
        self._bind()
        self.handle = None
        self._size = None
        self._config = _Config(inpaint_radius, padding, max_corners,
                               min_tracked_points, 0, 0)
        self._initial_region = region

    def _bind(self):
        d = self.dll
        d.MTE_Create.restype = C.c_void_p
        d.MTE_Create.argtypes = [C.POINTER(C.c_uint8), C.c_int, C.c_int,
                                 C.c_int, _Rect, C.POINTER(_Config)]
        d.MTE_Process.restype = C.c_int
        d.MTE_Process.argtypes = [C.c_void_p, C.POINTER(C.c_uint8), C.c_int,
                                  C.c_int, C.c_int, C.POINTER(_Rect)]
        d.MTE_ProcessMask.restype = C.c_int
        d.MTE_ProcessMask.argtypes = [
            C.c_void_p, C.POINTER(C.c_uint8), C.c_int, C.c_int, C.c_int,
            C.POINTER(C.c_uint8), C.c_int, C.c_float, C.POINTER(_Rect)
        ]
        d.MTE_Reset.restype = C.c_int
        d.MTE_Reset.argtypes = [C.c_void_p, C.POINTER(C.c_uint8), C.c_int,
                                C.c_int, C.c_int, _Rect]
        d.MTE_Destroy.argtypes = [C.c_void_p]
        d.MTE_Version.restype = C.c_char_p

    @staticmethod
    def _validate_frame(frame):
        a = np.asarray(frame)
        if a.dtype != np.uint8 or a.ndim != 3 or a.shape[2] != 3:
            raise ValueError("frame must be uint8 BGR with shape (H, W, 3)")
        return np.ascontiguousarray(a)

    @staticmethod
    def _validate_mask(mask, shape):
        m = np.asarray(mask)
        if m.ndim == 3:
            if m.shape[2] == 3:
                # Accept a binary BGR mask but collapse it to grayscale.
                m = np.max(m, axis=2)
            else:
                raise ValueError("mask must be HxW grayscale or HxWx3")
        if m.dtype != np.uint8 or m.shape != shape:
            raise ValueError("mask must be uint8 and match frame height/width")
        return np.ascontiguousarray(m)

    @property
    def version(self):
        return self.dll.MTE_Version().decode("ascii", errors="replace")

    def start(self, first_frame, region=None):
        frame = self._validate_frame(first_frame)
        region = region if region is not None else self._initial_region
        if region is None or len(region) != 4:
            raise ValueError("region must be (x, y, width, height)")
        self.close()
        h, w = frame.shape[:2]
        self._size = (w, h)
        rect = _Rect(*map(int, region))
        ptr = frame.ctypes.data_as(C.POINTER(C.c_uint8))
        self.handle = self.dll.MTE_Create(
            ptr, w, h, int(frame.strides[0]), rect, C.byref(self._config))
        if not self.handle:
            raise RuntimeError("MTE_Create failed; check region and frame dimensions.")
        return frame

    def _check_frame(self, frame):
        if not self.handle:
            raise RuntimeError("Call start(first_frame, region) before processing.")
        a = self._validate_frame(frame)
        h, w = a.shape[:2]
        if (w, h) != self._size:
            raise ValueError("All frames must have the same dimensions.")
        return a, w, h

    def process(self, frame):
        """Fast causal path: track the selected region and remove it."""
        a, w, h = self._check_frame(frame)
        tracked = _Rect()
        ptr = a.ctypes.data_as(C.POINTER(C.c_uint8))
        rc = self.dll.MTE_Process(self.handle, ptr, w, h,
                                  int(a.strides[0]), C.byref(tracked))
        if rc != 0:
            raise RuntimeError(f"MTE_Process failed with code {rc}")
        return a, (tracked.x, tracked.y, tracked.width, tracked.height)

    def process_mask(self, frame, mask, confidence=1.0):
        """Preferred path when the detector supplies a fresh character mask.

        confidence is in [0, 1]. Masks below 0.35 are ignored by native code
        and the tracked-region fallback is used.
        """
        a, w, h = self._check_frame(frame)
        m = self._validate_mask(mask, (h, w))
        confidence = float(np.clip(confidence, 0.0, 1.0))
        tracked = _Rect()
        fp = a.ctypes.data_as(C.POINTER(C.c_uint8))
        mp = m.ctypes.data_as(C.POINTER(C.c_uint8))
        rc = self.dll.MTE_ProcessMask(
            self.handle, fp, w, h, int(a.strides[0]),
            mp, int(m.strides[0]), confidence, C.byref(tracked))
        if rc != 0:
            raise RuntimeError(f"MTE_ProcessMask failed with code {rc}")
        return a, (tracked.x, tracked.y, tracked.width, tracked.height)

    def reset(self, frame, region):
        a = self._validate_frame(frame)
        h, w = a.shape[:2]
        if self.handle is None:
            raise RuntimeError("Engine is not started.")
        if (w, h) != self._size:
            raise ValueError("Reset frame dimensions must match the session.")
        rect = _Rect(*map(int, region))
        ptr = a.ctypes.data_as(C.POINTER(C.c_uint8))
        rc = self.dll.MTE_Reset(self.handle, ptr, w, h,
                                int(a.strides[0]), rect)
        if rc != 0:
            raise RuntimeError(f"MTE_Reset failed with code {rc}")

    def close(self):
        if getattr(self, "handle", None):
            self.dll.MTE_Destroy(self.handle)
            self.handle = None
            self._size = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()
