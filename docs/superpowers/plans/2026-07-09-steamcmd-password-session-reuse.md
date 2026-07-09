# SteamCMD Password Session Reuse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace user-facing Saved Session with a single Password Login flow that automatically reuses SteamCMD's persisted runtime login when possible.

**Architecture:** Keep `SteamCMDLogin.savedSession(username:)` as an internal command shape for `steamcmd +login <username>`, but remove it from Workshop UI/input. Add a ViewModel-owned runtime login state that chooses password login when a password is present, otherwise tries internal session reuse when SteamCMD login indicators and a saved username exist. Authentication failures invalidate only the automatic reuse path for the current app process.

**Tech Stack:** Swift, SwiftUI, XCTest, SteamCMD, existing `SteamCMDService`/`SteamCMDRunnerCore` abstraction.

## Global Constraints

- Do not save Steam password or Steam Guard code.
- Save only the last successful username.
- Do not clear SteamCMD login state automatically on app exit.
- Do not add anonymous Workshop download back to the UI.
- Do not implement app-owned session tokens.
- Do not change SteamCMD install, repair, or Workshop API browse behavior.
- Keep the Settings page action that clears SteamCMD login/session files.
- The worktree already has dirty files from previous Workshop/SteamCMD work; do not revert unrelated hunks.

---

## File Structure

- Modify `Open Wallpaper Engine/Services/WEProject.swift`
  - Add authentication failure parsing and `SteamCMDError` cases.
  - Keep low-level `SteamCMDLogin.savedSession(username:)` for internal reuse.
  - Remove user-facing `SteamWorkshopLoginMode` and Saved Session input validation.
- Modify `Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift`
  - Replace login-mode state with private runtime session state.
  - Build password-login requests when password is present.
  - Build internal `.savedSession(username:)` requests only from reusable runtime state.
  - Remove the login mode picker from Workshop download controls.
- Modify `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`
  - Replace Saved Session UI/input tests with automatic reuse tests.
  - Add runner tests for Steam Guard/login failure output.
  - Extend `RecordingSteamCMDClient` so ViewModel tests can simulate events/errors.

---

### Task 1: Runner Authentication Failure Signals

**Files:**
- Modify: `Open Wallpaper Engine/Services/WEProject.swift`
- Test: `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`

**Interfaces:**
- Consumes: existing `SteamCMDOutputParser`, `SteamCMDOutputEvent`, `SteamCMDError`, `SteamCMDRunnerCore.downloadItem`.
- Produces:
  - `SteamCMDOutputEvent.loginFailed`
  - `SteamCMDError.steamGuardRequired(recentOutput: [String])`
  - `SteamCMDError.loginFailed(recentOutput: [String])`

- [ ] **Step 1: Write failing parser and runner tests**

Add these tests near the existing SteamCMD output parser and runner tests:

```swift
func testSteamCMDOutputParserRecognizesLoginFailure() {
    XCTAssertEqual(
        SteamCMDOutputParser.event(from: "Login Failure: Invalid Password"),
        .loginFailed
    )
    XCTAssertEqual(
        SteamCMDOutputParser.event(from: "FAILED to login with result code 5"),
        .loginFailed
    )
}

func testSteamCMDRunnerCoreThrowsSteamGuardRequiredForGuardPrompt() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = SteamCMDPaths(managedRuntimeRoot: root)
    let runner = FakeProcessRunner()

    try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
    try writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
    try writeExecutable("binary", to: paths.steamCMDExecutableURL)
    runner.onRun = { executableURL, arguments, output, _ in
        guard executableURL == paths.steamCMDExecutableURL,
              arguments.contains("+workshop_download_item") else { return }
        output("Steam Guard code:")
    }

    let core = SteamCMDRunnerCore(paths: paths, processRunner: runner)

    do {
        _ = try await core.downloadItem(itemID: "3314492008", login: .savedSession(username: "alice"), output: { _ in })
        XCTFail("Expected Steam Guard prompt to fail the download")
    } catch let error as SteamCMDError {
        switch error {
        case .steamGuardRequired(let recentOutput):
            XCTAssertEqual(recentOutput, ["Steam Guard code:"])
        default:
            XCTFail("Expected steamGuardRequired, got \(error)")
        }
    }
}

func testSteamCMDRunnerCoreThrowsLoginFailedForLoginFailureOutput() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = SteamCMDPaths(managedRuntimeRoot: root)
    let runner = FakeProcessRunner()

    try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
    try writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
    try writeExecutable("binary", to: paths.steamCMDExecutableURL)
    runner.onRun = { executableURL, arguments, output, _ in
        guard executableURL == paths.steamCMDExecutableURL,
              arguments.contains("+workshop_download_item") else { return }
        output("Login Failure: Invalid Password")
    }

    let core = SteamCMDRunnerCore(paths: paths, processRunner: runner)

    do {
        _ = try await core.downloadItem(itemID: "3314492008", login: .account(username: "alice", password: "bad", steamGuardCode: nil), output: { _ in })
        XCTFail("Expected login failure output to fail the download")
    } catch let error as SteamCMDError {
        switch error {
        case .loginFailed(let recentOutput):
            XCTAssertEqual(recentOutput, ["Login Failure: Invalid Password"])
        default:
            XCTFail("Expected loginFailed, got \(error)")
        }
    }
}
```

