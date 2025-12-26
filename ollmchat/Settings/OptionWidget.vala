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
	 * Base class for option widgets that can update their values from Options objects.
	 * 
	 * @since 1.0
	 */
	public abstract class OptionWidget : Object
	{
		/**
		 * Updates the widget's value from the options object.
		 * 
		 * @param options Options object to read value from
		 */
		public abstract void update_from_options(OLLMchat.Call.Options options);

		/**
		 * Updates the options object from the widget's current value.
		 * 
		 * @param options Options object to update
		 */
		public abstract void update_to_options(OLLMchat.Call.Options options);
	}

	/**
	 * Temperature option widget (0.0-2.0).
	 */
	public class TemperatureWidget : OptionWidget
	{
		private Gtk.SpinButton spin_button;
		private Adw.ActionRow row;

		public TemperatureWidget()
		{
			this.spin_button = new Gtk.SpinButton.with_range(0.0, 2.0, 0.1) {
				digits = 1
			};
			this.row = new Adw.ActionRow() {
				title = "Temperature",
				subtitle = "Controls randomness in output (0.0 = deterministic, 2.0 = very random)"
			};
			this.row.add_suffix(this.spin_button);
		}

		public Adw.ActionRow get_row()
		{
			return this.row;
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.spin_button.value = options.temperature != -1.0 ? options.temperature : 0.0;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			var val = this.spin_button.value;
			if (val == 0.0 && options.temperature == -1.0) {
				return; // No change
			}
			options.temperature = val;
		}
	}

	/**
	 * Top P option widget (0.0-1.0).
	 */
	public class TopPWidget : OptionWidget
	{
		private Gtk.SpinButton spin_button;
		private Adw.ActionRow row;

		public TopPWidget()
		{
			this.spin_button = new Gtk.SpinButton.with_range(0.0, 1.0, 0.01) {
				digits = 2
			};
			this.row = new Adw.ActionRow() {
				title = "Top P",
				subtitle = "Nucleus sampling - considers tokens with cumulative probability up to this value"
			};
			this.row.add_suffix(this.spin_button);
		}

		public Adw.ActionRow get_row()
		{
			return this.row;
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.spin_button.value = options.top_p != -1.0 ? options.top_p : 0.9;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			var val = this.spin_button.value;
			if (val == 0.9 && options.top_p == -1.0) {
				return; // No change
			}
			options.top_p = val;
		}
	}

	/**
	 * Top K option widget (1-1000).
	 */
	public class TopKWidget : OptionWidget
	{
		private Gtk.SpinButton spin_button;
		private Adw.ActionRow row;

		public TopKWidget()
		{
			this.spin_button = new Gtk.SpinButton.with_range(1.0, 1000.0, 1.0) {
				digits = 0
			};
			this.row = new Adw.ActionRow() {
				title = "Top K",
				subtitle = "Limits sampling to top K most likely tokens"
			};
			this.row.add_suffix(this.spin_button);
		}

		public Adw.ActionRow get_row()
		{
			return this.row;
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.spin_button.value = options.top_k != -1 ? (double)options.top_k : 40.0;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			var val = (int)this.spin_button.value;
			if (val == 40 && options.top_k == -1) {
				return; // No change
			}
			options.top_k = val;
		}
	}

	/**
	 * Num Ctx option widget (1-1000000).
	 */
	public class NumCtxWidget : OptionWidget
	{
		private Gtk.SpinButton spin_button;
		private Adw.ActionRow row;

		public NumCtxWidget()
		{
			this.spin_button = new Gtk.SpinButton.with_range(1.0, 1000000.0, 1.0) {
				digits = 0
			};
			this.row = new Adw.ActionRow() {
				title = "Num Ctx",
				subtitle = "Context window size - number of tokens the model can consider"
			};
			this.row.add_suffix(this.spin_button);
		}

		public Adw.ActionRow get_row()
		{
			return this.row;
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.spin_button.value = options.num_ctx != -1 ? (double)options.num_ctx : 2048.0;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			var val = (int)this.spin_button.value;
			if (val == 2048 && options.num_ctx == -1) {
				return; // No change
			}
			options.num_ctx = val;
		}
	}

	/**
	 * Num Predict option widget (1-1000000, -1 for no limit).
	 */
	public class NumPredictWidget : OptionWidget
	{
		private Gtk.SpinButton spin_button;
		private Adw.ActionRow row;

		public NumPredictWidget()
		{
			this.spin_button = new Gtk.SpinButton.with_range(1.0, 1000000.0, 1.0) {
				digits = 0
			};
			this.row = new Adw.ActionRow() {
				title = "Num Predict",
				subtitle = "Maximum number of tokens to generate (-1 = no limit)"
			};
			this.row.add_suffix(this.spin_button);
		}

		public Adw.ActionRow get_row()
		{
			return this.row;
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.spin_button.value = options.num_predict != -1 ? (double)options.num_predict : -1.0;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			var val = (int)this.spin_button.value;
			options.num_predict = val;
		}
	}

	/**
	 * Repeat Penalty option widget (0.1-10.0).
	 */
	public class RepeatPenaltyWidget : OptionWidget
	{
		private Gtk.SpinButton spin_button;
		private Adw.ActionRow row;

		public RepeatPenaltyWidget()
		{
			this.spin_button = new Gtk.SpinButton.with_range(0.1, 10.0, 0.1) {
				digits = 1
			};
			this.row = new Adw.ActionRow() {
				title = "Repeat Penalty",
				subtitle = "Penalty for repeating tokens (1.0 = no penalty, >1.0 = penalty)"
			};
			this.row.add_suffix(this.spin_button);
		}

		public Adw.ActionRow get_row()
		{
			return this.row;
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.spin_button.value = options.repeat_penalty != -1.0 ? options.repeat_penalty : 1.1;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			var val = this.spin_button.value;
			if (val == 1.1 && options.repeat_penalty == -1.0) {
				return; // No change
			}
			options.repeat_penalty = val;
		}
	}

	/**
	 * Min P option widget (0.0-1.0).
	 */
	public class MinPWidget : OptionWidget
	{
		private Gtk.SpinButton spin_button;
		private Adw.ActionRow row;

		public MinPWidget()
		{
			this.spin_button = new Gtk.SpinButton.with_range(0.0, 1.0, 0.01) {
				digits = 2
			};
			this.row = new Adw.ActionRow() {
				title = "Min P",
				subtitle = "Minimum probability threshold for token selection"
			};
			this.row.add_suffix(this.spin_button);
		}

		public Adw.ActionRow get_row()
		{
			return this.row;
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.spin_button.value = options.min_p != -1.0 ? options.min_p : 0.0;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			var val = this.spin_button.value;
			if (val == 0.0 && options.min_p == -1.0) {
				return; // No change
			}
			options.min_p = val;
		}
	}

	/**
	 * Seed option widget (-1 or any int).
	 */
	public class SeedWidget : OptionWidget
	{
		private Gtk.SpinButton spin_button;
		private Adw.ActionRow row;

		public SeedWidget()
		{
			this.spin_button = new Gtk.SpinButton.with_range(-1.0, 2147483647.0, 1.0) {
				digits = 0
			};
			this.row = new Adw.ActionRow() {
				title = "Seed",
				subtitle = "Random seed for reproducible outputs (-1 = random)"
			};
			this.row.add_suffix(this.spin_button);
		}

		public Adw.ActionRow get_row()
		{
			return this.row;
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.spin_button.value = options.seed != -1 ? (double)options.seed : -1.0;
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			var val = (int)this.spin_button.value;
			options.seed = val == -1 ? -1 : val;
		}
	}

	/**
	 * Stop option widget (string entry).
	 */
	public class StopWidget : OptionWidget
	{
		private Gtk.Entry entry;
		private Adw.ActionRow row;

		public StopWidget()
		{
			this.entry = new Gtk.Entry() {
				placeholder_text = "(optional)"
			};
			this.row = new Adw.ActionRow() {
				title = "Stop",
				subtitle = "Stop sequences that cause generation to stop (comma-separated)"
			};
			this.row.add_suffix(this.entry);
		}

		public Adw.ActionRow get_row()
		{
			return this.row;
		}

		public override void update_from_options(OLLMchat.Call.Options options)
		{
			this.entry.text = options.stop != "" ? options.stop : "";
		}

		public override void update_to_options(OLLMchat.Call.Options options)
		{
			options.stop = this.entry.text;
		}
	}
}

