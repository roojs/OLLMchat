/*
 * Copyright (C) 2026 Alan Knowles <alan@roojs.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 */

namespace Markdown
{
	/**
	 * Base class for marker maps used by the parser.
	 * Holds an instance map and provides generic peek logic for matching
	 * variable-length marker sequences at a given position.
	 */
	public abstract class MarkerMap
	{
		/** Instance map; callers can use formatmap.map.get() and formatmap.map.has_key() directly. */
		public Gee.HashMap<string, FormatType> map { get; set; }

		protected MarkerMap(Gee.HashMap<string, FormatType> map_to_use)
		{
			this.map = map_to_use;
		}

		/**
		 * Core match: determines if characters at a given position match entries in this map.
		 * Uses a loop-based approach to handle variable-length sequences.
		 * Always normalizes digits to "1" for matching (harmless for maps without digit entries).
		 * Subclasses can wrap this with peek() for higher-level behaviour; callers can call eat() directly.
		 *
		 * @param chunk The text chunk to examine
		 * @param chunk_pos The position in the chunk to check
		 * @param is_end_of_chunks If true, markers at the end are treated as definitive
		 * @param matched_type Output parameter for the matched format type (NONE if no match)
		 * @param byte_length Output parameter for the byte length of the match
		 * @return 1-N: Length of the match, 0: No match found, -1: Cannot determine (need more characters)
		 */
		public int eat(
			string chunk,
			int chunk_pos,
			bool is_end_of_chunks,
			out FormatType matched_type,
			out int byte_length
		) {
			matched_type = FormatType.NONE;
			byte_length = 0;

			// Check bounds
			if (chunk_pos >= chunk.length) {
				return 0;
			}

			// Check if single character is in map
			var first_char = chunk.get_char(chunk_pos);
			var single_char = first_char.isdigit() ? "1" : first_char.to_string();
			if (first_char.isalpha() || !map.has_key(single_char)) {
				return 0; // No match
			}

			// Edge case: At end of chunk
			var ch = chunk.get_char(chunk_pos);
			var next_pos = chunk_pos + ch.to_string().length;
			if (next_pos >= chunk.length) {
				// only hit at end of chunk
				matched_type = map.get(single_char);
				if (matched_type == FormatType.INVALID) {
					// INVALID at end of chunk: need more input to resolve (e.g. [ → [?, [??; ~ → ~~)
					if (!is_end_of_chunks) {
						return -1;
					}
					return 0;
				}
				if (!is_end_of_chunks) {
					return -1; // Might be longer match
				}
				byte_length = next_pos - chunk_pos;
				return 1; // Definitive single char match
			}

			// Loop-based sequence matching
			int max_match_length = 0;
			int char_count = 0;
			string sequence = "";
			string wildcard_sequence = "";
 
			for (var cp = chunk_pos; cp < chunk.length; ) {
				var char_at_cp = chunk.get_char(cp);
				var wc_char = char_at_cp.to_string();
				// NOTE done this way as vala frees a?b:c assignemnts whcich borks this loop
				if (char_at_cp.isdigit()) {
					wc_char = "1";
				}
				sequence += wc_char;
				if (char_at_cp.isalpha()) {
					wc_char = "?";
				}
				wildcard_sequence += wc_char;

				cp += char_at_cp.to_string().length;
				char_count++;

				var last_char = char_at_cp;
				if (last_char == '\n') {
					if (max_match_length > 0) {
						return max_match_length;
					}
					return 0;
				}

				if (map.has_key(sequence)) {
					matched_type = map.get(sequence);
					if (matched_type == FormatType.INVALID) {
						continue; // e.g. "[" alone: keep building to try "[a", "[ ]", etc.
					}
					max_match_length = char_count;
					byte_length = cp - chunk_pos;
					continue; // try next char for longer match (e.g. * → ** → ***)
				}
				if (map.has_key(wildcard_sequence)) {
					matched_type = map.get(wildcard_sequence);
					if (matched_type == FormatType.INVALID) {
						continue; // let the loop eat another character
					}
					max_match_length = char_count;
					byte_length = cp - chunk_pos;
					break; // exit loop; end-of-loop returns max_match_length
				}
				// if we have had a match, gone pase and ended up with none
				// we can return it.
				GLib.debug("matched_type=%s max_match_length=%d byte_length=%d",
					matched_type.to_string(), max_match_length, byte_length);
				if (matched_type != FormatType.LINK && matched_type != FormatType.NONE) {
					return max_match_length;
				}
				break; /// we did not get a match..
			}

			// Reached end of chunk (no more characters to eat)
			if (!is_end_of_chunks) {
				// Wildcard INVALID (e.g. "[?") means need more characters to decide
				if (map.has_key(wildcard_sequence) && map.get(wildcard_sequence) == FormatType.INVALID) {
					return -1;
				}
				if (char_count >= 3 && matched_type == FormatType.LINK) {
					return max_match_length;
				}
				if (!map.has_key(wildcard_sequence) &&
					(!map.has_key(sequence) || map.get(sequence) == FormatType.NONE) &&
					matched_type != FormatType.NONE
					) {
				 
					return max_match_length;
				}
				return -1;
			}
			return max_match_length;
		}
	}
}
