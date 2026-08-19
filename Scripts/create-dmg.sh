#!/bin/bash

set -euo pipefail

readonly APP_PATH="${1:?Usage: create-dmg.sh <app-path> <output-directory> <version>}"
readonly OUTPUT_DIRECTORY="${2:?Missing output directory}"
readonly VERSION="${3:?Missing version}"
readonly VOLUME_NAME="MacFan"
readonly DMG_NAME="${VOLUME_NAME}-${VERSION}-arm64.dmg"

if [[ ! -d "${APP_PATH}" ]]; then
    echo "Application bundle not found: ${APP_PATH}" >&2
    exit 1
fi

readonly STAGING_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "${STAGING_DIRECTORY}"' EXIT

mkdir -p "${OUTPUT_DIRECTORY}"
ditto "${APP_PATH}" "${STAGING_DIRECTORY}/${VOLUME_NAME}.app"
ln -s /Applications "${STAGING_DIRECTORY}/Applications"

hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_DIRECTORY}" \
    -format UDZO \
    -ov \
    "${OUTPUT_DIRECTORY}/${DMG_NAME}"

shasum -a 256 "${OUTPUT_DIRECTORY}/${DMG_NAME}" \
    > "${OUTPUT_DIRECTORY}/${DMG_NAME}.sha256"
