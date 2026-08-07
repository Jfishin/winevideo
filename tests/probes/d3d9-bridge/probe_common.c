#include <stdio.h>

#include "probe_common.h"

HRESULT probe_create_d3d11(ID3D11Device **device,
        ID3D11DeviceContext **context)
{
    *device = NULL;
    *context = NULL;
    return D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT, NULL, 0, D3D11_SDK_VERSION,
            device, NULL, context);
}

int probe_fail_hr(const char *stage, HRESULT hr)
{
    printf("FAIL %s hr=0x%08lx\n", stage, (unsigned long)hr);
    return 1;
}

int probe_require_texture_desc(ID3D11Texture2D *texture, UINT width,
        UINT height, DXGI_FORMAT format)
{
    D3D11_TEXTURE2D_DESC actual;

    ID3D11Texture2D_GetDesc(texture, &actual);
    if (actual.Width != width || actual.Height != height
            || actual.Format != format)
        return probe_fail_hr("texture-desc", E_FAIL);
    return 0;
}
