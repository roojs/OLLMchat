[CCode (cprefix = "ts_", lower_case_cprefix = "ts_", cheader_filename = "tree_sitter/api.h")]
namespace TreeSitter {

	/* Constants */
	[CCode (cname = "TREE_SITTER_LANGUAGE_VERSION")]
	public const uint16 LANGUAGE_VERSION;
	[CCode (cname = "TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION")]
	public const uint16 MIN_COMPATIBLE_LANGUAGE_VERSION;

	/* Types */
	[CCode (cname = "TSSymbol")]
	public struct Symbol {
		public uint16 value;
	}

	[CCode (cname = "TSFieldId")]
	public struct FieldId {
		public uint16 value;
	}

	[CCode (cname = "TSLanguage", free_function = "", ref_function = "", unref_function = "")]
	public class Language {
	}

	[CCode (cname = "TSParser", free_function = "ts_parser_delete", ref_function = "", unref_function = "")]
	public class Parser {
		[CCode (cname = "ts_parser_new")]
		public Parser ();
		[CCode (cname = "ts_parser_set_language")]
		public bool set_language (Language language);
		[CCode (cname = "ts_parser_language")]
		public unowned Language? get_language ();
		[CCode (cname = "ts_parser_set_included_ranges")]
		public bool set_included_ranges ([CCode (array_length_type = "uint32_t")] Range[]? ranges, uint32 length);
		[CCode (cname = "ts_parser_included_ranges")]
		public unowned Range[]? get_included_ranges (out uint32 length);
		[CCode (cname = "ts_parser_parse")]
		public Tree? parse (Tree? old_tree, Input input);
		[CCode (cname = "ts_parser_parse_string")]
		public Tree? parse_string (Tree? old_tree, string? str, uint32 length);
		[CCode (cname = "ts_parser_parse_string_encoding")]
		public Tree? parse_string_encoding (Tree? old_tree, string? str, uint32 length, InputEncoding encoding);
		[CCode (cname = "ts_parser_reset")]
		public void reset ();
		[CCode (cname = "ts_parser_set_timeout_micros")]
		public void set_timeout_micros (uint64 timeout);
		[CCode (cname = "ts_parser_timeout_micros")]
		public uint64 get_timeout_micros ();
		[CCode (cname = "ts_parser_set_cancellation_flag")]
		public void set_cancellation_flag (size_t* flag);
		[CCode (cname = "ts_parser_cancellation_flag")]
		public unowned size_t* get_cancellation_flag ();
		[CCode (cname = "ts_parser_set_logger")]
		public void set_logger (Logger logger);
		[CCode (cname = "ts_parser_logger")]
		public Logger get_logger ();
		[CCode (cname = "ts_parser_print_dot_graphs")]
		public void print_dot_graphs (int file);
	}

	[CCode (cname = "TSTree", free_function = "ts_tree_delete", ref_function = "ts_tree_copy", unref_function = "ts_tree_delete")]
	public class Tree {
		[CCode (cname = "ts_tree_root_node")]
		public Node get_root_node ();
		[CCode (cname = "ts_tree_root_node_with_offset")]
		public Node get_root_node_with_offset (uint32 offset_bytes, Point offset_point);
		[CCode (cname = "ts_tree_language")]
		public unowned Language? get_language ();
		[CCode (cname = "ts_tree_included_ranges")]
		public Range[]? get_included_ranges (out uint32 length);
		[CCode (cname = "ts_tree_edit")]
		public void edit (InputEdit edit);
		[CCode (cname = "ts_tree_get_changed_ranges", array_length_type = "uint32_t")]
		public Range[]? get_changed_ranges (Tree old_tree, Tree new_tree, out uint32 length);
		[CCode (cname = "ts_tree_print_dot_graph")]
		public void print_dot_graph (int file_descriptor);
	}

