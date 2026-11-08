"""Isolated ROCm verification, foreground launch, and opt-in image smoke test."""
import argparse
import base64
import io
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.request


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding="utf-8")


def normal_name(name):
    return re.sub(r"\s+", " ", re.sub(r"\(tm\)|\(r\)|\bamd\b|\bati\b", "", name.lower())).strip()


def choose_device(devices, state):
    matches = [d for d in devices if d["arch"] == state["arch"]
               and normal_name(d["name"]) == normal_name(state["gpuName"])]
    if len(matches) != 1:
        raise RuntimeError("GPU name/architecture does not uniquely match the selected Windows GPU. "
                           "No device guessed. Include gpu-inventory.json and this log in a report.")
    return matches[0]


def verify(root):
    import torch
    import torch.nn.functional as F
    import torchvision  # Validate binary compatibility too.

    state = read_json(root / "state.json")
    manifest = read_json(root.parent / "manifest.json")
    if str(torch.__version__) != manifest["torch"]:
        raise RuntimeError(f"Unexpected torch version: {torch.__version__}")
    if not torch.version.hip or not torch.cuda.is_available():
        raise RuntimeError("AMD HIP runtime unavailable. Check the AMD driver; CPU/CUDA fallback refused.")
    devices = []
    for i in range(torch.cuda.device_count()):
        prop = torch.cuda.get_device_properties(i)
        devices.append(dict(index=i, name=prop.name, arch=prop.gcnArchName.split(":")[0],
                            vram_bytes=prop.total_memory))
    print(json.dumps(devices, indent=2), flush=True)
    selected = choose_device(devices, state)
    device = torch.device("cuda", selected["index"])
    torch.cuda.set_device(device)
    # HIP exposes the torch.cuda API. Check numerical output, not just enumeration.
    for dtype in (torch.float32, torch.float16):
        a = torch.full((64, 64), 0.25, device=device, dtype=dtype)
        b = a @ a
        if not torch.allclose(b.cpu().float(), torch.full((64, 64), 4.0), atol=0.02):
            raise RuntimeError(f"GPU matrix multiplication failed for {dtype}")
        x = torch.ones((1, 4, 16, 16), device=device, dtype=dtype)
        weight = torch.ones((4, 4, 3, 3), device=device, dtype=dtype)
        conv = F.conv2d(x, weight)
        if not torch.allclose(conv.cpu().float(), torch.full((1, 4, 14, 14), 36.0), atol=0.05):
            raise RuntimeError(f"GPU convolution failed for {dtype}")
        q = torch.randn((1, 2, 16, 32), device=device, dtype=dtype)
        attn = F.scaled_dot_product_attention(q, q, q)
        ref = F.scaled_dot_product_attention(q.cpu().float(), q.cpu().float(), q.cpu().float())
        if not torch.allclose(attn.cpu().float(), ref, atol=0.05, rtol=0.05):
            raise RuntimeError(f"GPU attention failed for {dtype}")
    torch.cuda.synchronize()
    result = dict(level="gpu-math-passed", image_generation_verified=False, gpu=selected,
                  torch=str(torch.__version__), torchvision=str(torchvision.__version__), hip=torch.version.hip,
                  timestamp=time.strftime("%Y-%m-%dT%H:%M:%S%z"))
    write_json(root / "gpu-verification.json", result)
    print("GPU math passed. This does not certify model loading or image generation.", flush=True)
    return selected


def request(port, route, payload=None, timeout=10):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(f"http://127.0.0.1:{port}{route}", data=data,
                                 headers={"Content-Type": "application/json"})
    # Local requests must never be routed through an inherited HTTP proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(req, timeout=timeout) as resp:
        return json.load(resp)


def launch_command(root, port, safe_mode=False):
    command = [sys.executable, "-u", "launch.py", "--skip-prepare-environment", "--skip-install",
               "--use-pytorch-cross-attention", "--disable-sage", "--disable-flash", "--disable-xformers",
               "--server-name", "127.0.0.1", "--port", str(port),
               "--api", "--autolaunch"]
    if safe_mode or not (root / "extensions-complete.json").exists():
        command.append("--disable-extra-extensions")
    return command


