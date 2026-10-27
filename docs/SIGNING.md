# Signing and notarization

**Version 0.2.0 beta 2 has a Developer ID Installer-signed PKG with a trusted timestamp.** The included app and Quick Look extension are Developer ID Application-signed. **Apple notarization remains pending.** Beta 1's installer was unsigned; its app payload is unchanged in beta 2. Signing and notarization are separate steps, and a signed installer alone does not establish Gatekeeper acceptance.

Before a general release, the maintainer needs:

1. A **Developer ID Application** certificate and private key for the app and Quick Look extension.
2. A **Developer ID Installer** certificate and private key for the PKG.
3. A working `notarytool` keychain profile. Store its credentials locally with `xcrun notarytool store-credentials`; do not commit credentials, private keys, or certificates containing private keys.

Both targets use the shared macOS app group `DTTKLCXH53.dev.y2data.clearmark`. When signing with another team, update the group identifier in `project.yml` and `ClearMark/Preferences/PreviewSettings.swift` to start with that team’s identifier. Keep both targets on the same team and group. This allows Quick Look to read settings after the main app has exited.

Build the universal app with hardened runtime and secure timestamps:

```sh
xcodebuild -project ClearMark.xcodeproj -scheme ClearMark \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/Distribution 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  DEVELOPMENT_TEAM=DTTKLCXH53 CODE_SIGN_STYLE=Manual \
  'CODE_SIGN_IDENTITY=Developer ID Application: YUHAO DAI (DTTKLCXH53)' \
  OTHER_CODE_SIGN_FLAGS=--timestamp build
```

Package, sign, submit to Apple, staple the ticket, and assess the completed installer:

```sh
python3 scripts/package-release.py \
  --app build/Distribution/Build/Products/Release/ClearMark.app \
  --output build/releases/signed \
  --installer-identity 'Developer ID Installer: YOUR NAME (TEAMID)' \
  --notary-profile YOUR_KEYCHAIN_PROFILE
```

The script refuses to overwrite an existing installer. It creates a checksum after stapling. It uses no install scripts, launch agents, login items, or background services. Payload relocation is disabled so an old development copy does not redirect installation away from `/Applications`.

For build environments that need each packaging command executed separately, `--stage-only PATH` prepares the payload, distribution metadata, and a `plan.json` without creating an installer. Run the plan’s signature verification before its packaging commands, verify the extracted final payload, and generate a SHA-256 checksum. Staging mode produces only unsigned beta inputs and cannot be combined with signing or notarization options.

Before publishing a stable release, verify on a clean Mac that the downloaded installer passes Gatekeeper, installs the app and extension, and that Finder previews Markdown with ClearMark closed. Enable the extension once in System Settings if macOS requires it. Test both English and Chinese settings and confirm they affect the next Finder preview. A successful app build does not establish that Finder registration or Gatekeeper validation succeeded.

For a signed beta without notarization, supply `--installer-identity` and omit `--notary-profile`. Omitting both creates an unsigned beta. The output name includes `-beta` whenever notarization is omitted. Verify the installer with `pkgutil --check-signature`, then upload the PKG and its `.sha256` file to a GitHub prerelease with its exact signing and notarization status.
