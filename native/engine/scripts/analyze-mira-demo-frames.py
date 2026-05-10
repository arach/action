#!/usr/bin/env python3

import argparse
import json
import math
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[3]
SPRITE_SHEET = ROOT / "assets/pets/explorer-cat/sprites/explorer-cat.sheet.png"

DEFAULT_MOMENTS = [
    ("8", "google-search", "Google search focus"),
    ("10", "google-search", "Google search typing"),
    ("22", "midjourney-prompt", "Midjourney prompt resolve"),
    ("28", "midjourney-prompt", "Midjourney prompt typing"),
]


@dataclass
class Rect:
    x: float
    y: float
    width: float
    height: float

    @property
    def center(self):
        return (self.x + self.width / 2, self.y + self.height / 2)

    @property
    def area(self):
        return max(0, self.width) * max(0, self.height)

    def to_json(self):
        return {
            "x": round(self.x),
            "y": round(self.y),
            "width": round(self.width),
            "height": round(self.height),
        }


def main():
    args = parse_args()
    video = Path(args.video).resolve()
    if not video.exists():
        raise SystemExit(f"Missing video: {video}")

    output_dir = Path(args.output_dir or video.with_suffix("").parent / "vision-check").resolve()
    frames_dir = output_dir / "frames"
    annotated_dir = output_dir / "annotated"
    frames_dir.mkdir(parents=True, exist_ok=True)
    annotated_dir.mkdir(parents=True, exist_ok=True)

    moments = parse_moments(args.moment)
    mira_template = load_mira_template()
    cursor_template = make_cursor_template()
    results = []

    for moment in moments:
        frame_path = frames_dir / f"{moment['id']}.png"
        extract_frame(video, moment["time"], frame_path)
        frame = cv2.imread(str(frame_path), cv2.IMREAD_COLOR)
        if frame is None:
            raise SystemExit(f"Unable to read extracted frame: {frame_path}")

        height, width = frame.shape[:2]
        target = target_rect(moment["target"], width, height)
        mira = locate_mira(frame, mira_template)
        cursor = locate_cursor(frame, cursor_template)
        analysis = analyze_moment(moment, width, height, target, mira, cursor)
        annotated_path = annotated_dir / f"{moment['id']}-annotated.png"
        annotate_frame(frame_path, annotated_path, moment, target, mira, cursor, analysis)
        analysis["frame"] = str(frame_path)
        analysis["annotatedFrame"] = str(annotated_path)
        results.append(analysis)

    report = {
        "kind": "demo-key-elements",
        "video": str(video),
        "verdict": report_verdict(results),
        "summary": summarize(results),
        "keyElements": [
            "target text box",
            "Mira persona",
            "visible teaching cursor",
        ],
        "distanceRubric": {
            "greatPx": 100,
            "finePx": 200,
            "tooFarPx": 400,
        },
        "moments": results,
    }
    report_path = output_dir / "vision-report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n")

    print(f"[key-elements] verdict={report['verdict']} score={report['summary']['score']}")
    for item in results:
        print(
            "[key-elements] {grade:5} t={time:>5}s {label:26} "
            "miraGap={mira_gap:4}px cursorGap={cursor_gap:4}px :: {note}".format(
                grade=item["grade"],
                time=item["time"],
                label=item["label"][:26],
                mira_gap=round(item["miraGapPx"]) if item.get("miraGapPx") is not None else -1,
                cursor_gap=round(item["cursorGapPx"]) if item.get("cursorGapPx") is not None else -1,
                note=item["notes"][0] if item["notes"] else "",
            )
        )
    print(f"[key-elements] report={report_path}")
    if args.fail_on_bad and report["verdict"] != "good":
        raise SystemExit(1)


def parse_args():
    parser = argparse.ArgumentParser(description="Analyze real captured frames for demo key-element placement.")
    parser.add_argument("--video", required=True, help="Captured .mov/.mp4 to sample")
    parser.add_argument("--output-dir", help="Directory for extracted frames, annotations, and JSON report")
    parser.add_argument(
        "--moment",
        action="append",
        help="Moment as time:target:label, for example 10:google-search:Google typing",
    )
    parser.add_argument("--fail-on-bad", action="store_true", help="Exit non-zero unless verdict is good")
    return parser.parse_args()


