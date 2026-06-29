#include <gst/gst.h>
#define PACKAGE "gst-plugins-good"
extern gboolean gst_element_register_matroskademux(GstPlugin *plugin);
extern gboolean gst_element_register_matroskaparse(GstPlugin *plugin);
static gboolean plugin_init(GstPlugin *plugin){
    gboolean ok=FALSE;
    ok|=gst_element_register_matroskademux(plugin);
    ok|=gst_element_register_matroskaparse(plugin);
    return ok;
}
GST_PLUGIN_DEFINE(GST_VERSION_MAJOR,GST_VERSION_MINOR,matroska,
    "Matroska/WebM (winevideo)",plugin_init,"1.24.13","LGPL",
    "gst-plugins-good","https://winevideo.local")
