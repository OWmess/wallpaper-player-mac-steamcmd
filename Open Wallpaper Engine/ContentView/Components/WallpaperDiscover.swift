//
//  WallpaperDiscover.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/21.
//

import SwiftUI
import AppKit

private struct WorkshopBrowsePage {
    var items: [SteamWorkshopItem]
    var nextCursor: String?
}

private struct WorkshopBrowseQueryContext: Equatable {
    var sort: SteamWorkshopQuery.Sort
    var searchText: String?

    init(sort: SteamWorkshopQuery.Sort, searchText: String) {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sort = trimmedSearch.isEmpty ? sort : .search
        self.searchText = trimmedSearch.isEmpty ? nil : trimmedSearch
    }
}

private struct WorkshopPageState {
    var queryContext: WorkshopBrowseQueryContext
    var pages = [WorkshopBrowsePage]()
    var currentPageIndex = -1
    var nextCursor = "*"
    var isExhausted = false

    var canLoadPreviousPage: Bool {
        currentPageIndex > 0
    }

    var canLoadNextPage: Bool {
        guard currentPageIndex >= 0 else { return false }
        return currentPageIndex + 1 < pages.count || !isExhausted
    }

    var currentPage: WorkshopBrowsePage? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
    }

    mutating func reset(with page: WorkshopBrowsePage) {
        pages = [page]
        currentPageIndex = 0
        updateCursor(from: page)
    }

    mutating func append(_ page: WorkshopBrowsePage) {
        pages.append(page)
        currentPageIndex = pages.count - 1
        updateCursor(from: page)
    }

    mutating func moveToPreviousPage() {
        guard canLoadPreviousPage else { return }
        currentPageIndex -= 1
    }

    mutating func moveToNextCachedPage() {
        guard currentPageIndex + 1 < pages.count else { return }
        currentPageIndex += 1
    }

    private mutating func updateCursor(from page: WorkshopBrowsePage) {
        guard let cursor = page.nextCursor, !cursor.isEmpty, cursor != nextCursor else {
            isExhausted = true
            return
        }
        nextCursor = cursor
        isExhausted = false
    }
}

private struct WorkshopBrowseFetchResult {
    var page: WorkshopBrowsePage
}

private enum SteamWorkshopRuntimeLoginState: Equatable {
    case passwordRequired
    case reusableSavedSession(username: String)
    case invalidSavedSession(username: String)

    var reusableSavedSessionUsername: String? {
        guard case .reusableSavedSession(let username) = self else { return nil }
        return username
    }
}

struct SteamWorkshopBrowserLayoutPolicy {
    enum Presentation: Equatable {
        case sideBySide
        case stacked
    }

    struct Layout: Equatable {
        var presentation: Presentation
        var detailWidthRange: ClosedRange<CGFloat>
        var listHeight: CGFloat
    }

    static func layout(forWidth width: CGFloat, height: CGFloat) -> Layout {
        if width >= 860 {
            let maxDetailWidth = min(max(width * 0.42, 480), 620)
            return Layout(
                presentation: .sideBySide,
                detailWidthRange: 320...maxDetailWidth,
                listHeight: height
            )
        }

        return Layout(
            presentation: .stacked,
            detailWidthRange: 0...width,
            listHeight: max(260, (height * 0.55).rounded())
        )
    }
}

struct WallpaperDiscover: View {
    var body: some View {
        ScrollView {
            WorkingInProgress()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 50)
        }
    }
}

@MainActor
final class SteamWorkshopBrowserViewModel: ObservableObject {
    private static let displayedPageSize = 24
    private static let videoWebTags = "Video,Web"
    private static let usernameDefaultsKey = "SteamWorkshopUsername"

    @Published var apiKey = ""
    @Published var sort = SteamWorkshopQuery.Sort.popular
    @Published var searchText = ""
    @Published var manualItemInput = ""
    @Published var username = UserDefaults.standard.string(forKey: usernameDefaultsKey) ?? ""
    @Published var password = ""
    @Published var steamGuardCode = ""
    @Published var items = [SteamWorkshopItem]()
    @Published var selectedItem: SteamWorkshopItem?
    @Published var statusMessage = ""
    @Published var isLoading = false
    @Published var isDownloading = false
    @Published var installState = SteamCMDInstallState.idle
    @Published private(set) var steamCMDResolution: SteamCMDPathResolution
    @Published private(set) var currentPageNumber = 0

