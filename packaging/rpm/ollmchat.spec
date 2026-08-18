# Split library RPMs when built with local GGUF (default).
# --without local_gguf produces a single ollmchat-remote-only package that
# conflicts with the split libraries. Same spec on Fedora 44 and openSUSE
# Tumbleweed. Fedora CI produces *.fc44.*.rpm; openSUSE CI omits %{dist}.
#
# Build with:
#   rpmbuild -bb --define "ollmchat_version 1.3.0" packaging/rpm/ollmchat.spec
#   rpmbuild -bb --without local_gguf --define "ollmchat_version 1.3.0" ...

%bcond_without local_gguf

Name: ollmchat%{?without_local_gguf:-remote-only}
Version: %{ollmchat_version}
Release: 1%{?dist}
Summary: LLM chat application for GNOME
License: LGPLv3+
URL: https://github.com/roojs/OLLMchat
Source0: ollmchat-%{version}.tar.gz

BuildRequires: meson
BuildRequires: ninja-build
BuildRequires: gcc
BuildRequires: gcc-c++
BuildRequires: vala
BuildRequires: desktop-file-utils
BuildRequires: gobject-introspection
BuildRequires: gobject-introspection-devel
BuildRequires: faiss-devel
BuildRequires: pkgconfig(gee-0.8)
BuildRequires: pkgconfig(glib-2.0)
BuildRequires: pkgconfig(json-glib-1.0)
BuildRequires: pkgconfig(libsoup-3.0)
BuildRequires: pkgconfig(libxml-2.0)
BuildRequires: pkgconfig(sqlite3)
BuildRequires: pkgconfig(gtk4)
BuildRequires: pkgconfig(gtksourceview-5)
BuildRequires: pkgconfig(libadwaita-1)
BuildRequires: pkgconfig(webkitgtk-6.0)
BuildRequires: pkgconfig(atspi-2)
BuildRequires: pkgconfig(tree-sitter)
BuildRequires: pkgconfig(libseccomp)
BuildRequires: pkgconfig(libgit2-glib-1.0)
%if 0%{?fedora}
BuildRequires: pkgconfig(flexiblas)
%else
BuildRequires: pkgconfig(openblas)
%endif
BuildRequires: pkgconfig(lapack)
%if %{with local_gguf}
BuildRequires: pkgconfig(llama)
%endif

%if %{with local_gguf}
Requires: bubblewrap
Requires: libocsqlite%{?_isa} = %{version}-%{release}
Requires: libocrpc%{?_isa} = %{version}-%{release}
Requires: libocmarkdown%{?_isa} = %{version}-%{release}
Requires: libollamaweb%{?_isa} = %{version}-%{release}
Requires: libochf%{?_isa} = %{version}-%{release}
Requires: libocmarkdowngtk%{?_isa} = %{version}-%{release}
Requires: libocfiles%{?_isa} = %{version}-%{release}
Requires: libollmchat%{?_isa} = %{version}-%{release}
Requires: libocwebkit%{?_isa} = %{version}-%{release}
Requires: libocvector2%{?_isa} = %{version}-%{release}
Requires: libocbwrap%{?_isa} = %{version}-%{release}
Requires: libocmcp%{?_isa} = %{version}-%{release}
Requires: liboctools%{?_isa} = %{version}-%{release}
Requires: liboccoder%{?_isa} = %{version}-%{release}
Requires: libollmchatgtk%{?_isa} = %{version}-%{release}
Recommends: ollmchat-tools
Conflicts: ollmchat-remote-only
%else
Requires: bubblewrap
Conflicts: ollmchat,
           ollmchat-tools,
           ollmchat-doc,
           libocsqlite,
           libocsqlite-devel,
           libocrpc,
           libocrpc-devel,
           libocmarkdown,
           libocmarkdown-devel,
           libollamaweb,
           libollamaweb-devel,
           libochf,
           libochf-devel,
           libocmarkdowngtk,
           libocmarkdowngtk-devel,
           libocfiles,
           libocfiles-devel,
           libollmchat,
           libollmchat-devel,
           libocwebkit,
           libocwebkit-devel,
           libocvector2,
           libocvector2-devel,
           libocbwrap,
           libocbwrap-devel,
           libocmcp,
           libocmcp-devel,
           liboctools,
           liboctools-devel,
           liboccoder,
           liboccoder-devel,
           libollmchatgtk,
           libollmchatgtk-devel
