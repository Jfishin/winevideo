/* mfalloc_probe.c — does the MF video sample allocator (the one the winegstreamer
 * h264 decoder uses on SET_D3D_MANAGER) hand back a texture whose format MATCHES the
 * NV12 type it was initialized with, or does patch 0004 silently swap it to BGRA?
 *
 * If init=NV12 but the allocated D3D texture is BGRA, a direct-MFT consumer like UE
 * Electra that trusts the negotiated NV12 type will mis-sample -> black media texture.
 *
 * Build: x86_64-w64-mingw32-gcc mfalloc_probe.c -o mfalloc_probe.exe \
 *   -lmfplat -lmfuuid -lole32 -luuid -ld3d11 -ldxgi
 */
#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfobjects.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

static const char *fmt(DXGI_FORMAT f){
    switch(f){
        case 0: return "UNKNOWN(0) *** crash format ***";
        case DXGI_FORMAT_B8G8R8A8_UNORM: return "B8G8R8A8_UNORM(87) *** 0004 swapped to BGRA ***";
        case DXGI_FORMAT_NV12: return "NV12(103) (matches requested type)";
        case DXGI_FORMAT_R8G8B8A8_UNORM: return "R8G8B8A8_UNORM(28)";
        default: return "other";
    }
}

int main(void){
    setvbuf(stdout,NULL,_IONBF,0);
    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    printf("MFStartup=0x%08lx\n",(unsigned long)hr);

    ID3D11Device *dev=NULL; ID3D11DeviceContext *ctx=NULL; D3D_FEATURE_LEVEL fl;
    UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
    hr = D3D11CreateDevice(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,flags,NULL,0,D3D11_SDK_VERSION,&dev,&fl,&ctx);
    if(FAILED(hr)){ flags=D3D11_CREATE_DEVICE_BGRA_SUPPORT;
        hr=D3D11CreateDevice(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,flags,NULL,0,D3D11_SDK_VERSION,&dev,&fl,&ctx);}
    printf("D3D11CreateDevice=0x%08lx\n",(unsigned long)hr);
    if(FAILED(hr)) return 2;
    ID3D10Multithread *mt=NULL;
    if(SUCCEEDED(ID3D11Device_QueryInterface(dev,&IID_ID3D10Multithread,(void**)&mt))){
        ID3D10Multithread_SetMultithreadProtected(mt,TRUE); ID3D10Multithread_Release(mt);}

    UINT token=0; IMFDXGIDeviceManager *mgr=NULL;
    hr=MFCreateDXGIDeviceManager(&token,&mgr);
    if(SUCCEEDED(hr)) hr=IMFDXGIDeviceManager_ResetDevice(mgr,(IUnknown*)dev,token);
    printf("DXGIDeviceManager=0x%08lx\n",(unsigned long)hr);

    /* the exact allocator the winegstreamer h264 decoder uses */
    IMFVideoSampleAllocatorEx *alloc=NULL;
    hr=MFCreateVideoSampleAllocatorEx(&IID_IMFVideoSampleAllocatorEx,(void**)&alloc);
    printf("MFCreateVideoSampleAllocatorEx=0x%08lx\n",(unsigned long)hr);
    if(FAILED(hr)||!alloc) return 3;
    hr=IMFVideoSampleAllocatorEx_SetDirectXManager(alloc,(IUnknown*)mgr);
    printf("SetDirectXManager=0x%08lx\n",(unsigned long)hr);

    /* NV12 output type, 1160x674 — same as the decoder negotiates */
    IMFMediaType *t=NULL; MFCreateMediaType(&t);
    IMFMediaType_SetGUID(t,&MF_MT_MAJOR_TYPE,&MFMediaType_Video);
    IMFMediaType_SetGUID(t,&MF_MT_SUBTYPE,&MFVideoFormat_NV12);
    IMFMediaType_SetUINT64(t,&MF_MT_FRAME_SIZE,((UINT64)1160<<32)|674);
    IMFMediaType_SetUINT32(t,&MF_MT_INTERLACE_MODE,MFVideoInterlace_Progressive);

    IMFAttributes *aa=NULL; MFCreateAttributes(&aa,2);
    IMFAttributes_SetUINT32(aa,&MF_SA_D3D11_AWARE,TRUE);
    IMFAttributes_SetUINT32(aa,&MF_SA_D3D11_BINDFLAGS,D3D11_BIND_SHADER_RESOURCE|D3D11_BIND_RENDER_TARGET);

    hr=IMFVideoSampleAllocatorEx_InitializeSampleAllocatorEx(alloc,2,6,aa,t);
    printf("InitializeSampleAllocatorEx(NV12, D3D11)=0x%08lx %s\n",(unsigned long)hr, FAILED(hr)?"*** rejected ***":"");

    if(SUCCEEDED(hr)){
        IMFSample *s=NULL;
        hr=IMFVideoSampleAllocatorEx_AllocateSample(alloc,&s);
        printf("AllocateSample=0x%08lx\n",(unsigned long)hr);
        if(SUCCEEDED(hr)&&s){
            IMFMediaBuffer *b=NULL;
            if(SUCCEEDED(IMFSample_GetBufferByIndex(s,0,&b))){
                IMFDXGIBuffer *dx=NULL;
                if(SUCCEEDED(IMFMediaBuffer_QueryInterface(b,&IID_IMFDXGIBuffer,(void**)&dx))){
                    ID3D11Texture2D *tex=NULL;
                    if(SUCCEEDED(IMFDXGIBuffer_GetResource(dx,&IID_ID3D11Texture2D,(void**)&tex))){
                        D3D11_TEXTURE2D_DESC d; ID3D11Texture2D_GetDesc(tex,&d);
                        printf(">>> requested NV12, ALLOCATED D3D TEXTURE format=%s  %ux%u\n",fmt(d.Format),d.Width,d.Height);
                        printf(">>> VERDICT: %s\n", d.Format==DXGI_FORMAT_NV12 ? "MATCH (no mismatch)" :
                               d.Format==DXGI_FORMAT_B8G8R8A8_UNORM ? "MISMATCH — 0004 gave BGRA for an NV12 type (breaks direct consumers)" :
                               "unexpected format");
                        ID3D11Texture2D_Release(tex);
                    } else printf(">>> IMFDXGIBuffer but no texture\n");
                    IMFDXGIBuffer_Release(dx);
                } else printf(">>> SYSTEM-MEMORY sample (not D3D) — allocator did not use D3D\n");
                IMFMediaBuffer_Release(b);
            }
            IMFSample_Release(s);
        }
    }
    if(t)IMFMediaType_Release(t); if(aa)IMFAttributes_Release(aa);
    if(alloc)IMFVideoSampleAllocatorEx_Release(alloc);
    if(mgr)IMFDXGIDeviceManager_Release(mgr);
    if(ctx)ID3D11DeviceContext_Release(ctx); if(dev)ID3D11Device_Release(dev);
    MFShutdown();
    return 0;
}
