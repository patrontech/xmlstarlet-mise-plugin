#!/usr/bin/env bash
set -euo pipefail

# --------- Configurable ----------
PREFIX="${PREFIX:-$HOME/.local/xmlstarlet-1.6.1}"   # install root for everything
XMLSTARLET_VERSION="1.6.1"
ZLIB_VERSION="1.3.1"
LIBXML2_VERSION="2.12.7"
LIBXSLT_VERSION="1.1.39"
# ---------------------------------

# Detect parallel jobs safely (works with set -u)
if command -v nproc >/dev/null 2>&1; then
  JOBS="${JOBS:-$(nproc)}"
elif command -v sysctl >/dev/null 2>&1; then
  JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
else
  JOBS="${JOBS:-1}"
fi

# Platform-specific loader env + rpaths
case "$(uname -s)" in
  Darwin)
    export DYLD_FALLBACK_LIBRARY_PATH="${PREFIX}/lib:${DYLD_FALLBACK_LIBRARY_PATH-}"
    RPATH_REL='@loader_path/../lib'
    RPATH_ABS="${PREFIX}/lib"
    ;;
  *)
    export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH-}"
    RPATH_REL='$ORIGIN/../lib'
    RPATH_ABS="${PREFIX}/lib"
    ;;
esac

fetch() {
  local url="$1" file="$2"
  if [ ! -f "$file" ]; then
    echo "==> Fetch $url"
    curl -fsSL -o "$file" -L "$url"
  fi
}

build_zlib() {
  fetch "https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz" "zlib-${ZLIB_VERSION}.tar.gz"
  rm -rf "zlib-${ZLIB_VERSION}"
  tar -xzf "zlib-${ZLIB_VERSION}.tar.gz"
  pushd "zlib-${ZLIB_VERSION}" >/dev/null
  ./configure --prefix="${PREFIX}"
  make -j"${JOBS}"
  make install
  popd >/dev/null
}

build_libxml2() {
  fetch "https://download.gnome.org/sources/libxml2/2.12/libxml2-${LIBXML2_VERSION}.tar.xz" "libxml2-${LIBXML2_VERSION}.tar.xz"
  rm -rf "libxml2-${LIBXML2_VERSION}"
  tar -xf "libxml2-${LIBXML2_VERSION}.tar.xz"
  pushd "libxml2-${LIBXML2_VERSION}" >/dev/null

  CPPFLAGS="-I${PREFIX}/include" \
  LDFLAGS="-L${PREFIX}/lib -Wl,-rpath,${RPATH_ABS} -Wl,-rpath,${RPATH_REL}" \
  ./configure --prefix="${PREFIX}" \
              --with-zlib="${PREFIX}" \
              --without-python \
              --without-lzma

  make -j"${JOBS}"
  make install
  popd >/dev/null

  export PATH="${PREFIX}/bin:${PATH}"   # ADDED: ensure xml2-config is visible to later steps
}

build_libxslt() {
  fetch "https://download.gnome.org/sources/libxslt/1.1/libxslt-${LIBXSLT_VERSION}.tar.xz" "libxslt-${LIBXSLT_VERSION}.tar.xz"
  rm -rf "libxslt-${LIBXSLT_VERSION}"
  tar -xf "libxslt-${LIBXSLT_VERSION}.tar.xz"
  pushd "libxslt-${LIBXSLT_VERSION}" >/dev/null

  # No pkg-config: point directly at our libxml2
  export XML2_CONFIG="${PREFIX}/bin/xml2-config"

  CPPFLAGS="-I${PREFIX}/include" \
  LDFLAGS="-L${PREFIX}/lib -Wl,-rpath,${RPATH_ABS} -Wl,-rpath,${RPATH_REL}" \
  ./configure --prefix="${PREFIX}" \
              --with-libxml-prefix="${PREFIX}" \
              --without-crypto \
              --without-python

  make -j"${JOBS}"
  make install
  popd >/dev/null
}

build_xmlstarlet() {
  local tgz="xmlstarlet-${XMLSTARLET_VERSION}.tar.gz"
  fetch "https://downloads.sourceforge.net/project/xmlstar/xmlstarlet/${XMLSTARLET_VERSION}/${tgz}" "${tgz}"
  rm -rf "xmlstarlet-${XMLSTARLET_VERSION}"
  tar -xzf "${tgz}"
  pushd "xmlstarlet-${XMLSTARLET_VERSION}" >/dev/null

  # Apple Clang warning suppression (>= 1500), harmless elsewhere if not applied
  if clang --version 2>/dev/null | grep -q "Apple clang"; then
    APPLE_CLANG_BUILD="$(clang --version | sed -n 's/.*clang-\([0-9][0-9]*\).*/\1/p' | head -n1 || echo 0)"
    if [ "${APPLE_CLANG_BUILD:-0}" -ge 1500 ]; then
      export CFLAGS="${CFLAGS-} -Wno-incompatible-function-pointer-types"
    fi
  fi

  # Make absolutely sure configure can find xml2-config:
  export XML2_CONFIG="${PREFIX}/bin/xml2-config"   # ADDED

  # Use libxml2's own flags for correctness (-I include/libxml2 etc)
  XML2_CFLAGS="$("${PREFIX}/bin/xml2-config" --cflags)"
  XML2_LIBS="$("${PREFIX}/bin/xml2-config" --libs)"

  CPPFLAGS="${XML2_CFLAGS} -I${PREFIX}/include" \
  LDFLAGS="-L${PREFIX}/lib -Wl,-rpath,${RPATH_ABS} -Wl,-rpath,${RPATH_REL}" \
  LIBS="${XML2_LIBS} -lxslt -lexslt" \
  ./configure --disable-dependency-tracking \
              --prefix="${PREFIX}" \
              --mandir="${PREFIX}/share/man"

  make -j"${JOBS}"
  make install

  ln -sf "${PREFIX}/bin/xml" "${PREFIX}/bin/xmlstarlet"
  popd >/dev/null
}

echo ">>> Install prefix: ${PREFIX}"
mkdir -p "${PREFIX}"

echo ">>> Building zlib"
build_zlib
echo ">>> Building libxml2"
build_libxml2
echo ">>> Building libxslt"
build_libxslt
echo ">>> Building xmlstarlet"
build_xmlstarlet

echo ">>> Done."
echo ">>> Try: ${PREFIX}/bin/xmlstarlet --version"
