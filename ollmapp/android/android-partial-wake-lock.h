#pragma once

#include <glib.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

void ollmapp_android_set_partial_wake_lock (GtkWindow *window, gboolean enable);

G_END_DECLS
