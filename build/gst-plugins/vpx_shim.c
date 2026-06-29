#include <gst/gst.h>
#define PACKAGE "gst-plugins-good"
extern gboolean gst_element_register_vp8dec(GstPlugin *plugin);
extern gboolean gst_element_register_vp9dec(GstPlugin *plugin);
static gboolean plugin_init(GstPlugin *plugin)
{
    gboolean ok = FALSE;
    ok |= gst_element_register_vp8dec(plugin);
    ok |= gst_element_register_vp9dec(plugin);
    return ok;
}
GST_PLUGIN_DEFINE(GST_VERSION_MAJOR, GST_VERSION_MINOR, vpx,
    "VPx decoders (winevideo)", plugin_init, "1.24.13", "LGPL",
    "gst-plugins-good", "https://winevideo.local")
