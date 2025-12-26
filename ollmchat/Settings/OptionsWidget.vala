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
	 * Helper class that creates all option rows for model configuration.
	 * 
	 * @since 1.0
	 */
	public class OptionsWidget
	{
		public static Gee.ArrayList<OptionRow> create_option_rows(OLLMchat.Call.Options options)
		{
			var rows = new Gee.ArrayList<OptionRow>();

			var temp_widget = new OptionFloatWidget() {
				title = "Temperature",
				subtitle = "Controls randomness in output (0.0 = deterministic, 2.0 = very random)",
				property_name = "temperature",
				min_value = 0.0,
				max_value = 2.0,
				step_value = 0.1,
				digits = 1,
				default_value = 0.0
			};
			temp_widget.load_options(options);
			rows.add(temp_widget);

			var top_p_widget = new OptionFloatWidget() {
				title = "Top P",
				subtitle = "Nucleus sampling - considers tokens with cumulative probability up to this value",
				property_name = "top_p",
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.9
			};
			top_p_widget.load_options(options);
			rows.add(top_p_widget);

			var top_k_widget = new OptionIntWidget() {
				title = "Top K",
				subtitle = "Limits sampling to top K most likely tokens",
				property_name = "top_k",
				min_value = 1.0,
				max_value = 1000.0,
				default_value = 40.0
			};
			top_k_widget.load_options(options);
			rows.add(top_k_widget);

			var num_ctx_widget = new OptionIntWidget() {
				title = "Num Ctx",
				subtitle = "Context window size - number of tokens the model can consider",
				property_name = "num_ctx",
				min_value = 1.0,
				max_value = 1000000.0,
				default_value = 2048.0
			};
			num_ctx_widget.load_options(options);
			rows.add(num_ctx_widget);

			var num_predict_widget = new OptionIntWidget() {
				title = "Num Predict",
				subtitle = "Maximum number of tokens to generate (-1 = no limit)",
				property_name = "num_predict",
				min_value = 1.0,
				max_value = 1000000.0,
				default_value = -1.0
			};
			num_predict_widget.load_options(options);
			rows.add(num_predict_widget);

			var repeat_penalty_widget = new OptionFloatWidget() {
				title = "Repeat Penalty",
				subtitle = "Penalty for repeating tokens (1.0 = no penalty, >1.0 = penalty)",
				property_name = "repeat_penalty",
				min_value = 0.1,
				max_value = 10.0,
				step_value = 0.1,
				digits = 1,
				default_value = 1.1
			};
			repeat_penalty_widget.load_options(options);
			rows.add(repeat_penalty_widget);

			var min_p_widget = new OptionFloatWidget() {
				title = "Min P",
				subtitle = "Minimum probability threshold for token selection",
				property_name = "min_p",
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.0
			};
			min_p_widget.load_options(options);
			rows.add(min_p_widget);

			var seed_widget = new OptionIntWidget() {
				title = "Seed",
				subtitle = "Random seed for reproducible outputs (-1 = random)",
				property_name = "seed",
				min_value = -1.0,
				max_value = 2147483647.0,
				default_value = -1.0
			};
			seed_widget.load_options(options);
			rows.add(seed_widget);

			var stop_widget = new OptionStringWidget() {
				title = "Stop",
				subtitle = "Stop sequences that cause generation to stop (comma-separated)",
				property_name = "stop",
				placeholder_text = "(optional)"
			};
			stop_widget.load_options(options);
			rows.add(stop_widget);

			return rows;
		}
	}
}
		{
			var temp_widget = new OptionFloatWidget() {
				title = "Temperature",
				subtitle = "Controls randomness in output (0.0 = deterministic, 2.0 = very random)",
				property_name = "temperature",
				min_value = 0.0,
				max_value = 2.0,
				step_value = 0.1,
				digits = 1,
				default_value = 0.0
			};
			temp_widget.load_options(options);
			this.append(temp_widget);
			this.option_rows.add(temp_widget);

			var top_p_widget = new OptionFloatWidget() {
				title = "Top P",
				subtitle = "Nucleus sampling - considers tokens with cumulative probability up to this value",
				property_name = "top_p",
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.9
			};
			top_p_widget.load_options(options);
			this.append(top_p_widget);
			this.option_rows.add(top_p_widget);

			var top_k_widget = new OptionIntWidget() {
				title = "Top K",
				subtitle = "Limits sampling to top K most likely tokens",
				property_name = "top_k",
				min_value = 1.0,
				max_value = 1000.0,
				default_value = 40.0
			};
			top_k_widget.load_options(options);
			this.append(top_k_widget);
			this.option_rows.add(top_k_widget);

			var num_ctx_widget = new OptionIntWidget() {
				title = "Num Ctx",
				subtitle = "Context window size - number of tokens the model can consider",
				property_name = "num_ctx",
				min_value = 1.0,
				max_value = 1000000.0,
				default_value = 2048.0
			};
			num_ctx_widget.load_options(options);
			this.append(num_ctx_widget);
			this.option_rows.add(num_ctx_widget);

			var num_predict_widget = new OptionIntWidget() {
				title = "Num Predict",
				subtitle = "Maximum number of tokens to generate (-1 = no limit)",
				property_name = "num_predict",
				min_value = 1.0,
				max_value = 1000000.0,
				default_value = -1.0
			};
			num_predict_widget.load_options(options);
			this.append(num_predict_widget);
			this.option_rows.add(num_predict_widget);

			var repeat_penalty_widget = new OptionFloatWidget() {
				title = "Repeat Penalty",
				subtitle = "Penalty for repeating tokens (1.0 = no penalty, >1.0 = penalty)",
				property_name = "repeat_penalty",
				min_value = 0.1,
				max_value = 10.0,
				step_value = 0.1,
				digits = 1,
				default_value = 1.1
			};
			repeat_penalty_widget.load_options(options);
			this.append(repeat_penalty_widget);
			this.option_rows.add(repeat_penalty_widget);

			var min_p_widget = new OptionFloatWidget() {
				title = "Min P",
				subtitle = "Minimum probability threshold for token selection",
				property_name = "min_p",
				min_value = 0.0,
				max_value = 1.0,
				step_value = 0.01,
				digits = 2,
				default_value = 0.0
			};
			min_p_widget.load_options(options);
			this.append(min_p_widget);
			this.option_rows.add(min_p_widget);

			var seed_widget = new OptionIntWidget() {
				title = "Seed",
				subtitle = "Random seed for reproducible outputs (-1 = random)",
				property_name = "seed",
				min_value = -1.0,
				max_value = 2147483647.0,
				default_value = -1.0
			};
			seed_widget.load_options(options);
			this.append(seed_widget);
			this.option_rows.add(seed_widget);

			var stop_widget = new OptionStringWidget() {
				title = "Stop",
				subtitle = "Stop sequences that cause generation to stop (comma-separated)",
				property_name = "stop",
				placeholder_text = "(optional)"
			};
			stop_widget.load_options(options);
			this.append(stop_widget);
			this.option_rows.add(stop_widget);
		}

		public void load_options(OLLMchat.Call.Options options)
		{
			foreach (var row in this.option_rows) {
				row.load_options(options);
			}
		}

		public void save_options(OLLMchat.Call.Options options)
		{
			foreach (var row in this.option_rows) {
				row.save_options(options);
			}
		}
	}
}

