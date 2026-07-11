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

namespace OLLMhf
{
	/** Hub detail {{{widgetData[]}}} entry. */
	public class ModelWidgetData : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string text { get; set; default = ""; }

		public static void rpc_register() {
			OLLMrpc.Bin.register("ModelWidgetData", typeof(ModelWidgetData));
		}
	}

	/** Hub detail {{{config.tokenizer_config}}} when present. */
	public class ModelTokenizerConfig : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string bos_token { get; set; default = ""; }
		public string chat_template { get; set; default = ""; }
		public string eos_token { get; set; default = ""; }
		public string pad_token { get; set; default = ""; }
		public string unk_token { get; set; default = ""; }

		public static void rpc_register() {
			OLLMrpc.Bin.register(
				"ModelTokenizerConfig",
				typeof(ModelTokenizerConfig)
			);
		}
	}

	/** Hub detail {{{config}}} (Hub API returns a short subset, not full config.json). */
	public class ModelConfig : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string[] architectures { get; set; default = {}; }
		public string model_type { get; set; default = ""; }
		public ModelTokenizerConfig tokenizer_config {
			get; set; default = new ModelTokenizerConfig();
		}

		public static void rpc_register() {
			OLLMrpc.Bin.register("ModelConfig", typeof(ModelConfig));
		}
	}

	/** Hub detail {{{cardData}}}. */
	public class ModelCardData : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string library_name { get; set; default = ""; }
		public string[] tags { get; set; default = {}; }
		public string license { get; set; default = ""; }
		public string license_link { get; set; default = ""; }
		public string pipeline_tag { get; set; default = ""; }
		public string[] language { get; set; default = {}; }
		public string[] base_model { get; set; default = {}; }

		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error {
			// Hub cardData.base_model is a JSON string on some repos and a string[] on others.
			if (prop.name == "base-model"
				&& (type_byte & 0x7F) == GLib.Type.STRING
				&& (type_byte & 0x80) == 0) {
				var str_len = (uint) ctx.in_stream.read_byte();
				if ((str_len & 0x80) != 0) {
					str_len = ((str_len & 0x7F) << 8) | ctx.in_stream.read_byte();
				}
				var str_buf = new uint8[str_len + 1];
				size_t str_read;
				ctx.in_stream.read_all(str_buf[0:str_len], out str_read);
				str_buf[str_len] = 0;
				this.base_model = { (string) str_buf };
				return;
			}
			// Hub cardData.language is sometimes a string and sometimes string[].
			if (prop.name == "language"
				&& (type_byte & 0x7F) == GLib.Type.STRING
				&& (type_byte & 0x80) == 0) {
				var str_len = (uint) ctx.in_stream.read_byte();
				if ((str_len & 0x80) != 0) {
					str_len = ((str_len & 0x7F) << 8) | ctx.in_stream.read_byte();
				}
				var str_buf = new uint8[str_len + 1];
				size_t str_read;
				ctx.in_stream.read_all(str_buf[0:str_len], out str_read);
				str_buf[str_len] = 0;
				this.language = { (string) str_buf };
				return;
			}
			this.bin_default_read_prop(ctx, prop, type_byte);
		}

		public static void rpc_register() {
			OLLMrpc.Bin.register("ModelCardData", typeof(ModelCardData));
		}
	}

	/** Hub detail {{{transformersInfo}}}. */
	public class ModelTransformersInfo : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public string auto_model { get; set; default = ""; }

		public static void rpc_register() {
			OLLMrpc.Bin.register(
				"ModelTransformersInfo",
				typeof(ModelTransformersInfo)
			);
		}
	}

	/** Hub detail {{{gguf}}} metadata when present. */
	public class ModelGguf : GLib.Object, OLLMrpc.Bin.Serializable
	{
		public int64 total { get; set; default = 0; }
		public string architecture { get; set; default = ""; }
		public int64 context_length { get; set; default = 0; }
		public string chat_template { get; set; default = ""; }
		public string bos_token { get; set; default = ""; }
		public string eos_token { get; set; default = ""; }
		public int64 totalFileSize { get; set; default = 0; }
		public string quantize_imatrix_file { get; set; default = ""; }

		public static void rpc_register() {
			OLLMrpc.Bin.register("ModelGguf", typeof(ModelGguf));
		}
	}
}
