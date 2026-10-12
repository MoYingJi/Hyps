#!/usr/bin/env python3
"""Patch the graphics API list in one Genshin globalgamemanagers file without UnityPy.

The list is changed in place: [2, 18] becomes [18, 18]. The array length and every
offset stay the same, so exactly one 4-byte integer changes.

This game build strips embedded type trees, so the BuildSettings layout cannot be read
from the file. The patch therefore relies on fixed facts that were checked against
UnityPy for this exact build: Unity version, serialized file version 17, the
BuildSettings class id, its object size, and the byte offset of m_GraphicsAPIs. Any
mismatch is refused before anything is written.
"""

from __future__ import annotations

import argparse
import os
import stat
import struct
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

EXPECTED_UNITY_VERSION = "2017.4.30f1"
SUPPORTED_SERIALIZED_VERSION = 17
HEADER_SIZE = 20
BUILD_SETTINGS_CLASS_ID = 141
BUILD_SETTINGS_OBJECT_SIZE = 910656
# Offset of the m_GraphicsAPIs length field, relative to the start of the BuildSettings object.
GRAPHICS_APIS_COUNT_OFFSET = 910644
ORIGINAL_APIS = (2, 18)
D3D12_APIS = (18, 18)


class PatchError(RuntimeError):
    pass


@dataclass(frozen=True)
class SerializedType:
    class_id: int


@dataclass(frozen=True)
class ObjectEntry:
    path_id: int
    byte_start: int
    byte_size: int
    type_id: int


def _read_cstring(data: bytes, pos: int) -> tuple[str, int]:
    end = data.index(b"\0", pos)
    return data[pos:end].decode("utf-8", "surrogateescape"), end + 1


def _align4(pos: int) -> int:
    return (pos + 3) & ~3


def parse_serialized_file(data: bytes) -> tuple[str, tuple[SerializedType, ...], tuple[ObjectEntry, ...]]:
    try:
        _, file_size, version, data_offset = struct.unpack_from(">IIII", data, 0)
        if data[16] != 0:
            raise PatchError("Big-endian serialized files are not supported")
        if version != SUPPORTED_SERIALIZED_VERSION:
            raise PatchError(
                f"Unsupported serialized file version {version}; expected "
                f"{SUPPORTED_SERIALIZED_VERSION}"
            )
        if file_size != len(data):
            raise PatchError("Header file size does not match the file length")

        unity_version, pos = _read_cstring(data, HEADER_SIZE)
        pos += 4  # target platform
        if data[pos] != 0:
            raise PatchError("File embeds type trees; this patcher only handles the stripped layout")
        pos += 1

        (type_count,) = struct.unpack_from("<i", data, pos)
        pos += 4
        types = []
        for _ in range(type_count):
            (class_id,) = struct.unpack_from("<i", data, pos)
            pos += 4
            pos += 1  # is stripped
            pos += 2  # script type index
            if class_id == 114:
                pos += 16  # script id
            pos += 16  # old type hash
            types.append(SerializedType(class_id))

        (object_count,) = struct.unpack_from("<i", data, pos)
        pos += 4
        objects = []
        for _ in range(object_count):
            pos = _align4(pos)
            path_id, byte_start, byte_size, type_id = struct.unpack_from("<qIIi", data, pos)
            pos += 20
            objects.append(ObjectEntry(path_id, byte_start + data_offset, byte_size, type_id))
    except (ValueError, IndexError, struct.error) as exc:
        raise PatchError(f"Malformed serialized file: {exc}") from exc
    return unity_version, tuple(types), tuple(objects)


