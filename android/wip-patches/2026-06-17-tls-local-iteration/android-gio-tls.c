#include "android-gio-tls.h"

#include <gio/gio.h>
#include <gio/gtlsbackend.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

/* Scan path in our GLib fork calls ensure_extension_points before loading modules. */

static char tls_backend_type_name[128];

static void
enable_gio_log_domains (void)
{
  if (g_getenv ("G_MESSAGES_DEBUG") == NULL)
    g_setenv ("G_MESSAGES_DEBUG", "GIO", TRUE);
}

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
log_tls_probe (const char *phase, GTlsBackend *backend)
{
  const char *module_dir = g_getenv ("GIO_MODULE_DIR");
  const char *xdg_env = g_getenv ("XDG_DATA_DIRS");
  const gchar * const *system_data_dirs = g_get_system_data_dirs ();
  const char *system_data = (system_data_dirs != NULL &&
                             system_data_dirs[0] != NULL)
      ? system_data_dirs[0]
      : "(empty)";
  gboolean supports = backend != NULL
      && g_tls_backend_supports_tls (backend);

  g_message (
      "OLLMchat TLS [%s]: GIO_MODULE_DIR=%s XDG_DATA_DIRS(env)=%s "
      "g_get_system_data_dirs[0]=%s backend=%s supports_tls=%d",
      phase,
      module_dir != NULL ? module_dir : "(unset)",
      xdg_env != NULL ? xdg_env : "(unset)",
      system_data,
      backend != NULL ? G_OBJECT_TYPE_NAME (backend) : "(null)",
      supports);
}

static void
preload_openssl_libs_from_dir (const char *dir)
{
  static const char *candidates[] = {
    "libcrypto.so",
    "libssl.so",
    "libcrypto.so.3",
    "libssl.so.3",
    NULL
  };
  gsize i;

  if (dir == NULL || dir[0] == '\0')
    return;

  for (i = 0; candidates[i] != NULL; i++)
    {
      g_autofree char *path = g_build_filename (dir, candidates[i], NULL);

      if (!g_file_test (path, G_FILE_TEST_IS_REGULAR))
        continue;

      if (dlopen (path, RTLD_NOW | RTLD_GLOBAL) == NULL)
        g_warning ("Failed to preload %s for GIO TLS: %s", path, dlerror ());
      else
        g_message ("OLLMchat TLS: preloaded %s", path);
    }
}

