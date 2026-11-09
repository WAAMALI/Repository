"""Low-latency live stream demo. Usage:
python examples/live_stream.py --source 0 --region 420,180,240,70
or --source rtsp://user:pass@host:554/stream
"""
import argparse
import time
import cv2
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from motion_text import MotionText


def parse_region(value):
    try:
        vals = tuple(int(v.strip()) for v in value.split(","))
        if len(vals) != 4:
            raise ValueError
        return vals
    except ValueError:
        raise argparse.ArgumentTypeError("region must be x,y,width,height")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default="0", help="camera index or RTSP/HTTP stream URL")
    ap.add_argument("--region", required=True, type=parse_region, help="initial text region x,y,w,h")
    ap.add_argument("--dll", default=str(ROOT / "bin" / "MotionTextEngine.dll"))
    ap.add_argument("--radius", type=int, default=4)
    ap.add_argument("--padding", type=int, default=2)
    args = ap.parse_args()

    source = int(args.source) if args.source.isdigit() else args.source
    cap = cv2.VideoCapture(source) if isinstance(source, int) else cv2.VideoCapture(source, cv2.CAP_FFMPEG)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    ok, first = cap.read()
    if not ok:
        raise RuntimeError("Could not read the first stream frame")

    engine = MotionText(args.dll, args.region, args.radius, args.padding)
    engine.start(first)
    last = time.perf_counter()
    fps_smooth = 0.0
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            cleaned, box = engine.process(frame)
            now = time.perf_counter()
            dt = max(now - last, 1e-6)
            last = now
            instant = 1.0 / dt
            fps_smooth = instant if fps_smooth == 0 else 0.9 * fps_smooth + 0.1 * instant
            cv2.putText(cleaned, f"Processing: {fps_smooth:.1f} FPS",
                        (18, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (40, 220, 40), 2)
            cv2.imshow("MotionTextEngine live", cleaned)
            if cv2.waitKey(1) & 0xFF == 27:
                break
    finally:
        engine.close()
        cap.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
