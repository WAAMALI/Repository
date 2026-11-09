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

typedef enum MTE_SourceType {
    MTE_SOURCE_FILE = 0,
    MTE_SOURCE_RTSP = 1,
    MTE_SOURCE_UDP = 2,
    MTE_SOURCE_CAPTURE_DEVICE = 3
} MTE_SourceType;

typedef enum MTE_Mode {
    MTE_MODE_LIVE_BALANCED = 0,
    MTE_MODE_MOVIE_QUALITY = 1
} MTE_Mode;

typedef struct MTE_Rect { int x; int y; int width; int height; } MTE_Rect;

typedef struct MTE_Config {
    int mode;                 /* MTE_Mode */
    int inpaint_radius;       /* 3..9 recommended */
    int mask_padding;         /* pixels around tracked box */
    int max_corners;          /* optical-flow features */
    int min_tracked_points;   /* feature refresh threshold */
    int inpaint_method;       /* 0=TELEA, 1=Navier-Stokes */
    int live_buffer_size;     /* live capture queue hint, normally 1 */
    int reconnect_attempts;   /* live input reconnect attempts */
    int reconnect_delay_ms;   /* delay between reconnect attempts */
    int movie_temporal_radius;/* reserved look-ahead window, 0 disables */
    int reacquire_search_radius;/* pixels around last box; 0 disables */
    float reacquire_min_score;  /* template match confidence, recommended 0.55-0.75 */
    int ocr_interval_frames;
    int max_instances;
    int max_absent_seconds;     /* 0 = no expiry */
    int min_ocr_confidence;
} MTE_Config;

typedef void (MTE_CALL *MTE_ProgressCallback)(int percent, void* user_data);

/* source:
   FILE: path to a local file
   RTSP: rtsp://...
   UDP:  udp://@239.x.x.x:port or udp://...
   CAPTURE_DEVICE: decimal camera/capture device index, e.g. "0"
   output: file path or a backend-supported stream destination.
   region is selected in pixels on the first decoded frame.
   Returns 0 on success; negative error code on failure. */
MTE_API int MTE_CALL MTE_Process(
    int source_type,
    const wchar_t* source,
    const wchar_t* output,
    MTE_Rect initial_region,
    const wchar_t* target_text,
    const MTE_Config* config,
    MTE_ProgressCallback progress,
    void* user_data
);

MTE_API const char* MTE_CALL MTE_Version(void);
MTE_API const char* MTE_CALL MTE_LastError(void);

#ifdef __cplusplus
}
#endif
