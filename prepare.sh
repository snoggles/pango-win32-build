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
export PKG_CONFIG_LIBDIR="$(cygpath --unix `pwd`/install/lib/pkgconfig)" # needed for glib

# apply general patches
cd srcs
cat ../patches/*.patch | patch -p0 # apply all patches
cd ../

#zlib
cd build/zlib
cmake ../../srcs/zlib-*/ \
    -G 'Ninja' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=../../install
ninja install

#libpng
cd ../libpng
cmake ../../srcs/libpng-*/ \
    -G 'Ninja' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=../../install
ninja install

#freetype no hb
cd ../freetype
cmake ../../srcs/freetype-*/ \
    -DWITH_PNG=ON \
    -G 'Ninja' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=../../install
ninja install

#harfbuzz (hb-glib required by pango fontconfig/freetype support.)
cd ../harfbuzz
cmake ../../srcs/harfbuzz-*/ \
    -DHB_HAVE_FREETYPE=ON -DHB_HAVE_GLIB=ON \
    -G 'Ninja' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=../../install
ninja install

#freetype with hb
rm -rf ../freetype/*
cd ../freetype
cmake ../../srcs/freetype-*/ \
    -DWITH_PNG=ON -DWITH_HARFBUZZ=ON \
    -G 'Ninja' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=../../install
ninja install

#libexpat
cd ../libexpat
cmake ../../srcs/libexpat-*/expat/ \
    -DBUILD_examples=off -DBUILD_tests=off -DBUILD_shared=OFF \
    -G 'Ninja' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=../../install
ninja install

#fontconfig
cd ../fontconfig
cmake ../../srcs/fontconfig-*/ \
    -G 'Ninja' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=../../install
ninja install
#ConfigureChecks.cmake, Config.h.cmake

#pixman
cd ../pixman
cmake ../../srcs/pixman-*/ \
    -G 'Ninja' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=../../install
ninja install

#cairo
cd ../cairo
cmake ../../srcs/cairo-*/ \
    -G 'Ninja' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=../../install
ninja install

#pango
cd ../pango
cmake ../../srcs/pango-* \
    -G 'Ninja' -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=../../install
ninja install
