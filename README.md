# MotionTextEngine

A small Windows x64 C++ DLL for tracking a user-selected moving video region and removing it with OpenCV inpainting. Python calls it through `ctypes`.

## Current scope (0.1.0)

- User selects a tight rectangle around the target word in the first frame.
- Sparse Lucas-Kanade optical flow follows features inside that region.
- The tracked rectangle is expanded by `mask_padding` and inpainted.
- Frames are processed one at a time. The DLL does not load the full video.
- No GUI and no OCR dependency.

## Important limitations

This first implementation tracks the selected **region**, not semantic text identity. Keep the initial selection tight around the word. The current mask is a rectangle, so it may erase some nearby background. Optical flow can drift when the selected region has few visual features, is heavily blurred, is occluded, or leaves the frame. For difficult footage, the next iteration should add polygon/character masks, scale-and-rotation estimation, confidence scoring, and re-detection/reacquisition.

OpenCV `inpaint` is intended for relatively small damaged regions. It does not guarantee convincing reconstruction over large or highly textured backgrounds.

## Build on GitHub

1. Create a GitHub repository and upload this project.
2. Open **Actions**.
3. Select **Build MotionTextEngine DLL**.
4. Press **Run workflow**.
5. When complete, open the workflow run and download the `MotionTextEngine-windows-x64` artifact.

The workflow builds an x64 DLL on `windows-latest` using MSVC, CMake, and vcpkg.

## Python usage

Requires Python with NumPy and OpenCV-Python for video decoding/encoding in your host application.

```python
import cv2
from motion_text import MotionText

cap = cv2.VideoCapture("input.mp4")
ok, first = cap.read()
if not ok:
    raise RuntimeError("Cannot read video")

# Tight rectangle around the moving word: x, y, width, height
engine = MotionText(
    dll_path="bin/MotionTextEngine.dll",
    region=(420, 180, 190, 48),
    inpaint_radius=5,
    padding=3,
)
engine.start(first)

writer = cv2.VideoWriter(
    "output.mp4",
    cv2.VideoWriter_fourcc(*"mp4v"),
    cap.get(cv2.CAP_PROP_FPS),
    (first.shape[1], first.shape[0]),
)

try:
    # Process the first frame separately if it also needs removal.
    processed, _ = engine.process(first.copy())
    writer.write(processed)

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        cleaned, tracked_box = engine.process(frame)
        writer.write(cleaned)
finally:
    engine.close()
    cap.release()
    writer.release()
```

## API

- `MTE_Create(...)`: initialize tracking from the first BGR frame and target rectangle.
- `MTE_Process(...)`: track and inpaint one BGR frame in-place.
- `MTE_Reset(...)`: reinitialize on a frame and a new rectangle.
- `MTE_Destroy(...)`: release native resources.
- `MTE_Version()`: return engine version.

## Configuration

- `inpaint_radius`: OpenCV inpaint radius, typically 3-7.
- `mask_padding`: expand the tracked rectangle around the target.
- `max_corners`: maximum optical-flow features.
- `min_tracked_points`: replenish features when fewer remain.
- `inpaint_method`: `0` TELEA, `1` Navier-Stokes.

## Notes

- The DLL exports a C ABI to keep Python `ctypes` integration straightforward.
- Match Python and DLL architecture: use 64-bit Python with the x64 artifact.
- This repository is a source/build starter. The DLL is produced by GitHub Actions, not included in source control.
