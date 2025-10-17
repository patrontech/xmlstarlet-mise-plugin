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

download() {
  local name="$1"
  local ext="$2"
  local ver="$(${name}_version $3)" 
  local from="$4"
  local to="$5"
  local filename="${name}.tar.${ext}"
  local url="${from}/${name}-${ver}.tar.${ext}"
  echo $url
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

download_release() {
  local install_version="$1"
  local download_dir="$2"
  download_zlib "$install_version" "$download_dir"
  download_libxml2 "$install_version" "$download_dir"
  download_libxslt "$install_version" "$download_dir"
}