	[CCode (cname = "TSQuery", free_function = "ts_query_delete", ref_function = "", unref_function = "")]
	public class Query {
		[CCode (cname = "ts_query_new")]
		public Query (Language language, string source, uint32 source_len, out uint32 error_offset, out QueryError error_type);
		[CCode (cname = "ts_query_pattern_count")]
		public uint32 get_pattern_count ();
		[CCode (cname = "ts_query_capture_count")]
		public uint32 get_capture_count ();
		[CCode (cname = "ts_query_string_count")]
		public uint32 get_string_count ();
		[CCode (cname = "ts_query_start_byte_for_pattern")]
		public uint32 get_start_byte_for_pattern (uint32 pattern_index);
		[CCode (cname = "ts_query_predicates_for_pattern", array_length_type = "uint32_t")]
		public unowned QueryPredicateStep[]? get_predicates_for_pattern (uint32 pattern_index, out uint32 length);
		[CCode (cname = "ts_query_is_pattern_rooted")]
		public bool is_pattern_rooted (uint32 pattern_index);
		[CCode (cname = "ts_query_is_pattern_non_local")]
		public bool is_pattern_non_local (uint32 pattern_index);
		[CCode (cname = "ts_query_is_pattern_guaranteed_at_step")]
		public bool is_pattern_guaranteed_at_step (uint32 byte_offset);
		[CCode (cname = "ts_query_capture_name_for_id")]
		public unowned string? get_capture_name_for_id (uint32 id, out uint32 length);
		[CCode (cname = "ts_query_capture_quantifier_for_id")]
		public Quantifier get_capture_quantifier_for_id (uint32 pattern_id, uint32 capture_id);
		[CCode (cname = "ts_query_string_value_for_id")]
		public unowned string? get_string_value_for_id (uint32 id, out uint32 length);
		[CCode (cname = "ts_query_disable_capture")]
		public void disable_capture (string name, uint32 length);
		[CCode (cname = "ts_query_disable_pattern")]
		public void disable_pattern (uint32 pattern_index);
	}

	[CCode (cname = "TSQueryCursor", free_function = "ts_query_cursor_delete", ref_function = "", unref_function = "")]
	public class QueryCursor {
		[CCode (cname = "ts_query_cursor_new")]
		public QueryCursor ();
		[CCode (cname = "ts_query_cursor_exec")]
		public void exec (Query query, Node node);
		[CCode (cname = "ts_query_cursor_did_exceed_match_limit")]
		public bool did_exceed_match_limit ();
		[CCode (cname = "ts_query_cursor_match_limit")]
		public uint32 get_match_limit ();
		[CCode (cname = "ts_query_cursor_set_match_limit")]
		public void set_match_limit (uint32 limit);
		[CCode (cname = "ts_query_cursor_set_byte_range")]
		public void set_byte_range (uint32 start_byte, uint32 end_byte);
		[CCode (cname = "ts_query_cursor_set_point_range")]
		public void set_point_range (Point start_point, Point end_point);
		[CCode (cname = "ts_query_cursor_next_match")]
		public bool next_match (out QueryMatch match);
		[CCode (cname = "ts_query_cursor_remove_match")]
		public void remove_match (uint32 id);
		[CCode (cname = "ts_query_cursor_next_capture")]
		public bool next_capture (out QueryMatch match, out uint32 capture_index);
	}

	[CCode (cname = "TSInputEncoding", cprefix = "TSInputEncoding")]
	public enum InputEncoding {
		UTF8,
		UTF16
	}

	[CCode (cname = "TSSymbolType", cprefix = "TSSymbolType")]
	public enum SymbolType {
		REGULAR,
		ANONYMOUS,
		AUXILIARY
	}

	[CCode (cname = "TSPoint")]
	[SimpleType]
	public struct Point {
		[CCode (cname = "row")]
		public uint32 row;
		[CCode (cname = "column")]
		public uint32 column;
	}

