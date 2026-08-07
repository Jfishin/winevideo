/* mf2d_probe.c -- decode one frame like mf_probe, then replicate UE Electra's
 * exact requirement: QI the frame's media buffer for IMF2DBuffer and Lock2D.
 * Black-cutscene root cause for Screamer: Electra rejects frames whose buffer
 * is not 2D-capable. PASS here = the decoder chain hands out 2D buffers. */
#define COBJMACROS
#include <stdio.h>
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>

int main(int c,char**v){
  setvbuf(stdout,NULL,_IONBF,0);
  if(c<2){printf("usage: mf2d_probe <file>\n");return 2;}
  WCHAR w[MAX_PATH]; MultiByteToWideChar(CP_ACP,0,v[1],-1,w,MAX_PATH);
  CoInitializeEx(NULL,COINIT_MULTITHREADED);
  HRESULT hr=MFStartup(MF_VERSION,MFSTARTUP_FULL);
  printf("[%s] MFStartup=0x%08lX\n",v[1],(unsigned long)hr);

  IMFSourceReader*r=NULL;
  hr=MFCreateSourceReaderFromURL(w,NULL,&r);
  printf("  CreateSourceReader=0x%08lX\n",(unsigned long)hr);
  if(FAILED(hr)||!r) goto end;

  IMFMediaType*ot=NULL; MFCreateMediaType(&ot);
  IMFMediaType_SetGUID(ot,&MF_MT_MAJOR_TYPE,&MFMediaType_Video);
  IMFMediaType_SetGUID(ot,&MF_MT_SUBTYPE,&MFVideoFormat_NV12);
  hr=IMFSourceReader_SetCurrentMediaType(r,(DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,NULL,ot);
  IMFMediaType_Release(ot);
  printf("  SetOutput(NV12)=0x%08lX\n",(unsigned long)hr);
  if(FAILED(hr)) goto end;

  DWORD flags=0; LONGLONG ts=0; IMFSample*s=NULL;
  hr=IMFSourceReader_ReadSample(r,(DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,0,NULL,&flags,&ts,&s);
  printf("  ReadSample=0x%08lX flags=0x%lX sample=%p\n",(unsigned long)hr,(unsigned long)flags,(void*)s);
  if(FAILED(hr)||!s){printf("  >>> NO FRAME === FAIL ===\n");goto end;}

  DWORD bufcount=0; IMFSample_GetBufferCount(s,&bufcount);
  IMFMediaBuffer*b=NULL;
  hr=IMFSample_GetBufferByIndex(s,0,&b);
  printf("  GetBufferByIndex(0)=0x%08lX bufcount=%lu\n",(unsigned long)hr,(unsigned long)bufcount);
  if(FAILED(hr)||!b){printf("  >>> NO BUFFER === FAIL ===\n");goto end;}

  /* Electra's gate: */
  IMF2DBuffer*b2=NULL;
  hr=IMFMediaBuffer_QueryInterface(b,&IID_IMF2DBuffer,(void**)&b2);
  printf("  QI(IMF2DBuffer)=0x%08lX\n",(unsigned long)hr);
  if(SUCCEEDED(hr)&&b2){
    BYTE*scan0=NULL; LONG pitch=0;
    hr=IMF2DBuffer_Lock2D(b2,&scan0,&pitch);
    printf("  Lock2D=0x%08lX scanline0=%p pitch=%ld\n",(unsigned long)hr,(void*)scan0,(long)pitch);
    if(SUCCEEDED(hr)){IMF2DBuffer_Unlock2D(b2);printf("  >>> 2D BUFFER OK === PASS ===\n");}
    else printf("  >>> Lock2D failed === FAIL ===\n");
    IMF2DBuffer_Release(b2);
  } else {
    printf("  >>> buffer is NOT IMF2DBuffer === FAIL (Electra would reject) ===\n");
  }
  IMFMediaBuffer_Release(b);
  IMFSample_Release(s);
end:
  if(r)IMFSourceReader_Release(r);
  MFShutdown(); CoUninitialize();
  return 0;
}
