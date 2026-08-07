/* mf_probe_d3d12.c — reproduce NG4's EXACT crash path on d3dmetal.
 * NG4 is a D3D12 title (d3dmetal). For Media Foundation video it uses a
 * D3D11On12 device layered on its D3D12 (d3dmetal) device, hands that to the
 * SourceReader via MF_SOURCE_READER_D3D_MANAGER, and the decoded VP9 frame is
 * allocated as a D3D texture on d3dmetal — where it dies with Metal
 * "MTLTextureDescriptor has invalid pixelFormat (0)".
 *
 * Plain D3D11 does not reach d3dmetal here; only the D3D12+D3D11On12 path does.
 *
 * Build (llvm-mingw):
 *   x86_64-w64-mingw32-gcc mf_probe_d3d12.c -o mf_probe_d3d12.exe \
 *     -lmfplat -lmfreadwrite -lmfuuid -lmf -lole32 -luuid -ld3d12 -ld3d11 -ldxgi
 * Run (force d3dmetal):
 *   CX_GRAPHICS_BACKEND=d3dmetal CX_BOTTLE=Test <app>/bin/wine \
 *     mf_probe_d3d12.exe 'C:\mftest\ng4_real.msd' [nv12|argb|rgb32|none]
 */
#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <d3d12.h>
#include <d3d11on12.h>
#include <d3d11.h>
#include <dxgi1_4.h>
#include <stdio.h>

static const char *dxgi_name(DXGI_FORMAT f){
    switch(f){
        case 0: return "UNKNOWN(0) *** CRASH FORMAT ***";
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
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc > 1) { MultiByteToWideChar(CP_ACP,0,argv[1],-1,wbuf,1024); url = wbuf; }

    hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    printf("MFStartup=0x%08lx\n", (unsigned long)hr);

    /* --- D3D12 device (d3dmetal) --- */
    ID3D12Device *dev12 = NULL;
    hr = D3D12CreateDevice(NULL, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void**)&dev12);
    printf("D3D12CreateDevice=0x%08lx %s\n", (unsigned long)hr, FAILED(hr)?"*** no D3D12/d3dmetal ***":"(d3dmetal)");
    if (FAILED(hr)) return 2;

    D3D12_COMMAND_QUEUE_DESC qd; ZeroMemory(&qd,sizeof(qd));
    qd.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    ID3D12CommandQueue *queue = NULL;
    hr = ID3D12Device_CreateCommandQueue(dev12, &qd, &IID_ID3D12CommandQueue, (void**)&queue);
    printf("CreateCommandQueue=0x%08lx\n", (unsigned long)hr);

    /* --- D3D11On12 device on top of the d3dmetal D3D12 device --- */
    ID3D11Device *dev11 = NULL; ID3D11DeviceContext *ctx11 = NULL;
    IUnknown *queues[1] = { (IUnknown*)queue };
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
    hr = D3D11On12CreateDevice((IUnknown*)dev12, flags, NULL, 0, queues, 1, 0, &dev11, &ctx11, NULL);
    if (FAILED(hr)) {
        printf("D3D11On12CreateDevice(VIDEO)=0x%08lx, retry without VIDEO_SUPPORT\n",(unsigned long)hr);
        flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
        hr = D3D11On12CreateDevice((IUnknown*)dev12, flags, NULL, 0, queues, 1, 0, &dev11, &ctx11, NULL);
    }
    printf("D3D11On12CreateDevice=0x%08lx %s\n", (unsigned long)hr, FAILED(hr)?"*** failed ***":"");
    if (FAILED(hr)) return 3;

    ID3D10Multithread *mt = NULL;
    if (SUCCEEDED(ID3D11Device_QueryInterface(dev11,&IID_ID3D10Multithread,(void**)&mt))) {
        ID3D10Multithread_SetMultithreadProtected(mt, TRUE); ID3D10Multithread_Release(mt);
    }

    UINT token = 0; IMFDXGIDeviceManager *mgr = NULL;
    hr = MFCreateDXGIDeviceManager(&token, &mgr);
    printf("MFCreateDXGIDeviceManager=0x%08lx\n", (unsigned long)hr);
    hr = IMFDXGIDeviceManager_ResetDevice(mgr, (IUnknown*)dev11, token);
    printf("ResetDevice(D3D11On12)=0x%08lx\n", (unsigned long)hr);

    IMFAttributes *attrs = NULL; MFCreateAttributes(&attrs, 4);
    IMFAttributes_SetUnknown(attrs, &MF_SOURCE_READER_D3D_MANAGER, (IUnknown*)mgr);
    IMFAttributes_SetUINT32(attrs, &MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING, TRUE);

    IMFSourceReader *reader = NULL;
    hr = MFCreateSourceReaderFromURL(url, attrs, &reader);
    printf("CreateSourceReader(D3D11On12)=0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 4;

    IMFMediaType *nt = NULL;
    if (SUCCEEDED(IMFSourceReader_GetNativeMediaType(reader, MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &nt))) {
        GUID sub; IMFMediaType_GetGUID(nt, &MF_MT_SUBTYPE, &sub);
        printf(">>> native subtype=%08lx\n", (unsigned long)sub.Data1);
        IMFMediaType_Release(nt);
    }
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

    printf(">>> reading samples (d3dmetal builds the texture here)...\n");
    for (int i = 0; i < 5; ++i) {
        DWORD si=0, fl=0; LONGLONG ts=0; IMFSample *samp = NULL;
        hr = IMFSourceReader_ReadSample(reader, MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &si, &fl, &ts, &samp);
        if (FAILED(hr)) { printf("  ReadSample[%d]=0x%08lx FAILED\n", i, (unsigned long)hr); break; }
        if (fl & MF_SOURCE_READERF_ENDOFSTREAM) { printf("  EOF at %d\n", i); break; }
        if (!samp) { printf("  ReadSample[%d] no sample (flags=0x%lx)\n", i, (unsigned long)fl); continue; }
        IMFMediaBuffer *buf = NULL;
        if (SUCCEEDED(IMFSample_GetBufferByIndex(samp, 0, &buf))) {
            IMFDXGIBuffer *dxb = NULL;
            if (SUCCEEDED(IMFMediaBuffer_QueryInterface(buf, &IID_IMFDXGIBuffer, (void**)&dxb))) {
                ID3D11Texture2D *tex = NULL;
                if (SUCCEEDED(IMFDXGIBuffer_GetResource(dxb, &IID_ID3D11Texture2D, (void**)&tex))) {
                    D3D11_TEXTURE2D_DESC d; ID3D11Texture2D_GetDesc(tex, &d);
                    printf("  sample[%d]: D3D TEXTURE format=%s  %ux%u\n", i, dxgi_name(d.Format), d.Width, d.Height);
                    ID3D11Texture2D_Release(tex);
                } else printf("  sample[%d]: IMFDXGIBuffer GetResource failed\n", i);
                IMFDXGIBuffer_Release(dxb);
            } else printf("  sample[%d]: SYSTEM-MEMORY buffer\n", i);
            IMFMediaBuffer_Release(buf);
        }
        IMFSample_Release(samp);
    }
    printf(">>> survived sample reads (no Metal abort)  === D3D11On12 PATH OK ===\n");

    if (reader) IMFSourceReader_Release(reader);
    if (mgr) IMFDXGIDeviceManager_Release(mgr);
    if (ctx11) ID3D11DeviceContext_Release(ctx11);
    if (dev11) ID3D11Device_Release(dev11);
    if (queue) ID3D12CommandQueue_Release(queue);
    if (dev12) ID3D12Device_Release(dev12);
    MFShutdown();
    return 0;
}
