/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

/**
 * Temporary Android stand-in for libadwaita 1.6 ''Adw.Spinner''.
 *
 * The Android VAPI has no Spinner. This is a ''Gtk.Spinner'' that
 * starts spinning. Desktop builds use the real widget and do not
 * compile this file.
 */
public class Adw.Spinner : Gtk.Spinner
{
	public Spinner()
	{
		Object(spinning: true);
	}
}
