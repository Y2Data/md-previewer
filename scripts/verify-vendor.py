"""Check that the bundled offline assets match their committed SHA-256 manifest."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "ClearMark/Resources/Vendor"
manifest = json.loads((root / "manifest.json").read_text())
expected = set(manifest["files"])
actual = {str(path.relative_to(root)) for path in root.rglob("*") if path.is_file() and path.name != "manifest.json" and not path.name.startswith("._")}
if expected != actual:
    raise SystemExit(f"Vendor file list changed: missing={expected-actual}, extra={actual-expected}")
for name, digest in manifest["files"].items():
    if hashlib.sha256((root / name).read_bytes()).hexdigest() != digest:
        raise SystemExit(f"Vendor checksum mismatch: {name}")
print(f"Verified {len(expected)} vendored assets.")
