#ifndef OLLMCHAT_LLAMA_PROBE_H
#define OLLMCHAT_LLAMA_PROBE_H

#include <glib.h>

G_BEGIN_DECLS

typedef enum {
	OLLMCHAT_LLAMA_POOLING_UNSPECIFIED = 0,
	OLLMCHAT_LLAMA_POOLING_NONE,
	OLLMCHAT_LLAMA_POOLING_MEAN,
	OLLMCHAT_LLAMA_POOLING_CLS,
	OLLMCHAT_LLAMA_POOLING_LAST
} OllmchatLlamaPooling;

typedef struct _OllmchatLlamaEmbedding OllmchatLlamaEmbedding;

OllmchatLlamaEmbedding *ollmchat_llama_embed_text(
	const char *model_path,
	const char *text,
	int context_length,
	int threads,
	OllmchatLlamaPooling pooling,
	char **error_message
);

int ollmchat_llama_embedding_length(const OllmchatLlamaEmbedding *embedding);

float ollmchat_llama_embedding_get(
	const OllmchatLlamaEmbedding *embedding,
	int index
);

void ollmchat_llama_embedding_free(OllmchatLlamaEmbedding *embedding);

G_END_DECLS

#endif
