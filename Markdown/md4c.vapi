[CCode (cprefix = "MD_", lower_case_cprefix = "md_", cheader_filename = "md4c.h")]
namespace MD4C {
	[CCode (cname = "MD_SIZE")]
	public uint SIZE;

	[CCode (cname = "MD_OFFSET")]
	public uint OFFSET;

	[CCode (cname = "MD_BLOCKTYPE", cprefix = "MD_BLOCK_")]
	public enum BlockType {
		DOC,
		QUOTE,
		UL,
		OL,
		LI,
		HR,
		H,
		CODE,
		HTML,
		P,
		TABLE,
		THEAD,
		TBODY,
		TR,
		TH,
		TD
	}

	[CCode (cname = "MD_SPANTYPE", cprefix = "MD_SPAN_")]
	public enum SpanType {
		EM,
		STRONG,
		A,
		IMG,
		CODE,
		DEL,
		LATEXMATH,
		LATEXMATH_DISPLAY,
		WIKILINK,
		U
	}

	[CCode (cname = "MD_TEXTTYPE", cprefix = "MD_TEXT_")]
	public enum TextType {
		NORMAL,
		NULLCHAR,
		BR,
		SOFTBR,
		ENTITY,
		CODE,
		HTML,
		LATEXMATH
	}

	[CCode (cname = "MD_ALIGN", cprefix = "MD_ALIGN_")]
	public enum Align {
		DEFAULT,
		LEFT,
		CENTER,
		RIGHT
	}

	[CCode (cname = "MD_ATTRIBUTE")]
	public struct Attribute {
		[CCode (cname = "text", type = "const MD_CHAR*")]
		public unowned string text;
		[CCode (cname = "size")]
		public SIZE size;
		[CCode (cname = "substr_types", type = "const MD_TEXTTYPE*")]
		public unowned TextType[] substr_types;
		[CCode (cname = "substr_offsets", type = "const MD_OFFSET*")]
		public unowned OFFSET[] substr_offsets;
	}

	[CCode (cname = "MD_BLOCK_UL_DETAIL")]
	public struct BlockULDetail {
		[CCode (cname = "is_tight")]
		public int is_tight;
		[CCode (cname = "mark", type = "MD_CHAR")]
		public char mark;
	}

	[CCode (cname = "MD_BLOCK_OL_DETAIL")]
	public struct BlockOLDetail {
		[CCode (cname = "start")]
		public uint start;
		[CCode (cname = "is_tight")]
		public int is_tight;
		[CCode (cname = "mark_delimiter", type = "MD_CHAR")]
		public char mark_delimiter;
	}

	[CCode (cname = "MD_BLOCK_LI_DETAIL")]
	public struct BlockLIDetail {
		[CCode (cname = "is_task")]
		public int is_task;
		[CCode (cname = "task_mark", type = "MD_CHAR")]
		public char task_mark;
		[CCode (cname = "task_mark_offset")]
		public OFFSET task_mark_offset;
	}

	[CCode (cname = "MD_BLOCK_H_DETAIL")]
	public struct BlockHDetail {
		[CCode (cname = "level")]
		public uint level;
	}

	[CCode (cname = "MD_BLOCK_CODE_DETAIL")]
	public struct BlockCodeDetail {
		[CCode (cname = "info")]
		public Attribute info;
		[CCode (cname = "lang")]
		public Attribute lang;
		[CCode (cname = "fence_char", type = "MD_CHAR")]
		public char fence_char;
	}

	[CCode (cname = "MD_BLOCK_TABLE_DETAIL")]
	public struct BlockTableDetail {
		[CCode (cname = "col_count")]
		public uint col_count;
		[CCode (cname = "head_row_count")]
		public uint head_row_count;
		[CCode (cname = "body_row_count")]
		public uint body_row_count;
	}

	[CCode (cname = "MD_BLOCK_TD_DETAIL")]
	public struct BlockTDDetail {
		[CCode (cname = "align")]
		public Align align;
	}

	[CCode (cname = "MD_SPAN_A_DETAIL")]
	public struct SpanADetail {
		[CCode (cname = "href")]
		public Attribute href;
		[CCode (cname = "title")]
		public Attribute title;
		[CCode (cname = "is_autolink")]
		public int is_autolink;
	}

	[CCode (cname = "MD_SPAN_IMG_DETAIL")]
	public struct SpanIMGDetail {
		[CCode (cname = "src")]
		public Attribute src;
		[CCode (cname = "title")]
		public Attribute title;
	}

	[CCode (cname = "MD_SPAN_WIKILINK_DETAIL")]
	public struct SpanWikilinkDetail {
		[CCode (cname = "target")]
		public Attribute target;
	}

