//
//  PluginsPage.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/12.
//

import SwiftUI
import AppKit

struct PluginsPage: SettingsPage {
    @ObservedObject var viewModel: GlobalSettingsViewModel

    @AppStorage("SteamWorkshopUsername") private var steamUsername = ""
    @State private var steamWebAPIKey = ""
    @State private var statusMessage = ""
    @State private var installState = SteamCMDInstallState.idle
    @State private var steamCMDResolution = SteamCMDPathResolver.resolve()

    private var steamCMDService: SteamCMDService {
        SteamCMDService(resolution: steamCMDResolution)
    }

    init(globalSettings viewModel: GlobalSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    SecureField("Steam Web API Key", text: $steamWebAPIKey)
                    Button {
                        saveAPIKey()
                    } label: {
                        Label("Save", systemImage: "key.fill")
                    }
                    Link(destination: SteamWorkshopSupport.webAPIKeyURL) {
                        Label("Get API Key", systemImage: "link")
                    }
                }
                Text("Get a Steam Web API key at steamcommunity.com/dev/apikey, then paste it here to enable in-app Workshop browsing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Workshop Browse", systemImage: "sparkle.magnifyingglass")
            }

            Section {
                TextField("Steam username", text: $steamUsername)
                Text("The app stores this username only. Steam passwords and Steam Guard codes stay in the download form for one run and are not saved by Open Wallpaper Engine. When SteamCMD keeps a valid login in its runtime, downloads can reuse it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Steam Login", systemImage: "person.crop.circle")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Label(installState.statusText, systemImage: installState.systemImage)
                            .foregroundStyle(installState.tint)
                        Spacer()
                    }
                    steamCMDActionButtons
                    Text(steamCMDDirectoryStatusText)
                        .font(.caption)
                        .textSelection(.enabled)
                    Text("Source: \(steamCMDResolution.source.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("The app manages SteamCMD in a private runtime and executes the SteamCMD binary through the bundled runner. Install only creates missing files; Repair runs SteamCMD's own check/update. Clearing the session removes SteamCMD login state but keeps downloaded Workshop content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("SteamCMD", systemImage: "terminal")
            }

            if !statusMessage.isEmpty {
                Section {
                    Label(statusMessage, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            steamWebAPIKey = (try? SteamWorkshopCredentialStore.loadAPIKey()) ?? ""
            refreshInstallState()
        }
    }

    private func saveAPIKey() {
        do {
            let trimmed = steamWebAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try SteamWorkshopCredentialStore.deleteAPIKey()
                statusMessage = "Steam Web API key removed."
            } else {
                try SteamWorkshopCredentialStore.saveAPIKey(trimmed)
                steamWebAPIKey = trimmed
                statusMessage = "Steam Web API key saved to Keychain."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private var steamCMDActionButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    installSteamCMD()
                } label: {
                    steamCMDActionLabel(installState.isInstalled ? "Repair" : "Install", systemImage: "arrow.clockwise")
                }
                .disabled(installState.isBusy)

                Button {
                    openSteamCMDRuntimeFolder()
                } label: {
                    steamCMDActionLabel("Open Runtime", systemImage: "folder")
                }

                Button {
                    runSteamCMDDiagnostics()
                } label: {
                    steamCMDActionLabel("Diagnostics", systemImage: "stethoscope")
                }
            }

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    resetSteamCMDRuntime()
                } label: {
                    steamCMDActionLabel("Reset Runtime", systemImage: "trash")
                }
                .disabled(installState.isBusy)

                Button(role: .destructive) {
                    clearSteamSession()
                } label: {
                    steamCMDActionLabel("Clear Steam Session", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private func steamCMDActionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func clearSteamSession() {
        Task {
            do {
                try await steamCMDService.clearLoginSession()
                statusMessage = "SteamCMD session cleared. Downloaded Workshop files were kept."
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private var steamCMDDirectoryStatusText: String {
        if let authorizationIssue = steamCMDResolution.authorizationIssue {
            return authorizationIssue.recoveryMessage
        }
        return steamCMDService.paths.steamCMDDirectory.path
    }

    private func reloadSteamCMDResolution() {
        steamCMDResolution = SteamCMDPathResolver.resolve()
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

    private func installSteamCMD() {
        Task {
            do {
                let shouldRepair = installState.isInstalled
                if shouldRepair {
                    try await steamCMDService.repairRuntime { state in
                        Task { @MainActor in
                            installState = state
                        }
                    }
                } else {
                    try await steamCMDService.installIfMissing { state in
                        Task { @MainActor in
                            installState = state
                        }
                    }
                }
                installState = .installed(steamCMDService.paths.executableURL)
                statusMessage = shouldRepair ? "SteamCMD runtime repaired." : "SteamCMD is ready."
            } catch {
                installState = .failed(error.localizedDescription)
                statusMessage = installState.statusText
            }
        }
    }

    private func resetSteamCMDRuntime() {
        do {
            try steamCMDService.resetRuntime()
            refreshInstallState()
            statusMessage = "SteamCMD runtime reset. Install again to rebuild it."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func openSteamCMDRuntimeFolder() {
        let url = steamCMDService.paths.steamCMDDirectory
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func runSteamCMDDiagnostics() {
        Task {
            let diagnostics = await steamCMDService.diagnostics()
            statusMessage = [
                diagnostics.isUsingXPCClient ? "Runner: XPC" : "Runner: local",
                "cwd: \(diagnostics.cwd.path)",
                "HOME: \(diagnostics.home.path)"
            ].joined(separator: " | ")
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