- [ ] **Step 2: Run the new tests and verify they fail**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testSteamCMDOutputParserRecognizesLoginFailure" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testSteamCMDRunnerCoreThrowsSteamGuardRequiredForGuardPrompt" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testSteamCMDRunnerCoreThrowsLoginFailedForLoginFailureOutput" test
```

Expected: FAIL because `SteamCMDOutputEvent.loginFailed`, `SteamCMDError.steamGuardRequired`, and `SteamCMDError.loginFailed` do not exist.

- [ ] **Step 3: Add parser and error support**

In `SteamCMDOutputEvent`, add:

```swift
case loginFailed
```

In `SteamCMDOutputParser.event(from:)`, use this order:

```swift
let lowercased = line.lowercased()
if lowercased.contains("steam guard") {
    return .steamGuardRequired
}
if isLoginFailureLine(line) {
    return .loginFailed
}
if lowercased.contains("waiting for user info") && lowercased.contains("ok") {
    return .loginSucceeded
}
```

Add this helper inside `SteamCMDOutputParser`:

```swift
static func isLoginFailureLine(_ line: String) -> Bool {
    let lowercased = line.lowercased()
    return [
        "login failure",
        "failed to login",
        "invalid password",
        "account logon denied",
        "logon failure"
    ].contains { lowercased.contains($0) }
}
```

In `SteamCMDError`, add cases:

```swift
case steamGuardRequired(recentOutput: [String])
case loginFailed(recentOutput: [String])
```

Add `errorDescription` branches:

```swift
case .steamGuardRequired(let recentOutput):
    return Self.message(
        base: "Steam Guard required. Enter the current code and try again.",
        recentOutput: recentOutput
    )
case .loginFailed(let recentOutput):
    return Self.message(
        base: "SteamCMD login failed. Check your Steam username, password, and Steam Guard code.",
        recentOutput: recentOutput
    )
```

- [ ] **Step 4: Throw authentication errors from `downloadItem`**

Inside `SteamCMDRunnerCore.downloadItem`, add local flags:

```swift
var sawSteamGuardRequired = false
var sawLoginFailure = false
```

In the output event block, after `if let event = parser.event(from: line)`, add:

```swift
switch event {
case .steamGuardRequired:
    sawSteamGuardRequired = true
case .loginFailed:
    sawLoginFailure = true
case .loginSucceeded, .downloadSucceeded, .downloadFailed:
    break
}
```

After `runSteamCMD` returns and before checking `failedItemID`, add:

```swift
if downloadedItemURL == nil {
    if sawSteamGuardRequired {
        throw SteamCMDError.steamGuardRequired(recentOutput: recentOutput.lines)
    }
    if sawLoginFailure {
        throw SteamCMDError.loginFailed(recentOutput: recentOutput.lines)
    }
}
```

Update `SteamCMDRunnerXPCPayload.failure(_:)` and `SteamCMDRunnerXPCPayload.error(from:)` with:

```swift
case .steamGuardRequired(let recentOutput):
    payload["errorKind"] = "steamGuardRequired"
    payload["recentOutput"] = recentOutput
case .loginFailed(let recentOutput):
    payload["errorKind"] = "loginFailed"
    payload["recentOutput"] = recentOutput
```

and:

```swift
if payload["errorKind"] as? String == "steamGuardRequired" {
    return SteamCMDError.steamGuardRequired(recentOutput: recentOutput)
}
if payload["errorKind"] as? String == "loginFailed" {
    return SteamCMDError.loginFailed(recentOutput: recentOutput)
}
```

- [ ] **Step 5: Update status text for the new event**

In `WallpaperDiscover.swift`, update `SteamCMDOutputEvent.statusText`:

```swift
case .loginFailed:
    return "SteamCMD login failed."
