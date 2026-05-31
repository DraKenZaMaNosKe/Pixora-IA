#!/usr/bin/env bash
# Switch the active Pixora REALM shader on the connected Samsung.
#
# Usage:
#   bash tools/shaders/switch_shader.sh <name>
#
# Examples:
#   bash tools/shaders/switch_shader.sh universe
#   bash tools/shaders/switch_shader.sh kaleidoscope
#
# Valid names: universe, honeycomb, neon_triangles, sacred_geometry,
#              digital_rain, synthwave_grid, plasma_orbs, kaleidoscope,
#              metaballs, circuit_city
#
# Note: this force-stops the wallpaper process so the engine respawns with
# the new shader. Samsung may revert the home wallpaper to its default —
# that's fine, just reapply Pixora Realm from the preview.

set -euo pipefail

SHADER="${1:-}"
if [ -z "$SHADER" ]; then
  echo "usage: $0 <shader_name>"; exit 1
fi

DEVICE="${ANDROID_SERIAL:-RF8X903KZ3K}"

echo "→ setting shader_name=$SHADER"
adb -s "$DEVICE" shell "run-as com.orbix.pixora sh -c '
  mkdir -p shared_prefs &&
  printf %s \"<?xml version=\\\"1.0\\\" encoding=\\\"utf-8\\\" standalone=\\\"yes\\\" ?>
<map>
    <string name=\\\"shader_name\\\">$SHADER</string>
</map>
\" > shared_prefs/pixora_shader.xml
'"

echo "→ killing :wallpaper process (engine will respawn with new shader)"
adb -s "$DEVICE" shell "am force-stop com.orbix.pixora" || true
sleep 1

echo "→ launching wallpaper preview"
MSYS_NO_PATHCONV=1 adb -s "$DEVICE" shell "am start -a android.service.wallpaper.CHANGE_LIVE_WALLPAPER --ecn android.service.wallpaper.extra.LIVE_WALLPAPER_COMPONENT com.orbix.pixora/com.orbix.pixora.gl.ShaderWallpaperService"
echo ""
echo "✅ shader switched to: $SHADER"
echo "   tap 'Aplicar' in the preview to set as wallpaper."
