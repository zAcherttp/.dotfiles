#!/usr/bin/env swift
// Default apps for file types and URL schemes.
// Run: swift scripts/file-associations.swift   (or ./install.sh, which calls it)
//
// Uses NSWorkspace, not duti/LSSetDefaultRoleHandler: the old API returns
// success on public types (public.json, markdown, ...) but doesn't store them,
// so Xcode, which claims those types, keeps winning.
//
// One extension maps to one type, so .ts and .mts open as video (IINA) even
// when they're TypeScript. .tsx and .cts are code.

import AppKit
import UniformTypeIdentifiers

let zed = "dev.zed.Zed"
let iina = "com.colliderli.iina"
let studio = "com.Roblox.RobloxStudio"
let console = "com.apple.Console"
let chrome = "com.google.Chrome"

// Types by identifier.
let types: [(String, String)] = [
    ("public.json", zed),
    ("net.daringfireball.markdown", zed),
    ("public.plain-text", zed),
    ("public.source-code", zed),
    ("public.script", zed),
    ("public.python-script", zed),
    ("public.shell-script", zed),
    ("public.yaml", zed),
    ("public.xml", zed),
    ("public.toml", zed),
    ("public.css", zed),
    ("public.comma-separated-values-text", zed),
    ("public.c-source", zed),
    ("public.c-header", zed),
    ("public.c-plus-plus-source", zed),
    ("public.swift-source", zed),
    ("com.apple.property-list", zed),
    ("com.microsoft.ini", zed),
    ("com.microsoft.typescript", zed),
    ("com.netscape.javascript-source", zed),
    ("public.html", chrome),
    ("com.apple.log", console),
    ("public.mpeg-2-transport-stream", iina),
    ("public.avchd-mpeg-2-transport-stream", iina),
]

// Extensions with no public type of their own.
let extensions: [(String, String)] = [
    ("luau", zed), ("lua", zed), ("jsonl", zed), ("conf", zed), ("cts", zed),
    ("zsh-theme", zed), ("local", zed),
    ("rbxl", studio), ("rbxlx", studio), ("rbxm", studio), ("rbxmx", studio),
]

// Changing these asks for confirmation in a system dialog.
let schemes: [(String, String)] = [("http", chrome), ("https", chrome)]

let ws = NSWorkspace.shared
let group = DispatchGroup()

func set(_ type: UTType, _ label: String, _ bundle: String) {
    guard let app = ws.urlForApplication(withBundleIdentifier: bundle) else {
        print("skip \(label): \(bundle) not installed"); return
    }
    group.enter()
    ws.setDefaultApplication(at: app, toOpen: type) { error in
        print(error == nil ? "ok   \(label) -> \(bundle)" : "fail \(label): \(error!.localizedDescription)")
        group.leave()
    }
}

for (id, bundle) in types {
    if let type = UTType(id) { set(type, id, bundle) }
}
for (ext, bundle) in extensions {
    if let type = UTType(filenameExtension: ext) { set(type, "." + ext, bundle) }
}
for (scheme, bundle) in schemes {
    guard let app = ws.urlForApplication(withBundleIdentifier: bundle) else { continue }
    group.enter()
    ws.setDefaultApplication(at: app, toOpenURLsWithScheme: scheme) { error in
        print(error == nil ? "ok   \(scheme): -> \(bundle)" : "fail \(scheme): \(error!.localizedDescription)")
        group.leave()
    }
}

group.notify(queue: .main) { exit(0) }
RunLoop.main.run(until: Date().addingTimeInterval(120))
