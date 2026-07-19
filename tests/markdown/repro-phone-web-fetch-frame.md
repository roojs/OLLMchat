# Repro: phone session 05-39-23.json ui msg 61 (web_fetch markdown frame, ~9KB)

```markdown.oc-frame-success.collapsed web_fetch - response (markdown)
259787 – (CVE-2025-66286) [WPE][GTK] Certain connections to remote sites cannot 

be intercepted using WebKitWebPage::send-request signal

[ WebKit Bugzilla](./) 

- [New](enter_bug.cgi)

- [Browse](describecomponents.cgi)

- [Search+](query.cgi?format=advanced)

- Log In 

[×](#) Sign in with GitHub or

Remember my login 

[Create Account](/createaccount.cgi) · [Forgot Password](show_bug.cgi?id=259787&GoAheadAndLogIn=1#forgot) 
## Forgotten password account recovery

- 
NEW[259787](show_bug.cgi?id=259787) CVE-2025-66286 [WPE][GTK] Certain connections 

to remote sites cannot be intercepted using WebKitWebPage::send-request signal 

```https://bugs.webkit.org/show_bug.cgi?id=259787```

[Summary](page.cgi?id=fields.html#short_desc "The bug summary is a short sentence which succinctly describes what the bug is
about.")[WPE][GTK] Certain connections to remote sites cannot be intercepted using 

We... 

Albrecht Dreß 

[Reported](show_bug.cgi?id=259787#c0) 2023-08-03 11:40:54 PDT 

Created [attachment 467194](attachment.cgi?id=467194 "sample application and HTML test input to reproduce the issue") 

[[details]](attachment.cgi?id=467194&action=edit "sample application and HTML test input to reproduce the issue")sample 

application and HTML test input to reproduce the issueOS version: Debian Bookworm/x86_64Webkit 

GTK package: libwebkit2gtk-4.1 v. 2.40.3-2~deb12u2Overview:=========Even if the request 

to access a remote site is intercepted in the WebPage::send-request signal handler, 

a socket connection is opened and –if applicable– the TLS handshake is performed. 

If the access is triggered e.g. by malicious HTML content in an e-mail, this will 

already give the attacker valuable information, so this might (should?) be considered 

a security bug.Steps to Reproduce:===================See the attached sample code 

package "sample.tar.gz" (note: tested on Debian Bookworm, should work similarly on 

other Linux systems):(1) Unpack the sampleUnpack the package, cd into the folder 

“sample”, and say “make”(2) Log network trafficIn an other terminal, start 

“tcpdump” or a similar tool to listen on ports 80/tcp and 443/tcp, e.g.: sudo 

tcpdump -vvv -K -X \\( tcp port 80 or tcp port 443 \\)(3) Run test applicationIn 

“sample” run the application to display the included HTML file: ./samp-main Test.htmlThe 

application prints (time stamps omitted)--8<-------------------------webkit_web_extension_initialize: 

done!web_page_created_cb: page 10 created for (null)send_request_cb: uri
'[http://ftp.de.debian.org/debian/doc/00-INDEX](http://ftp.de.debian.org/debian/doc/00-INDEX)' 

caught, redirect to 'about:blank', stop event emission--8<-------------------------The 

HTML contains two “link” containers (preconnect, stylesheet) triggering this 

event without any further user interaction. The tcpdump log shows a connect() to 

the remote site.(4) Click linkClick on the link in the window. The application
prints--8<-------------------------send_request_cb: uri '[https://www.posteo.de/](https://www.posteo.de/)' 

caught, redirect to 'about:blank', stop event emission--8<-------------------------The 

tcpdump log shows that the connection opened in step (3) is closed, a new connect() 

to www.posteo.de is opened, and the full (!) TLS handshake is performed.The sample 

package contains the tcpdump log in the file tcpdump.log:\* start the test application 

at 19:06:59\* click the link at 19:07:39Expected Results:=================No connection 

to the remote site must be opened, and in particular no TLS handshake must occur 

if the WebPage::send-request signal handler redirects the request to a different 

location.Speculation: the connection is established before the WebPage::send-request 

is emitted, resulting in this behavior. 

| Attachments                                                                                                                                                                                                                                                                     |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [ **sample application and HTML test input to reproduce the issue**](attachment.cgi?id=467194 "View the content of the attachment") (14.85 KB, application/gzip) <br> [2023-08-03 11:40 PDT](#attach_467194 "Go to the comment associated with the attachment"), Albrecht Dreß | *no flags* |  |
| [Details](attachment.cgi?id=467194&action=edit)                                                                                                                                                                                                                                 |            |
| [View All](attachment.cgi?bugid=259787&action=viewall) [Add attachment](attachment.cgi?bugid=259787&action=enter) *proposed patch, testcase, etc.*                                                                                                                              |

Michael Catanzaro 

[Comment 1](show_bug.cgi?id=259787#c1) 2025-07-09 07:33:25 PDT 

There is a corresponding Evolution issue report:
[https://gitlab.gnome.org/GNOME/evolution/-/issues/2727](https://gitlab.gnome.org/GNOME/evolution/-/issues/2727)But 

I think this bug report contains everything we need to know. send-request is indeed 

supposed to be emitted, allowing the application to stop the TCP connection before 

it happens. Evidently something is wrong. 

Michael Catanzaro 

[Comment 2](show_bug.cgi?id=259787#c2) 2025-07-09 07:57:49 PDT 

Your test cases uses rel="preconnect" and rel="stylesheet". There are a bunch of 

other cases that we should test as
well:[https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/rel](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/rel)dns-prefetch, 

icon, modulepreload, pingback, prefetch, preload, prerenderHopefully these will all 

be fixable in one place and not require separate fixes. 

Albrecht Dreß 

[Comment 3](show_bug.cgi?id=259787#c3) 2025-07-09 12:13:56 PDT 

Hi, great that someone takes care of this rather old bug!> Your test cases uses rel="preconnect" 

and rel="stylesheet". There are a bunch of other cases that we should test as well:I 

know – my example basically should only demonstrate that an attacker could exploit 

the bug both without and with any user interaction. There are of course plenty of 

other options for him to “use” it… 

beanbo 

[Comment 4](show_bug.cgi?id=259787#c4) 2025-07-09 14:11:09 PDT 

I already reported this issue as a security issue of Webkit and got no response... 

Michael Catanzaro 

[Comment 5](show_bug.cgi?id=259787#c5) 2025-07-09 14:57:02 PDT 

\*\*\* [Bug 287218](show_bug.cgi?id=287218 "RESOLVED DUPLICATE") has been marked 

as a duplicate of this bug. \*\*\* 

Radar WebKit Bug Importer 

[Comment 6](show_bug.cgi?id=259787#c6) 2025-07-10 05:35:36 PDT 

<[rdar://problem/155518218](rdar://problem/155518218)> 

renrenking86 

[Comment 7](show_bug.cgi?id=259787#c7) 2025-07-17 02:31:35 PDT 

Comment on [attachment 467194](attachment.cgi?id=467194 "sample application and HTML test input to reproduce the issue") 

[[details]](attachment.cgi?id=467194&action=edit "sample application and HTML test input to reproduce the issue")sample 

application and HTML test input to reproduce the issue[renrengornica86@gmail.com](mailto:renrengornica86@gmail.com) 

renrenking86 

[Comment 8](show_bug.cgi?id=259787#c8) 2025-07-17 02:31:58 PDT 

9ok 

Michael Catanzaro 

[Comment 9](show_bug.cgi?id=259787#c9) 2025-07-19 07:27:03 PDT 

rel="dns-prefetch" might be tricky, because that is not an HTTP request, so we \*can't\* 

emit send-request. In [https://gitlab.gnome.org/GNOME/evolution/-/issues/3095](https://gitlab.gnome.org/GNOME/evolution/-/issues/3095) 

I indicated that we do not need to bring back the enable-dns-prefetching setting, 

but I think this is wrong. We will need to undeprecate it and implement it. (Currently, 

there is no way to control it.)Moreover, in [https://gitlab.gnome.org/GNOME/balsa/-/issues/99](https://gitlab.gnome.org/GNOME/balsa/-/issues/99) 

and [https://gitlab.gnome.org/GNOME/geary/-/issues/1680](https://gitlab.gnome.org/GNOME/geary/-/issues/1680), 

Mike discovered that rel="preconnect" only creates a TLS connection, not an HTTP 

request. So again, relying on send-request won't be sufficient. We'll need yet another 

[Truncated: response had 759 lines; showing the first 200 lines only. Do not pull large page slices here (e.g. curl piped to head or wide ranges); that still floods context. For a targeted follow-up via run_command, use a narrow pipeline — for example curl -sL 'https://bugs.webkit.org/show_bug.cgi?id=259787' | grep -E 'YourPattern' — so only matching lines are returned. That run_command must include "network": true (curl needs outbound network; the user may need to approve).]

```
