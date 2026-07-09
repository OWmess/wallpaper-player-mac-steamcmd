//
//  WEProject.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/6/5.
//

import SwiftUI
import ImageIO
import Security
import Darwin

struct WEProjectPropertyOption: Codable, Equatable, Hashable {
    var label: String
    var value: String
}

struct WEProjectProperty: Codable, Equatable, Hashable {
    // optional
    var condition: String?
    var index: Int?
    var options: [WEProjectPropertyOption]?
    var order: Int?

    // must have
    var text: String
    var type: String
    var value: String
}

struct WEProjectProperties: Codable, Equatable, Hashable {
    var schemecolor: WEProjectProperty?
}

struct WEProjectGeneral: Codable, Equatable, Hashable {
    var properties: WEProjectProperties
}

enum WorkshopId: Codable, Equatable, Hashable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) {
            self = .int(x)
            return
        }
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        throw DecodingError.typeMismatch(Self.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for Workshop ID"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let x):
            try container.encode(x)
        case .string(let x):
            try container.encode(x)
        }
    }
}

struct WEProject: Codable, Equatable, Hashable {
    var contentrating: String?
    var description: String?
    var file: String
    var general: WEProjectGeneral?
    var preview: String
    var tags: [String]?
    var title: String
    var visibility: String?
    var workshopid: WorkshopId?
    var type: String
    var version: Int?

    static let invalid = Self(file: "",
                              preview: "",
                              title: "Error",
                              type: "video")
}

struct WEWallpaper: Codable, RawRepresentable, Identifiable {

    var id: Int { self.project.hashValue }
    var rawValue: String {
        do {
            let rawValueData = try JSONEncoder().encode(self)
            return String(data: rawValueData, encoding: .utf8)!
        } catch {
            print(error)
            return ""
        }
    }

    var wallpaperDirectory: URL
    var project: WEProject

    init(using project: WEProject, where url: URL) {
        self.wallpaperDirectory = url
        self.project = project
    }

    enum CodingKeys: CodingKey {
        case wallpaperDirectory
        case project
        // <all the other elements too>
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.wallpaperDirectory = try container.decode(URL.self, forKey: .wallpaperDirectory)
        self.project = try container.decode(WEProject.self, forKey: .project)
        // <and so on>
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wallpaperDirectory, forKey: .wallpaperDirectory)
        try container.encode(project, forKey: .project)
        // <and so on>
    }

    init?(rawValue: String) {
        if let rawValueData = rawValue.data(using: .utf8),
           let wallpaper = try? JSONDecoder().decode(WEWallpaper.self, from: rawValueData) {
            self = wallpaper
        } else {
            return nil
        }
    }
}

enum WEWallpaperSortingMethod: String {
    case name, rating, likes, size, dateSubscribed, dateAdded
}

enum WEWallpaperSortingSequence: String, CaseIterable {
    case increased, decreased
}

enum WEInitError: Error {
    enum WEJSONProjectInitError: Error {
        case notFound, corrupted, mismatched, unkownError
    }

    enum WEResourcesInitError: Error {
        case notFound, mismatchedFormat, corrupted, unkownError
    }

    enum WEPreviewInitError: Error {
        case notFound, notImage, unkownError
    }

    case badDirectoryPath
    case JSONProject(was: WEJSONProjectInitError)
    case resources(was: WEResourcesInitError)
    case preview(was: WEPreviewInitError)
}

enum SteamWorkshopIDParser {
    static func publishedFileID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.allSatisfy({ $0.isNumber }) {
            return trimmed
        }

        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
           id.allSatisfy({ $0.isNumber }) {
            return id
        }

        if let range = trimmed.range(of: #"CommunityFilePage/(\d+)"#, options: .regularExpression) {
            return String(trimmed[range]).split(separator: "/").last.map(String.init)
        }

        return nil
    }
}

struct SteamWorkshopQueryResponse: Decodable {
    let response: SteamWorkshopQueryPayload
}

struct SteamWorkshopQueryPayload: Decodable {
    let total: Int
    let nextCursor: String?
    let items: [SteamWorkshopItem]

    enum CodingKeys: String, CodingKey {
        case total
        case nextCursor = "next_cursor"
        case items = "publishedfiledetails"
    }
}

struct SteamWorkshopItem: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let fileDescription: String?
    let creator: String?
    let previewURL: URL?
    let timeCreated: Int?
    let tags: [String]
    let previews: [SteamWorkshopPreview]
    let metadata: SteamWorkshopMetadata?
    let stats: SteamWorkshopStats

    var isSupportedByCurrentPlayer: Bool {
        let candidates = Set((tags + [metadata?.type].compactMap { $0 }).map { $0.lowercased() })
        return candidates.contains("video") || candidates.contains("web")
    }

    enum CodingKeys: String, CodingKey {
        case id = "publishedfileid"
        case title
        case fileDescription = "file_description"
        case creator
        case previewURL = "preview_url"
        case timeCreated = "time_created"
        case tags
        case previews
        case metadata
        case subscriptions
        case favorited
        case lifetimeFavorited = "lifetime_favorited"
        case score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        fileDescription = try container.decodeIfPresent(String.self, forKey: .fileDescription)
        creator = try container.decodeIfPresent(String.self, forKey: .creator)
        previewURL = try container.decodeIfPresent(URL.self, forKey: .previewURL)
        timeCreated = Self.decodeFlexibleInt(container, forKey: .timeCreated)
        tags = (try container.decodeIfPresent([SteamWorkshopTag].self, forKey: .tags) ?? []).map(\.tag)
        previews = try container.decodeIfPresent([SteamWorkshopPreview].self, forKey: .previews) ?? []

        if let metadataString = try container.decodeIfPresent(String.self, forKey: .metadata),
           let data = metadataString.data(using: .utf8) {
            metadata = try? JSONDecoder().decode(SteamWorkshopMetadata.self, from: data)
        } else {
            metadata = nil
        }

        stats = SteamWorkshopStats(
            subscriptions: Self.decodeFlexibleInt(container, forKey: .subscriptions),
            favorited: Self.decodeFlexibleInt(container, forKey: .favorited),
            lifetimeFavorited: Self.decodeFlexibleInt(container, forKey: .lifetimeFavorited),
            score: Self.decodeFlexibleDouble(container, forKey: .score)
        )
    }

    private static func decodeFlexibleInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    private static func decodeFlexibleDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }
}

struct SteamWorkshopTag: Decodable, Equatable {
    let tag: String
}

struct SteamWorkshopPreview: Decodable, Equatable {
    let previewType: Int?
    let url: URL?

    enum CodingKeys: String, CodingKey {
        case previewType = "preview_type"
        case url
    }
}

struct SteamWorkshopMetadata: Decodable, Equatable {
    let type: String?
    let preview: String?
}

struct SteamWorkshopStats: Equatable {
    let subscriptions: Int?
    let favorited: Int?
    let lifetimeFavorited: Int?
    let score: Double?
}

enum SteamCMDOutputEvent: Equatable {
    case loginSucceeded
    case steamGuardRequired
    case loginFailed
    case downloadSucceeded(itemID: String)
    case downloadFailed
}

enum SteamCMDOutputParser {
    static func event(from line: String) -> SteamCMDOutputEvent? {
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
        if lowercased.contains("downloaded item"),
           let id = firstNumber(after: "item", in: line) {
            return .downloadSucceeded(itemID: id)
        }
        if lowercased.contains("download item") && lowercased.contains("failed") {
            return .downloadFailed
        }
        return nil
    }

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

    static func downloadedItemDirectory(from line: String) -> URL? {
        let lowercased = line.lowercased()
        guard lowercased.contains("downloaded item"),
              let toRange = line.range(of: " to ", options: .caseInsensitive) else {
            return nil
        }

        let remainder = line[toRange.upperBound...]
        guard let openingQuote = remainder.firstIndex(of: "\"") else {
            return nil
        }
        let pathStart = remainder.index(after: openingQuote)
        guard let closingQuote = remainder[pathStart...].firstIndex(of: "\"") else {
            return nil
        }
        return URL(fileURLWithPath: String(remainder[pathStart..<closingQuote]), isDirectory: true)
    }

    static func failedItemID(from line: String) -> String? {
        let lowercased = line.lowercased()
        guard lowercased.contains("download item"),
              lowercased.contains("failed") else {
            return nil
        }
        return firstNumber(after: "item", in: line)
    }

