<p align="center">
  <h1 align="center">mac-image-search</h1>
  <p align="center">
    Search your images and screenshots by what's <strong>in</strong> them, not what they're named.
    <br />
    <em>A single Swift script. Zero dependencies. Runs on any Mac.</em>
  </p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013+-blue?logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/swift-5.9+-orange?logo=swift" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/dependencies-0-brightgreen" alt="Zero dependencies">
  <img src="https://img.shields.io/badge/processing-100%25%20local-purple" alt="100% local">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="MIT License">
</p>

---

### The problem

You took a screenshot of something important. Now you need it. But your screenshots folder looks like this:

```
Screenshot 2025-06-13 at 9.17.27 AM.png
Screenshot 2025-10-31 at 10.04.32 AM.png
Screenshot 2025-11-20 at 9.43.44 AM.png
... × 500 more
```

macOS Spotlight doesn't OCR screenshot content. You're stuck scrolling through thumbnails.

### The solution

Search by what you **see** in the image:

<p align="center">
  <img src="assets/example.png" alt="Example: a screenshot of a chat message about a hyped up AI tool" width="700" style="border-radius: 8px; border: 1px solid #333;">
</p>

```
$ swift image_search.swift "hyped up AI tool"

Search terms: hyped up AI tool
Directory: ~/Desktop/Screenshots
Total images: 556
Cached: 556, Need OCR: 0
---
MATCH: ~/Desktop/Screenshots/Screenshot 2026-03-03 at 1.27.42 PM.png
  Matched terms: hyped up AI tool
  Text: You had really specific conversation about a new hyped up AI tool
  and took a screenshot to remember it. But now you have hundreds of
  screenshots to look into. You're trying to find it, mac-image-search
  will help.
---
Scanned: 556 images
Matches: 1
```

Found in **< 1 second** (cached). That's it.

---

## Quick Start

Two ways to use it — pick whichever fits your workflow:

### Option A: Use with Claude Code