```

- [ ] **Step 6: Run focused tests**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testSteamCMDOutputParserRecognizesLoginFailure" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testSteamCMDRunnerCoreThrowsSteamGuardRequiredForGuardPrompt" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testSteamCMDRunnerCoreThrowsLoginFailedForLoginFailureOutput" test
```

Expected: PASS.

- [ ] **Step 7: Commit task 1**

If the dirty worktree makes whole-file staging unsafe, use `git add -p` and stage only the hunks from this task.

```bash
git diff -- "Open Wallpaper Engine/Services/WEProject.swift" "Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git add -p "Open Wallpaper Engine/Services/WEProject.swift" "Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git commit -m "App: detect SteamCMD login failures"
```

---

### Task 2: Add Password-Only Workshop Input Entry Point

**Files:**
- Modify: `Open Wallpaper Engine/Services/WEProject.swift`
- Test: `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`

**Interfaces:**
- Consumes: `SteamWorkshopIDParser.publishedFileID(from:)`.
- Produces:
  - `SteamWorkshopDownloadInput.makePasswordRequest() throws -> SteamWorkshopDownloadRequest`
  - `SteamWorkshopDownloadInputError.missingPassword` for empty password.
  - Backward-compatible existing `makeRequest(savedSessionAvailable:)` until Task 3 removes its callers.

- [ ] **Step 1: Replace input model tests**

Replace `testWorkshopLoginModesDefaultToPasswordAndDoNotExposeAnonymous` with:

```swift
@MainActor
func testWorkshopDownloadInputOnlyBuildsPasswordLogin() throws {
    let input = SteamWorkshopDownloadInput(
        itemInput: "https://steamcommunity.com/sharedfiles/filedetails/?id=3004222851",
        username: " alice ",
        password: " secret ",
        steamGuardCode: " 12345 "
    )

    let request = try input.makePasswordRequest()

    XCTAssertEqual(request.itemID, "3004222851")
    XCTAssertEqual(
        request.login,
        .account(username: "alice", password: "secret", steamGuardCode: "12345")
    )
}
```

Replace `testWorkshopDownloadInputBuildsSavedSessionLoginWithoutPassword` with:

```swift
func testWorkshopDownloadInputRequiresPassword() throws {
    let input = SteamWorkshopDownloadInput(
        itemInput: "3004222851",
        username: "alice",
        password: "",
        steamGuardCode: ""
    )

    XCTAssertThrowsError(try input.makePasswordRequest()) { error in
        XCTAssertEqual(
            error.localizedDescription,
            "Enter your Steam password to sign in to SteamCMD."
        )
    }
}
```

Update `testWorkshopDownloadInputBuildsPasswordLoginWithoutPersistingPassword` so it calls `makePasswordRequest()` and no longer passes `loginMode`.

- [ ] **Step 2: Run the input tests and verify they fail**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopDownloadInputOnlyBuildsPasswordLogin" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopDownloadInputRequiresPassword" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopDownloadInputBuildsPasswordLoginWithoutPersistingPassword" test
```

Expected: FAIL because `makePasswordRequest()` does not exist and tests still reference removed call shapes.

- [ ] **Step 3: Add password-only request builder**

In `SteamWorkshopDownloadInputError`, keep existing cases for now and change `missingPassword` text:

```swift
case .missingPassword:
    return "Enter your Steam password to sign in to SteamCMD."
