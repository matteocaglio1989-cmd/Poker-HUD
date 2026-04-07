#!/usr/bin/env bash
#
# fix-storekit-membership.sh
#
# One-shot fix for the "Couldn't load subscription plans /
# StoreKitError.unknown / nw_connection flood" symptom that happens when
# PokerHUD.storekit is selected in the scheme dropdown but isn't actually
# a member of the Xcode project. The dropdown autodetects loose .storekit
# files in the project folder, but the scheme XML stores its file
# reference as a project-relative pointer; if the file isn't a project
# member, launch-time resolution silently fails and StoreKit falls back
# to network calls (the source of the nw_connection warnings).
#
# This script:
#   1. Locates the .xcodeproj next to it (or via $1)
#   2. Confirms PokerHUD.storekit exists at the repo root
#   3. Installs Ruby's xcodeproj gem to the user gem dir if missing
#      (no sudo, writes to ~/.gem)
#   4. Adds PokerHUD.storekit as a PBXFileReference in the project root
#      group, with no target membership (the file is read by Xcode at
#      launch, not compiled into the bundle)
#   5. Verifies the StoreKitConfigurationFileReference identifier in
#      every .xcscheme under xcshareddata/xcschemes resolves to the
#      newly-added file path; rewrites it if wrong
#   6. Prints next-step instructions
#
# Idempotent: re-running on a fixed project is a no-op.
#
# Tested against Ruby 2.6+ (Apple stock Ruby on macOS Ventura+).

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$SCRIPT_DIR"
STOREKIT_FILE="PokerHUD.storekit"

echo "== Poker HUD StoreKit project-membership fix =="
echo

# 1. Locate .xcodeproj
if [[ -n "${1:-}" ]]; then
    XCODEPROJ="$1"
else
    # First .xcodeproj in the repo root
    XCODEPROJ="$( find "$REPO_ROOT" -maxdepth 2 -type d -name "*.xcodeproj" | head -n 1 )"
fi

if [[ -z "$XCODEPROJ" || ! -d "$XCODEPROJ" ]]; then
    echo "ERROR: Could not find an .xcodeproj. Pass the path as the first argument:"
    echo "    bash $0 /path/to/Poker-HUD.xcodeproj"
    exit 1
fi

echo "Project: $XCODEPROJ"

# 2. Confirm the .storekit file exists
if [[ ! -f "$REPO_ROOT/$STOREKIT_FILE" ]]; then
    echo "ERROR: $STOREKIT_FILE not found at $REPO_ROOT"
    echo "Run 'git pull origin main' first."
    exit 1
fi

echo "StoreKit file: $REPO_ROOT/$STOREKIT_FILE"
echo

# 3. Ensure Ruby + xcodeproj gem are available (install to user dir if missing)
if ! command -v ruby >/dev/null 2>&1; then
    echo "ERROR: ruby not found in PATH. macOS Ventura+ ships Ruby — run 'xcode-select --install' if needed."
    exit 1
fi

if ! ruby -e "require 'xcodeproj'" >/dev/null 2>&1; then
    echo "Installing Ruby xcodeproj gem to your user gem dir (no sudo)..."
    if ! gem install --user-install xcodeproj >/dev/null; then
        echo "ERROR: gem install --user-install xcodeproj failed."
        echo "Try: sudo gem install xcodeproj"
        exit 1
    fi
    # gem --user-install puts binaries / libs in ~/.gem/ruby/<version>/...
    # We need that on RUBYLIB so the require below picks it up.
    USER_GEM_DIR="$( ruby -e 'puts Gem.user_dir' )"
    export GEM_PATH="${GEM_PATH:-}:$USER_GEM_DIR"
fi

# 4 & 5. Patch the project + scheme via xcodeproj gem
RUBY_RESULT=0
ruby - "$XCODEPROJ" "$REPO_ROOT" "$STOREKIT_FILE" <<'RUBY' || RUBY_RESULT=$?
require 'xcodeproj'
require 'rexml/document'

xcodeproj_path, repo_root, storekit_file = ARGV

proj = Xcodeproj::Project.open(xcodeproj_path)

# 4. Add PBXFileReference if missing
existing = proj.files.find { |f| f.path == storekit_file || f.real_path.to_s.end_with?("/#{storekit_file}") }

if existing
  puts "  ✓ #{storekit_file} is already a project member (file ref: #{existing.uuid})"
else
  ref = proj.new_file(File.join(repo_root, storekit_file))
  # new_file places it in the root group by default; do not add to any target.
  proj.save
  puts "  + Added #{storekit_file} to project root group (file ref: #{ref.uuid})"
end

# 5. Walk every .xcscheme under xcshareddata/xcschemes and verify the
#    StoreKitConfigurationFileReference identifier resolves correctly.
#
#    Xcode stores the identifier as "container:<path-relative-to-project-dir>"
#    where <project-dir> is the directory CONTAINING the .xcodeproj.
#    For PokerHUD.storekit at the repo root, the correct identifier is
#    "container:PokerHUD.storekit".
schemes_dir = File.join(xcodeproj_path, "xcshareddata", "xcschemes")
expected_id = "container:#{storekit_file}"

if File.directory?(schemes_dir)
  Dir.glob(File.join(schemes_dir, "*.xcscheme")).each do |scheme_path|
    xml = REXML::Document.new(File.read(scheme_path))
    refs = REXML::XPath.match(xml, "//StoreKitConfigurationFileReference")

    if refs.empty?
      # Add a fresh reference inside the LaunchAction. The user has to
      # also pick it in the Edit Scheme UI for Xcode to wire it up
      # cleanly, but having the element here means the dropdown will
      # already point at the right path the next time they look.
      launch = REXML::XPath.first(xml, "//LaunchAction")
      if launch
        new_ref = REXML::Element.new("StoreKitConfigurationFileReference")
        new_ref.add_attribute("identifier", expected_id)
        launch.add_element(new_ref)
        File.write(scheme_path, xml.to_s)
        puts "  + #{File.basename(scheme_path)}: added StoreKitConfigurationFileReference #{expected_id}"
      else
        puts "  ! #{File.basename(scheme_path)}: no <LaunchAction>, skipping"
      end
    else
      refs.each do |ref|
        current = ref.attribute("identifier")&.value
        if current == expected_id
          puts "  ✓ #{File.basename(scheme_path)}: identifier already #{current}"
        else
          ref.add_attribute("identifier", expected_id)
          File.write(scheme_path, xml.to_s)
          puts "  + #{File.basename(scheme_path)}: rewrote identifier #{current.inspect} -> #{expected_id}"
        end
      end
    end
  end
else
  puts "  ! No xcshareddata/xcschemes dir found; you may need to mark your scheme as Shared in Manage Schemes…"
end
RUBY

if [[ $RUBY_RESULT -ne 0 ]]; then
    echo
    echo "ERROR: Ruby xcodeproj patching failed (exit $RUBY_RESULT)."
    exit $RUBY_RESULT
fi

echo
echo "== Done =="
echo
echo "Now in Xcode:"
echo "  1. Stop the running app  (⌘. or Stop button)"
echo "  2. Activity Monitor: force-quit any leftover PokerHUD process"
echo "  3. Clean Build Folder    (⇧⌘K)"
echo "  4. Quit Xcode entirely   (⌘Q) and reopen the project"
echo "  5. Run                   (⌘R)"
echo
echo "Then verify:  Debug → StoreKit → Manage Transactions"
echo "  - Should be enabled and list 'Poker HUD Monthly' + 'Poker HUD Yearly'"
echo "  - The Xcode console should NO LONGER print nw_connection_copy_protocol_metadata_internal warnings"
