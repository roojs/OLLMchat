#pragma once

#include <glib.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

void ollmapp_android_set_partial_wake_lock (GtkWindow *window, gboolean enable);
void ollmapp_android_set_streaming_foreground (GtkWindow *window, gboolean enable);
gboolean ollmapp_android_is_tablet (GtkWindow *window);
void ollmapp_android_lock_landscape (GtkWindow *window);

G_END_DECLS
