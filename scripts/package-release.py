"""Build a script-free macOS installer; optionally sign, notarize, and staple it.

The input app must already be signed. Never pass passwords or keys on the command
line: notarization uses an existing notarytool keychain profile.
"""
import argparse
import contextlib
import hashlib
import html
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


def run(*arguments, **kwargs):
    subprocess.run([str(value) for value in arguments], check=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--installer-identity", help="Developer ID Installer identity name")
    parser.add_argument("--notary-profile", help="Existing notarytool keychain profile; requires installer signing")
    parser.add_argument("--stage-only", type=Path, help="Prepare persistent packaging inputs without building an installer; run the printed commands separately")
    args = parser.parse_args()
    app = args.app.resolve()
    output = args.output.resolve()
    if args.notary_profile and not args.installer_identity:
        parser.error("--notary-profile requires --installer-identity")
    if args.stage_only and (args.installer_identity or args.notary_profile):
        parser.error("--stage-only prepares unsigned beta inputs; signing must be run as a separate release step")
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    version = info["CFBundleShortVersionString"]
    if info["CFBundleIdentifier"] != "dev.y2data.clearmark":
        parser.error("The input is not a ClearMark app bundle.")
    run("lipo", "-verify_arch", "arm64", "x86_64", app / "Contents/MacOS" / info["CFBundleExecutable"])
    run("lipo", "-verify_arch", "arm64", "x86_64", app / "Contents/PlugIns/ClearMarkQuickLook.appex/Contents/MacOS/ClearMarkQuickLook")
    if not args.stage_only:
        run("codesign", "--verify", "--deep", "--strict", app)
    output.mkdir(parents=True, exist_ok=True)
    suffix = "" if args.notary_profile else "-beta"
    package = output / f"ClearMark-{version}-macOS-universal{suffix}.pkg"
    if package.exists():
        parser.error(f"Refusing to overwrite an existing installer: {package}")
    manager = contextlib.nullcontext(args.stage_only.resolve()) if args.stage_only else tempfile.TemporaryDirectory(prefix="clearmark-package-")
    with manager as temporary:
        work = Path(temporary)
        payload = work / "payload/Applications"
        payload.mkdir(parents=True)
        run("ditto", "--norsrc", app, payload / "ClearMark.app")
        components = [{"RootRelativeBundlePath": "Applications/ClearMark.app", "BundleIsRelocatable": False,
                       "BundleIsVersionChecked": True, "BundleHasStrictIdentifier": True, "BundleOverwriteAction": "upgrade"}]
        with (work / "components.plist").open("wb") as handle:
            plistlib.dump(components, handle)
        identifier = "dev.y2data.clearmark.installer"
        component = work / "ClearMark-component.pkg"
        component_command = ["pkgbuild", "--root", work / "payload", "--component-plist", work / "components.plist",
                             "--identifier", identifier, "--version", version, "--install-location", "/", "--ownership", "recommended", component]
        if not args.stage_only:
            run(*component_command)
        resources = work / "resources"
        resources.mkdir()
        root = Path(__file__).resolve().parents[1]
        shutil.copyfile(root / "LICENSE", resources / "license.txt")
        notices = {
            "en": ("Markdown. Just press Space.", "ClearMark will be installed in Applications. Select a Markdown file in Finder and press Space. Open the app only to change settings. If needed, enable ClearMark Preview in System Settings → Extensions → Quick Look.", "This beta installer is not notarized by Apple. macOS may require explicit approval before installation."),
            "zh-Hans": ("Markdown，按空格即可预览。", "ClearMark 将安装到“应用程序”文件夹。在访达中选中 Markdown 文件，按空格键即可预览。仅在需要修改设置时打开应用。如未生效，请在系统设置 → 扩展 → 快速预览中启用 ClearMark Preview。", "此测试版安装包尚未经 Apple 公证。macOS 可能要求你明确允许后才能安装。"),
        }
        for language, (title, body, warning) in notices.items():
            folder = resources / f"{language}.lproj"
            folder.mkdir()
            notice = "" if args.notary_profile else f"<p><strong>{html.escape(warning)}</strong></p>"
            (folder / "welcome.html").write_text(f'<!doctype html><meta charset="utf-8"><style>body{{font:14px -apple-system,sans-serif;line-height:1.7;padding:18px}}h1{{font-size:24px}}</style><h1>{html.escape(title)}</h1><p>{html.escape(body)}</p>{notice}')
        distribution = work / "Distribution.xml"
        distribution.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>ClearMark {html.escape(version)}</title>
  <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
  <welcome file="welcome.html"/><license file="license.txt"/>
  <choices-outline><line choice="default"><line choice="{identifier}"/></line></choices-outline>
  <choice id="default" title="ClearMark"/>
  <choice id="{identifier}" visible="false"><pkg-ref id="{identifier}"/></choice>
  <pkg-ref id="{identifier}" version="{html.escape(version)}" onConclusion="none">ClearMark-component.pkg</pkg-ref>
</installer-gui-script>
''')
        unsigned = work / "ClearMark-unsigned.pkg"
        if args.stage_only:
            import json
            plan = [["codesign", "--verify", "--deep", "--strict", payload / "ClearMark.app"], component_command,
                    ["productbuild", "--distribution", distribution, "--resources", resources, "--package-path", work, package]]
            (work / "plan.json").write_text(json.dumps([[str(value) for value in command] for command in plan], indent=2))
            print(f"Prepared inputs in {work}. No installer was created. Run the verification and build commands in plan.json, then verify the extracted payload and generate a checksum.")
            return
        run("productbuild", "--distribution", distribution, "--resources", resources, "--package-path", work, unsigned)
        if args.installer_identity:
            run("productsign", "--sign", args.installer_identity, "--timestamp", unsigned, package)
        else:
            shutil.copyfile(unsigned, package)
    if args.notary_profile:
        run("xcrun", "notarytool", "submit", package, "--keychain-profile", args.notary_profile, "--wait")
        run("xcrun", "stapler", "staple", package)
        run("xcrun", "stapler", "validate", package)
        run("spctl", "--assess", "--type", "install", "--verbose=2", package)
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    (output / (package.name + ".sha256")).write_text(f"{digest}  {package.name}\n")
    print(f"Installer: {package}\nSHA-256: {digest}")


if __name__ == "__main__":
    main()