    private static func firstNumber(after marker: String, in line: String) -> String? {
        guard let markerRange = line.range(of: marker, options: .caseInsensitive) else { return nil }
        let remainder = line[markerRange.upperBound...]
        return remainder
            .split(whereSeparator: { !$0.isNumber })
            .first
            .map(String.init)
    }
}

struct SteamCMDOutputStreamParser {
    private var isWaitingForUserInfo = false

    mutating func event(from line: String) -> SteamCMDOutputEvent? {
        let lowercased = line.lowercased()
        if isWaitingForUserInfo, lowercased.contains("ok") {
            isWaitingForUserInfo = false
            return .loginSucceeded
        }
        isWaitingForUserInfo = lowercased.contains("waiting for user info")
        return SteamCMDOutputParser.event(from: line)
    }
}

enum WorkshopLibraryService {
    static func scanDownloadedWallpapers(at root: URL) -> [WEWallpaper] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { entry in
            guard let projectURL = entry as? URL,
                  projectURL.lastPathComponent == "project.json",
                  let data = try? Data(contentsOf: projectURL),
                  let project = try? JSONDecoder().decode(WEProject.self, from: data),
                  ["video", "web"].contains(project.type.lowercased()) else {
                return nil
            }
            return WEWallpaper(using: project, where: projectURL.deletingLastPathComponent())
        }
    }
}

struct SteamWorkshopQuery: Equatable {
    enum Sort: String, CaseIterable, Identifiable {
        case popular
        case trending
        case latest
        case search

        var id: Self { self }

        var queryType: Int {
            switch self {
            case .popular:
                return 9
            case .trending:
                return 3
            case .latest:
                return 1
            case .search:
                return 12
            }
        }

        var title: String {
            switch self {
            case .popular:
                return "Popular"
            case .trending:
                return "Trending"
            case .latest:
                return "Latest"
            case .search:
                return "Search"
            }
        }
    }

    var sort: Sort = .popular
    var searchText: String? = nil
    var cursor: String? = nil
    var pageSize: Int = 30
    var creatorAppID: Int = 431960
    var requiredTag: String? = nil
    var matchAllTags: Bool = true
    var days: Int? = nil
}

private struct SteamWorkshopQueryRequestPayload: Encodable {
    let appid = 431960
    let creatorAppID: Int
    let queryType: Int
    let numPerPage: Int
    let cursor: String
    let requiredTag: String?
    let matchAllTags: Bool
    let searchText: String?
    let days: Int?
    let returnDetails = true
    let returnMetadata = true
    let returnPreviews = true
    let returnTags = true
    let returnVoteData = true

    enum CodingKeys: String, CodingKey {
        case appid
        case creatorAppID = "creator_appid"
        case queryType = "query_type"
        case numPerPage = "numperpage"
        case cursor
        case requiredTag = "requiredtags"
        case matchAllTags = "match_all_tags"
        case searchText = "search_text"
        case days
        case returnDetails = "return_details"
        case returnMetadata = "return_metadata"
        case returnPreviews = "return_previews"
        case returnTags = "return_tags"
        case returnVoteData = "return_vote_data"
    }

    init(query: SteamWorkshopQuery) {
        let trimmedSearch = query.searchText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTag = query.requiredTag?.trimmingCharacters(in: .whitespacesAndNewlines)

        creatorAppID = query.creatorAppID
        queryType = query.sort.queryType
        numPerPage = query.pageSize
        cursor = query.cursor?.isEmpty == false ? query.cursor! : "*"
        requiredTag = trimmedTag?.isEmpty == false ? trimmedTag : nil
        matchAllTags = query.matchAllTags
        searchText = trimmedSearch?.isEmpty == false ? trimmedSearch : nil
        days = query.days ?? (query.sort == .trending ? 7 : nil)
    }
}

enum SteamWorkshopAPIError: LocalizedError {
    case invalidRequest
    case badStatusCode(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Unable to build Steam Workshop request."
        case .badStatusCode(let code):
            return "Steam Workshop request failed with HTTP \(code)."
        }
    }
}

protocol SteamWorkshopHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: SteamWorkshopHTTPClient {}

struct SteamWorkshopAPIService {
    var httpClient: SteamWorkshopHTTPClient = URLSession.shared
    var decoder = JSONDecoder()

    static func makeQueryRequest(apiKey: String, query: SteamWorkshopQuery) throws -> URLRequest {
        let payload = SteamWorkshopQueryRequestPayload(query: query)
        let data = try JSONEncoder().encode(payload)
        guard let inputJSON = String(data: data, encoding: .utf8) else {
            throw SteamWorkshopAPIError.invalidRequest
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.steampowered.com"
        components.path = "/IPublishedFileService/QueryFiles/v1/"
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "input_json", value: inputJSON)
        ]

        guard let url = components.url else {
            throw SteamWorkshopAPIError.invalidRequest
        }

        return URLRequest(url: url)
    }

    func queryFiles(apiKey: String, query: SteamWorkshopQuery) async throws -> SteamWorkshopQueryPayload {
        let request = try Self.makeQueryRequest(apiKey: apiKey, query: query)
        let (data, response) = try await httpClient.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw SteamWorkshopAPIError.badStatusCode(httpResponse.statusCode)
        }
        return try decoder.decode(SteamWorkshopQueryResponse.self, from: data).response
    }
}

enum SteamCMDLogin: Equatable {
    case anonymous
    case savedSession(username: String)
    case account(username: String, password: String, steamGuardCode: String?)
}

struct SteamCMDDownloadCommand: Equatable {
    static let wallpaperEngineAppID = "431960"

    let itemID: String
    let login: SteamCMDLogin

    var arguments: [String] {
        var result = ["+@sSteamCmdForcePlatformType", "windows"]
        switch login {
        case .anonymous:
            result += ["+login", "anonymous"]
        case .savedSession(let username):
            result += ["+login", username]
        case .account(let username, let password, let steamGuardCode):
            result += ["+login", username, password]
            if let steamGuardCode, !steamGuardCode.isEmpty {
                result.append(steamGuardCode)
            }
        }
        result += ["+workshop_download_item", Self.wallpaperEngineAppID, itemID, "+quit"]
        return result
    }
}

enum SteamCMDInstallState: Equatable {
    case idle
    case checking
    case downloading
    case extracting
    case installed(URL)
    case failed(String)

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .extracting:
            return true
        case .idle, .installed, .failed:
            return false
        }
    }

    var statusText: String {
        switch self {
        case .idle:
            return "SteamCMD is not installed yet."
        case .checking:
            return "Checking SteamCMD installation..."
        case .downloading:
            return "Downloading SteamCMD from Valve..."
        case .extracting:
            return "Installing SteamCMD..."
        case .installed:
            return "SteamCMD is ready."
        case .failed(let message):
            return "SteamCMD install failed: \(message)"
        }
    }
}

enum SteamCMDPathSource: Equatable {
    case environmentOverride
    case managedRuntime
    case userSelected
    case notConfigured

    var label: String {
        switch self {
        case .environmentOverride:
            return "Environment override"
        case .managedRuntime:
            return "App managed"
        case .userSelected:
            return "User selected"
        case .notConfigured:
            return "Not configured"
        }
    }
}

enum SteamCMDRuntimeAuthorizationIssue: Error, Equatable {
    case runtimeDirectoryNotSelected
    case staleRuntimeDirectoryBookmark
    case runtimeDirectoryBookmarkInvalid(String)

    var recoveryMessage: String {
        switch self {
        case .runtimeDirectoryNotSelected:
            return "Choose a SteamCMD Runtime folder before installing SteamCMD. macOS requires a user-authorized folder for app-managed command-line tools."
        case .staleRuntimeDirectoryBookmark:
            return "The saved SteamCMD Runtime folder permission is stale. Choose the folder again to refresh macOS authorization."
        case .runtimeDirectoryBookmarkInvalid(let message):
            return "The saved SteamCMD Runtime folder could not be opened: \(message)"
        }
    }
}

enum SteamCMDRuntimeSelection: Equatable {
    case selected(URL)
    case missing
    case unavailable(SteamCMDRuntimeAuthorizationIssue)
}

struct SteamCMDRuntimeBookmarkResolution: Equatable {
    var url: URL
    var isStale: Bool
}

