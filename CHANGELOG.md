# Changelog

## 0.3.0-live
- Added per-frame external character-mask API (`MTE_ProcessMask`).
- Added robust similarity-transform tracking for target translation, scale, and rotation.
- Added background-motion estimation outside the text mask.
- Added causal temporal repair from the previous cleaned frame with inpainting fallback.
- Improved Python wrapper lifecycle, validation, and mask support.
- Kept the original `MTE_Create`, `MTE_Process`, `MTE_Reset`, and `MTE_Destroy` entry points.

## 0.1.0
- Initial sparse optical-flow rectangle tracker and OpenCV inpainting.