```

Keep `SteamWorkshopLoginMode` and the existing `makeRequest(savedSessionAvailable:)` until Task 3 removes ViewModel callers. Add this method to `SteamWorkshopDownloadInput`:

```swift
func makePasswordRequest() throws -> SteamWorkshopDownloadRequest {
    guard let itemID = SteamWorkshopIDParser.publishedFileID(from: itemInput) else {
        throw SteamWorkshopDownloadInputError.invalidWorkshopID
    }

    let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedSteamGuardCode = steamGuardCode.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedUsername.isEmpty else {
        throw SteamWorkshopDownloadInputError.missingUsername
    }
    guard !trimmedPassword.isEmpty else {
        throw SteamWorkshopDownloadInputError.missingPassword
    }

    return SteamWorkshopDownloadRequest(
        itemID: itemID,
        login: .account(
            username: trimmedUsername,
            password: trimmedPassword,
            steamGuardCode: trimmedSteamGuardCode.isEmpty ? nil : trimmedSteamGuardCode
        )
    )
}
```

- [ ] **Step 4: Remove stale references**

Run:

```bash
rg -n "SteamWorkshopLoginMode|missingSavedSession|makeRequest\\(|loginMode:" "Open Wallpaper Engine" "Open Wallpaper EngineTests"
```

Expected after this task's implementation: matches remain in the existing compatibility path and in `WallpaperDiscover.swift`; Task 3 and Task 4 remove them from Workshop UI/input usage.

- [ ] **Step 5: Run focused tests**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopDownloadInputOnlyBuildsPasswordLogin" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopDownloadInputRequiresPassword" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopDownloadInputBuildsPasswordLoginWithoutPersistingPassword" test
```

Expected: PASS.

- [ ] **Step 6: Commit task 2**

```bash
git diff -- "Open Wallpaper Engine/Services/WEProject.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git add -p "Open Wallpaper Engine/Services/WEProject.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git commit -m "App: simplify Workshop login input"
```

---

### Task 3: Add Automatic Runtime Session Reuse In ViewModel

**Files:**
- Modify: `Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift`
- Test: `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`

**Interfaces:**
- Consumes:
  - `SteamCMDService.hasSavedLoginSession() -> Bool`
  - `SteamCMDLogin.savedSession(username:)`
  - `SteamWorkshopDownloadInput.makePasswordRequest()`
- Produces:
  - private `SteamWorkshopRuntimeLoginState`
  - automatic reuse behavior when password is empty.

- [ ] **Step 1: Extend the recording SteamCMD test client**

Modify `RecordingSteamCMDClient` in the test file:

```swift
private final class RecordingSteamCMDClient: SteamCMDClient {
    let paths: SteamCMDPaths
    private(set) var clearLoginSessionCallCount = 0
    private(set) var installIfMissingCallCount = 0
    private(set) var downloadCalls = [(itemID: String, login: SteamCMDLogin)]()
    var downloadError: Error?
    var outputEvents = [SteamCMDOutputEvent]()
    var createDownloadedDirectory = true

    init(paths: SteamCMDPaths) {
        self.paths = paths
    }

    func installIfMissing(progress: @escaping (SteamCMDInstallState) -> Void) async throws -> SteamCMDRunnerResult {
        installIfMissingCallCount += 1
        progress(.installed(paths.executableURL))
        return SteamCMDRunnerResult(runtimeURL: paths.steamCMDDirectory, downloadedItemURL: nil, recentOutput: [])
    }

    func repairRuntime(progress: @escaping (SteamCMDInstallState) -> Void) async throws -> SteamCMDRunnerResult {
        progress(.installed(paths.executableURL))
        return SteamCMDRunnerResult(runtimeURL: paths.steamCMDDirectory, downloadedItemURL: nil, recentOutput: [])
    }

    func downloadItem(
        itemID: String,
        login: SteamCMDLogin,
        output: @escaping (SteamCMDOutputEvent) -> Void
    ) async throws -> SteamCMDRunnerResult {
        downloadCalls.append((itemID: itemID, login: login))
        for event in outputEvents {
            output(event)
        }
        if let downloadError {
            throw downloadError
        }
        let directory = paths.workshopContentDirectory.appendingPathComponent(itemID, isDirectory: true)
        if createDownloadedDirectory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return SteamCMDRunnerResult(
            runtimeURL: paths.steamCMDDirectory,
            downloadedItemURL: directory,
            recentOutput: []
        )
    }

    func clearLoginSession() async throws {
        clearLoginSessionCallCount += 1
    }

    func diagnostics() async -> SteamCMDDiagnostics {
        SteamCMDDiagnostics(
            runtimeURL: paths.steamCMDDirectory,
            source: .managedRuntime,
            executableURL: paths.executableURL,
            cwd: paths.steamCMDDirectory,
            home: paths.steamHomeDirectory,
            temporaryDirectory: paths.steamCMDDirectory.appendingPathComponent("tmp", isDirectory: true),
            isUsingXPCClient: false,
            legacyWorkshopDirectories: []
        )
    }
}
```

Add this test helper:

