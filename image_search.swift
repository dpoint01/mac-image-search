#!/usr/bin/env swift

// image_search.swift
// Search images by their visible text content using macOS Vision OCR.
//
// Zero dependencies — uses only frameworks built into macOS:
//   - Vision (OCR / text recognition)
//   - AppKit (image loading)
//   - Foundation (file system, JSON, concurrency)
//
// Supported formats: PNG, JPG, JPEG, HEIC, TIFF, BMP, GIF, WEBP
//
// Usage:
//   swift image_search.swift [OPTIONS] <term1> [term2] ...
//
// Options:
//   --dir <path>      Directory to scan (can be specified multiple times)
//   --all             Scan all common image locations (Desktop, Downloads, Documents, Pictures)
//   --cache <path>    Cache file location (default: ~/.mac-image-search-cache.json)
//   --match-all       Require ALL search terms to match (default: ANY)
//   --open            Open results folder in Finder after search
//   --rebuild         Force rebuild the OCR cache
//   --fast            Use fast OCR (~3x faster, slightly less accurate)
//   --no-cache        Disable caching entirely
//   --no-results-dir  Don't create a results folder with symlinks
//
// Security:
//   This script is 100% local. It makes ZERO network calls. No data is uploaded,
//   transmitted, or shared. All OCR processing happens on-device using Apple's
//   Vision framework. The only files written are a local JSON cache and symlinks.
//
// Examples:
//   swift image_search.swift "error"
//   swift image_search.swift --dir ~/Downloads --dir ~/Desktop "receipt"
//   swift image_search.swift --all "meeting notes"
//   swift image_search.swift --match-all "invoice" "2024"
//   swift image_search.swift --fast --rebuild "login"

import Vision
import AppKit
import Foundation

// MARK: - Configuration

let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "bmp", "gif", "webp"]

let homeDir = NSString(string: "~").expandingTildeInPath

// Common image locations for --all mode
let allDirs: [String] = [
    "~/Desktop/Screenshots",
    "~/Desktop",
    "~/Downloads",
    "~/Documents",
    "~/Pictures",
].map { NSString(string: $0).expandingTildeInPath }

// MARK: - Argument Parsing

var args = Array(CommandLine.arguments.dropFirst())
var searchDirs: [String] = []
var scanAll = false
var cachePathOverride: String? = nil
var matchAll = false
var openFolder = false
var rebuildCache = false
var useFastOCR = false
var disableCache = false
var disableResultsDir = false
var searchTerms: [String] = []

var i = 0
while i < args.count {
    switch args[i] {
    case "--dir":
        i += 1
        if i < args.count {
            searchDirs.append(NSString(string: args[i]).expandingTildeInPath)
        }
    case "--all":
        scanAll = true
    case "--cache":
        i += 1
        if i < args.count {
            cachePathOverride = NSString(string: args[i]).expandingTildeInPath
        }
    case "--match-all":
        matchAll = true
    case "--open":
        openFolder = true
    case "--rebuild":
        rebuildCache = true
    case "--fast":
        useFastOCR = true
    case "--no-cache":
        disableCache = true
    case "--no-results-dir":
        disableResultsDir = true
    case "--help", "-h":
        print("""
        image_search — Find images by their visible text content (macOS Vision OCR)

        Usage: swift image_search.swift [OPTIONS] <term1> [term2] ...

        Input Folders:
          --dir <path>      Directory to scan (can be specified multiple times)
          --all             Scan all common locations:
                              ~/Desktop/Screenshots, ~/Desktop, ~/Downloads,
                              ~/Documents, ~/Pictures

          If no --dir or --all is specified, defaults to ~/Desktop/Screenshots.
          For large folders, prefer --dir with specific paths for faster scans.

        Search Options:
          --match-all       Require ALL terms to match (default: ANY)
          --open            Open results folder in Finder

        Performance:
          --cache <path>    Cache file location (default: ~/.mac-image-search-cache.json)
          --rebuild         Force rebuild the OCR cache
          --fast            Use fast OCR (~3x faster, slightly less accurate)
          --no-cache        Disable caching entirely

        Output:
          --no-results-dir  Don't create a results folder with symlinks
          --help, -h        Show this help message

        Supported formats: PNG, JPG, JPEG, HEIC, TIFF, BMP, GIF, WEBP

        Security: 100% local. Zero network calls. No data leaves your machine.

        Examples:
          swift image_search.swift "error message"
          swift image_search.swift --dir ~/Downloads --dir ~/Desktop "receipt"
          swift image_search.swift --all "quarterly report"
          swift image_search.swift --match-all "invoice" "2024"
        """)
        exit(0)
    default:
        if args[i].hasPrefix("-") {
            print("WARNING: Unknown option '\(args[i])' — treating as search term")
        }
        searchTerms.append(args[i])
    }
    i += 1
}

