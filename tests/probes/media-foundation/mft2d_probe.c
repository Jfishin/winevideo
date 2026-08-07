/* mft2d_probe.c -- drive the H264 decoder MFT DIRECTLY like UE Electra does:
 * create via CLSID, SetInput(H264)/SetOutput(NV12), feed raw annex-B chunks,
 * pump ProcessOutput, then replicate Electra's gate on the produced frame:
 * GetBufferByIndex(0) -> QI IMF2DBuffer -> Lock2D.
 * Also verifies GetOutputStreamInfo reports PROVIDES_SAMPLES (patch 0008).
 * Input: a raw .h264 elementary stream (ffmpeg -bsf:v h264_mp4toannexb). */
#define COBJMACROS
#include <stdio.h>
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mftransform.h>
#include <mferror.h>

/* CLSID_MSH264DecoderMFT comes from mfidl.h */

int main(int c,char**v){
  setvbuf(stdout,NULL,_IONBF,0);
  if(c<2){printf("usage: mft2d_probe <file.h264>\n");return 2;}
  CoInitializeEx(NULL,COINIT_MULTITHREADED);
  HRESULT hr=MFStartup(MF_VERSION,MFSTARTUP_FULL);
  printf("MFStartup=0x%08lX\n",(unsigned long)hr);

  IMFTransform*t=NULL;
  hr=CoCreateInstance(&CLSID_MSH264DecoderMFT,NULL,CLSCTX_INPROC_SERVER,&IID_IMFTransform,(void**)&t);
  printf("CoCreate(H264 MFT)=0x%08lX\n",(unsigned long)hr);
  if(FAILED(hr)||!t) goto end;

  IMFMediaType*it=NULL; MFCreateMediaType(&it);
  IMFMediaType_SetGUID(it,&MF_MT_MAJOR_TYPE,&MFMediaType_Video);
  IMFMediaType_SetGUID(it,&MF_MT_SUBTYPE,&MFVideoFormat_H264);
  IMFMediaType_SetUINT64(it,&MF_MT_FRAME_SIZE,((UINT64)1920<<32)|1080);
  hr=IMFTransform_SetInputType(t,0,it,0);
  printf("SetInputType(H264)=0x%08lX\n",(unsigned long)hr);
  IMFMediaType_Release(it);
  if(FAILED(hr)) goto end;

  /* pick NV12 from available output types, like Electra */
  IMFMediaType*ot=NULL; DWORD i=0; GUID sub={0}; BOOL got_nv12=FALSE;
  while(SUCCEEDED(IMFTransform_GetOutputAvailableType(t,0,i++,&ot))){
    IMFMediaType_GetGUID(ot,&MF_MT_SUBTYPE,&sub);
    if(IsEqualGUID(&sub,&MFVideoFormat_NV12)){got_nv12=TRUE;break;}
    IMFMediaType_Release(ot); ot=NULL;
  }
  printf("NV12 enumerable=%d\n",(int)got_nv12);
  if(!got_nv12) {printf(">>> NV12 missing from enumeration === FAIL ===\n"); goto end;}
  hr=IMFTransform_SetOutputType(t,0,ot,0);
  printf("SetOutputType(NV12)=0x%08lX\n",(unsigned long)hr);
  IMFMediaType_Release(ot);
  if(FAILED(hr)) goto end;

  MFT_OUTPUT_STREAM_INFO osi={0};
  IMFTransform_GetOutputStreamInfo(t,0,&osi);
  printf("OutputStreamInfo flags=0x%08lX cbSize=%lu (PROVIDES_SAMPLES=%d)\n",
      (unsigned long)osi.dwFlags,(unsigned long)osi.cbSize,
      !!(osi.dwFlags&MFT_OUTPUT_STREAM_PROVIDES_SAMPLES));

  IMFTransform_ProcessMessage(t,MFT_MESSAGE_NOTIFY_BEGIN_STREAMING,0);
  IMFTransform_ProcessMessage(t,MFT_MESSAGE_NOTIFY_START_OF_STREAM,0);

  FILE*f=fopen(v[1],"rb");
  if(!f){printf("cannot open %s\n",v[1]);goto end;}

  #define CHUNK (256*1024)
  BYTE*chunk=malloc(CHUNK);
  int frames=0, pushes=0;
  LONGLONG pts=0;
  for(int iter=0; iter<400 && frames<3; iter++){
    /* pull outputs until NEED_MORE_INPUT */
    for(;;){
      MFT_OUTPUT_DATA_BUFFER ob={0}; DWORD st=0;
      if(!(osi.dwFlags&(MFT_OUTPUT_STREAM_PROVIDES_SAMPLES|MFT_OUTPUT_STREAM_CAN_PROVIDE_SAMPLES))){
        printf(">>> MFT does not provide samples; Electra-style NULL-sample call would fail === INFO ===\n");
      }
      hr=IMFTransform_ProcessOutput(t,0,1,&ob,&st);
      if(hr==MF_E_TRANSFORM_STREAM_CHANGE){
        IMFMediaType*nt=NULL;
        if(SUCCEEDED(IMFTransform_GetOutputAvailableType(t,0,0,&nt))){
          GUID s2; IMFMediaType_GetGUID(nt,&MF_MT_SUBTYPE,&s2);
          UINT64 fs=0; IMFMediaType_GetUINT64(nt,&MF_MT_FRAME_SIZE,&fs);
          hr=IMFTransform_SetOutputType(t,0,nt,0);
          printf("STREAM_CHANGE -> renegotiated %ux%u hr=0x%08lX\n",(unsigned)(fs>>32),(unsigned)fs,(unsigned long)hr);
          IMFMediaType_Release(nt);
          IMFTransform_GetOutputStreamInfo(t,0,&osi);
          continue;
        }
        break;
      }
      if(FAILED(hr)) break; /* NEED_MORE_INPUT etc. */
      if(ob.pSample){
        frames++;
        printf("FRAME %d delivered, status=0x%lX\n",frames,(unsigned long)ob.dwStatus);
        IMFMediaBuffer*b=NULL;
        if(SUCCEEDED(IMFSample_GetBufferByIndex(ob.pSample,0,&b))&&b){
          IMF2DBuffer*b2=NULL;
          HRESULT q=IMFMediaBuffer_QueryInterface(b,&IID_IMF2DBuffer,(void**)&b2);
          printf("  QI(IMF2DBuffer)=0x%08lX\n",(unsigned long)q);
          if(SUCCEEDED(q)&&b2){
            BYTE*scan0=NULL; LONG pitch=0;
            q=IMF2DBuffer_Lock2D(b2,&scan0,&pitch);
            printf("  Lock2D=0x%08lX pitch=%ld\n",(unsigned long)q,(long)pitch);
            if(SUCCEEDED(q)){IMF2DBuffer_Unlock2D(b2);printf("  >>> 2D BUFFER OK === PASS ===\n");}
            IMF2DBuffer_Release(b2);
          } else printf("  >>> NOT IMF2DBuffer === FAIL (Electra rejects) ===\n");
          IMFMediaBuffer_Release(b);
        }
        IMFSample_Release(ob.pSample);
      }
      if(ob.pEvents) IMFCollection_Release(ob.pEvents);
    }
    /* feed next chunk */
    size_t n=fread(chunk,1,CHUNK,f);
    if(!n) break;
    IMFSample*s=NULL; IMFMediaBuffer*mb=NULL; BYTE*p=NULL; DWORD ml=0;
    MFCreateSample(&s); MFCreateMemoryBuffer((DWORD)n,&mb);
    IMFMediaBuffer_Lock(mb,&p,&ml,NULL); memcpy(p,chunk,n); IMFMediaBuffer_Unlock(mb);
    IMFMediaBuffer_SetCurrentLength(mb,(DWORD)n);
    IMFSample_AddBuffer(s,mb); IMFMediaBuffer_Release(mb);
    IMFSample_SetSampleTime(s,pts); pts+=400000;
    hr=IMFTransform_ProcessInput(t,0,s,0);
    pushes++;
    IMFSample_Release(s);
    if(FAILED(hr)&&hr!=MF_E_NOTACCEPTING){printf("ProcessInput=0x%08lX at push %d\n",(unsigned long)hr,pushes);break;}
  }
  printf("done: %d pushes, %d frames\n",pushes,frames);
  if(!frames) printf(">>> NO FRAMES DECODED === FAIL ===\n");
  fclose(f); free(chunk);
end:
  if(t)IMFTransform_Release(t);
  MFShutdown(); CoUninitialize();
  return 0;
}
