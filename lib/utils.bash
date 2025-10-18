#!/usr/bin/env bash

set -euo pipefail

fetch() {
  local url="$1" file="$2"
  if [ ! -f "$file" ]; then
    curl -fsSL -o "$file" -L "$url"
  fi
}

list_all_versions_sorted() {
  # This is the only one we support at the moment
  echo "1.6.1"
}

get_major_minor() {
  local version=$1

  # Require exactly three numeric parts separated by dots
  if [[ $version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  else
    echo "Error: invalid version string '$version'" >&2
    return 1
  fi
}

zlib_version() {
  local install_version="$1"
  # This is the only one we support at the moment
  echo "1.3.1"
}

libxml2_version() {
  local install_version="$1"
  # This is the only one we support at the moment
  echo "2.12.7"
}

libxslt_version() {
  local install_version="$1"
  # This is the only one we support at the moment
  echo "1.1.39"
}

xmlstarlet_version() {
  echo "$1"
}

download() {
  local name="$1"
  local ext="$2"
  local ver="$(${name}_version $3)" 
  local from="$4"
  local to="$5"
  local filename="${name}.tar.${ext}"
  local url="${from}/${name}-${ver}.tar.${ext}"
  fetch $url "${to}/$filename"
  pushd "$to" >/dev/null
  rm -rf $name
  case $ext in
    gz)
      tar -xzf $filename
    ;;
    xz)
      tar -xf $filename
  esac
  mv "${name}-${ver}" "$name"
  rm "$filename"
  popd >/dev/null
}

download_zlib() {
  local install_version="$1"
  local download_dir="$2"
  local from="https://zlib.net"
  download zlib gz "$install_version" "$from" "$download_dir"
}

download_libxml2() {
  local install_version="$1"
  local download_dir="$2"
  local ver="$(get_major_minor "$(libxml2_version "$install_version")")"
  local from="https://download.gnome.org/sources/libxml2/$ver"
  download libxml2 xz "$install_version" "$from" "$download_dir"
}

download_libxslt() {
  local install_version="$1"
  local download_dir="$2"
  local ver="$(get_major_minor "$(libxslt_version "$install_version")")"
  local from="https://download.gnome.org/sources/libxslt/$ver"
  download libxslt xz "$install_version" "$from" "$download_dir"
}

download_xmlstarlet() {
  local install_version="$1"
  local download_dir="$2"
  local tgz="xmlstarlet-${install_version}.tar.gz"
  local from="https://downloads.sourceforge.net/project/xmlstar/xmlstarlet/${install_version}"
  download xmlstarlet gz "$install_version" "$from" "$download_dir"
}

download_release() {
  local install_version="$1"
  local download_dir="$2"
  download_zlib "$install_version" "$download_dir"
  download_libxml2 "$install_version" "$download_dir"
  download_libxslt "$install_version" "$download_dir"
  download_xmlstarlet "$install_version" "$download_dir" 
}

install_zlib() {
  local download_dir="$1"
  local install_dir="$2"
  local jobs="$3"
  pushd "$download_dir/zlib" >/dev/null
  ./configure --prefix="$install_dir"
  make -j"$jobs"
  make install
  popd >/dev/null
}

install_libxml2() {
  local download_dir="$1"
  local install_dir="$2"
  local jobs="$3"
  case "$(uname -s)" in
    Darwin)
      RPATH_REL='@loader_path/../lib'
      RPATH_ABS="${install_dir}/lib"
      ;;
    *)
      RPATH_REL='$ORIGIN/../lib'
      RPATH_ABS="${install_dir}/lib"
      ;;
  esac
  pushd "$download_dir/libxml2" >/dev/null
  CPPFLAGS="-I${install_dir}/include" \
  LDFLAGS="-L${install_dir}/lib -Wl,-rpath,${RPATH_ABS} -Wl,-rpath,${RPATH_REL}" \
  ./configure --prefix="${install_dir}" \
              --with-zlib="${install_dir}" \
              --without-python \
              --without-lzma
  make -j"$jobs"
  make install
  popd >/dev/null
}

install_libxslt() {
  local download_dir="$1"
  local install_dir="$2"
  local jobs="$3"
  case "$(uname -s)" in
    Darwin)
      RPATH_REL='@loader_path/../lib'
      RPATH_ABS="${install_dir}/lib"
      ;;
    *)
      RPATH_REL='$ORIGIN/../lib'
      RPATH_ABS="${install_dir}/lib"
      ;;
  esac
  pushd "$download_dir/libxslt" >/dev/null
  export XML2_CONFIG="${install_dir}/bin/xml2-config"
  CPPFLAGS="-I${install_dir}/include" \
  LDFLAGS="-L${install_dir}/lib -Wl,-rpath,${RPATH_ABS} -Wl,-rpath,${RPATH_REL}" \
  ./configure --prefix="${install_dir}" \
              --with-libxml-prefix="${install_dir}" \
              --without-crypto \
              --without-python
  make -j"$jobs"
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

install_xmlstarlet() {
  local download_dir="$1"
  local install_dir="$2"
  local jobs="$3"
  case "$(uname -s)" in
    Darwin)
      RPATH_REL='@loader_path/../lib'
      RPATH_ABS="${install_dir}/lib"
      ;;
    *)
      RPATH_REL='$ORIGIN/../lib'
      RPATH_ABS="${install_dir}/lib"
      ;;
  esac
  if clang --version 2>/dev/null | grep -q "Apple clang"; then
    APPLE_CLANG_BUILD="$(clang --version | sed -n 's/.*clang-\([0-9][0-9]*\).*/\1/p' | head -n1 || echo 0)"
    if [ "${APPLE_CLANG_BUILD:-0}" -ge 1500 ]; then
      export CFLAGS="${CFLAGS-} -Wno-incompatible-function-pointer-types"
    fi
  fi
  export XML2_CONFIG="${install_dir}/bin/xml2-config"   # ADDED
  XML2_CFLAGS="$("$XML2_CONFIG" --cflags)"
  XML2_LIBS="$("$XML2_CONFIG" --libs)"
  pushd "$download_dir/xmlstarlet" >/dev/null
  CPPFLAGS="${XML2_CFLAGS} -I${install_dir}/include" \
  LDFLAGS="-L${install_dir}/lib -Wl,-rpath,${RPATH_ABS} -Wl,-rpath,${RPATH_REL}" \
  LIBS="${XML2_LIBS} -lxslt -lexslt" \
  ./configure --disable-dependency-tracking \
              --prefix="${install_dir}" \
              --mandir="${install_dir}/share/man"
  make -j"$jobs"
  make install
  ln -sf "${install_dir}/bin/xml" "${install_dir}/bin/xmlstarlet"
  popd >/dev/null
}

install_release() {
  local download_dir="$1"
  local install_dir="$2"
  local jobs="${3:-1}"
  rm -rf "$install_dir"
  mkdir -p "$install_dir"
  install_zlib "$download_dir" "$install_dir" "$jobs"
  install_libxml2 "$download_dir" "$install_dir" "$jobs"
  install_libxslt "$download_dir" "$install_dir" "$jobs"
  install_xmlstarlet "$download_dir" "$install_dir" "$jobs"
}
