/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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

namespace OLLMchat.Ollama
{
	/**
	 * Options object for Ollama API calls.
	 * 
	 * Contains all runtime parameters that can be passed to Ollama API.
	 * All properties are read-only getters from the client, with blank setters
	 * for serialization purposes. Default values are -1 for numbers (indicating
	 * no value set) or empty string for strings.
	 */
	public class Options : OllamaBase
	{
		// Numeric options - default to -1 (no value set)
		public int seed {
			get { return this.client != null ? this.client.seed : -1; }
			set { } // Blank setter for serialization
		}
		
		public double temperature {
			get { return this.client != null ? this.client.temperature : -1.0; }
			set { } // Blank setter for serialization
		}
		
		public double top_p {
			get { return this.client != null ? this.client.top_p : -1.0; }
			set { } // Blank setter for serialization
		}
		
		public int top_k {
			get { return this.client != null ? this.client.top_k : -1; }
			set { } // Blank setter for serialization
		}
		
		public int num_predict {
			get { return this.client != null ? this.client.num_predict : -1; }
			set { } // Blank setter for serialization
		}
		
		public double repeat_penalty {
			get { return this.client != null ? this.client.repeat_penalty : -1.0; }
			set { } // Blank setter for serialization
		}
		
		public int num_ctx {
			get { return this.client != null ? this.client.num_ctx : -1; }
			set { } // Blank setter for serialization
		}
		
		public int num_batch {
			get { return this.client != null ? this.client.num_batch : -1; }
			set { } // Blank setter for serialization
		}
		
		public int num_gpu {
			get { return this.client != null ? this.client.num_gpu : -1; }
			set { } // Blank setter for serialization
		}
		
		public int num_thread {
			get { return this.client != null ? this.client.num_thread : -1; }
			set { } // Blank setter for serialization
		}
		
		// String options - default to empty string (no value set)
		public string stop {
			get { return this.client != null ? (this.client.stop ?? "") : ""; }
			set { } // Blank setter for serialization
		}

		public Options(Client client)
		{
			base(client);
		}

		/**
		 * Checks if any options have valid values set.
		 * 
		 * Returns true if at least one option has a non-default value.
		 * For numeric options, -1 indicates no value set.
		 * For string options, empty string indicates no value set.
		 * 
		 * @return true if options have values, false otherwise
		 */
		public bool has_values()
		{
			return this.seed != -1
				|| this.temperature != -1.0
				|| this.top_p != -1.0
				|| this.top_k != -1
				|| this.num_predict != -1
				|| this.repeat_penalty != -1.0
				|| this.num_ctx != -1
				|| this.num_batch != -1
				|| this.num_gpu != -1
				|| this.num_thread != -1
				|| this.stop != "";
		}

		public override Json.Node serialize_property(string property_name, Value value, ParamSpec pspec)
		{
			// Exclude client from serialization
			if (property_name == "client") {
				return null;
			}
			
			// Only serialize properties that have valid values
			switch (property_name) {
				case "seed":
					if (this.seed == -1) {
						return null;
					}
					break;
				case "temperature":
					if (this.temperature == -1.0) {
						return null;
					}
					break;
				case "top_p":
					if (this.top_p == -1.0) {
						return null;
					}
					break;
				case "top_k":
					if (this.top_k == -1) {
						return null;
					}
					break;
				case "num_predict":
					if (this.num_predict == -1) {
						return null;
					}
					break;
				case "repeat_penalty":
					if (this.repeat_penalty == -1.0) {
						return null;
					}
					break;
				case "num_ctx":
					if (this.num_ctx == -1) {
						return null;
					}
					break;
				case "num_batch":
					if (this.num_batch == -1) {
						return null;
					}
					break;
				case "num_gpu":
					if (this.num_gpu == -1) {
						return null;
					}
					break;
				case "num_thread":
					if (this.num_thread == -1) {
						return null;
					}
					break;
				case "stop":
					if (this.stop == "") {
						return null;
					}
					break;
			}
			
			return base.serialize_property(property_name, value, pspec);
		}
	}
}