%endif

%description
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

%if %{with local_gguf}
This package contains the ollmchat application and the ollmfilesd file
daemon. Shared libraries and development files ship in separate packages
(libocrpc, libocrpc-devel, and so on).
%else
This all-in-one package is built without libllama: use Ollama,
OpenAI-compatible HTTP APIs, and other remote backends only — no local
GGUF inference.
%endif

%if %{with local_gguf}
%package -n libocsqlite
Summary: SQLite helper library for OLLMchat
Conflicts: ollmchat-remote-only

%description -n libocsqlite
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libocsqlite.so.

%package -n libocsqlite-devel
Summary: Development files for libocsqlite
Conflicts: ollmchat-remote-only
Requires: libocsqlite%{?_isa} = %{version}-%{release}
Requires: pkgconfig(glib-2.0)
Requires: pkgconfig(sqlite3)

%description -n libocsqlite-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libocsqlite.

%package -n libocrpc
Summary: Binary RPC wire library for OLLMchat
Conflicts: ollmchat-remote-only

%description -n libocrpc
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libocrpc.so.

%package -n libocrpc-devel
Summary: Development files for libocrpc
Conflicts: ollmchat-remote-only
Requires: libocrpc%{?_isa} = %{version}-%{release}
Requires: pkgconfig(gee-0.8)
Requires: pkgconfig(glib-2.0)
Requires: pkgconfig(json-glib-1.0)
Requires: pkgconfig(libsoup-3.0)

%description -n libocrpc-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libocrpc.
Install this to reuse the OLLMrpc binary protocol from other applications.

%package -n libocmarkdown
Summary: Markdown parsing library
Conflicts: ollmchat-remote-only

%description -n libocmarkdown
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libocmarkdown.so.

%package -n libocmarkdown-devel
Summary: Development files for libocmarkdown
Conflicts: ollmchat-remote-only
Requires: libocmarkdown%{?_isa} = %{version}-%{release}
Requires: pkgconfig(gee-0.8)
Requires: pkgconfig(glib-2.0)

%description -n libocmarkdown-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libocmarkdown.

%package -n libollamaweb
Summary: Ollama HTTP client library for OLLMchat
Conflicts: ollmchat-remote-only

%description -n libollamaweb
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libollamaweb.so.

%package -n libollamaweb-devel
Summary: Development files for libollamaweb
Conflicts: ollmchat-remote-only
Requires: libollamaweb%{?_isa} = %{version}-%{release}
Requires: pkgconfig(gee-0.8)
Requires: pkgconfig(glib-2.0)
Requires: pkgconfig(json-glib-1.0)
Requires: pkgconfig(libsoup-3.0)
Requires: pkgconfig(libxml-2.0)

%description -n libollamaweb-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libollamaweb.

%package -n libochf
Summary: Hugging Face Hub catalog library for OLLMchat
Conflicts: ollmchat-remote-only
Requires: libocrpc%{?_isa} = %{version}-%{release}

%description -n libochf
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libochf.so.

%package -n libochf-devel
Summary: Development files for libochf
Conflicts: ollmchat-remote-only
Requires: libochf%{?_isa} = %{version}-%{release}
Requires: libocrpc-devel%{?_isa} = %{version}-%{release}

%description -n libochf-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libochf.

%package -n libocmarkdowngtk
Summary: GTK markdown rendering library
Conflicts: ollmchat-remote-only
Requires: libocmarkdown%{?_isa} = %{version}-%{release}

