# Repro: phone session 2026-07-19/05-39-23.json content-stream msg 73
# Truncated mid-token inside unclosed fence (lang c).
# build/examples/oc-markdown-test tests/markdown/repro-phone-unclosed-fence.md
# build/examples/oc-test-gtkmd tests/markdown/repro-phone-unclosed-fence.md
# build/examples/oc-test-gtkmd --history /tmp/ollmchat-phone-sessions/05-39-23.json

Based on my research, here's a comprehensive approach for mitigating LLM browser automation risks using WebKitGTK:

## Browser-Level POST Gating (WebKitGTK)

Since **WebkitGTK 2.35+**, you can use the `WebKitBlockingWebResourceRequest` interface to intercept and control all outgoing requests *before they leave your process*:

### Code Example

```c
// Must be called before webkit_web_view_new() at most once per app
static void init_blocking_interface(void) {
    GInterfaceInfo blocking_info = {
        .interface_init = NULL,  // No interface initialization needed
        .interface_finalize = NULL,
        .interface_data = NULL
    };
    
    webkit_web_view_class_add_interface(
        WEBKIT_WEB_VIEW_GET_CLASS(web_view), &blocking_info);
}

// Then connect to the signal on your WebView instance:
g_signal_connect(video_wewb_view, "blocking-web-resource-request",
                 G_CALLBACK(on_blocking_request), user_data);

G_GNUC_BEGIN_IGNORE_DEPRECATION
GtkCallbackStatus on_blocking_request(WebKitWebView *web_view, 
                                       guint64 request_id, 
                                       WebKitNetworkRequest *request,
                                       gpointer user_data) {
    
    // Block all POST/PUT/DELETE/PATCH requests
    const char *method = webkit_network_request_get_http_method(request);
    
    if (g_strcmp0(method, "POST") == 0 ||
        g_strcmp_