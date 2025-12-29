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

namespace OLLMchat.Settings
{
	/**
	 * Pull status information for a model pull operation.
	 * 
	 * Combines both runtime tracking and persistence data.
	 * 
	 * @since 1.3.4
	 */
	public class PullStatus : GLib.Object, Json.Serializable
	{
		// Persistence fields (saved to JSON)
		public string model_name { get; set; default = ""; }
		public string status { get; set; default = ""; }
		public string started { get; set; default = ""; }
		public string error { get; set; default = ""; }
		public string last_chunk_status { get; set; default = ""; }
		public int retry_count { get; set; default = 0; }
		public string connection_url { get; set; default = ""; }
		public int64 completed { get; set; default = 0; }
		public int64 total { get; set; default = 0; }
		
		// Runtime fields (not serialized)
		public bool active = false;
		public int64 last_update_time = 0;
		public OLLMchat.Settings.Connection? connection = null;
		private int64 previous_completed = 0;
		private int64 previous_update_time = 0;
		public uint completion_timer_id = 0;
		
		// Start tracking for overall rate calculation
		public int64 start_time = 0;
		public int64 start_completed = 0;
		
		/**
		 * Progress percentage (0-100), calculated from completed/total.
		 * 
		 * This is a calculated property that derives from completed and total.
		 * If total is 0, returns 0. Otherwise calculates percentage.
		 */
		public int progress {
			get {
				if (this.total > 0) {
					return (int)(((double)this.completed / (double)this.total) * 100.0);
				}
				return 0;
			}
			set {
				// Setter is a no-op - progress is always calculated
				// This allows the property to be used in serialization if needed
			}
		}
		
		/**
		 * Progress fraction (0.0-1.0) for progress bar.
		 */
		public double get_fraction()
		{
			if (this.total > 0) {
				return ((double)this.completed / (double)this.total).clamp(0.0, 1.0);
			}
			return 0.0;
		}
		
		/**
		 * Updates rate tracking with current values.
		 * Should be called after updating completed bytes.
		 */
		public void update_rate_tracking()
		{
			this.previous_completed = this.completed;
			this.previous_update_time = this.last_update_time;
		}
		
		/**
		 * Download rate in bytes per second.
		 * Uses overall average rate since download started.
		 * 
		 * @return Download rate in bytes/sec, or 0 if cannot be calculated
		 */
		public double get_download_rate_bytes_per_sec()
		{
			// Use overall rate since download started
			if (this.start_time > 0 && this.last_update_time > this.start_time) {
				var time_diff = this.last_update_time - this.start_time;
				// Require minimum 2 seconds to avoid silly rates from tiny time differences
				// Allow calculation when completed >= start_completed (handles start_completed = 0 case)
				// and ensure we have some actual progress (completed > 0) to calculate a meaningful rate
				if (time_diff >= 2.0 && this.completed >= this.start_completed && this.completed > 0) {
					return (double)(this.completed - this.start_completed) / (double)time_diff;
				}
			}
			return 0.0;
		}
		
		/**
		 * Estimated time remaining in seconds.
		 * 
		 * @return Estimated time in seconds, or 0 if cannot be calculated
		 */
		public double get_time_estimate_seconds()
		{
			var rate = this.get_download_rate_bytes_per_sec();
			if (this.total > this.completed && rate > 0) {
				return (double)(this.total - this.completed) / rate;
			}
			return 0.0;
		}
		
		/**
		 * Formats size text in MB (e.g., "100 MB of 300 MB").
		 */
		public string get_formatted_size_text()
		{
			var completed_mb = (int64)(this.completed / (1024 * 1024));
			var total_mb = (int64)(this.total / (1024 * 1024));
			
			// Format with comma separators using locale-aware formatting
			return "%'d MB of %'d MB".printf(completed_mb, total_mb);
		}
		
