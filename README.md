# browser-lists

Content-blocking lists for the WebBrowser app, converted to the format WebKit
understands and published daily to <https://lists.keval.ca>.

## What's published

| File | What it is |
|---|---|
| `manifest.json` | Describes every list: its file, size, rule count and SHA-256 fingerprint. The app downloads this first and only fetches lists whose fingerprint changed. |
| `easylist.json` | EasyList, which blocks ads. |

## How it works

`scripts/build-lists.sh` downloads each list, converts it with AdGuard's
[SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib), and
writes the results and the manifest into `public/`. The GitHub Action in
`.github/workflows/build-lists.yml` runs it every day and publishes `public/`
to GitHub Pages. If a build fails, nothing is published and the previous
lists stay up.

To build locally, see the comment at the top of the script.

## Credits and licenses

The published lists are converted from:

- **EasyList** by The EasyList authors, <https://easylist.to/>, licensed under
  [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) or
  [GPL-3.0](https://www.gnu.org/licenses/gpl-3.0.html). The converted
  `easylist.json` is a derivative of EasyList and is available under the same
  terms.

The conversion uses SafariConverterLib by AdGuard, available under GPL-3.0 or
Apache 2.0. It runs only while building the lists and isn't part of the
published files.
