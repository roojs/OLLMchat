/*
 * Copyright (C) 2025 Alan Knowles <alan@roojs.com>
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
 *
 * This code implements the Myers diff algorithm based on diffseq.h from GNU diffutils.
 * The core algorithm (compareseq, diag) is ported from GNU diffutils diffseq.h.
 * Additional functions (shift_boundaries, build_script) are based on GNU diff's analyze.c.
 */

namespace OLLMfiles.Diff
{
	// Internal edit operation types
	private enum EditOp
	{
		DELETE,
		INSERT,
		EQUAL
	}
	
	// Internal edit operation
	private class Edit : Object
	{
		public EditOp op;
		public int line_index1;  // Index in lines1 array
		public int line_index2;  // Index in lines2 array
		public string? line;     // The line content (null for EQUAL)
		
		public Edit(EditOp op, int idx1, int idx2, string? line = null)
		{
			this.op = op;
			this.line_index1 = idx1;
			this.line_index2 = idx2;
			this.line = line;
		}
	}
	
	/**
	 * Simple line-based diff implementation using Myers algorithm.
	 * 
	 * Computes the differences between two texts and returns
	 * a list of patches with line numbers.
	 * 
	 * Implementation based on diffseq.h from GNU diffutils.
	 */
	public class Differ : Object
	{
		private string[] lines1;
		private string[] lines2;
		private Gee.ArrayList<Edit> edits = new Gee.ArrayList<Edit>();
		private int prefix_len = 0;
		private int suffix_len = 0;
		
		/**
		 * Read-only access to the computed patches.
		 * 
		 * This property is updated whenever {@link diff} is called.
		 */
		public Gee.ArrayList<Patch> patches { get; private set; default = new Gee.ArrayList<Patch>(); }
		
		/**
		 * Constructor that takes two texts and converts them to lines.
		 * 
		 * @param text1 Original text
		 * @param text2 Modified text
		 */
		public Differ(string text1, string text2)
		{
			this.lines1 = text1.split("\n");
			this.lines2 = text2.split("\n");
		}
		
		/**
		 * Update the first text (text1) and recompute lines.
		 * 
		 * @param text1 New original text
		 */
		public void diff_update1(string text1)
		{
			this.lines1 = text1.split("\n");
		}
		
		/**
		 * Update the second text (text2) and recompute lines.
		 * 
		 * @param text2 New modified text
		 */
		public void diff_update2(string text2)
		{
			this.lines2 = text2.split("\n");
		}
		
		/**
		 * Compute diff and return patches.
		 * 
		 * The computed patches are also available via the {@link patches} property.
		 * 
		 * @return List of patches with line numbers
		 */
		public Gee.ArrayList<Patch> diff()
		{
			this.patches.clear();
			this.edits.clear();
			
			if (this.lines1.length == 0 && this.lines2.length == 0) {
				return this.patches;
			}
			
			if (this.lines1.length == 0) {
				this.patches.add(new Patch(
					PatchOperation.ADD,
					1, 0,
					1, this.lines2.length,
					this.lines1,
					this.lines2
				));
				return this.patches;
			}
			
			if (this.lines2.length == 0) {
				this.patches.add(new Patch(
					PatchOperation.REMOVE,
					1, this.lines1.length,
					1, 0,
					this.lines1,
					this.lines2
				));
				return this.patches;
			}
			
			this.prefix_len = this.common_prefix();
			this.suffix_len = this.common_suffix(this.prefix_len);
			var mid1_start = this.prefix_len;
			var mid1_end = this.lines1.length - this.suffix_len;
			var mid2_start = this.prefix_len;
			var mid2_end = this.lines2.length - this.suffix_len;
			
			var mid1 = new string[mid1_end - mid1_start];
			var mid2 = new string[mid2_end - mid2_start];
			for (var i = 0; i < mid1.length; i++) {
				mid1[i] = this.lines1[mid1_start + i];
			}
			for (var i = 0; i < mid2.length; i++) {
				mid2[i] = this.lines2[mid2_start + i];
			}
			
			if (!this.compute_diff(mid1, mid2, mid1_start, mid2_start)) {
				this.edits_to_patches(mid1_start, mid2_start);
			}
			
			return this.patches;
		}
		
