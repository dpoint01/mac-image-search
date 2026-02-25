# mac-image-search

Search your images and screenshots by what's **in** them, not what they're named.

A single Swift script that uses macOS Vision to OCR your images, caches the results, and lets you search by text content. No dependencies to install — it runs on any Mac.

```
$ swift image_search.swift "invoice"

Search terms: invoice
Directory: /Users/me/Desktop/Screenshots
Total images: 556
Cached: 556, Need OCR: 0
---
MATCH: /Users/me/Desktop/Screenshots/Screenshot 2025-08-12 at 3.22.01 PM.png
  Matched terms: invoice
  Text: Invoice #4821 — Acme Corp — $1,250.00 — Due: September 1, 2025...
---
Scanned: 556 images
Matches: 1

Results folder: /Users/me/Desktop/Screenshots/image_search_results/invoice
```

## Why

macOS screenshots are named `Screenshot 2025-01-01 at 10.00.00 AM.png`. When you have hundreds, finding a specific one means scrolling through thumbnails and hoping you remember the date. Spotlight doesn't OCR screenshot content.

This script lets you search by what you **see** in the image: a name, an error message, a URL, a company name — anything the OCR can read.

## Requirements

- **macOS 13+** (Ventura or later)
- **Swift** (pre-installed with Xcode or Command Line Tools: `xcode-select --install`)
- That's it. Zero external dependencies.

The script uses only frameworks that ship with macOS:
| Framework | Purpose |
|-----------|---------|
| `Vision` | Text recognition (OCR) |
| `AppKit` | Image loading |
| `Foundation` | File system, JSON, concurrency |

## Quick Start

```bash
# Clone the repo
git clone https://github.com/dpoint01/mac-image-search.git
cd mac-image-search

# Make it executable (optional)
chmod +x image_search.swift

# Search your screenshots
swift image_search.swift "error"

# Search a specific folder
swift image_search.swift --dir ~/Downloads "receipt"

# Require ALL terms to match
swift image_search.swift --match-all "slack" "meeting notes"

# Open matching results in Finder
swift image_search.swift --open "budget"
```

## How It Works

1. **Scan** — Collects all image files (PNG, JPG, JPEG, HEIC, TIFF, BMP, GIF, WEBP) from the target directory and one level of subdirectories
2. **OCR** — Runs macOS Vision text recognition in parallel across all CPU cores
3. **Cache** — Saves recognized text to a JSON cache file. Subsequent searches skip OCR entirely and run in under 1 second
4. **Search** — Case-insensitive text matching against the OCR results
5. **Results** — Creates a folder with symlinks to matching files so you can browse them in Finder

### Performance

| | First Run | Subsequent Runs |
|---|---|---|
| **~500 images** | ~2 min (parallel OCR) | < 1 second (cache) |
| **CPU usage** | All cores (parallel GCD) | Negligible |
| **Cache invalidation** | Automatic (checks file modification dates) |

## Options

```
swift image_search.swift [OPTIONS] <term1> [term2] ...
```

| Flag | Description | Default |
|------|-------------|---------|
| `--dir <path>` | Directory to scan | `~/Desktop/Screenshots` |
| `--cache <path>` | Cache file location | `.ocr_cache.json` in search dir |
| `--match-all` | Require ALL terms to match | Match ANY term |
| `--open` | Open results folder in Finder | Off |
| `--rebuild` | Force re-OCR all images | Off |
| `--fast` | Fast OCR mode (~3x faster, less accurate) | Off |
| `--no-cache` | Disable caching | Off |
| `--no-results-dir` | Don't create results folder | Off |
| `--help` | Show help | |

## Examples

```bash
# Find screenshots containing an error message
swift image_search.swift "connection refused"

# Find receipts or invoices in Downloads
swift image_search.swift --dir ~/Downloads "receipt" "invoice"

# Find screenshots with both a person's name AND a project name
swift image_search.swift --match-all "Alice" "Project Alpha"

# Fast initial scan of a large folder (trades some accuracy for speed)
swift image_search.swift --fast --dir ~/Pictures "vacation"

# Re-index everything (useful if you edited images)
swift image_search.swift --rebuild "quarterly report"

# Search without leaving files behind
swift image_search.swift --no-results-dir --no-cache "password reset"
```

## Supported Image Formats

PNG, JPG, JPEG, HEIC, TIFF, BMP, GIF, WEBP

## Cache

The OCR cache is stored as `.ocr_cache.json` in the search directory (or a custom path via `--cache`). It maps each file to its recognized text and last-modified timestamp.

- **Auto-invalidation**: If a file's modification date changes, it gets re-OCR'd on the next run
- **Force rebuild**: Use `--rebuild` to re-OCR everything
- **Disable**: Use `--no-cache` for one-off searches

The cache file is safe to delete at any time — it will be rebuilt on the next run.

## Use with Claude Code

This repo includes a ready-to-use [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill. To install:

```bash
# Copy the skill into your Claude Code skills directory
mkdir -p ~/.claude/skills/image-search/scripts
cp image_search.swift ~/.claude/skills/image-search/scripts/
cp claude-code/SKILL.md ~/.claude/skills/image-search/

# (Optional) Auto-approve the script in your settings
# Add to ~/.claude/settings.local.json under permissions.allow:
# "Bash(swift ~/.claude/skills/image-search/scripts/image_search.swift:*)"
```

Then in Claude Code, just say "search my screenshots for meeting notes" or invoke `/image-search meeting notes`.

## Security & Privacy

- **All processing is local**. No data leaves your machine. No cloud APIs, no network calls.
- **Read-only**. The script never modifies, moves, or deletes your images. The only files it writes are the cache (`.ocr_cache.json`) and symlinks in the results folder.
- **No dependencies**. No `pip install`, no `npm`, no `brew`. Nothing to audit except this single Swift file.
- **Cache contains OCR text**. The `.ocr_cache.json` file stores recognized text from your images. Add it to `.gitignore` if your images contain sensitive information.

## License

MIT
