#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include <d3d9.h>

#include "probe_common.h"

static uint64_t checksum_bytes(uint64_t checksum, const BYTE *data, size_t size)
{
    size_t i;

    for (i = 0; i < size; ++i)
    {
        checksum ^= data[i];
        checksum *= UINT64_C(1099511628211);
    }
    return checksum;
}

static DWORD pattern_pixel(UINT x, UINT y)
{
    return 0xff000000u | x << 16 | y << 8 | (x ^ y);
}

static uint64_t expected_pixel_checksum(void)
{
    uint64_t checksum = UINT64_C(14695981039346656037);
    UINT x, y;

    for (y = 0; y < 64; ++y)
    {
        for (x = 0; x < 64; ++x)
        {
            DWORD pixel = pattern_pixel(x, y);
            checksum = checksum_bytes(checksum, (const BYTE *)&pixel,
                    sizeof(pixel));
        }
    }
    return checksum;
}

static int run_positive_mode(BOOL pixels)
{
    ID3D11Texture2D *staging = NULL;
    ID3D11DeviceContext *context11 = NULL;
    IDirect3DDevice9Ex *device9 = NULL;
    IDirect3DSurface9 *surface = NULL;
    IDirect3D9Ex *d3d9 = NULL;
    ID3D11Texture2D *imported = NULL;
    ID3D11Device *device11 = NULL;
    D3DPRESENT_PARAMETERS present;
    BOOL staging_mapped = FALSE;
    HANDLE shared = NULL;
    HWND window = NULL;
    HRESULT hr;
    int result = 1;

    window = CreateWindowExW(0, L"STATIC", L"winevideo-dxmt-probe", 0,
            0, 0, 64, 64, NULL, NULL, GetModuleHandleW(NULL), NULL);
    if (!window)
    {
        result = probe_fail_hr("device-create", HRESULT_FROM_WIN32(GetLastError()));
        goto cleanup;
    }

    hr = Direct3DCreate9Ex(D3D_SDK_VERSION, &d3d9);
    if (FAILED(hr))
    {
        result = probe_fail_hr("d3d9-create", hr);
        goto cleanup;
    }

    memset(&present, 0, sizeof(present));
    present.BackBufferWidth = 64;
    present.BackBufferHeight = 64;
    present.BackBufferFormat = D3DFMT_UNKNOWN;
    present.BackBufferCount = 1;
    present.SwapEffect = D3DSWAPEFFECT_DISCARD;
    present.hDeviceWindow = window;
    present.Windowed = TRUE;
    present.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE;

    hr = IDirect3D9Ex_CreateDeviceEx(d3d9, D3DADAPTER_DEFAULT,
            D3DDEVTYPE_HAL, window,
            D3DCREATE_HARDWARE_VERTEXPROCESSING | D3DCREATE_MULTITHREADED,
            &present, NULL, &device9);
    if (FAILED(hr))
    {
        result = probe_fail_hr("device-create", hr);
        goto cleanup;
    }

    hr = IDirect3DDevice9Ex_CreateRenderTarget(device9, 64, 64,
            D3DFMT_A8R8G8B8, D3DMULTISAMPLE_NONE, 0, TRUE, &surface,
            &shared);
    if (FAILED(hr))
    {
        result = probe_fail_hr("rt-create", hr);
        goto cleanup;
    }
    if (!shared)
    {
        result = probe_fail_hr("shared-handle", E_FAIL);
        goto cleanup;
    }

    hr = probe_create_d3d11(&device11, &context11);
    if (FAILED(hr))
    {
        result = probe_fail_hr("open-shared", hr);
        goto cleanup;
    }

    hr = ID3D11Device_OpenSharedResource(device11, shared,
            &IID_ID3D11Texture2D, (void **)&imported);
    if (FAILED(hr))
    {
        result = probe_fail_hr("open-shared", hr);
        goto cleanup;
    }
    if (probe_require_texture_desc(imported, 64, 64,
            DXGI_FORMAT_B8G8R8A8_UNORM))
        goto cleanup;

    if (pixels)
    {
        D3D11_TEXTURE2D_DESC staging_desc;
        D3D11_MAPPED_SUBRESOURCE mapped;
        D3DLOCKED_RECT locked;
        uint64_t actual = UINT64_C(14695981039346656037);
        uint64_t expected = expected_pixel_checksum();
        UINT x, y;

        hr = IDirect3DSurface9_LockRect(surface, &locked, NULL, 0);
        if (FAILED(hr))
        {
            result = probe_fail_hr("lock-rect", hr);
            goto cleanup;
        }
        for (y = 0; y < 64; ++y)
        {
            DWORD *row = (DWORD *)((BYTE *)locked.pBits + y * locked.Pitch);
            for (x = 0; x < 64; ++x)
                row[x] = pattern_pixel(x, y);
        }
        hr = IDirect3DSurface9_UnlockRect(surface);
        if (FAILED(hr))
        {
            result = probe_fail_hr("unlock-rect", hr);
            goto cleanup;
        }

        ID3D11Texture2D_GetDesc(imported, &staging_desc);
        staging_desc.Usage = D3D11_USAGE_STAGING;
        staging_desc.BindFlags = 0;
        staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
        staging_desc.MiscFlags = 0;
        hr = ID3D11Device_CreateTexture2D(device11, &staging_desc, NULL,
                &staging);
        if (FAILED(hr))
        {
            result = probe_fail_hr("staging-create", hr);
            goto cleanup;
        }
        ID3D11DeviceContext_CopyResource(context11,
                (ID3D11Resource *)staging, (ID3D11Resource *)imported);
        hr = ID3D11DeviceContext_Map(context11, (ID3D11Resource *)staging,
                0, D3D11_MAP_READ, 0, &mapped);
        if (FAILED(hr))
        {
            result = probe_fail_hr("staging-map", hr);
            goto cleanup;
        }
        staging_mapped = TRUE;
        for (y = 0; y < 64; ++y)
            actual = checksum_bytes(actual,
                    (const BYTE *)mapped.pData + y * mapped.RowPitch, 64 * 4);
        if (actual != expected)
        {
            const BYTE *first = mapped.pData;
            size_t nonzero = 0;

            for (y = 0; y < 64; ++y)
            {
                const BYTE *row = (const BYTE *)mapped.pData
                        + y * mapped.RowPitch;
                for (x = 0; x < 64 * 4; ++x)
                    nonzero += row[x] != 0;
            }
            printf("pixel-diagnostic expected=0x%016" PRIx64
                    " actual=0x%016" PRIx64 " nonzero=%zu/16384"
                    " first=%02x%02x%02x%02x-%02x%02x%02x%02x\n",
                    expected, actual, nonzero, first[0], first[1], first[2],
                    first[3], first[4], first[5], first[6], first[7]);
            result = probe_fail_hr("pixel-checksum", E_FAIL);
            goto cleanup;
        }
        printf("PASS d3d9-bridge mode=pixels checksum=0x%016" PRIx64 "\n",
                actual);
    }
    else
    {
        printf("PASS d3d9-bridge mode=handle handle=0x%" PRIxPTR "\n",
                (uintptr_t)shared);
    }
    result = 0;

cleanup:
    if (staging_mapped)
        ID3D11DeviceContext_Unmap(context11, (ID3D11Resource *)staging, 0);
    if (staging)
        ID3D11Texture2D_Release(staging);
    if (imported)
        ID3D11Texture2D_Release(imported);
    if (context11)
        ID3D11DeviceContext_Release(context11);
    if (device11)
        ID3D11Device_Release(device11);
    if (surface)
        IDirect3DSurface9_Release(surface);
    if (device9)
        IDirect3DDevice9Ex_Release(device9);
    if (d3d9)
        IDirect3D9Ex_Release(d3d9);
    if (window)
        DestroyWindow(window);
    return result;
}

