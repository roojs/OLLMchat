namespace OLLMchat.Tools
{
	/**
	 * Dummy implementation of PermissionProvider for testing.
	 * 
	 * Logs all permission requests using GLib.debug().
	 * Always allows READ requests, denies WRITE and EXECUTE requests.
	 */
	public class PermissionProviderDummy : PermissionProvider
	{
		public PermissionProviderDummy(string directory = "")
		{
			base(directory);
		}
		
		protected override PermissionResponse request_user(Ollama.Tool tool)
		{
			string op_str = tool.permission_operation == Operation.READ ? "READ" : (tool.permission_operation == Operation.WRITE ? "WRITE" : "EXECUTE");
			GLib.debug("Permission requested for tool '%s' on '%s' (%s): %s", tool.name, tool.permission_target_path, op_str, tool.permission_question);
			// Always allow READ requests, deny others
			if (tool.permission_operation == Operation.READ) {
				return PermissionResponse.ALLOW_ONCE;
			}
			return PermissionResponse.DENY_ONCE;
		}
	}
}

