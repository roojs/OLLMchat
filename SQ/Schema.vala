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
 */

/**
 * Simple SQL builder for GObject values.
 * 
 * This namespace provides a lightweight SQL query builder and database
 * management system for working with GObject-based types and SQLite databases.
 */
namespace SQ {

	/**
	 * Represents the schema information for a database table column.
	 * 
	 * This class is used to store and retrieve column metadata from SQLite
	 * tables, including column name, type, constraints, and default values.
	 * It also provides caching functionality to avoid repeated schema queries.
	 */
	public class Schema : Object
	{
		/**
		 * The database instance used for schema queries.
		 */
		private Database db;
		
		/**
		 * Creates a new Schema instance.
		 * 
		 * @param db The database instance to use for schema queries
		 */
		public Schema(Database db)
		{
			this.db = db;
		}
		
		/**
		 * Loads the schema information for a table.
		 * 
		 * This method queries SQLite's PRAGMA table_info to retrieve column
		 * information for the specified table. Results are cached to avoid
		 * repeated queries for the same table.
		 * 
		 * @param name The name of the table to load schema for
		 * @return A list of Schema objects representing each column in the table
		 */
		public Gee.ArrayList<Schema> load(string name) {
			if (db.schema_cache.has_key(name)) {
				return db.schema_cache.get(name);
			}
			
			var sq = new Query<Schema>(this.db, "");
			var ret = new Gee.ArrayList<Schema>();
			sq.selectQuery("PRAGMA table_info('" + name + "')", ret);
			
			db.schema_cache.set(name, ret);
			return ret;
		}
		
		/**
		 * The column ID (ordinal position) in the table.
		 */
		public int cid { get; set; default = -1 ;}
		
		/**
		 * The name of the column.
		 */
		public string name  { get; set; default = ""; }
		
		/**
		 * The SQLite type of the column (e.g., "INTEGER", "TEXT", "INT64").
		 */
		public string ctype  { get; set; default = "" ;}
		
		/**
		 * Whether the column has a NOT NULL constraint.
		 */
		public bool notnull  { get; set; default = false; }
		
		/**
		 * The default value for the column as a string.
		 */
		public string dflt_value  { get; set; default = "" ;}
		
		/**
		 * Whether this column is part of the primary key.
		 */
		public bool pk  { get; set; default = false; }

		
		
	}
}
		