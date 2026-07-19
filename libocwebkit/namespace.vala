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
 * WebKit browser tool for OLLMchat — accessibility-driven browsing.
 *
 * {@link Browser} is one WebView session. {@link BrowserStack} owns the
 * {@link Gtk.Stack} and primary browser (Snappr-style). {@link Tool} is the
 * OLLMchat tool wire name ''browser''.
 *
 * == Usage Examples ==
 *
 * === Chat session ===
 *
 * {{{
 * var stack = new OLLMwebkit.BrowserStack();
 * var tool = new OLLMwebkit.Tool();
 * tool.stack = stack;
 * manager.register_tool(tool);
 * }}}
 *
 * === Spike app ===
 *
 * {{{
 * // libocwebkit/examples/oc-test-webkit — embeds BrowserStack, CLI later
 * }}}
 */
namespace OLLMwebkit
{
}