		/**
		 * Find common prefix length (number of matching lines at start).
		 */
		private int common_prefix()
		{
			for (var i = 0; i < int.min(this.lines1.length, this.lines2.length); i++) {
				if (this.lines1[i] != this.lines2[i]) {
					return i;
				}
			}
			return int.min(this.lines1.length, this.lines2.length);
		}
		
		/**
		 * Find common suffix length (number of matching lines at end).
		 * 
		 * @param prefix_len Already matched prefix length to avoid overlap
		 */
		private int common_suffix(int prefix_len)
		{
			var max_suffix = int.min(this.lines1.length - prefix_len, this.lines2.length - prefix_len);
			for (var i = 0; i < max_suffix; i++) {
				if (this.lines1.length - 1 - i < prefix_len || this.lines2.length - 1 - i < prefix_len) {
					break;
				}
				if (this.lines1[this.lines1.length - 1 - i] != this.lines2[this.lines2.length - 1 - i]) {
					return i;
				}
			}
			return max_suffix;
		}
		
		/**
		 * Compute diff between two line arrays.
		 * 
		 * Handles trivial cases and delegates to appropriate algorithm.
		 * 
		 * @param lines1 First array of lines
		 * @param lines2 Second array of lines
		 * @param line_offset1 Line offset for patches in lines1
		 * @param line_offset2 Line offset for patches in lines2
		 * @return true if patches were already created, false if edits need to be converted to patches
		 */
		private bool compute_diff(string[] lines1, string[] lines2, int line_offset1, int line_offset2)
		{
			if (lines1.length == 0) {
				this.patches.add(new Patch(
					PatchOperation.ADD,
					line_offset1 + 1, line_offset1,
					line_offset2 + 1, line_offset2 + lines2.length,
					this.lines1,
					this.lines2
				));
				return true;
			}
			
			if (lines2.length == 0) {
				this.patches.add(new Patch(
					PatchOperation.REMOVE,
					line_offset1 + 1, line_offset1 + lines1.length,
					line_offset2 + 1, line_offset2,
					this.lines1,
					this.lines2
				));
				return true;
			}
			
			if (lines1.length + lines2.length > 10000) {
				this.simple_diff(lines1, lines2);
				return false;
			}
			
			this.myers_diff(lines1, lines2);
			return false;
		}
		
		private class CompareContext : Object
		{
			public string[] xvec;
			public string[] yvec;
			public bool[] changed1;
			public bool[] changed2;
			public int[] fdiag;
			public int[] bdiag;
			public bool heuristic;
			public int too_expensive;
			
			public CompareContext(string[] xvec, string[] yvec, ref bool[] changed1, ref bool[] changed2, int diags)
			{
				this.xvec = xvec;
				this.yvec = yvec;
				this.changed1 = changed1;
				this.changed2 = changed2;
				this.fdiag = new int[diags];
				this.bdiag = new int[diags];
				this.heuristic = false;
				var log2 = 0;
				var n = diags;
				while (n > 1) {
					log2++;
					n >>= 1;
				}
				this.too_expensive = int.max(4096, 1 << ((log2 >> 1) + 1));
			}
		}
		
		private class Partition : Object
		{
			public int xmid;
			public int ymid;
			public bool lo_minimal;
			public bool hi_minimal;
		}
		
		/**
		 * Myers algorithm using recursive divide-and-conquer.
		 * 
		 * Implementation based on diffseq.h compareseq function.
		 */
		private void myers_diff(string[] lines1, string[] lines2)
		{
			var m = lines1.length;
			var n = lines2.length;
			
			var changed1 = new bool[m + 1];
			var changed2 = new bool[n + 1];
			changed1[0] = false;
			changed2[0] = false;
			
			var ctxt = new CompareContext(lines1, lines2, ref changed1, ref changed2, (m + n) * 2 + (n + 1) * 2 + 10);
			
			this.compareseq(0, m, 0, n, true, ctxt);
			
			changed1 = ctxt.changed1;
			changed2 = ctxt.changed2;
			
			this.shift_boundaries(changed1, changed2, lines1, lines2);
			
			this.build_script(changed1, changed2, lines1, lines2);
		}
		
