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
	 * Stream one Hub model's ''.gguf'' siblings to the local install layout.
	 *
	 * Progress is emitted as {@link OLLMrpc.Notification} on {@link progress}
	 * ({@link OLLMrpc.Notification.progress_completed},
	 * {@link OLLMrpc.Notification.progress_total}, {@link OLLMrpc.Notification.message}
	 * for the filename).
	 * Crash-safe state is stored in ''download.json'' via
	 * {@link OLLMrpc.Bin.Json.from_gobject}.
	 */
	public class Download : GLib.Object
	{
		public Model model { get; construct; }
		public string models_dir { get; set; default = ""; }
		public string revision { get; set; default = "main"; }
		public string[] file_filter { get; set; default = {}; }

		private Soup.Session soup;
		private OLLMrpc.Bin.Json json =
			new OLLMrpc.Bin.Json(OLLMrpc.Bin.Mode.AUTO);
		private GLib.Cancellable? stop_cancellable;
		private int64 last_persist_time;
		private int64 last_persist_bytes;

		public signal void progress(OLLMrpc.Notification notif);

		public Download(Model model) {
			Object(model: model);
			this.soup = new Soup.Session();
		}

		public void stop() {
			if (this.stop_cancellable != null) {
				this.stop_cancellable.cancel();
			}
		}

		public async void start(GLib.Cancellable? cancellable = null) throws GLib.Error
		{
			this.stop_cancellable = new GLib.Cancellable();
			var active_cancel = cancellable != null
				? cancellable
				: this.stop_cancellable;
			var model_dir = this.models_dir;
			if (model_dir == "") {
				model_dir = GLib.Path.build_filename(
					GLib.Environment.get_user_data_dir(),
					"ollmchat", "models");
			}
			foreach (var segment in this.model.id.split("/")) {
				model_dir = GLib.Path.build_filename(model_dir, segment);
			}
			GLib.File.new_for_path(model_dir).make_directory_with_parents(null);
			var download_path = GLib.Path.build_filename(model_dir, "download.json");
			if (GLib.FileUtils.test(download_path, GLib.FileTest.EXISTS)) {
				var contents = "";
				GLib.FileUtils.get_contents(download_path, out contents, null);
				var parser = new Json.Parser();
				parser.load_from_data(contents);
				var root = parser.get_root();
				var mem = new GLib.MemoryOutputStream.resizable();
				var encode_ctx = new OLLMrpc.Bin.Stream(null, new GLib.DataOutputStream(mem));
				this.json.json_to_bin(root.get_object(), encode_ctx, typeof(Model));
				encode_ctx.out_stream.close();
				var decode_ctx = new OLLMrpc.Bin.Stream(
					new GLib.DataInputStream(new GLib.MemoryInputStream.from_bytes(
						mem.steal_as_bytes())), null);
				decode_ctx.mode = this.json.mode;
				var restored = (Model) decode_ctx.parse();
				if (restored.id == this.model.id) {
					this.model.download_revision = restored.download_revision;
					this.model.siblings.clear();
					foreach (var sibling in restored.siblings) {
						this.model.siblings.add(sibling);
					}
				}
			}
			this.model.download_revision = this.revision;
			this.last_persist_time = GLib.get_monotonic_time();
			this.last_persist_bytes = 0;

			foreach (var file in this.model.siblings) {
				yield this.download_sibling(file, model_dir, download_path, active_cancel);
			}

			var manifest_path = GLib.Path.build_filename(model_dir, "manifest.json");
			var manifest_node = this.json.from_gobject(this.model);
			GLib.FileUtils.set_contents(manifest_path, Json.to_string(manifest_node, true));
			if (GLib.FileUtils.test(download_path, GLib.FileTest.EXISTS)) {
				GLib.FileUtils.unlink(download_path);
			}
			foreach (var file in this.model.siblings) {
				if (!file.rfilename.has_suffix(".gguf")) {
					continue;
				}
				var partial_path = GLib.Path.build_filename(model_dir, file.rfilename + ".partial");
				if (GLib.FileUtils.test(partial_path, GLib.FileTest.EXISTS)) {
					GLib.FileUtils.unlink(partial_path);
				}
			}
		}

		/**
		 * Stream, verify, and persist one ''.gguf'' sibling when filters
		 * and resume state allow it. HEAD runs only on a fresh start to
		 * fetch the LFS ETag; resumed downloads reuse persisted state.
		 *
		 * @param file          sibling to download
		 * @param model_dir     install directory for this model
		 * @param download_path path to ''download.json'' progress file
		 * @param active_cancel download cancellation source
		 */
		private async void download_sibling(
			ModelFile file,
			string model_dir,
			string download_path,
			GLib.Cancellable active_cancel
		) throws GLib.Error
		{
			if (!file.rfilename.has_suffix(".gguf")) {
				return;
			}
			if (this.file_filter.length > 0 && !(file.rfilename in this.file_filter)) {
				return;
			}
			if (file.download_complete) {
				return;
			}

			var resolve_url = file.to_url(this.model.id, this.model.download_revision);
			if (file.bytes_written == 0) {
				var head_msg = new Soup.Message("HEAD", resolve_url);
				var head_in = yield this.soup.send_async(
					head_msg, GLib.Priority.DEFAULT, active_cancel);
				if (head_in != null) {
					var discard = new uint8[4096];
					while (true) {
						var drained = yield head_in.read_async(
							discard, GLib.Priority.DEFAULT, active_cancel);
						if (drained <= 0) {
							break;
						}
					}
				}
				var etag_raw = head_msg.response_headers.get_one("ETag");
				if (etag_raw != null && etag_raw != "") {
					var etag = etag_raw.strip();
					if (etag.has_prefix("\"") && etag.has_suffix("\"")) {
						etag = etag[1:etag.length - 1];
					}
					file.etag = etag;
				}
			}

			var partial_path = GLib.Path.build_filename(model_dir, file.rfilename + ".partial");
			var dest_path = GLib.Path.build_filename(model_dir, file.rfilename);
			var get_msg = new Soup.Message("GET", resolve_url);
			if (file.bytes_written > 0) {
				get_msg.request_headers.replace(
					"Range", "bytes=%lld-".printf(file.bytes_written));
			}
			var input = yield this.soup.send_async(
				get_msg, GLib.Priority.DEFAULT, active_cancel);
			if (get_msg.status_code != 200 && get_msg.status_code != 206) {
				throw new GLib.IOError.FAILED("HTTP %u for %s",
					get_msg.status_code, file.rfilename);
			}
			if (file.size == 0) {
				file.size = (int64) get_msg.response_headers.get_content_length();
			}

			GLib.FileOutputStream? out_stream = null;
			if (file.bytes_written > 0) {
				out_stream = GLib.File.new_for_path(partial_path).append_to(
					GLib.FileCreateFlags.NONE);
			} else {
				out_stream = GLib.File.new_for_path(partial_path).create(
					GLib.FileCreateFlags.REPLACE_DESTINATION);
			}

			var checksum = new GLib.Checksum(GLib.ChecksumType.SHA256);
			if (file.bytes_written > 0
				&& GLib.FileUtils.test(partial_path, GLib.FileTest.EXISTS)) {
				var partial_in = yield GLib.File.new_for_path(partial_path).read_async(
					GLib.Priority.DEFAULT, active_cancel);
				var hash_buf = new uint8[65536];
				while (true) {
					var hash_read = yield partial_in.read_async(
						hash_buf, GLib.Priority.DEFAULT, active_cancel);
					if (hash_read <= 0) {
						break;
					}
					checksum.update(hash_buf[0:hash_read], hash_read);
				}
			}

			var buf = new uint8[65536];
			while (true) {
				var n = yield input.read_async(buf, GLib.Priority.DEFAULT, active_cancel);
				if (n <= 0) {
					break;
				}
				out_stream.write(buf[0:n]);
				checksum.update(buf[0:n], n);
				file.bytes_written += n;
				file.sha256_partial = checksum.get_string();
				this.progress(new OLLMrpc.Notification() {
					method = "event.hf.download.progress",
					object_type = "ModelFile",
					message = file.rfilename,
					progress_completed = file.bytes_written,
					progress_total = file.size,
				});
				var now = GLib.get_monotonic_time();
				if (now - this.last_persist_time >= 5000000
					|| file.bytes_written - this.last_persist_bytes >= 8 * 1024 * 1024) {
					var node = this.json.from_gobject(this.model);
					var json_text = Json.to_string(node, true);
					GLib.FileUtils.set_contents(download_path, json_text);
					this.last_persist_time = now;
					this.last_persist_bytes = file.bytes_written;
				}
			}
			out_stream.close();

			var digest = checksum.get_string();
			if (file.etag != "" && digest != file.etag) {
				throw new GLib.IOError.FAILED("checksum mismatch for %s", file.rfilename);
			}
			if (file.size > 0 && file.bytes_written != file.size) {
				throw new GLib.IOError.FAILED(
					"size mismatch for %s: got %lld expected %lld",
					file.rfilename, file.bytes_written, file.size);
			}

			GLib.File.new_for_path(partial_path).move(
				GLib.File.new_for_path(dest_path), GLib.FileCopyFlags.OVERWRITE);
			file.download_complete = true;
			var persist_node = this.json.from_gobject(this.model);
			GLib.FileUtils.set_contents(download_path, Json.to_string(persist_node, true));
		}
	}
}
