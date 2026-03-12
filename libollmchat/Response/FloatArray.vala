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

namespace OLLMchat.Response
{
	/**
	 * Stores multiple vectors in a flat array (row-major).
	 * Used for embedding API responses and batch FAISS operations.
	 * All vectors must have the same width (dimension).
	 */
	public class FloatArray : Object
	{
		/**
		 * Flat array containing all vector data (row-major order).
		 */
		public float[] data;
		/**
		 * Vector dimension (width of each vector).
		 */
		public int width { get; private set; default = 0; }
		/**
		 * Number of vectors stored.
		 */
		public int rows { get; private set; default = 0; }

		/**
		 * @param width The dimension of each vector
		 */
		public FloatArray(int width)
		{
			this.data = {};
			this.width = width;
			 
		}

		/**
		 * Adds a vector to the batch.
		 * @param vector The vector to add (must match width, or sets width if empty)
		 */
		public void add(float[] vector) throws Error
		{
			if (this.width == 0) {
				this.width = vector.length;
			}
			if (vector.length != this.width) {
				throw new GLib.IOError.FAILED(
					"Vector width mismatch: expected " +
					this.width.to_string() +
					", got " +
					vector.length.to_string()
				);
			}
			int current_size = this.data.length;
			this.data.resize(current_size + this.width);
			for (int i = 0; i < this.width; i++) {
				this.data[current_size + i] = vector[i];
			}
			this.rows++;
		}

		/**
		 * Retrieves a vector by index.
		 * @param index The vector index (0-based)
		 * @return The vector as a float array
		 */
		public float[] get_vector(int index) throws Error
		{
			if (index < 0 || index >= this.rows) {
				throw new GLib.IOError.FAILED("Vector index out of range");
			}
			var vector = new float[this.width];
			int offset = index * this.width;
			for (int i = 0; i < this.width; i++) {
				vector[i] = this.data[offset + i];
			}
			return vector;
		}

		/**
		 * L2-normalize the vector at the given index in place.
		 */
		public void normalize_vector_at(int index) throws Error
		{
			if (index < 0 || index >= this.rows) {
				throw new GLib.IOError.FAILED("Vector index out of range");
			}
			int offset = index * this.width;
			double norm_squared = 0.0;
			for (int j = 0; j < this.width; j++) {
				double v = (double)this.data[offset + j];
				norm_squared += v * v;
			}
			double norm = Math.sqrt(norm_squared);
			if (norm <= 0.0) {
				return;
			}
			for (int j = 0; j < this.width; j++) {
				this.data[offset + j] = (float)((double)this.data[offset + j] / norm);
			}
		}
	}
}