static gboolean
try_set_gio_module_dir (const char *module_dir)
{
  if (module_dir == NULL || module_dir[0] == '\0')
    return FALSE;

  if (!g_file_test (module_dir, G_FILE_TEST_IS_DIR))
    return FALSE;

  g_setenv ("GIO_MODULE_DIR", module_dir, TRUE);
  return TRUE;
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

static gboolean
load_gio_tls_modules_from_dir (const char *module_dir)
{
  GTlsBackend *backend;

  if (!try_set_gio_module_dir (module_dir))
    return FALSE;

  g_message ("OLLMchat TLS: scan %s", module_dir);
  g_io_modules_scan_all_in_directory (module_dir);

  backend = g_tls_backend_get_default ();
  remember_backend_type (backend);
  log_tls_probe ("after-scan", backend);

  return backend_is_real (backend);
}

static gboolean
module_dir_from_path (const char *path, char **out_dir)
{
  const char *marker = "/gio/modules";
  const char *found = strstr (path, marker);

  if (found == NULL)
    return FALSE;

  *out_dir = g_strndup (path, (gsize) (found - path + strlen (marker)));
  return TRUE;
}

static gboolean
try_gio_module_dir_from_env (void)
{
  const char *module_dir = g_getenv ("GIO_MODULE_DIR");

  if (module_dir == NULL || module_dir[0] == '\0')
    return FALSE;

  return load_gio_tls_modules_from_dir (module_dir);
}

static gboolean
try_gio_module_dir_from_system_data_dirs (void)
{
  const gchar * const *data_dirs = g_get_system_data_dirs ();
  gsize i;

  if (data_dirs == NULL)
    return FALSE;

  for (i = 0; data_dirs[i] != NULL; i++)
    {
      g_autofree char *module_dir =
          g_build_filename (data_dirs[i], "gio", "modules", NULL);

      if (load_gio_tls_modules_from_dir (module_dir))
        return TRUE;
    }

  return FALSE;
}

static gboolean
try_gio_module_dir_from_xdg_data_dirs (void)
{
  const char *xdg_data_dirs = g_getenv ("XDG_DATA_DIRS");

  if (xdg_data_dirs == NULL || xdg_data_dirs[0] == '\0')
    return FALSE;

  g_autofree char *first = g_strdup (xdg_data_dirs);
  char *colon = strchr (first, G_SEARCHPATH_SEPARATOR);

  if (colon != NULL)
    *colon = '\0';

  g_autofree char *module_dir =
      g_build_filename (first, "gio", "modules", NULL);

  return load_gio_tls_modules_from_dir (module_dir);
}

static gboolean
find_gio_module_dir_from_maps (char **out_dir)
{
  FILE *maps = fopen ("/proc/self/maps", "re");

  if (maps == NULL)
    return FALSE;

  char line[4096];
  while (fgets (line, sizeof (line), maps) != NULL)
    {
      char *path = strrchr (line, '/');

      if (path == NULL)
        continue;

      if (strstr (path, "/gio/modules") == NULL)
        continue;

      char *newline = strchr (path, '\n');
      if (newline != NULL)
        *newline = '\0';

      if (module_dir_from_path (path, out_dir))
        {
          fclose (maps);
          return TRUE;
        }
    }

  fclose (maps);
  return FALSE;
}

static gboolean
try_preload_openssl_from_native_lib_dir (void)
{
  Dl_info info;

  if (!dladdr ((void *) ollmapp_configure_android_gio_tls_modules, &info) ||
      info.dli_fname == NULL)
    return FALSE;

  g_autofree char *lib_dir = g_path_get_dirname (info.dli_fname);
  preload_openssl_libs_from_dir (lib_dir);
  return TRUE;
}

const char *
ollmapp_android_gio_tls_backend_type_name (void)
{
  if (tls_backend_type_name[0] == '\0')
    return "(unknown)";

  return tls_backend_type_name;
}

gboolean
ollmapp_configure_android_gio_tls_modules (void)
{
  GTlsBackend *backend;

  enable_gio_log_domains ();
  try_preload_openssl_from_native_lib_dir ();

  /* Path A (gdkandroidruntime.c) may have scanned modules already on the Java
   * main thread. Check before rescanning. */
  backend = g_tls_backend_get_default ();
  remember_backend_type (backend);
  log_tls_probe ("after-gdk", backend);
  if (backend_is_real (backend))
    {
      if (g_getenv ("GTK_ICON_THEME_NAME") == NULL)
        g_setenv ("GTK_ICON_THEME_NAME", "Adwaita", TRUE);
      return TRUE;
    }

  if (try_gio_module_dir_from_env ())
    {
      if (g_getenv ("GTK_ICON_THEME_NAME") == NULL)
        g_setenv ("GTK_ICON_THEME_NAME", "Adwaita", TRUE);
      return TRUE;
    }

  if (try_gio_module_dir_from_system_data_dirs ())
    {
      if (g_getenv ("GTK_ICON_THEME_NAME") == NULL)
        g_setenv ("GTK_ICON_THEME_NAME", "Adwaita", TRUE);
      return TRUE;
    }

  if (try_gio_module_dir_from_xdg_data_dirs ())
    {
      if (g_getenv ("GTK_ICON_THEME_NAME") == NULL)
        g_setenv ("GTK_ICON_THEME_NAME", "Adwaita", TRUE);
      return TRUE;
    }

  Dl_info info;

  if (dladdr ((void *) ollmapp_configure_android_gio_tls_modules, &info) &&
      info.dli_fname != NULL)
    {
      g_autofree char *lib_dir = g_path_get_dirname (info.dli_fname);
      g_autofree char *module_dir =
          g_build_filename (lib_dir, "gio", "modules", NULL);

      if (load_gio_tls_modules_from_dir (module_dir))
        {
          if (g_getenv ("GTK_ICON_THEME_NAME") == NULL)
            g_setenv ("GTK_ICON_THEME_NAME", "Adwaita", TRUE);
          return TRUE;
        }
    }

  g_autofree char *maps_dir = NULL;
  if (find_gio_module_dir_from_maps (&maps_dir) &&
      load_gio_tls_modules_from_dir (maps_dir))
    {
      if (g_getenv ("GTK_ICON_THEME_NAME") == NULL)
        g_setenv ("GTK_ICON_THEME_NAME", "Adwaita", TRUE);
      return TRUE;
    }

  g_warning ("GIO TLS backend unavailable after scanning module directories "
             "(expected assets/share/gio/modules/libgioopenssl.so on device; "
             "libssl/libcrypto must be preloaded from lib/arm64-v8a/)");

  if (g_getenv ("GTK_ICON_THEME_NAME") == NULL)
    g_setenv ("GTK_ICON_THEME_NAME", "Adwaita", TRUE);

  return FALSE;
}
