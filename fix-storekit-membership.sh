#!/usr/bin/env bash
#
# fix-storekit-membership.sh
#
# One-shot fix for the "Couldn't load subscription plans /
# StoreKitError.unknown / nw_connection flood" symptom.
#
# Handles BOTH project layouts:
#
#   A. Classic Xcode project: a Poker-HUD.xcodeproj exists at the repo root.
#      The script adds PokerHUD.storekit as a PBXFileReference and verifies
#      the StoreKitConfigurationFileReference identifier in every shared
#      scheme.
#
#   B. SPM-only workflow: no .xcodeproj — the user opens Package.swift
#      directly in Xcode, which generates virtual schemes and stores
#      per-user scheme settings under
#      .swiftpm/xcode/xcuserdata/<user>.xcuserdatad/xcschemes/<Target>.xcscheme
#      The script patches that file (or each .xcscheme it finds) to ensure
#      <StoreKitConfigurationFileReference identifier="container:PokerHUD.storekit"/>
#      exists inside <LaunchAction>.
#
# Why this exists: a properly-loaded local .storekit file serves products
# with zero network traffic. If you see nw_connection_copy_protocol_metadata_internal
# warnings on launch and StoreKitError.unknown, the local config is NOT
# loaded — usually because Xcode's dropdown selection didn't actually
# persist to the scheme XML on disk (a known SPM-mode flake), or because
# the file isn't a project member in classic mode.
#
# Idempotent: safe to re-run.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$SCRIPT_DIR"
STOREKIT_FILE="PokerHUD.storekit"

echo "== Poker HUD StoreKit configuration fix =="
echo "Repo root: $REPO_ROOT"
echo

# Sanity check: the .storekit file must exist on disk.
if [[ ! -f "$REPO_ROOT/$STOREKIT_FILE" ]]; then
    echo "ERROR: $STOREKIT_FILE not found at repo root."
    echo "Run 'git pull origin main' first, then re-run this script."
    exit 1
fi
echo "Found: $REPO_ROOT/$STOREKIT_FILE"

# -----------------------------------------------------------------------------
# Detect project layout
# -----------------------------------------------------------------------------
XCODEPROJ="$( find "$REPO_ROOT" -maxdepth 2 -type d -name "*.xcodeproj" 2>/dev/null | head -n 1 )"

if [[ -n "$XCODEPROJ" ]]; then
    LAYOUT="classic"
    echo "Layout: classic Xcode project at $XCODEPROJ"
else
    LAYOUT="spm"
    echo "Layout: SPM-only (no .xcodeproj — opening Package.swift in Xcode)"
fi
echo

# -----------------------------------------------------------------------------
# Mode A: classic Xcode project
# -----------------------------------------------------------------------------
if [[ "$LAYOUT" == "classic" ]]; then
    if ! command -v ruby >/dev/null 2>&1; then
        echo "ERROR: ruby not found. Run 'xcode-select --install' first."
        exit 1
    fi
    if ! ruby -e "require 'xcodeproj'" >/dev/null 2>&1; then
        echo "Installing the xcodeproj gem to your user gem dir (no sudo)..."
        gem install --user-install xcodeproj >/dev/null
        export GEM_PATH="${GEM_PATH:-}:$( ruby -e 'puts Gem.user_dir' )"
    fi

    ruby - "$XCODEPROJ" "$REPO_ROOT" "$STOREKIT_FILE" <<'RUBY'
require 'xcodeproj'
require 'rexml/document'
xcodeproj_path, repo_root, storekit_file = ARGV
proj = Xcodeproj::Project.open(xcodeproj_path)
existing = proj.files.find { |f| f.path == storekit_file || f.real_path.to_s.end_with?("/#{storekit_file}") }
if existing
  puts "  ✓ #{storekit_file} already a project member"
else
  proj.new_file(File.join(repo_root, storekit_file))
  proj.save
  puts "  + Added #{storekit_file} to project root group"
end

schemes_dir = File.join(xcodeproj_path, "xcshareddata", "xcschemes")
expected_id = "container:#{storekit_file}"
if File.directory?(schemes_dir)
  Dir.glob(File.join(schemes_dir, "*.xcscheme")).each do |scheme|
    xml = REXML::Document.new(File.read(scheme))
    refs = REXML::XPath.match(xml, "//StoreKitConfigurationFileReference")
    if refs.empty?
      launch = REXML::XPath.first(xml, "//LaunchAction")
      next unless launch
      el = REXML::Element.new("StoreKitConfigurationFileReference")
      el.add_attribute("identifier", expected_id)
      launch.add_element(el)
      File.write(scheme, xml.to_s)
      puts "  + #{File.basename(scheme)}: added #{expected_id}"
    else
      refs.each do |r|
        cur = r.attribute("identifier")&.value
        if cur == expected_id
          puts "  ✓ #{File.basename(scheme)}: identifier already correct"
        else
          r.add_attribute("identifier", expected_id)
          File.write(scheme, xml.to_s)
          puts "  + #{File.basename(scheme)}: rewrote #{cur.inspect} -> #{expected_id}"
        end
      end
    end
  end