def launch(root, port, safe_mode=False):
    selected = verify(root)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", port))  # Fail before launch if another app owns the port.
    env = os.environ.copy()
    env["HIP_VISIBLE_DEVICES"] = str(selected["index"])
    env["CUDA_VISIBLE_DEVICES"] = str(selected["index"])
    command = launch_command(root, port, safe_mode)
    # Never execute third-party startup installers in the ROCm environment.
    env["PIP_CONSTRAINT"] = str(root / "extensions-constraints.txt") if (root / "extensions-constraints.txt").exists() else str(root / "constraints.txt")
    env["TIPO_NO_AUTO_INSTALL"] = "1"
    process = subprocess.Popen(command, cwd=root / "forge-neo", env=env)
    stop = threading.Event()

    def readiness():
        deadline = time.monotonic() + 600
        while not stop.wait(3) and time.monotonic() < deadline:
            try:
                request(port, "/sdapi/v1/options")
                write_json(root / "session.json", dict(pid=process.pid, port=port))
                print(f"[UI READY] http://127.0.0.1:{port} (image generation not yet verified)", flush=True)
                return
            except (OSError, ValueError):
                pass
        if not stop.is_set():
            print("[UI NOT VERIFIED] Startup exceeded 10 minutes. Inspect this log; Ctrl+C stops it.", flush=True)

    watcher = threading.Thread(target=readiness, daemon=True)
    watcher.start()
    try:
        code = process.wait()
        if code:
            raise RuntimeError(f"Forge Neo exited with code {code}")
    except KeyboardInterrupt:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
        print("Stopped Forge Neo.")
    finally:
        stop.set()
        watcher.join(timeout=12)
        (root / "session.json").unlink(missing_ok=True)


def generate(root, port):
    import psutil
    from PIL import Image, ImageStat

    session = read_json(root / "session.json")
    process = psutil.Process(session["pid"])
    if session["port"] != port or Path(process.cwd()).resolve() != (root / "forge-neo").resolve():
        raise RuntimeError("The managed Forge Neo session is not running on this port.")
    if "launch.py" not in process.cmdline():
        raise RuntimeError("Session process mismatch")
    if not request(port, "/sdapi/v1/sd-models"):
        raise RuntimeError("No checkpoint installed. Follow README model setup and select a model in the UI.")
    print("Generating one 512x512 test image using the currently selected model (4 steps).", flush=True)
    result = request(port, "/sdapi/v1/txt2img", dict(prompt="a red apple on a wooden table, daylight",
        negative_prompt="", seed=12345, steps=4, width=512, height=512, cfg_scale=5,
        batch_size=1, n_iter=1, sampler_name="Euler"), timeout=1800)
    images = result.get("images", [])
    if not images:
        raise RuntimeError("Generation API returned no images")
    data = base64.b64decode(images[0].split(",")[-1], validate=True)
    im = Image.open(io.BytesIO(data)).convert("RGB")
    deviation = max(ImageStat.Stat(im).stddev)
    if im.size != (512, 512) or deviation < 0.5:
        raise RuntimeError("Image is blank or has unexpected dimensions. Inspect the Forge console.")
    out = root / "verification"
    out.mkdir(exist_ok=True)
    filename = out / (time.strftime("smoke-%Y%m%d-%H%M%S") + ".png")
    im.save(filename)
    write_json(filename.with_suffix(".json"), dict(level="image-smoke-passed", image=str(filename),
               info=result.get("info"), pixel_stddev=deviation,
               note="One 4-step image only; visual quality and other models are not certified."))
    print(f"[IMAGE SMOKE PASSED] {filename}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["verify", "launch", "generate"])
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--port", type=int, default=7865)
    parser.add_argument("--safe-mode", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()
    if args.action == "verify":
        verify(root)
    elif args.action == "launch":
        launch(root, args.port, args.safe_mode)
    else:
        generate(root, args.port)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"[FAILED] {type(error).__name__}: {error}", file=sys.stderr, flush=True)
        sys.exit(1)
