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
 * App namespace for the source-diff smoke window.
 *
 * Project and file selectors live here while they are
 * still in the smoke test. {@link Form} is the layout.
 *
 * == Example ==
 *
 * {{{
 * var coder = new CoderView(manager, Form.PHONE);
 * }}}
 */
namespace OLLMapp
{
	/**
	 * Layout of the project and file selectors.
	 *
	 * Desktop draws the lists on the editor. Phone and tablet
	 * use {@link SelectorPull}.
	 *
	 * == Example ==
	 *
	 * {{{
	 * var coder = new CoderView(manager, Form.PHONE);
	 * }}}
	 */
	enum Form {
		DESKTOP,
		PHONE,
		TABLET
	}

	/**
	 * Which file list a fetch fills.
	 *
	 * Recent is the desktop history list. Pullout is the
	 * phone and tablet page.
	 */
	enum Slot {
		HISTORY,
		PULLOUT
	}
}
