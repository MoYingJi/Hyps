#!/usr/bin/env python3
# /// script
# requires-python = ">=3.8"
# dependencies = ["UnityPy==1.25.4"]
# ///
"""Validate and patch the graphics API list in one Genshin globalgamemanagers file."""

from __future__ import annotations

import argparse
import os
import stat
import sys
import tempfile
from pathlib import Path
from typing import Any

EXPECTED_UNITY_VERSION = "2017.4.30f1"
DEFAULT_APIS = [2, 18]
D3D12_APIS = [18]


class PatchError(RuntimeError):
    pass


def load_unitypy() -> Any:
    try:
        import UnityPy
    except ImportError as exc:
        raise PatchError(
            "UnityPy is required. Install it into this Python environment with "
            "`python3 -m pip install UnityPy`, or use a virtual environment."
        ) from exc
    return UnityPy


def read_build_settings(path: Path) -> tuple[Any, Any, dict[str, Any]]:
    if path.is_symlink() or not path.is_file():
        raise PatchError(f"Target must be a regular, non-symlink file: {path}")

    UnityPy = load_unitypy()
    try:
        env = UnityPy.load(str(path))
        if len(env.files) != 1:
            raise PatchError(
                f"Expected one serialized Unity file, found {len(env.files)}: {path}"
            )
        serialized_file = next(iter(env.files.values()))
        unity_version = getattr(serialized_file, "unity_version", "")
        if unity_version != EXPECTED_UNITY_VERSION:
            raise PatchError(
                f"Unexpected Unity version {unity_version!r}; expected "
                f"{EXPECTED_UNITY_VERSION!r}. Refusing to patch this build."
            )
        build_settings = [
            obj for obj in env.objects if obj.type.name == "BuildSettings"
        ]
        if len(build_settings) != 1:
            raise PatchError(
                f"Expected exactly one BuildSettings object, found "
                f"{len(build_settings)}: {path}"
            )
        obj = build_settings[0]
        tree = obj.read_typetree()
        if "m_GraphicsAPIs" not in tree:
            raise PatchError(f"BuildSettings has no m_GraphicsAPIs field: {path}")
        apis = tree["m_GraphicsAPIs"]
        if not isinstance(apis, list) or not all(type(api) is int for api in apis):
            raise PatchError(f"Unexpected m_GraphicsAPIs value in {path}: {apis!r}")
        return serialized_file, obj, tree
    except PatchError:
        raise
    except Exception as exc:
        raise PatchError(f"Could not parse Unity BuildSettings in {path}: {exc}") from exc


def fsync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def patch_file(path: Path, mode: str) -> None:
    target_apis = D3D12_APIS if mode == "d3d12" else DEFAULT_APIS
    serialized_file, obj, tree = read_build_settings(path)
    current_apis = tree["m_GraphicsAPIs"]
    if current_apis not in (DEFAULT_APIS, D3D12_APIS):
        raise PatchError(
            f"Unsupported existing graphics API list {current_apis}; expected "
            f"{DEFAULT_APIS} or {D3D12_APIS}. Refusing to patch."
        )
    if current_apis == target_apis:
        print(f"Graphics API list already {target_apis}; unchanged: {path}")
        return

    tree["m_GraphicsAPIs"] = target_apis.copy()
    try:
        obj.save_typetree(tree)
        output = serialized_file.save()
    except Exception as exc:
        raise PatchError(f"UnityPy could not serialize the patch: {exc}") from exc

    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(output)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp_path, stat.S_IMODE(path.stat().st_mode))
        _, _, verified_tree = read_build_settings(temp_path)
        verified_apis = verified_tree["m_GraphicsAPIs"]
        if verified_apis != target_apis:
            raise PatchError(
                f"Post-write verification returned {verified_apis}, expected "
                f"{target_apis}; target was not changed."
            )
        os.replace(temp_path, path)
        fsync_directory(path.parent)
    finally:
        temp_path.unlink(missing_ok=True)

    print(f"Patched graphics APIs {current_apis} -> {target_apis}: {path}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate and patch one Genshin globalgamemanagers file. This tool does "
            "not locate files or mount overlays."
        )
    )
    parser.add_argument(
        "--mode",
        choices=("default", "d3d12"),
        default="d3d12",
        help="use the game's original [2,18] list or D3D12-only [18] (default)",
    )
    parser.add_argument("file", type=Path, help="path to globalgamemanagers")
    args = parser.parse_args()
    try:
        patch_file(args.file, args.mode)
    except (PatchError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
