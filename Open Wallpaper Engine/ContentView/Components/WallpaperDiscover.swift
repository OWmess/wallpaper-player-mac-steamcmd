//
//  WallpaperDiscover.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/21.
//

import SwiftUI
import AppKit

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
    @Published var apiKey = ""
    @Published var sort = SteamWorkshopQuery.Sort.popular
    @Published var searchText = ""
    @Published var manualItemInput = ""
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

    private let apiService: SteamWorkshopAPIService
    private var steamCMDService: SteamCMDService

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
        if FileManager.default.fileExists(atPath: steamCMDService.paths.executableURL.path) {
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
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveSort: SteamWorkshopQuery.Sort = trimmedSearch.isEmpty ? sort : .search
            let payload = try await apiService.queryFiles(
                apiKey: trimmedKey,
                query: SteamWorkshopQuery(
                    sort: effectiveSort,
                    searchText: trimmedSearch.isEmpty ? nil : trimmedSearch,
                    pageSize: 36
                )
            )
            items = payload.items.filter(\.isSupportedByCurrentPlayer)
            selectedItem = items.first
            statusMessage = items.isEmpty
                ? "No playable Video/Web Workshop items found."
                : "Loaded \(items.count) playable Workshop items."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func ensureSteamCMDInstalled() async -> Bool {
        do {
            try await steamCMDService.installIfNeeded { [weak self] state in
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

            HSplitView {
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
                .frame(minWidth: 520)

                WorkshopDetailPane(
                    item: viewModel.selectedItem,
                    isDownloading: viewModel.isDownloading,
                    canDownload: viewModel.canStartDownload,
                    download: { item in download(itemID: item.id) },
                    openInSteam: { item in viewModel.openWorkshopPage(for: item) }
                )
                .frame(minWidth: 260, maxWidth: 340)
            }
        }
        .padding(.top, 8)
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

    private var steamCMDStatusBar: some View {
        HStack(spacing: 8) {
            Label(viewModel.installState.statusText, systemImage: viewModel.installState.systemImage)
                .foregroundStyle(viewModel.installState.tint)
            Text(viewModel.steamCMDPathSourceText)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            Text(viewModel.steamCMDDirectoryPath)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Button {
                Task { await viewModel.ensureSteamCMDInstalled() }
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
        .font(.footnote)
    }

    private var apiKeyBar: some View {
        HStack(spacing: 8) {
            SecureField("Steam Web API Key", text: $viewModel.apiKey)
                .textFieldStyle(.roundedBorder)
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
    }

    private var browserToolbar: some View {
        HStack(spacing: 8) {
            Picker("Sort", selection: $viewModel.sort) {
                ForEach(SteamWorkshopQuery.Sort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 360)

            TextField("Search Workshop", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await viewModel.browse() }
            } label: {
                Label(viewModel.isLoading ? "Loading" : "Browse", systemImage: "magnifyingglass")
            }
            .disabled(viewModel.isLoading)
        }
    }

    private var manualDownloadBar: some View {
        HStack(spacing: 8) {
            TextField("Workshop URL or ID", text: $viewModel.manualItemInput)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
            TextField("Steam username", text: $viewModel.username)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
            SecureField("Steam password, not saved", text: $viewModel.password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            TextField("Steam Guard", text: $viewModel.steamGuardCode)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
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
                .frame(minHeight: 40, alignment: .topLeading)

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
