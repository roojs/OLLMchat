/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace OLLMcoder.Action
{

/**
 * Base for task execution runners (lifted from {@link Task.Details.run_exec} /
 * {@link Task.Details.run_post_exec}). Not wired in yet — see plan 7.16.1.
 */
public abstract class Base
{
	protected Task.Details task;

	protected Base (Task.Details task)
	{
		this.task = task;
	}

	public abstract async void run () throws GLib.Error;
}

}
