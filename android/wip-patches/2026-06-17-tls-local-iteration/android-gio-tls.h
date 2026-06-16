#pragma once

#include <glib.h>

G_BEGIN_DECLS

gboolean ollmapp_configure_android_gio_tls_modules (void);
const char *ollmapp_android_gio_tls_backend_type_name (void);

G_END_DECLS