struct negative_case
{
    D3DFORMAT format;
    D3DMULTISAMPLE_TYPE multisample;
    BOOL lockable;
    const char *name;
};

static int run_negative_mode(void)
{
    static const struct negative_case cases[] = {
        {D3DFMT_R5G6B5, D3DMULTISAMPLE_NONE, TRUE, "unsupported-format"},
        {D3DFMT_A8R8G8B8, D3DMULTISAMPLE_2_SAMPLES, TRUE, "multisampled"},
        {D3DFMT_A8R8G8B8, D3DMULTISAMPLE_NONE, FALSE, "not-lockable"},
    };
    IDirect3DDevice9Ex *device9 = NULL;
    IDirect3D9Ex *d3d9 = NULL;
    D3DPRESENT_PARAMETERS present;
    HWND window = NULL;
    HRESULT hr;
    size_t i;
    int result = 1;

    window = CreateWindowExW(0, L"STATIC", L"winevideo-dxmt-negative-probe", 0,
            0, 0, 64, 64, NULL, NULL, GetModuleHandleW(NULL), NULL);
    if (!window)
    {
        result = probe_fail_hr("device-create", HRESULT_FROM_WIN32(GetLastError()));
        goto cleanup;
    }

    hr = Direct3DCreate9Ex(D3D_SDK_VERSION, &d3d9);
    if (FAILED(hr))
    {
        result = probe_fail_hr("d3d9-create", hr);
        goto cleanup;
    }

    memset(&present, 0, sizeof(present));
    present.BackBufferWidth = 64;
    present.BackBufferHeight = 64;
    present.BackBufferFormat = D3DFMT_UNKNOWN;
    present.BackBufferCount = 1;
    present.SwapEffect = D3DSWAPEFFECT_DISCARD;
    present.hDeviceWindow = window;
    present.Windowed = TRUE;
    present.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE;

    hr = IDirect3D9Ex_CreateDeviceEx(d3d9, D3DADAPTER_DEFAULT,
            D3DDEVTYPE_HAL, window,
            D3DCREATE_HARDWARE_VERTEXPROCESSING | D3DCREATE_MULTITHREADED,
            &present, NULL, &device9);
    if (FAILED(hr))
    {
        result = probe_fail_hr("device-create", hr);
        goto cleanup;
    }

    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i)
    {
        IDirect3DSurface9 *surface = NULL;
        HANDLE shared = NULL;

        hr = IDirect3DDevice9Ex_CreateRenderTarget(device9, 64, 64,
                cases[i].format, cases[i].multisample, 0, cases[i].lockable,
                &surface, &shared);
        if (shared)
        {
            printf("FAIL negative-%s hr=0x%08lx\n", cases[i].name,
                    (unsigned long)E_FAIL);
            if (surface)
                IDirect3DSurface9_Release(surface);
            goto cleanup;
        }
        if (surface)
            IDirect3DSurface9_Release(surface);
    }

    printf("PASS d3d9-bridge mode=negative\n");
    result = 0;

cleanup:
    if (device9)
        IDirect3DDevice9Ex_Release(device9);
    if (d3d9)
        IDirect3D9Ex_Release(d3d9);
    if (window)
        DestroyWindow(window);
    return result;
}

int wmain(int argc, wchar_t **argv)
{
    if (argc == 3 && !wcscmp(argv[1], L"--mode")
            && !wcscmp(argv[2], L"handle"))
        return run_positive_mode(FALSE);
    if (argc == 3 && !wcscmp(argv[1], L"--mode")
            && !wcscmp(argv[2], L"pixels"))
        return run_positive_mode(TRUE);
    if (argc == 3 && !wcscmp(argv[1], L"--mode")
            && !wcscmp(argv[2], L"negative"))
        return run_negative_mode();

    printf("FAIL arguments hr=0x%08lx\n", (unsigned long)E_INVALIDARG);
    return 2;
}
