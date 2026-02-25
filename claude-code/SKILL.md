---
name: image-search
description: Search for text inside screenshots and images using OCR. Use this skill when the user asks to "find a screenshot", "search screenshots", "search images for text", "find an image containing", or wants to locate screenshots by their visible text content.
---

# Image Search (OCR)

Search for screenshots and images on the local machine by running OCR (text recognition) on them and matching against user-provided search terms.

## How It Works

This skill uses a Swift script that leverages macOS's built-in Vision framework for OCR. It maintains a **persistent cache** so the first scan OCRs all images (using parallel threads), and subsequent searches are near-instant.

Results are saved as **symlinks** in a subfolder: `<search-dir>/image_search_results/<query>/`

**Script location:** `~/.claude/skills/image-search/scripts/image_search.swift`

## Usage

```bash
swift ~/.claude/skills/image-search/scripts/image_search.swift [OPTIONS] <term1> [term2] ...
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--dir <path>` | Directory to scan | `~/Desktop/Screenshots` |
| `--match-all` | Require ALL terms to be present | Match ANY term |
| `--open` | Open results folder in Finder | Off |
| `--rebuild` | Force rebuild the OCR cache | Off |
| `--fast` | Use fast OCR mode (~3x faster, slightly less accurate) | Off |
| `--no-cache` | Disable caching entirely | Off |
| `--no-results-dir` | Don't create symlink results folder | Off |

## Steps to Follow

1. **Determine search terms** from the user's request.
2. **Determine directory** — default is `~/Desktop/Screenshots`. If the user mentions Downloads, Documents, or another folder, use `--dir`.
3. **Determine match mode** — if the user wants images containing ALL terms, use `--match-all`. If ANY term, omit it.
4. **Run the script** with a 10-minute timeout:
   ```bash
   swift ~/.claude/skills/image-search/scripts/image_search.swift [options] "term1" "term2" ...
   ```
5. **Present results** to the user in a readable table format.
6. **If the user wants to open them**, re-run with `--open` or use `open <results-folder-path>`.

## Performance

- **First run**: Parallel OCR using all CPU cores. ~500 images in ~2 min.
- **Subsequent runs**: Near-instant (cache lookup only).
- **Cache auto-invalidates** when a file's modification date changes.
