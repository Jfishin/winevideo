/* mf_probe.c -- hardened MF decode probe: prints native subtype + decode result */
#define COBJMACROS
#include <stdio.h>
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>

static void fourcc(const GUID*g,char*b){
  unsigned d=g->Data1; b[0]=d&0xff;b[1]=(d>>8)&0xff;b[2]=(d>>16)&0xff;b[3]=(d>>24)&0xff;b[4]=0;
  for(int i=0;i<4;i++) if(b[i]<32||b[i]>126) b[i]='.';
}

int main(int c,char**v){
  setvbuf(stdout,NULL,_IONBF,0);
  if(c<2){printf("usage: probe <file>\n");return 2;}
  WCHAR w[MAX_PATH]; MultiByteToWideChar(CP_ACP,0,v[1],-1,w,MAX_PATH);
  CoInitializeEx(NULL,COINIT_MULTITHREADED);
  HRESULT hr=MFStartup(MF_VERSION,MFSTARTUP_FULL);
  printf("[%s] MFStartup=0x%08lX\n",v[1],(unsigned long)hr);

  IMFAttributes*a=NULL; MFCreateAttributes(&a,1);
  if(a) IMFAttributes_SetUINT32(a,&MF_SOURCE_READER_ENABLE_ADVANCED_VIDEO_PROCESSING,TRUE);

  IMFSourceReader*r=NULL;
  hr=MFCreateSourceReaderFromURL(w,a,&r);
  printf("  CreateSourceReader=0x%08lX reader=%p\n",(unsigned long)hr,(void*)r);
  if(FAILED(hr)||!r){printf("  >>> NO SOURCE (no byte-stream handler / open failed)\n");goto end;}

  IMFMediaType*nt=NULL;
  hr=IMFSourceReader_GetNativeMediaType(r,(DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,0,&nt);
  printf("  GetNativeMediaType=0x%08lX\n",(unsigned long)hr);
  if(SUCCEEDED(hr)&&nt){
    GUID sub={0}; char fc[5]="????";
    if(SUCCEEDED(IMFMediaType_GetGUID(nt,&MF_MT_SUBTYPE,&sub))) fourcc(&sub,fc);
    UINT64 fs=0; UINT32 ww=0,hh=0;
    if(SUCCEEDED(IMFMediaType_GetUINT64(nt,&MF_MT_FRAME_SIZE,&fs))){ww=(UINT32)(fs>>32);hh=(UINT32)fs;}
    printf("  >>> DEMUXED: native video subtype=%08lX '%s' size=%ux%u\n",(unsigned long)sub.Data1,fc,ww,hh);
    IMFMediaType_Release(nt);
  } else { printf("  >>> source opened but NO video native type\n"); }

  IMFMediaType*ot=NULL; MFCreateMediaType(&ot);
  if(ot){
    IMFMediaType_SetGUID(ot,&MF_MT_MAJOR_TYPE,&MFMediaType_Video);
    IMFMediaType_SetGUID(ot,&MF_MT_SUBTYPE,&MFVideoFormat_NV12);
    hr=IMFSourceReader_SetCurrentMediaType(r,(DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,NULL,ot);
    printf("  SetOutput(NV12)=0x%08lX\n",(unsigned long)hr);
    if(FAILED(hr)){
      IMFMediaType_SetGUID(ot,&MF_MT_SUBTYPE,&MFVideoFormat_RGB32);
      hr=IMFSourceReader_SetCurrentMediaType(r,(DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,NULL,ot);
      printf("  SetOutput(RGB32)=0x%08lX\n",(unsigned long)hr);
    }
    IMFMediaType_Release(ot);
  }
  if(FAILED(hr)){printf("  >>> DEMUX OK but NO DECODER (output type rejected)\n");goto end;}

  DWORD flags=0; LONGLONG ts=0; IMFSample*s=NULL;
  hr=IMFSourceReader_ReadSample(r,(DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM,0,NULL,&flags,&ts,&s);
  printf("  ReadSample=0x%08lX flags=0x%lX sample=%p\n",(unsigned long)hr,(unsigned long)flags,(void*)s);
  if(SUCCEEDED(hr)&&s){
    IMFMediaBuffer*b=NULL; IMFSample_ConvertToContiguousBuffer(s,&b);
    if(b){DWORD len=0;BYTE*p=NULL;
      if(SUCCEEDED(IMFMediaBuffer_Lock(b,&p,NULL,&len))){printf("  >>> DECODED %lu bytes  === PASS ===\n",(unsigned long)len);IMFMediaBuffer_Unlock(b);}
      IMFMediaBuffer_Release(b);}
    IMFSample_Release(s);
  } else { printf("  >>> ReadSample produced no frame (hr/flags above)\n"); }
end:
  if(a)IMFAttributes_Release(a);
  if(r)IMFSourceReader_Release(r);
  MFShutdown(); CoUninitialize();
  return 0;
}