    private let apiService: SteamWorkshopAPIService
    private var steamCMDService: SteamCMDService
    private var pageState: WorkshopPageState?
    private var runtimeLoginState = SteamWorkshopRuntimeLoginState.passwordRequired

    init(
        apiService: SteamWorkshopAPIService = SteamWorkshopAPIService(),
        steamCMDResolution: SteamCMDPathResolution = SteamCMDPathResolver.resolve(),
        steamCMDService: SteamCMDService? = nil
    ) {
        self.apiService = apiService
        self.steamCMDResolution = steamCMDResolution
        self.steamCMDService = steamCMDService ?? SteamCMDService(resolution: steamCMDResolution)
        refreshInstallState()
        refreshSavedLoginSessionAvailability()
    }

    var steamCMDDirectoryPath: String {
        if let authorizationIssue = steamCMDResolution.authorizationIssue {
            return authorizationIssue.recoveryMessage
        }
        return steamCMDService.paths.steamCMDDirectory.path
    }

    var steamCMDPathSourceText: String {
        steamCMDResolution.source.label
    }

    var needsSteamCMDRuntimeSelection: Bool {
        false
    }

    var canStartDownload: Bool {
        installState.isInstalled && !isDownloading
    }

    var canLoadPreviousPage: Bool {
        pageState?.canLoadPreviousPage == true
    }

    var canLoadNextPage: Bool {
        pageState?.canLoadNextPage == true
    }

    func loadAPIKey() {
        apiKey = (try? SteamWorkshopCredentialStore.loadAPIKey()) ?? ""
    }

