[CCode (cheader_filename = "ollmchat-llama-probe.h")]
namespace OllmchatLlamaProbe
{
	[CCode (cname = "OllmchatLlamaPooling", cprefix = "OLLMCHAT_LLAMA_POOLING_")]
	public enum Pooling
	{
		UNSPECIFIED,
		NONE,
		MEAN,
		CLS,
		LAST
	}

	[Compact]
	[CCode (
		cname = "OllmchatLlamaEmbedding",
		free_function = "ollmchat_llama_embedding_free"
	)]
	public class Embedding
	{
		[CCode (cname = "ollmchat_llama_embedding_length")]
		public int length();

		[CCode (cname = "ollmchat_llama_embedding_get")]
		public float get(int index);
	}

	[CCode (cname = "ollmchat_llama_embed_text")]
	public static Embedding? embed_text(
		string model_path,
		string text,
		int context_length,
		int threads,
		Pooling pooling,
		out string? error_message
	);
}
