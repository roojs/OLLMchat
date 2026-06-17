#include "android-gio-tls.h"

#include <gio/gio.h>
#include <gio/gtlsbackend.h>
#include <string.h>

/* Static glib-networking OpenSSL backend (gtk-android-builder#20). */
extern void g_io_openssl_load (gpointer module);

static char tls_backend_type_name[128];

static void
remember_backend_type (GTlsBackend *backend)
{
  const char *type_name = backend != NULL
      ? G_OBJECT_TYPE_NAME (backend)
      : "(null)";

  g_strlcpy (tls_backend_type_name, type_name,
             sizeof (tls_backend_type_name));
}

static void
log_tls_probe (GTlsBackend *backend)
{
  const gchar * const *system_data_dirs = g_get_system_data_dirs ();
  const char *system_data = (system_data_dirs != NULL &&
                             system_data_dirs[0] != NULL)
      ? system_data_dirs[0]
      : "(empty)";
  gboolean supports = backend != NULL
      && g_tls_backend_supports_tls (backend);

  g_message (
      "OLLMchat TLS: g_get_system_data_dirs[0]=%s backend=%s supports_tls=%d",
      system_data,
      backend != NULL ? G_OBJECT_TYPE_NAME (backend) : "(null)",
      supports);
}

static gboolean
backend_is_real (GTlsBackend *backend)
{
  const char *type_name;

  if (backend == NULL)
    return FALSE;

  type_name = G_OBJECT_TYPE_NAME (backend);
  return type_name != NULL && strcmp (type_name, "GDummyTlsBackend") != 0;
}

static gchar *
find_bundled_ca_cert_path (void)
{
  const gchar * const *data_dirs;
  gsize i;

  data_dirs = g_get_system_data_dirs ();
  if (data_dirs != NULL)
    {
      for (i = 0; data_dirs[i] != NULL; i++)
        {
          gchar *path =
              g_build_filename (data_dirs[i], "ssl", "certs",
                                "ca-certificates.crt", NULL);

          if (g_file_test (path, G_FILE_TEST_IS_REGULAR))
            return path;

          g_free (path);
        }
    }

  {
    const char *xdg_data_dirs = g_getenv ("XDG_DATA_DIRS");

    if (xdg_data_dirs != NULL && xdg_data_dirs[0] != '\0')
      {
        gchar *first = g_strdup (xdg_data_dirs);
        char *colon = strchr (first, G_SEARCHPATH_SEPARATOR);

        if (colon != NULL)
          *colon = '\0';

        gchar *path =
            g_build_filename (first, "ssl", "certs",
                              "ca-certificates.crt", NULL);

        g_free (first);
        if (g_file_test (path, G_FILE_TEST_IS_REGULAR))
          return path;

        g_free (path);
      }
  }

  return NULL;
}

const char *
ollmapp_android_gio_tls_backend_type_name (void)
{
  if (tls_backend_type_name[0] == '\0')
    return "(unknown)";

  return tls_backend_type_name;
}

void
ollmapp_apply_bundled_tls_database_to_session (GObject *session)
{
  g_autofree gchar *cert_file = NULL;
  GTlsDatabase *db;
  GError *error = NULL;

  if (session == NULL)
    return;

  cert_file = find_bundled_ca_cert_path ();
  if (cert_file == NULL)
    return;

  db = G_TLS_DATABASE (g_tls_file_database_new (cert_file, &error));
  if (db == NULL)
    {
      g_warning ("OLLMchat TLS: g_tls_file_database_new(%s): %s",
                 cert_file, error != NULL ? error->message : "unknown");
      g_clear_error (&error);
      return;
    }

  g_object_set (session, "tls-database", db, NULL);
  g_object_unref (db);
  g_message ("OLLMchat TLS: Soup.Session tls_database=%s", cert_file);
}

gboolean
ollmapp_configure_android_gio_tls_modules (void)
{
  GTlsBackend *backend;

  g_io_openssl_load (NULL);

  backend = g_tls_backend_get_default ();
  remember_backend_type (backend);
  log_tls_probe (backend);

  if (!backend_is_real (backend))
    {
      g_warning (
          "GIO TLS backend unavailable after g_io_openssl_load(NULL)");
      return FALSE;
    }

  return TRUE;
}

void
ollmapp_log_tls_trust_store (void)
{
  static const char *candidate_paths[] = {
    "/etc/ssl/certs/ca-certificates.crt",
    "/etc/ssl/certs/ca-bundle.crt",
    "/etc/ssl/cert.pem",
    "/system/etc/security/cacerts",
    NULL
  };
  g_autofree gchar *bundled = find_bundled_ca_cert_path ();
  gsize i;

  g_message (
      "OLLMchat TLS trust: bundled_ca=%s",
      bundled != NULL ? bundled : "(not found)");

  for (i = 0; candidate_paths[i] != NULL; i++)
    {
      const char *path = candidate_paths[i];
      gboolean exists = g_file_test (path,
                                     G_FILE_TEST_IS_REGULAR |
                                     G_FILE_TEST_IS_DIR);

      g_message ("OLLMchat TLS trust: path %s exists=%d", path, exists);
    }
}
