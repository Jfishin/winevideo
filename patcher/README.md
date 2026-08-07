# winevideo patcher internals

The user-facing workflow is documented in the repository [README](../README.md)
and the [installation wiki](https://github.com/Jfishin/winevideo/wiki/Installation).

`patch.sh` installs the application payload into a duplicate CrossOver 26.2 or
26.3 app. When a bottle name is provided, it also registers the VP9 Media
Foundation components, selects DXMT, and enables the opt-in D3D9 video bridge in
that bottle.

The GUI invokes the same script. Advanced command-line use accepts a staging
folder without an `.app` extension:

```sh
patcher/patch.sh /path/to/CrossOver-winevideo "Bottle Name"
```

The staging folder is patched, re-sealed, and renamed to
`CrossOver-winevideo.app`. With no bottle argument, only the application payload
is installed. `--bottle-only` prepares another bottle using an already-patched
app.

`restore.sh` restores the backed-up application payload and the selected
bottle's saved environment values.
