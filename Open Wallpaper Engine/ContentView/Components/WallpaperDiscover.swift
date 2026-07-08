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
}

private struct WorkshopBrowseQueryContext {
    var sort: SteamWorkshopQuery.Sort
    var searchText: String?

    init(sort: SteamWorkshopQuery.Sort, searchText: String) {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sort = trimmedSearch.isEmpty ? sort : .search
        self.searchText = trimmedSearch.isEmpty ? nil : trimmedSearch
    }
}

private struct WorkshopBrowseStream {
    let requiredTag: String
    var nextCursor = "*"
    var isExhausted = false
    var bufferedItems = [WorkshopBufferedItem]()

    var canFetch: Bool {
        !isExhausted
    }
}

private struct WorkshopBufferedItem {
    var item: SteamWorkshopItem
    var arrivalOrder: Int
}

private struct WorkshopBrowseSession {
    var queryContext: WorkshopBrowseQueryContext
    var streams = [
        WorkshopBrowseStream(requiredTag: "Video"),
        WorkshopBrowseStream(requiredTag: "Web")
    ]
    var seenItemIDs = Set<String>()
    var nextInterleavedStreamIndex = 0
    var nextArrivalOrder = 0

    var bufferedItemCount: Int {
        streams.reduce(0) { $0 + $1.bufferedItems.count }
    }

    var canFetchMore: Bool {
        streams.contains { $0.canFetch }
    }

    var canLoadMore: Bool {
        bufferedItemCount > 0 || canFetchMore
    }

    func fetchableStreamIndices() -> [Int] {
        streams.indices.filter { streams[$0].canFetch }
    }

    mutating func record(payload: SteamWorkshopQueryPayload, forStreamAt index: Int) {
        let playableItems = payload.items.filter(\.isSupportedByCurrentPlayer)
        for item in playableItems where seenItemIDs.insert(item.id).inserted {
            streams[index].bufferedItems.append(
                WorkshopBufferedItem(item: item, arrivalOrder: nextArrivalOrder)
            )
            nextArrivalOrder += 1
        }

        guard let responseCursor = payload.nextCursor, !responseCursor.isEmpty, responseCursor != streams[index].nextCursor else {
            streams[index].isExhausted = true
            return
        }
        streams[index].nextCursor = responseCursor
    }

    mutating func takePageItems(limit: Int) -> [SteamWorkshopItem] {
        if queryContext.sort == .latest {
            return takeLatestPageItems(limit: limit)
        }
        return takeInterleavedPageItems(limit: limit)
    }

    private mutating func takeLatestPageItems(limit: Int) -> [SteamWorkshopItem] {
        let selected = streams
            .flatMap(\.bufferedItems)
            .sorted { left, right in
                switch (left.item.timeCreated, right.item.timeCreated) {
                case let (leftTime?, rightTime?):
                    return leftTime > rightTime
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return left.arrivalOrder < right.arrivalOrder
                }
            }
            .prefix(limit)
        let selectedIDs = Set(selected.map(\.item.id))
        for index in streams.indices {
            streams[index].bufferedItems.removeAll { selectedIDs.contains($0.item.id) }
        }
        return selected.map(\.item)
    }

    private mutating func takeInterleavedPageItems(limit: Int) -> [SteamWorkshopItem] {
        var pageItems = [SteamWorkshopItem]()
        while pageItems.count < limit {
            var didTakeItem = false
            for offset in streams.indices {
                let index = (nextInterleavedStreamIndex + offset) % streams.count
                guard !streams[index].bufferedItems.isEmpty else {
                    continue
                }
                pageItems.append(streams[index].bufferedItems.removeFirst().item)
                nextInterleavedStreamIndex = (index + 1) % streams.count
                didTakeItem = true
                break
            }
            if !didTakeItem {
                break
            }
        }
        return pageItems
    }
}

private struct WorkshopBrowseFetchResult {
    var page: WorkshopBrowsePage
    var session: WorkshopBrowseSession
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
    private static let displayedPageSize = 36
    private static let steamBatchSize = 100

