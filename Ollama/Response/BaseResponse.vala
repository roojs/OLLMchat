namespace OLLMchat.Ollama
{
	/**
	 * Abstract base class for Ollama API responses.
	 * 
	 * Provides common functionality for deserializing responses from the Ollama API.
	 * All response types extend this class.
	 */
	public abstract class BaseResponse : OllamaBase
	{
		protected string id = "";

		protected BaseResponse(Client? client = null)
		{
			base(client);
		}
	}
}

