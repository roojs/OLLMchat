# All-in-one OLLMchat RPM. Same spec on Fedora 44 and openSUSE Tumbleweed.
# Fedora CI produces *.fc44.*.rpm; openSUSE CI omits %{dist} so repos can
# publish the same spec's output into rpm/tumbleweed/ without a .fc tag.
#
# Build with:
#   rpmbuild -bb --define "ollmchat_version 1.2.5~alpha" packaging/rpm/ollmchat.spec
#   rpmbuild -bb --without local_gguf --define "ollmchat_version 1.2.5~alpha" ...

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
BuildRequires: pkgconfig(openblas)
BuildRequires: pkgconfig(lapack)
%if %{with local_gguf}
BuildRequires: pkgconfig(llama)
%endif

Requires: bubblewrap

%if %{without local_gguf}
Conflicts: ollmchat
%else
Conflicts: ollmchat-remote-only
%endif

%description
OLLMchat is a GTK chat application with LLM access, tool integration,
and embeddable libraries for other applications.

%if %{with local_gguf}
This all-in-one package bundles the application, shared libraries,
GObject introspection data, and command-line tools. It is built with
libllama for local GGUF embedding and chat in addition to Ollama,
OpenAI-compatible HTTP APIs, and other remote backends.
%else
This all-in-one package is built without libllama: use Ollama,
OpenAI-compatible HTTP APIs, and other remote backends only — no local
GGUF inference.
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
rm -f %{buildroot}%{_bindir}/oc-diff
rm -f %{buildroot}%{_bindir}/oc-local-gguf-chat
rm -f %{buildroot}%{_bindir}/oc-local-gguf-embed
rm -f %{buildroot}%{_bindir}/oc-vala-ternary-bug
rm -f %{buildroot}%{_bindir}/oc-vector-index
rm -f %{buildroot}%{_bindir}/oc-vector-search
rm -rf %{buildroot}%{_datadir}/doc/ollmchat
rm -rf %{buildroot}%{_includedir}

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

%changelog