struct SteamCMDPaths: Equatable {
    var steamCMDDirectory: URL
    var securityScopedResourceURL: URL?

    init(steamCMDDirectory: URL, securityScopedResourceURL: URL? = nil) {
        self.steamCMDDirectory = steamCMDDirectory
        self.securityScopedResourceURL = securityScopedResourceURL
    }

    init(applicationSupportDirectory: URL) {
        self.init(steamCMDDirectory: applicationSupportDirectory.appendingPathComponent("SteamCMD", isDirectory: true))
    }

    init(managedRuntimeRoot: URL) {
        self.init(
            steamCMDDirectory: managedRuntimeRoot
                .appendingPathComponent("SteamCMDManaged", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
        )
    }

    init(userSelectedRuntimeDirectory: URL) {
        self.init(
            steamCMDDirectory: userSelectedRuntimeDirectory.appendingPathComponent("SteamCMD", isDirectory: true),
            securityScopedResourceURL: userSelectedRuntimeDirectory
        )
    }

    static var appPrivateApplicationSupportRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var appPrivateApplicationSupportDirectory: URL {
        legacyApplicationSupportDirectory(in: appPrivateApplicationSupportRoot)
    }

    static func v2RuntimeDirectory(in applicationSupportRoot: URL) -> URL {
        applicationSupportRoot
            .appendingPathComponent("SteamCMDRuntime", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
    }

    static func managedRuntimeDirectory(in applicationSupportRoot: URL) -> URL {
        applicationSupportRoot
            .appendingPathComponent("SteamCMDManaged", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    static func legacyApplicationSupportDirectory(in applicationSupportRoot: URL) -> URL {
        applicationSupportRoot
            .appendingPathComponent("Open Wallpaper Engine", isDirectory: true)
            .appendingPathComponent("Steam", isDirectory: true)
    }

    static func legacySteamCMDDirectory(in applicationSupportRoot: URL) -> URL {
        legacyApplicationSupportDirectory(in: applicationSupportRoot)
            .appendingPathComponent("SteamCMD", isDirectory: true)
    }

    static var legacyAppPrivateDefault: SteamCMDPaths {
        SteamCMDPaths(applicationSupportDirectory: appPrivateApplicationSupportDirectory)
    }

    static var appPrivateDefault: SteamCMDPaths {
        SteamCMDPathResolver.resolve().paths
    }

    var executableURL: URL {
        steamCMDDirectory.appendingPathComponent("steamcmd.sh")
    }

    var steamCMDExecutableURL: URL {
        steamCMDDirectory.appendingPathComponent("steamcmd")
    }

    var steamHomeDirectory: URL {
        steamCMDDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Steam", isDirectory: true)
    }

    var workshopContentDirectory: URL {
        steamHomeDirectory
            .appendingPathComponent("steamapps", isDirectory: true)
            .appendingPathComponent("workshop", isDirectory: true)
            .appendingPathComponent("content", isDirectory: true)
            .appendingPathComponent(SteamCMDDownloadCommand.wallpaperEngineAppID, isDirectory: true)
    }

    var legacyWorkshopContentDirectories: [URL] {
        [
            steamCMDDirectory
                .appendingPathComponent("steamapps", isDirectory: true)
                .appendingPathComponent("workshop", isDirectory: true)
                .appendingPathComponent("content", isDirectory: true)
                .appendingPathComponent(SteamCMDDownloadCommand.wallpaperEngineAppID, isDirectory: true)
        ]
    }

    func loginSessionCandidateURLs(fileManager: FileManager = .default) -> [URL] {
        var urls = [
            steamHomeDirectory.appendingPathComponent("config", isDirectory: true),
            steamHomeDirectory.appendingPathComponent("appcache", isDirectory: true),
            steamHomeDirectory.appendingPathComponent("userdata", isDirectory: true),
            steamCMDDirectory.appendingPathComponent("config", isDirectory: true),
            steamCMDDirectory.appendingPathComponent("appcache", isDirectory: true)
        ]
        for directory in [steamHomeDirectory, steamCMDDirectory] {
            if let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                urls += contents.filter { $0.lastPathComponent.lowercased().hasPrefix("ssfn") }
            }
        }
        return uniqueURLs(urls)
    }

    func loginSessionIndicatorURLs(fileManager: FileManager = .default) -> [URL] {
        var urls = [
            steamHomeDirectory
                .appendingPathComponent("config", isDirectory: true)
                .appendingPathComponent("config.vdf"),
            steamHomeDirectory
                .appendingPathComponent("config", isDirectory: true)
                .appendingPathComponent("loginusers.vdf"),
            steamCMDDirectory
                .appendingPathComponent("config", isDirectory: true)
                .appendingPathComponent("config.vdf"),
            steamCMDDirectory
                .appendingPathComponent("config", isDirectory: true)
                .appendingPathComponent("loginusers.vdf")
        ]
        for directory in [steamHomeDirectory, steamCMDDirectory] {
            if let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                urls += contents.filter { $0.lastPathComponent.lowercased().hasPrefix("ssfn") }
            }
        }
        return uniqueURLs(urls)
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}

enum SteamCMDRuntimeBookmarkStore {
    static let defaultsKey = "SteamCMDRuntimeDirectoryBookmark"

    static func currentSelection(userDefaults: UserDefaults = .standard) -> SteamCMDRuntimeSelection {
        currentSelection(
            resolveBookmark: {
                try resolveRuntimeDirectoryBookmark(userDefaults: userDefaults)
            },
            refreshBookmark: { url in
                try saveRuntimeDirectory(url, userDefaults: userDefaults)
            }
        )
    }

    static func currentSelection(
        resolveBookmark: () throws -> SteamCMDRuntimeBookmarkResolution?,
        refreshBookmark: (URL) throws -> Void
    ) -> SteamCMDRuntimeSelection {
        do {
            guard let resolution = try resolveBookmark() else {
                return .missing
            }
            if resolution.isStale {
                try? refreshBookmark(resolution.url)
            }
            return .selected(resolution.url)
        } catch let issue as SteamCMDRuntimeAuthorizationIssue {
            return .unavailable(issue)
        } catch {
            return .unavailable(.runtimeDirectoryBookmarkInvalid(error.localizedDescription))
        }
    }

    static func saveRuntimeDirectory(_ url: URL, userDefaults: UserDefaults = .standard) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        userDefaults.set(bookmark, forKey: defaultsKey)
    }

    static func clearRuntimeDirectory(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: defaultsKey)
    }

    static func resolveRuntimeDirectory(userDefaults: UserDefaults = .standard) throws -> URL? {
        try resolveRuntimeDirectoryBookmark(userDefaults: userDefaults)?.url
    }

    static func resolveRuntimeDirectoryBookmark(userDefaults: UserDefaults = .standard) throws -> SteamCMDRuntimeBookmarkResolution? {
        guard let bookmark = userDefaults.data(forKey: defaultsKey) else {
            return nil
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return SteamCMDRuntimeBookmarkResolution(url: url, isStale: isStale)
    }
}

struct SteamCMDPathResolution: Equatable {
    var paths: SteamCMDPaths
    var source: SteamCMDPathSource
    var legacyPaths: [SteamCMDPaths]
    var authorizationIssue: SteamCMDRuntimeAuthorizationIssue?

    var workshopContentDirectories: [URL] {
        uniquePaths(([paths] + legacyPaths).flatMap { [$0.workshopContentDirectory] + $0.legacyWorkshopContentDirectories })
    }

    func loginSessionCandidateURLs(fileManager: FileManager = .default) -> [URL] {
        uniquePaths([paths] + legacyPaths).flatMap {
            $0.loginSessionCandidateURLs(fileManager: fileManager)
        }
    }

    func loginSessionIndicatorURLs(fileManager: FileManager = .default) -> [URL] {
        uniquePaths([paths] + legacyPaths).flatMap {
            $0.loginSessionIndicatorURLs(fileManager: fileManager)
        }
    }

    private func uniquePaths(_ paths: [SteamCMDPaths]) -> [SteamCMDPaths] {
        var seen = Set<String>()
        return paths.filter { path in
            seen.insert(path.steamCMDDirectory.standardizedFileURL.path).inserted
        }
    }

    private func uniquePaths(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}

enum SteamCMDPathResolver {
    static let environmentKey = "OWE_STEAMCMD_DIR"

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sourceFilePath: String = #filePath,
        applicationSupportDirectory: URL = SteamCMDPaths.appPrivateApplicationSupportRoot,
        runtimeSelection: SteamCMDRuntimeSelection = SteamCMDRuntimeBookmarkStore.currentSelection(),
        isWritableDirectory: (URL) -> Bool = SteamCMDPathResolver.defaultIsWritableDirectory
    ) -> SteamCMDPathResolution {
        let managedRuntimePath = SteamCMDPaths(
            steamCMDDirectory: SteamCMDPaths.managedRuntimeDirectory(in: applicationSupportDirectory)
        )
        let containerRuntimePath = SteamCMDPaths(steamCMDDirectory: SteamCMDPaths.v2RuntimeDirectory(in: applicationSupportDirectory))
        let legacyContainerPath =
            SteamCMDPaths(steamCMDDirectory: SteamCMDPaths.legacySteamCMDDirectory(in: applicationSupportDirectory))

        var legacyCandidates = [containerRuntimePath, legacyContainerPath]
        if case .selected(let runtimeDirectory) = runtimeSelection {
            legacyCandidates.insert(SteamCMDPaths(userSelectedRuntimeDirectory: runtimeDirectory), at: 0)
        }

        func legacyPaths(excluding active: SteamCMDPaths) -> [SteamCMDPaths] {
            legacyCandidates.filter {
                $0.steamCMDDirectory.standardizedFileURL.path != active.steamCMDDirectory.standardizedFileURL.path
            }
        }

        if let override = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let active = SteamCMDPaths(steamCMDDirectory: directoryURL(from: override))
            return SteamCMDPathResolution(
                paths: active,
                source: .environmentOverride,
                legacyPaths: legacyPaths(excluding: active)
            )
        }

        return SteamCMDPathResolution(
            paths: managedRuntimePath,
            source: .managedRuntime,
            legacyPaths: legacyPaths(excluding: managedRuntimePath)
        )
    }

    static func defaultIsWritableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return FileManager.default.isWritableFile(atPath: url.path)
        }
        return FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
    }

    private static func directoryURL(from path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
    }

    private static func sourceProjectRoot(containing sourceFilePath: String) -> URL? {
        var current = URL(fileURLWithPath: sourceFilePath).deletingLastPathComponent()
        while current.path != "/" {
            if FileManager.default.fileExists(
                atPath: current.appendingPathComponent("Open Wallpaper Engine.xcodeproj", isDirectory: true).path
            ) {
                return current
            }
            current.deleteLastPathComponent()
        }
        return nil
    }
}

