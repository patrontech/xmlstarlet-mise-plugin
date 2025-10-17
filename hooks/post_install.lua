-- hooks/post_install.lua
-- Performs additional setup after installation
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#postinstall-hook

local function sh(cmd)
  local ok = os.execute(cmd)
  if ok ~= true and ok ~= 0 then
    error("command failed: " .. cmd)
  end
end

local function platform_rpaths(prefix)
  local osType = RUNTIME.osType
  if osType == "Darwin" then
    return "@loader_path/../lib", prefix .. "/lib", "DYLD_FALLBACK_LIBRARY_PATH"
  else
    return "$ORIGIN/../lib", prefix .. "/lib", "LD_LIBRARY_PATH"
  end
end

function PLUGIN:PostInstall(ctx)
  local work = ctx.workDir                  -- temp working dir
  local prefix = ctx.path                   -- final install prefix for this version

  local ZLIB_VERSION    = "1.3.1"
  local LIBXML2_VERSION = "2.12.7"
  local LIBXSLT_VERSION = "1.1.39"

  local RPATH_REL, RPATH_ABS, LOADER_ENV = platform_rpaths(prefix)

  -- Ensure tools
  local need = { "curl", "tar", "make" }
  for _, bin in ipairs(need) do
    if not which(bin) then
      error("missing required tool: " .. bin)
    end
  end
  if not (which("gcc") or which("clang")) then
    error("missing C compiler (gcc or clang)")
  end

  -- Helper to fetch (quietly) into work dir
  local function fetch(url, out)
    sh(("cd %q && curl -fsSL -o %q -L %q"):format(work, out, url))
  end

  -- Build helpers ------------------------------------------------------------
  local function build_zlib()
    local tgz = ("zlib-%s.tar.gz"):format(ZLIB_VERSION)
    fetch(("https://zlib.net/%s"):format(tgz), tgz)
    sh(("cd %q && rm -rf zlib-%s && tar -xzf %q"):format(work, ZLIB_VERSION, tgz))
    sh(("cd %q/zlib-%s && ./configure --prefix=%q && make -j && make install")
        :format(work, ZLIB_VERSION, prefix))
  end

  local function build_libxml2()
    local txz = ("libxml2-%s.tar.xz"):format(LIBXML2_VERSION)
    fetch(("https://download.gnome.org/sources/libxml2/2.12/%s"):format(txz), txz)
    sh(("cd %q && rm -rf libxml2-%s && tar -xf %q"):format(work, LIBXML2_VERSION, txz))
    local cmd = table.concat({
      ("cd %q/libxml2-%s &&"):format(work, LIBXML2_VERSION),
      ("env CPPFLAGS='-I%q/include'"):format(prefix),
      ("LDFLAGS='-L%q/lib -Wl,-rpath,%s -Wl,-rpath,%s'"):format(prefix, RPATH_ABS, RPATH_REL),
      ("%s='%s:%s'"):format(LOADER_ENV, prefix .. "/lib", os.getenv(LOADER_ENV) or ""),
      ("./configure --prefix=%q --with-zlib=%q --without-python --without-lzma && make -j && make install")
        :format(prefix, prefix)
    }, " ")
    sh(cmd)
  end

  local function build_libxslt()
    local txz = ("libxslt-%s.tar.xz"):format(LIBXSLT_VERSION)
    fetch(("https://download.gnome.org/sources/libxslt/1.1/%s"):format(txz), txz)
    sh(("cd %q && rm -rf libxslt-%s && tar -xf %q"):format(work, LIBXSLT_VERSION, txz))
    local cmd = table.concat({
      ("cd %q/libxslt-%s &&"):format(work, LIBXSLT_VERSION),
      ("env XML2_CONFIG=%q/bin/xml2-config"):format(prefix),
      ("CPPFLAGS='-I%q/include'"):format(prefix),
      ("LDFLAGS='-L%q/lib -Wl,-rpath,%s -Wl,-rpath,%s'"):format(prefix, RPATH_ABS, RPATH_REL),
      ("%s='%s:%s'"):format(LOADER_ENV, prefix .. "/lib", os.getenv(LOADER_ENV) or ""),
      ("./configure --prefix=%q --with-libxml-prefix=%q --without-crypto --without-python && make -j && make install")
        :format(prefix, prefix)
    }, " ")
    sh(cmd)
  end

  local function build_xmlstarlet()
    -- Use the source tree extracted by mise: it’s in `work`, find the dir name:
    local srcdir
    for name in lfs.dir(work) do
      if name:match("^xmlstarlet%-%d+%.%d+%.%d+$") then
        srcdir = work .. "/" .. name
        break
      end
    end
    if not srcdir then
      error("xmlstarlet source dir not found in workDir")
    end

    -- Apple Clang warning suppression only if present & >= 1500
    local cflags_extra = ""
    if RUNTIME.osType == "Darwin" and which("clang") then
      -- crude check; acceptable for our case
      local v = io.popen("clang --version 2>/dev/null"):read("*a") or ""
      if v:match("clang%-(%d+)") and tonumber(v:match("clang%-(%d+)")) >= 1500 then
        cflags_extra = " -Wno-incompatible-function-pointer-types"
      end
    end

    -- Pull in libxml2’s flags; xml2-config lives in our prefix
    local xml2cfg = prefix .. "/bin/xml2-config"
    local xml2_cflags = io.popen(("%q --cflags"):format(xml2cfg)):read("*a"):gsub("\n","")
    local xml2_libs   = io.popen(("%q --libs"):format(xml2cfg)):read("*a"):gsub("\n","")

    local cmd = table.concat({
      ("cd %q &&"):format(srcdir),
      ("env XML2_CONFIG=%q"):format(xml2cfg),
      ("CPPFLAGS='%s -I%q/include'"):format(xml2_cflags, prefix),
      ("CFLAGS='$CFLAGS%s'"):format(cflags_extra),
      ("LDFLAGS='-L%q/lib -Wl,-rpath,%s -Wl,-rpath,%s'"):format(prefix, RPATH_ABS, RPATH_REL),
      ("LIBS='%s -lxslt -lexslt'"):format(xml2_libs),
      ("./configure --disable-dependency-tracking --prefix=%q --mandir=%q/share/man && make -j && make install")
        :format(prefix, prefix),
      ("&& ln -snf %q/bin/xml %q/bin/xmlstarlet"):format(prefix, prefix)
    }, " ")
    sh(cmd)
  end

  -- Build in order
  build_zlib()
  build_libxml2()
  build_libxslt()
  build_xmlstarlet()
end

