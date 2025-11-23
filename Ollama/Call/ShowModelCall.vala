namespace OLLMchat.Ollama
{
	public class ShowModelCall : BaseCall
	{
		public string model { get; set; default = ""; }
		public bool verbose { get; set; default = false; }

		public ShowModelCall(Client client, string model_name) throws OllamaError
		{
			base(client);
			if (model_name == "") {
				throw new OllamaError.FAILED("Model name cannot be empty");
			}
			this.model = model_name;
			this.url_endpoint = "show";
			this.http_method = "POST";
		}

		public async Model exec_show() throws Error
		{
			var bytes = yield this.send_request(true);
			var root = this.parse_response(bytes);

			if (root.get_node_type() != Json.NodeType.OBJECT) {
				throw new OllamaError.FAILED("Invalid JSON response");
			}

			var generator = new Json.Generator();
			generator.set_root(root);
			var json_str = generator.to_data(null);
			var model_obj = Json.gobject_from_data(typeof(Model), json_str, -1) as Model;
			if (model_obj == null) {
				throw new OllamaError.FAILED("Failed to deserialize model");
			}
			// Set the name from the request parameter (API response may not include it)
			if (model_obj.name == "") {
				model_obj.name = this.model;
			}
			model_obj.client = this.client;
			return model_obj;
		}
	}
}

