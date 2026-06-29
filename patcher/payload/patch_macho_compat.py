#!/usr/bin/env python3
"""
Patch compatibility_version in LC_LOAD_DYLIB entries of a Mach-O binary.

When a GStreamer plugin built against Homebrew GStreamer 1.28 (compat 2802.0.0)
is loaded by CrossOver's GStreamer 1.24 (compat 2405.0.0), dyld refuses because
2405 < 2802. This tool patches the compat version requirements in the binary so
it accepts the older library.

Usage:
    python3 patch_macho_compat.py <binary> [--dry-run]

Patches all @rpath/libgst*.dylib and @rpath/libg*.dylib references to use
CrossOver's compat versions.
"""

import struct
import sys
import os
import shutil

# Mach-O constants
MH_MAGIC_64 = 0xFEEDFACF
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_REEXPORT_DYLIB = 0x8000001F
LC_ID_DYLIB = 0x0D

# Version mapping: library name pattern -> target compat version
# Format: major * 65536 + minor * 256 + patch
# CrossOver's versions:
#   GStreamer 1.24.5: compat 2405.0.0  -> 2405 * 65536 = 0x09650000
#   glib 2.78.1:      compat 7801.0.0  -> 7801 * 65536 = 0x1E790000
VERSION_MAP = {
    "libgstreamer-1.0": 2405 * 65536,  # GStreamer
    "libgstbase-1.0":   2405 * 65536,
    "libgsttag-1.0":    2405 * 65536,
    "libgstvideo-1.0":  2405 * 65536,
    "libgstaudio-1.0":  2405 * 65536,
    "libgstriff-1.0":   2405 * 65536,
    "libgstpbutils-1.0": 2405 * 65536,
    "libgstcodecs-1.0": 2405 * 65536,
    "libglib-2.0":      7801 * 65536,  # glib
    "libgobject-2.0":   7801 * 65536,
    "libintl":          10 * 65536,     # intl
}


def encode_version(v):
    """Encode version as major.minor.patch string."""
    major = (v >> 16) & 0xFFFF
    minor = (v >> 8) & 0xFF
    patch = v & 0xFF
    return f"{major}.{minor}.{patch}"


def patch_binary(path, dry_run=False):
    with open(path, "rb") as f:
        data = bytearray(f.read())

    # Check Mach-O magic
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != MH_MAGIC_64:
        print(f"Error: Not a 64-bit Mach-O binary (magic: 0x{magic:08X})")
        sys.exit(1)

    # Parse header
    # struct mach_header_64: magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved
    ncmds = struct.unpack_from("<I", data, 16)[0]

    offset = 32  # Size of mach_header_64
    patched = 0

    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, offset)

        if cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB, LC_REEXPORT_DYLIB):
            # struct dylib_command: cmd, cmdsize, dylib{name_offset, timestamp, current_version, compat_version}
            name_offset = struct.unpack_from("<I", data, offset + 8)[0]
            current_ver = struct.unpack_from("<I", data, offset + 16)[0]
            compat_ver = struct.unpack_from("<I", data, offset + 20)[0]

            # Read the library name (null-terminated string)
            name_start = offset + name_offset
            name_end = data.index(b'\x00', name_start)
            lib_name = data[name_start:name_end].decode("utf-8", errors="replace")

            # Check if this library needs patching
            for pattern, target_ver in VERSION_MAP.items():
                if pattern in lib_name and compat_ver != target_ver:
                    old_ver_str = encode_version(compat_ver)
                    new_ver_str = encode_version(target_ver)
                    print(f"  {lib_name}: compat {old_ver_str} -> {new_ver_str}")

                    if not dry_run:
                        # Patch compat_version
                        struct.pack_into("<I", data, offset + 20, target_ver)
                        # Also patch current_version to match
                        struct.pack_into("<I", data, offset + 16, target_ver)
                    patched += 1
                    break

        offset += cmdsize

    if patched == 0:
        print("  No libraries needed patching.")
    else:
        print(f"  Patched {patched} library references.")
        if not dry_run:
            with open(path, "wb") as f:
                f.write(data)
            print(f"  Written to: {path}")

    return patched


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <binary> [--dry-run]")
        sys.exit(1)

    path = sys.argv[1]
    dry_run = "--dry-run" in sys.argv

    if not os.path.isfile(path):
        print(f"Error: File not found: {path}")
        sys.exit(1)

    if dry_run:
        print(f"[DRY RUN] Analyzing: {path}")
    else:
        print(f"Patching: {path}")

    patched = patch_binary(path, dry_run)

    if patched > 0 and not dry_run:
        # Re-sign after patching
        os.system(f'codesign --force --sign - "{path}" 2>/dev/null')
        print("  Re-signed with ad-hoc signature.")


if __name__ == "__main__":
    main()