	[CCode (cname = "TSRange")]
	public struct Range {
		[CCode (cname = "start_point")]
		public Point start_point;
		[CCode (cname = "end_point")]
		public Point end_point;
		[CCode (cname = "start_byte")]
		public uint32 start_byte;
		[CCode (cname = "end_byte")]
		public uint32 end_byte;
	}

	[CCode (has_target = false, cheader_filename = "tree_sitter/api.h")]
	public delegate unowned string? InputReadFunc (void* payload, uint32 byte_index, Point position, out uint32 bytes_read);

	[CCode (cname = "TSInput")]
	public struct Input {
		[CCode (cname = "payload")]
		public void* payload;
		[CCode (cname = "read", type = "const char*(*)(void*, uint32_t, TSPoint, uint32_t*)")]
		public InputReadFunc? read;
		[CCode (cname = "encoding")]
		public InputEncoding encoding;
	}

	[CCode (cname = "TSLogType", cprefix = "TSLogType")]
	public enum LogType {
		PARSE,
		LEX
	}

	[CCode (has_target = false, cheader_filename = "tree_sitter/api.h")]
	public delegate void LoggerLogFunc (void* payload, LogType type, string message);

	[CCode (cname = "TSLogger")]
	public struct Logger {
		[CCode (cname = "payload")]
		public void* payload;
		[CCode (cname = "log", type = "void(*)(void*, TSLogType, const char*)")]
		public LoggerLogFunc? log;
	}

	[CCode (cname = "TSInputEdit")]
	public struct InputEdit {
		[CCode (cname = "start_byte")]
		public uint32 start_byte;
		[CCode (cname = "old_end_byte")]
		public uint32 old_end_byte;
		[CCode (cname = "new_end_byte")]
		public uint32 new_end_byte;
		[CCode (cname = "start_point")]
		public Point start_point;
		[CCode (cname = "old_end_point")]
		public Point old_end_point;
		[CCode (cname = "new_end_point")]
		public Point new_end_point;
	}

	[CCode (cname = "TSNode")]
	[SimpleType]
	public struct Node {
		[CCode (cname = "context", array_length = false, array_null_terminated = false)]
		public uint32 context[4];
		[CCode (cname = "id")]
		public void* id;
		[CCode (cname = "tree")]
		public unowned Tree? tree;
		
		[CCode (cname = "ts_node_type")]
		public unowned string? get_type ();
		[CCode (cname = "ts_node_symbol")]
		public Symbol get_symbol ();
		[CCode (cname = "ts_node_start_byte")]
		public uint32 get_start_byte ();
		[CCode (cname = "ts_node_start_point", array_length = false)]
		public Point get_start_point ();
		[CCode (cname = "ts_node_end_byte")]
		public uint32 get_end_byte ();
		[CCode (cname = "ts_node_end_point", array_length = false)]
		public Point get_end_point ();
	}

