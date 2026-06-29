/* mf_probe_d3d.c — reproduce NG4's crash path: a D3D-backed Media Foundation
 * SourceReader feeding decoded video into D3D11 textures (which become Metal
 * textures under CrossOver d3dmetal). The game dies with Metal
 * "MTLTextureDescriptor has invalid pixelFormat (0)" on the first VP9 frame;
 * this harness exercises the same path without launching the game.
 *
 * It: creates a D3D11 device, wraps it in an IMFDXGIDeviceManager, creates a
 * SourceReader with MF_SOURCE_READER_D3D_MANAGER + advanced video processing,
 * requests an output type, then ReadSamples and inspects the D3D texture format
 * of each returned sample (or crashes the same way the game does).
 *
 * Build (llvm-mingw):
 *   x86_64-w64-mingw32-gcc mf_probe_d3d.c -o mf_probe_d3d.exe \
 *     -lmfplat -lmfreadwrite -lmfuuid -lmf -lole32 -luuid -ld3d11 -ldxgi
 * Run:
 *   CX_BOTTLE=Test <app>/bin/wine mf_probe_d3d.exe 'C:\mftest\ng4_real.msd' [nv12|argb|rgb32|none]
 */
#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

static const GUID MY_VP90 =
    {0x30395056,0x0000,0x0010,{0x80,0x00,0x00,0xaa,0x00,0x38,0x9b,0x71}};

static const char *dxgi_name(DXGI_FORMAT f){
    switch(f){
        case 0: return "UNKNOWN(0) *** THIS IS THE CRASH FORMAT ***";
        case DXGI_FORMAT_B8G8R8A8_UNORM: return "B8G8R8A8_UNORM(87)";
        case DXGI_FORMAT_R8G8B8A8_UNORM: return "R8G8B8A8_UNORM(28)";
        case DXGI_FORMAT_NV12: return "NV12(103)";
        case DXGI_FORMAT_420_OPAQUE: return "420_OPAQUE(106)";
        case DXGI_FORMAT_YUY2: return "YUY2(107)";
        case DXGI_FORMAT_P010: return "P010(104)";
        default: return "other";
    }
}

