#!/bin/bash

export MSYS="winsymlinks:lnk"
set -eux

# Get all our sources
mkdir -p dl
tr -d '\r' < download.list > download.list.tmp
wget -P dl -i download.list.tmp
rm download.list.tmp

# #Untar them all
mkdir -p srcs
while read f; do
	tar --no-same-owner -xvf "$f" -C srcs
done < <(find ./dl -type f)

# #clone cmake repos
mkdir -p "patches/cmake"
cd "patches/cmake"
while read f; do git clone "$f"; done < <(tr -d '\r' < ../../cmakelists.list)
cd ../../

# # Add cmake to sources
while read cm; do
	p=`basename ${cm%-*}`
	# Robustly find the target directory to rsync into
	target=$(find srcs -maxdepth 1 -name "${p}*" -type d | head -n 1)
	if [ -n "$target" ]; then
		echo "Applying cmake files to $target"
		rsync -a "$cm/" "$target/"
	else
		echo "Warning: Could not find source directory for $p"
	fi
done < <(find "patches/cmake/" -mindepth 1 -maxdepth 1 -name "*cmake")

# create out of src build tree
mkdir -p build
while read p; do
	p_base=`basename ${p%-*}`
	mkdir -p "build/$p_base"
	
	# Fontconfig MSVC header fix
	if [[ "$p" == fontconfig-* ]]; then
		echo "Applying sys/time.h mock for fontconfig"
		mkdir -p "srcs/$p/win_compat/sys"
		echo '#include <winsock2.h>' > "srcs/$p/win_compat/sys/time.h"
	fi
done < <(ls srcs)

#glib ;_;
cd srcs
patch -p0 < ../patches/glib*.prepatch
export PKG_CONFIG_LIBDIR='/' # stop it from using cygwin pkg-config
#export PKG_CONFIG_LIBDIR="$(cygpath --mixed `pwd`/install/share/pkgconfig)" # Just let them build their internal zlib
cd glib-*/
# Current requires ucrtbased.dll in system path... because meson.
meson ../../build/glib/ --prefix="`cygpath --mixed ../../install/`" --buildtype=debugoptimized
cd ../
cat ../patches/glib*.postpatch | patch -p0 # apply all patches
cd ../build/glib
ninja install # required before harfbuzz for pango
cd ../../

# Set up toolchain pkgconfig paths
INSTALL_DIR="$(pwd)/install"
unset PKG_CONFIG_LIBDIR || true
export PKG_CONFIG_PATH="$(cygpath -m "$INSTALL_DIR/lib/pkgconfig"):$(cygpath -m "$INSTALL_DIR/share/pkgconfig")"
echo "Set PKG_CONFIG_PATH to $PKG_CONFIG_PATH"

# Debug: verify glib is found
pkg-config --exists --print-errors glib-2.0 || echo "Warning: glib-2.0.pc not found in path!"

# apply general patches
cd srcs
cat ../patches/*.patch | patch -p0 || true # apply all patches
cd ../

# Helper to run cmake consistently
run_cmake() {
    local build_dir=$1
    local src_pattern=$2
    shift 2

    # Expand the pattern relative to ROOT (current directory)
    # We must NOT quote the pattern here to allow shell expansion
    local expanded=( $src_pattern )
    local src_path="${expanded[0]}"

    if [ ! -d "$src_path" ]; then
        echo "Error: Source directory $src_path (expanded from $src_pattern) not found!"
        exit 1
    fi

    local src_abs=$(cygpath -m "$(realpath "$src_path")")
    local inst_abs=$(cygpath -m "$INSTALL_DIR")
    
    echo "--- Building $build_dir ---"
    echo "Source: $src_abs"
    echo "Install Prefix: $inst_abs"

    mkdir -p "$build_dir"
    pushd "$build_dir" > /dev/null
    cmake "$src_abs" \
        -G 'Ninja' \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX="$inst_abs" \
        -DPKG_CONFIG_EXECUTABLE=$(cygpath -m $(which pkg-config)) \
        "$@"
    ninja install
    popd > /dev/null
}

#zlib
run_cmake "build/zlib" "srcs/zlib-*/"

#libpng
run_cmake "build/libpng" "srcs/libpng-*/"

#freetype no hb
run_cmake "build/freetype" "srcs/freetype-*/" -DWITH_PNG=ON

#harfbuzz (hb-glib required by pango fontconfig/freetype support.)
run_cmake "build/harfbuzz" "srcs/harfbuzz-*/" -DHB_HAVE_FREETYPE=ON -DHB_HAVE_GLIB=ON

#freetype with hb
rm -rf build/freetype/*
run_cmake "build/freetype" "srcs/freetype-*/" -DWITH_PNG=ON -DWITH_HARFBUZZ=ON

#libexpat
run_cmake "build/libexpat" "srcs/libexpat-*/expat/" -DBUILD_examples=off -DBUILD_tests=off -DBUILD_shared=OFF

#fontconfig
run_cmake "build/fontconfig" "srcs/fontconfig-*/"

#pixman
run_cmake "build/pixman" "srcs/pixman-*/"

#cairo
run_cmake "build/cairo" "srcs/cairo-*/"

#pango
# Fix strcasecmp on MSVC for pango-view
sed -i 's/strcasecmp/_stricmp/g' srcs/pango-*/pango-view/viewer-cairo.c

run_cmake "build/pango" "srcs/pango-*/"