enum SteamCMDError: LocalizedError {
    case installFailed(recentOutput: [String])
    case commandFailed(status: Int32, recentOutput: [String])
    case steamGuardRequired(recentOutput: [String])
    case loginFailed(recentOutput: [String])
    case downloadFailed(itemID: String?, recentOutput: [String])

    var errorDescription: String? {
        switch self {
        case .installFailed(let recentOutput):
            return Self.message(
                base: "SteamCMD could not be installed.",
                recentOutput: recentOutput
            )
        case .commandFailed(let status, let recentOutput):
            return Self.message(
                base: "SteamCMD exited with status \(status).",
                recentOutput: recentOutput
            )
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
        case .downloadFailed(let itemID, let recentOutput):
            let base = itemID.map { "SteamCMD download failed for item \($0)." } ?? "SteamCMD download failed."
            return Self.message(base: base, recentOutput: recentOutput)
        }
    }

    private static func message(base: String, recentOutput: [String]) -> String {
        let trimmedOutput = recentOutput
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(6)
            .joined(separator: " | ")
        if trimmedOutput.isEmpty {
            return base
        }
        return "\(base) Recent output: \(trimmedOutput)"
    }
}

protocol SteamCMDProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?,
        output: @escaping (String) -> Void
    ) async throws -> Int32
}

protocol SteamCMDSecurityScopedAccessing {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

struct DefaultSteamCMDSecurityScopedAccess: SteamCMDSecurityScopedAccessing {
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

private final class RecentProcessOutput {
    private let limit: Int
    private let lock = NSLock()
    private var storage = [String]()

    init(limit: Int = 12) {
        self.limit = limit
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(line)
        if storage.count > limit {
            storage.removeFirst(storage.count - limit)
        }
    }
}

struct DefaultSteamCMDProcessRunner: SteamCMDProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL?,
        environment: [String: String]?,
        output: @escaping (String) -> Void
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let standardOutput = Pipe()
                let standardError = Pipe()

                process.executableURL = executableURL
                process.arguments = arguments
                process.currentDirectoryURL = currentDirectoryURL
                process.environment = environment
                process.standardOutput = standardOutput
                process.standardError = standardError

                let handler: (FileHandle) -> Void = { fileHandle in
                    let data = fileHandle.availableData
                    guard !data.isEmpty,
                          let chunk = String(data: data, encoding: .utf8) else {
                        return
                    }
                    chunk.split(whereSeparator: \.isNewline).map(String.init).forEach(output)
                }

                standardOutput.fileHandleForReading.readabilityHandler = handler
                standardError.fileHandleForReading.readabilityHandler = handler