int main(int argc, char **argv)
{
    const wchar_t *url = L"C:\\mftest\\ng4_real.msd";
    wchar_t wbuf[1024];
    const char *out = (argc > 2) ? argv[2] : "nv12";
    HRESULT hr;

    setvbuf(stdout, NULL, _IONBF, 0);  /* unbuffered: survive a Metal abort() */
    if (argc > 1) { MultiByteToWideChar(CP_ACP,0,argv[1],-1,wbuf,1024); url = wbuf; }

    hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    printf("MFStartup=0x%08lx\n", (unsigned long)hr);

    /* --- D3D11 device (this brings up d3dmetal) --- */
    ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL;
    D3D_FEATURE_LEVEL fl;
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, flags, NULL, 0,
                           D3D11_SDK_VERSION, &dev, &fl, &ctx);
    if (FAILED(hr)) {
        printf("D3D11CreateDevice(VIDEO_SUPPORT)=0x%08lx, retrying without VIDEO_SUPPORT\n",(unsigned long)hr);
        flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
        hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, flags, NULL, 0,
                               D3D11_SDK_VERSION, &dev, &fl, &ctx);
    }
    printf("D3D11CreateDevice=0x%08lx featureLevel=0x%x\n", (unsigned long)hr, fl);
    if (FAILED(hr)) { printf("*** no D3D11 device; cannot test D3D path ***\n"); return 2; }

    /* multithread protect (MF requires it) */
    ID3D10Multithread *mt = NULL;
    if (SUCCEEDED(ID3D11Device_QueryInterface(dev,&IID_ID3D10Multithread,(void**)&mt))) {
        ID3D10Multithread_SetMultithreadProtected(mt, TRUE);
        ID3D10Multithread_Release(mt);
    }

    /* --- DXGI device manager --- */
    UINT token = 0; IMFDXGIDeviceManager *dxgimgr = NULL;
    hr = MFCreateDXGIDeviceManager(&token, &dxgimgr);
    printf("MFCreateDXGIDeviceManager=0x%08lx\n", (unsigned long)hr);
    if (SUCCEEDED(hr)) {
        hr = IMFDXGIDeviceManager_ResetDevice(dxgimgr, (IUnknown*)dev, token);
        printf("ResetDevice=0x%08lx\n", (unsigned long)hr);
    }

    /* --- SourceReader attributes: D3D manager + advanced video processing --- */
    IMFAttributes *attrs = NULL;
    MFCreateAttributes(&attrs, 4);
    IMFAttributes_SetUnknown(attrs, &MF_SOURCE_READER_D3D_MANAGER, (IUnknown*)dxgimgr);
    IMFAttributes_SetUINT32(attrs, &MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE);
    IMFAttributes_SetUINT32(attrs, &MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);

    IMFSourceReader *reader = NULL;
    hr = MFCreateSourceReaderFromURL(url, attrs, &reader);
    printf("CreateSourceReader(D3D)=0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr)) { printf(">>> source open failed\n"); return 3; }

    /* native type */
    IMFMediaType *nt = NULL;
    if (SUCCEEDED(IMFSourceReader_GetNativeMediaType(reader, MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &nt))) {
        GUID sub; IMFMediaType_GetGUID(nt, &MF_MT_SUBTYPE, &sub);
        printf(">>> native subtype=%08lx\n", (unsigned long)sub.Data1);
        IMFMediaType_Release(nt);
    }

    /* request an output type so the SourceReader inserts the video processor that
       allocates D3D textures — this is where the game dies. */
    if (strcmp(out,"none")) {
        IMFMediaType *want = NULL; MFCreateMediaType(&want);
        IMFMediaType_SetGUID(want, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
        const GUID *sub = &MFVideoFormat_NV12;
        if (!strcmp(out,"argb")) sub = &MFVideoFormat_ARGB32;
        else if (!strcmp(out,"rgb32")) sub = &MFVideoFormat_RGB32;
        IMFMediaType_SetGUID(want, &MF_MT_SUBTYPE, sub);
        hr = IMFSourceReader_SetCurrentMediaType(reader, MF_SOURCE_READER_FIRST_VIDEO_STREAM, NULL, want);
        printf("SetCurrentMediaType(%s)=0x%08lx %s\n", out, (unsigned long)hr, SUCCEEDED(hr)?"":"*** rejected ***");
        IMFMediaType_Release(want);
    }

    /* read a few samples and inspect the D3D texture format (the crash point) */
    printf(">>> reading samples (this is where d3dmetal builds the texture)...\n");
    for (int i = 0; i < 5; ++i) {
        DWORD streamIndex=0, flags2=0; LONGLONG ts=0; IMFSample *samp = NULL;
        hr = IMFSourceReader_ReadSample(reader, MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0,
                                        &streamIndex, &flags2, &ts, &samp);
        if (FAILED(hr)) { printf("  ReadSample[%d]=0x%08lx FAILED\n", i, (unsigned long)hr); break; }
        if (flags2 & MF_SOURCE_READERF_ENDOFSTREAM) { printf("  EOF at %d\n", i); break; }
        if (!samp) { printf("  ReadSample[%d] no sample (flags=0x%lx)\n", i, (unsigned long)flags2); continue; }

        IMFMediaBuffer *buf = NULL;
        if (SUCCEEDED(IMFSample_GetBufferByIndex(samp, 0, &buf))) {
            IMFDXGIBuffer *dxb = NULL;
            if (SUCCEEDED(IMFMediaBuffer_QueryInterface(buf, &IID_IMFDXGIBuffer, (void**)&dxb))) {
                ID3D11Texture2D *tex = NULL;
                if (SUCCEEDED(IMFDXGIBuffer_GetResource(dxb, &IID_ID3D11Texture2D, (void**)&tex))) {
                    D3D11_TEXTURE2D_DESC d; ID3D11Texture2D_GetDesc(tex, &d);
                    printf("  sample[%d]: D3D TEXTURE format=%s  %ux%u\n", i, dxgi_name(d.Format), d.Width, d.Height);
                    ID3D11Texture2D_Release(tex);
                } else printf("  sample[%d]: IMFDXGIBuffer but GetResource failed\n", i);
                IMFDXGIBuffer_Release(dxb);
            } else {
                printf("  sample[%d]: SYSTEM-MEMORY buffer (not D3D-backed)\n", i);
            }
            IMFMediaBuffer_Release(buf);
        }
        IMFSample_Release(samp);
    }
    printf(">>> survived sample reads (no Metal abort)  === D3D PATH OK ===\n");

    if (reader) IMFSourceReader_Release(reader);
    if (attrs) IMFAttributes_Release(attrs);
    if (dxgimgr) IMFDXGIDeviceManager_Release(dxgimgr);
    if (ctx) ID3D11DeviceContext_Release(ctx);
    if (dev) ID3D11Device_Release(dev);
    MFShutdown();
    return 0;
}