%description -n libocmarkdowngtk
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libocmarkdowngtk.so.

%package -n libocmarkdowngtk-devel
Summary: Development files for libocmarkdowngtk
Conflicts: ollmchat-remote-only
Requires: libocmarkdowngtk%{?_isa} = %{version}-%{release}
Requires: libocmarkdown-devel%{?_isa} = %{version}-%{release}
Requires: pkgconfig(gtk4)
Requires: pkgconfig(gtksourceview-5)

%description -n libocmarkdowngtk-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libocmarkdowngtk.

%package -n libocfiles
Summary: File and project management library for OLLMchat
Conflicts: ollmchat-remote-only
Requires: libocsqlite%{?_isa} = %{version}-%{release}
Requires: libocrpc%{?_isa} = %{version}-%{release}

%description -n libocfiles
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libocfiles.so.

%package -n libocfiles-devel
Summary: Development files for libocfiles
Conflicts: ollmchat-remote-only
Requires: libocfiles%{?_isa} = %{version}-%{release}
Requires: libocsqlite-devel%{?_isa} = %{version}-%{release}
Requires: libocrpc-devel%{?_isa} = %{version}-%{release}

%description -n libocfiles-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libocfiles.

%package -n libollmchat
Summary: Base library for Ollama/OpenAI API access
Conflicts: ollmchat-remote-only
Requires: libocsqlite%{?_isa} = %{version}-%{release}
Requires: libocmarkdown%{?_isa} = %{version}-%{release}
Requires: libollamaweb%{?_isa} = %{version}-%{release}
Requires: libocrpc%{?_isa} = %{version}-%{release}

%description -n libollmchat
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libollmchat.so.

%package -n libollmchat-devel
Summary: Development files for libollmchat
Conflicts: ollmchat-remote-only
Requires: libollmchat%{?_isa} = %{version}-%{release}
Requires: libocsqlite-devel%{?_isa} = %{version}-%{release}
Requires: libocmarkdown-devel%{?_isa} = %{version}-%{release}
Requires: libollamaweb-devel%{?_isa} = %{version}-%{release}
Requires: libocrpc-devel%{?_isa} = %{version}-%{release}

%description -n libollmchat-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libollmchat.

%package -n libocwebkit
Summary: WebKitGTK browser-tool library for OLLMchat
Conflicts: ollmchat-remote-only
Requires: libollmchat%{?_isa} = %{version}-%{release}

%description -n libocwebkit
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libocwebkit.so.

%package -n libocwebkit-devel
Summary: Development files for libocwebkit
Conflicts: ollmchat-remote-only
Requires: libocwebkit%{?_isa} = %{version}-%{release}
Requires: libollmchat-devel%{?_isa} = %{version}-%{release}
Requires: pkgconfig(gtk4)
Requires: pkgconfig(webkitgtk-6.0)

%description -n libocwebkit-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libocwebkit.

%package -n libocvector2
Summary: Vector search library for the OLLMchat file daemon
Conflicts: ollmchat-remote-only
Requires: libocsqlite%{?_isa} = %{version}-%{release}
Requires: libollmchat%{?_isa} = %{version}-%{release}

%description -n libocvector2
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libocvector2.so.

%package -n libocvector2-devel
Summary: Development files for libocvector2
Conflicts: ollmchat-remote-only
Requires: libocvector2%{?_isa} = %{version}-%{release}
Requires: libocsqlite-devel%{?_isa} = %{version}-%{release}
Requires: libollmchat-devel%{?_isa} = %{version}-%{release}

%description -n libocvector2-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libocvector2.

%package -n libocbwrap
Summary: Bubblewrap and seccomp helper library for OLLMchat
Conflicts: ollmchat-remote-only
Recommends: bubblewrap

%description -n libocbwrap
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libocbwrap.so.

