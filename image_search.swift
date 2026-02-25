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
//   --dir <path>      Directory to scan (default: ~/Desktop/Screenshots)
//   --cache <path>    Cache file location (default: ./.ocr_cache.json)
//   --match-all       Require ALL search terms to match (default: ANY)
//   --open            Open results folder in Finder after search
//   --rebuild         Force rebuild the OCR cache
//   --fast            Use fast OCR (~3x faster, slightly less accurate)
//   --no-cache        Disable caching entirely
//   --no-results-dir  Don't create a results folder with symlinks
//
// Examples:
//   swift image_search.swift "error"
//   swift image_search.swift --match-all "invoice" "2024"
//   swift image_search.swift --dir ~/Downloads --open "receipt"
//   swift image_search.swift --fast --rebuild "login"

import Vision
import AppKit
import Foundation

// MARK: - Configuration

let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "bmp", "gif", "webp"]

// MARK: - Argument Parsing

var args = Array(CommandLine.arguments.dropFirst())
var searchDir = NSString(string: "~/Desktop/Screenshots").expandingTildeInPath
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
            searchDir = NSString(string: args[i]).expandingTildeInPath
        }
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

        Options:
          --dir <path>      Directory to scan (default: ~/Desktop/Screenshots)
          --cache <path>    Cache file location (default: ./.ocr_cache.json)
          --match-all       Require ALL terms to match (default: ANY)
          --open            Open results folder in Finder
          --rebuild         Force rebuild the OCR cache
          --fast            Use fast OCR (~3x faster, slightly less accurate)
          --no-cache        Disable caching entirely
          --no-results-dir  Don't create a results folder with symlinks
          --help, -h        Show this help message

        Supported formats: PNG, JPG, JPEG, HEIC, TIFF, BMP, GIF, WEBP

        Examples:
          swift image_search.swift "error message"
          swift image_search.swift --match-all "invoice" "2024"
          swift image_search.swift --dir ~/Downloads --open "receipt"
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

// Validate search directory exists
var isDirFlag: ObjCBool = false
guard FileManager.default.fileExists(atPath: searchDir, isDirectory: &isDirFlag), isDirFlag.boolValue else {
    print("ERROR: Directory does not exist: \(searchDir)")
    exit(1)
}

let fileManager = FileManager.default

// MARK: - Cache

let cachePath = cachePathOverride ?? (searchDir as NSString).appendingPathComponent(".ocr_cache.json")

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

// Scan top-level dir + one level of subdirectories (skip results folder)
collectImages(in: searchDir)
if let topLevel = try? fileManager.contentsOfDirectory(atPath: searchDir) {
    for item in topLevel {
        if item == resultsSubdir { continue }
        let fullPath = (searchDir as NSString).appendingPathComponent(item)
        var isSubDir: ObjCBool = false
        if fileManager.fileExists(atPath: fullPath, isDirectory: &isSubDir), isSubDir.boolValue {
            collectImages(in: fullPath)
        }
    }
}

guard !allImageFiles.isEmpty else {
    print("No images found in: \(searchDir)")
    exit(0)
}

let matchMode = matchAll ? "ALL" : "ANY"
print("Search terms: \(searchTerms.joined(separator: ", "))")
print("Match mode: \(matchMode)")
print("Directory: \(searchDir)")
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
    let resultsDir = (searchDir as NSString).appendingPathComponent("\(resultsSubdir)/\(sanitizedSearch)")

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
