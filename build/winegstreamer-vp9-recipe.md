# winegstreamer VP9 build recipe (Route B) — WORKING build, routing TODO

Status 2026-06-29 (late): winegstreamer with VP9/AV1 caps **builds, loads in CrossOver 26.2,
and works** (h264 decodes, no crash, no glib symbol blocker, single GStreamer instance).
Remaining: get Media Foundation to route `.webm/.mkv/.msd` to the GStreamer byte-stream handler
so VP9 actually reaches the decoder.

## The key insight (why earlier attempts failed)
winegstreamer MUST be built against the **same GStreamer/glib CrossOver ships** (GStreamer 1.24,
glib 2.74-2.78), NOT Homebrew's 1.28/glib-2.88. Building against Homebrew makes winegstreamer.so
reference `g_once_init_enter_pointer` (glib 2.80+), which CrossOver's glib 2.78 lacks → dlopen
fails → NO SOURCE for everything.

## Build environment (one-time, done)
- Downloaded `gstreamer-1.0-devel-1.24.13-universal.pkg` (~/Downloads) — bundles glib **2.74.4**
  (only `g_once_init_enter`, no `_pointer`). Couldn't install (system-only installer), so extracted:
  `pkgutil --expand-full <pkg> ~/.local/winevideo/gst-devel`
  then merged all component Payloads into `~/.local/winevideo/gst-framework` (Headers/, lib/, include/).
- Rewrote the baked Homebrew gstreamer/glib `-I`/`-L` paths in the build Makefile
  (`~/.local/winevideo/build/wine/Makefile`) to the framework (backup: `Makefile.bak.brew`).
  makedep bakes flags into per-file rules, so `make VAR=` override does NOT work — must edit the Makefile.

## Build
- Source change: `build/patches/0002-winegstreamer-vp9-av1-caps.patch` (VP9/AV1 caps + decoder input types).
- `cd ~/.local/winevideo/build/wine && (clean winegstreamer objects) && make` → produces
  winegstreamer.{dll,so} linking `@rpath/libgstreamer-1.0.0.dylib` (compat 2414) / glib (7401),
  referencing only `g_once_init_enter` (verify: `nm -u winegstreamer.so | grep once_init`).

## Drop-in (see build/dropin-winegstreamer.sh)
1. copy winegstreamer.dll/.so into the CrossOver app.
2. delete framework/brew rpaths from the .so, add `<app>/.../lib64` rpath (so @rpath → CrossOver's
   single GStreamer 1.24.5 — avoids the "implemented in both" duplicate-class crash).
3. `patch_macho_compat.py` to rewrite compat 2414→2405 / glib→7801 (match CrossOver).
4. ad-hoc `codesign --force --sign -`.
Result: loads + h264 decodes (PASS). Verified on the disposable 26.2 copy.

## Remaining: container routing (next session)
`.webm/.mkv` have no MF byte-stream handler → NO SOURCE before the decoder is ever reached.
Registered `.webm/.mkv/.msd` → GStreamer handler CLSID `{317df618-5e5a-468a-9f15-d827a9a08162}` in
the bottle registry (HKLM\…\Windows Media Foundation\ByteStreamHandlers), but MF still doesn't invoke
it (CrossOver's mfplat/mfreadwrite are release builds — no trace to see why).
**Next:** drop in OUR trace-enabled mfplat.dll + mfreadwrite.dll (same 26.2.0 source) to trace the
source resolver and see why the `.webm` handler isn't selected; also test VP9-in-MP4 via the working
`.mp4` handler (winedmo path → our VP9 decoder MFT). Validate decode with mf_probe; NG4 live with user.
