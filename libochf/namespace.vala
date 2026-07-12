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
 * Hugging Face Hub catalog library (`libochf`).
 *
 * Search and model-detail metadata use {@link OLLMrpc.Client.call} against
 * {{{https://huggingface.co}}} (set {@link OLLMrpc.Client.socket_path} to that
 * base URL). Typed results are {@link Model}, {@link ModelArray}, and
 * {@link Param.Search} on {@link OLLMrpc.Request.param}. Detail requests put
 * the model ref in {@link OLLMrpc.Request.method} and use the default
 * {@link OLLMrpc.CallParam} (no query string). When Hub omits sibling
 * {{{size}}}, {@link Model.fetch_siblings} uses
 * {{{GET /api/models/MODEL_ID/tree/REVISION}}}.
 *
 * Call {@link rpc_register} once before the first Hub HTTP call so result wire
 * types are registered with {@link OLLMrpc.Bin}. {@link Param.Search} is not
 * registered — it only supplies outbound query fields for
 * {@link OLLMrpc.Client.send_http}.
 */
namespace OLLMhf
{
	/**
	 * Register all `libochf` bin wire types with {@link OLLMrpc.Bin}.
	 *
	 * Call before {@link OLLMrpc.Client.connect} when using Hub metadata over HTTP.
	 */
	public void rpc_register()
	{
		Model.rpc_register();
		ModelFile.rpc_register();
		ModelWidgetData.rpc_register();
		ModelTokenizerConfig.rpc_register();
		ModelConfig.rpc_register();
		ModelCardData.rpc_register();
		ModelTransformersInfo.rpc_register();
		ModelGguf.rpc_register();
		ModelArray.rpc_register();
		ModelTreeLfs.rpc_register();
		ModelTreeEntry.rpc_register();
		ModelTreeArray.rpc_register();
	}
}
