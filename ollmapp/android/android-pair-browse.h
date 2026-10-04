#pragma once

#include <glib.h>
#include <gtk/gtk.h>

G_BEGIN_DECLS

void ollmapp_android_pair_browse_start (GtkWindow *window);
char *ollmapp_android_pair_browse_poll (void);
void ollmapp_android_pair_browse_stop (GtkWindow *window);

G_END_DECLS
