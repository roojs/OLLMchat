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
 * Agent Pi — Pi-like free-form coding agent.
 *
 * Project-aware factory and agent ({@link Agent}, {@link PendingMessage}) with
 * liboccoder UI weight (SourceView / {@link OLLMfiles.ProjectManager}).
 * Phase 0 is registration and a chat-only turn queue; context hygiene is
 * deferred (study plan Phase 5 Option C). Phase 1 injects AGENTS.md /
 * CLAUDE.md via {@link Factory.build_agents_md}. Phase 2 adds {@link Skill}
 * / {@link SkillSet} and injects the catalog from {@link PendingMessage.run}.
 *
 * == Usage Examples ==
 *
 * === Register ===
 *
 * {{{
 * var factory = new OLLMcoder.AgentPi.Factory(project_manager);
 * history_manager.agent_factories.set(factory.name, factory);
 * }}}
 */
namespace OLLMcoder.AgentPi
{
	/**
	 * Namespace documentation marker.
	 */
	internal class NamespaceDoc {}
}
