import Foundation

final class SteamCMDRunnerService: NSObject, SteamCMDRunnerXPCProtocol {
    func install(runtimePath: String, reply: @escaping (NSDictionary) -> Void) {
        Task.detached {
            let core = SteamCMDRunnerService.core(runtimePath: runtimePath)
            do {
                let result = try await core.installIfNeeded()
                reply(SteamCMDRunnerXPCPayload.success(result))
            } catch {
                reply(SteamCMDRunnerXPCPayload.failure(error))
            }
        }
    }

    func download(runtimePath: String, itemID: String, login: NSDictionary, reply: @escaping (NSDictionary) -> Void) {
        Task.detached {
            let core = SteamCMDRunnerService.core(runtimePath: runtimePath)
            do {
                let result = try await core.downloadItem(
                    itemID: itemID,
                    login: SteamCMDRunnerXPCPayload.login(from: login),
                    output: { _ in }
                )
                reply(SteamCMDRunnerXPCPayload.success(result))
            } catch {
                reply(SteamCMDRunnerXPCPayload.failure(error))
            }
        }
    }

    func clearSession(runtimePath: String, legacyRuntimePaths: [String], reply: @escaping (NSDictionary) -> Void) {
        do {
            let core = SteamCMDRunnerService.core(runtimePath: runtimePath)
            let legacyPaths = legacyRuntimePaths.map {
                SteamCMDPaths(steamCMDDirectory: URL(fileURLWithPath: $0, isDirectory: true))
            }
            try core.clearLoginSession(legacyPaths: legacyPaths)
            reply(SteamCMDRunnerXPCPayload.success(
                SteamCMDRunnerResult(
                    runtimeURL: URL(fileURLWithPath: runtimePath, isDirectory: true),
                    downloadedItemURL: nil,
                    recentOutput: []
                )
            ))
        } catch {
            reply(SteamCMDRunnerXPCPayload.failure(error))
        }
    }

    func diagnostics(runtimePath: String, source: String, legacyRuntimePaths: [String], reply: @escaping (NSDictionary) -> Void) {
        Task.detached {
            let paths = SteamCMDPaths(steamCMDDirectory: URL(fileURLWithPath: runtimePath, isDirectory: true))
            let legacyPaths = legacyRuntimePaths.map {
                SteamCMDPaths(steamCMDDirectory: URL(fileURLWithPath: $0, isDirectory: true))
            }
            let core = SteamCMDRunnerCore(paths: paths)
            let diagnostics = await core.diagnostics(
                source: .managedRuntime,
                legacyPaths: legacyPaths,
                isUsingXPCClient: true
            )
            reply(SteamCMDRunnerXPCPayload.success(diagnostics))
        }
    }

    private static func core(runtimePath: String) -> SteamCMDRunnerCore {
        SteamCMDRunnerCore(
            paths: SteamCMDPaths(
                steamCMDDirectory: URL(fileURLWithPath: runtimePath, isDirectory: true)
            )
        )
    }
}

final class SteamCMDRunnerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: SteamCMDRunnerXPCProtocol.self)
        connection.exportedObject = SteamCMDRunnerService()
        connection.resume()
        return true
    }
}

let delegate = SteamCMDRunnerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
