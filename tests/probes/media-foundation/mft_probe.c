/* mft_probe.c — replicate a game's "is VP9 supported?" capability check.
 * Games like Ninja Gaiden 4 call MFTEnumEx(MFT_CATEGORY_VIDEO_DECODER, ...,
 * inputType={Video,VP90}, ...) and bail with a "Failed to Play VP9" dialog if
 * the count is 0. This tool prints the count for a given codec and lists the
 * friendly names of every registered video-decoder MFT.
 *
 * Build (llvm-mingw):
 *   x86_64-w64-mingw32-gcc mft_probe.c -o mft_probe.exe \
 *       -lmfplat -lmfuuid -lole32 -luuid
 * Run:
 *   CX_BOTTLE=Test <app>/bin/wine mft_probe.exe vp9   (or: h264 av1 hevc all)
 */
#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mftransform.h>
#include <mferror.h>
#include <stdio.h>

static const GUID MY_MFVideoFormat_VP90 =
    {0x30395056,0x0000,0x0010,{0x80,0x00,0x00,0xaa,0x00,0x38,0x9b,0x71}};
static const GUID MY_MFVideoFormat_VP80 =
    {0x30385056,0x0000,0x0010,{0x80,0x00,0x00,0xaa,0x00,0x38,0x9b,0x71}};
static const GUID MY_MFVideoFormat_AV1 =
    {0x31305641,0x0000,0x0010,{0x80,0x00,0x00,0xaa,0x00,0x38,0x9b,0x71}};
static const GUID MY_MFVideoFormat_H264 =
    {0x34363248,0x0000,0x0010,{0x80,0x00,0x00,0xaa,0x00,0x38,0x9b,0x71}};
static const GUID MY_MFVideoFormat_HEVC =
    {0x43564548,0x0000,0x0010,{0x80,0x00,0x00,0xaa,0x00,0x38,0x9b,0x71}};

static int enum_for(const char *label, const GUID *subtype)
{
    MFT_REGISTER_TYPE_INFO in;
    IMFActivate **acts = NULL;
    UINT32 count = 0, i;
    HRESULT hr;

    in.guidMajorType = MFMediaType_Video;
    in.guidSubtype   = *subtype;

    hr = MFTEnumEx(MFT_CATEGORY_VIDEO_DECODER, MFT_ENUM_FLAG_ALL,
                   &in, NULL, &acts, &count);
    if (FAILED(hr)) {
        printf("[%s] MFTEnumEx FAILED hr=0x%08lx\n", label, (unsigned long)hr);
        return 0;
    }
    printf("[%s] MFTEnumEx -> %u decoder(s)  %s\n", label, count,
           count ? "=== ADVERTISED (probe PASSES) ===" : "*** NONE (game would bail) ***");
    for (i = 0; i < count; ++i) {
        WCHAR name[256] = {0};
        UINT32 len = 0;
        if (SUCCEEDED(IMFActivate_GetString(acts[i], &MFT_FRIENDLY_NAME_Attribute,
                                            name, 256, &len)))
            printf("        - %ls\n", name);
        else
            printf("        - (unnamed MFT)\n");
        IMFActivate_Release(acts[i]);
    }
    if (acts) CoTaskMemFree(acts);
    return (int)count;
}

/* Prove the enumerated VP9 MFT is real: activate it, then negotiate VP9->NV12. */
static void instantiate_vp9(void)
{
    MFT_REGISTER_TYPE_INFO in = { MFMediaType_Video, MY_MFVideoFormat_VP90 };
    IMFActivate **acts = NULL;
    UINT32 count = 0;
    HRESULT hr;
    IMFTransform *mft = NULL;
    IMFMediaType *it = NULL, *ot = NULL;

    hr = MFTEnumEx(MFT_CATEGORY_VIDEO_DECODER, MFT_ENUM_FLAG_ALL, &in, NULL, &acts, &count);
    if (FAILED(hr) || !count) { printf("[VP9-instantiate] nothing to activate\n"); return; }

    hr = IMFActivate_ActivateObject(acts[0], &IID_IMFTransform, (void **)&mft);
    printf("[VP9-instantiate] ActivateObject       hr=0x%08lx %s\n",
           (unsigned long)hr, SUCCEEDED(hr) ? "(MFT created)" : "*** FAILED ***");
    if (SUCCEEDED(hr)) {
        MFCreateMediaType(&it);
        IMFMediaType_SetGUID(it, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
        IMFMediaType_SetGUID(it, &MF_MT_SUBTYPE, &MY_MFVideoFormat_VP90);
        IMFMediaType_SetUINT64(it, &MF_MT_FRAME_SIZE, ((UINT64)1920 << 32) | 1080);
        hr = IMFTransform_SetInputType(mft, 0, it, 0);
        printf("[VP9-instantiate] SetInputType(VP90)   hr=0x%08lx %s\n",
               (unsigned long)hr, SUCCEEDED(hr) ? "(accepts VP9)" : "*** FAILED ***");

        MFCreateMediaType(&ot);
        IMFMediaType_SetGUID(ot, &MF_MT_MAJOR_TYPE, &MFMediaType_Video);
        IMFMediaType_SetGUID(ot, &MF_MT_SUBTYPE, &MFVideoFormat_NV12);
        IMFMediaType_SetUINT64(ot, &MF_MT_FRAME_SIZE, ((UINT64)1920 << 32) | 1080);
        hr = IMFTransform_SetOutputType(mft, 0, ot, 0);
        printf("[VP9-instantiate] SetOutputType(NV12)  hr=0x%08lx %s\n",
               (unsigned long)hr, SUCCEEDED(hr) ? "=== REAL VP9 DECODER MFT ===" : "*** FAILED ***");
        if (ot) IMFMediaType_Release(ot);
        if (it) IMFMediaType_Release(it);
        IMFTransform_Release(mft);
    }
    for (UINT32 i = 0; i < count; ++i) IMFActivate_Release(acts[i]);
    if (acts) CoTaskMemFree(acts);
}

int main(int argc, char **argv)
{
    const char *which = (argc > 1) ? argv[1] : "vp9";
    HRESULT hr;

    hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    if (FAILED(hr)) { printf("MFStartup failed 0x%08lx\n", (unsigned long)hr); return 2; }

    printf("=== MFT capability probe (category: VIDEO_DECODER) ===\n");
    if (!strcmp(which, "all")) {
        enum_for("H264", &MY_MFVideoFormat_H264);
        enum_for("HEVC", &MY_MFVideoFormat_HEVC);
        enum_for("VP8",  &MY_MFVideoFormat_VP80);
        enum_for("VP9",  &MY_MFVideoFormat_VP90);
        enum_for("AV1",  &MY_MFVideoFormat_AV1);
        instantiate_vp9();
    } else if (!strcmp(which, "h264")) enum_for("H264", &MY_MFVideoFormat_H264);
    else if (!strcmp(which, "hevc"))   enum_for("HEVC", &MY_MFVideoFormat_HEVC);
    else if (!strcmp(which, "av1"))    enum_for("AV1",  &MY_MFVideoFormat_AV1);
    else if (!strcmp(which, "vp8"))    enum_for("VP8",  &MY_MFVideoFormat_VP80);
    else { enum_for("VP9", &MY_MFVideoFormat_VP90); instantiate_vp9(); }

    MFShutdown();
    return 0;
}