	/* Node functions */
	[CCode (cname = "ts_node_type")]
	public unowned string? node_get_type (Node node);
	[CCode (cname = "ts_node_symbol")]
	public Symbol node_get_symbol (Node node);
	[CCode (cname = "ts_node_start_byte")]
	public uint32 node_get_start_byte (Node node);
	[CCode (cname = "ts_node_start_point", returns_value_pos = -1)]
	public Point node_get_start_point (Node node);
	[CCode (cname = "ts_node_end_byte")]
	public uint32 node_get_end_byte (Node node);
	[CCode (cname = "ts_node_end_point", returns_value_pos = -1)]
	public Point node_get_end_point (Node node);
	[CCode (cname = "ts_node_string")]
	public string? node_to_string (Node node);
	[CCode (cname = "ts_node_is_null")]
	public bool node_is_null (Node node);
	[CCode (cname = "ts_node_is_named")]
	public bool node_is_named (Node node);
	[CCode (cname = "ts_node_is_missing")]
	public bool node_is_missing (Node node);
	[CCode (cname = "ts_node_is_extra")]
	public bool node_is_extra (Node node);
	[CCode (cname = "ts_node_has_changes")]
	public bool node_has_changes (Node node);
	[CCode (cname = "ts_node_has_error")]
	public bool node_has_error (Node node);
	[CCode (cname = "ts_node_parent")]
	public Node node_get_parent (Node node);
	[CCode (cname = "ts_node_child")]
	public Node node_get_child (Node node, uint32 index);
	[CCode (cname = "ts_node_field_name_for_child")]
	public unowned string? node_get_field_name_for_child (Node node, uint32 index);
	[CCode (cname = "ts_node_child_count")]
	public uint32 node_get_child_count (Node node);
	[CCode (cname = "ts_node_named_child")]
	public Node node_get_named_child (Node node, uint32 index);
	[CCode (cname = "ts_node_named_child_count")]
	public uint32 node_get_named_child_count (Node node);
	[CCode (cname = "ts_node_child_by_field_name")]
	public Node node_get_child_by_field_name (Node node, string field_name, uint32 field_name_length);
	[CCode (cname = "ts_node_child_by_field_id")]
	public Node node_get_child_by_field_id (Node node, FieldId field_id);
	[CCode (cname = "ts_node_next_sibling")]
	public Node node_get_next_sibling (Node node);
	[CCode (cname = "ts_node_prev_sibling")]
	public Node node_get_prev_sibling (Node node);
	[CCode (cname = "ts_node_next_named_sibling")]
	public Node node_get_next_named_sibling (Node node);
	[CCode (cname = "ts_node_prev_named_sibling")]
	public Node node_get_prev_named_sibling (Node node);
	[CCode (cname = "ts_node_first_child_for_byte")]
	public Node node_get_first_child_for_byte (Node node, uint32 byte);
	[CCode (cname = "ts_node_first_named_child_for_byte")]
	public Node node_get_first_named_child_for_byte (Node node, uint32 byte);
	[CCode (cname = "ts_node_descendant_for_byte_range")]
	public Node node_get_descendant_for_byte_range (Node node, uint32 start, uint32 end);
	[CCode (cname = "ts_node_descendant_for_point_range")]
	public Node node_get_descendant_for_point_range (Node node, Point start, Point end);
	[CCode (cname = "ts_node_named_descendant_for_byte_range")]
	public Node node_get_named_descendant_for_byte_range (Node node, uint32 start, uint32 end);
	[CCode (cname = "ts_node_named_descendant_for_point_range")]
	public Node node_get_named_descendant_for_point_range (Node node, Point start, Point end);
	[CCode (cname = "ts_node_edit")]
	public void node_edit (ref Node node, InputEdit edit);
	[CCode (cname = "ts_node_eq")]
	public bool node_equals (Node node1, Node node2);

	[CCode (cname = "TSTreeCursor")]
	[SimpleType]
	public struct TreeCursor {
		[CCode (cname = "tree")]
		public void* tree;
		[CCode (cname = "id")]
		public void* id;
		[CCode (cname = "context", array_length = false, array_null_terminated = false)]
		public uint32 context[2];
	}

	/* TreeCursor functions */
	[CCode (cname = "ts_tree_cursor_new")]
	public TreeCursor tree_cursor_new (Node node);
	[CCode (cname = "ts_tree_cursor_delete")]
	public void tree_cursor_delete (TreeCursor* cursor);
	[CCode (cname = "ts_tree_cursor_reset")]
	public void tree_cursor_reset (TreeCursor* cursor, Node node);
	[CCode (cname = "ts_tree_cursor_current_node")]
	public Node tree_cursor_get_current_node (TreeCursor* cursor);
	[CCode (cname = "ts_tree_cursor_current_field_name")]
	public unowned string? tree_cursor_get_current_field_name (TreeCursor* cursor);
	[CCode (cname = "ts_tree_cursor_current_field_id")]
	public FieldId tree_cursor_get_current_field_id (TreeCursor* cursor);
	[CCode (cname = "ts_tree_cursor_goto_parent")]
	public bool tree_cursor_goto_parent (TreeCursor* cursor);
	[CCode (cname = "ts_tree_cursor_goto_next_sibling")]
	public bool tree_cursor_goto_next_sibling (TreeCursor* cursor);
	[CCode (cname = "ts_tree_cursor_goto_first_child")]
	public bool tree_cursor_goto_first_child (TreeCursor* cursor);
	[CCode (cname = "ts_tree_cursor_goto_first_child_for_byte")]
	public int64 tree_cursor_goto_first_child_for_byte (TreeCursor* cursor, uint32 byte);
	[CCode (cname = "ts_tree_cursor_goto_first_child_for_point")]
	public int64 tree_cursor_goto_first_child_for_point (TreeCursor* cursor, Point point);
	[CCode (cname = "ts_tree_cursor_copy")]
	public TreeCursor tree_cursor_copy (TreeCursor* cursor);

