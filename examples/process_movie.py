"""Sequential offline video demo.
Usage: python examples/process_movie.py input.mp4 output.mp4 --region 420,180,240,70
"""
import argparse
import cv2
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))
from motion_text import MotionText


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--region", required=True)
    ap.add_argument("--dll", default=str(ROOT / "bin" / "MotionTextEngine.dll"))
    args = ap.parse_args()
    region = tuple(int(v) for v in args.region.split(","))
    if len(region) != 4:
        raise ValueError("--region must be x,y,width,height")

    cap = cv2.VideoCapture(args.input)
    ok, first = cap.read()
    if not ok:
        raise RuntimeError("Could not read input video")
    fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
    h, w = first.shape[:2]
    writer = cv2.VideoWriter(args.output, cv2.VideoWriter_fourcc(*"mp4v"),
                             fps, (w, h))
    if not writer.isOpened():
        raise RuntimeError("Could not open output writer")

    engine = MotionText(args.dll, region=region)
    engine.start(first)
    try:
        cleaned, _ = engine.process(first.copy())
        writer.write(cleaned)
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            cleaned, _ = engine.process(frame)
            writer.write(cleaned)
    finally:
        engine.close()
        cap.release()
        writer.release()


if __name__ == "__main__":
    main()
