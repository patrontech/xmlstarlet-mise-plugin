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
  cd "$to"
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
  cd "$download_dir/zlib"
  ./configure --prefix="$install_dir"
  make -j"$jobs"
  make install
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
  cd "$download_dir/libxml2"
  CPPFLAGS="-I${install_dir}/include" \
  LDFLAGS="-L${install_dir}/lib -Wl,-rpath,${RPATH_ABS} -Wl,-rpath,${RPATH_REL}" \
  ./configure --prefix="${install_dir}" \
              --with-zlib="${install_dir}" \
              --without-python \
              --without-lzma
  make -j"$jobs"
  make install
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
  cd "$download_dir/libxslt"
  export XML2_CONFIG="${install_dir}/bin/xml2-config"
  CPPFLAGS="-I${install_dir}/include" \
  LDFLAGS="-L${install_dir}/lib -Wl,-rpath,${RPATH_ABS} -Wl,-rpath,${RPATH_REL}" \
  ./configure --prefix="${install_dir}" \
              --with-libxml-prefix="${install_dir}" \
              --without-crypto \
              --without-python
  make -j"$jobs"
  make install
}

install_xmlstarlet() {
  local download_dir="$1"
  local install_dir="$2"
  local jobs="$3"
  # export CFLAGS="${CFLAGS-} -Wno-incompatible-function-pointer-types"
  export CFLAGS="${CFLAGS-} -Wno-deprecated-declarations"
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
  export XML2_CONFIG="${install_dir}/bin/xml2-config"   # ADDED
  XML2_CFLAGS="$("$XML2_CONFIG" --cflags)"
  XML2_LIBS="$("$XML2_CONFIG" --libs)"
  cd "$download_dir/xmlstarlet"
  CPPFLAGS="${XML2_CFLAGS} -I${install_dir}/include" \
  LDFLAGS="-L${install_dir}/lib -Wl,-rpath,${RPATH_ABS} -Wl,-rpath,${RPATH_REL}" \
  LIBS="${XML2_LIBS} -lxslt -lexslt" \
  ./configure --disable-dependency-tracking \
              --prefix="${install_dir}" \
              --mandir="${install_dir}/share/man"
  make -j"$jobs"
  make install
  ln -sf "${install_dir}/bin/xml" "${install_dir}/bin/xmlstarlet"
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
