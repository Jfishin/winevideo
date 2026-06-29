/* mf_probe_tex.c — directly probe which D3D11 texture formats the active backend
 * (d3dmetal's D3D11) can create. Isolates whether NV12 is fundamentally
 * unsupported vs. only-with-certain-flags. Each CreateTexture2D that hits an
 * invalid Metal pixelFormat aborts the process, so BGRA is tested first.
 *
 * Build: x86_64-w64-mingw32-gcc mf_probe_tex.c -o mf_probe_tex.exe -ld3d11 -ldxgi -lole32 -luuid
 * Run:   CX_BOTTLE=steam-ul <app>/bin/wine mf_probe_tex.exe
 */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

static ID3D11Device *dev;

static void try_tex(const char *label, DXGI_FORMAT fmt, D3D11_USAGE usage, UINT bind)
{
    D3D11_TEXTURE2D_DESC d; ZeroMemory(&d,sizeof(d));
    d.Width = 768; d.Height = 432; d.MipLevels = 1; d.ArraySize = 1;
    d.Format = fmt; d.SampleDesc.Count = 1; d.Usage = usage; d.BindFlags = bind;
    ID3D11Texture2D *t = NULL;
    printf("  try %-34s ... ", label);
    HRESULT hr = ID3D11Device_CreateTexture2D(dev, &d, NULL, &t);
    printf("hr=0x%08lx %s\n", (unsigned long)hr, SUCCEEDED(hr)?"OK":"FAIL");
    if (t) ID3D11Texture2D_Release(t);
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    D3D_FEATURE_LEVEL fl;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, NULL, 0, D3D11_SDK_VERSION, &dev, &fl, NULL);
    printf("D3D11CreateDevice=0x%08lx fl=0x%x\n", (unsigned long)hr, fl);
    if (FAILED(hr)) return 2;

    UINT sup = 0;
    ID3D11Device_CheckFormatSupport(dev, DXGI_FORMAT_NV12, &sup);
    printf("CheckFormatSupport(NV12)=0x%x (TEXTURE2D=%d SHADER=%d RT=%d)\n", sup,
        !!(sup&D3D11_FORMAT_SUPPORT_TEXTURE2D), !!(sup&D3D11_FORMAT_SUPPORT_SHADER_LOAD),
        !!(sup&D3D11_FORMAT_SUPPORT_RENDER_TARGET));
    UINT sup2=0; ID3D11Device_CheckFormatSupport(dev, DXGI_FORMAT_B8G8R8A8_UNORM, &sup2);
    printf("CheckFormatSupport(BGRA)=0x%x\n", sup2);

    /* BGRA first (known good) so we get output before any NV12 abort */
    try_tex("BGRA default shader-resource", DXGI_FORMAT_B8G8R8A8_UNORM, D3D11_USAGE_DEFAULT, D3D11_BIND_SHADER_RESOURCE);
    /* NV12 variants — these are what MF video allocation uses */
    try_tex("NV12 default shader-resource", DXGI_FORMAT_NV12, D3D11_USAGE_DEFAULT, D3D11_BIND_SHADER_RESOURCE);
    try_tex("NV12 default 0-bind",          DXGI_FORMAT_NV12, D3D11_USAGE_DEFAULT, 0);
    try_tex("NV12 staging 0-bind",          DXGI_FORMAT_NV12, D3D11_USAGE_STAGING, 0);
    printf("done (survived all)\n");
    return 0;
}
