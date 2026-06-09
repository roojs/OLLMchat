[CCode (cheader_filename = "llama.h", lower_case_cprefix = "llama_")]
namespace Llama
{
	[CCode (cname = "LLAMA_TOKEN_NULL")]
	public const int TOKEN_NULL;

	[CCode (cname = "LLAMA_DEFAULT_SEED")]
	public const uint DEFAULT_SEED;

	[CCode (cname = "enum ggml_log_level", cprefix = "GGML_LOG_LEVEL_")]
	public enum LogLevel
	{
		NONE,
		DEBUG,
		INFO,
		WARN,
		ERROR,
		CONT
	}

	[CCode (cname = "ggml_log_callback", has_target = false)]
	public delegate void LogCallback(LogLevel level, string text, void* user_data);

	[CCode (cname = "llama_seq_id")]
	public struct SeqId : int {}

	[CCode (cname = "enum llama_context_type", cprefix = "LLAMA_CONTEXT_TYPE_")]
	public enum ContextType
	{
		DEFAULT,
		MTP
	}

	[CCode (cname = "enum llama_rope_scaling_type", cprefix = "LLAMA_ROPE_SCALING_TYPE_")]
	public enum RopeScalingType
	{
		UNSPECIFIED = -1,
		NONE,
		LINEAR,
		YARN,
		LONGROPE
	}

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

		[CCode (cname = "llama_token_to_piece")]
		public int token_to_piece(
			int token,
			[CCode (array_length = false)] char[] buf,
			int length,
			int lstrip,
			bool special
		);

		[CCode (cname = "llama_vocab_is_eog")]
		public bool is_eog(int token);
	}

	[Compact]
	[CCode (cname = "struct llama_sampler", free_function = "llama_sampler_free")]
	public class Sampler {}

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
		public uint n_batch;
		public uint n_ubatch;
		public uint n_seq_max;
		public uint n_rs_seq;
		public uint n_outputs_max;
		public int n_threads;
		public int n_threads_batch;
		public ContextType ctx_type;
		public RopeScalingType rope_scaling_type;
		public PoolingType pooling_type;

		[CCode (cname = "llama_context_default_params")]
		public ContextParams();
	}

	[CCode (cname = "llama_set_embeddings")]
	public static void set_embeddings(Context ctx, bool embeddings);

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

	[SimpleType]
	[CCode (cname = "struct llama_sampler_chain_params")]
	public struct SamplerChainParams
	{
		public bool no_perf;

		[CCode (cname = "llama_sampler_chain_default_params")]
		public SamplerChainParams();
	}

	[CCode (cname = "llama_log_set")]
	public static void log_set(LogCallback callback, void* user_data = null);

	[CCode (cname = "llama_backend_init")]
	public static void backend_init();

	[CCode (cname = "llama_supports_gpu_offload")]
	public static bool supports_gpu_offload();

	[CCode (cname = "llama_sampler_chain_init")]
	public static Sampler sampler_chain_init(SamplerChainParams parameters);

	[CCode (cname = "llama_sampler_chain_add")]
	public static void sampler_chain_add(Sampler chain, Sampler sampler);

	[CCode (cname = "llama_sampler_init_greedy")]
	public static Sampler sampler_init_greedy();

	[CCode (cname = "llama_sampler_init_dist")]
	public static Sampler sampler_init_dist(uint seed);

	[CCode (cname = "llama_sampler_sample")]
	public static int sampler_sample(Sampler sampler, Context ctx, int index);

	[CCode (cname = "llama_sampler_accept")]
	public static void sampler_accept(Sampler sampler, int token);
}
