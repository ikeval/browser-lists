#!/bin/bash
# Builds the content-blocking lists the browser downloads, plus the manifest
# that describes them, into public/.
#
# Usage: scripts/build-lists.sh
#
# The GitHub Action in .github/workflows runs this daily and publishes public/
# to https://lists.keval.ca. To run it locally you need internet access,
# Python 3, and AdGuard's SafariConverterLib cloned and built next to this
# repository:
#
#     git clone https://github.com/AdguardTeam/SafariConverterLib ../SafariConverterLib
#     (cd ../SafariConverterLib && swift build -c release)
#
# To use a ConverterTool somewhere else, set CONVERTER to its path.
set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT_DIR="public"
CONVERTER="${CONVERTER:-../SafariConverterLib/.build/release/ConverterTool}"
CONVERTER_VERSION="${CONVERTER_VERSION:-$(git -C "$(dirname "$CONVERTER")/../.." describe --tags 2>/dev/null || echo unknown)}"

# The oldest Safari (WebKit) version the app runs on. The app needs iOS 27,
# and 26 is the newest version the converter knows by name.
SAFARI_VERSION=26

# How often the app should check the manifest for changes.
CHECK_EVERY_HOURS=24

# The lists to build, one per line:
# name, output file, source name, source website, download address.
LISTS="
ads	easylist.json	EasyList	https://easylist.to/	https://easylist.to/easylist/easylist.txt
"

if [ ! -x "$CONVERTER" ]; then
    echo "Can't find ConverterTool at $CONVERTER" >&2
    echo "Build it with: (cd ../SafariConverterLib && swift build -c release)" >&2
    echo "or set CONVERTER to its path." >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$OUTPUT_DIR"

# Download and convert each list, noting where its result is for the step below.
while IFS=$'\t' read -r name file source source_url download_url; do
    [ -z "$name" ] && continue
    curl -fsSL "$download_url" -o "$work/$name.txt"
    version=$(grep -m 1 -E '^! (Version|Last modified):' "$work/$name.txt" | sed -E 's/^! [^:]+: *//' || true)
    # --input-path rather than piping the list in: the tool stops reading
    # piped input at the first blank line.
    "$CONVERTER" convert --input-path "$work/$name.txt" --safari-version "$SAFARI_VERSION" > "$work/$name.result.json"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$file" "$source" "$source_url" "${version:-unknown}" "$work/$name.result.json" >> "$work/lists.tsv"
done <<< "$LISTS"

# Write each list's rules one per line, then the manifest. If anything looks
# wrong this exits with an error, and the Action keeps the previous files.
python3 - "$OUTPUT_DIR" "$work/lists.tsv" "$CONVERTER_VERSION" "$SAFARI_VERSION" "$CHECK_EVERY_HOURS" <<'PY'
import datetime, hashlib, json, os, sys

output_dir, lists_tsv, converter_version, safari_version, check_every_hours = sys.argv[1:]

# Far below any real list; a list this small means a download or conversion went wrong.
MINIMUM_RULES = 1000
# WebKit won't compile a rule list longer than this.
WEBKIT_LIMIT = 150_000

entries = []
with open(lists_tsv) as f:
    for line in f:
        name, file, source, source_url, source_version, result_path = line.rstrip("\n").split("\t")
        with open(result_path) as r:
            result = json.load(r)
        rules = json.loads(result["safariRulesJSON"])

        print(f"{source} {source_version}: {result['sourceRulesCount']} lines")
        print(f"  {len(rules)} WebKit rules, {result['errorsCount']} couldn't be converted, "
              f"{result['discardedSafariRules']} dropped for WebKit's limits")

        if result["discardedSafariRules"] > 0 or len(rules) > WEBKIT_LIMIT:
            sys.exit(f"{source} doesn't fit WebKit's limit of {WEBKIT_LIMIT} rules per list.")
        if len(rules) < MINIMUM_RULES:
            sys.exit(f"{source} has only {len(rules)} rules, which suggests something went wrong.")

        body = ("[\n" + ",\n".join(
            json.dumps(rule, separators=(",", ":"), ensure_ascii=False) for rule in rules
        ) + "\n]\n").encode()
        with open(os.path.join(output_dir, file), "wb") as out:
            out.write(body)

        entries.append({
            "name": name,
            "file": file,
            "sha256": hashlib.sha256(body).hexdigest(),
            "bytes": len(body),
            "rules": len(rules),
            "source": source,
            "sourceURL": source_url,
            "sourceVersion": source_version,
        })

manifest = {
    "format": 1,
    "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "checkEveryHours": int(check_every_hours),
    "converter": converter_version,
    "safariVersion": safari_version,
    "lists": entries,
}
with open(os.path.join(output_dir, "manifest.json"), "w") as out:
    json.dump(manifest, out, indent=2)
    out.write("\n")
print(f"Wrote {len(entries)} list(s) and manifest.json to {output_dir}/")
PY
