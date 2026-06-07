[CCode (cheader_filename = "llama.h", lower_case_cprefix = "llama_")]
namespace Llama
{
	[CCode (cname = "llama_seq_id")]
	public struct SeqId : int {}

	[CCode (cname = "enum llama_pooling_type", cprefix = "LLAMA_POOLING_TYPE_")]
	public enum PoolingType
	{
		UNSPECIFIED,
		NONE,
		MEAN,
		CLS,
		LAST,
		RANK
	}

	[Compact]
	[CCode (cname = "struct llama_model", free_function = "")]
	public class Model {}

	[Compact]
	[CCode (cname = "struct llama_context", free_function = "")]
	public class Context {}

	[Compact]
	[CCode (cname = "struct llama_vocab", free_function = "")]
	public class Vocab {}

	[SimpleType]
	[CCode (cname = "struct llama_model_params")]
	public struct ModelParams {}

	[SimpleType]
	[CCode (cname = "struct llama_context_params")]
	public struct ContextParams
	{
		public uint n_ctx;
		public int n_threads;
		public int n_threads_batch;
		public PoolingType pooling_type;
		public bool embeddings;
	}

	[SimpleType]
	[CCode (cname = "struct llama_batch")]
	public struct Batch
	{
		public int n_tokens;
		public int* token;
		public int* pos;
		public int* n_seq_id;
		public SeqId** seq_id;
		public int8* logits;
	}

	[CCode (cname = "llama_backend_init")]
	public static void backend_init();

	[CCode (cname = "llama_model_default_params")]
	public static ModelParams model_default_params();

	[CCode (cname = "llama_context_default_params")]
	public static ContextParams context_default_params();

	[CCode (cname = "llama_model_load_from_file")]
	public static unowned Model? model_load_from_file(string model_path, ModelParams parameters);

	[CCode (cname = "llama_init_from_model")]
	public static unowned Context? init_from_model(Model model, ContextParams parameters);

	[CCode (cname = "llama_model_get_vocab")]
	public static unowned Vocab model_get_vocab(Model model);

	[CCode (cname = "llama_tokenize")]
	public static int tokenize(
		Vocab vocab,
		string text,
		int text_length,
		int* tokens,
		int max_tokens,
		bool add_special,
		bool parse_special
	);

	[CCode (cname = "llama_batch_init")]
	public static Batch batch_init(int token_count, int embedding_count, int sequence_count);

	[CCode (cname = "llama_batch_free")]
	public static void batch_free(Batch batch);

	[CCode (cname = "llama_decode")]
	public static int decode(Context context, Batch batch);

	[CCode (cname = "llama_get_embeddings_seq")]
	public static unowned float* get_embeddings_seq(Context context, SeqId sequence_id);

	[CCode (cname = "llama_get_embeddings_ith")]
	public static unowned float* get_embeddings_ith(Context context, int index);

	[CCode (cname = "llama_get_embeddings")]
	public static unowned float* get_embeddings(Context context);

	[CCode (cname = "llama_model_n_embd")]
	public static int model_n_embd(Model model);

	[CCode (cname = "llama_free")]
	public static void free(Context context);

	[CCode (cname = "llama_model_free")]
	public static void model_free(Model model);
}
