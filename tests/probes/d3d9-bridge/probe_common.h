#ifndef WINEVIDEO_DXMT_PROBE_COMMON_H
#define WINEVIDEO_DXMT_PROBE_COMMON_H

#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>

HRESULT probe_create_d3d11(ID3D11Device **device,
        ID3D11DeviceContext **context);
int probe_fail_hr(const char *stage, HRESULT hr);
int probe_require_texture_desc(ID3D11Texture2D *texture, UINT width,
        UINT height, DXGI_FORMAT format);

#endif
