# winegstreamer VP9 build recipe

How `winegstreamer.dll`/`.so` is rebuilt with VP9/AV1 support for CrossOver 26.2.

## Key constraint

`winegstreamer` must be built against the **same GStreamer/glib that CrossOver ships**
(GStreamer 1.24, glib 2.74–2.78), not Homebrew's newer GStreamer/glib. Building against
glib 2.80+ makes `winegstreamer.so` reference `g_once_init_enter_pointer`, which
CrossOver's glib lacks → `dlopen` fails at runtime → Media Foundation reports no source
for every codec.

## Build environment

Obtain a GStreamer **1.24.x** framework that bundles glib 2.74 (e.g. the
`gstreamer-1.0-devel-1.24.13-universal.pkg`). If it cannot be installed system-wide,
extract it:

```sh
pkgutil --expand-full <pkg> /tmp/gst-devel
# merge component Payloads into one tree with Headers/, lib/, include/
```

Point the Wine build at this framework instead of Homebrew. `makedep` bakes include/lib
flags into per-file rules, so a `make VAR=` override is ignored — edit the generated
`Makefile` (or configure) to use the framework's `-I`/`-L` paths.

## Build

1. Apply `build/patches/0002-winegstreamer-vp9-av1-caps.patch` (VP9/AV1 caps + decoder
   input types) and `build/patches/0003-winegstreamer-vp9-decoder-mft.patch` (the VP9
   decoder MFT).
2. Rebuild winegstreamer:
   ```sh
   cd <wine-build> && make dlls/winegstreamer/x86_64-windows/winegstreamer.dll \
                            dlls/winegstreamer/winegstreamer.so
   ```
3. Verify the `.so` references only `g_once_init_enter` (no `_pointer`):
   ```sh
   nm -u dlls/winegstreamer/winegstreamer.so | grep once_init
   ```

## GStreamer plugins (libgstvpx, libgstmatroska)

`build/build-gst-plugins.sh` builds `libgstvpx` (`vp9dec`/`vp8dec`) and `libgstmatroska`
(`matroskademux`) from the framework's static `.a` libraries plus the shims in
`build/gst-plugins/`. Each shim drops the archive's own `GST_PLUGIN_DEFINE` object and
exports `gst_plugin_<name>_get_desc()` (the symbol GStreamer 1.24 resolves at load).

## Install into a CrossOver app

For each rebuilt `.so`/plugin dylib:

1. Copy it into the app.
2. Remove framework/Homebrew `LC_RPATH` entries and add the app's `…/lib64` rpath so
   `@rpath` resolves to CrossOver's single bundled GStreamer 1.24.5 (avoids the
   "implemented in both" duplicate-class crash).
3. Rewrite Mach-O compat versions to match CrossOver (`patch_macho_compat.py`:
   GStreamer 2414→2405, glib 7401→7801).
4. Ad-hoc sign: `codesign --force --sign -`.

The `patcher/` ships prebuilt artifacts produced by this recipe; `patcher/patch.sh`
performs the install steps above. `mft_probe`/`mf_probe` validate the result.
