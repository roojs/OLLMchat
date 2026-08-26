#pragma once
#include <ffi.h>
#include <glib.h>

typedef union {
	gint v_int32;
	guint8 v_uint8;
	gint16 v_int16;
	guint16 v_uint16;
	guint v_uint32;
	gint64 v_int64;
	guint64 v_uint64;
	gfloat v_float;
	gdouble v_double;
	gpointer v_pointer;
} OLLMrpcFfiArg;

static inline void ollmrpc_ffi_arg_set_int32(OLLMrpcFfiArg *a, gint v)
{
	a->v_int32 = v;
}

static inline void ollmrpc_ffi_arg_set_uint8(OLLMrpcFfiArg *a, guint8 v)
{
	a->v_uint8 = v;
}

static inline void ollmrpc_ffi_arg_set_int16(OLLMrpcFfiArg *a, gint16 v)
{
	a->v_int16 = v;
}

static inline void ollmrpc_ffi_arg_set_uint16(OLLMrpcFfiArg *a, guint16 v)
{
	a->v_uint16 = v;
}

static inline void ollmrpc_ffi_arg_set_uint32(OLLMrpcFfiArg *a, guint v)
{
	a->v_uint32 = v;
}

static inline void ollmrpc_ffi_arg_set_int64(OLLMrpcFfiArg *a, gint64 v)
{
	a->v_int64 = v;
}

static inline void ollmrpc_ffi_arg_set_uint64(OLLMrpcFfiArg *a, guint64 v)
{
	a->v_uint64 = v;
}

static inline void ollmrpc_ffi_arg_set_float(OLLMrpcFfiArg *a, gfloat v)
{
	a->v_float = v;
}

static inline void ollmrpc_ffi_arg_set_double(OLLMrpcFfiArg *a, gdouble v)
{
	a->v_double = v;
}

static inline void ollmrpc_ffi_arg_set_pointer(OLLMrpcFfiArg *a, gpointer v)
{
	a->v_pointer = v;
}

#define OLLMRPC_FFI_TYPE_VOID (&ffi_type_void)
#define OLLMRPC_FFI_TYPE_POINTER (&ffi_type_pointer)
#define OLLMRPC_FFI_TYPE_UINT8 (&ffi_type_uint8)
#define OLLMRPC_FFI_TYPE_SINT16 (&ffi_type_sint16)
#define OLLMRPC_FFI_TYPE_UINT16 (&ffi_type_uint16)
#define OLLMRPC_FFI_TYPE_SINT32 (&ffi_type_sint32)
#define OLLMRPC_FFI_TYPE_UINT32 (&ffi_type_uint32)
#define OLLMRPC_FFI_TYPE_SINT64 (&ffi_type_sint64)
#define OLLMRPC_FFI_TYPE_UINT64 (&ffi_type_uint64)
#define OLLMRPC_FFI_TYPE_FLOAT (&ffi_type_float)
#define OLLMRPC_FFI_TYPE_DOUBLE (&ffi_type_double)

static inline int ollmrpc_ffi_prep_void(ffi_cif *cif, unsigned int nargs, ffi_type **atypes)
{
	return ffi_prep_cif(cif, FFI_DEFAULT_ABI, nargs, &ffi_type_void, atypes);
}

static inline void ollmrpc_ffi_call_void(ffi_cif *cif, void *fn, OLLMrpcFfiArg *slots, unsigned int n)
{
	void **avalues = g_newa(void *, n);
	unsigned int i;
	for (i = 0; i < n; i++) {
		avalues[i] = &slots[i];
	}
	ffi_call(cif, fn, NULL, avalues);
}
