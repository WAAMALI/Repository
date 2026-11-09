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

typedef struct MTE_Config {
    int inpaint_radius;       /* Recommended: 3-7 */
    int mask_padding;         /* Expand selected text region in pixels */
    int max_corners;          /* Optical-flow features, e.g. 100 */
    int min_tracked_points;   /* Re-detect features below this count */
    int inpaint_method;       /* 0 = TELEA, 1 = Navier-Stokes */
    int mask_mode;            /* 0 = solid tracked rectangle */
} MTE_Config;

/* Returns nullptr on failure. The first frame must be BGR uint8. */
MTE_API MTE_Handle MTE_CALL MTE_Create(
    const uint8_t* first_frame_bgr,
    int width, int height, int stride,
    MTE_Rect initial_region,
    const MTE_Config* config
);

/* Tracks the selected region and inpaints it in-place.
   frame_bgr must be writable BGR uint8 with the same dimensions.
   Returns 0 on success, negative value on error. */
MTE_API int MTE_CALL MTE_Process(
    MTE_Handle handle,
    uint8_t* frame_bgr,
    int width, int height, int stride,
    MTE_Rect* tracked_region
);

/* Reset tracking using a new frame and region. */
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