		/**
		 * Compare in detail contiguous subsequences of the two vectors.
		 * 
		 * Implementation based on diffseq.h compareseq function.
		 */
		private void compareseq(int xoff, int xlim, int yoff, int ylim, bool find_minimal, CompareContext ctxt)
		{
			while (true) {
				while (xoff < xlim && yoff < ylim && ctxt.xvec[xoff] == ctxt.yvec[yoff]) {
					xoff++;
					yoff++;
				}
				
				while (xoff < xlim && yoff < ylim && ctxt.xvec[xlim - 1] == ctxt.yvec[ylim - 1]) {
					xlim--;
					ylim--;
				}
				
				if (xoff == xlim) {
					while (yoff < ylim) {
						if (yoff + 1 < ctxt.changed2.length) {
							ctxt.changed2[yoff + 1] = true;
						}
						yoff++;
					}
					break;
				}
				
				if (yoff == ylim) {
					while (xoff < xlim) {
						if (xoff + 1 < ctxt.changed1.length) {
							ctxt.changed1[xoff + 1] = true;
						}
						xoff++;
					}
					break;
				}
				
				var part = new Partition();
				this.diag(xoff, xlim, yoff, ylim, find_minimal, part, ctxt);
				
				int xoff1, xlim1, yoff1, ylim1, xoff2, xlim2, yoff2, ylim2;
				bool find_minimal1, find_minimal2;
				
				if ((xlim + ylim) - (part.xmid + part.ymid) < (part.xmid + part.ymid) - (xoff + yoff)) {
					xoff1 = part.xmid;
					xlim1 = xlim;
					yoff1 = part.ymid;
					ylim1 = ylim;
					find_minimal1 = part.hi_minimal;
					
					xoff2 = xoff;
					xlim2 = part.xmid;
					yoff2 = yoff;
					ylim2 = part.ymid;
					find_minimal2 = part.lo_minimal;
				} else {
					xoff1 = xoff;
					xlim1 = part.xmid;
					yoff1 = yoff;
					ylim1 = part.ymid;
					find_minimal1 = part.lo_minimal;
					
					xoff2 = part.xmid;
					xlim2 = xlim;
					yoff2 = part.ymid;
					ylim2 = ylim;
					find_minimal2 = part.hi_minimal;
				}
				
				this.compareseq(xoff1, xlim1, yoff1, ylim1, find_minimal1, ctxt);
				
				xoff = xoff2;
				xlim = xlim2;
				yoff = yoff2;
				ylim = ylim2;
				find_minimal = find_minimal2;
			}
		}
		