                do {
                    try process.run()
                    process.waitUntilExit()
                    standardOutput.fileHandleForReading.readabilityHandler = nil
                    standardError.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    standardOutput.fileHandleForReading.readabilityHandler = nil
                    standardError.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private actor SteamCMDInstallCoordinator {
    private var tasks = [String: Task<Void, Error>]()

    func install(key: String, operation: @escaping () async throws -> Void) async throws {
        if let existingTask = tasks[key] {
            try await existingTask.value
            return
        }

        let task = Task {
            try await operation()
        }
        tasks[key] = task

        do {
            try await task.value
            tasks[key] = nil
        } catch {
            tasks[key] = nil
            throw error
        }
    }
}

struct SteamCMDRunnerResult: Equatable {
    var runtimeURL: URL
    var downloadedItemURL: URL?
    var recentOutput: [String]
}

struct SteamCMDDiagnostics: Equatable {
    var runtimeURL: URL
    var source: SteamCMDPathSource
    var executableURL: URL
    var cwd: URL
    var home: URL
    var temporaryDirectory: URL
    var isUsingXPCClient: Bool
    var legacyWorkshopDirectories: [URL]
}

protocol SteamCMDClient {
    var paths: SteamCMDPaths { get }

    func installIfMissing(progress: @escaping (SteamCMDInstallState) -> Void) async throws -> SteamCMDRunnerResult
    func repairRuntime(progress: @escaping (SteamCMDInstallState) -> Void) async throws -> SteamCMDRunnerResult
    func downloadItem(
        itemID: String,
        login: SteamCMDLogin,
        output: @escaping (SteamCMDOutputEvent) -> Void
    ) async throws -> SteamCMDRunnerResult
    func clearLoginSession() async throws
    func diagnostics() async -> SteamCMDDiagnostics
}

struct SteamCMDRunnerCore {
    static let installArchiveURL = URL(string: "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz")!
    static let installShellCommand = "curl -sqL \"\(installArchiveURL.absoluteString)\" | tar zxvf - && chmod 755 steamcmd steamcmd.sh"
    private static let installShellExecutableURL = URL(fileURLWithPath: "/bin/sh")
    private static let tarExecutableURL = URL(fileURLWithPath: "/usr/bin/tar")
    private static let quarantineAttributeName = "com.apple.quarantine"
    private static let steamCMDMagicRestartExitCode: Int32 = 42
    private static let maxSteamCMDLaunchAttempts = 4

    var paths: SteamCMDPaths
    var processRunner: SteamCMDProcessRunning
    var fileManager: FileManager

    init(
        paths: SteamCMDPaths,
        processRunner: SteamCMDProcessRunning = DefaultSteamCMDProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.processRunner = processRunner
        self.fileManager = fileManager
    }

    func installIfMissing(progress: @escaping (SteamCMDInstallState) -> Void = { _ in }) async throws -> SteamCMDRunnerResult {
        progress(.checking)
        try prepareSteamCMDProcessDirectories()
        try makeInstalledSteamCMDFilesExecutable()
        if isSteamCMDExecutablePairReady {
            progress(.installed(paths.executableURL))
            return SteamCMDRunnerResult(runtimeURL: paths.steamCMDDirectory, downloadedItemURL: nil, recentOutput: [])
        }

        let output = try await installFreshSteamCMD(progress: progress)
        progress(.installed(paths.executableURL))
        return SteamCMDRunnerResult(runtimeURL: paths.steamCMDDirectory, downloadedItemURL: nil, recentOutput: output)
    }

    func repairRuntime(progress: @escaping (SteamCMDInstallState) -> Void = { _ in }) async throws -> SteamCMDRunnerResult {
        progress(.checking)
        try prepareSteamCMDProcessDirectories()
        try makeInstalledSteamCMDFilesExecutable()
        guard isSteamCMDExecutablePairReady else {
            let recentOutput = RecentProcessOutput()
            appendExecutableValidationFailures(to: recentOutput)
            throw SteamCMDError.installFailed(recentOutput: recentOutput.lines)
        }
        let recentOutput = RecentProcessOutput()
        try repairQuarantineUnderRuntime()
        try await validateInstalledSteamCMD(recentOutput: recentOutput)
        progress(.installed(paths.executableURL))
        return SteamCMDRunnerResult(runtimeURL: paths.steamCMDDirectory, downloadedItemURL: nil, recentOutput: recentOutput.lines)
    }

    func installIfNeeded(progress: @escaping (SteamCMDInstallState) -> Void = { _ in }) async throws -> SteamCMDRunnerResult {
        try await installIfMissing(progress: progress)
    }

    private func installFreshSteamCMD(progress: @escaping (SteamCMDInstallState) -> Void) async throws -> [String] {
        try prepareSteamCMDProcessDirectories()

        progress(.downloading)
        progress(.extracting)
        let recentOutput = RecentProcessOutput()
        let status: Int32
        do {
            status = try await processRunner.run(
                executableURL: Self.installShellExecutableURL,
                arguments: ["-c", Self.installShellCommand],
                currentDirectoryURL: paths.steamCMDDirectory,
                environment: try steamCMDProcessEnvironment(),
                output: recentOutput.append
            )
        } catch {
            recentOutput.append("Failed to launch SteamCMD installer: \(error.localizedDescription)")
            throw SteamCMDError.installFailed(recentOutput: recentOutput.lines)
        }
        if status != 0 {
            recentOutput.append("Install command exited with status \(status).")
        }
        try makeInstalledSteamCMDFilesExecutable()
        if status != 0 || !isSteamCMDExecutablePairReady {
            if status == 0 {
                appendExecutableValidationFailures(to: recentOutput)
            }
            if try await recoverFromLegacyInstallArchiveIfPossible(recentOutput: recentOutput) {
                try repairQuarantineUnderRuntime()
                try await validateInstalledSteamCMD(recentOutput: recentOutput)
                return recentOutput.lines
            }
            removePartialExecutablePair()
            throw SteamCMDError.installFailed(recentOutput: recentOutput.lines)
        }

        try repairQuarantineUnderRuntime()
        try await validateInstalledSteamCMD(recentOutput: recentOutput)
        return recentOutput.lines
    }

    private var isSteamCMDExecutablePairReady: Bool {
        hasExecutablePermission(at: paths.executableURL)
            && hasExecutablePermission(at: paths.steamCMDExecutableURL)
    }

    private func makeInstalledSteamCMDFilesExecutable() throws {
        for url in [paths.executableURL, paths.steamCMDExecutableURL] where fileManager.fileExists(atPath: url.path) {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    private func hasExecutablePermission(at url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return false
        }
        return permissions.intValue & 0o111 != 0
    }

    private var legacyInstallArchiveURL: URL {
        paths.steamCMDDirectory.appendingPathComponent("steamcmd_osx.tar.gz")
    }

    private var steamCMDTemporaryDirectory: URL {
        paths.steamCMDDirectory.appendingPathComponent("tmp", isDirectory: true)
    }

    private var steamCMDHomeApplicationSupportDirectory: URL {
        paths.steamHomeDirectory
    }

    private func prepareSteamCMDProcessDirectories() throws {
        try fileManager.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: steamCMDTemporaryDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: steamCMDHomeApplicationSupportDirectory, withIntermediateDirectories: true)
    }

    private func steamCMDProcessEnvironment() throws -> [String: String] {
        try prepareSteamCMDProcessDirectories()
        var environment = ProcessInfo.processInfo.environment
        if environment["PATH"]?.isEmpty != false {
            environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        }
        environment["HOME"] = paths.steamHomeDirectory.path
        environment["TMPDIR"] = steamCMDTemporaryDirectory.path
        environment["STEAMCMD_HOME"] = paths.steamHomeDirectory.path
        environment["DYLD_LIBRARY_PATH"] = prependingSteamCMDDirectory(to: environment["DYLD_LIBRARY_PATH"])
        environment["DYLD_FRAMEWORK_PATH"] = prependingSteamCMDDirectory(to: environment["DYLD_FRAMEWORK_PATH"])
        return environment
    }

    private func prependingSteamCMDDirectory(to existingValue: String?) -> String {
        guard let existingValue, !existingValue.isEmpty else {
            return paths.steamCMDDirectory.path
        }
        return "\(paths.steamCMDDirectory.path):\(existingValue)"
    }

    private func appendExecutableValidationFailures(to recentOutput: RecentProcessOutput) {
        for url in [paths.executableURL, paths.steamCMDExecutableURL] {
            if !fileManager.fileExists(atPath: url.path) {
                recentOutput.append("Missing \(url.lastPathComponent).")
            } else if !hasExecutablePermission(at: url) {
                recentOutput.append("\(url.lastPathComponent) is not executable.")
            }
        }
    }

    private func recoverFromLegacyInstallArchiveIfPossible(recentOutput: RecentProcessOutput) async throws -> Bool {
        guard fileManager.fileExists(atPath: legacyInstallArchiveURL.path) else {
            return false
        }
        recentOutput.append("Retrying from existing steamcmd_osx.tar.gz.")
        let status = try await processRunner.run(
            executableURL: Self.tarExecutableURL,
            arguments: ["zxvf", legacyInstallArchiveURL.lastPathComponent],
            currentDirectoryURL: paths.steamCMDDirectory,
            environment: try steamCMDProcessEnvironment(),
            output: recentOutput.append
        )
        if status != 0 {
            recentOutput.append("Existing archive extraction exited with status \(status).")
            return false
        }
        try makeInstalledSteamCMDFilesExecutable()
        if isSteamCMDExecutablePairReady {
            return true
        }
        appendExecutableValidationFailures(to: recentOutput)
        return false
    }

    private func validateInstalledSteamCMD(recentOutput: RecentProcessOutput = RecentProcessOutput()) async throws {
        let status = try await runSteamCMD(
            arguments: ["+quit"],
            recentOutput: recentOutput,
            output: recentOutput.append
        )
        if status != 0 {
            recentOutput.append("SteamCMD readiness check exited with status \(status).")
            throw SteamCMDError.installFailed(recentOutput: recentOutput.lines)
        }
    }

    private func runSteamCMD(
        arguments: [String],
        recentOutput: RecentProcessOutput,
        output: @escaping (String) -> Void
    ) async throws -> Int32 {
        var launchAttempt = 0
        while launchAttempt < Self.maxSteamCMDLaunchAttempts {
            launchAttempt += 1
            let status: Int32
            do {
                status = try await processRunner.run(
                    executableURL: paths.steamCMDExecutableURL,
                    arguments: arguments,
                    currentDirectoryURL: paths.steamCMDDirectory,
                    environment: try steamCMDProcessEnvironment(),
                    output: output
                )
            } catch {
                recentOutput.append("Failed to launch SteamCMD: \(error.localizedDescription)")
                throw SteamCMDError.commandFailed(status: -1, recentOutput: recentOutput.lines)
            }
            if status == Self.steamCMDMagicRestartExitCode,
               launchAttempt < Self.maxSteamCMDLaunchAttempts {
                recentOutput.append("SteamCMD requested restart after self-update.")
                continue
            }
            return status
        }
        return Self.steamCMDMagicRestartExitCode
    }

    private func validateInstalledSteamCMDIsNotQuarantined() throws {
        let quarantinedNames = quarantinedURLsUnderRuntime()
            .map { relativeRuntimePath(for: $0) }
            .sorted()
        guard quarantinedNames.isEmpty else {
            throw SteamCMDError.installFailed(recentOutput: [
                "Sandbox created quarantined SteamCMD files even in clean runtime path: \(quarantinedNames.joined(separator: ", "))."
            ])
        }
    }

    private func repairQuarantineUnderRuntime() throws {
        for url in quarantinedURLsUnderRuntime() {
            do {
                try Self.removeQuarantineAttribute(at: url)
            } catch {
                throw SteamCMDError.installFailed(recentOutput: [
                    "Could not remove quarantine from SteamCMD file \(relativeRuntimePath(for: url)): \(error.localizedDescription)"
                ])
            }
        }
        try validateInstalledSteamCMDIsNotQuarantined()
    }

    private func quarantinedURLsUnderRuntime() -> [URL] {
        var urls = [URL]()
        if fileManager.fileExists(atPath: paths.steamCMDDirectory.path),
           Self.hasQuarantineAttribute(at: paths.steamCMDDirectory) {
            urls.append(paths.steamCMDDirectory)
        }
        guard let enumerator = fileManager.enumerator(
            at: paths.steamCMDDirectory,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: nil
        ) else {
            return urls
        }
        for case let url as URL in enumerator where Self.hasQuarantineAttribute(at: url) {
            urls.append(url)
        }
        return urls
    }

    private func relativeRuntimePath(for url: URL) -> String {
        let runtimePath = paths.steamCMDDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == runtimePath {
            return paths.steamCMDDirectory.lastPathComponent
        }
        if path.hasPrefix(runtimePath + "/") {
            return String(path.dropFirst(runtimePath.count + 1))
        }
        return url.lastPathComponent
    }

    private static func hasQuarantineAttribute(at url: URL) -> Bool {
        let result = url.path.withCString { path in
            getxattr(path, quarantineAttributeName, nil, 0, 0, 0)
        }
        return result >= 0
    }

    private static func removeQuarantineAttribute(at url: URL) throws {
        let result = url.path.withCString { path in
            removexattr(path, quarantineAttributeName, 0)
        }
        guard result == 0 || errno == ENOATTR else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func removePartialExecutablePair() {
        for url in [paths.executableURL, paths.steamCMDExecutableURL] where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    func downloadItem(
        itemID: String,
        login: SteamCMDLogin,
        output: @escaping (SteamCMDOutputEvent) -> Void
    ) async throws -> SteamCMDRunnerResult {
        _ = try await installIfMissing()
        let command = SteamCMDDownloadCommand(itemID: itemID, login: login)
        let recentOutput = RecentProcessOutput()
        var parser = SteamCMDOutputStreamParser()
        var downloadedItemURL: URL?
        var failedItemID: String?
        var sawSteamGuardRequired = false
        var sawLoginFailure = false
        let status = try await runSteamCMD(
            arguments: command.arguments,
            recentOutput: recentOutput
        ) { line in
            recentOutput.append(line)
            if let directory = SteamCMDOutputParser.downloadedItemDirectory(from: line) {
                downloadedItemURL = directory
            }
            if let itemID = SteamCMDOutputParser.failedItemID(from: line) {
                failedItemID = itemID
            }
            if let event = parser.event(from: line) {
                switch event {
                case .steamGuardRequired:
                    sawSteamGuardRequired = true
                case .loginFailed:
                    sawLoginFailure = true
                case .loginSucceeded, .downloadSucceeded, .downloadFailed:
                    break
                }
                output(event)
            }
        }

        if downloadedItemURL == nil {
            if sawSteamGuardRequired {
                throw SteamCMDError.steamGuardRequired(recentOutput: recentOutput.lines)
            }
            if sawLoginFailure {
                throw SteamCMDError.loginFailed(recentOutput: recentOutput.lines)
            }
        }

        if let failedItemID {
            throw SteamCMDError.downloadFailed(itemID: failedItemID, recentOutput: recentOutput.lines)
        }

        guard status == 0 else {
            throw SteamCMDError.commandFailed(status: status, recentOutput: recentOutput.lines)
        }

        return SteamCMDRunnerResult(
            runtimeURL: paths.steamCMDDirectory,
            downloadedItemURL: downloadedItemURL ?? paths.workshopContentDirectory.appendingPathComponent(itemID, isDirectory: true),
            recentOutput: recentOutput.lines
        )
    }

    func clearLoginSession(legacyPaths: [SteamCMDPaths] = []) throws {
        for url in ([paths] + legacyPaths).flatMap({ $0.loginSessionCandidateURLs(fileManager: fileManager) }) {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    func diagnostics(source: SteamCMDPathSource, legacyPaths: [SteamCMDPaths], isUsingXPCClient: Bool) async -> SteamCMDDiagnostics {
        SteamCMDDiagnostics(
            runtimeURL: paths.steamCMDDirectory,
            source: source,
            executableURL: paths.executableURL,
            cwd: paths.steamCMDDirectory,
            home: paths.steamHomeDirectory,
            temporaryDirectory: steamCMDTemporaryDirectory,
            isUsingXPCClient: isUsingXPCClient,
            legacyWorkshopDirectories: legacyPaths.flatMap { [$0.workshopContentDirectory] + $0.legacyWorkshopContentDirectories }
        )
    }
}

@objc(SteamCMDRunnerXPCProtocol)
protocol SteamCMDRunnerXPCProtocol {
    func install(runtimePath: String, reply: @escaping (NSDictionary) -> Void)
    func repair(runtimePath: String, reply: @escaping (NSDictionary) -> Void)
    func download(runtimePath: String, itemID: String, login: NSDictionary, reply: @escaping (NSDictionary) -> Void)
    func clearSession(runtimePath: String, legacyRuntimePaths: [String], reply: @escaping (NSDictionary) -> Void)
    func diagnostics(runtimePath: String, source: String, legacyRuntimePaths: [String], reply: @escaping (NSDictionary) -> Void)
}

enum SteamCMDRunnerXPCPayload {
    static func loginPayload(_ login: SteamCMDLogin) -> NSDictionary {
        switch login {
        case .anonymous:
            return ["kind": "anonymous"]
        case .savedSession(let username):
            return [
                "kind": "savedSession",
                "username": username
            ]
        case .account(let username, let password, let steamGuardCode):
            var payload: [String: Any] = [
                "kind": "account",
                "username": username,
                "password": password
            ]
            if let steamGuardCode {
                payload["steamGuardCode"] = steamGuardCode
            }
            return payload as NSDictionary
        }
    }

    static func login(from payload: NSDictionary) -> SteamCMDLogin {
        switch payload["kind"] as? String {
        case "account":
            return .account(
                username: payload["username"] as? String ?? "",
                password: payload["password"] as? String ?? "",
                steamGuardCode: payload["steamGuardCode"] as? String
            )
        case "savedSession":
            return .savedSession(username: payload["username"] as? String ?? "")
        default:
            return .anonymous
        }
    }

    static func success(_ result: SteamCMDRunnerResult) -> NSDictionary {
        var payload: [String: Any] = [
            "ok": true,
            "runtimePath": result.runtimeURL.path,
            "recentOutput": result.recentOutput
        ]
        if let downloadedItemURL = result.downloadedItemURL {
            payload["downloadedItemPath"] = downloadedItemURL.path
        }
        return payload as NSDictionary
    }

    static func success(_ diagnostics: SteamCMDDiagnostics) -> NSDictionary {
        [
            "ok": true,
            "runtimePath": diagnostics.runtimeURL.path,
            "source": diagnostics.source.label,
            "executablePath": diagnostics.executableURL.path,
            "cwd": diagnostics.cwd.path,
            "home": diagnostics.home.path,
            "tmpdir": diagnostics.temporaryDirectory.path,
            "isUsingXPCClient": diagnostics.isUsingXPCClient,
            "legacyWorkshopDirectories": diagnostics.legacyWorkshopDirectories.map(\.path)
        ] as NSDictionary
    }

    static func failure(_ error: Error) -> NSDictionary {
        var payload: [String: Any] = [
            "ok": false,
            "message": error.localizedDescription
        ]
        if let steamCMDError = error as? SteamCMDError {
            switch steamCMDError {
            case .installFailed(let recentOutput):
                payload["errorKind"] = "installFailed"
                payload["recentOutput"] = recentOutput
            case .commandFailed(let status, let recentOutput):
                payload["errorKind"] = "commandFailed"
                payload["status"] = status
                payload["recentOutput"] = recentOutput
            case .steamGuardRequired(let recentOutput):
                payload["errorKind"] = "steamGuardRequired"
                payload["recentOutput"] = recentOutput
            case .loginFailed(let recentOutput):
                payload["errorKind"] = "loginFailed"
                payload["recentOutput"] = recentOutput
            case .downloadFailed(let itemID, let recentOutput):
                payload["errorKind"] = "downloadFailed"
                payload["itemID"] = itemID
                payload["recentOutput"] = recentOutput
            }
        } else {
            payload["errorKind"] = "unknown"
            payload["recentOutput"] = [error.localizedDescription]
        }
        return payload as NSDictionary
    }

    static func result(from payload: NSDictionary) throws -> SteamCMDRunnerResult {
        if payload["ok"] as? Bool == true {
            let runtimePath = payload["runtimePath"] as? String ?? ""
            let downloadedItemPath = payload["downloadedItemPath"] as? String
            return SteamCMDRunnerResult(
                runtimeURL: URL(fileURLWithPath: runtimePath, isDirectory: true),
                downloadedItemURL: downloadedItemPath.map { URL(fileURLWithPath: $0, isDirectory: true) },
                recentOutput: payload["recentOutput"] as? [String] ?? []
            )
        }
        throw error(from: payload)
    }

    static func error(from payload: NSDictionary) -> Error {
        let recentOutput = payload["recentOutput"] as? [String] ?? [payload["message"] as? String].compactMap { $0 }
        if payload["errorKind"] as? String == "commandFailed" {
            return SteamCMDError.commandFailed(
                status: (payload["status"] as? NSNumber)?.int32Value ?? -1,
                recentOutput: recentOutput
            )
        }
        if payload["errorKind"] as? String == "steamGuardRequired" {
            return SteamCMDError.steamGuardRequired(recentOutput: recentOutput)
        }
        if payload["errorKind"] as? String == "loginFailed" {
            return SteamCMDError.loginFailed(recentOutput: recentOutput)
        }
        if payload["errorKind"] as? String == "downloadFailed" {
            return SteamCMDError.downloadFailed(
                itemID: payload["itemID"] as? String,
                recentOutput: recentOutput
            )
        }
        return SteamCMDError.installFailed(recentOutput: recentOutput)
    }
}

struct LocalSteamCMDClient: SteamCMDClient {
    var resolution: SteamCMDPathResolution
    var core: SteamCMDRunnerCore

    var paths: SteamCMDPaths { core.paths }

    init(
        resolution: SteamCMDPathResolution,
        processRunner: SteamCMDProcessRunning = DefaultSteamCMDProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.resolution = resolution
        self.core = SteamCMDRunnerCore(
            paths: resolution.paths,
            processRunner: processRunner,
            fileManager: fileManager
        )
    }

    init(
        paths: SteamCMDPaths,
        processRunner: SteamCMDProcessRunning = DefaultSteamCMDProcessRunner(),
        fileManager: FileManager = .default
    ) {
        self.init(
            resolution: SteamCMDPathResolution(paths: paths, source: .managedRuntime, legacyPaths: []),
            processRunner: processRunner,
            fileManager: fileManager
        )
    }

    func installIfMissing(progress: @escaping (SteamCMDInstallState) -> Void) async throws -> SteamCMDRunnerResult {
        try await core.installIfMissing(progress: progress)
    }

    func repairRuntime(progress: @escaping (SteamCMDInstallState) -> Void) async throws -> SteamCMDRunnerResult {
        try await core.repairRuntime(progress: progress)
    }

    func downloadItem(
        itemID: String,
        login: SteamCMDLogin,
        output: @escaping (SteamCMDOutputEvent) -> Void
    ) async throws -> SteamCMDRunnerResult {
        try await core.downloadItem(itemID: itemID, login: login, output: output)
    }

    func diagnostics() async -> SteamCMDDiagnostics {
        await core.diagnostics(
            source: resolution.source,
            legacyPaths: resolution.legacyPaths,
            isUsingXPCClient: false
        )
    }

    func clearLoginSession() async throws {
        try core.clearLoginSession(legacyPaths: resolution.legacyPaths)
    }
}

struct XPCSteamCMDClient: SteamCMDClient {
    static let serviceName = "com.haren724.open-wallpaper-engine.steamcmd-runner"

    var resolution: SteamCMDPathResolution
    var paths: SteamCMDPaths { resolution.paths }

    func installIfMissing(progress: @escaping (SteamCMDInstallState) -> Void) async throws -> SteamCMDRunnerResult {
        progress(.checking)
        let result = try await withRemoteProxy { proxy, reply in
            proxy.install(runtimePath: paths.steamCMDDirectory.path, reply: reply)
        }
        progress(.installed(paths.executableURL))
        return result
    }

    func repairRuntime(progress: @escaping (SteamCMDInstallState) -> Void) async throws -> SteamCMDRunnerResult {
        progress(.checking)
        let result = try await withRemoteProxy { proxy, reply in
            proxy.repair(runtimePath: paths.steamCMDDirectory.path, reply: reply)
        }
        progress(.installed(paths.executableURL))
        return result
    }

    func downloadItem(
        itemID: String,
        login: SteamCMDLogin,
        output: @escaping (SteamCMDOutputEvent) -> Void
    ) async throws -> SteamCMDRunnerResult {
        let result = try await withRemoteProxy { proxy, reply in
            proxy.download(
                runtimePath: paths.steamCMDDirectory.path,
                itemID: itemID,
                login: SteamCMDRunnerXPCPayload.loginPayload(login),
                reply: reply
            )
        }
        var parser = SteamCMDOutputStreamParser()
        result.recentOutput.compactMap { parser.event(from: $0) }.forEach(output)
        return result
    }

    func clearLoginSession() async throws {
        _ = try await withRemoteProxy { proxy, reply in
            proxy.clearSession(
                runtimePath: paths.steamCMDDirectory.path,
                legacyRuntimePaths: resolution.legacyPaths.map(\.steamCMDDirectory.path),
                reply: reply
            )
        }
    }

    func diagnostics() async -> SteamCMDDiagnostics {
        SteamCMDDiagnostics(
            runtimeURL: paths.steamCMDDirectory,
            source: resolution.source,
            executableURL: paths.executableURL,
            cwd: paths.steamCMDDirectory,
            home: paths.steamHomeDirectory,
            temporaryDirectory: paths.steamCMDDirectory.appendingPathComponent("tmp", isDirectory: true),
            isUsingXPCClient: true,
            legacyWorkshopDirectories: resolution.legacyPaths.flatMap { [$0.workshopContentDirectory] + $0.legacyWorkshopContentDirectories }
        )
    }

    private func withRemoteProxy(
        _ body: @escaping (SteamCMDRunnerXPCProtocol, @escaping (NSDictionary) -> Void) -> Void
    ) async throws -> SteamCMDRunnerResult {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(serviceName: Self.serviceName)
            connection.remoteObjectInterface = NSXPCInterface(with: SteamCMDRunnerXPCProtocol.self)
            connection.resume()

            let finish: (Result<SteamCMDRunnerResult, Error>) -> Void = { result in
                connection.invalidate()
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                finish(.failure(SteamCMDError.installFailed(recentOutput: [
                    "SteamCMD runner XPC connection failed: \(error.localizedDescription)"
                ])))
            }) as? SteamCMDRunnerXPCProtocol else {
                finish(.failure(SteamCMDError.installFailed(recentOutput: [
                    "SteamCMD runner XPC proxy is unavailable."
                ])))
                return
            }

            body(proxy) { payload in
                do {
                    finish(.success(try SteamCMDRunnerXPCPayload.result(from: payload)))
                } catch {
                    finish(.failure(error))
                }
            }
        }
    }
}

struct SteamCMDService {
    static let installArchiveURL = SteamCMDRunnerCore.installArchiveURL
    static let installShellCommand = SteamCMDRunnerCore.installShellCommand

    private static let installCoordinator = SteamCMDInstallCoordinator()

    var resolution: SteamCMDPathResolution
    private var client: SteamCMDClient
    private var fileManager: FileManager

    var paths: SteamCMDPaths { client.paths }
    var additionalLoginSessionPaths: [URL] {
        resolution.legacyPaths.flatMap { $0.loginSessionCandidateURLs(fileManager: fileManager) }
    }

    init(
        resolution: SteamCMDPathResolution = SteamCMDPathResolver.resolve(),
        client: SteamCMDClient? = nil,
        fileManager: FileManager = .default
    ) {
        self.resolution = resolution
        self.client = client ?? XPCSteamCMDClient(resolution: resolution)
        self.fileManager = fileManager
    }

    init(
        resolution: SteamCMDPathResolution,
        processRunner: SteamCMDProcessRunning,
        securityScopedAccess: SteamCMDSecurityScopedAccessing = DefaultSteamCMDSecurityScopedAccess(),
        fileManager: FileManager = .default
    ) {
        self.init(
            resolution: resolution,
            client: LocalSteamCMDClient(
                resolution: resolution,
                processRunner: processRunner,
                fileManager: fileManager
            ),
            fileManager: fileManager
        )
    }

    init(
        paths: SteamCMDPaths,
        processRunner: SteamCMDProcessRunning = DefaultSteamCMDProcessRunner(),
        fileManager: FileManager = .default
    ) {
        let resolution = SteamCMDPathResolution(paths: paths, source: .managedRuntime, legacyPaths: [])
        self.init(
            resolution: resolution,
            client: LocalSteamCMDClient(paths: paths, processRunner: processRunner, fileManager: fileManager),
            fileManager: fileManager
        )
    }

    func installIfMissing(progress: @escaping (SteamCMDInstallState) -> Void = { _ in }) async throws {
        do {
            try await Self.installCoordinator.install(key: paths.steamCMDDirectory.path) {
                _ = try await client.installIfMissing(progress: progress)
            }
        } catch {
            progress(.failed(error.localizedDescription))
            throw error
        }
    }

    func repairRuntime(progress: @escaping (SteamCMDInstallState) -> Void = { _ in }) async throws {
        do {
            try await Self.installCoordinator.install(key: paths.steamCMDDirectory.path) {
                _ = try await client.repairRuntime(progress: progress)
            }
        } catch {
            progress(.failed(error.localizedDescription))
            throw error
        }
    }

    func installIfNeeded(progress: @escaping (SteamCMDInstallState) -> Void = { _ in }) async throws {
        try await installIfMissing(progress: progress)
    }

    func downloadItem(
        itemID: String,
        login: SteamCMDLogin,
        output: @escaping (SteamCMDOutputEvent) -> Void
    ) async throws -> URL {
        let result = try await client.downloadItem(itemID: itemID, login: login, output: output)
        return result.downloadedItemURL ?? paths.workshopContentDirectory.appendingPathComponent(itemID, isDirectory: true)
    }

    func clearLoginSession() async throws {
        try await client.clearLoginSession()
    }

    func hasSavedLoginSession() -> Bool {
        resolution.loginSessionIndicatorURLs(fileManager: fileManager).contains { url in
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                return false
            }

            let filename = url.lastPathComponent.lowercased()
            if filename.hasPrefix("ssfn") || filename == "loginusers.vdf" {
                return true
            }

            guard filename == "config.vdf",
                  let data = try? Data(contentsOf: url),
                  let contents = String(data: data, encoding: .utf8)?.lowercased() else {
                return false
            }
            return contents.contains("\"accounts\"")
        }
    }

    func resetRuntime() throws {
        if fileManager.fileExists(atPath: paths.steamCMDDirectory.path) {
            try fileManager.removeItem(at: paths.steamCMDDirectory)
        }
    }

    func diagnostics() async -> SteamCMDDiagnostics {
        await client.diagnostics()
    }
}

enum WallpaperLibraryService {
    static func scanInstalledWallpapers(documentDirectory: URL, workshopContentDirectory: URL) -> [WEWallpaper] {
        scanInstalledWallpapers(documentDirectory: documentDirectory, workshopContentDirectories: [workshopContentDirectory])
    }

    static func scanInstalledWallpapers(documentDirectory: URL, workshopContentDirectories: [URL]) -> [WEWallpaper] {
        let uniqueWorkshopDirectories = uniqueURLs(workshopContentDirectories)
        return scanDocumentWallpapers(at: documentDirectory)
            + uniqueWorkshopDirectories.flatMap { WorkshopLibraryService.scanDownloadedWallpapers(at: $0) }
    }

    private static func scanDocumentWallpapers(at documentDirectory: URL) -> [WEWallpaper] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: documentDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents.map { url in
            if let data = try? Data(contentsOf: url.appending(path: "project.json")),
               let project = try? JSONDecoder().decode(WEProject.self, from: data) {
                return WEWallpaper(using: project, where: url)
            }
            return WEWallpaper(using: .invalid, where: url)
        }
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }
}

struct KeychainCredentialKey: Hashable {
    let service: String
    let account: String
}

protocol KeychainCredentialBackend {
    func loadString(for key: KeychainCredentialKey) throws -> String?
    func saveString(_ string: String, for key: KeychainCredentialKey) throws
    func deleteString(for key: KeychainCredentialKey) throws
}

enum KeychainCredentialStoreError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

struct SystemKeychainCredentialBackend: KeychainCredentialBackend {
    func loadString(for key: KeychainCredentialKey) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.unhandledStatus(status)
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func saveString(_ string: String, for key: KeychainCredentialKey) throws {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = Data(string.utf8)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainCredentialStoreError.unhandledStatus(status)
        }
    }

    func deleteString(for key: KeychainCredentialKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainCredentialStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(for key: KeychainCredentialKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.service,
            kSecAttrAccount as String: key.account
        ]
    }
}

final class CachedKeychainCredentialStore {
    private enum CachedValue {
        case string(String)
        case missing

