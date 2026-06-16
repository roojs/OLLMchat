#include "android-gio-tls.h"

#include <gio/gio.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

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
load_gio_tls_modules_from_dir (const char *module_dir)
{
  if (!try_set_gio_module_dir (module_dir))
    return FALSE;

  preload_openssl_libs_from_dir (module_dir);
  g_io_modules_scan_all_in_directory (module_dir);
  return g_tls_backend_get_default () != NULL;
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

void
ollmapp_configure_android_gio_tls_modules (void)
{
  Dl_info info;

  if (g_tls_backend_get_default () != NULL)
    return;

  try_preload_openssl_from_native_lib_dir ();

  if (try_gio_module_dir_from_xdg_data_dirs ())
    return;

  if (dladdr ((void *) ollmapp_configure_android_gio_tls_modules, &info) &&
      info.dli_fname != NULL)
    {
      g_autofree char *lib_dir = g_path_get_dirname (info.dli_fname);
      g_autofree char *module_dir =
          g_build_filename (lib_dir, "gio", "modules", NULL);

      if (load_gio_tls_modules_from_dir (module_dir))
        return;
    }

  g_autofree char *maps_dir = NULL;
  if (find_gio_module_dir_from_maps (&maps_dir) &&
      load_gio_tls_modules_from_dir (maps_dir))
    return;

  g_warning ("GIO TLS backend unavailable after scanning module directories "
             "(expected assets/share/gio/modules/libgioopenssl.so with "
             "libssl.so and libcrypto.so beside it on device)");

  /* Windows sqgipkg sets gtk_icon_theme: Adwaita; Android has no gsettings. */
  if (g_getenv ("GTK_ICON_THEME_NAME") == NULL)
    g_setenv ("GTK_ICON_THEME_NAME", "Adwaita", TRUE);
}