		private void diag(int xoff, int xlim, int yoff, int ylim, bool find_minimal, Partition part, CompareContext ctxt)
		{
			var fd = ctxt.fdiag;
			var bd = ctxt.bdiag;
			var xv = ctxt.xvec;
			var yv = ctxt.yvec;
			
			var dmin = xoff - ylim;
			var dmax = xlim - yoff;
			var fmid = xoff - yoff;
			var bmid = xlim - ylim;
			var fmin = fmid;
			var fmax = fmid;
			var bmin = bmid;
			var bmax = bmid;
			var odd = ((fmid - bmid) & 1) != 0;
			
			var fdiag_offset = ctxt.yvec.length + 1;
			var bdiag_offset = ctxt.yvec.length + 1;
			
			if (fmid + fdiag_offset < 0 || fmid + fdiag_offset >= ctxt.fdiag.length) {
				part.xmid = (xoff + xlim) / 2;
				part.ymid = (yoff + ylim) / 2;
				part.lo_minimal = false;
				part.hi_minimal = false;
				return;
			}
			if (bmid + bdiag_offset < 0 || bmid + bdiag_offset >= ctxt.bdiag.length) {
				part.xmid = (xoff + xlim) / 2;
				part.ymid = (yoff + ylim) / 2;
				part.lo_minimal = false;
				part.hi_minimal = false;
				return;
			}
			
			fd[fmid + fdiag_offset] = xoff;
			bd[bmid + bdiag_offset] = xlim;
			
			const int SNAKE_LIMIT = 20;
			const int OFFSET_MAX = 2147483647;
			
			var c = 1;
			while (true) {
				var big_snake = false;
				
				if (fmin > dmin) {
					fd[--fmin + fdiag_offset - 1] = -1;
				} else {
					fmin++;
				}
				if (fmax < dmax) {
					fd[++fmax + fdiag_offset + 1] = -1;
				} else {
					fmax--;
				}
				
				for (var d = fmax; d >= fmin; d -= 2) {
					var tlo = fd[d + fdiag_offset - 1];
					var thi = fd[d + fdiag_offset + 1];
					var x0 = tlo < thi ? thi : tlo + 1;
					
					var x = x0;
					var y = x0 - d;
					while (x < xlim && y < ylim && xv[x] == yv[y]) {
						x++;
						y++;
					}
					if (x - x0 > SNAKE_LIMIT) {
						big_snake = true;
					}
					fd[d + fdiag_offset] = x;
					if (odd && bmin <= d && d <= bmax && bd[d + bdiag_offset] <= x) {
						part.xmid = x;
						part.ymid = y;
						part.lo_minimal = true;
						part.hi_minimal = true;
						return;
					}
				}
				
				if (bmin > dmin) {
					bd[--bmin + bdiag_offset - 1] = OFFSET_MAX;
				} else {
					bmin++;
				}
				if (bmax < dmax) {
					bd[++bmax + bdiag_offset + 1] = OFFSET_MAX;
				} else {
					bmax--;
				}
				
				for (var d = bmax; d >= bmin; d -= 2) {
					var tlo = bd[d + bdiag_offset - 1];
					var thi = bd[d + bdiag_offset + 1];
					var x0 = tlo < thi ? tlo : thi - 1;
					
					var x = x0;
					var y = x0 - d;
					while (xoff < x && yoff < y && xv[x - 1] == yv[y - 1]) {
						x--;
						y--;
					}
					if (x0 - x > SNAKE_LIMIT) {
						big_snake = true;
					}
					bd[d + bdiag_offset] = x;
					if (!odd && fmin <= d && d <= fmax && x <= fd[d + fdiag_offset]) {
						part.xmid = x;
						part.ymid = y;
						part.lo_minimal = true;
						part.hi_minimal = true;
						return;
					}
				}
				
				if (find_minimal) {
					c++;
					continue;
				}
				
				if (200 < c && big_snake && ctxt.heuristic) {
					var best = 0;
					var best_xmid = 0;
					var best_ymid = 0;
					
					for (var d = fmax; d >= fmin; d -= 2) {
						var dd = d - fmid;
						var x = fd[d + fdiag_offset];
						var y = x - d;
						var v = (x - xoff) * 2 - dd;
						
						if (v > 12 * (c + (dd < 0 ? -dd : dd))) {
							if (v > best && xoff + SNAKE_LIMIT <= x && x < xlim && yoff + SNAKE_LIMIT <= y && y < ylim) {
								var k = 1;
								while (k < SNAKE_LIMIT && x - k >= 0 && y - k >= 0 && xv[x - k] == yv[y - k]) {
									k++;
								}
								if (k == SNAKE_LIMIT) {
									best = v;
									best_xmid = x;
									best_ymid = y;
								}
							}
						}
					}
					
					if (best > 0) {
						part.xmid = best_xmid;
						part.ymid = best_ymid;
						part.lo_minimal = true;
						part.hi_minimal = false;
						return;
					}
					
					best = 0;
					for (var d = bmax; d >= bmin; d -= 2) {
						var dd = d - bmid;
						var x = bd[d + bdiag_offset];
						var y = x - d;
						var v = (xlim - x) * 2 + dd;
						
						if (v > 12 * (c + (dd < 0 ? -dd : dd))) {
							if (v > best && xoff < x && x <= xlim - SNAKE_LIMIT && yoff < y && y <= ylim - SNAKE_LIMIT) {
								var k = 0;
								while (k < SNAKE_LIMIT - 1 && x + k < xlim && y + k < ylim && xv[x + k] == yv[y + k]) {
									k++;
								}
								if (k == SNAKE_LIMIT - 1) {
									best = v;
									best_xmid = x;
									best_ymid = y;
								}
							}
						}
					}
					
					if (best > 0) {
						part.xmid = best_xmid;
						part.ymid = best_ymid;
						part.lo_minimal = false;
						part.hi_minimal = true;
						return;
					}
				}
				
				if (c >= ctxt.too_expensive) {
					var fxybest = -1;
					var fxbest = 0;
					for (var d = fmax; d >= fmin; d -= 2) {
						var x = int.min(fd[d + fdiag_offset], xlim);
						var y = x - d;
						if (ylim < y) {
							x = ylim + d;
							y = ylim;
						}
						if (fxybest < x + y) {
							fxybest = x + y;
							fxbest = x;
						}
					}
					
					var bxybest = OFFSET_MAX;
					var bxbest = 0;
					for (var d = bmax; d >= bmin; d -= 2) {
						var x = int.max(xoff, bd[d + bdiag_offset]);
						var y = x - d;
						if (y < yoff) {
							x = yoff + d;
							y = yoff;
						}
						if (x + y < bxybest) {
							bxybest = x + y;
							bxbest = x;
						}
					}
					
					if ((xlim + ylim) - bxybest < fxybest - (xoff + yoff)) {
						part.xmid = fxbest;
						part.ymid = fxybest - fxbest;
						part.lo_minimal = true;
						part.hi_minimal = false;
					} else {
						part.xmid = bxbest;
						part.ymid = bxybest - bxbest;
						part.lo_minimal = false;
						part.hi_minimal = true;
					}
					return;
				}
				
				c++;
			}
		}
		