```swift
private func withStoredWorkshopUsername(_ username: String?, run body: () async throws -> Void) async rethrows {
    let key = "SteamWorkshopUsername"
    let previous = UserDefaults.standard.string(forKey: key)
    if let username {
        UserDefaults.standard.set(username, forKey: key)
    } else {
        UserDefaults.standard.removeObject(forKey: key)
    }
    defer {
        if let previous {
            UserDefaults.standard.set(previous, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    try await body()
}
```

Add this helper:

```swift
private func writeSteamCMDAccountState(paths: SteamCMDPaths, username: String = "alice") throws {
    let configDirectory = paths.steamHomeDirectory.appendingPathComponent("config", isDirectory: true)
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    let configFile = configDirectory.appendingPathComponent("config.vdf")
    try Data(#""Accounts" { "\#(username)" { "SteamID" "76561198000000000" } }"#.utf8).write(to: configFile)
}
```

- [ ] **Step 2: Write ViewModel reuse tests**

Replace `testWorkshopBrowserDoesNotCallSteamCMDForSavedSessionWithoutSession` with these tests:

```swift
@MainActor
func testWorkshopBrowserReusesSteamCMDSessionWhenPasswordIsEmpty() async throws {
    try await withStoredWorkshopUsername("alice") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        try writeSteamCMDAccountState(paths: paths)
        let resolution = SteamCMDPathResolution(paths: paths, source: .managedRuntime, legacyPaths: [])
        let client = RecordingSteamCMDClient(paths: paths)
        let service = SteamCMDService(resolution: resolution, client: client)
        let viewModel = SteamWorkshopBrowserViewModel(
            steamCMDResolution: resolution,
            steamCMDService: service
        )
        viewModel.manualItemInput = "3004222851"
        viewModel.password = ""

        _ = await viewModel.download()

        XCTAssertEqual(client.downloadCalls.count, 1)
        XCTAssertEqual(client.downloadCalls.first?.login, .savedSession(username: "alice"))
    }
}

@MainActor
func testWorkshopBrowserRequiresPasswordWithoutReusableSteamCMDSession() async throws {
    try await withStoredWorkshopUsername(nil) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let resolution = SteamCMDPathResolution(paths: paths, source: .managedRuntime, legacyPaths: [])
        let client = RecordingSteamCMDClient(paths: paths)
        let service = SteamCMDService(resolution: resolution, client: client)
        let viewModel = SteamWorkshopBrowserViewModel(
            steamCMDResolution: resolution,
            steamCMDService: service
        )
        viewModel.manualItemInput = "3004222851"
        viewModel.username = "alice"
        viewModel.password = ""

        let wallpaper = await viewModel.download()

        XCTAssertNil(wallpaper)
        XCTAssertEqual(client.installIfMissingCallCount, 0)
        XCTAssertEqual(client.downloadCalls.count, 0)
        XCTAssertEqual(viewModel.statusMessage, "Enter your Steam password to sign in to SteamCMD.")
    }
}

@MainActor
func testWorkshopBrowserInvalidatesExpiredReusableSteamCMDSession() async throws {
    try await withStoredWorkshopUsername("alice") {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        try writeSteamCMDAccountState(paths: paths)
        let resolution = SteamCMDPathResolution(paths: paths, source: .managedRuntime, legacyPaths: [])
        let client = RecordingSteamCMDClient(paths: paths)
        client.downloadError = SteamCMDError.steamGuardRequired(recentOutput: ["Steam Guard code:"])
        let service = SteamCMDService(resolution: resolution, client: client)
        let viewModel = SteamWorkshopBrowserViewModel(
            steamCMDResolution: resolution,
            steamCMDService: service
        )
        viewModel.manualItemInput = "3004222851"
        viewModel.password = ""

        _ = await viewModel.download()

        XCTAssertEqual(client.downloadCalls.count, 1)
        XCTAssertEqual(viewModel.statusMessage, "Saved SteamCMD login expired. Enter your Steam password and current Steam Guard code, then download again.")

        client.downloadError = nil
        _ = await viewModel.download()

        XCTAssertEqual(client.downloadCalls.count, 1)
        XCTAssertEqual(viewModel.statusMessage, "Enter your Steam password to sign in to SteamCMD.")
    }
}

@MainActor
func testWorkshopBrowserPasswordLoginSuccessSavesUsernameForFutureReuse() async throws {
    try await withStoredWorkshopUsername(nil) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let resolution = SteamCMDPathResolution(paths: paths, source: .managedRuntime, legacyPaths: [])
        let client = RecordingSteamCMDClient(paths: paths)
        client.outputEvents = [.loginSucceeded]
        let service = SteamCMDService(resolution: resolution, client: client)
        let viewModel = SteamWorkshopBrowserViewModel(
            steamCMDResolution: resolution,
            steamCMDService: service
        )
        viewModel.manualItemInput = "3004222851"
        viewModel.username = " alice "
        viewModel.password = " secret "
        viewModel.steamGuardCode = " 12345 "

        _ = await viewModel.download()

        XCTAssertEqual(
            client.downloadCalls.first?.login,
            .account(username: "alice", password: "secret", steamGuardCode: "12345")
        )
        XCTAssertEqual(UserDefaults.standard.string(forKey: "SteamWorkshopUsername"), "alice")
        XCTAssertEqual(viewModel.username, "alice")
        XCTAssertEqual(viewModel.password, "")
        XCTAssertEqual(viewModel.steamGuardCode, "")
    }
}
```