        var stringValue: String? {
            switch self {
            case .string(let string):
                return string
            case .missing:
                return nil
            }
        }
    }

    private let backend: KeychainCredentialBackend
    private let queue = DispatchQueue(label: "com.haren724.open-wallpaper-engine.keychain-credential-cache")
    private var cache = [KeychainCredentialKey: CachedValue]()

    init(backend: KeychainCredentialBackend = SystemKeychainCredentialBackend()) {
        self.backend = backend
    }

    func loadString(for key: KeychainCredentialKey) throws -> String? {
        try queue.sync {
            if let cachedValue = cache[key] {
                return cachedValue.stringValue
            }

            let string = try backend.loadString(for: key)
            if let string = string {
                cache[key] = .string(string)
            } else {
                cache[key] = .missing
            }
            return string
        }
    }

    func saveString(_ string: String, for key: KeychainCredentialKey) throws {
        try queue.sync {
            try backend.saveString(string, for: key)
            cache[key] = .string(string)
        }
    }

    func deleteString(for key: KeychainCredentialKey) throws {
        try queue.sync {
            try backend.deleteString(for: key)
            cache[key] = .missing
        }
    }
}

enum SteamWorkshopCredentialStore {
    private static let apiKey = KeychainCredentialKey(
        service: "com.haren724.open-wallpaper-engine.steam-workshop",
        account: "steam-web-api-key"
    )
    private static let credentialStore = CachedKeychainCredentialStore()

