#pragma once
#include <stdint.h>

#if defined(_WIN32)
  #if defined(MTE_BUILD_DLL)
    #define MTE_API __declspec(dllexport)
  #else
    #define MTE_API __declspec(dllimport)
  #endif
  #define MTE_CALL __cdecl
#else
  #define MTE_API
  #define MTE_CALL
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void* MTE_Handle;

typedef struct MTE_Rect {
    int x;
    int y;
    int width;
    int height;
} MTE_Rect;

/* Kept ABI-compatible with the original 0.1.x configuration. */
typedef struct MTE_Config {
    int inpaint_radius;
    int mask_padding;
    int max_corners;
    int min_tracked_points;
    int inpaint_method;       /* 0 = TELEA, 1 = Navier-Stokes */
    int mask_mode;            /* Reserved for compatibility */
} MTE_Config;

/* Create from a BGR frame and initial approximate text region. */
MTE_API MTE_Handle MTE_CALL MTE_Create(
    const uint8_t* first_frame_bgr,
    int width, int height, int stride,
    MTE_Rect initial_region,
    const MTE_Config* config
);

/* Causal/low-latency processing. The engine uses only the current and previous
   frames. frame_bgr is modified in-place. */
MTE_API int MTE_CALL MTE_Process(
    MTE_Handle handle,
    uint8_t* frame_bgr,
    int width, int height, int stride,
    MTE_Rect* tracked_region
);

/* Preferred integration API: provide the character/text mask for this frame.
   mask is 8-bit single-channel, non-zero pixels are removed. mask_stride is
   measured in bytes. Pass confidence in [0,1]; low confidence triggers a
   conservative fallback to tracked-region processing. */
MTE_API int MTE_CALL MTE_ProcessMask(
    MTE_Handle handle,
    uint8_t* frame_bgr,
    int width, int height, int stride,
    const uint8_t* mask,
    int mask_stride,
    float confidence,
    MTE_Rect* tracked_region
);

/* Reset tracking and temporal history using a new frame and region. */
MTE_API int MTE_CALL MTE_Reset(
    MTE_Handle handle,
    const uint8_t* frame_bgr,
    int width, int height, int stride,
    MTE_Rect region
);

MTE_API void MTE_CALL MTE_Destroy(MTE_Handle handle);
MTE_API const char* MTE_CALL MTE_Version(void);

#ifdef __cplusplus
}
#endif