def locate_graphics_apis(data: bytes) -> tuple[tuple[int, ...], int]:
    """Return (apis, file offset of the first API element) for the BuildSettings object."""
    unity_version, types, objects = parse_serialized_file(data)
    if unity_version != EXPECTED_UNITY_VERSION:
        raise PatchError(
            f"Unexpected Unity version {unity_version!r}; expected "
            f"{EXPECTED_UNITY_VERSION!r}. Refusing to patch this build."
        )

    candidates = []
    for obj in objects:
        if not 0 <= obj.type_id < len(types):
            raise PatchError(f"Object {obj.path_id} references unknown type {obj.type_id}")
        if types[obj.type_id].class_id == BUILD_SETTINGS_CLASS_ID:
            candidates.append(obj)
    if len(candidates) != 1:
        raise PatchError(f"Expected exactly one BuildSettings object, found {len(candidates)}")

    obj = candidates[0]
    if obj.byte_size != BUILD_SETTINGS_OBJECT_SIZE:
        raise PatchError(
            f"BuildSettings size {obj.byte_size}; expected {BUILD_SETTINGS_OBJECT_SIZE}. "
            "Refusing to patch an unrecognized layout."
        )

    count_pos = obj.byte_start + GRAPHICS_APIS_COUNT_OFFSET
    (count,) = struct.unpack_from("<i", data, count_pos)
    if count != 2:
        raise PatchError(f"Unexpected m_GraphicsAPIs length {count}; expected 2")
    apis = struct.unpack_from("<2i", data, count_pos + 4)
    return apis, count_pos + 4


def build_patched(data: bytes, mode: str) -> tuple[bytes | None, tuple[int, ...], tuple[int, ...], int]:
    apis, element_offset = locate_graphics_apis(data)
    target = D3D12_APIS if mode == "d3d12" else ORIGINAL_APIS
    if apis == target:
        return None, apis, target, element_offset
    if apis not in (ORIGINAL_APIS, D3D12_APIS):
        raise PatchError(
            f"Unsupported existing graphics API list {list(apis)}; expected "
            f"{list(ORIGINAL_APIS)} or {list(D3D12_APIS)}. Refusing to patch."
        )

    # Both lists differ only in element 0, so one 4-byte write is enough.
    patched = bytearray(data)
    struct.pack_into("<i", patched, element_offset, target[0])
    return bytes(patched), apis, target, element_offset


def fsync_directory(path: Path) -> None:
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def patch_file(path: Path, mode: str) -> None:
    if path.is_symlink() or not path.is_file():
        raise PatchError(f"Target must be a regular, non-symlink file: {path}")

    original = path.read_bytes()
    patched, apis, target, element_offset = build_patched(original, mode)
    if patched is None:
        print(f"Graphics API list already {list(apis)}; unchanged: {path}")
        return

    if len(patched) != len(original):
        raise PatchError("Internal error: patched size differs from original")
    diff = [i for i, (a, b) in enumerate(zip(original, patched)) if a != b]
    if not diff or any(not element_offset <= i < element_offset + 4 for i in diff):
        raise PatchError("Internal error: patch touches bytes outside the API element")
    verified_apis, verified_offset = locate_graphics_apis(patched)
    if verified_apis != target or verified_offset != element_offset:
        raise PatchError(f"In-memory verification returned {list(verified_apis)}, expected {list(target)}")

    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temp_path = Path(temp_name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(patched)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp_path, stat.S_IMODE(path.stat().st_mode))
        if temp_path.read_bytes() != patched:
            raise PatchError("Written temp file does not match the patched data; target was not changed.")
        os.replace(temp_path, path)
        fsync_directory(path.parent)
    finally:
        temp_path.unlink(missing_ok=True)

    print(
        f"Patched graphics APIs {list(apis)} -> {list(target)} at byte offset "
        f"{element_offset} (4 bytes): {path}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate and patch one Genshin globalgamemanagers file by rewriting a single "
            "4-byte integer. Does not use UnityPy and does not locate files or mount overlays."
        )
    )
    parser.add_argument(
        "--mode",
        choices=("default", "d3d12"),
        default="d3d12",
        help="use the game's original [2, 18] list or D3D12-only [18, 18] (default)",
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