    typealias KeychainError = KeychainCredentialStoreError

    static func saveAPIKey(_ apiKey: String) throws {
        try credentialStore.saveString(apiKey, for: Self.apiKey)
    }

    static func loadAPIKey() throws -> String? {
        try credentialStore.loadString(for: Self.apiKey)
    }

    static func deleteAPIKey() throws {
        try credentialStore.deleteString(for: Self.apiKey)
    }
}

enum SteamWorkshopSupport {
    static let webAPIKeyURL = URL(string: "https://steamcommunity.com/dev/apikey")!
    static let wallpaperEngineWorkshopURL = URL(string: "https://steamcommunity.com/app/431960/workshop/")!

    static func workshopPageURL(itemID: String) -> URL {
        URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(itemID)")!
    }
}

enum SteamWorkshopDownloadInputError: LocalizedError {
    case invalidWorkshopID
    case missingUsername
    case missingPassword

    var errorDescription: String? {
        switch self {
        case .invalidWorkshopID:
            return "Enter a valid Steam Workshop URL or published file ID."
        case .missingUsername:
            return "Enter your Steam username to sign in to SteamCMD."
        case .missingPassword:
            return "Enter your Steam password to sign in to SteamCMD."
        }
    }
}

struct SteamWorkshopDownloadRequest: Equatable {
    let itemID: String
    let login: SteamCMDLogin
}

struct SteamWorkshopDownloadInput: Equatable {
    var itemInput: String
    var username: String
    var password: String
    var steamGuardCode: String

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
}
