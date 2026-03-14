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
		
		public bool deserialize_property(string property_name, out Value value, ParamSpec pspec, Json.Node property_node)
		{
			if (property_name == "project-path") {
				this.project_path = property_node.get_string() ?? "";
				value = Value(typeof(string));
				value.set_string(this.project_path);
				return true;
			}
			if (property_name != "messages") {
				value = Value(pspec.value_type);
				return true;
			}
			
			this.messages.clear();
			var array = property_node.get_array();
			bool migrate_user_sent = this.updated_at_timestamp > 0 && this.updated_at_timestamp <= 1773458325;
			for (uint i = 0; i < array.get_length(); i++) {
				var element_node = array.get_element(i);
				var msg = Json.gobject_deserialize(typeof(Message), element_node) as Message;
				if (msg == null) {
					continue;
				}
				this.messages.add(msg);
				if (!migrate_user_sent || msg.role != "user-sent") {
					continue;
				}
				this.messages.add(new Message("ui",
					Message.fenced("text.oc-frame-primary.oc-frame-user You said:", msg.content)));
				migrate_user_sent = false;
			}
			value = Value(typeof(Gee.ArrayList));
			value.set_object(this.messages);
			return true;
		}
		
		public Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			return null;
		}
	}
}
