/*
 * Stubs so the probe can compile the real Linux WebDriver and WebViewAuto
 * without the rest of libocwebkit. Browser.web_view is the only member
 * WebViewAuto reads. A11y fields are the ones WebDriver.fill / press use.
 */

public class OLLMwebkit.Browser : GLib.Object
{
	public WebKit.WebView web_view { get; set; }
}

public class OLLMwebkit.A11yNode : GLib.Object
{
	public string fill_key { get; set; default = ""; }
	public int press_id { get; set; default = 0; }
	public int x { get; set; default = 0; }
	public int y { get; set; default = 0; }
	public int width { get; set; default = 0; }
	public int height { get; set; default = 0; }
}

public class OLLMwebkit.A11y : GLib.Object
{
	public Gee.ArrayList<OLLMwebkit.A11yNode> nodes {
		get; set; default = new Gee.ArrayList<OLLMwebkit.A11yNode>();
	}
}
