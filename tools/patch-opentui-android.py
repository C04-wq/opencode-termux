#!/usr/bin/env python3
"""Apply the Android/Bionic build guards to an OpenTUI source tree.

Version-agnostic: the build.zig hooks below are required, and fail loudly when
upstream moves them. The safety guards in buffer/renderer/clipboard are applied
only when their anchor still exists, because upstream may fix them itself.

    patch-opentui-android.py <opentui-tree>
"""

import argparse
from pathlib import Path


def replace(path: Path, old: str, new: str, count: int = 1, required: bool = True) -> bool:
    text = path.read_text(encoding="utf-8")
    if new and new in text:
        return True  # already applied
    actual = text.count(old)
    if actual != count:
        if required:
            raise SystemExit(
                f"patch-opentui: {path.name}: expected {count} occurrence(s), found {actual}"
            )
        return False
    path.write_text(text.replace(old, new), encoding="utf-8")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("tree", type=Path)
    args = parser.parse_args()

    native = args.tree / "packages" / "native"
    src = native / "src"
    build = native / "build.zig"
    buffer = src / "buffer.zig"
    renderer = src / "renderer.zig"
    clipboard_host = src / "clipboard" / "host.zig"
    for path in (build, buffer, renderer, clipboard_host):
        if not path.is_file():
            raise SystemExit(f"patch-opentui: missing {path}")

    # 1. translate-c needs the NDK bionic headers; zig's bundled libc has none.
    replace(
        build,
        "fn addTranslatedCImports(\n    b: *std.Build,",
        """fn addBionicTranslateIncludes(b: *std.Build, step: *std.Build.Step.TranslateC) void {
    const arch_inc = b.graph.environ_map.get("BIONIC_ARCH_INCLUDE");
    const sys_inc = b.graph.environ_map.get("BIONIC_SYS_INCLUDE");
    if (arch_inc) |path| {
        step.addSystemIncludePath(.{ .cwd_relative = path });
    }
    if (sys_inc) |path| {
        step.addSystemIncludePath(.{ .cwd_relative = path });
    }
    if (arch_inc != null or sys_inc != null) {
        // Zig 0.17's translate-c also searches the host /usr/include (0.16 did
        // not). Bionic <limits.h> ends with `#include_next <limits.h>`, which
        // would then resolve to glibc's limits.h and fail on __GLIBC_USE and
        // gnu/stubs-32.h. This empty shadow sits right after the NDK dirs, so
        // include_next stops inside the sysroot. Kept conditional so a
        // desktop build without the NDK still gets the real limits.h.
        step.addSystemIncludePath(b.path("src/bionic-include-next"));
    }
    // Nullability is type metadata only. Zig translate-c rejects the NDK's
    // annotated array parameters, so erase these annotations for translation.
    step.defineCMacroRaw("_Nullable=");
    step.defineCMacroRaw("_Nonnull=");
    step.defineCMacroRaw("_Null_unspecified=");
    step.defineCMacroRaw("__ANDROID_MIN_SDK_VERSION__=28");
    step.defineCMacroRaw("__ANDROID_API__=28");
}

fn addTranslatedCImports(
    b: *std.Build,""",
    )

    # Bionic's <limits.h> ends with `#include_next <limits.h>`. Zig 0.17's
    # translate-c also searches the host /usr/include (0.16 did not), so that
    # include_next lands in glibc and dies on __GLIBC_USE / gnu/stubs-32.h.
    # This empty file is injected as a system include dir after the NDK ones,
    # so include_next stops at the sysroot boundary instead of the host.
    shadow = src / "bionic-include-next"
    shadow.mkdir(parents=True, exist_ok=True)
    (shadow / "limits.h").write_text(
        "/* Terminates bionic's `#include_next <limits.h>` inside the NDK.\n"
        "   Host glibc limits.h is not a valid target for this sysroot. */\n",
        encoding="utf-8",
    )

    replace(
        build,
        '    miniaudio_translate.addIncludePath(b.path("src"));\n'
        '    module.addImport("miniaudio", miniaudio_translate.createModule());',
        '    miniaudio_translate.addIncludePath(b.path("src"));\n'
        "    addBionicTranslateIncludes(b, miniaudio_translate);\n"
        '    module.addImport("miniaudio", miniaudio_translate.createModule());',
    )

    replace(
        build,
        '    yoga_translate.addIncludePath(yoga_dep.path(""));\n'
        '    module.addImport("yoga", yoga_translate.createModule());',
        '    yoga_translate.addIncludePath(yoga_dep.path(""));\n'
        "    addBionicTranslateIncludes(b, yoga_translate);\n"
        '    module.addImport("yoga", yoga_translate.createModule());',
    )

    # The context ABI header is translated too, and it includes system headers
    # (stdint.h, limits.h). Without the bionic paths its translate-c falls back
    # to the host headers just like the other two steps did.
    replace(
        build,
        '        .root_source_file = b.path("include/opentui.h"),\n'
        "        .target = target,\n"
        "        .optimize = optimize,\n"
        "    });\n"
        '    module.addImport("context_abi_c", header.createModule());',
        '        .root_source_file = b.path("include/opentui.h"),\n'
        "        .target = target,\n"
        "        .optimize = optimize,\n"
        "    });\n"
        "    addBionicTranslateIncludes(b, header);\n"
        '    module.addImport("context_abi_c", header.createModule());',
    )

    # Bionic has no libpthread stub: pthread lives in libc.
    replace(
        build,
        """        .linux => {
            module.linkSystemLibrary("dl", .{});
            module.linkSystemLibrary("pthread", .{});
            module.linkSystemLibrary("m", .{});
        },""",
        """        .linux => {
            if (b.graph.environ_map.get("BIONIC_LIB_DIR")) |path| {
                module.addLibraryPath(.{ .cwd_relative = path });
                module.linkSystemLibrary("dl", .{});
                module.linkSystemLibrary("m", .{});
            } else {
                module.linkSystemLibrary("dl", .{});
                module.linkSystemLibrary("pthread", .{});
                module.linkSystemLibrary("m", .{});
            }
        },""",
    )

    # Bionic < 11 ignores TLSDESC relocations; the shim also supplies the
    # glibc-only pthread_tryjoin_np that OpenTUI declares as extern.
    shim = Path(__file__).resolve().parent.parent / "patches" / "opentui" / "tlsdesc-shim.c"
    if not shim.is_file():
        raise SystemExit(f"patch-opentui: missing {shim}")
    (src / "tlsdesc-shim.c").write_text(shim.read_text(encoding="utf-8"), encoding="utf-8")
    replace(
        build,
        "    addMiniaudioShim(b, module, target, macos_sdk_path);\n"
        "    addImageShim(b, module, target, macos_sdk_path);\n",
        "    addMiniaudioShim(b, module, target, macos_sdk_path);\n"
        "    addImageShim(b, module, target, macos_sdk_path);\n"
        "    // tlsdesc-shim.c: bionic < 11 ignores TLSDESC relocations, and\n"
        "    // bionic has no libpthread with pthread_tryjoin_np. Must live in the\n"
        "    // module it fixes (see the file header for the full rationale).\n"
        '    module.addCSourceFile(.{ .file = b.path("src/tlsdesc-shim.c"), .flags = &.{"-std=c99"} });\n',
    )

    # 2. Optional integer-overflow guards; skipped if upstream already fixed them.
    skipped = []
    if not replace(
        buffer,
        """        return x >= scissor.x and x < scissor.x + @as(i32, @intCast(scissor.width)) and
            y >= scissor.y and y < scissor.y + @as(i32, @intCast(scissor.height));""",
        """        const w = @as(i32, @intCast(@min(scissor.width, 0x7FFFFFFF)));
        const h = @as(i32, @intCast(@min(scissor.height, 0x7FFFFFFF)));
        return x >= scissor.x and x < scissor.x +| w and
            y >= scissor.y and y < scissor.y +| h;""",
        required=False,
    ):
        skipped.append("buffer scissor guard")

    rect_old = """        const rect_end_x = x + @as(i32, @intCast(width));
        const rect_end_y = y + @as(i32, @intCast(height));
        const scissor_end_x = scissor.x + @as(i32, @intCast(scissor.width));
        const scissor_end_y = scissor.y + @as(i32, @intCast(scissor.height));"""
    rect_new = """        const w = @as(i32, @intCast(@min(width, 0x7FFFFFFF)));
        const h = @as(i32, @intCast(@min(height, 0x7FFFFFFF)));
        const sw = @as(i32, @intCast(@min(scissor.width, 0x7FFFFFFF)));
        const sh = @as(i32, @intCast(@min(scissor.height, 0x7FFFFFFF)));
        const rect_end_x = x +| w;
        const rect_end_y = y +| h;
        const scissor_end_x = scissor.x +| sw;
        const scissor_end_y = scissor.y +| sh;"""
    if not replace(buffer, rect_old, rect_new, count=2, required=False):
        skipped.append("buffer rect guard")

    if not replace(
        buffer,
        """        if (virtual_lines.len == 0) return;

        const firstVisibleLine: u32 = if (y < 0) @intCast(-y) else 0;""",
        """        if (virtual_lines.len == 0) return;
        if (y <= -0x40000000) return;

        const firstVisibleLine: u32 = if (y < 0) @intCast(-y) else 0;""",
        required=False,
    ):
        skipped.append("buffer virtual-line guard")

    if not replace(
        buffer,
        """        if (posX >= @as(i32, @intCast(self.width)) or posY >= @as(i32, @intCast(self.height))) return;

        const startX: u32 = if (posX < 0) @intCast(-posX) else 0;""",
        """        if (posX >= @as(i32, @intCast(self.width)) or posY >= @as(i32, @intCast(self.height))) return;
        if (posX < -0x40000000 or posY < -0x40000000) return;

        const startX: u32 = if (posX < 0) @intCast(-posX) else 0;""",
        count=2,
        required=False,
    ):
        skipped.append("buffer draw guard")

    if not replace(
        renderer,
        "            clipped.x + @as(i32, @intCast(clipped.width)),",
        "            clipped.x +| @as(i32, @intCast(@min(clipped.width, 0x7FFFFFFF))),",
        required=False,
    ):
        skipped.append("renderer clip-x guard")

    if not replace(
        renderer,
        "            clipped.y + @as(i32, @intCast(clipped.height)),",
        "            clipped.y +| @as(i32, @intCast(@min(clipped.height, 0x7FFFFFFF))),",
        required=False,
    ):
        skipped.append("renderer clip-y guard")

    # Postconditions for the required hooks.
    build_text = build.read_text(encoding="utf-8")
    for marker in (
        "addBionicTranslateIncludes(b, miniaudio_translate)",
        "addBionicTranslateIncludes(b, yoga_translate)",
        'b.graph.environ_map.get("BIONIC_LIB_DIR")',
    ):
        if marker not in build_text:
            raise SystemExit(f"patch-opentui: missing postcondition in build.zig: {marker}")

    print("patch-opentui: bionic build hooks applied")
    if skipped:
        print("patch-opentui: upstream no longer needs: " + ", ".join(skipped))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
