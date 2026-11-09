# Architecture notes

## Live path
Capture/decoder -> one-frame processing loop -> optical-flow update -> rectangular mask -> OpenCV inpaint -> writer.
The capture buffer is requested as one frame where supported. This is a backend hint, not a hard real-time guarantee. RTSP/UDP reconnect is bounded and configurable.

## Movie path
The v0.3 API separates the movie profile from live mode so future offline temporal processing can use look-ahead and multi-frame references without adding latency to live mode. The first v0.3 implementation intentionally keeps spatial inpainting in both profiles.

## Next engineering milestones
1. Dedicated FFmpeg demux/decode/encode/mux path with audio passthrough and predictable RTSP/UDP ingest.
2. Separate bounded live queues with explicit drop-oldest policy and latency telemetry.
3. Text detector and polygon/character masks.
4. Similarity/scale/rotation tracking with reacquisition.
5. Movie-mode temporal inpainting using forward/backward frame references.
6. Automated tests with synthetic moving text and real match/movie clips.
