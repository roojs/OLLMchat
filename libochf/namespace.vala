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
 * Hugging Face Hub — search, model detail, and GGUF download.
 *
 * Hub calls use OLLMrpc.Client with an HTTPS URL as the socket path.
 * Call rpc_register() once before the first request.
 */
namespace OLLMhf
{
	/**
	 * Register all ''libochf'' bin wire types with {@link OLLMrpc.Bin}.
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
