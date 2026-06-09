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
	[CCode (cname = "struct llama_model", free_function = "llama_model_free")]
	public class Model
	{
		[CCode (cname = "llama_model_load_from_file")]
		public Model.from_file(string model_path, ModelParams parameters);

		[CCode (cname = "llama_model_get_vocab")]
		public unowned Vocab get_vocab();

		[CCode (cname = "llama_model_n_embd")]
		public int n_embd();

		[CCode (cname = "llama_model_has_encoder")]
		public bool has_encoder();
	}

	[Compact]
	[CCode (cname = "struct llama_context", free_function = "llama_free")]
	public class Context
	{
		[CCode (cname = "llama_init_from_model")]
		public Context.from_model(Model model, ContextParams parameters);

		[CCode (cname = "llama_encode")]
		public int encode(Batch batch);

		[CCode (cname = "llama_decode")]
		public int decode(Batch batch);

		[CCode (cname = "llama_get_embeddings_seq")]
		public unowned float* get_embeddings_seq(SeqId sequence_id);

		[CCode (cname = "llama_get_embeddings_ith")]
		public unowned float* get_embeddings_ith(int index);

		[CCode (cname = "llama_get_embeddings")]
		public unowned float* get_embeddings();
	}

	[Compact]
	[CCode (cname = "struct llama_vocab", free_function = "")]
	public class Vocab
	{
		[CCode (cname = "llama_tokenize")]
		public int tokenize(
			string text,
			int text_length,
			int* tokens,
			int max_tokens,
			bool add_special,
			bool parse_special
		);
	}

	[SimpleType]
	[CCode (cname = "struct llama_model_params")]
	public struct ModelParams
	{
		public void* devices;
		public void* tensor_buft_overrides;
		public int n_gpu_layers;

		[CCode (cname = "llama_model_default_params")]
		public ModelParams();
	}

	[SimpleType]
	[CCode (cname = "struct llama_context_params")]
	public struct ContextParams
	{
		public uint n_ctx;
		public int n_threads;
		public int n_threads_batch;
		public PoolingType pooling_type;
		public bool embeddings;

		[CCode (cname = "llama_context_default_params")]
		public ContextParams();
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

		[CCode (cname = "llama_batch_init")]
		public Batch(int token_count, int embedding_count, int sequence_count);

		[CCode (cname = "llama_batch_free")]
		public void free();
	}

	[CCode (cname = "llama_backend_init")]
	public static void backend_init();

	[CCode (cname = "llama_supports_gpu_offload")]
	public static bool supports_gpu_offload();
}
