#include "ollmchat-llama-probe.h"

#include <llama.h>
#include <math.h>
#include <string.h>

struct _OllmchatLlamaEmbedding {
	int length;
	float *data;
};

static gboolean llama_backend_ready = FALSE;

static enum llama_pooling_type
ollmchat_llama_pooling_to_native(OllmchatLlamaPooling pooling)
{
	switch (pooling) {
	case OLLMCHAT_LLAMA_POOLING_NONE:
		return LLAMA_POOLING_TYPE_NONE;
	case OLLMCHAT_LLAMA_POOLING_CLS:
		return LLAMA_POOLING_TYPE_CLS;
	case OLLMCHAT_LLAMA_POOLING_LAST:
		return LLAMA_POOLING_TYPE_LAST;
	case OLLMCHAT_LLAMA_POOLING_MEAN:
	case OLLMCHAT_LLAMA_POOLING_UNSPECIFIED:
	default:
		return LLAMA_POOLING_TYPE_MEAN;
	}
}

static void
ollmchat_llama_set_error(char **error_message, const char *message)
{
	if (error_message != NULL) {
		*error_message = g_strdup(message);
	}
}

static void
ollmchat_llama_normalize(float *vector, int length)
{
	double norm_squared = 0.0;

	for (int i = 0; i < length; i++) {
		double value = vector[i];
		norm_squared += value * value;
	}

	double norm = sqrt(norm_squared);
	if (norm <= 0.0) {
		return;
	}

	for (int i = 0; i < length; i++) {
		vector[i] = (float)((double)vector[i] / norm);
	}
}

OllmchatLlamaEmbedding *
ollmchat_llama_embed_text(
	const char *model_path,
	const char *text,
	int context_length,
	int threads,
	OllmchatLlamaPooling pooling,
	char **error_message
)
{
	if (error_message != NULL) {
		*error_message = NULL;
	}
	if (model_path == NULL || model_path[0] == '\0') {
		ollmchat_llama_set_error(error_message, "model path is required");
		return NULL;
	}
	if (text == NULL || text[0] == '\0') {
		ollmchat_llama_set_error(error_message, "text is required");
		return NULL;
	}

	if (!llama_backend_ready) {
		llama_backend_init();
		llama_backend_ready = TRUE;
	}

	struct llama_model_params model_params = llama_model_default_params();
	struct llama_model *model = llama_model_load_from_file(model_path, model_params);
	if (model == NULL) {
		ollmchat_llama_set_error(error_message, "failed to load GGUF model");
		return NULL;
	}

	struct llama_context_params ctx_params = llama_context_default_params();
	ctx_params.embeddings = true;
	ctx_params.pooling_type = ollmchat_llama_pooling_to_native(pooling);
	ctx_params.n_ctx = context_length > 0 ? (uint32_t)context_length : 2048;
	ctx_params.n_threads = threads > 0 ? threads : g_get_num_processors();
	ctx_params.n_threads_batch = ctx_params.n_threads;

	struct llama_context *ctx = llama_init_from_model(model, ctx_params);
	if (ctx == NULL) {
		llama_model_free(model);
		ollmchat_llama_set_error(error_message, "failed to create llama context");
		return NULL;
	}

	const struct llama_vocab *vocab = llama_model_get_vocab(model);
	const int text_len = (int)strlen(text);
	int token_count = -llama_tokenize(
		vocab,
		text,
		text_len,
		NULL,
		0,
		true,
		true
	);
	if (token_count <= 0) {
		llama_free(ctx);
		llama_model_free(model);
		ollmchat_llama_set_error(error_message, "failed to count prompt tokens");
		return NULL;
	}
	if (token_count > (int)ctx_params.n_ctx) {
		llama_free(ctx);
		llama_model_free(model);
		ollmchat_llama_set_error(error_message, "prompt exceeds embedding context length");
		return NULL;
	}

	llama_token *tokens = g_new0(llama_token, token_count);
	int actual_tokens = llama_tokenize(
		vocab,
		text,
		text_len,
		tokens,
		token_count,
		true,
		true
	);
	if (actual_tokens < 0 || actual_tokens > token_count) {
		g_free(tokens);
		llama_free(ctx);
		llama_model_free(model);
		ollmchat_llama_set_error(error_message, "failed to tokenize prompt");
		return NULL;
	}
	token_count = actual_tokens;

	struct llama_batch batch = llama_batch_init(token_count, 0, 1);
	batch.n_tokens = token_count;
	for (int i = 0; i < token_count; i++) {
		batch.token[i] = tokens[i];
		batch.pos[i] = i;
		batch.n_seq_id[i] = 1;
		batch.seq_id[i][0] = 0;
		batch.logits[i] = i == token_count - 1;
	}

	int decode_result = llama_decode(ctx, batch);
	if (decode_result < 0) {
		llama_batch_free(batch);
		g_free(tokens);
		llama_free(ctx);
		llama_model_free(model);
		ollmchat_llama_set_error(error_message, "llama_decode failed");
		return NULL;
	}

	const float *source_embedding = llama_get_embeddings_seq(ctx, 0);
	if (source_embedding == NULL) {
		source_embedding = llama_get_embeddings_ith(ctx, token_count - 1);
	}
	if (source_embedding == NULL) {
		source_embedding = llama_get_embeddings(ctx);
	}
	if (source_embedding == NULL) {
		llama_batch_free(batch);
		g_free(tokens);
		llama_free(ctx);
		llama_model_free(model);
		ollmchat_llama_set_error(error_message, "model did not return embeddings");
		return NULL;
	}

	int dimension = llama_model_n_embd(model);
	OllmchatLlamaEmbedding *embedding = g_new0(OllmchatLlamaEmbedding, 1);
	embedding->length = dimension;
	embedding->data = g_new0(float, dimension);
	memcpy(embedding->data, source_embedding, sizeof(float) * dimension);
	ollmchat_llama_normalize(embedding->data, dimension);

	llama_batch_free(batch);
	g_free(tokens);
	llama_free(ctx);
	llama_model_free(model);

	return embedding;
}

int
ollmchat_llama_embedding_length(const OllmchatLlamaEmbedding *embedding)
{
	return embedding == NULL ? 0 : embedding->length;
}

float
ollmchat_llama_embedding_get(const OllmchatLlamaEmbedding *embedding, int index)
{
	if (embedding == NULL || index < 0 || index >= embedding->length) {
		return 0.0f;
	}
	return embedding->data[index];
}

void
ollmchat_llama_embedding_free(OllmchatLlamaEmbedding *embedding)
{
	if (embedding == NULL) {
		return;
	}
	g_free(embedding->data);
	g_free(embedding);
}