def parse_moments(raw_moments):
    source = raw_moments or [":".join(item) for item in DEFAULT_MOMENTS]
    parsed = []
    for index, raw in enumerate(source):
        pieces = raw.split(":", 2)
        if len(pieces) < 2:
            raise SystemExit(f"Invalid --moment value: {raw}")
        time_text = pieces[0]
        target = pieces[1]
        label = pieces[2] if len(pieces) > 2 else target
        parsed.append(
            {
                "id": f"{index + 1:02d}-{slug(label)}",
                "time": time_text,
                "target": target,
                "label": label,
            }
        )
    return parsed


def load_mira_template():
    sheet = cv2.imread(str(SPRITE_SHEET), cv2.IMREAD_UNCHANGED)
    if sheet is None:
        raise SystemExit(f"Unable to read sprite sheet: {SPRITE_SHEET}")
    template = sheet[0:208, 0:192]
    if template.shape[2] != 4:
        raise SystemExit("Mira sprite sheet must include an alpha channel")
    return {
        "rgb": template[:, :, :3],
        "alpha": template[:, :, 3],
    }


def extract_frame(video, time_text, frame_path):
    ffmpeg = shutil.which("ffmpeg") or "/Users/art/.local/bin/ffmpeg"
    command = [
        ffmpeg,
        "-y",
        "-ss",
        str(time_text),
        "-i",
        str(video),
        "-frames:v",
        "1",
        str(frame_path),
    ]
    subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)


def locate_mira(frame, template):
    best = None
    for scale in np.linspace(0.28, 0.65, 20):
        width = max(8, int(template["rgb"].shape[1] * scale))
        height = max(8, int(template["rgb"].shape[0] * scale))
        resized = cv2.resize(template["rgb"], (width, height), interpolation=cv2.INTER_AREA)
        alpha = cv2.resize(template["alpha"], (width, height), interpolation=cv2.INTER_AREA)
        mask = (alpha > 30).astype(np.uint8) * 255
        score_map = cv2.matchTemplate(frame, resized, cv2.TM_CCORR_NORMED, mask=mask)
        _, score, _, point = cv2.minMaxLoc(score_map)
        if best is None or score > best["score"]:
            best = {
                "score": float(score),
                "rect": Rect(point[0], point[1], width, height),
                "scale": float(scale),
            }
    return best


def make_cursor_template():
    scale = 1.08
    points = np.array(
        [[0, 0], [0, -43], [12, -32], [20, -52], [29, -48], [21, -29], [38, -29]],
        dtype=np.float32,
    ) * scale
    min_x, min_y = points.min(axis=0)
    max_x, max_y = points.max(axis=0)
    pad = 8
    draw_points = np.column_stack([points[:, 0] - min_x + pad, -points[:, 1] + pad]).astype(np.int32)
    width = int(max_x - min_x + pad * 2 + 4)
    height = int(-min_y + max_y + pad * 2 + 4)
    template = np.zeros((height, width, 4), dtype=np.uint8)
    cv2.fillPoly(template, [draw_points], (255, 255, 255, 255))
    cv2.polylines(template, [draw_points], True, (10, 10, 10, 255), 2, lineType=cv2.LINE_AA)
    tip = (float(draw_points[0][0]), float(draw_points[0][1]))
    return {
        "rgb": template[:, :, :3],
        "alpha": template[:, :, 3],
        "tip": tip,
    }


def locate_cursor(frame, template):
    best = None
    for scale in np.linspace(0.75, 2.1, 28):
        width = max(8, int(template["rgb"].shape[1] * scale))
        height = max(8, int(template["rgb"].shape[0] * scale))
        resized = cv2.resize(template["rgb"], (width, height), interpolation=cv2.INTER_AREA)
        alpha = cv2.resize(template["alpha"], (width, height), interpolation=cv2.INTER_AREA)
        mask = (alpha > 30).astype(np.uint8) * 255
        score_map = cv2.matchTemplate(frame, resized, cv2.TM_CCORR_NORMED, mask=mask)
        _, score, _, point = cv2.minMaxLoc(score_map)
        if best is None or score > best["score"]:
            tip_x = point[0] + template["tip"][0] * scale
            tip_y = point[1] + template["tip"][1] * scale
            best = {
                "score": float(score),
                "rect": Rect(point[0], point[1], width, height),
                "tip": (tip_x, tip_y),
                "scale": float(scale),
            }
    return best


