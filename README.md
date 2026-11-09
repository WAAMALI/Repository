# MotionTextEngine 0.3.0-live

A C++17 / OpenCV DLL for low-latency removal of moving text regions from video.
Python integrates through `ctypes`.

## Target workloads

- Live sports broadcasts: fast camera pans, zooms, cuts, and busy moving scenes.
- Film/video files: sequential processing with temporal background compensation.
- Text detector integration: another project may provide a per-frame binary character mask.
  This engine owns tracking, motion compensation, removal, and frame-to-frame state.

## Processing design

1. **Target tracking:** pyramidal Lucas-Kanade optical flow plus robust similarity-transform
   estimation (translation, rotation, and scale). It does not depend on font colour.
2. **Detector handoff:** `MTE_ProcessMask` accepts an 8-bit mask for the current frame.
   This is the preferred path when the companion project can provide character shapes.
3. **Background motion:** estimates a robust global background transform using features
   outside the text mask.
4. **Temporal repair:** warps the previous *cleaned* frame into the current camera position.
   The warped pixels are used only in the eroded interior of the text mask when the
   background-motion estimate is sufficiently reliable.
5. **Scene-cut guard:** large frame changes outside the mask disable temporal reuse so an old
   scene is not pasted into a new shot.
6. **Fallback repair:** OpenCV TELEA or Navier-Stokes inpainting fills the mask and its edges.
7. **ROI processing:** spatial inpainting is restricted to a crop around the mask to reduce
   per-frame work.

## Live and file-processing behaviour

The native engine is **causal**: it uses the current frame and the immediately previous
frame only. This avoids waiting for future frames and is the correct low-latency baseline
for live streams. It does not introduce an intentional multi-frame look-ahead delay.

For movies, process frames in order. This version uses the same causal repair. A separate
offline look-ahead mode (using future frames and shot-boundary-aware temporal filling) is
not yet implemented. It is intentionally not claimed as available because future-frame
reconstruction needs additional occlusion and scene-cut handling.

## Important limitations

- No algorithm can recover hidden background detail if it is never visible in any usable
  frame. In such regions, inpainting is an estimate, not a guaranteed reconstruction.
- Sports footage contains players, ball motion, camera pans, zooms, replays, scoreboards,
  and scene cuts. A global affine transform models dominant camera motion, not every
  independently moving player or object. A scene-cut guard disables temporal reuse on large
  changes, but moving objects behind the text can still leave stale pixels or artifacts.
- For best quality, the companion detector should send a tight mask around glyph pixels,
  including antialiasing, for each frame. Confidence below 0.35 triggers tracked-region
  fallback.
- The current engine does not perform OCR or discover text by itself. It expects an initial
  selected region or a mask from the companion detector.
- The engine is not a broadcast-grade guarantee. Validate on representative streams,
  resolutions, frame rates, and hardware before production use.

## Build on GitHub Actions

1. Push this source tree to GitHub.
2. Open **Actions** and run **Build MotionTextEngine DLL**.
3. Download `MotionTextEngine-windows-x64` from the completed workflow.
4. Use 64-bit Python with the x64 DLL.

The workflow builds with MSVC, CMake, and vcpkg OpenCV.

## Python integration

```python
import cv2
from motion_text import MotionText

cap = cv2.VideoCapture("input.mp4")
ok, first = cap.read()
if not ok:
    raise RuntimeError("Cannot read input")

# Approximate initial text area: x, y, width, height
engine = MotionText(
    dll_path="bin/MotionTextEngine.dll",
    region=(420, 180, 240, 70),
    inpaint_radius=4,
    padding=2,
)
engine.start(first)

try:
    # If the companion project supplies a binary mask per frame:
    # mask: uint8 (height, width), text pixels > 0, background = 0
    #
    # cleaned, box = engine.process_mask(frame, mask, confidence=0.98)

    # Without an external per-frame mask:
    cleaned, box = engine.process(first.copy())
finally:
    engine.close()
    cap.release()
```

For a live stream, read each frame and call `process` or `process_mask` immediately.
Do not accumulate a large queue in the host application; that would add avoidable latency.

## Native API

- `MTE_Create`: initialize from first BGR frame and an approximate region.
- `MTE_Process`: track the region and remove it using a generated rectangular mask.
- `MTE_ProcessMask`: preferred API; use the supplied per-frame character mask.
- `MTE_Reset`: reset tracker and temporal history after a scene cut or manual reselection.
- `MTE_Destroy`: release native resources.
- `MTE_Version`: returns `0.3.0-live`.

## Build requirements

- C++17 compiler
- OpenCV modules: `core`, `imgproc`, `video`, `videoio`, `photo`, `calib3d`
- Windows x64 for the provided GitHub Actions workflow

## Integration contract with the companion detector

Recommended per-frame payload:

- `mask`: 8-bit single-channel mask, same width and height as the video frame.
- `confidence`: float in `[0, 1]`.
- Mask pixels: non-zero means remove; zero means preserve.
- The detector should not send font colour as a required feature. Shape/mask is sufficient.
- If the detector loses the text or a scene cut occurs, call `MTE_Reset` with a fresh region
  and frame to reinitialize temporal state.


## Included examples

- `examples/live_stream.py`: webcam or RTSP/HTTP live stream preview. It requests a
  one-frame capture buffer where the backend supports it and processes frames immediately.
- `examples/process_movie.py`: sequential processing of a recorded movie.

The examples use the rectangle fallback. For the best results, connect the companion
character detector and call `process_mask(frame, mask, confidence)` on each frame.
