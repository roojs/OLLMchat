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

namespace OLLMchat.History
{
	/**
	 * SessionJson is used only for loading messages from JSON files.
	 *
	 * This is a minimal temporary class used only during JSON deserialization.
	 */
	public class SessionJson : Object, Json.Serializable
	{
		public int64 id { get; set; default = -1; }
		public int64 updated_at_timestamp { get; set; default = 0; }
		public string title { get; set; default = ""; }
		public Settings.ModelUsage? model_usage { get; set; default = null; }
		public string agent_name { get; set; default = "just-ask"; }
		public string fid { get; set; default = ""; }
		public Gee.ArrayList<string> child_chats { get; set; default = new Gee.ArrayList<string>(); }
		public Gee.ArrayList<Message> messages { get; set; default = new Gee.ArrayList<Message>(); }
		/** Session project path; from JSON top-level (or DB when loading via placeholder). */
		public string project_path { get; set; default = ""; }

		/**
		 * True after load when the transcript contains replay markers; also persisted as can-replay in JSON when present.
		 */
		public bool can_replay { get; set; default = false; }

		public bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			switch (property_name) {
				case "project-path":
				case "can-replay":
					return default_deserialize_property(property_name, out value, pspec, property_node);
				case "messages":
					Message.idx_counter = 0;
					this.messages.clear();
					var array = property_node.get_array();
					Message? last_msg = null;
					for (uint i = 0; i < array.get_length(); i++) {
						var element_node = array.get_element(i);
						var msg = Json.gobject_deserialize(typeof(Message), element_node) as Message;
						if (msg == null) {
							continue;
						}
						// If previous was user-sent and current is not the "You said:" ui frame, add the ui message (migrate old session format).
						if (last_msg != null && last_msg.role == "user-sent"
							&& (msg.role != "ui" || !msg.content.contains("oc-frame-user You said:"))) {
							this.messages.add(new Message("ui",
								Message.fenced("text.oc-frame-primary.oc-frame-user You said:", last_msg.content)));
						}
						this.messages.add(msg);
						if (!this.can_replay && msg.role == "agent-stage") {
							this.can_replay = true;
						}
						last_msg = msg;
					}
					value = Value(typeof(Gee.ArrayList));
					value.set_object(this.messages);
					return true;
				default:
					// Same as pre–can-replay tree: do not default_deserialize; Json-GLib handles other keys elsewhere.
					value = Value(pspec.value_type);
					return true;
			}
		}

		public Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			return null;
		}
	}
}