	[CCode (cname = "TSQueryCapture")]
	public struct QueryCapture {
		[CCode (cname = "node")]
		public Node node;
		[CCode (cname = "index")]
		public uint32 index;
	}

	[CCode (cname = "TSQuantifier", cprefix = "TSQuantifier")]
	public enum Quantifier {
		ZERO,
		ZERO_OR_ONE,
		ZERO_OR_MORE,
		ONE,
		ONE_OR_MORE
	}

	[CCode (cname = "TSQueryMatch")]
	public struct QueryMatch {
		[CCode (cname = "id")]
		public uint32 id;
		[CCode (cname = "pattern_index")]
		public uint16 pattern_index;
		[CCode (cname = "capture_count")]
		public uint16 capture_count;
		[CCode (cname = "captures", array_length_cname = "capture_count", array_length_type = "uint16_t")]
		public unowned QueryCapture[] captures;
	}

	[CCode (cname = "TSQueryPredicateStepType", cprefix = "TSQueryPredicateStepType")]
	public enum QueryPredicateStepType {
		DONE,
		CAPTURE,
		STRING
	}

	[CCode (cname = "TSQueryPredicateStep")]
	public struct QueryPredicateStep {
		[CCode (cname = "type")]
		public QueryPredicateStepType type;
		[CCode (cname = "value_id")]
		public uint32 value_id;
	}

	[CCode (cname = "TSQueryError", cprefix = "TSQueryError")]
	public enum QueryError {
		NONE,
		SYNTAX,
		NODE_TYPE,
		FIELD,
		CAPTURE,
		STRUCTURE,
		LANGUAGE
	}

	/* Language functions */
	[CCode (cname = "ts_language_symbol_count")]
	public uint32 language_get_symbol_count (Language language);
	[CCode (cname = "ts_language_symbol_name")]
	public unowned string? language_get_symbol_name (Language language, Symbol symbol);
	[CCode (cname = "ts_language_symbol_for_name")]
	public Symbol language_get_symbol_for_name (Language language, string name, uint32 length, bool is_named);
	[CCode (cname = "ts_language_field_count")]
	public uint32 language_get_field_count (Language language);
	[CCode (cname = "ts_language_field_name_for_id")]
	public unowned string? language_get_field_name_for_id (Language language, FieldId field_id);
	[CCode (cname = "ts_language_field_id_for_name")]
	public FieldId language_get_field_id_for_name (Language language, string name, uint32 length);
	[CCode (cname = "ts_language_symbol_type")]
	public SymbolType language_get_symbol_type (Language language, Symbol symbol);
	[CCode (cname = "ts_language_version")]
	public uint32 language_get_version (Language language);

	/* Global configuration */
	[CCode (cname = "ts_set_allocator")]
	public void set_allocator (
		[CCode (type = "void*(*)(size_t)")] void* malloc_func,
		[CCode (type = "void*(*)(size_t, size_t)")] void* calloc_func,
		[CCode (type = "void*(*)(void*, size_t)")] void* realloc_func,
		[CCode (type = "void(*)(void*)")] void* free_func
	);
}

