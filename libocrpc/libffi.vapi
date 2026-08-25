[CCode (cheader_filename = "ffi.h,libffi-arg.h")]
namespace Libffi {
	[CCode (cname = "ffi_type*", cprefix = "ffi_type_", has_type_id = false)]
	[SimpleType]
	public struct Type {
	}

	[CCode (cname = "OLLMRPC_FFI_TYPE_VOID")]
	public const Type VOID;

	[CCode (cname = "OLLMRPC_FFI_TYPE_POINTER")]
	public const Type POINTER;

	[CCode (cname = "OLLMRPC_FFI_TYPE_UINT8")]
	public const Type UINT8;

	[CCode (cname = "OLLMRPC_FFI_TYPE_SINT16")]
	public const Type SINT16;

	[CCode (cname = "OLLMRPC_FFI_TYPE_UINT16")]
	public const Type UINT16;

	[CCode (cname = "OLLMRPC_FFI_TYPE_SINT32")]
	public const Type SINT32;

	[CCode (cname = "OLLMRPC_FFI_TYPE_UINT32")]
	public const Type UINT32;

	[CCode (cname = "OLLMRPC_FFI_TYPE_SINT64")]
	public const Type SINT64;

	[CCode (cname = "OLLMRPC_FFI_TYPE_UINT64")]
	public const Type UINT64;

	[CCode (cname = "OLLMRPC_FFI_TYPE_FLOAT")]
	public const Type FLOAT;

	[CCode (cname = "OLLMRPC_FFI_TYPE_DOUBLE")]
	public const Type DOUBLE;

	[CCode (cname = "OLLMrpcFfiArg", has_type_id = false)]
	public struct Arg {
		[CCode (cname = "ollmrpc_ffi_arg_set_int32")]
		public void set_int32(int v);

		[CCode (cname = "ollmrpc_ffi_arg_set_uint8")]
		public void set_uint8(uint8 v);

		[CCode (cname = "ollmrpc_ffi_arg_set_int16")]
		public void set_int16(int16 v);

		[CCode (cname = "ollmrpc_ffi_arg_set_uint16")]
		public void set_uint16(uint16 v);

		[CCode (cname = "ollmrpc_ffi_arg_set_uint32")]
		public void set_uint32(uint v);

		[CCode (cname = "ollmrpc_ffi_arg_set_int64")]
		public void set_int64(int64 v);

		[CCode (cname = "ollmrpc_ffi_arg_set_uint64")]
		public void set_uint64(uint64 v);

		[CCode (cname = "ollmrpc_ffi_arg_set_float")]
		public void set_float(float v);

		[CCode (cname = "ollmrpc_ffi_arg_set_double")]
		public void set_double(double v);

		[CCode (cname = "ollmrpc_ffi_arg_set_pointer")]
		public void set_pointer(void* v);
	}

	[CCode (cname = "ffi_cif", has_type_id = false, destroy_function = "")]
	public struct Cif {
		/**
		 * ''ffi_prep_cif'' for a void return and the default ABI.
		 *
		 * @return 0 on success (''FFI_OK'')
		 */
		[CCode (cname = "ollmrpc_ffi_prep_void")]
		public static int prep(
			out Cif cif,
			[CCode (array_length_type = "unsigned int", array_length_pos = 1.5)] Type[] atypes
		);

		/**
		 * ''ffi_call'' with no return slot. Builds ''avalues'' from ''slots''.
		 */
		[CCode (cname = "ollmrpc_ffi_call_void")]
		public void call(
			void* fn,
			[CCode (array_length_type = "unsigned int", array_length_pos = 2.9)] Arg[] slots
		);
	}
}