    @Published var apiKey = ""
    @Published var sort = SteamWorkshopQuery.Sort.popular
    @Published var searchText = ""
    @Published var manualItemInput = ""
    @Published var loginMode = SteamWorkshopLoginMode.anonymous
    @Published var username = UserDefaults.standard.string(forKey: "SteamWorkshopUsername") ?? ""
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
    private var pages = [WorkshopBrowsePage]()
    private var currentPageIndex = -1
    private var activeSession: WorkshopBrowseSession?

    init(
        apiService: SteamWorkshopAPIService = SteamWorkshopAPIService(),
        steamCMDResolution: SteamCMDPathResolution = SteamCMDPathResolver.resolve()
    ) {
        self.apiService = apiService
        self.steamCMDResolution = steamCMDResolution
        self.steamCMDService = SteamCMDService(resolution: steamCMDResolution)
        refreshInstallState()
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
        currentPageIndex > 0
    }

    var canLoadNextPage: Bool {
        guard currentPageIndex >= 0 else { return false }
        return currentPageIndex + 1 < pages.count || activeSession?.canLoadMore == true
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

    func resetSteamCMDRuntime() {
        do {
            try steamCMDService.resetRuntime()
            refreshInstallState()
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
                session: WorkshopBrowseSession(queryContext: queryContext)
            )
            activeSession = result.session
            pages = [result.page]
            showPage(at: 0)
            updateStatusForCurrentPage()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadNextPage() async {
        guard canLoadNextPage else { return }

        if currentPageIndex + 1 < pages.count {
            showPage(at: currentPageIndex + 1)
            updateStatusForCurrentPage()
            return
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, let session = activeSession else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await fetchPage(apiKey: trimmedKey, session: session)
            activeSession = result.session
            pages.append(result.page)
            showPage(at: pages.count - 1)
            updateStatusForCurrentPage()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func loadPreviousPage() {
        guard canLoadPreviousPage else { return }
        showPage(at: currentPageIndex - 1)
        updateStatusForCurrentPage()
    }

    private func updateStatusForCurrentPage() {
        statusMessage = items.isEmpty
            ? "No playable Video/Web Workshop items found on page \(currentPageNumber)."
            : "Loaded page \(currentPageNumber) with \(items.count) playable Workshop items."
    }

    private func fetchPage(
        apiKey: String,
        session: WorkshopBrowseSession
    ) async throws -> WorkshopBrowseFetchResult {
        var session = session

        while session.bufferedItemCount < Self.displayedPageSize, session.canFetchMore {
            let fetchableIndices = session.fetchableStreamIndices()
            guard !fetchableIndices.isEmpty else {
                break
            }

            for index in fetchableIndices {
                let stream = session.streams[index]
                let payload = try await apiService.queryFiles(
                    apiKey: apiKey,
                    query: SteamWorkshopQuery(
                        sort: session.queryContext.sort,
                        searchText: session.queryContext.searchText,
                        cursor: stream.nextCursor,
                        pageSize: Self.steamBatchSize,
                        requiredTag: stream.requiredTag
                    )
                )
                session.record(payload: payload, forStreamAt: index)
            }
        }

        let pageItems = session.takePageItems(limit: Self.displayedPageSize)
        return WorkshopBrowseFetchResult(
            page: WorkshopBrowsePage(items: pageItems),
            session: session
        )
    }

    private func showPage(at index: Int) {
        guard pages.indices.contains(index) else { return }
        currentPageIndex = index
        currentPageNumber = index + 1
        items = pages[index].items
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
            statusMessage = "SteamCMD runtime repaired."
            return true
        } catch {
            installState = .failed(error.localizedDescription)
            statusMessage = installState.statusText
            return false
        }
    }

    func download(itemID overrideItemID: String? = nil) async -> WEWallpaper? {
        guard await ensureSteamCMDInstalled() else {
            return nil
        }

        isDownloading = true
        defer {
            isDownloading = false
            password = ""
            steamGuardCode = ""
        }

        do {
            UserDefaults.standard.set(username, forKey: "SteamWorkshopUsername")
            let input = SteamWorkshopDownloadInput(
                itemInput: overrideItemID ?? manualItemInput,
                loginMode: loginMode,
                username: username,
                password: password,
                steamGuardCode: steamGuardCode
            )
            let request = try input.makeRequest()
            manualItemInput = request.itemID
            statusMessage = "Starting SteamCMD download for \(request.itemID)..."
            let directory = try await steamCMDService.downloadItem(
                itemID: request.itemID,
                login: request.login
            ) { [weak self] event in
                Task { @MainActor in
                    self?.statusMessage = event.statusText
                }
            }
            let wallpaper = WorkshopLibraryService.scanDownloadedWallpapers(at: directory).first
            statusMessage = wallpaper == nil
                ? "Download finished, but no playable project.json was found."
                : "Downloaded \(wallpaper?.project.title ?? request.itemID)."
            return wallpaper
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
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

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
    ]

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                apiKeyBar
                steamCMDStatusBar
                browserToolbar
                manualDownloadBar

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
            .clipped()
        }
        .onAppear {
            viewModel.refreshSteamCMDResolution()
            viewModel.loadAPIKey()
            Task { await viewModel.ensureSteamCMDInstalled() }
            if viewModel.apiKey.isEmpty {
                viewModel.statusMessage = "Paste a Steam Web API key to browse here, or use a Workshop URL/ID to download directly."
            } else if viewModel.items.isEmpty {
                Task { await viewModel.browse() }
            }
        }
    }

    private var workshopContent: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 820 {
                HSplitView {
                    workshopList
                        .frame(minWidth: 420)
                    workshopDetail
                        .frame(minWidth: 260, maxWidth: 340)
                }
            } else {
                let listHeight = max(240, proxy.size.height * 0.55)
                VStack(alignment: .leading, spacing: 12) {
                    workshopList
                        .frame(height: listHeight)
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
                            isSelected: viewModel.selectedItem?.id == item.id,
                            isDownloading: viewModel.isDownloading,
                            canDownload: viewModel.canStartDownload
                        ) {
                            viewModel.selectedItem = item
                        } download: {
                            download(itemID: item.id)
                        } openInSteam: {
                            viewModel.openWorkshopPage(for: item)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            workshopPaginationBar
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

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.top, 2)
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

    private var browserToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                sortPicker
                searchControls
            }
            VStack(alignment: .leading, spacing: 8) {
                sortPicker
                searchControls
            }
        }
    }