If you use [Claude Code](https://docs.anthropic.com/en/docs/claude-code), install it as a skill and search with natural language:

```bash
# Clone and install the skill
git clone https://github.com/dpoint01/mac-image-search.git
cd mac-image-search
mkdir -p ~/.claude/skills/image-search/scripts
cp image_search.swift ~/.claude/skills/image-search/scripts/
cp claude-code/SKILL.md ~/.claude/skills/image-search/
```

Then in Claude Code:
```
> search my screenshots for "meeting notes"
> find images containing "error" in my Downloads folder
> /image-search quarterly report
```

To auto-approve (no confirmation prompts), add to `~/.claude/settings.local.json` under `permissions.allow`:
```json
"Bash(swift ~/.claude/skills/image-search/scripts/image_search.swift:*)"
```

### Option B: Use directly with Swift

No Claude Code needed. Just run the script from your terminal:

```bash
git clone https://github.com/dpoint01/mac-image-search.git
cd mac-image-search
swift image_search.swift "your search term"
```

No `brew install`. No `pip install`. No `npm install`. Just `swift` — which is already on your Mac.

---

## How It Works

```
┌─────────────┐     ┌──────────────────┐     ┌────────────────┐
│  Scan dir   │────▶│  Parallel OCR    │────▶│  Cache to JSON │
│  for images │     │  (all CPU cores) │     │  (auto-expire) │
└─────────────┘     └──────────────────┘     └────────────────┘
                                                      │
                                                      ▼
                    ┌──────────────────┐     ┌────────────────┐
                    │  Results folder  │◀────│  Text search   │
                    │  (symlinks)      │     │  (< 1 second)  │
                    └──────────────────┘     └────────────────┘
```

1. **Scan** — Collects all image files (PNG, JPG, JPEG, HEIC, TIFF, BMP, GIF, WEBP) from the target directories + one level of subdirectories
2. **OCR** — Runs macOS Vision text recognition in parallel across all CPU cores
3. **Cache** — Saves recognized text to a JSON file. Only new/modified files get re-OCR'd
4. **Search** — Case-insensitive text matching against the cached OCR results
5. **Results** — Creates a folder with symlinks to matching files for easy browsing in Finder

### Performance

| | First Run | Subsequent Runs |
|---|---|---|
| **~500 images** | ~2 min (parallel OCR) | **< 1 second** (cache) |
| **CPU usage** | All cores (parallel GCD) | Negligible |
| **Cache** | Auto-invalidates when files change | |

## Zero Dependencies

The script uses **only frameworks built into macOS**. Nothing to install, nothing to audit, nothing to break.

| Framework | Purpose | Ships with |
|-----------|---------|------------|
| `Vision` | Text recognition (OCR) | macOS 10.15+ |
| `AppKit` | Image loading | macOS 10.0+ |
| `Foundation` | File system, JSON, GCD concurrency | macOS 10.0+ |

**Requirements:**
- macOS 13+ (Ventura or later)
- Swift (pre-installed with Xcode or Command Line Tools: `xcode-select --install`)

## Options

```
swift image_search.swift [OPTIONS] <term1> [term2] ...
```

**Input Folders:**

| Flag | Description | Default |
|------|-------------|---------|
| `--dir <path>` | Directory to scan (can be specified multiple times) | `~/Desktop/Screenshots` |
| `--all` | Scan all common locations (Desktop/Screenshots, Desktop, Downloads, Documents, Pictures) | Off |

> **Tip:** For faster, more targeted scans, use `--dir` with specific folders rather than `--all`.

**Search & Output:**

| Flag | Description | Default |
|------|-------------|---------|
| `--match-all` | Require ALL terms to match | Match ANY term |
| `--open` | Open results folder in Finder | Off |
| `--no-results-dir` | Don't create results folder | Off |

**Performance:**

| Flag | Description | Default |
|------|-------------|---------|
| `--cache <path>` | Cache file location | Auto (per-dir or shared) |
| `--rebuild` | Force re-OCR all images | Off |
| `--fast` | Fast OCR mode (~3x faster, less accurate) | Off |
| `--no-cache` | Disable caching | Off |
| `--help` | Show help | |

## Examples

```bash
# Search default screenshots folder
swift image_search.swift "connection refused"

# Search a specific folder
swift image_search.swift --dir ~/Downloads "receipt" "invoice"

# Search multiple folders at once
swift image_search.swift --dir ~/Downloads --dir ~/Desktop "quarterly report"

# Search all common locations (Desktop, Downloads, Documents, Pictures)
swift image_search.swift --all "meeting notes"

# Require ALL terms to match
swift image_search.swift --match-all "Alice" "Project Alpha"

# Fast initial scan of a large folder
swift image_search.swift --fast --dir ~/Pictures "vacation"

# Re-index everything (useful if you edited images)
swift image_search.swift --rebuild "quarterly report"

# Search without leaving files behind
swift image_search.swift --no-results-dir --no-cache "password reset"
```

## Supported Formats

PNG, JPG, JPEG, HEIC, TIFF, BMP, GIF, WEBP

## Cache

The OCR cache (`.ocr_cache.json`) maps each file to its recognized text and last-modified timestamp.

- **Auto-invalidation** — modified files get re-OCR'd on next run
- **Force rebuild** — `--rebuild` to re-OCR everything
- **Disable** — `--no-cache` for one-off searches
- **Safe to delete** — it rebuilds automatically

## Security & Privacy

This script is **100% local**. It makes **zero network calls**. No data is uploaded, transmitted, or shared — ever.

| Guarantee | Details |
|-----------|---------|
| **No network access** | Zero HTTP requests, zero sockets, zero DNS lookups. The script imports only `Vision`, `AppKit`, and `Foundation` — no networking frameworks. |
| **Read-only on your images** | Never modifies, moves, or deletes your files. Only writes a local JSON cache and symlinks. |
| **Nothing to install** | Zero third-party dependencies. Only macOS built-in frameworks. Nothing to audit except one Swift file. |
| **No telemetry** | No analytics, no tracking, no crash reporting. |
| **Cache is local** | OCR text is cached in a local JSON file. Add `.ocr_cache.json` to `.gitignore` if your images contain sensitive content. |

You can verify this yourself — the entire tool is a single readable Swift file.

## License

MIT
