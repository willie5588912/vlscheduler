#!/bin/bash
# Build macOS .pkg installer for VLScheduler
set -e

VERSION="0.0.1"
PKG_ID="com.weishih.vlscheduler"
BUILD_DIR="pkg-build"

# Clean
rm -rf "$BUILD_DIR"

# --- Payload ---
mkdir -p "$BUILD_DIR/root/Applications/VLC.app/Contents/MacOS/share/lua/extensions"
mkdir -p "$BUILD_DIR/root/Applications/VLC.app/Contents/MacOS/plugins"

cp vlscheduler.lua "$BUILD_DIR/root/Applications/VLC.app/Contents/MacOS/share/lua/extensions/"
cp libscheduler_plugin.dylib "$BUILD_DIR/root/Applications/VLC.app/Contents/MacOS/plugins/"

# --- Scripts ---
mkdir -p "$BUILD_DIR/scripts"
cat > "$BUILD_DIR/scripts/preinstall" << 'SCRIPT'
#!/bin/bash
if [ ! -d "/Applications/VLC.app" ]; then
    echo "ERROR: VLC.app not found. Please install VLC first." >&2
    exit 1
fi
exit 0
SCRIPT

cat > "$BUILD_DIR/scripts/postinstall" << 'SCRIPT'
#!/bin/bash
# Match file ownership to VLC.app's owner
VLC_OWNER=$(stat -f '%Su:%Sg' /Applications/VLC.app)
chown "$VLC_OWNER" "/Applications/VLC.app/Contents/MacOS/share/lua/extensions/vlscheduler.lua" 2>/dev/null
chown "$VLC_OWNER" "/Applications/VLC.app/Contents/MacOS/plugins/libscheduler_plugin.dylib" 2>/dev/null
# Clear VLC plugin cache so the new plugin is discovered
rm -f ~/Library/Caches/org.videolan.vlc/plugins.dat 2>/dev/null
exit 0
SCRIPT

chmod +x "$BUILD_DIR/scripts/preinstall"
chmod +x "$BUILD_DIR/scripts/postinstall"

# --- Resources ---
mkdir -p "$BUILD_DIR/resources"

cat > "$BUILD_DIR/resources/welcome.html" << 'HTML'
<html><body style="font-family: -apple-system, Helvetica, sans-serif;">
<h1>VLScheduler 0.0.1</h1>
<p>Schedule automatic playlist playback in VLC on specific weekdays and times.</p>
<p><strong>Requirement:</strong> VLC 3.x must be installed at
<code>/Applications/VLC.app</code>.</p>
<p>This installer will add two files to your VLC installation:</p>
<ul>
<li><code>vlscheduler.lua</code> &mdash; configuration GUI</li>
<li><code>libscheduler_plugin.dylib</code> &mdash; scheduler engine</li>
</ul>
</body></html>
HTML

cat > "$BUILD_DIR/resources/license.html" << 'HTML'
<html><body style="font-family: -apple-system, Helvetica, sans-serif;">
<h2>GNU General Public License v2</h2>
<p>VLScheduler &mdash; Scheduled Playlist Playback for VLC<br>
Copyright &copy; 2026 Wei Shih</p>
<p>This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.</p>
<p>This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.</p>
<p>You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor,
Boston, MA 02110-1301, USA.</p>
<p>Full license text:
<a href="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html">
https://www.gnu.org/licenses/old-licenses/gpl-2.0.html</a></p>
</body></html>
HTML

cat > "$BUILD_DIR/resources/readme.html" << 'HTML'
<html><body style="font-family: -apple-system, Helvetica, sans-serif;">
<h2>After Installation</h2>
<ol>
<li>Open VLC</li>
<li>Go to <strong>View &gt; VLScheduler</strong></li>
<li>Check the weekdays you want, set times, and browse for media files</li>
<li>Click <strong>Save</strong></li>
<li>Quit and reopen VLC once to activate the scheduler engine</li>
</ol>
<p>After the first setup, schedule changes are hot-reloaded automatically
&mdash; no restart needed.</p>
</body></html>
HTML

# --- Step 1: Build component package ---
pkgbuild \
  --root "$BUILD_DIR/root" \
  --identifier "$PKG_ID" \
  --version "$VERSION" \
  --install-location / \
  --scripts "$BUILD_DIR/scripts" \
  "$BUILD_DIR/vlscheduler-component.pkg"

# --- Step 2: Synthesize distribution ---
productbuild --synthesize \
  --package "$BUILD_DIR/vlscheduler-component.pkg" \
  "$BUILD_DIR/distribution.xml"

# --- Step 3: Add welcome/license/readme to distribution.xml ---
sed -i '' 's|<installer-gui-script minSpecVersion="1">|<installer-gui-script minSpecVersion="1">\
    <title>VLScheduler</title>\
    <welcome    file="welcome.html"/>\
    <readme     file="readme.html"/>\
    <license    file="license.html"/>|' "$BUILD_DIR/distribution.xml"

# --- Step 4: Build final product archive ---
productbuild \
  --distribution "$BUILD_DIR/distribution.xml" \
  --resources "$BUILD_DIR/resources" \
  --package-path "$BUILD_DIR" \
  "vlscheduler-${VERSION}.pkg"

echo ""
echo "Built: vlscheduler-${VERSION}.pkg"
echo "Size: $(du -h "vlscheduler-${VERSION}.pkg" | cut -f1)"

# Clean up
rm -rf "$BUILD_DIR"