- [ ] **Step 3: Run ViewModel tests and verify they fail**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserReusesSteamCMDSessionWhenPasswordIsEmpty" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserRequiresPasswordWithoutReusableSteamCMDSession" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserInvalidatesExpiredReusableSteamCMDSession" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserPasswordLoginSuccessSavesUsernameForFutureReuse" test
```

Expected: FAIL because the ViewModel still uses `loginMode` and does not own automatic reuse state.

- [ ] **Step 4: Add runtime login state to ViewModel**

In `WallpaperDiscover.swift`, add near the ViewModel:

```swift
private enum SteamWorkshopRuntimeLoginState: Equatable {
    case unknown
    case reusable(username: String)
    case invalid
}
```

Remove these properties:

```swift
@Published var loginMode = SteamWorkshopLoginMode.password
@Published private(set) var hasSavedLoginSession = false
```

Add this private property:

```swift
private var runtimeLoginState = SteamWorkshopRuntimeLoginState.unknown
```

In `init`, replace `refreshSavedLoginSessionAvailability()` and `preferredLoginMode(...)` with:

```swift
refreshRuntimeLoginState()
```

Replace `canStartDownload` with:

```swift
var canStartDownload: Bool {
    installState.isInstalled && !isDownloading
}
```

Remove `canUseSavedSession` and `preferredLoginMode`.

- [ ] **Step 5: Add runtime state helpers**

Add these private helpers to `SteamWorkshopBrowserViewModel`:

```swift
private func refreshRuntimeLoginState() {
    let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
    if steamCMDService.hasSavedLoginSession(), !trimmedUsername.isEmpty {
        runtimeLoginState = .reusable(username: trimmedUsername)
    } else {
        runtimeLoginState = .unknown
    }
}

private func markReusableRuntimeLoginIfAvailable(username: String) {
    let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedUsername.isEmpty else {
        runtimeLoginState = .unknown
        return
    }
    if steamCMDService.hasSavedLoginSession() {
        runtimeLoginState = .reusable(username: trimmedUsername)
    } else {
        runtimeLoginState = .unknown
    }
}

private func makeDownloadRequest(itemID overrideItemID: String?) throws -> SteamWorkshopDownloadRequest {
    let itemInput = overrideItemID ?? manualItemInput
    let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedPassword.isEmpty {
        return try SteamWorkshopDownloadInput(
            itemInput: itemInput,
            username: username,
            password: password,
            steamGuardCode: steamGuardCode
        ).makePasswordRequest()
    }

    guard let itemID = SteamWorkshopIDParser.publishedFileID(from: itemInput) else {
        throw SteamWorkshopDownloadInputError.invalidWorkshopID
    }
    switch runtimeLoginState {
    case .reusable(let username):
        return SteamWorkshopDownloadRequest(itemID: itemID, login: .savedSession(username: username))
    case .unknown, .invalid:
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUsername.isEmpty {
            throw SteamWorkshopDownloadInputError.missingUsername
        }
        throw SteamWorkshopDownloadInputError.missingPassword
    }
}