guard !searchTerms.isEmpty else {
    print("ERROR: No search terms provided.")
    print("Usage: swift image_search.swift [OPTIONS] <term1> [term2] ...")
    print("Run with --help for full usage information.")
    exit(1)
}

// Resolve which directories to scan
if scanAll {
    for dir in allDirs {
        if !searchDirs.contains(dir) {
            searchDirs.append(dir)
        }
    }
}

if searchDirs.isEmpty {
    searchDirs = [NSString(string: "~/Desktop/Screenshots").expandingTildeInPath]
}

// Validate and deduplicate directories
var validDirs: [String] = []
var seenDirs: Set<String> = []
for dir in searchDirs {
    // Resolve symlinks and standardize path
    let resolved = (dir as NSString).standardizingPath
    guard !seenDirs.contains(resolved) else { continue }
    seenDirs.insert(resolved)

    var isDirFlag: ObjCBool = false
    if FileManager.default.fileExists(atPath: dir, isDirectory: &isDirFlag), isDirFlag.boolValue {
        validDirs.append(dir)
    } else {
        print("WARNING: Skipping directory (does not exist): \(dir)")
    }
}

guard !validDirs.isEmpty else {
    print("ERROR: No valid directories to scan.")
    exit(1)
}

let fileManager = FileManager.default

// MARK: - Cache

// When scanning multiple dirs, use a shared cache in the home directory
let defaultCachePath: String
if validDirs.count == 1 {
    defaultCachePath = (validDirs[0] as NSString).appendingPathComponent(".ocr_cache.json")
} else {
    defaultCachePath = (homeDir as NSString).appendingPathComponent(".mac-image-search-cache.json")
}
let cachePath = cachePathOverride ?? defaultCachePath

struct CacheEntry: Codable {
    let text: String
    let modified: Double
}

var cache: [String: [String: CacheEntry]] = [:]

if !disableCache && !rebuildCache, let data = fileManager.contents(atPath: cachePath) {
    cache = (try? JSONDecoder().decode([String: [String: CacheEntry]].self, from: data)) ?? [:]
}

// MARK: - Collect Image Files

let resultsSubdir = "image_search_results"

var allImageFiles: [(path: String, dir: String, name: String)] = []

func collectImages(in dir: String) {
    guard let files = try? fileManager.contentsOfDirectory(atPath: dir) else { return }
    for file in files {
        let ext = (file as NSString).pathExtension.lowercased()
        if supportedExtensions.contains(ext) {
            let fullPath = (dir as NSString).appendingPathComponent(file)
            allImageFiles.append((path: fullPath, dir: dir, name: file))
        }
    }
}

// Scan each directory + one level of subdirectories (skip results folders)
for dir in validDirs {
    collectImages(in: dir)
    if let topLevel = try? fileManager.contentsOfDirectory(atPath: dir) {
        for item in topLevel {
            if item == resultsSubdir { continue }
            let fullPath = (dir as NSString).appendingPathComponent(item)
            var isSubDir: ObjCBool = false
            if fileManager.fileExists(atPath: fullPath, isDirectory: &isSubDir), isSubDir.boolValue {
                collectImages(in: fullPath)
            }
        }
    }
}

guard !allImageFiles.isEmpty else {
    let dirList = validDirs.joined(separator: ", ")
    print("No images found in: \(dirList)")
    exit(0)
}

let matchMode = matchAll ? "ALL" : "ANY"
print("Search terms: \(searchTerms.joined(separator: ", "))")
print("Match mode: \(matchMode)")
print("Directories: \(validDirs.count)")
for dir in validDirs {
    print("  - \(dir)")
}
print("Total images: \(allImageFiles.count)")

// MARK: - Determine Cache Hits vs Misses

var needsOCR: [Int] = []
var cachedText: [Int: String] = [:]

for (idx, file) in allImageFiles.enumerated() {
    if !disableCache,
       let dirCache = cache[file.dir],
       let entry = dirCache[file.name] {
        let attrs = try? fileManager.attributesOfItem(atPath: file.path)
        let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        if abs(modified - entry.modified) < 1.0 {
            cachedText[idx] = entry.text
            continue
        }
    }
    needsOCR.append(idx)
}