def target_rect(name, width, height):
    targets = {
        "omnibox": (0.255, 0.018, 0.49, 0.036),
        "google-search": (0.30, 0.335, 0.40, 0.07),
        "midjourney-prompt": (0.13, 0.055, 0.68, 0.052),
        "inspection-rail": (0.78, 0.09, 0.18, 0.52),
        "artifact-beat": (0.76, 0.08, 0.20, 0.28),
    }
    if name not in targets:
        raise SystemExit(f"Unknown target: {name}")
    rx, ry, rw, rh = targets[name]
    return Rect(width * rx, height * ry, width * rw, height * rh)


def analyze_moment(moment, width, height, target, mira, cursor):
    notes = []
    grade = "good"
    if mira is None or mira["score"] < 0.84:
        return {
            "time": moment["time"],
            "label": moment["label"],
            "targetName": moment["target"],
            "grade": "bad",
            "notes": ["Mira key element was not confidently detected in the captured frame"],
            "frameSize": {"width": width, "height": height},
            "target": rect_payload(target),
            "mira": None,
            "cursor": cursor_payload(cursor) if cursor else None,
            "miraGapPx": None,
            "cursorGapPx": None,
        }

    mira_rect = mira["rect"]
    mira_center = mira_rect.center
    mira_gap = distance_to_rect(mira_center, target)
    vertical_delta = mira_center[1] - target.center[1]
    overlap = overlap_area(target, mira_rect) / target.area if target.area else 0
    cursor_gap = None

    if mira_gap > 400:
        grade = "bad"
        notes.append(f"Mira is {round(mira_gap)}px from the text box; 400px is too detached")
    elif mira_gap > 260:
        grade = "watch"
        notes.append(f"Mira is pushing the edge of proximity ({round(mira_gap)}px from the text box)")
    elif mira_gap < 35:
        grade = "watch"
        notes.append(f"Mira is too tucked into the text box ({round(mira_gap)}px gap)")
    elif mira_gap < 75 and overlap > 0.03:
        grade = "watch"
        notes.append("Mira is close enough to risk crowding the text box")

    if overlap > 0.12:
        grade = "bad"
        notes.append(f"Mira overlaps {round(overlap * 100)}% of the target zone")
    elif overlap > 0.03 and grade == "good":
        grade = "watch"
        notes.append(f"Mira slightly overlaps the target zone ({round(overlap * 100)}%)")

    if cursor is not None and cursor["score"] >= 0.88:
        cursor_gap = distance_to_rect(cursor["tip"], target)
        if cursor_gap > 400:
            grade = "bad"
            notes.append(f"cursor tip is {round(cursor_gap)}px from the text box")
        elif cursor_gap > 240 and grade == "good":
            grade = "watch"
            notes.append(f"cursor tip is a little detached ({round(cursor_gap)}px)")
    elif "resolve" in moment["label"].lower():
        if grade == "good":
            grade = "watch"
        notes.append("cursor was not confidently detected in this captured frame")

    if not notes:
        notes.append("Mira/cursor are visually tied to the text box without covering it")

    return {
        "time": moment["time"],
        "label": moment["label"],
        "targetName": moment["target"],
        "grade": grade,
        "notes": notes,
        "frameSize": {"width": width, "height": height},
        "target": rect_payload(target),
        "mira": {
            **rect_payload(mira_rect),
            "matchScore": round(mira["score"], 4),
            "scale": round(mira["scale"], 3),
        },
        "cursor": cursor_payload(cursor) if cursor else None,
        "miraGapPx": round(mira_gap, 1),
        "cursorGapPx": round(cursor_gap, 1) if cursor_gap is not None else None,
        "verticalDeltaPx": round(vertical_delta, 1),
        "targetOverlapPercent": round(overlap * 100, 1),
    }


