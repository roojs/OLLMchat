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
	/**
	 * Hugging Face Hub model record (search hit or full detail).
	 *
	 * {@link id} is the repo id {{{author/name}}}. Hub {{{siblings[]}}} entries
	 * decode into {@link ModelFile} objects on {@link siblings}.
	 */
	public class Model : GLib.Object, OLLMrpc.Bin.Serializable
	{
		/** Hub document id (JSON {{{_id}}} → {@link underscore_id}). */
		public string underscore_id { get; set; default = ""; }

		/** Hub repo id {{{author/name}}}. */
		public string id { get; set; default = ""; }

		/** Hub {{{modelId}}} when present. */
		public string modelId { get; set; default = ""; }

		/** Hub {{{createdAt}}} when present. */
		public string createdAt { get; set; default = ""; }

		/** Hub {{{lastModified}}} when present. */
		public string lastModified { get; set; default = ""; }

		/** Repo owner from Hub metadata. */
		public string author { get; set; default = ""; }

		/** Hub commit sha when present. */
		public string sha { get; set; default = ""; }

		/** Download count from Hub search/detail metadata. */
		public int64 downloads { get; set; default = 0; }

		/** Like count from Hub metadata. */
		public int likes { get; set; default = 0; }

		/** Hub trending score when present (full search). */
		public int trendingScore { get; set; default = 0; }

		/** Hub tags (e.g. {{{gguf}}}, {{{text-generation}}}). */
		public string[] tags { get; set; default = {}; }

		/** Hub {{{pipeline_tag}}} when set. */
		public string pipeline_tag { get; set; default = ""; }

		/** Primary library name from Hub metadata. */
		public string library_name { get; set; default = ""; }

		/** True when the repo requires acceptance before download. */
		public bool gated { get; set; default = false; }

		/** True when the repo is private on the Hub. */
		public bool @private { get; set; default = false; }

		/** True when the repo is disabled on the Hub. */
		public bool disabled { get; set; default = false; }

		/** Hub {{{model-index}}} when present. */
		public string model_index { get; set; default = ""; }

		/** Hub storage used when present (detail). */
		public int64 usedStorage { get; set; default = 0; }

		/** Hub detail {{{widgetData[]}}}. */
		public Gee.ArrayList<ModelWidgetData> widgetData {
			get; set; default = new Gee.ArrayList<ModelWidgetData>();
		}

		/** Hub detail {{{config}}}. */
		public ModelConfig config {
			get; set; default = new ModelConfig();
		}

		/** Hub detail {{{cardData}}}. */
		public ModelCardData cardData {
			get; set; default = new ModelCardData();
		}

		/** Hub detail {{{transformersInfo}}}. */
		public ModelTransformersInfo transformersInfo {
			get; set; default = new ModelTransformersInfo();
		}

		/** Hub detail {{{gguf}}} metadata when present. */
		public ModelGguf gguf {
			get; set; default = new ModelGguf();
		}

		/** Hub detail {{{spaces[]}}}. */
		public string[] spaces { get; set; default = {}; }

		/** Repo files from Hub {{{siblings[]}}}. */
		public Gee.ArrayList<ModelFile> siblings {
			get; set; default = new Gee.ArrayList<ModelFile>();
		}

		/** Revision used for resolve URLs during an in-progress download. */
		public string download_revision { get; set; default = "main"; }

		public static void rpc_register() {
			OLLMrpc.Bin.register("Model", typeof(Model));
		}

		public override void bin_write_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop
		) throws GLib.Error {
			switch (prop.name) {
				case "siblings":
					this.bin_write_prop_array(
						ctx,
						prop.name,
						typeof(ModelFile)
					);
					return;
				case "widgetData":
					this.bin_write_prop_array(
						ctx,
						prop.name,
						typeof(ModelWidgetData)
					);
					return;
				default:
					this.bin_default_write_prop(ctx, prop);
					return;
			}
		}

		public override void bin_read_prop(
			OLLMrpc.Bin.Stream ctx,
			GLib.ParamSpec prop,
			uint8 type_byte
		) throws GLib.Error {
			switch (prop.name) {
				case "siblings":
					this.siblings = (Gee.ArrayList<ModelFile>) this.read_anon_array(
						ctx,
						prop.name,
						type_byte,
						typeof(ModelFile)
					);
					return;
				case "widgetData":
					this.widgetData = (Gee.ArrayList<ModelWidgetData>) this.read_anon_array(
						ctx,
						prop.name,
						type_byte,
						typeof(ModelWidgetData)
					);
					return;
				case "config":
					if ((type_byte & 0x7F) != GLib.Type.OBJECT
						|| (type_byte & 0x80) != 0) {
						throw new OLLMrpc.Bin.SerializableError.PROPERTY(
							"prop '%s' expected object",
							prop.name
						);
					}
					ctx.read_gtype();
					this.config = new ModelConfig();
					this.config.bin_read(ctx);
					return;
				case "cardData":
					if ((type_byte & 0x7F) != GLib.Type.OBJECT
						|| (type_byte & 0x80) != 0) {
						throw new OLLMrpc.Bin.SerializableError.PROPERTY(
							"prop '%s' expected object",
							prop.name
						);
					}
					ctx.read_gtype();
					this.cardData = new ModelCardData();
					this.cardData.bin_read(ctx);
					return;
				case "transformersInfo":
					if ((type_byte & 0x7F) != GLib.Type.OBJECT
						|| (type_byte & 0x80) != 0) {
						throw new OLLMrpc.Bin.SerializableError.PROPERTY(
							"prop '%s' expected object",
							prop.name
						);
					}
					ctx.read_gtype();
					this.transformersInfo = new ModelTransformersInfo();
					this.transformersInfo.bin_read(ctx);
					return;
				case "gguf":
					if ((type_byte & 0x7F) != GLib.Type.OBJECT
						|| (type_byte & 0x80) != 0) {
						throw new OLLMrpc.Bin.SerializableError.PROPERTY(
							"prop '%s' expected object",
							prop.name
						);
					}
					ctx.read_gtype();
					this.gguf = new ModelGguf();
					this.gguf.bin_read(ctx);
					return;
				default:
					this.bin_default_read_prop(ctx, prop, type_byte);
					return;
			}
		}
	}
}