%package -n libocbwrap-devel
Summary: Development files for libocbwrap
Conflicts: ollmchat-remote-only
Requires: libocbwrap%{?_isa} = %{version}-%{release}
Requires: pkgconfig(gee-0.8)
Requires: pkgconfig(glib-2.0)
Requires: pkgconfig(libseccomp)

%description -n libocbwrap-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libocbwrap.

%package -n libocmcp
Summary: MCP integration library for OLLMchat
Conflicts: ollmchat-remote-only
Requires: libollmchat%{?_isa} = %{version}-%{release}
Requires: libocfiles%{?_isa} = %{version}-%{release}
Requires: libocbwrap%{?_isa} = %{version}-%{release}

%description -n libocmcp
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libocmcp.so.

%package -n libocmcp-devel
Summary: Development files for libocmcp
Conflicts: ollmchat-remote-only
Requires: libocmcp%{?_isa} = %{version}-%{release}
Requires: libollmchat-devel%{?_isa} = %{version}-%{release}
Requires: libocfiles-devel%{?_isa} = %{version}-%{release}
Requires: libocbwrap-devel%{?_isa} = %{version}-%{release}

%description -n libocmcp-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libocmcp.

%package -n liboctools
Summary: LLM tool implementations for OLLMchat
Conflicts: ollmchat-remote-only
Requires: libollmchat%{?_isa} = %{version}-%{release}
Requires: libocfiles%{?_isa} = %{version}-%{release}
Requires: libocmarkdown%{?_isa} = %{version}-%{release}
Requires: libollamaweb%{?_isa} = %{version}-%{release}
Requires: libocrpc%{?_isa} = %{version}-%{release}
Requires: libochf%{?_isa} = %{version}-%{release}
Requires: libocwebkit%{?_isa} = %{version}-%{release}
Requires: libocbwrap%{?_isa} = %{version}-%{release}

%description -n liboctools
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains liboctools.so.

%package -n liboctools-devel
Summary: Development files for liboctools
Conflicts: ollmchat-remote-only
Requires: liboctools%{?_isa} = %{version}-%{release}
Requires: libollmchat-devel%{?_isa} = %{version}-%{release}
Requires: libocfiles-devel%{?_isa} = %{version}-%{release}
Requires: libocmarkdown-devel%{?_isa} = %{version}-%{release}
Requires: libollamaweb-devel%{?_isa} = %{version}-%{release}
Requires: libocrpc-devel%{?_isa} = %{version}-%{release}
Requires: libochf-devel%{?_isa} = %{version}-%{release}
Requires: libocwebkit-devel%{?_isa} = %{version}-%{release}
Requires: libocbwrap-devel%{?_isa} = %{version}-%{release}

%description -n liboctools-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for liboctools.

%package -n liboccoder
Summary: Code editor and agent UI library for OLLMchat
Conflicts: ollmchat-remote-only
Requires: libocsqlite%{?_isa} = %{version}-%{release}
Requires: libocfiles%{?_isa} = %{version}-%{release}
Requires: libollmchat%{?_isa} = %{version}-%{release}
Requires: libocmarkdown%{?_isa} = %{version}-%{release}
Requires: liboctools%{?_isa} = %{version}-%{release}

%description -n liboccoder
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains liboccoder.so.

%package -n liboccoder-devel
Summary: Development files for liboccoder
Conflicts: ollmchat-remote-only
Requires: liboccoder%{?_isa} = %{version}-%{release}
Requires: libocsqlite-devel%{?_isa} = %{version}-%{release}
Requires: libocfiles-devel%{?_isa} = %{version}-%{release}
Requires: libollmchat-devel%{?_isa} = %{version}-%{release}
Requires: libocmarkdown-devel%{?_isa} = %{version}-%{release}
Requires: liboctools-devel%{?_isa} = %{version}-%{release}

%description -n liboccoder-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for liboccoder.

