# Repository Guidelines

## Project Structure & Module Organization

This repository is a Swift Package that publishes Wallpaper Player user documentation with DocC. `Package.swift` uses Swift tools 6.0, depends on Apple's DocC plugin, and declares two library targets: `User_Documentation_en_US` and `User_Documentation_zh_CN`.

Each target lives in `Sources/<target>/` and contains a Swift stub plus a `Documentation.docc/` catalog. Articles belong in `Documentation.docc/articles/`; shared DocC images belong in `Documentation.docc/Resources/documentation-art/`. GitHub Pages publishing is configured in `.github/workflows/docs.yml`. There is currently no `Tests/` directory.

## Build, Test, and Development Commands

- `swift build`: validates the Swift package and both documentation targets.
- `swift test`: runs tests if future test targets are added.
- `swift package --allow-writing-to-directory ./.docc-build/en_us generate-documentation --target User_Documentation_en_US --disable-indexing --transform-for-static-hosting --hosting-base-path wallpaper-player-mac/en_us --output-path ./.docc-build/en_us`: builds the English DocC site locally.
- `swift package --allow-writing-to-directory ./.docc-build/zh_cn generate-documentation --target User_Documentation_zh_CN --disable-indexing --transform-for-static-hosting --hosting-base-path wallpaper-player-mac/zh_cn --output-path ./.docc-build/zh_cn`: builds the Chinese DocC site locally.

Generated output such as `.build/` and `.docc-build/` is ignored and should not be committed.

## Coding Style & Naming Conventions

Use Swift 6 defaults with four-space indentation, matching `Package.swift`. Keep target names, folder names, and DocC symbol references aligned exactly, including `User_Documentation_en_US` and `User_Documentation_zh_CN`. Use lower-kebab-case for article filenames, for example `supported-wallpaper-types.md`, and link articles with DocC syntax such as `<doc:import-your-first-wallpaper>`. When adding documentation, update both locale catalogs unless the change is intentionally language-specific.

## Testing Guidelines

For documentation changes, run `swift build` and generate the affected DocC target locally. Check rendered output for broken topic links, missing resources, and placeholder text such as DocC menu tokens. If tests are introduced later, place them under `Tests/<TargetName>Tests/` and name tests after the behavior being verified.

## Commit & Pull Request Guidelines

Recent history uses short, direct commit messages such as `Bug Fix`, `Update docs.yml`, and `Test i18n with Github Action`. Prefer concise messages with an area when useful, for example `Docs: add zh_CN wallpaper type article`.

Pull requests should include a brief summary, affected locale(s), commands run, linked issues when applicable, and screenshots or published previews for rendered DocC changes involving layout or assets.
