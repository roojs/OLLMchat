#pragma once

#include <glib.h>

G_BEGIN_DECLS

gboolean ocrpc_cert_create_pem_files (const gchar *cert_path,
                                      const gchar *key_path,
                                      const gchar *cn,
                                      gboolean server_san,
                                      const gchar *ca_pem_path,
                                      const gchar *ca_key_path,
                                      GError **error);

gboolean ocrpc_cert_write_csr (const gchar *key_path,
                               const gchar *csr_path,
                               const gchar *cn,
                               GError **error);

G_END_DECLS