private func invalidateReusableRuntimeLogin() {
    runtimeLoginState = .invalid
}
```

Add this private extension in `WallpaperDiscover.swift`:

```swift
private extension SteamCMDLogin {
    var isReusableRuntimeLogin: Bool {
        if case .savedSession = self {
            return true
        }
        return false
    }
}
```

Add this private extension:

```swift
private extension SteamCMDError {
    var isAuthenticationFailureForRuntimeReuse: Bool {
        switch self {
        case .steamGuardRequired, .loginFailed, .commandFailed:
            return true
        case .installFailed, .downloadFailed:
            return false
        }
    }
}
```

- [ ] **Step 6: Update install/repair/reset refresh calls**

Replace every `refreshSavedLoginSessionAvailability()` call in `WallpaperDiscover.swift`:

```swift
refreshRuntimeLoginState()
```

For `resetSteamCMDRuntime()`, set:

```swift
runtimeLoginState = .unknown
```

after a successful reset.

- [ ] **Step 7: Replace `download(itemID:)` request logic**

In `download(itemID:)`, replace the request-building block with:

```swift
var attemptedReusableRuntimeLogin = false

do {
    let request = try makeDownloadRequest(itemID: overrideItemID)
    attemptedReusableRuntimeLogin = request.login.isReusableRuntimeLogin
    manualItemInput = request.itemID
    guard await ensureSteamCMDInstalled() else {
        return nil
    }
    statusMessage = "Starting SteamCMD download for \(request.itemID)..."
    let directory = try await steamCMDService.downloadItem(
        itemID: request.itemID,
        login: request.login
    ) { [weak self] event in
        Task { @MainActor in
            if case .loginSucceeded = event {
                _ = self?.persistSuccessfulUsername(for: request.login)
            }
            self?.statusMessage = event.statusText
        }
    }
    if let username = persistedUsername(for: request.login) {
        _ = persistSuccessfulUsername(for: request.login)
        markReusableRuntimeLoginIfAvailable(username: username)
    }
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
        statusMessage = "SteamCMD did not create a download folder for \(request.itemID)."
        return nil
    }
    let wallpaper = WorkshopLibraryService.scanDownloadedWallpapers(at: directory).first
    statusMessage = wallpaper == nil
        ? "Downloaded \(request.itemID), but no playable project.json was found at \(directory.path)."
        : "Downloaded \(wallpaper?.project.title ?? request.itemID)."
    return wallpaper
} catch let error as SteamCMDError where attemptedReusableRuntimeLogin && error.isAuthenticationFailureForRuntimeReuse {
    invalidateReusableRuntimeLogin()
    statusMessage = "Saved SteamCMD login expired. Enter your Steam password and current Steam Guard code, then download again."
    return nil
} catch {
    statusMessage = error.localizedDescription
    return nil
}
```

Replace `persistSuccessfulUsername(for:)` with:

```swift
private func persistedUsername(for login: SteamCMDLogin) -> String? {
    switch login {
    case .account(let username, _, _), .savedSession(let username):
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedUsername.isEmpty ? nil : trimmedUsername
    case .anonymous:
        return nil
    }
}

private func persistSuccessfulUsername(for login: SteamCMDLogin) -> Bool {
    guard let usernameToPersist = persistedUsername(for: login) else {
        return false
    }
    UserDefaults.standard.set(usernameToPersist, forKey: Self.usernameDefaultsKey)
    username = usernameToPersist
    return true
}
```

- [ ] **Step 8: Run ViewModel tests**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserReusesSteamCMDSessionWhenPasswordIsEmpty" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserRequiresPasswordWithoutReusableSteamCMDSession" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserInvalidatesExpiredReusableSteamCMDSession" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserPasswordLoginSuccessSavesUsernameForFutureReuse" test
```

Expected: PASS.

- [ ] **Step 9: Commit task 3**

```bash
git diff -- "Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git add -p "Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git commit -m "App: reuse SteamCMD login automatically"
```

---

### Task 4: Remove Saved Session UI Controls

**Files:**
- Modify: `Open Wallpaper Engine/Services/WEProject.swift`
- Modify: `Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift`
- Test: `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`

**Interfaces:**
- Consumes: ViewModel fields `username`, `password`, `steamGuardCode`.
- Produces: Workshop manual download bar without login mode picker, and no user-facing `SteamWorkshopLoginMode`.

- [ ] **Step 1: Add a UI/source assertion test**

Add this test near other Workshop browser UI tests:

```swift
func testWorkshopBrowserSourceDoesNotExposeSavedSessionPicker() throws {
    let source = try String(
        contentsOf: repositoryRoot()
            .appendingPathComponent("Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift"),
        encoding: .utf8
    )

    XCTAssertFalse(source.contains("loginModePicker"))
    XCTAssertFalse(source.contains("Saved Session"))
    XCTAssertFalse(source.contains("Picker(\"Login\""))
}
```