print("Cached: \(allImageFiles.count - needsOCR.count), Need OCR: \(needsOCR.count)")
print("---")

// MARK: - Parallel OCR

if !needsOCR.isEmpty {
    let startTime = Date()
    let lock = NSLock()
    var ocrResults: [Int: String] = [:]
    var processed = 0

    let concurrency = ProcessInfo.processInfo.activeProcessorCount
    print("Running OCR with \(concurrency) threads...")

    DispatchQueue.concurrentPerform(iterations: needsOCR.count) { iter in
        let idx = needsOCR[iter]
        let file = allImageFiles[idx]

        guard let image = NSImage(contentsOfFile: file.path),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = useFastOCR ? .fast : .accurate
        request.usesLanguageCorrection = !useFastOCR

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return
        }

        let observations = request.results ?? []
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")

        lock.lock()
        ocrResults[idx] = text
        processed += 1
        if processed % 50 == 0 {
            let elapsed = Date().timeIntervalSince(startTime)
            let rate = Double(processed) / elapsed
            let remaining = Double(needsOCR.count - processed) / rate
            print("... OCR: \(processed)/\(needsOCR.count) (\(String(format: "%.0f", remaining))s remaining) ...")
        }
        lock.unlock()
    }

    let elapsed = Date().timeIntervalSince(startTime)
    print("OCR complete: \(needsOCR.count) images in \(String(format: "%.1f", elapsed))s")

    // Update cache
    if !disableCache {
        for (idx, text) in ocrResults {
            cachedText[idx] = text
            let file = allImageFiles[idx]
            let attrs = try? fileManager.attributesOfItem(atPath: file.path)
            let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            if cache[file.dir] == nil { cache[file.dir] = [:] }
            cache[file.dir]![file.name] = CacheEntry(text: text, modified: modified)
        }

        if let data = try? JSONEncoder().encode(cache) {
            fileManager.createFile(atPath: cachePath, contents: data)
        }
    } else {
        for (idx, text) in ocrResults {
            cachedText[idx] = text
        }
    }
}

// MARK: - Search

print("---")

var allMatches: [(file: String, path: String, terms: [String], snippet: String)] = []

for (idx, file) in allImageFiles.enumerated() {
    guard let text = cachedText[idx] else { continue }
    let lower = text.lowercased()

    var matchedTerms: [String] = []
    for term in searchTerms {
        if lower.contains(term.lowercased()) {
            matchedTerms.append(term)
        }
    }

    let isMatch: Bool
    if matchAll {
        isMatch = matchedTerms.count == searchTerms.count
    } else {
        isMatch = !matchedTerms.isEmpty
    }

    if isMatch {
        let snippet = String(text.prefix(300))
        print("MATCH: \(file.path)")
        print("  Matched terms: \(matchedTerms.joined(separator: ", "))")
        print("  Text: \(snippet)")
        print("")
        allMatches.append((file: file.name, path: file.path, terms: matchedTerms, snippet: snippet))
    }
}

print("---")
print("Scanned: \(allImageFiles.count) images")
print("Matches: \(allMatches.count)")

// MARK: - Results Folder

if !allMatches.isEmpty && !disableResultsDir {
    let sanitizedSearch = searchTerms.joined(separator: "_")
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .replacingOccurrences(of: ".", with: "-")

    // Place results in the first search directory
    let resultsBase = validDirs[0]
    let resultsDir = (resultsBase as NSString).appendingPathComponent("\(resultsSubdir)/\(sanitizedSearch)")

    try? fileManager.removeItem(atPath: resultsDir)
    try? fileManager.createDirectory(atPath: resultsDir, withIntermediateDirectories: true)

    print("")
    print("Results folder: \(resultsDir)")
    print("")

    for (idx, m) in allMatches.enumerated() {
        let linkPath = (resultsDir as NSString).appendingPathComponent(m.file)
        try? fileManager.createSymbolicLink(atPath: linkPath, withDestinationPath: m.path)
        print("  \(idx + 1). \(m.file)")
        print("     Terms: \(m.terms.joined(separator: ", "))")
    }

    if openFolder {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [resultsDir]
        try? task.run()
        task.waitUntilExit()
    }
} else if allMatches.isEmpty {
    print("\nNo matches found.")
}
