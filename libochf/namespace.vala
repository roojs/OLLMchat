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
 * Hub I/O uses OLLMrpc.Client with an HTTPS socket URL. Call rpc_register()
 * once, then connect:
 *
 * {{{
 * OLLMhf.rpc_register();
 * var rpc = new OLLMrpc.Client("", "", "https://huggingface.co");
 * yield rpc.connect(new OLLMrpc.Request());
 * }}}
 *
 * == Search ==
 *
 * Param.Search becomes the query string. Result decodes as ModelArray.
 *
 * {{{
 * var resp = yield rpc.call(new OLLMrpc.Request() {
 *     method = "/api/models",
 *     param = new OLLMhf.Param.Search() {
 *         search = "mistral",
 *         filter = "gguf",
 *         limit = 20
 *     },
 *     result_type = typeof(OLLMhf.ModelArray)
 * });
 * foreach (var model in ((OLLMhf.ModelArray) resp.result[0]).items) {
 *     stdout.printf("%s\n", model.id);
 * }
 * }}}
 *
 * == Model detail ==
 *
 * Put the repo ref in method. fetch_siblings fills missing file sizes.
 *
 * {{{
 * var resp = yield rpc.call(new OLLMrpc.Request() {
 *     method = "/api/models/author/name",
 *     result_type = typeof(OLLMhf.Model)
 * });
 * var model = (OLLMhf.Model) resp.result[0];
 * yield model.fetch_siblings(rpc);
 * }}}
 *
 * == Download ==
 *
 * Download streams ''.gguf'' siblings to the local models tree.
 *
 * {{{
 * var dl = new OLLMhf.Download(model);
 * dl.file_filter = { "model-q4_k_m.gguf" };
 * dl.progress.connect((n) => {
 *     stdout.printf("%lld/%lld %s\n",
 *         n.progress_completed, n.progress_total, n.message);
 * });
 * yield dl.start();
 * }}}
 */
namespace OLLMhf
{
	/**
	 * Register libochf wire types with OLLMrpc.Bin.
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