- [ ] **Step 2: Run the UI/source test and verify it fails**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserSourceDoesNotExposeSavedSessionPicker" test
```

Expected: FAIL because `loginModePicker` still exists before UI cleanup.

- [ ] **Step 3: Remove login mode picker from the manual download bar**

In `manualDownloadBar`, replace the horizontal layout with:

```swift
HStack(spacing: 8) {
    manualItemField
    usernameField
    passwordField
    steamGuardField
    manualDownloadActions
}
```

Replace the vertical fallback with:

```swift
VStack(alignment: .leading, spacing: 8) {
    HStack(spacing: 8) {
        manualItemField
        manualDownloadActions
    }
    HStack(spacing: 8) {
        usernameField
        passwordField
        steamGuardField
    }
}
```

Delete the `loginModePicker` computed property.

Remove `.disabled(viewModel.loginMode != .password)` from both `passwordField` and `steamGuardField`.

- [ ] **Step 4: Remove stale input symbols**

In `WEProject.swift`, delete `SteamWorkshopLoginMode`.

In `SteamWorkshopDownloadInputError`, delete:

```swift
case missingSavedSession
```

and remove its `errorDescription` branch.

In `SteamWorkshopDownloadInput`, delete:

```swift
var loginMode: SteamWorkshopLoginMode = .password
```

Delete the compatibility method:

```swift
func makeRequest(savedSessionAvailable: Bool = true) throws -> SteamWorkshopDownloadRequest
```

- [ ] **Step 5: Remove stale symbols**

Run:

```bash
rg -n "SteamWorkshopLoginMode|loginMode|loginModePicker|canUseSavedSession|hasSavedLoginSession|preferredLoginMode|missingSavedSession" "Open Wallpaper Engine" "Open Wallpaper EngineTests"
```

Expected: no matches in Workshop UI/input code. Low-level `SteamCMDLogin.savedSession` matches remain valid.

- [ ] **Step 6: Run the UI/source test**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserSourceDoesNotExposeSavedSessionPicker" test
```

Expected: PASS.

- [ ] **Step 7: Commit task 4**

```bash
git diff -- "Open Wallpaper Engine/Services/WEProject.swift" "Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git add -p "Open Wallpaper Engine/Services/WEProject.swift" "Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git commit -m "App: remove Saved Session Workshop UI"
```

---

### Task 5: Focused Regression Verification

**Files:**
- Modify: no source files.
- Test: `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`

**Interfaces:**
- Consumes all previous tasks.
- Produces verified build and focused test evidence.

- [ ] **Step 1: Run all focused tests for this change**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testSteamCMDOutputParserRecognizesLoginFailure" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testSteamCMDRunnerCoreThrowsSteamGuardRequiredForGuardPrompt" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testSteamCMDRunnerCoreThrowsLoginFailedForLoginFailureOutput" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopDownloadInputOnlyBuildsPasswordLogin" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopDownloadInputRequiresPassword" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopDownloadInputBuildsPasswordLoginWithoutPersistingPassword" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserReusesSteamCMDSessionWhenPasswordIsEmpty" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserRequiresPasswordWithoutReusableSteamCMDSession" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserInvalidatesExpiredReusableSteamCMDSession" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserPasswordLoginSuccessSavesUsernameForFutureReuse" -only-testing:"Open Wallpaper EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserSourceDoesNotExposeSavedSessionPicker" test
```

Expected: PASS.

- [ ] **Step 2: Run build**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -destination 'platform=macOS' -derivedDataPath DerivedData build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run full unit target**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:"Open Wallpaper EngineTests" test
```

Expected: Workshop/login tests pass. Existing SteamCMD install/repair quarantine permission tests may still fail with messages like `Could not remove quarantine ... Operation not permitted`; record exact failures if they remain.

- [ ] **Step 4: Check status and diff**

Run:

```bash
git status --short
git diff --check
```

Expected: `git diff --check` exits 0. `git status --short` shows only intentional modified files and any pre-existing dirty files not committed by these tasks.

- [ ] **Step 5: Commit verification-only updates if files changed during cleanup**

If Step 4 required a source or test cleanup, stage only those cleanup hunks:

```bash
git add -p "Open Wallpaper Engine/Services/WEProject.swift" "Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git commit -m "App: verify SteamCMD password session reuse"
```

If Step 4 did not require cleanup, do not create an empty commit.
