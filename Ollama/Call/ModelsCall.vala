namespace OLLMchat.Ollama
{
	/**
	 * API call to list available models on the Ollama server.
	 * 
	 * Retrieves a list of all models that are available for use.
	 */
	public class ModelsCall : BaseCall
	{
		public ModelsCall(Client client)
		{
			base(client);
			this.url_endpoint = "tags";
			this.http_method = "GET";
		}

		public async Gee.ArrayList<Model> exec_models() throws Error
		{
			return yield this.get_models("models");
		}
	}
}
