#include <inttypes.h>
#include <stdio.h>

#include "probe_common.h"

int wmain(void)
{
    D3D11_TEXTURE2D_DESC desc = {
        .Width = 64,
        .Height = 64,
        .MipLevels = 1,
        .ArraySize = 1,
        .Format = DXGI_FORMAT_B8G8R8A8_UNORM,
        .SampleDesc = {1, 0},
        .Usage = D3D11_USAGE_DEFAULT,
        .BindFlags = D3D11_BIND_SHADER_RESOURCE,
        .CPUAccessFlags = 0,
        .MiscFlags = D3D11_RESOURCE_MISC_SHARED,
    };
    ID3D11DeviceContext *context_a = NULL, *context_b = NULL;
    ID3D11Texture2D *texture = NULL, *imported = NULL;
    ID3D11Device *device_a = NULL, *device_b = NULL;
    IDXGIResource *resource = NULL;
    HANDLE shared = NULL;
    HRESULT hr;
    int result = 1;

    hr = probe_create_d3d11(&device_a, &context_a);
    if (FAILED(hr))
    {
        result = probe_fail_hr("device-a", hr);
        goto cleanup;
    }

    hr = probe_create_d3d11(&device_b, &context_b);
    if (FAILED(hr))
    {
        result = probe_fail_hr("device-b", hr);
        goto cleanup;
    }

    hr = ID3D11Device_CreateTexture2D(device_a, &desc, NULL, &texture);
    if (FAILED(hr))
    {
        result = probe_fail_hr("texture-create", hr);
        goto cleanup;
    }

    hr = ID3D11Texture2D_QueryInterface(texture, &IID_IDXGIResource,
            (void **)&resource);
    if (FAILED(hr))
    {
        result = probe_fail_hr("resource-query", hr);
        goto cleanup;
    }

    hr = IDXGIResource_GetSharedHandle(resource, &shared);
    if (FAILED(hr))
    {
        result = probe_fail_hr("shared-handle", hr);
        goto cleanup;
    }
    if (!shared)
    {
        result = probe_fail_hr("shared-handle", E_FAIL);
        goto cleanup;
    }

    hr = ID3D11Device_OpenSharedResource(device_b, shared,
            &IID_ID3D11Texture2D, (void **)&imported);
    if (FAILED(hr))
    {
        result = probe_fail_hr("open-shared", hr);
        goto cleanup;
    }

    if (probe_require_texture_desc(imported, 64, 64,
            DXGI_FORMAT_B8G8R8A8_UNORM))
        goto cleanup;

    printf("PASS dxmt-shared handle=0x%" PRIxPTR
            " size=64x64 format=%u\n", (uintptr_t)shared,
            (unsigned int)DXGI_FORMAT_B8G8R8A8_UNORM);
    result = 0;

cleanup:
    if (resource)
        IDXGIResource_Release(resource);
    if (imported)
        ID3D11Texture2D_Release(imported);
    if (texture)
        ID3D11Texture2D_Release(texture);
    if (context_b)
        ID3D11DeviceContext_Release(context_b);
    if (device_b)
        ID3D11Device_Release(device_b);
    if (context_a)
        ID3D11DeviceContext_Release(context_a);
    if (device_a)
        ID3D11Device_Release(device_a);
    return result;
}
