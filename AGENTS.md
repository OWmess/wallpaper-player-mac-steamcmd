# Repository Guidelines

## Project Structure & Module Organization

This repository contains a macOS SwiftUI/AppKit app plus DocC documentation targets. App code lives in `Open Wallpaper Engine/`: `Services/` holds wallpaper parsing and settings models, `ContentView/` contains the main explorer UI, `WallpaperView/` renders wallpapers, `SettingsView/` handles preferences, and `MenuBars/` owns menu/status bar integration. App assets are under `Open Wallpaper Engine/Resources/`, with localized strings in `Localizable.xcstrings`.

XCTest targets live in `Open Wallpaper EngineTests/` and `Open Wallpaper EngineUITests/`. Documentation package targets live in `Sources/User_Documentation_en_US/` and `Sources/User_Documentation_zh_CN/`. README images are in `resources/`, release notes in `TestFlight/`, and the Pages workflow is `.github/workflows/docs.yml`.

## Build, Test, and Development Commands

- `open "Open Wallpaper Engine.xcodeproj"`: open the app in Xcode for signing setup and interactive runs.
- `xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -derivedDataPath DerivedData build`: build the macOS app locally.
- `xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -derivedDataPath DerivedData test`: run unit and UI tests.
- `swift build`: validate the Swift package used for DocC documentation.
- `swift package --allow-writing-to-directory ./.docc-build/en_us generate-documentation --target User_Documentation_en_US --disable-indexing --transform-for-static-hosting --hosting-base-path wallpaper-player-mac/en_us --output-path ./.docc-build/en_us`: render English docs locally; use `zh_cn` and `User_Documentation_zh_CN` for Chinese docs.

## Coding Style & Naming Conventions

Use Swift defaults with four-space indentation. Name types in `UpperCamelCase` and methods, properties, and enum cases in `lowerCamelCase`. Keep file names aligned with their primary type or view, for example `WallpaperViewModel.swift` or `ExplorerItem.swift`. Prefer SwiftUI view composition for UI changes and keep AppKit lifecycle/window behavior in `AppDelegate` or existing window/menu components. Do not commit generated `.build/`, `.docc-build/`, `DerivedData/`, or user-specific Xcode files.

## Testing Guidelines

Use XCTest. Put unit coverage in `Open Wallpaper EngineTests/` and UI workflows in `Open Wallpaper EngineUITests/`. Name tests after behavior, such as `testImportsVideoWallpaperProject()`. For DocC edits, build the affected target and check rendered links, images, and localized content.

## Commit & Pull Request Guidelines

Recent history uses short imperative messages such as `Bug Fix`, `Update docs.yml`, and `Test i18n with Github Action`. Prefer concise, scoped subjects like `Docs: update zh_CN import guide` or `App: fix wallpaper fallback`.

Pull requests should include a summary, commands run, affected app areas or locales, linked issues when applicable, and screenshots or screen recordings for visible UI or rendered documentation changes.