		/**
		 * Formats download rate text (e.g., "2.5 MB/s" or "512 KB/s").
		 * 
		 * @return Formatted rate text, or empty string if rate cannot be calculated
		 */
		public string get_formatted_rate_text()
		{
			var rate_bytes_per_sec = this.get_download_rate_bytes_per_sec();
			if (rate_bytes_per_sec <= 0.0) {
				return "";
			}
			
			var rate_mbps = rate_bytes_per_sec / (1024.0 * 1024.0);
			if (rate_mbps >= 1.0) {
				return "%.2f MB/s".printf(rate_mbps);
			}
			return "%.0f KB/s".printf(rate_mbps * 1024.0);
		}
		
		/**
		 * Formats time estimate text (e.g., "est. time left: 5m" or "est. time left: 2h").
		 * 
		 * @return Formatted time estimate with "est. time left:" prefix, or "est. time left: unknown" if cannot be calculated
		 */
		public string get_formatted_time_estimate()
		{
			var remaining_seconds = this.get_time_estimate_seconds();
			if (remaining_seconds <= 0) {
				return "est. time left: unknown";
			}
			
			var remaining_minutes = (int)(remaining_seconds / 60);
			
			// Up to 90 minutes, show in minutes
			if (remaining_minutes <= 90) {
				return "est. time left: %dm".printf(remaining_minutes);
			}
			
			// Over 90 minutes, show in hours
			var hours = remaining_minutes / 60;
			return "est. time left: %dh".printf(hours);
		}
		
		/**
		 * Formats progress text for progress bar display.
		 * 
		 * @return Formatted progress text
		 */
		public string get_progress_text()
		{
			string[] parts = {};
			
			// Always show model name
			parts += this.model_name;
			
			switch (this.status) {
				case "pulling":
					// Show size text (total should be saved and restored, so it should have a value)
					parts += this.get_formatted_size_text();
					if (this.total > 0) {
						parts += "%d%%".printf(this.progress);
						
						// Check if time estimate can be calculated (rate is also invalid if time estimate is unknown)
						var time_estimate = this.get_formatted_time_estimate();
						if (time_estimate != "est. time left: unknown") {
							// Show rate if available and time estimate is valid
							var rate_text = this.get_formatted_rate_text();
							if (rate_text != "") {
								parts += rate_text;
							}
							
							// Show time estimate
							parts += time_estimate;
						}
					}
					break;
				case "pending-retry":
					parts += "Retrying...";
					break;
				case "complete":
					parts += "Complete";
					break;
				case "failed":
					parts += "Failed";
					break;
			}
			
			return string.joinv(" • ", parts);
		}
		
		public unowned ParamSpec? find_property(string name)
		{
			return this.get_class().find_property(name);
		}
		
		public new void Json.Serializable.set_property(ParamSpec pspec, Value value)
		{
			base.set_property(pspec.get_name(), value);
		}
		
		public new Value Json.Serializable.get_property(ParamSpec pspec)
		{
			GLib.Value val = GLib.Value(pspec.value_type);
			base.get_property(pspec.get_name(), ref val);
			return val;
		}
		
		public override Json.Node serialize_property(string property_name, GLib.Value value, ParamSpec pspec)
		{
			// Don't serialize runtime-only fields or calculated properties
			switch (property_name) {
				case "active":
				case "last_update_time":
				case "connection":
				case "completion_timer_id":
				case "progress":
					return null;
				case "completed":
				case "total":
					// Always serialize completed and total, even if 0, so we can restore progress
					// Explicitly create JSON node to ensure zero values are included
					var node = new Json.Node(Json.NodeType.VALUE);
					node.set_int(value.get_int64());
					return node;
				default:
					// Serialize all other fields (defaults will handle empty/zero values)
					return default_serialize_property(property_name, value, pspec);
			}
		}
		
		// Note: previous_completed and previous_update_time are private fields
		// and not properties, so they won't be serialized automatically
	}
}