%package -n libollmchatgtk
Summary: GTK chat widget library for OLLMchat
Conflicts: ollmchat-remote-only
Requires: libollmchat%{?_isa} = %{version}-%{release}
Requires: libocmarkdown%{?_isa} = %{version}-%{release}
Requires: libocmarkdowngtk%{?_isa} = %{version}-%{release}

%description -n libollmchatgtk
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains libollmchatgtk.so.

%package -n libollmchatgtk-devel
Summary: Development files for libollmchatgtk
Conflicts: ollmchat-remote-only
Requires: libollmchatgtk%{?_isa} = %{version}-%{release}
Requires: libollmchat-devel%{?_isa} = %{version}-%{release}
Requires: libocmarkdowngtk-devel%{?_isa} = %{version}-%{release}

%description -n libollmchatgtk-devel
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains VAPI and GIR development files for libollmchatgtk.

%package tools
Summary: Command-line tools for OLLMchat
Conflicts: ollmchat-remote-only
Requires: libocmarkdown%{?_isa} = %{version}-%{release}

%description tools
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains oc-md2html and oc-html2md.

%package doc
Summary: Example and test executables for OLLMchat
Conflicts: ollmchat-remote-only

%description doc
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

This package contains example and test executables (oc-test-*, oc-hf,
oc-vector-index, and similar).

%endif

%prep
%autosetup -n ollmchat-%{version}

%build
%meson \
  -Ddocs=false \
  -Dexamples=true \
  -Dtests=false \
%if %{with local_gguf}
  -Dlocal_gguf=enabled
%else
  -Dlocal_gguf=disabled
%endif
%meson_build

