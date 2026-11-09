# MotionTextEngine v0.4.0

Windows x64 native video text-region tracking/removal engine with two processing profiles and four input classes.

## Input sources
- `file`: recorded video file
- `rtsp`: RTSP/IPTV stream
- `udp`: UDP MPEG-TS stream
- `capture`: local capture device index, e.g. `0`

## Processing profiles
- `live`: balanced low-latency processing, small capture buffer hint, bounded reconnect attempts
- `movie`: offline file processing profile. The current v0.3.1 implementation uses the same optical-flow tracker and spatial OpenCV inpainting; temporal multi-frame reconstruction is an explicit next-stage feature, not yet implemented.

## Output
Use a local output file for reliable operation. OpenCV VideoWriter network output support varies by backend/build; RTMP/UDP/RTSP output is not guaranteed by this release. For live deployments requiring guaranteed network output, integrate a dedicated FFmpeg mux/encoder output pipeline in the next iteration.

## Standalone requirements
- No NumPy or OpenCV-Python.
- Python wrapper uses only Python standard library plus the native DLL.
- EXE can run without Python.
- The GitHub workflow uses static vcpkg triplet and packages DLL + EXE + wrapper. Test on a clean Windows x64 machine before declaring fully self-contained; codec/backend availability may vary by OpenCV build.

## CLI
```powershell
MotionText.exe file "D:\video\match.mp4" "D:\video\cleaned.avi" 400 80 180 50 live
MotionText.exe rtsp "rtsp://user:pass@host:554/stream" "D:\capture\cleaned.avi" 400 80 180 50 live
MotionText.exe udp "udp://@:1234" "D:\capture\cleaned.avi" 400 80 180 50 live
MotionText.exe capture "0" "D:\capture\cleaned.avi" 400 80 180 50 live
```
Coordinates are x, y, width, height in the first decoded frame. A local output file is recommended for live inputs.

## Python (no third-party packages)
```python
from motion_text import MotionText

engine = MotionText()
engine.process(
    source="rtsp://192.168.1.10:554/live",
    output=r"D:\output\cleaned.avi",
    region=(400, 80, 180, 50),
    source_type="rtsp",
    mode="live",
)
```

## Important algorithm limits in v0.3
The user selects a rectangular region in the first frame. Sparse Lucas-Kanade optical flow tracks the region's translation. The mask is rectangular. Automatic OCR/text detection, character-level masks, robust scale/rotation estimation, temporal movie inpainting, audio passthrough, and production-grade FFmpeg network output are not included yet. The `movie_temporal_radius` field is reserved for the temporal reconstruction milestone. This release is a working architecture foundation, not yet a full broadcast-grade remover.

## Error codes
- `-1`: missing source/output
- `-2`: invalid source type
- `-3`: input source open failed
- `-4`: no first frame
- `-5`: invalid initial rectangle
- `-6`: output writer open failed
- `-7`: processing stopped after stream/tracking failure
- `-20/-21/-22`: native exception

## Build
GitHub Actions builds `MotionTextEngine.dll` and `MotionText.exe` for Windows x64 using MSVC, CMake, and vcpkg.


## v0.3.1 changes
- Separate live capture producer and processing consumer threads.
- Bounded live queue (1-4 frames); drop-oldest policy to limit latency growth.
- Corrected MSVC runtime selection to match the `x64-windows-static-md` vcpkg triplet.
- This remains a low-latency best-effort architecture, not a hard real-time guarantee.


## v0.3.2 tracking improvements
- Uses robust partial-affine estimation (RANSAC) over tracked feature points.
- Tracks in-plane translation, scale and rotation instead of translation only.
- Uses a transformed quadrilateral mask, expanded by morphology, rather than a fixed axis-aligned rectangle.
- Requires OpenCV calib3d in addition to the previous components.

Limitations remain: this is region tracking, not OCR/text understanding. Rotation/scale estimation depends on enough stable features inside the selected region. Occlusion, motion blur and low-texture glyphs can still cause drift.


## v0.3.3 recovery improvements
- Added bounded template-match reacquisition around the last known target location after optical-flow feature loss.
- Configurable search radius and minimum normalized correlation score.
- Re-detects optical-flow features after successful reacquisition.
- This improves recovery from brief occlusions or weak optical-flow frames; it is not semantic OCR and can confuse visually similar nearby patterns.


## v0.4.0 target identity and multi-instance OCR
- The user enters the target string manually.
- Matching is case-insensitive and ignores whitespace.
- Tesseract English OCR scans for exact word-level matches.
- Multiple simultaneous occurrences are supported up to `max_instances`.
- OCR runs every `ocr_interval_frames`; lower values improve short-appearance detection at higher CPU cost.
- The target identity remains configured during long absences; the scanner continues searching.
- `tessdata/eng.traineddata` is bundled by the workflow.
- Current matching is word-token based; split tokens and punctuation need sequence-aware matching in a later iteration.
- Validate against representative video before unattended operation for months.
