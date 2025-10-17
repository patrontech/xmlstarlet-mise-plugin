-- metadata.lua
-- Plugin metadata and configuration
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#metadata-lua

PLUGIN = { -- luacheck: ignore
    -- Required: Tool name (lowercase, no spaces)
    name = "xmlstarlet",

    -- Required: Plugin version (not the tool version)
    version = "1.0.0",

    -- Required: Brief description of the tool
    description = "A mise tool plugin for xmlstarlet",

    -- Required: Plugin author/maintainer
    author = "patrontech",

    -- Optional: Repository URL for plugin updates
    updateUrl = "https://github.com/patrontech/xmlstarlet-mise-plugin",

    -- Optional: Minimum mise runtime version required
    minRuntimeVersion = "0.2.0",
}
