namespace OLLMchat.Ollama
{
	/**
	 * Interface for objects that provide chat content.
	 * 
	 * Used to unify access to message content across different types
	 * (Message, ChatResponse, ChatCall) for consistent content handling.
	 */
	public interface MessageInterface : Object
	{
		public abstract string chat_content { get; set; default = ""; }
	}
}