		/**
		 * Shift boundaries to join changes as much as possible.
		 * 
		 * Implementation based on GNU diff's shift_boundaries function.
		 */
		private void shift_boundaries(bool[] changed1, bool[] changed2, string[] lines1, string[] lines2)
		{
			for (var f = 0; f < 2; f++) {
				var changed = f == 0 ? changed1 : changed2;
				var other_changed = f == 0 ? changed2 : changed1;
				var lines = f == 0 ? lines1 : lines2;
				var other_lines = f == 0 ? lines2 : lines1;
				var i = 0;
				var j = 0;
				var i_end = lines.length;
				
				while (true) {
					while (i < i_end && !changed[i + 1]) {
						while (other_changed[j + 1]) {
							j++;
						}
						i++;
						j++;
					}
					
					if (i >= i_end) {
						break;
					}
					
					var start = i;
					
					while (i < i_end && changed[i + 1]) {
						i++;
					}
					while (j < other_lines.length && other_changed[j + 1]) {
						j++;
					}
					
					var runlength = i - start;
					var corresponding = i_end;
					
					do {
						runlength = i - start;
						
						while (start > 0 && lines[start - 1] == lines[i - 1]) {
							changed[start] = true;
							changed[i] = false;
							start--;
							i--;
							while (start > 0 && changed[start]) {
								start--;
							}
							while (j > 0 && other_changed[j]) {
								j--;
							}
						}
						
						corresponding = (j > 0 && other_changed[j]) ? i : i_end;
						
						while (i < i_end && lines[start] == lines[i]) {
							changed[start] = false;
							changed[i + 1] = true;
							start++;
							i++;
							while (i < i_end && changed[i + 1]) {
								i++;
							}
							while (j < other_lines.length && other_changed[j + 1]) {
								j++;
								corresponding = i;
							}
						}
					} while (runlength != i - start);
					
					while (corresponding < i) {
						changed[start] = true;
						changed[i] = false;
						start--;
						i--;
						while (j > 0 && other_changed[j]) {
							j--;
						}
					}
				}
			}
		}
		
