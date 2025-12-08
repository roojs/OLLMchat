# Debian Package Building Guide

This document provides instructions for building Debian packages for OLLMchat.

## Package Structure

The source package builds the following binary packages:

### Runtime Libraries
- **libocmarkdown1** - Base markdown parsing library (libocmarkdown.so)
- **libocmarkdowngtk1** - GTK markdown rendering library (libocmarkdowngtk.so)
- **libollmchat1** - Base LLM library (libollmchat.so), GTK widgets (libollmchatgtk.so), and SQLite library (libocsqlite.so)

### Development Packages
- **libocmarkdown-dev** - Development files for libocmarkdown (headers, VAPI files)
- **libocmarkdowngtk-dev** - Development files for libocmarkdowngtk (headers, VAPI files)
- **libollmchat-dev** - Development files for libollmchat, libollmchatgtk, and libocsqlite (headers, VAPI files)

### Tools and Documentation
- **ollmchat-tools** - Command-line tools (oc-md2html, oc-html2md) installed to `/usr/bin`
- **ollmchat-doc** - Test executables (oc-test-cli, oc-test-window, oc-markdown-test) installed to `/usr/share/doc/ollmchat`

## Prerequisites

### Build Dependencies

Install the required build dependencies:

```bash
sudo apt-get update
sudo apt-get install build-essential devscripts debhelper meson ninja-build \
  pkg-config valac libgee-0.8-dev libglib2.0-dev libgobject-2.0-dev \
  libgio-2.0-dev libjson-glib-dev libsoup-3.0-dev libxml2-dev libsqlite3-dev \
  libgtk-4-dev libgtksourceview-5-dev libadwaita-1-dev gobject-introspection \
  libgirepository1.0-dev
```

## Building Packages

### Building Binary Packages

To build all binary packages:

```bash
dpkg-buildpackage -us -uc -b
```

This will:
1. Configure the build using Meson
2. Compile all libraries and executables
3. Install files to a temporary directory
4. Package files into separate .deb packages
5. Create the packages in the parent directory

### Building Source Package

To build a source package (for uploading to a PPA or repository):

```bash
dpkg-buildpackage -us -uc -S
```

### Building with Debug Symbols

To build packages with debug symbols:

```bash
DEB_BUILD_OPTIONS="debug" dpkg-buildpackage -us -uc -b
```

### Clean Build

To perform a clean build (removes build directory first):

```bash
debian/rules clean
dpkg-buildpackage -us -uc -b
```

## Package Contents

### Install Locations

Files are installed to standard Debian locations:

- **Libraries**: `/usr/lib/<arch>/` (e.g., `/usr/lib/x86_64-linux-gnu/`)
- **Headers**: `/usr/include/`
- **VAPI files**: `/usr/share/vala/vapi/`
- **GIR files**: `/usr/share/gir-1.0/`
- **Typelib files**: `/usr/lib/<arch>/girepository-1.0/`
- **Tools**: `/usr/bin/` (oc-md2html, oc-html2md)
- **Test executables**: `/usr/share/doc/ollmchat/` (oc-test-*)

### Package Dependencies

- `libocmarkdown1` has no library dependencies (only system libraries)
- `libocmarkdowngtk1` depends on `libocmarkdown1`
- `libollmchat1` includes all three libraries (ollmchat, ollmchatgtk, ocsqlite)
- `ollmchat-tools` depends on `libocmarkdown1`
- Development packages depend on their corresponding runtime packages

## Customizing the Build

### Changing Install Prefix

The build uses `/usr` as the prefix. To change this, modify `debian/rules`:

```makefile
override_dh_auto_configure:
	meson setup build --prefix=/usr/local
```

### Modifying Package Contents

To change which files go into which packages, edit the corresponding `.install` files in the `debian/` directory:

- `debian/libocmarkdown1.install` - Runtime files for libocmarkdown
- `debian/libocmarkdown-dev.install` - Development files for libocmarkdown
- `debian/libocmarkdowngtk1.install` - Runtime files for libocmarkdowngtk
- `debian/libocmarkdowngtk-dev.install` - Development files for libocmarkdowngtk
- `debian/libollmchat1.install` - Runtime files for libollmchat
- `debian/libollmchat-dev.install` - Development files for libollmchat
- `debian/ollmchat-tools.install` - Command-line tools
- `debian/ollmchat-doc.install` - Test executables

## Testing Packages

### Installing Packages Locally

After building, install the packages:

```bash
sudo dpkg -i ../libocmarkdown1_*.deb
sudo dpkg -i ../libocmarkdown-dev_*.deb
sudo dpkg -i ../libocmarkdowngtk1_*.deb
sudo dpkg -i ../libocmarkdowngtk-dev_*.deb
sudo dpkg -i ../libollmchat1_*.deb
sudo dpkg -i ../libollmchat-dev_*.deb
sudo dpkg -i ../ollmchat-tools_*.deb
sudo dpkg -i ../ollmchat-doc_*.deb
```

Or install all at once:

```bash
sudo dpkg -i ../*.deb
```

### Verifying Installation

Check that libraries are installed:

```bash
dpkg -L libocmarkdown1
dpkg -L libollmchat1
```

Test the command-line tools:

```bash
oc-md2html --help
oc-html2md --help
```

## Troubleshooting

### Build Fails with Missing Dependencies

Ensure all build dependencies are installed (see Prerequisites section).

### Libraries Not Found at Runtime

Make sure the runtime packages are installed. Development packages only contain headers and VAPI files, not the actual libraries.

### VAPI Files Not Found

VAPI files are installed to `/usr/share/vala/vapi/`. Ensure the development packages are installed and that your Vala compiler can find them (they should be found automatically).

### GIR/Typelib Issues

GIR and typelib files are generated during the build. If they're missing, check that:
1. `gobject-introspection` is installed
2. The build completed successfully
3. The runtime packages are installed

## Updating Package Version

To update the package version, edit `debian/changelog`:

```bash
dch -i  # Interactive editor
# or
dch -v 1.0.1-1 "New upstream release"
```

Then rebuild the packages.

## Uploading to a PPA

1. Build the source package:
   ```bash
   dpkg-buildpackage -S
   ```

2. Upload to PPA:
   ```bash
   dput ppa:your-ppa/ollmchat ../ollmchat_*.changes
   ```

## Additional Resources

- [Debian Packaging Guide](https://www.debian.org/doc/manuals/packaging-tutorial/packaging-tutorial.en.pdf)
- [Meson Build System](https://mesonbuild.com/)
- [Debian Policy Manual](https://www.debian.org/doc/debian-policy/)
