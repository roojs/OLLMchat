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
			
			var ocl = (GLib.ObjectClass) typeof(T).class_ref ();
			
			
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
				var ps = ocl.find_property( s.name );
				if (ps == null) {
					GLib.debug("could not find property %s in object interface", s.name);
					continue;
				}
				switch(s.ctype) {
					case "INTEGER":
					case "INT2":

						stmt.bind_int (stmt.bind_parameter_index ("$"+ s.name), this.getInt(newer, s.name,ps.value_type));
					 	break;
					case "INT64":
						// might be better to have getInt64
						stmt.bind_int64 (stmt.bind_parameter_index ("$"+ s.name), (int64) this.getInt(newer, s.name,ps.value_type));
					 	break;
					case "TEXT":
						stmt.bind_text (stmt.bind_parameter_index ("$"+ s.name), this.getText(newer, s.name, ps.value_type));
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
			
			var ocl = (GLib.ObjectClass) typeof(T).class_ref ();
			   
			string[] setter = {};
			var types = new Gee.HashMap<string,string> ();
			foreach(var s in sc) {
				if (s.name == "id" ){
					continue;
				}
			
				var ps = ocl.find_property( s.name );
				if (ps == null) {
					GLib.debug("could not find property %s in object interface",  s.name);
					continue;
				}
				
				if (old ==null || !this.compareProperty(old, newer, s.name, ps.value_type)) {
					setter += (s.name +  " = $" + s.name);
					types.set(s.name,s.ctype);
				}
			}
			if (setter.length < 1) {
				return;
			}

			var id = this.getInt(old == null ? newer : old, "id",
				ocl.find_property("id").value_type);
				
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
			
			var ocl = (GLib.ObjectClass) typeof(T).class_ref ();
			   
			string[] setter = {};
			var types = new Gee.HashMap<string,string> ();
			foreach(var s in sc) {
				if (s.name == "id" ){
					continue;
				}
			
				var ps = ocl.find_property( s.name );
				if (ps == null) {
					GLib.debug("could not find property %s in object interface",  s.name);
					continue;
				}
				
				 
				setter += (s.name +  " = $" + s.name);
				types.set(s.name,s.ctype);
				
			}
			if (setter.length < 1) {
				return;
			}

			var id = this.getInt(newer, "id",
				ocl.find_property("id").value_type);
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
	
			var ocl = (GLib.ObjectClass) typeof(T).class_ref ();
			Sqlite.Statement stmt;
			var q = "UPDATE " + this.table + " SET  " + string.joinv(",", setter) +
				" WHERE id = " + id.to_string();
			this.db.db.prepare_v2 (q, q.length, out stmt);
			if (stmt == null) {
			    GLib.error("Update: %s %s", q, this.db.db.errmsg());
			}
			
			foreach(var n in types.keys) {
				var ps = ocl.find_property( n );
				if (ps == null) {
					GLib.debug("could not find property %s in object interface", n);
					continue;
				}
				switch(types.get(n)) {
					case "INTEGER":
					case "INT2":
						stmt.bind_int (stmt.bind_parameter_index ("$"+ n), this.getInt(newer, n,ps.value_type));
					 	break;
					case "INT64":
						stmt.bind_int64 (stmt.bind_parameter_index ("$"+ n), (int64) this.getInt(newer, n,ps.value_type));
						break;
					
					case "TEXT":
						stmt.bind_text (stmt.bind_parameter_index ("$"+ n), this.getText(newer, n, ps.value_type));
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
			while (stmt.step() == Sqlite.ROW) {
		 		var row =   Object.new (typeof(T));
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
			 
		    GLib.debug("fetchAllString got %d rows / last errr  %s", ret.size,  Database.db.errmsg());
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
			 
		    GLib.debug("fetchAllString got %d rows / last errr  %s", ret.size,  Database.db.errmsg());
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
			var ocl = (GLib.ObjectClass) typeof(T).class_ref ();
			for (int i = 0; i < cols; i++) {
				var col_name = stmt.column_name (i);
				if (col_name == null) {
					GLib.debug("Skip col %d = no column name?", i);
					continue;
				}
				
				var type_id = stmt.column_type (i);
				// Sqlite.INTEGER, Sqlite.FLOAT, Sqlite.TEXT,Sqlite.BLOB, or Sqlite.NULL. 
				var prop = col_name == "type" ? "ctype" : col_name; 
				var ps = ocl.find_property( prop );
				if (ps == null) {
					GLib.debug("could not find property %s in object interface", prop);
					continue;
				}
				 
				this.setObjectProperty(stmt, row, i, col_name, type_id, ps.value_type);
			}
			 
		}
		
		/**
		 * Sets an object property from a SQLite column value.
		 * 
		 * This internal method handles type conversion from SQLite column types
		 * to GObject property types, including boolean, int, int64, enum, and string.
		 * 
		 * @param stmt The prepared statement
		 * @param in_row The object to set the property on
		 * @param pos The column index in the statement
		 * @param col_name The name of the column (used for property name)
		 * @param stype The SQLite column type
		 * @param gtype The GType of the property to set
		 */
		void setObjectProperty(Sqlite.Statement stmt, T in_row, int pos, string col_name, int stype, Type gtype) 
		{
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
			// as we cant use 'type' as a vala object property..
			var prop = col_name == "type" ? "ctype" : col_name; 
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