		/**
		 * Build change script from changed arrays.
		 * 
		 * Implementation based on GNU diff's build_script function.
		 */
		private void build_script(bool[] changed1, bool[] changed2, string[] lines1, string[] lines2)
		{
			var i0 = lines1.length;
			var i1 = lines2.length;
			
			while (i0 >= 0 || i1 >= 0) {
				if ((i0 > 0 && changed1[i0]) || (i1 > 0 && changed2[i1])) {
					var line0 = i0;
					var line1 = i1;
					
					while (i0 > 0 && changed1[i0]) {
						i0--;
					}
					while (i1 > 0 && changed2[i1]) {
						i1--;
					}
					
					for (var j = i0 + 1; j <= line0; j++) {
						var line_idx = j - 1;
						if (line_idx >= 0 && line_idx < lines1.length) {
							this.edits.insert(0, new Edit(EditOp.DELETE, line_idx, -1, lines1[line_idx]));
						}
					}
					for (var j = i1 + 1; j <= line1; j++) {
						var line_idx = j - 1;
						if (line_idx >= 0 && line_idx < lines2.length) {
							this.edits.insert(0, new Edit(EditOp.INSERT, -1, line_idx, lines2[line_idx]));
						}
					}
				}
				
				if (i0 > 0 && i1 > 0) {
					this.edits.insert(0, new Edit(EditOp.EQUAL, i0 - 1, i1 - 1, null));
				}
				
				i0--;
				i1--;
			}
		}
		
		/**
		 * Simple diff for very large files - just compare line by line.
		 */
		private void simple_diff(string[] lines1, string[] lines2)
		{
			var i = 0;
			var j = 0;
			
			while (i < lines1.length || j < lines2.length) {
				if (i < lines1.length && j < lines2.length && lines1[i] == lines2[j]) {
					this.edits.add(new Edit(EditOp.EQUAL, i, j, null));
					i++;
					j++;
					continue;
				}
				
				if (j < lines2.length && (i >= lines1.length || lines1[i] != lines2[j])) {
					this.edits.add(new Edit(EditOp.INSERT, -1, j, lines2[j]));
					j++;
					continue;
				}
				
				if (i < lines1.length) {
					this.edits.add(new Edit(EditOp.DELETE, i, -1, lines1[i]));
					i++;
				}
			}
		}
		
		/**
		 * Convert edit operations to Patch objects.
		 * 
		 * Groups consecutive operations and creates appropriate patch types.
		 */
		private void edits_to_patches(int line_offset1, int line_offset2)
		{
			if (this.edits.size == 0) {
				return;
			}
			
			var pos1 = 0;
			var pos2 = 0;
			var i = 0;
			
			while (i < this.edits.size) {
				if (this.edits.get(i).op == EditOp.EQUAL) {
					pos1++;
					pos2++;
					i++;
					continue;
				}
				
				var delete_start_pos = pos1;
				var delete_count = 0;
				var insert_start_pos = pos2;
				var insert_count = 0;
				
				while (i < this.edits.size && this.edits.get(i).op != EditOp.EQUAL) {
					if (this.edits.get(i).op == EditOp.DELETE) {
						if (delete_count == 0) {
							delete_start_pos = pos1;
						}
						delete_count++;
						pos1++;
						i++;
						continue;
					}
					
					if (this.edits.get(i).op == EditOp.INSERT) {
						if (insert_count == 0) {
							insert_start_pos = pos2;
						}
						insert_count++;
						pos2++;
						i++;
					}
				}
				
				if (delete_count > 0 && insert_count > 0) {
					this.patches.add(new Patch(
						PatchOperation.REPLACE,
						line_offset1 + delete_start_pos + 1,
						line_offset1 + delete_start_pos + delete_count,
						line_offset2 + insert_start_pos + 1,
						line_offset2 + insert_start_pos + insert_count,
						this.lines1,
						this.lines2
					));
					continue;
				}
				
				if (delete_count > 0) {
					this.patches.add(new Patch(
						PatchOperation.REMOVE,
						line_offset1 + delete_start_pos + 1,
						line_offset1 + delete_start_pos + delete_count,
						line_offset1 + delete_start_pos + 1,
						line_offset1 + delete_start_pos,
						this.lines1,
						this.lines2
					));
					continue;
				}
				
				if (insert_count > 0) {
					this.patches.add(new Patch(
						PatchOperation.ADD,
						line_offset1 + delete_start_pos + 1,
						line_offset1 + delete_start_pos,
						line_offset2 + insert_start_pos + 1,
						line_offset2 + insert_start_pos + insert_count,
						this.lines1,
						this.lines2
					));
				}
			}
		}
	}
}

