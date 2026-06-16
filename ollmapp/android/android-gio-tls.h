#pragma once

#include <glib.h>
#include <glib-object.h>

G_BEGIN_DECLS

gboolean ollmapp_configure_android_gio_tls_modules (void);
const char *ollmapp_android_gio_tls_backend_type_name (void);
void ollmapp_log_tls_trust_store (void);

void ollmapp_apply_bundled_tls_database_to_session (GObject *session);

G_END_DECLS
