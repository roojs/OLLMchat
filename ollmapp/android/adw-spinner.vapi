/* Android pixie libadwaita VAPI has no Spinner. The C library does.
 * This binds adw_spinner_new. Desktop uses the real libadwaita VAPI.
 * cheader is adwaita.h: adw-spinner.h refuses a direct include.
 */
[CCode (cprefix = "Adw", lower_case_cprefix = "adw_")]
namespace Adw {
	[CCode (cheader_filename = "adwaita.h", type_id = "adw_spinner_get_type ()")]
	public sealed class Spinner : Gtk.Widget {
		[CCode (has_construct_function = false, type = "GtkWidget*")]
		public Spinner ();
	}
}
