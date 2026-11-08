"""Install a reviewed, pinned EasyForgeNeo extension set without upstream installers.

Called only by Manage.ps1 after ownership, GPU, revision and operation-lock checks.
The base packages are frozen: incompatible dependencies fail before pip changes them.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def save_json(path, value):
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, indent=2, ensure_ascii=False), encoding="utf-8")
    tmp.replace(path)


def run(args, capture=False):
    print("> " + " ".join(map(str, args)), flush=True)
    result = subprocess.run(list(map(str, args)), check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def validate_catalog(catalog):
    names = set()
    for ext in catalog["extensions"]:
        name = ext["name"]
        if not re.fullmatch(r"[A-Za-z0-9_-]+", name) or name.lower() in names:
            raise ValueError("Invalid or duplicate extension name")
        names.add(name.lower())
        if not re.fullmatch(r"https://github\.com/[A-Za-z0-9_-]+/" + re.escape(name) + r"\.git", ext["url"]):
            raise ValueError("Invalid extension source")
        if not re.fullmatch(r"[0-9a-f]{40}", ext["commit"]):
            raise ValueError("Extension revision must be pinned")


def freeze_constraints(packages):
    lines = []
    for pkg in packages:
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", pkg["name"]):
            raise ValueError("Invalid package name")
        if not re.fullmatch(r"[A-Za-z0-9_.+!-]+", pkg["version"]):
            raise ValueError("Invalid package version")
        lines.append(pkg["name"] + "==" + pkg["version"])
    return "\n".join(sorted(lines)) + "\n"


def add_default_disabled(config):
    # Match EasyForgeNeo's choice without replacing the user's other preferences.
    disabled = config.setdefault("disabled_extensions", [])
    if not isinstance(disabled, list):
        raise ValueError("disabled_extensions must be a list")
    if "model-keyword" not in disabled:
        disabled.append("model-keyword")
    return config


def assert_no_links(path):
    for current, dirs, files in os.walk(path):
        for name in dirs + files:
            entry = Path(current) / name
            if entry.is_symlink() or entry.is_junction():
                raise RuntimeError(f"Link refused: {entry}")


def install(root):
    catalog = read_json(root.parent / "extensions.json")
    validate_catalog(catalog)
    git = os.environ["GIT_PYTHON_GIT_EXECUTABLE"]
    neo = root / "forge-neo"
    destination = neo / "extensions"
    destination.mkdir(exist_ok=True)
    ownership_file = root / "extensions-owned.json"
    owned = read_json(ownership_file) if ownership_file.exists() else {}
    # Refuse to adopt or overwrite manually installed extensions, even the same URL.
    for ext in catalog["extensions"]:
        target = destination / ext["name"]
        if target.exists():
            if owned.get(ext["name"]) != ext["commit"]:
                raise RuntimeError(f"Existing unmanaged extension: {target}. Nothing overwritten.")
            if run([git, "-C", target, "rev-parse", "HEAD"], True) != ext["commit"]:
                raise RuntimeError(f"Extension revision changed: {target}")
            if run([git, "-C", target, "diff", "--name-only", "HEAD"], True):
                raise RuntimeError(f"Tracked extension files modified: {target}")

    completed = root / "extensions-complete.json"
    if completed.exists():
        if read_json(completed)["extensions"] != catalog["extensions"]:
            raise RuntimeError("Extension catalog changed. Use a fresh installation for this version.")
        if any(not (destination / ext["name"]).is_dir() for ext in catalog["extensions"]):
            raise RuntimeError("An installed extension is missing. Use a fresh install or restore its original directory.")
        run([sys.executable, "-m", "pip", "check"])
        print("Extensions already installed. No updates or reinstalls performed.")
        return

    # Fetch first; never run extension install.py, and never modify existing files.
    staging = Path(tempfile.mkdtemp(prefix="extensions-", dir=root / "temp"))
    for ext in catalog["extensions"]:
        if (destination / ext["name"]).exists():
            continue
        target = staging / ext["name"]
        run([git, "init", target])
        run([git, "-C", target, "remote", "add", "origin", ext["url"]])
        run([git, "-C", target, "fetch", "--depth", "1", "origin", ext["commit"]])
        run([git, "-C", target, "checkout", "--detach", "FETCH_HEAD"])
        if run([git, "-C", target, "rev-parse", "HEAD"], True) != ext["commit"]:
            raise RuntimeError("Extension commit verification failed")
        assert_no_links(target)

    constraints = root / "extensions-constraints.txt"
    packages = json.loads(run([sys.executable, "-m", "pip", "list", "--format=json"], True))
    constraints.write_text(freeze_constraints(packages), encoding="utf-8")
    requirements = root.parent / "requirements-extensions.txt"
    pip_args = [sys.executable, "-m", "pip", "install", "--index-url", "https://pypi.org/simple",
                "-c", constraints, "-r", requirements]
    run(pip_args + ["--dry-run", "--report", root / "extensions-dependency-plan.json"])
    run(pip_args)
    run([sys.executable, "-m", "pip", "check"])
    run([sys.executable, Path(__file__).with_name("runtime.py"), "verify", "--root", root])
    # Prepare config before activation. Never copy NVIDIA settings or authentication.
    config_path = neo / "config.json"
    config = read_json(config_path) if config_path.exists() else {}
    config = add_default_disabled(config)
    if config_path.exists():
        backup = root / "config-before-extensions.json"
        if not backup.exists():
            backup.write_bytes(config_path.read_bytes())
    save_json(config_path, config)
    for ext in catalog["extensions"]:
        target = destination / ext["name"]
        if not target.exists():
            # Journal before move: an interrupted run can resume these exact commits.
            owned[ext["name"]] = ext["commit"]
            save_json(ownership_file, owned)
            (staging / ext["name"]).rename(target)
    save_json(completed, {"extensions": catalog["extensions"], "gpu_ui_tested": False})
    print("14 extensions installed. Run 03_Launch.bat; use 07_LaunchSafe.bat if startup fails.")
    print("UI/image generation remain unverified. See README for optional services and model downloads.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    args = parser.parse_args()
    try:
        install(args.root.resolve())
    except Exception as error:
        print(f"[EXTENSIONS FAILED] {error}", file=sys.stderr)
        print("Activation was not completed. Retry 06_InstallExtensions.bat after fixing the cause; use 07_LaunchSafe.bat for recovery.")
        sys.exit(1)
