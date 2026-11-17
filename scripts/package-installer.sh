#!/bin/bash
set -euo pipefail

# Package a previously built Release app. Signing/notarization is a separate flow.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$project_root/build/Build/Products/Release/QuotaPie.app}"
output_dir="$project_root/dist"

if [[ ! -d "$app_path" ]]; then
    echo "Release app not found: $app_path" >&2
    echo "Build Release first using the command in README.md." >&2
    exit 1
fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
if [[ "$bundle_id" != "zauli.med.QuotaPie" ]]; then
    echo "Unexpected app bundle identifier." >&2
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$app_path"

package_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/QuotaPie-package.XXXXXX")"
trap 'rm -rf "$package_work_dir"' EXIT
mkdir -p "$output_dir"
/usr/bin/pkgbuild --component "$app_path" --install-location /Applications \
    --identifier "$bundle_id.installer" --version "$version" \
    "$package_work_dir/QuotaPie-component.pkg"
/usr/bin/productbuild --package "$package_work_dir/QuotaPie-component.pkg" \
    "$package_work_dir/QuotaPie-Instalador.pkg"
# Copy only after successful packaging to keep a previous package on build failure.
/usr/bin/ditto "$package_work_dir/QuotaPie-Instalador.pkg" "$output_dir/QuotaPie-Instalador.pkg"
(cd "$output_dir" && /usr/bin/shasum -a 256 QuotaPie-Instalador.pkg > SHA256SUMS.txt)
echo "Created $output_dir/QuotaPie-Instalador.pkg (unsigned installer)."
