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

namespace Markdown
{
	/**
	 * Marker map for delimiter runs that are valid at **end of line** ("?_").
	 * Used when the run is at end of line (closing delimiter).
	 * Contains only emphasis-style sequences (asterisk and underscore); no links, code, etc.
	 * No integration with parser yet - structure only.
	 */
	public class EndMap : MarkerMap
	{
		private static Gee.HashMap<string, FormatType> mp;

		private static void init()
		{
			if (mp != null) {
				return;
			}
			mp = new Gee.HashMap<string, FormatType>();

			// Asterisk sequences (valid closer at end of line)
			mp["*"] = FormatType.ITALIC_ASTERISK;
			mp["**"] = FormatType.BOLD_ASTERISK;
			mp["***"] = FormatType.BOLD_ITALIC_ASTERISK;

			// Underscore sequences (valid closer at end of line)
			mp["_"] = FormatType.ITALIC_UNDERSCORE;
			mp["__"] = FormatType.BOLD_UNDERSCORE;
			mp["___"] = FormatType.BOLD_ITALIC_UNDERSCORE;
		}

		public EndMap()
		{
			EndMap.init();
			base(EndMap.mp);
		}
	}
}