else
  puts "  ! No xcshareddata/xcschemes — your scheme might be User-only. Mark it Shared in Manage Schemes…"
fi
RUBY

# -----------------------------------------------------------------------------
# Mode B: SPM-only (no .xcodeproj)
# -----------------------------------------------------------------------------
else
    SWIFTPM_DIR="$REPO_ROOT/.swiftpm"
    if [[ ! -d "$SWIFTPM_DIR" ]]; then
        echo "ERROR: $SWIFTPM_DIR does not exist."
        echo
        echo "Xcode hasn't been run on this project yet, so the per-user scheme"
        echo "files haven't been generated. Open Package.swift in Xcode once"
        echo "(File → Open → select Package.swift in this folder), let it"
        echo "resolve packages, then re-run this script."
        exit 1
    fi

    # Find ALL .xcscheme files under .swiftpm (covers any username).
    # Using a while-read loop instead of `mapfile` because macOS still
    # ships bash 3.2 (from 2007), where `mapfile` doesn't exist.
    SCHEMES=()
    while IFS= read -r line; do
        SCHEMES+=("$line")
    done < <( find "$SWIFTPM_DIR" -name "*.xcscheme" 2>/dev/null )

    if [[ ${#SCHEMES[@]} -eq 0 ]]; then
        echo "ERROR: No .xcscheme files found under $SWIFTPM_DIR"
        echo
        echo "Open Package.swift in Xcode, then in the menu bar:"
        echo "  Product → Scheme → Manage Schemes…"
        echo "Tick the 'Shared' checkbox next to PokerHUD, then run this"
        echo "script again. (Sharing the scheme persists it under .swiftpm"
        echo "where this script can patch it.)"
        exit 1
    fi

    EXPECTED_ID="container:$STOREKIT_FILE"
    PATCHED=0

    for scheme in "${SCHEMES[@]}"; do
        echo "Patching $scheme"
        # Use python (always present on macOS) for reliable XML editing
        python3 - "$scheme" "$EXPECTED_ID" <<'PY'
import sys
import xml.etree.ElementTree as ET

scheme_path, expected_id = sys.argv[1], sys.argv[2]

# Parse preserving the document
tree = ET.parse(scheme_path)
root = tree.getroot()

launch = root.find("LaunchAction")
if launch is None:
    print(f"  ! no <LaunchAction> in {scheme_path} — skipping")
    sys.exit(0)

# Look for an existing StoreKitConfigurationFileReference anywhere in the doc
ref = root.find(".//StoreKitConfigurationFileReference")
if ref is None:
    ref = ET.SubElement(launch, "StoreKitConfigurationFileReference")
    ref.set("identifier", expected_id)
    print(f"  + added <StoreKitConfigurationFileReference identifier=\"{expected_id}\"/>")
else:
    current = ref.get("identifier", "")
    if current == expected_id:
        print(f"  ✓ identifier already {expected_id}")
        sys.exit(0)
    else:
        ref.set("identifier", expected_id)
        print(f"  + rewrote identifier {current!r} -> {expected_id}")

# Write back, keeping XML declaration
tree.write(scheme_path, xml_declaration=True, encoding="UTF-8")
PY
        PATCHED=$((PATCHED+1))
    done

    echo
    echo "Patched $PATCHED scheme file(s)."
fi

# -----------------------------------------------------------------------------
# Final instructions
# -----------------------------------------------------------------------------
echo
echo "== Done =="
echo
echo "Now in Xcode:"
echo "  1. Stop the running app   (Cmd+. or Stop button)"
echo "  2. Activity Monitor: force-quit any leftover PokerHUD process"
echo "  3. Clean Build Folder     (Shift+Cmd+K)"
echo "  4. Quit Xcode entirely    (Cmd+Q) and reopen the project"
echo "  5. Run                    (Cmd+R)"
echo
echo "Verify it worked:"
echo "  - Debug → StoreKit → Manage Transactions  should be enabled and list"
echo "    'Poker HUD Monthly' and 'Poker HUD Yearly'"
echo "  - The Xcode console should NOT print nw_connection_copy_protocol_metadata_internal"
echo "    warnings on the next launch (those are the smoking gun for"
echo "    'local .storekit not loaded')"
echo
if [[ "$LAYOUT" == "spm" ]]; then
    cat <<'NOTE'
Note: SPM-only Xcode StoreKit testing has historical flakiness compared
to a real Xcode App project. If after running this script the local
config still isn't loading, the most reliable workaround is to wrap the
package in a thin Xcode App project:

  1. File → New → Project → macOS → App
  2. Save it inside this folder (e.g. Poker-HUD.xcodeproj)
  3. Add the local Swift package as a dependency
  4. In the App target's scheme: Edit Scheme → Run → Options
     → StoreKit Configuration → PokerHUD.storekit

Then re-run this script to also patch the .xcodeproj scheme.
NOTE
fi
