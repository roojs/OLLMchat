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
	 * A generic SQL query builder for GObject-based types.
	 * 
	 * This class provides type-safe CRUD operations for GObject instances,
	 * automatically mapping object properties to database columns. It supports
	 * INSERT, UPDATE, SELECT, and DELETE operations with automatic type
	 * conversion between GObject property types and SQLite column types.
	 * 
	 * Supported GObject property types:
	 * - boolean (maps to INTEGER 0/1)
	 * - int (maps to INTEGER)
	 * - int64 (maps to INT64)
	 * - string (maps to TEXT)
	 * - enum (maps to INTEGER)
	 * 
	 * **Important:** SQ.Query only works with GObject properties. When deserializing
	 * from the database (SELECT operations), all properties found in the result set
	 * will be set on the object. If a property is read-only (`get;` only), GObject
	 * will throw an error when attempting to set it. Therefore, properties that appear
	 * in SELECT queries must be settable (`get; set;`).
	 * 
	 * @param T The GObject type to work with
	 */
	public class Query < T > {
	
		/**
		 * The name of the database table this query operates on.
		 */
		string table;
		
		/**
		 * The database instance to use for queries.
		 */
		Database db;
		
		/**
		 * Property names to pass to Object.new_with_properties when constructing objects.
		 */
		string[]? property_names = null;
		
		/**
		 * Property values to pass to Object.new_with_properties when constructing objects.
		 */
		Value[]? property_values = null;
		
		/**
		 * Typemap for polymorphic deserialization.
		 * 
		 * Maps type identifier strings (e.g., "p", "f", "d") to GObject types.
		 * This allows Query to instantiate the correct subclass when deserializing
		 * from a database table that stores multiple types in a single table.
		 * 
		 * **Why this is needed:**
		 * 
		 * When you have a base class (e.g., `FileBase`) with multiple subclasses
		 * (e.g., `File`, `Folder`, `Project`), and all are stored in the same database
		 * table, SQLite can only return generic rows. Without type information, you
		 * cannot know which subclass to instantiate when deserializing.
		 * 
		 * **How it works:**
		 * 
		 * 1. The database table must include a column (specified by `typekey`) that
		 * stores a type identifier string (e.g., "p" for Project, "f" for File, "d" for Folder).
		 * 
		 * 2. Before executing a query, you populate `typemap` with mappings from these
		 * identifier strings to the actual GObject types.
		 * 
		 * 3. When `selectExecute` processes each row, it reads the type identifier
		 * from the `typekey` column, looks it up in `typemap`, and instantiates
		 * the correct subclass instead of the base class.
		 * 
		 * **Example:**
		 * 
		 * {{{
		 * // Database table: files
		 * // Columns: id, path, parent_id, base_type, ...
		 * // base_type column contains: "p", "f", or "d"
		 * 
		 * var query = new SQ.Query<FileBase>(db, "files");
		 * 
		 * // Set up polymorphic type mapping
		 * query.typemap = new Gee.HashMap<string, Type>();
		 * query.typemap["p"] = typeof(Project);
		 * query.typemap["f"] = typeof(File);
		 * query.typemap["d"] = typeof(Folder);
		 * query.typekey = "base_type";  // Column name containing type identifier
		 * 
		 * // Now when you query, each row will be instantiated as the correct subclass
		 * var results = new Gee.ArrayList<FileBase>();
		 * query.select("parent_id = ?", results);
		 * // Results will contain Project, File, and Folder instances as appropriate
		 * }}}
		 * 
		 * **Important:**
		 * 
		 * - The `typekey` column must exist in the SELECT query results
		 * - The type identifier values in the database must match the keys in `typemap`
		 * - If a type identifier is not found in `typemap`, the base type `T` will be used
		 * - This only affects object instantiation; property mapping works the same way
		 */
		public Gee.HashMap<string, Type>? typemap = null;
		
		/**
		 * Column name that contains the type identifier for polymorphic deserialization.
		 * 
		 * This should be set to the name of the database column that stores the type
		 * identifier string (e.g., "base_type", "type", "class_type").
		 * 
		 * The column must be included in the SELECT query results for polymorphic
		 * deserialization to work. The value in this column will be looked up in
		 * `typemap` to determine which GObject type to instantiate.
		 * 
		 * See `typemap` documentation for a complete example.
		 */
		public string? typekey = null;
		  
		/**
		 * Creates a new Query instance for the specified table.
		 * 
		 * @param db The database instance to use
		 * @param table The name of the table to query
		 */
		public Query(Database db, string table) 
		{
			this.db = db;
			this.table = table;
		}
		
		/**
		 * Creates a new Query instance with property initialization.
		 * 
		 * Properties specified here will be set on objects when they are constructed
		 * from database rows using Object.new_with_properties.
		 * 
		 * @param db The database instance to use
		 * @param table The name of the table to query
		 * @param names Array of property names to set on constructed objects
		 * @param values Array of property values (must match names array length)
		 */
		public Query.with_properties(Database db, string table, string[] names, Value[] values)
		{
			this.db = db;
			this.table = table;
			this.property_names = names;
			this.property_values = values;
		}
		
		/**
		 * Inserts a new object into the database table.
		 * 
		 * This method automatically extracts all properties from the object
		 * (except 'id') and inserts them into the table. After insertion,
		 * the object's 'id' property is set to the newly generated row ID.
		 * 
		 * @param newer The object to insert
		 * @return The ID of the newly inserted row
		 */
		public int64 insert(T newer)
		{	
		 	assert(this.table != "");
			assert (typeof(T).is_object());
			var schema = new Schema(this.db);
			var sc = schema.load(this.table);			
			
			string[] keys = {};
			string[] values = {};
 
			foreach(var s in sc) {
				if (s.name == "id" ){
					continue;
				}

				keys +=  s.name;
				values += "$" + s.name;				
				 
			}
			
			Sqlite.Statement stmt;
			 
			
			var q = "INSERT INTO " + this.table + " ( " +
				string.joinv(",", keys) + " ) VALUES ( " + 
				string.joinv(",", values) +   " );";
			
			//GLib.debug("Query %s", q);
			this.db.db.prepare_v2 (q, q.length, out stmt);
			

			foreach(var s in sc) {
				if (s.name == "id" ){
					continue;
				}
				// Convert column name to property name (underscores to hyphens for GObject)
				var prop_name = s.name.replace("_", "-");
				Type value_type;
				if (!this.has_property(prop_name, out value_type)) {
					continue;
				}
				switch(s.ctype) {
					case "INTEGER":
					case "INT2":
						stmt.bind_int (stmt.bind_parameter_index ("$"+ s.name), this.getInt(newer, prop_name, value_type));
					 	break;
					case "INT64":
						// might be better to have getInt64
						stmt.bind_int64 (stmt.bind_parameter_index ("$"+ s.name), (int64) this.getInt(newer, prop_name, value_type));
					 	break;
					case "TEXT":
						stmt.bind_text (stmt.bind_parameter_index ("$"+ s.name), this.getText(newer, prop_name, value_type));
						break;
					default:
					    GLib.error("Column %s : %s has Unhandled SQlite type : %s", 
					    		this.table, s.name,  s.ctype);
				}
				 			
				 
			}
 
			if (Sqlite.DONE != stmt.step ()) {
			    GLib.debug("SYmbol insert: %s", this.db.db.errmsg());
			}
			//GLib.debug("Execute %s", stmt.expanded_sql());	 
			
			stmt.reset(); //not really needed.
			var id = this.db.db.last_insert_rowid();
			var  newv = GLib.Value ( typeof(int64) );
			newv.set_int64(id);
			((Object)newer).set_property("id", newv);
			//GLib.debug("got id=%d", (int)id);
			return id;

		}
		
		/**
		 * Updates an existing object in the database, only changing modified fields.
		 * 
		 * This method compares the old and new objects and only updates columns
		 * where values have changed. The 'id' property from the old object (or
		 * newer if old is null) is used to identify the row to update.
		 * 
		 * @param old The original object (can be null, in which case newer.id is used)
		 * @param newer The updated object with new values
		 */
		public void updateOld(T old, T newer)
		{
			assert(this.table != "");
			var schema = new Schema(this.db);
			var sc = schema.load(this.table);
						   
			string[] setter = {};
			var types = new Gee.HashMap<string,string> ();
			foreach(var s in sc) {
				if (s.name == "id" ){
					continue;
				}
				// Convert column name to property name (underscores to hyphens for GObject)
				var prop_name = s.name.replace("_", "-");
				Type value_type;
				if (!this.has_property(prop_name, out value_type)) {
					continue;
				}
				
				if (old ==null || !this.compareProperty(old, newer, prop_name, value_type)) {
					setter += (s.name +  " = $" + s.name);
					types.set(s.name,s.ctype);
				}
			}
			if (setter.length < 1) {
				return;
			}

			Type id_type;
			if (!this.has_property("id", out id_type)) {
				GLib.error("Property 'id' not found on object");
			}
			var id = this.getInt(old == null ? newer : old, "id", id_type);
				
			this.updateImp(newer, types, setter, id);
			
				
		}
		
		/**
		 * Updates an existing object in the database by ID.
		 * 
		 * This method updates all columns (except 'id') for the row identified
		 * by the object's 'id' property. All fields are updated regardless of
		 * whether they've changed.
		 * 
		 * @param newer The object to update (must have a valid 'id' property)
		 */
		public void updateById(T newer)
		{
			assert(this.table != "");
			var schema = new Schema(this.db);
			var sc = schema.load(this.table);
						   
			string[] setter = {};
			var types = new Gee.HashMap<string,string> ();
			foreach(var s in sc) {
				if (s.name == "id" ){
					continue;
				}
				// Convert column name to property name (underscores to hyphens for GObject)
				var prop_name = s.name.replace("_", "-");
				Type value_type;
				if (!this.has_property(prop_name, out value_type)) {
					continue;
				}
				
				 
				setter += (s.name +  " = $" + s.name);
				types.set(s.name,s.ctype);
				
			}
			if (setter.length < 1) {
				return;
			}

			Type id_type;
			if (!this.has_property("id", out id_type)) {
				GLib.error("Property 'id' not found on object");
			}
			var id = this.getInt(newer, "id", id_type);
			this.updateImp(newer, types, setter, id);
		}
		
		/**
		 * Internal implementation of the UPDATE operation.
		 * 
		 * @param newer The object with updated values
		 * @param types Map of column names to their SQLite types
		 * @param setter Array of "column = $column" assignment strings
		 * @param id The ID of the row to update
		 */
		void updateImp(T newer, Gee.HashMap<string,string> types, string[] setter, int id)
		{
	
			Sqlite.Statement stmt;
			var q = "UPDATE " + this.table + " SET  " + string.joinv(",", setter) +
				" WHERE id = " + id.to_string();
			this.db.db.prepare_v2 (q, q.length, out stmt);
			if (stmt == null) {
			    GLib.error("Update: %s %s", q, this.db.db.errmsg());
			}
			
			foreach(var n in types.keys) {
				// Convert column name to property name (underscores to hyphens for GObject)
				var prop_name = n.replace("_", "-");
				Type value_type;
				if (!this.has_property(prop_name, out value_type)) {
					continue;
				}
				switch(types.get(n)) {
					case "INTEGER":
					case "INT2":
						stmt.bind_int (stmt.bind_parameter_index ("$"+ n), this.getInt(newer, prop_name, value_type));
					 	break;
					case "INT64":
						stmt.bind_int64 (stmt.bind_parameter_index ("$"+ n), (int64) this.getInt(newer, prop_name, value_type));
						break;
					
					case "TEXT":
						stmt.bind_text (stmt.bind_parameter_index ("$"+ n), this.getText(newer, prop_name, value_type));
						break;
					default:
					    GLib.error("Unhandled SQlite type : %s", types.get(n));
				}
			
			}
			GLib.debug("Execute %s", stmt.expanded_sql());	 
 			if (Sqlite.DONE != stmt.step ()) {
			    GLib.error("Update:   %s",   this.db.db.errmsg());
			}
			

		}
		
		/**
		 * Compares a property value between two objects.
		 * 
		 * @param older The first object to compare
		 * @param newer The second object to compare
		 * @param prop The name of the property to compare
		 * @param gtype The GType of the property
		 * @return true if the property values are equal, false otherwise
		 */
		public bool compareProperty(T older, T newer, string prop, GLib.Type gtype)
		{
			assert (typeof(T).is_object());
			var  oldv = GLib.Value (gtype);				
			((Object)older).get_property(prop, ref oldv);
			var  newv = GLib.Value (gtype);				
			((Object)newer).get_property(prop, ref newv);
			
			gtype = gtype.is_enum()  ? GLib.Type.ENUM : gtype;
			
			switch(gtype) {
				case GLib.Type.BOOLEAN: 	return 	newv.get_boolean() == oldv.get_boolean();
				case GLib.Type.INT64:    return 	newv.get_int64() == oldv.get_int64();	
				case GLib.Type.INT:  return 	newv.get_int() == oldv.get_int();
				case GLib.Type.STRING:  return 	newv.get_string() == oldv.get_string();
	 			case GLib.Type.ENUM:  return 	newv.get_enum() == oldv.get_enum();
				default:
					GLib.error("unsupported type for col %s : %s", prop, gtype.to_string());
					//return;
			}
		
		}
		
		/**
		 * Extracts an integer value from an object property.
		 * 
		 * Converts various property types (boolean, int, int64, enum) to an
		 * integer value for use in SQL queries.
		 * 
		 * @param obj The object to read from
		 * @param prop The property name
		 * @param gtype The GType of the property
		 * @return The integer value of the property
		 */
		public int getInt(T obj, string prop, GLib.Type gtype)
		{
			assert (typeof(T).is_object());
			var  newv = GLib.Value (gtype);	
			((Object)obj).get_property(prop, ref newv);
			gtype = gtype.is_enum()  ? GLib.Type.ENUM : gtype;
			
			switch(gtype) {
				case GLib.Type.BOOLEAN: 	return 	newv.get_boolean() ? 1 : 0;
				case GLib.Type.INT64:    return (int)	newv.get_int64();
				case GLib.Type.INT:  return 	newv.get_int();
	 			case GLib.Type.ENUM:  return 	(int) newv.get_enum() ;
				case GLib.Type.STRING:  
				default:
					GLib.error("unsupported getInt  for prop %s : %s", prop, gtype.to_string());
	 		}
		}
		
		/**
		 * Extracts a text value from an object property.
		 * 
		 * Converts a string property to text for use in SQL queries.
		 * 
		 * @param obj The object to read from
		 * @param prop The property name
		 * @param gtype The GType of the property
		 * @return The string value of the property
		 */
		public string getText(T obj, string prop, GLib.Type gtype)
		{
			assert (typeof(T).is_object());
			var  newv = GLib.Value (gtype);	
			((Object)obj).get_property(prop, ref newv);
			switch(gtype) {
				case GLib.Type.STRING:  return 	newv.get_string();
				case GLib.Type.BOOLEAN:
				case GLib.Type.INT64:  
				case GLib.Type.INT:  
				
				default:
					GLib.error("unsupported getText  for prop %s : %s", prop, gtype.to_string());
	 		}
		}
		
		/**
		 * Gets a list of column names, optionally excluding some and adding a prefix.
		 * 
		 * This method retrieves all column names from the table schema, excluding
		 * any specified in the except array, and optionally prefixing them with
		 * a table alias (e.g., "table.column as column").
		 * 
		 * @param except Array of column names to exclude (null to exclude none)
		 * @param prefix Optional prefix to add to column names (e.g., table alias)
		 * @return Array of column name strings
		 */
		public string[] getColsExcept(string[]? except, string prefix = "")
		{
		 	assert(this.table != "");
			var schema = new Schema(this.db);
			var sc = schema.load(this.table);
			string[] keys = {};			
			foreach(var s in sc) {
				if (except != null && GLib.strv_contains(except, s.name)) {
					continue;
				}
				if (prefix != "") {
					keys += (prefix + s.name + " as " + s.name);
					continue;
				}
				
				keys +=   s.name;
		 	}
		 	return keys;
	 	}
		
		/**
		 * Selects objects from the table matching a WHERE clause.
		 * 
		 * This method executes a SELECT query with the specified WHERE clause
		 * and populates the result list with instantiated objects of type T.
		 * 
		 * @param where The WHERE clause (e.g., "WHERE id = 5" or "WHERE name = 'test'")
		 * @param ret The list to populate with results
		 */
		public void select( string where,  Gee.ArrayList<T> ret )
		{
			

		 	assert(this.table != "");
			var keys = this.getColsExcept(null);
			var q = "SELECT " +  string.joinv(",", keys) + " FROM  " + this.table + "  " + where;
			this.selectQuery(q, ret);
			
		}
		
		/**
		 * Selects objects from the table matching a WHERE clause asynchronously.
		 * 
		 * This method executes a SELECT query in a background thread and populates
		 * the result list with instantiated objects of type T.
		 * 
		 * **IMPORTANT**: You MUST always use `yield` when calling this method. The
		 * result list (`ret`) is being populated in a background thread and is NOT
		 * thread-safe to access while the query is running. Only access the result
		 * list after `yield` returns (i.e., after the async method completes).
		 * 
		 * @param where The WHERE clause (e.g., "WHERE id = 5" or "WHERE name = 'test'")
		 * @param ret The list to populate with results (DO NOT access until after yield completes)
		 * @throws ThreadError if thread creation fails
		 */
		public async void select_async(string where, Gee.ArrayList<T> ret) throws ThreadError
		{
			assert(this.table != "");
			
			// Build query string on main thread (fast operation, safe cache access)
			var keys = this.getColsExcept(null);
			var q = "SELECT " + string.joinv(",", keys) + " FROM " + this.table + " " + where;
			
			SourceFunc callback = select_async.callback;
			
			// Hold reference to closure to keep it from being freed whilst thread is active
			ThreadFunc<bool> run = () => {
				// Execute query in background thread (slow operation)
				this.selectQuery(q, ret);
				
				// Schedule callback on main thread
				Idle.add((owned) callback);
				return true;
			};
			
			new Thread<bool>("select-query", run);
			
			// Wait for background thread to schedule our callback
			yield;
		}
		
		/**
		 * Prepares a SQL SELECT statement for execution.
		 * 
		 * This method prepares a SQL query string and returns a prepared statement
		 * that can be executed or bound with parameters.
		 * 
		 * @param q The SQL query string to prepare
		 * @return A prepared SQLite statement
		 */
	 	public Sqlite.Statement selectPrepare(string q  )
		{	
			Sqlite.Statement stmt;

			this.db.db.prepare_v2 (q, q.length, out stmt);
			if (stmt == null) {
			    GLib.error("%s from query   %s",   this.db.db.errmsg(), q);
			
			}
 			return stmt;
 		}
 		
 		/**
 		 * Executes a prepared SELECT statement and populates a result list.
 		 * 
 		 * This method steps through all rows returned by the query and creates
 		 * objects of type T for each row, populating them with the column values.
 		 * 
 		 * @param stmt The prepared statement to execute
 		 * @param ret The list to populate with result objects
 		 */
		public void selectExecute(Sqlite.Statement stmt, Gee.ArrayList<T> ret )
		{
			GLib.debug("Execute %s", stmt.expanded_sql());
			
			// Find the typekey column index once (column positions don't change between rows)
			int typekey_index = -1;
			if (this.typemap != null && this.typekey != null) {
				for (int i = 0; i < stmt.column_count(); i++) {
					if (stmt.column_name(i) == this.typekey) {
						typekey_index = i;
						break;
					}
				}
			}
			
			while (stmt.step() == Sqlite.ROW) {
		 		T row;
		 		
		 		// Check if we need to use polymorphic type mapping
		 		Type object_type = typeof(T);
		 		if (typekey_index >= 0) {
		 			var type_id = stmt.column_text(typekey_index);
		 			if (type_id != null && this.typemap.has_key(type_id)) {
		 				object_type = this.typemap.get(type_id);
		 			}
		 		}
		 		
		 		if (this.property_names != null && this.property_values != null) {
				//	GLib.debug("new_with_properties %s", string.joinv(",", this.property_names));
		 			row = (T) Object.new_with_properties(object_type, this.property_names, this.property_values);
		 		} else {
				//	GLib.debug("new %s", object_type.name());
		 			row = (T) Object.new(object_type);
		 		}
				this.fetchRow(stmt, row);
		 		ret.add( row);
		 		
			}
			 
		    GLib.debug("select got %d rows / last errr  %s", ret.size,  this.db.db.errmsg());
					
		}
		
		/**
		 * Fetches all string values from the first column of a query result.
		 * 
		 * This is a convenience method for queries that return a single column
		 * of string values (e.g., "SELECT name FROM table").
		 * 
		 * @param stmt The prepared statement to execute
		 * @return A list of string values from the first column
		 */
		public Gee.ArrayList<string> fetchAllString(Sqlite.Statement stmt )
 		{
			var ret = new Gee.ArrayList<string>();
			while (stmt.step() == Sqlite.ROW) {
		 		 ret.add( stmt.column_text(0));
			}
			 
		    GLib.debug("fetchAllString got %d rows / last errr  %s", ret.size,  this.db.db.errmsg());
			return ret;		
		}
		
		/**
		 * Fetches all integer values from the first column of a query result.
		 * 
		 * This is a convenience method for queries that return a single column
		 * of integer values (e.g., "SELECT id FROM table").
		 * 
		 * @param stmt The prepared statement to execute
		 * @return A list of integer values from the first column
		 */
		public Gee.ArrayList<int> fetchAllInt64(Sqlite.Statement stmt )
 		{
			var ret = new Gee.ArrayList<int>();
			while (stmt.step() == Sqlite.ROW) {
		 		 ret.add(( int)stmt.column_int64(0));
			}
			 
		    GLib.debug("fetchAllInt64 got %d rows / last errr  %s", ret.size,  this.db.db.errmsg());
			return ret;		
		}
		
		/**
		 * Executes a prepared SELECT statement and populates a single object.
		 * 
		 * This method is useful for queries that are expected to return exactly
		 * one row (e.g., "SELECT * FROM table WHERE id = 5"). The first row
		 * is used to populate the provided object.
		 * 
		 * @param stmt The prepared statement to execute
		 * @param row The object to populate with the first row's data
		 * @return true if a row was found and populated, false otherwise
		 */
		public bool selectExecuteInto(Sqlite.Statement stmt,  T row )
		{
			GLib.debug("Execute INTO %s", stmt.expanded_sql());	
			if (stmt.step() == Sqlite.ROW) {
		 		 
				this.fetchRow(stmt, row);
		 		return true;
		 		
			}
//		    GLib.debug("select got %d rows / last errr  %s", ret.size,  this.db.db.errmsg());
			return false;
			 

					
		}
		
		/**
		 * Executes a raw SQL SELECT query and populates a result list.
		 * 
		 * This method combines selectPrepare and selectExecute for convenience.
		 * It prepares the query, executes it, and populates the result list.
		 * 
		 * @param q The SQL SELECT query string
		 * @param ret The list to populate with result objects
		 */
		public void selectQuery(string q, Gee.ArrayList<T> ret )
		{	
			assert (typeof(T).is_object());
			var  stmt = this.selectPrepare(q);
 			this.selectExecute(stmt, ret);
			 
 
					
		}
		
		/**
		 * Fetches a single row from a prepared statement and populates an object.
		 * 
		 * This internal method reads column values from the current row of the
		 * statement and sets corresponding properties on the object.
		 * 
		 * @param stmt The prepared statement positioned at a row
		 * @param row The object to populate
		 */
		void fetchRow(Sqlite.Statement stmt, T row)
		{
			 
			assert (typeof(T).is_object());
 
			int cols = stmt.column_count ();
			for (int i = 0; i < cols; i++) {
				var col_name = stmt.column_name (i);
				if (col_name == null) {
					GLib.debug("Skip col %d = no column name?", i);
					continue;
				}
				
				var type_id = stmt.column_type (i);
				// Sqlite.INTEGER, Sqlite.FLOAT, Sqlite.TEXT,Sqlite.BLOB, or Sqlite.NULL. 
				this.setObjectProperty(stmt, row, i, col_name, type_id);
			}
			 
		}
		
		private Gee.HashMap<string, int> has_prop { get; set; 
			default = new Gee.HashMap<string, int>(); }
		
		/**
		 * Check if a property exists and is writable, using a cache to avoid repeated lookups.
		 * 
		 * @param prop The property name to check
		 * @param value_type Output parameter for the property's value type (0 if not found/read-only)
		 * @return true if the property exists and is writable, false otherwise
		 */
		bool has_property(string prop, out Type value_type)
		{
			if (!this.has_prop.has_key(prop)) {
				// Check if property exists and is writable
				var ocl = (GLib.ObjectClass) typeof(T).class_ref();
				var ps = ocl.find_property(prop);
				if (ps == null) {
					this.has_prop[prop] = 0;
					value_type = 0;
					GLib.warning("Property '%s' not found on object, skipping", prop);
					return false;
				}
				
				if ((ps.flags & GLib.ParamFlags.WRITABLE) == 0) {
					this.has_prop[prop] = 0;
					value_type = 0;
					GLib.warning("Property '%s' is read-only, skipping", prop);
					return false;
				}
				this.has_prop[prop] = (int) ps.value_type;
			}
 			value_type = (Type) this.has_prop[prop] ;
			return value_type > 0  ? true : false;
		}
		
		/**
		 * Sets an object property from a SQLite column value.
		 * 
		 * This internal method handles type conversion from SQLite column types
		 * to GObject property types, including boolean, int, int64, enum, and string.
		 * Handles column name to property name mapping (e.g., "type" -> "ctype").
		 * 
		 * @param stmt The prepared statement
		 * @param in_row The object to set the property on
		 * @param pos The column index in the statement
		 * @param col_name The name of the column
		 * @param stype The SQLite column type
		 */
		void setObjectProperty(Sqlite.Statement stmt, T in_row, int pos, string col_name, int stype) 
		{
			// Map column name to property name (e.g., "type" -> "ctype", "base_type" -> "base-type")
			var prop = col_name == "type" ? "ctype" : col_name.replace("_", "-");
			
			// Check if property exists and is writable
			Type gtype;
			if (!this.has_property(prop, out gtype)) {
				return;
			}

			var  newv = GLib.Value ( gtype );
			var row = (Object) in_row;
			gtype = gtype.is_enum()  ? GLib.Type.ENUM : gtype;
				
			switch (gtype) {
				case GLib.Type.BOOLEAN:
 				 	if (stype == Sqlite.INTEGER) {			 	
						newv.set_boolean(stmt.column_int( pos) == 1);
						break;
					}
					GLib.debug("invalid bool setting for col_name %s", col_name);
					return;
					
				case GLib.Type.INT64:
					if (stype == Sqlite.INTEGER) {	
		 				newv.set_int64( stmt.column_int64( pos) ); // we will have to let symbol sort out parent_id storage?
		 				break;
	 				}
	 				GLib.debug("invalid int setting for col_name %s", col_name);
					return;
 			 	case GLib.Type.ENUM:

					if (stype == Sqlite.INTEGER) {	
						var val = stmt.column_int(pos );
						if (val == 0) {
							GLib.error("invalid enum value");
						}
		 				newv.set_enum( val ); // we will have to let symbol sort out parent_id storage?
		 				break;
	 				}
	 				GLib.debug("invalid enum setting for col_name %s", col_name);
					return;	
					
			 	case GLib.Type.INT:

					if (stype == Sqlite.INTEGER) {	
		 				newv.set_int( stmt.column_int(pos ) ); // we will have to let symbol sort out parent_id storage?
		 				break;
	 				}
	 				GLib.debug("invalid int setting for col_name %s", col_name);
					return;
	 						
				case GLib.Type.STRING:
					if (stype == Sqlite.TEXT || stype == Sqlite.NULL) {	
						var str = stmt.column_text(pos);
						newv.set_string(str == null? "": str);
						break;	
					}
					GLib.debug("invalid string setting for col_name %s", col_name);
					return;
				
				default:
					GLib.error("unsupported type for col %s : %s", col_name, gtype.to_string());
					//return;
				
			}
			
			
			row.set_property(prop, newv);
		
		
		
		
		}
		
		/**
		 * Deletes a row from the table by ID.
		 * 
		 * This method executes a DELETE query for the row with the specified ID.
		 * 
		 * @param id The ID of the row to delete
		 */
		public void deleteId(int64 id) 
		{
			var q= "DELETE from " + this.table + " WHERE id = $id";
			GLib.debug("Query %s", q);
			var stmt = this.selectPrepare( q );
			stmt.bind_int64 (stmt.bind_parameter_index ("$id"), id);
			if (Sqlite.DONE != stmt.step ()) {
			    GLib.error("Delete %d:   %s", (int)id,   this.db.db.errmsg());
			}
				 
			
		
		}
		 
		 
		
	}
}