    private var manualDownloadBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                manualItemField
                loginModePicker
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
                    loginModePicker
                    usernameField
                }
                HStack(spacing: 8) {
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
        .frame(width: 360)
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

    private var loginModePicker: some View {
        Picker("Login", selection: $viewModel.loginMode) {
            ForEach(SteamWorkshopLoginMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 330)
    }

    private var usernameField: some View {
        TextField("Steam username", text: $viewModel.username)
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
            .disabled(viewModel.loginMode == .anonymous)
    }

    private var passwordField: some View {
        SecureField("Steam password, not saved", text: $viewModel.password)
            .textFieldStyle(.roundedBorder)
            .frame(width: 220)
            .disabled(viewModel.loginMode != .password)
    }

    private var steamGuardField: some View {
        TextField("Steam Guard", text: $viewModel.steamGuardCode)
            .textFieldStyle(.roundedBorder)
            .frame(width: 130)
            .disabled(viewModel.loginMode != .password)
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
    let isDownloading: Bool
    let canDownload: Bool
    let select: () -> Void
    let download: () -> Void
    let openInSteam: () -> Void

    var body: some View {
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
                Button(action: download) {
                    Image(systemName: "arrow.down")
                }
                .help("Download")
                .disabled(isDownloading || !canDownload)

                Button(action: openInSteam) {
                    Image(systemName: "safari")
                }
                .help("Open in Steam")

                Spacer()
                Text(scoreText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
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
        .onTapGesture(perform: select)
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
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color.secondary.opacity(0.12))

                Text(item.title)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(3)

                ScrollView {
                    Text(item.fileDescription?.plainWorkshopText ?? "No description")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 90)

                Text(item.tags.joined(separator: " / "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

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
                }
            } else {
                Spacer()
                Label("Browse Workshop to select a wallpaper.", systemImage: "photo.on.rectangle.angled")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.leading, 10)
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