	[CCode (cname = "MD_FLAG_COLLAPSEWHITESPACE")]
	public const uint FLAG_COLLAPSEWHITESPACE;
	[CCode (cname = "MD_FLAG_PERMISSIVEATXHEADERS")]
	public const uint FLAG_PERMISSIVEATXHEADERS;
	[CCode (cname = "MD_FLAG_PERMISSIVEURLAUTOLINKS")]
	public const uint FLAG_PERMISSIVEURLAUTOLINKS;
	[CCode (cname = "MD_FLAG_PERMISSIVEEMAILAUTOLINKS")]
	public const uint FLAG_PERMISSIVEEMAILAUTOLINKS;
	[CCode (cname = "MD_FLAG_NOINDENTEDCODEBLOCKS")]
	public const uint FLAG_NOINDENTEDCODEBLOCKS;
	[CCode (cname = "MD_FLAG_NOHTMLBLOCKS")]
	public const uint FLAG_NOHTMLBLOCKS;
	[CCode (cname = "MD_FLAG_NOHTMLSPANS")]
	public const uint FLAG_NOHTMLSPANS;
	[CCode (cname = "MD_FLAG_TABLES")]
	public const uint FLAG_TABLES;
	[CCode (cname = "MD_FLAG_STRIKETHROUGH")]
	public const uint FLAG_STRIKETHROUGH;
	[CCode (cname = "MD_FLAG_PERMISSIVEWWWAUTOLINKS")]
	public const uint FLAG_PERMISSIVEWWWAUTOLINKS;
	[CCode (cname = "MD_FLAG_TASKLISTS")]
	public const uint FLAG_TASKLISTS;
	[CCode (cname = "MD_FLAG_LATEXMATHSPANS")]
	public const uint FLAG_LATEXMATHSPANS;
	[CCode (cname = "MD_FLAG_WIKILINKS")]
	public const uint FLAG_WIKILINKS;
	[CCode (cname = "MD_FLAG_UNDERLINE")]
	public const uint FLAG_UNDERLINE;
	[CCode (cname = "MD_FLAG_HARD_SOFT_BREAKS")]
	public const uint FLAG_HARD_SOFT_BREAKS;
	[CCode (cname = "MD_FLAG_PERMISSIVEAUTOLINKS")]
	public const uint FLAG_PERMISSIVEAUTOLINKS;
	[CCode (cname = "MD_FLAG_NOHTML")]
	public const uint FLAG_NOHTML;
	[CCode (cname = "MD_DIALECT_COMMONMARK")]
	public const uint DIALECT_COMMONMARK;
	[CCode (cname = "MD_DIALECT_GITHUB")]
	public const uint DIALECT_GITHUB;

	[CCode (cname = "int (*)(MD_BLOCKTYPE, void*, void*)", has_target = false)]
	public delegate int ParserEnterBlockFunc (BlockType type, void* detail, void* userdata);

	[CCode (cname = "int (*)(MD_BLOCKTYPE, void*, void*)", has_target = false)]
	public delegate int ParserLeaveBlockFunc (BlockType type, void* detail, void* userdata);

	[CCode (cname = "int (*)(MD_SPANTYPE, void*, void*)", has_target = false)]
	public delegate int ParserEnterSpanFunc (SpanType type, void* detail, void* userdata);

	[CCode (cname = "int (*)(MD_SPANTYPE, void*, void*)", has_target = false)]
	public delegate int ParserLeaveSpanFunc (SpanType type, void* detail, void* userdata);

	[CCode (cname = "int (*)(MD_TEXTTYPE, const MD_CHAR*, MD_SIZE, void*)", has_target = false)]
	public delegate int ParserTextFunc (TextType type, [CCode (type = "const MD_CHAR*")] string text, SIZE size, void* userdata);

	[CCode (cname = "void (*)(const char*, void*)", has_target = false)]
	public delegate void ParserDebugLogFunc (string msg, void* userdata);

	[CCode (cname = "void (*)(void)", has_target = false)]
	public delegate void ParserSyntaxFunc ();

	[CCode (cname = "MD_PARSER")]
	public struct Parser {
		[CCode (cname = "abi_version")]
		public uint abi_version;
		[CCode (cname = "flags")]
		public uint flags;
		[CCode (cname = "enter_block")]
		public ParserEnterBlockFunc? enter_block;
		[CCode (cname = "leave_block")]
		public ParserLeaveBlockFunc? leave_block;
		[CCode (cname = "enter_span")]
		public ParserEnterSpanFunc? enter_span;
		[CCode (cname = "leave_span")]
		public ParserLeaveSpanFunc? leave_span;
		[CCode (cname = "text")]
		public ParserTextFunc? text;
		[CCode (cname = "debug_log")]
		public ParserDebugLogFunc? debug_log;
		[CCode (cname = "syntax")]
		public ParserSyntaxFunc? syntax;
	}

	[CCode (cname = "md_parse")]
	public int parse ([CCode (type = "const MD_CHAR*")] string text, SIZE size, ref Parser parser, void* userdata);
}

