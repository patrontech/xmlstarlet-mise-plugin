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

download_zlib() {
  local install_version="$1"
  local download_dir="$2"
  local download_path="${download_dir}/zlib.tar.gz"
  local ver="$(zlib_version "$install_version")"
  fetch "https://zlib.net/zlib-${ver}.tar.gz" "$download_path" 
  pushd "$download_dir" >/dev/null
  rm -rf zlib
  tar -xzf zlib.tar.gz
  mv "zlib-${ver}" zlib
  popd >/dev/null
}

download_release() {
  local install_version="$1"
  local download_dir="$2"
  download_zlib "$install_version" "$download_dir"
  download_libxml2 "$install_version" "$dowload_dir"
}

download_libxml2() {
  local install_version="$1"
  local download_dir="$2"
  local download_path="${download_dir}/libxml2.tar.xz"
  local ver="$(libxml2_version "$install_version")"
  fetch "https://download.gnome.org/sources/libxml2/2.12/libxml2-${ver}.tar.xz" "$download_path" 
  pushd "$download_dir" >/dev/null
  rm -rf libxml2 
  tar -xf libxml2.tar.xz 
  mv "libxml2-${ver}" libxml2 
  popd >/dev/null
}