    func saveAPIKey() {
        do {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try SteamWorkshopCredentialStore.deleteAPIKey()
                apiKey = ""
                statusMessage = "Steam Web API key removed."
            } else {
                try SteamWorkshopCredentialStore.saveAPIKey(trimmed)
                apiKey = trimmed
                statusMessage = "Steam Web API key saved to Keychain."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refreshSteamCMDResolution() {
        let resolution = SteamCMDPathResolver.resolve()
        steamCMDResolution = resolution
        steamCMDService = SteamCMDService(resolution: resolution)
        refreshInstallState()
        refreshSavedLoginSessionAvailability()
    }

    private func refreshInstallState() {
        guard steamCMDResolution.authorizationIssue == nil else {
            installState = .idle
            return
        }
        if FileManager.default.fileExists(atPath: steamCMDService.paths.executableURL.path),
           FileManager.default.fileExists(atPath: steamCMDService.paths.steamCMDExecutableURL.path) {
            installState = .installed(steamCMDService.paths.executableURL)
        } else {
            installState = .idle
        }
    }

    private func refreshSavedLoginSessionAvailability() {
        let sessionAvailable = steamCMDService.hasSavedLoginSession()
        let savedUsername = Self.savedWorkshopUsername()
        if case .invalidSavedSession(let username) = runtimeLoginState,
           sessionAvailable,
           savedUsername == username {
            return
        }
        runtimeLoginState = Self.makeRuntimeLoginState(
            savedSessionAvailable: sessionAvailable,
            username: savedUsername
        )
    }

    private static func savedWorkshopUsername() -> String {
        (UserDefaults.standard.string(forKey: usernameDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func makeRuntimeLoginState(
        savedSessionAvailable: Bool,
        username: String
    ) -> SteamWorkshopRuntimeLoginState {
        guard savedSessionAvailable, !username.isEmpty else {
            return .passwordRequired
        }
        return .reusableSavedSession(username: username)
    }

    func resetSteamCMDRuntime() {
        do {
            try steamCMDService.resetRuntime()
            refreshInstallState()
            refreshSavedLoginSessionAvailability()
            statusMessage = "SteamCMD runtime reset. Install again to rebuild it."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func openSteamCMDRuntimeFolder() {
        let url = steamCMDService.paths.steamCMDDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func runSteamCMDDiagnostics() async {
        let diagnostics = await steamCMDService.diagnostics()
        statusMessage = [
            diagnostics.isUsingXPCClient ? "Runner: XPC" : "Runner: local",
            "cwd: \(diagnostics.cwd.path)",
            "HOME: \(diagnostics.home.path)"
        ].joined(separator: " | ")
    }

    func browse() async {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            statusMessage = "Paste a Steam Web API key to browse Workshop results."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let queryContext = WorkshopBrowseQueryContext(sort: sort, searchText: searchText)
            let result = try await fetchPage(
                apiKey: trimmedKey,
                queryContext: queryContext,
                cursor: "*"
            )
            var state = WorkshopPageState(queryContext: queryContext)
            state.reset(with: result.page)
            pageState = state
            showCurrentPage()
            updateStatusForCurrentPage()
        } catch {
            pageState = nil
            items = []
            selectedItem = nil
            currentPageNumber = 0
            statusMessage = error.localizedDescription
        }
    }

    func loadNextPage() async {
        guard canLoadNextPage else { return }

        guard var state = pageState else { return }

        if state.currentPageIndex + 1 < state.pages.count {
            state.moveToNextCachedPage()
            pageState = state
            showCurrentPage()
            updateStatusForCurrentPage()
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !state.isExhausted else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await fetchPage(
                apiKey: trimmedKey,
                queryContext: state.queryContext,
                cursor: state.nextCursor
            )
            state.append(result.page)
            pageState = state
            showCurrentPage()
            updateStatusForCurrentPage()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadPreviousPage() {
        guard var state = pageState, state.canLoadPreviousPage else { return }
        state.moveToPreviousPage()
        pageState = state
        showCurrentPage()
        updateStatusForCurrentPage()
    }

    private func updateStatusForCurrentPage() {
        if items.isEmpty {
            if currentPageNumber == 1, pageState?.queryContext.searchText == nil {
                statusMessage = "Steam did not return Video/Web Workshop results for the combined tag query."
            } else {
                statusMessage = "No playable Video/Web Workshop items found on page \(currentPageNumber)."
            }
        } else {
            statusMessage = "Loaded page \(currentPageNumber) with \(items.count) playable Workshop items."
        }
    }

    private func fetchPage(
        apiKey: String,
        queryContext: WorkshopBrowseQueryContext,
        cursor: String
    ) async throws -> WorkshopBrowseFetchResult {
        let payload = try await apiService.queryFiles(
            apiKey: apiKey,
            query: SteamWorkshopQuery(
                sort: queryContext.sort,
                searchText: queryContext.searchText,
                cursor: cursor,
                pageSize: Self.displayedPageSize,
                requiredTag: Self.videoWebTags,
                matchAllTags: false
            )
        )
        let pageItems = payload.items
            .filter(\.isSupportedByCurrentPlayer)
            .prefix(Self.displayedPageSize)
        return WorkshopBrowseFetchResult(
            page: WorkshopBrowsePage(items: Array(pageItems), nextCursor: payload.nextCursor)
        )
    }

    private func showCurrentPage() {
        guard let state = pageState, let page = state.currentPage else { return }
        currentPageNumber = state.currentPageIndex + 1
        items = page.items
        selectedItem = items.first
    }

    @discardableResult
    func ensureSteamCMDInstalled() async -> Bool {
        do {
            try await steamCMDService.installIfMissing { [weak self] state in
                Task { @MainActor in
                    self?.installState = state
                }
            }
            installState = .installed(steamCMDService.paths.executableURL)
            refreshSavedLoginSessionAvailability()
            return true
        } catch {
            installState = .failed(error.localizedDescription)
            statusMessage = installState.statusText
            return false
        }
    }

    @discardableResult
    func repairSteamCMDRuntime() async -> Bool {
        do {
            try await steamCMDService.repairRuntime { [weak self] state in
                Task { @MainActor in
                    self?.installState = state
                }
            }
            installState = .installed(steamCMDService.paths.executableURL)
            refreshSavedLoginSessionAvailability()
            statusMessage = "SteamCMD runtime repaired."
            return true
        } catch {
            installState = .failed(error.localizedDescription)
            statusMessage = installState.statusText
            return false
        }
    }

    func download(itemID overrideItemID: String? = nil) async -> WEWallpaper? {
        isDownloading = true
        defer {
            isDownloading = false
            password = ""
            steamGuardCode = ""
        }

        var attemptedLogin: SteamCMDLogin?
        do {
            refreshSavedLoginSessionAvailability()
            let request = try makeDownloadRequest(itemInput: overrideItemID ?? manualItemInput)
            attemptedLogin = request.login
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
            _ = persistSuccessfulUsername(for: request.login)
            refreshSavedLoginSessionAvailability()
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
        } catch {
            if !handleDownloadError(error, attemptedLogin: attemptedLogin) {
                statusMessage = error.localizedDescription
            }
            return nil
        }
    }

    private func makeDownloadRequest(itemInput: String) throws -> SteamWorkshopDownloadRequest {
        guard let itemID = SteamWorkshopIDParser.publishedFileID(from: itemInput) else {
            throw SteamWorkshopDownloadInputError.invalidWorkshopID
        }

        let input = SteamWorkshopDownloadInput(
            itemInput: itemID,
            username: username,
            password: password,
            steamGuardCode: steamGuardCode
        )
        if password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let savedUsername = runtimeLoginState.reusableSavedSessionUsername else {
                return try input.makePasswordRequest()
            }
            return SteamWorkshopDownloadRequest(itemID: itemID, login: .savedSession(username: savedUsername))
        }
        return try input.makePasswordRequest()
    }

    private func handleDownloadError(_ error: Error, attemptedLogin: SteamCMDLogin?) -> Bool {
        guard let attemptedLogin else {
            return false
        }
        guard case .savedSession(let username) = attemptedLogin else {
            return false
        }
        guard let steamCMDError = error as? SteamCMDError else {
            return false
        }
        switch steamCMDError {
        case .steamGuardRequired, .loginFailed:
            runtimeLoginState = .invalidSavedSession(username: username)
            statusMessage = "Saved SteamCMD login expired. Enter your Steam password and current Steam Guard code, then download again."
            return true
        case .installFailed, .commandFailed, .downloadFailed:
            return false
        }
    }

    private func persistSuccessfulUsername(for login: SteamCMDLogin) -> Bool {
        let usernameToPersist: String
        switch login {
        case .account(let username, _, _), .savedSession(let username):
            usernameToPersist = username.trimmingCharacters(in: .whitespacesAndNewlines)
        case .anonymous:
            return false
        }
        guard !usernameToPersist.isEmpty else {
            return false
        }
        UserDefaults.standard.set(usernameToPersist, forKey: Self.usernameDefaultsKey)
        username = usernameToPersist
        runtimeLoginState = .reusableSavedSession(username: usernameToPersist)
        return true
    }

    func openWorkshopPage(for item: SteamWorkshopItem) {
        NSWorkspace.shared.open(SteamWorkshopSupport.workshopPageURL(itemID: item.id))
    }

    func openManualWorkshopPage() {
        if let itemID = SteamWorkshopIDParser.publishedFileID(from: manualItemInput) {
            NSWorkspace.shared.open(SteamWorkshopSupport.workshopPageURL(itemID: itemID))
        } else {
            NSWorkspace.shared.open(SteamWorkshopSupport.wallpaperEngineWorkshopURL)
        }
    }
}

private extension SteamCMDOutputEvent {
    var statusText: String {
        switch self {
        case .loginSucceeded:
            return "SteamCMD login succeeded."
        case .steamGuardRequired:
            return "Steam Guard required. Enter the code and download again."
        case .loginFailed:
            return "SteamCMD login failed."
        case .downloadSucceeded(let itemID):
            return "SteamCMD downloaded item \(itemID)."
        case .downloadFailed:
            return "SteamCMD download failed."
        }
    }
}

struct SteamWorkshopBrowser: View {
    @ObservedObject var contentViewModel: ContentViewModel
    @ObservedObject var wallpaperViewModel: WallpaperViewModel
    @StateObject private var viewModel = SteamWorkshopBrowserViewModel()
    @State private var isAdvancedControlsExpanded = false

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
    ]

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                primaryToolbar

                if isAdvancedControlsExpanded {
                    advancedControlsPanel
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !viewModel.statusMessage.isEmpty {
                    Label(viewModel.statusMessage, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                workshopContent
                    .layoutPriority(1)
            }
            .padding(.top, 8)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .onAppear {
            viewModel.refreshSteamCMDResolution()
            viewModel.loadAPIKey()
            if viewModel.apiKey.isEmpty {
                viewModel.statusMessage = "Open Advanced to paste a Steam Web API key, or download directly with a Workshop URL/ID."
            } else if viewModel.items.isEmpty {
                Task { await viewModel.browse() }
            }
        }
    }

    private var workshopContent: some View {
        GeometryReader { proxy in
            let layout = SteamWorkshopBrowserLayoutPolicy.layout(forWidth: proxy.size.width, height: proxy.size.height)

            if layout.presentation == .sideBySide {
                HSplitView {
                    workshopList
                        .frame(minWidth: 420)
                    workshopDetail
                        .frame(
                            minWidth: layout.detailWidthRange.lowerBound,
                            idealWidth: layout.detailWidthRange.upperBound,
                            maxWidth: layout.detailWidthRange.upperBound
                        )
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    workshopList
                        .frame(height: layout.listHeight)
                    Divider()
                    workshopDetail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var workshopList: some View {
        VStack(spacing: 8) {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(viewModel.items) { item in
                        WorkshopItemCard(
                            item: item,
                            isSelected: viewModel.selectedItem?.id == item.id
                        ) {
                            viewModel.selectedItem = item
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var primaryToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                sortPicker
                searchControls
                    .layoutPriority(1)
                workshopPaginationBar
                Spacer(minLength: 8)
                advancedToggleButton
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    searchControls
                    Spacer(minLength: 8)
                    advancedToggleButton
                }
                HStack(spacing: 8) {
                    sortPicker
                    workshopPaginationBar
                    Spacer()
                }
            }
        }
    }

    private var workshopPaginationBar: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.loadPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("Previous page")
            .disabled(viewModel.isLoading || !viewModel.canLoadPreviousPage)

            Text(viewModel.currentPageNumber > 0 ? "Page \(viewModel.currentPageNumber)" : "Page")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minWidth: 64)

            Button {
                Task { await viewModel.loadNextPage() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("Next page")
            .disabled(viewModel.isLoading || !viewModel.canLoadNextPage)

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .buttonStyle(.borderless)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var advancedToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isAdvancedControlsExpanded.toggle()
            }
        } label: {
            Label(isAdvancedControlsExpanded ? "Hide Advanced" : "Advanced", systemImage: "slider.horizontal.3")
        }
        .help(isAdvancedControlsExpanded ? "Hide advanced controls" : "Show advanced controls")
        .fixedSize(horizontal: true, vertical: false)
    }

    private var advancedControlsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            apiKeyBar
            Divider()
            steamCMDStatusBar
            Divider()
            manualDownloadBar
        }
        .padding(.vertical, 2)
    }

    private var workshopDetail: some View {
        WorkshopDetailPane(
            item: viewModel.selectedItem,
            isDownloading: viewModel.isDownloading,
            canDownload: viewModel.canStartDownload,
            download: { item in download(itemID: item.id) },
            openInSteam: { item in viewModel.openWorkshopPage(for: item) }
        )
    }

    private var steamCMDStatusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(viewModel.installState.statusText, systemImage: viewModel.installState.systemImage)
                    .foregroundStyle(viewModel.installState.tint)
                Text(viewModel.steamCMDPathSourceText)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Spacer()
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    steamCMDPathText
                    Spacer(minLength: 12)
                    steamCMDRuntimeActions
                }
                VStack(alignment: .leading, spacing: 8) {
                    steamCMDPathText
                    steamCMDRuntimeActions
                }
            }
        }
        .font(.footnote)
    }

    private var apiKeyBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                apiKeyField
                apiKeyActions
            }
            VStack(alignment: .leading, spacing: 8) {
                apiKeyField
                apiKeyActions
            }
        }
    }

    private var manualDownloadBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                manualItemField
                usernameField
                passwordField
                steamGuardField
                manualDownloadActions
            }
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
        }
    }

    private var steamCMDPathText: some View {
        Text(viewModel.steamCMDDirectoryPath)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private var steamCMDRuntimeActions: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    if viewModel.installState.isInstalled {
                        await viewModel.repairSteamCMDRuntime()
                    } else {
                        await viewModel.ensureSteamCMDInstalled()
                    }
                }
            } label: {
                Label(viewModel.installState.isInstalled ? "Repair" : "Install", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.installState.isBusy)
            Button {
                viewModel.openSteamCMDRuntimeFolder()
            } label: {
                Image(systemName: "folder")
            }
            .help("Open SteamCMD runtime folder")
            Button {
                Task { await viewModel.runSteamCMDDiagnostics() }
            } label: {
                Image(systemName: "stethoscope")
            }
            .help("Run diagnostics")
            Button(role: .destructive) {
                viewModel.resetSteamCMDRuntime()
            } label: {
                Image(systemName: "trash")
            }
            .help("Reset SteamCMD runtime")
            .disabled(viewModel.installState.isBusy)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var apiKeyField: some View {
        SecureField("Steam Web API Key", text: $viewModel.apiKey)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 220)
    }

    private var apiKeyActions: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.saveAPIKey()
            } label: {
                Label("Save", systemImage: "key.fill")
            }
            Link(destination: SteamWorkshopSupport.webAPIKeyURL) {
                Label("Get API Key", systemImage: "link")
            }
            Link(destination: SteamWorkshopSupport.wallpaperEngineWorkshopURL) {
                Label("Open Workshop", systemImage: "safari")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $viewModel.sort) {
            ForEach(SteamWorkshopQuery.Sort.allCases) { sort in
                Text(sort.title).tag(sort)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 320)
    }

    private var searchControls: some View {
        HStack(spacing: 8) {
            TextField("Search Workshop", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
            Button {
                Task { await viewModel.browse() }
            } label: {
                Label(viewModel.isLoading ? "Loading" : "Browse", systemImage: "magnifyingglass")
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var manualItemField: some View {
        TextField("Workshop URL or ID", text: $viewModel.manualItemInput)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 220)
    }

    private var usernameField: some View {
        TextField("Steam username", text: $viewModel.username)
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
    }

    private var passwordField: some View {
        SecureField("Steam password, not saved", text: $viewModel.password)
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
    }

    private var steamGuardField: some View {
        TextField("Steam Guard", text: $viewModel.steamGuardCode)
            .textFieldStyle(.roundedBorder)
            .frame(width: 130)
    }

    private var manualDownloadActions: some View {
        HStack(spacing: 8) {
            Button {
                download(itemID: nil)
            } label: {
                Label(viewModel.isDownloading ? "Downloading" : "Download", systemImage: "arrow.down.circle.fill")
            }
            .disabled(!viewModel.canStartDownload)
            .help(viewModel.canStartDownload ? "Download" : "SteamCMD must be ready before downloading")

            Button {
                viewModel.openManualWorkshopPage()
            } label: {
                Image(systemName: "safari")
            }
            .help("Open Workshop page")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func download(itemID: String?) {
        Task {
            if let wallpaper = await viewModel.download(itemID: itemID) {
                contentViewModel.refresh()
                wallpaperViewModel.nextCurrentWallpaper = wallpaper
            }
        }
    }
}

private struct WorkshopItemCard: View {
    let item: SteamWorkshopItem
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: item.previewURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image("we.placeholder")
                        .resizable()
                        .scaledToFit()
                        .padding(24)
                }
                .frame(height: 112)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color.secondary.opacity(0.12))

                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(minHeight: 48, alignment: .topLeading)

                Text(item.tags.prefix(3).joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack {
                    Text(scoreText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var scoreText: String {
        if let subscriptions = item.stats.subscriptions {
            return "\(subscriptions) subs"
        }
        if let score = item.stats.score {
            return String(format: "%.0f%%", score * 100)
        }
        return "Video/Web"
    }
}

private struct WorkshopDetailPane: View {
    let item: SteamWorkshopItem?
    let isDownloading: Bool
    let canDownload: Bool
    let download: (SteamWorkshopItem) -> Void
    let openInSteam: (SteamWorkshopItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let item {
                    AsyncImage(url: item.previewURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image("we.placeholder")
                            .resizable()
                            .scaledToFit()
                            .padding(36)
                    }
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .background(Color.secondary.opacity(0.12))

                    Text(item.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.fileDescription?.plainWorkshopText ?? "No description")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(item.tags.joined(separator: " / "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button {
                            download(item)
                        } label: {
                            Label("Download & Apply", systemImage: "arrow.down.circle.fill")
                        }
                        .disabled(isDownloading || !canDownload)

                        Button {
                            openInSteam(item)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .help("Open in Steam")

                        Spacer()
                    }
                } else {
                    Spacer(minLength: 80)
                    Label("Browse Workshop to select a wallpaper.", systemImage: "photo.on.rectangle.angled")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 80)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.leading, 10)
            .padding(.bottom, 8)
        }
    }
}

private extension SteamCMDInstallState {
    var systemImage: String {
        switch self {
        case .idle:
            return "terminal"
        case .checking:
            return "magnifyingglass"
        case .downloading:
            return "arrow.down.circle"
        case .extracting:
            return "archivebox"
        case .installed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .installed:
            return .green
        case .failed:
            return .red
        case .checking, .downloading, .extracting:
            return .accentColor
        case .idle:
            return .secondary
        }
    }
}

private extension String {
    var plainWorkshopText: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WallpaperDiscover_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: .init(isStaging: true, topTabBarSelection: 1), wallpaperViewModel: .init())
            .environmentObject(GlobalSettingsViewModel())
    }
}