def rect_payload(rect):
    cx, cy = rect.center
    return {
        **rect.to_json(),
        "center": {"x": round(cx), "y": round(cy)},
    }


def cursor_payload(cursor):
    if cursor is None:
        return None
    tip_x, tip_y = cursor["tip"]
    return {
        **rect_payload(cursor["rect"]),
        "tip": {"x": round(tip_x), "y": round(tip_y)},
        "matchScore": round(cursor["score"], 4),
        "scale": round(cursor["scale"], 3),
    }


def annotate_frame(frame_path, output_path, moment, target, mira, cursor, analysis):
    image = Image.open(frame_path).convert("RGBA")
    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default()

    target_xy = [
        target.x,
        target.y,
        target.x + target.width,
        target.y + target.height,
    ]
    draw.rectangle(target_xy, outline=(80, 220, 150, 255), width=5)
    draw.text((target.x + 8, max(8, target.y - 20)), f"target: {moment['target']}", fill=(80, 220, 150, 255), font=font)

    if mira is not None:
        rect = mira["rect"]
        mira_xy = [rect.x, rect.y, rect.x + rect.width, rect.y + rect.height]
        draw.rectangle(mira_xy, outline=(255, 105, 90, 255), width=5)
        draw.text((rect.x + 6, max(8, rect.y - 20)), "Mira", fill=(255, 105, 90, 255), font=font)
        draw.line([target.center, rect.center], fill=(255, 210, 90, 255), width=4)

    if cursor is not None and cursor["score"] >= 0.88:
        rect = cursor["rect"]
        tip = cursor["tip"]
        cursor_xy = [rect.x, rect.y, rect.x + rect.width, rect.y + rect.height]
        draw.rectangle(cursor_xy, outline=(120, 180, 255, 255), width=4)
        draw.ellipse([tip[0] - 7, tip[1] - 7, tip[0] + 7, tip[1] + 7], fill=(120, 180, 255, 255))
        draw.text((rect.x + 6, max(8, rect.y - 20)), "cursor", fill=(120, 180, 255, 255), font=font)
        draw.line([nearest_point_on_rect(tip, target), tip], fill=(120, 180, 255, 255), width=3)

    badge_width = 650
    badge_height = 86
    draw.rectangle([16, 16, badge_width, badge_height], fill=(6, 7, 8, 220), outline=(255, 255, 255, 60), width=2)
    draw.text((30, 30), f"{analysis['grade'].upper()} · {moment['label']} @ {moment['time']}s", fill=(255, 255, 255, 255), font=font)
    draw.text((30, 54), analysis["notes"][0], fill=(230, 230, 220, 255), font=font)

    image.save(output_path)


def report_verdict(results):
    if any(item["grade"] == "bad" for item in results):
        return "bad"
    if any(item["grade"] == "watch" for item in results):
        return "needs-tuning"
    return "good"


def summarize(results):
    score = 100
    for item in results:
        if item["grade"] == "bad":
            score -= 24
        elif item["grade"] == "watch":
            score -= 10
    return {
        "score": max(0, score),
        "badMoments": sum(1 for item in results if item["grade"] == "bad"),
        "watchMoments": sum(1 for item in results if item["grade"] == "watch"),
    }


def overlap_area(a, b):
    x = max(0, min(a.x + a.width, b.x + b.width) - max(a.x, b.x))
    y = max(0, min(a.y + a.height, b.y + b.height) - max(a.y, b.y))
    return x * y


def distance_to_rect(point, rect):
    x, y = point
    dx = max(rect.x - x, 0, x - (rect.x + rect.width))
    dy = max(rect.y - y, 0, y - (rect.y + rect.height))
    return math.hypot(dx, dy)


def nearest_point_on_rect(point, rect):
    x, y = point
    return (
        min(max(x, rect.x), rect.x + rect.width),
        min(max(y, rect.y), rect.y + rect.height),
    )


def slug(text):
    return "".join(ch.lower() if ch.isalnum() else "-" for ch in text).strip("-")


if __name__ == "__main__":
    main()
