// Vala codegen bug: nested ternary can free temp before g_strdup() → use-after-free. Use explicit if/else.
void main() {
	string instr = "[1]";
	string s = "";
	for (var i = 0; i < instr.length; ) {
		var c = instr.get_char(i);
		var w = 
			c.isalpha() ? "?" : (c.isdigit() ? "1" : c.to_string());  // BUG: wrong len/content
		stdout.printf("ADD %s or %s\n", c.to_string(),  w.to_string());
		s += w;
		i += c.to_string().length;
	}
	stdout.printf("nested ternary: s=%s len=%d (expected [1] len=3)\n", s, (int)s.length);
}
