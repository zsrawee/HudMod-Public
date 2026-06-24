import sys, json, os

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
os.environ.setdefault("HF_HUB_DISABLE_XET", "1")

MODEL_DIR = r"C:\Windows\Temp\whisper_setup\models"
MODEL_MAP = {
    "tiny":   os.path.join(MODEL_DIR, "tiny"),
    "base":   os.path.join(MODEL_DIR, "base"),
    "small":  os.path.join(MODEL_DIR, "small"),
    "medium": os.path.join(MODEL_DIR, "medium"),
}

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

def _emit(obj: dict, out_file: str = "") -> None:
    data = (json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8")
    if out_file:
        with open(out_file, "wb") as f:
            f.write(data)
    else:
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()

def main():
    model_size = sys.argv[1] if len(sys.argv) > 1 else "base"
    audio_path = sys.argv[2] if len(sys.argv) > 2 else ""
    out_file = sys.argv[3] if len(sys.argv) > 3 else ""
    if not audio_path:
        _emit({"error": "No audio path provided"}, out_file)
        return 1

    if model_size in MODEL_MAP and os.path.isdir(MODEL_MAP[model_size]):
        model_path = MODEL_MAP[model_size]
    elif os.path.isdir(model_size) or os.path.isfile(model_size):
        model_path = model_size
    else:
        model_path = model_size

    try:
        from faster_whisper import WhisperModel
        model = WhisperModel(model_path, device="cpu", compute_type="int8")
        segments, info = model.transcribe(audio_path, beam_size=5, vad_filter=True)
        text = "".join(seg.text for seg in segments)
        _emit({
            "text": text.strip(),
            "language": info.language,
            "duration": round(info.duration, 2),
        }, out_file)
        return 0
    except Exception as e:
        _emit({"error": str(e)}, out_file)
        return 1

if __name__ == "__main__":
    sys.exit(main())
