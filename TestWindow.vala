namespace OLLMchat 
{
	int main(string[] args)
	{
		// Set up debug handler to print all GLib.debug output to stderr
		GLib.Log.set_default_handler((dom, lvl, msg) => {
			stderr.printf("%s: %s : %s\n", (new DateTime.now_local()).format("%H:%M:%S.%f"), lvl.to_string(), msg);
		});

		var app = new Gtk.Application("org.roojs.roobuilder.test", GLib.ApplicationFlags.DEFAULT_FLAGS);

		app.activate.connect(() => {
			var window = new TestWindow(app);
			app.add_window(window);
			window.present();
		});

		return app.run(args);
	}

	/**
	 * Test window for testing ChatWidget.
	 * 
	 * This is a simple wrapper around ChatWidget for standalone testing.
	 * It includes a main() function and can be compiled independently.
	 * 
	 * @since 1.0
	 */
	public class TestWindow : Gtk.Window
	{
		private UI.ChatWidget chat_widget;

		/**
		 * Creates a new TestWindow instance.
		 * 
		 * @param app The Gtk.Application instance
		 * @since 1.0
		 */
		public TestWindow(Gtk.Application app)
		{
			this.title = "OLL Chat Test";
			this.set_default_size(800, 600);

			// Read configuration from ~/.config/ollmchat/ollama.json
			// Example file content:
			/* 
{
	"url": "http://192.168.88.14:11434/api",
	"model": "MichelRosselli/GLM-4.5-Air:Q4_K_M",
	"api_key": "your-api-key-here"
}
			 */
			var parser = new Json.Parser();
			try {
				parser.load_from_file(Path.build_filename(
					GLib.Environment.get_home_dir(), ".config", "ollmchat", "ollama.json")
				);
			} catch (GLib.Error e) {
				GLib.error("Failed to load config file: %s", e.message);
			}
			var obj = parser.get_root().get_object();

			// Create CodeAssistant prompt generator with dummy provider
			var code_assistant = new Prompt.CodeAssistant(new Prompt.CodeAssistantProviderDummy()) {
				shell = GLib.Environment.get_variable("SHELL") ?? "/usr/bin/bash",
			};
			
			var client = new Ollama.Client() {
				url = obj.get_string_member("url"),
				model = obj.get_string_member("model"),
				api_key = obj.get_string_member("api_key"),
				stream = true,
				think =  obj.has_member("think") ?  obj.get_boolean_member("api_key") : false,
				keep_alive = "5m",
				prompt_assistant = code_assistant
			};
			
			// Add tools to the client
			client.addTool(new Tools.ReadFile(client));
			client.addTool(new Tools.EditFile(client));

			// Create chat widget with client
			this.chat_widget = new UI.ChatWidget(client) {
				default_message = "Please read the first few lines of /var/log/syslog and tell me what you think the hostname of this system is"
			};
			
			// Create ChatView permission provider and set it on the client
			var permission_provider = new ChatPermission.ChatView(
				this.chat_widget,
				Path.build_filename(
					GLib.Environment.get_home_dir(), ".config", "ollmchat"
				)) {
				application = app as GLib.Application,
				
			};
			client.permission_provider = permission_provider;
			
			// Track if we've sent the first query to automatically send the reply
			bool first_response_received = false;

		// Connect widget signals for testing (optional: print to stdout)
			this.chat_widget.message_sent.connect((text) => {
				stdout.printf("Message sent: %s\n", text);
			});

			this.chat_widget.response_received.connect((text) => {
				stdout.printf("Response received: %s\n", text);
				// Fill in the second prompt in the input field after first response
				if (!first_response_received) {
					first_response_received = true;
					// Set the second prompt in the input field (user must click send)
					this.chat_widget.default_message = "Please read the first few lines of /var/log/dmesg and tell me what kernel version we are running";
				}
			});

			this.chat_widget.error_occurred.connect((error) => {
				stderr.printf("Error: %s\n", error);
			});

			// Set window child
			this.set_child(this.chat_widget);
		}
	}
}

