#!/bin/bash

# Manifest Plugin Loader
# Discovers and loads optional modules from Manifest Cloud installation

# Guard against multiple sourcing
[ -n "$_MANIFEST_PLUGIN_LOADER_LOADED" ] && return 0
_MANIFEST_PLUGIN_LOADER_LOADED=1

MANIFEST_CLOUD_PLUGINS_DIR="${MANIFEST_CLOUD_DIR:-$HOME/.manifest-cloud}/cli-plugins"
export MANIFEST_CLOUD_PLUGINS_DIR

# Try to source a plugin file. Returns 0 if loaded, 1 if absent.
manifest_load_plugin() {
    local plugin_path="$MANIFEST_CLOUD_PLUGINS_DIR/$1"
    if [ -f "$plugin_path" ]; then
        source "$plugin_path"
        return 0
    fi
    return 1
}