%install
%meson_install
rm -f %{buildroot}%{_datadir}/vala/vapi/*-meson.vapi
rm -f %{buildroot}%{_datadir}/vala/vapi/*-meson.deps
%if %{without local_gguf}
rm -f %{buildroot}%{_bindir}/oc-diff
rm -f %{buildroot}%{_bindir}/oc-local-gguf-chat
rm -f %{buildroot}%{_bindir}/oc-local-gguf-embed
rm -f %{buildroot}%{_bindir}/oc-vala-ternary-bug
rm -f %{buildroot}%{_bindir}/oc-vector-index
rm -f %{buildroot}%{_bindir}/oc-vector-search
rm -rf %{buildroot}%{_datadir}/doc/ollmchat
rm -rf %{buildroot}%{_includedir}
%endif

%if %{with local_gguf}
%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_bindir}/ollmchat
%{_bindir}/ollmchat-cli
%{_bindir}/ollmfilesd
%{_datadir}/applications/org.roojs.ollmchat.desktop
%{_datadir}/icons/hicolor/scalable/apps/org.roojs.ollmchat.svg

%files -n libocsqlite
%{_libdir}/libocsqlite.so
%{_libdir}/girepository-1.0/OCSqlite-1.0.typelib

%files -n libocsqlite-devel
%{_datadir}/vala/vapi/ocsqlite.vapi
%{_datadir}/gir-1.0/OCSqlite-1.0.gir

%files -n libocrpc
%{_libdir}/libocrpc.so

%files -n libocrpc-devel
%{_datadir}/vala/vapi/ocrpc.vapi

%files -n libocmarkdown
%{_libdir}/libocmarkdown.so
%{_libdir}/girepository-1.0/OCMarkdown-1.0.typelib

%files -n libocmarkdown-devel
%{_datadir}/vala/vapi/ocmarkdown.vapi
%{_datadir}/gir-1.0/OCMarkdown-1.0.gir

%files -n libollamaweb
%{_libdir}/libollamaweb.so

%files -n libollamaweb-devel
%{_datadir}/vala/vapi/ollamaweb.vapi

%files -n libochf
%{_libdir}/libochf.so

%files -n libochf-devel
%{_datadir}/vala/vapi/ochf.vapi

%files -n libocmarkdowngtk
%{_libdir}/libocmarkdowngtk.so
%{_libdir}/girepository-1.0/OCMarkdownGtk-1.0.typelib

%files -n libocmarkdowngtk-devel
%{_datadir}/vala/vapi/ocmarkdowngtk.vapi
%{_datadir}/gir-1.0/OCMarkdownGtk-1.0.gir

%files -n libocfiles
%{_libdir}/libocfiles.so
%{_libdir}/girepository-1.0/OLLMfiles-1.0.typelib

%files -n libocfiles-devel
%{_datadir}/vala/vapi/ocfiles.vapi
%{_datadir}/gir-1.0/OLLMfiles-1.0.gir

%files -n libollmchat
%{_libdir}/libollmchat.so
%{_libdir}/girepository-1.0/OLLMchat-1.0.typelib

%files -n libollmchat-devel
%{_datadir}/gir-1.0/OLLMchat-1.0.gir
%{_datadir}/vala/vapi/ollmchat.vapi

%files -n libocwebkit
%{_libdir}/libocwebkit.so

%files -n libocwebkit-devel
%{_datadir}/vala/vapi/ocwebkit.vapi

%files -n libocvector2
%{_libdir}/libocvector2.so

%files -n libocvector2-devel
%{_datadir}/vala/vapi/ocvector2.vapi

%files -n libocbwrap
%{_libdir}/libocbwrap.so
%{_libdir}/girepository-1.0/OLLMbwrap-1.0.typelib

%files -n libocbwrap-devel
%{_datadir}/vala/vapi/ocbwrap.vapi
%{_datadir}/gir-1.0/OLLMbwrap-1.0.gir

%files -n libocmcp
%{_libdir}/libocmcp.so

%files -n libocmcp-devel
%{_datadir}/vala/vapi/ocmcp.vapi

%files -n liboctools
%{_libdir}/liboctools.so
%{_libdir}/girepository-1.0/OLLMtools-1.0.typelib

%files -n liboctools-devel
%{_datadir}/vala/vapi/octools.vapi
%{_datadir}/gir-1.0/OLLMtools-1.0.gir

%files -n liboccoder
%{_libdir}/liboccoder.so
%{_libdir}/girepository-1.0/OLLMcoder-1.0.typelib

%files -n liboccoder-devel
%{_datadir}/vala/vapi/occoder.vapi
%{_datadir}/gir-1.0/OLLMcoder-1.0.gir

%files -n libollmchatgtk
%{_libdir}/libollmchatgtk.so
%{_libdir}/girepository-1.0/OLLMchatGtk-1.0.typelib

%files -n libollmchatgtk-devel
%{_datadir}/gir-1.0/OLLMchatGtk-1.0.gir
%{_datadir}/vala/vapi/ollmchatgtk.vapi

%files tools
%{_bindir}/oc-md2html
%{_bindir}/oc-html2md

%files doc
%{_bindir}/oc-local-gguf-chat
%{_bindir}/oc-local-gguf-embed
%{_bindir}/oc-vala-ternary-bug
%{_bindir}/oc-vector-index
%{_bindir}/oc-vector-search
%{_datadir}/doc/ollmchat/oc-*

%else
%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_bindir}/ollmchat
%{_bindir}/ollmchat-cli
%{_bindir}/ollmfilesd
%{_bindir}/oc-md2html
%{_bindir}/oc-html2md
%{_libdir}/liboc*.so*
%{_libdir}/liboll*.so*
%{_datadir}/applications/org.roojs.ollmchat.desktop
%{_datadir}/icons/hicolor/scalable/apps/org.roojs.ollmchat.svg
%{_datadir}/gir-1.0/OC*.gir
%{_datadir}/gir-1.0/OLL*.gir
%{_libdir}/girepository-1.0/OC*.typelib
%{_libdir}/girepository-1.0/OLL*.typelib
%{_datadir}/vala/vapi/oc*.vapi
%{_datadir}/vala/vapi/oll*.vapi
%endif

%changelog
