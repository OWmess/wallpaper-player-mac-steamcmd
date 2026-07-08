//
//  Open_Wallpaper_EngineTests.swift
//  Open Wallpaper EngineTests
//
//  Created by Haren on 2023/6/5.
//

import Darwin
import XCTest
@testable import Open_Wallpaper_Engine

final class Open_Wallpaper_EngineTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    func testWorkshopIDParserAcceptsSteamWorkshopURLAndPlainID() {
        XCTAssertEqual(
            SteamWorkshopIDParser.publishedFileID(from: "https://steamcommunity.com/sharedfiles/filedetails/?id=3004222851"),
            "3004222851"
        )
        XCTAssertEqual(
            SteamWorkshopIDParser.publishedFileID(from: "steam://url/CommunityFilePage/3004222851"),
            "3004222851"
        )
        XCTAssertEqual(SteamWorkshopIDParser.publishedFileID(from: "3004222851"), "3004222851")
        XCTAssertNil(SteamWorkshopIDParser.publishedFileID(from: "https://example.com/no-workshop-id"))
    }

    func testWorkshopQueryFilesResponseDecodesPreviewTagsMetadataAndStats() throws {
        let json = """
        {
          "response": {
            "total": 1,
            "next_cursor": "AoIIPw==",
            "publishedfiledetails": [
              {
                "publishedfileid": "3004222851",
                "title": "City Rain",
                "file_description": "A rainy city wallpaper.",
                "creator": "76561198000000000",
                "preview_url": "https://cdn.example/preview.jpg",
                "time_created": 1700000000,
                "subscriptions": 42,
                "favorited": 7,
                "lifetime_favorited": 9,
                "score": 0.91,
                "metadata": "{\\"type\\":\\"video\\",\\"preview\\":\\"preview.gif\\"}",
                "tags": [
                  { "tag": "Video" },
                  { "tag": "Relaxing" }
                ],
                "previews": [
                  { "preview_type": 0, "url": "https://cdn.example/detail.jpg" }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SteamWorkshopQueryResponse.self, from: json)

        XCTAssertEqual(response.response.total, 1)
        XCTAssertEqual(response.response.nextCursor, "AoIIPw==")
        let item = try XCTUnwrap(response.response.items.first)
        XCTAssertEqual(item.id, "3004222851")
        XCTAssertEqual(item.title, "City Rain")
        XCTAssertEqual(item.previewURL, URL(string: "https://cdn.example/preview.jpg"))
        XCTAssertEqual(item.timeCreated, 1_700_000_000)
        XCTAssertEqual(item.tags, ["Video", "Relaxing"])
        XCTAssertEqual(item.metadata?.type, "video")
        XCTAssertEqual(item.stats.subscriptions, 42)
        XCTAssertTrue(item.isSupportedByCurrentPlayer)
    }

    func testWorkshopQueryFilesResponseAcceptsStringEncodedStats() throws {
        let json = """
        {
          "response": {
            "total": 1,
            "publishedfiledetails": [
              {
                "publishedfileid": "3004222851",
                "title": "City Rain",
                "subscriptions": "42",
                "favorited": "7",
                "lifetime_favorited": "9",
                "score": "0.91",
                "metadata": "{\\"type\\":\\"video\\"}",
                "tags": [
                  { "tag": "Video" }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SteamWorkshopQueryResponse.self, from: json)
        let item = try XCTUnwrap(response.response.items.first)

        XCTAssertEqual(item.stats.subscriptions, 42)
        XCTAssertEqual(item.stats.favorited, 7)
        XCTAssertEqual(item.stats.lifetimeFavorited, 9)
        XCTAssertEqual(item.stats.score, 0.91)
    }

    func testSteamCMDOutputParserRecognizesLoginDownloadAndGuardStates() {
        var parser = SteamCMDOutputStreamParser()
        XCTAssertNil(parser.event(from: "Waiting for user info..."))
        XCTAssertEqual(parser.event(from: "OK"), .loginSucceeded)
        XCTAssertEqual(
            parser.event(from: "Success. Downloaded item 3004222851 to \"/tmp/content/431960/3004222851\""),
            .downloadSucceeded(itemID: "3004222851")
        )
        XCTAssertEqual(
            parser.event(from: "ERROR! Download item 431960 failed (Failure)."),
            .downloadFailed
        )
        XCTAssertEqual(
            parser.event(from: "Steam Guard code:"),
            .steamGuardRequired
        )
        XCTAssertEqual(
            SteamCMDOutputParser.event(from: "Waiting for user info...OK"),
            .loginSucceeded
        )
    }

    func testWorkshopLibraryScannerReadsValidWallpaperProjects() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let itemDirectory = root
            .appendingPathComponent("431960", isDirectory: true)
            .appendingPathComponent("3004222851", isDirectory: true)
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        try """
        {
          "file": "rain.mp4",
          "preview": "preview.jpg",
          "title": "City Rain",
          "type": "video",
          "workshopid": "3004222851"
        }
        """.data(using: .utf8)!.write(to: itemDirectory.appendingPathComponent("project.json"))

        let wallpapers = WorkshopLibraryService.scanDownloadedWallpapers(at: root)

        XCTAssertEqual(wallpapers.count, 1)
        XCTAssertEqual(wallpapers.first?.project.title, "City Rain")
        XCTAssertEqual(
            wallpapers.first?.wallpaperDirectory.resolvingSymlinksInPath(),
            itemDirectory.resolvingSymlinksInPath()
        )
    }

    func testWorkshopQueryRequestUsesSteamAPIKeyAndInputJSON() throws {
        let request = try SteamWorkshopAPIService.makeQueryRequest(
            apiKey: "steam-api-key",
            query: SteamWorkshopQuery(
                sort: .popular,
                cursor: nil,
                pageSize: 24,
                requiredTag: "Video"
            )
        )
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let inputJSON = try XCTUnwrap(queryItems["input_json"])
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any]
        )

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.steampowered.com")
        XCTAssertEqual(queryItems["key"], "steam-api-key")
        XCTAssertEqual(payload["appid"] as? Int, 431960)
        XCTAssertEqual(payload["creator_appid"] as? Int, 431960)
        XCTAssertEqual(payload["numperpage"] as? Int, 24)
        XCTAssertEqual(payload["cursor"] as? String, "*")
        XCTAssertEqual(payload["requiredtags"] as? String, "Video")
        XCTAssertEqual(payload["match_all_tags"] as? Bool, true)
        XCTAssertEqual(payload["query_type"] as? Int, 9)
        XCTAssertEqual(payload["return_metadata"] as? Bool, true)
        XCTAssertEqual(payload["return_previews"] as? Bool, true)
        XCTAssertEqual(payload["return_tags"] as? Bool, true)
        XCTAssertEqual(payload["return_vote_data"] as? Bool, true)
    }

    func testWorkshopSortQueryTypesMatchSteamPublishedFileQueryTypeValues() {
        XCTAssertEqual(SteamWorkshopQuery.Sort.popular.queryType, 9)
        XCTAssertEqual(SteamWorkshopQuery.Sort.trending.queryType, 3)
        XCTAssertEqual(SteamWorkshopQuery.Sort.latest.queryType, 1)
        XCTAssertEqual(SteamWorkshopQuery.Sort.search.queryType, 12)
    }

    func testWorkshopTrendingRequestIncludesDefaultDays() throws {
        let request = try SteamWorkshopAPIService.makeQueryRequest(
            apiKey: "steam-api-key",
            query: SteamWorkshopQuery(sort: .trending, cursor: "cursor-2", pageSize: 100, requiredTag: "Web")
        )
        let inputJSON = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "input_json" })?
            .value)
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any]
        )

        XCTAssertEqual(payload["query_type"] as? Int, 3)
        XCTAssertEqual(payload["cursor"] as? String, "cursor-2")
        XCTAssertEqual(payload["requiredtags"] as? String, "Web")
        XCTAssertEqual(payload["days"] as? Int, 7)
    }

    func testWorkshopSearchRequestIncludesSearchTextAndQueryType() throws {
        let request = try SteamWorkshopAPIService.makeQueryRequest(
            apiKey: "steam-api-key",
            query: SteamWorkshopQuery(sort: .search, searchText: "city rain", cursor: "AoIIPw==", pageSize: 12)
        )
        let inputJSON = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "input_json" })?
            .value)
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any]
        )

        XCTAssertEqual(payload["query_type"] as? Int, 12)
        XCTAssertEqual(payload["search_text"] as? String, "city rain")
        XCTAssertEqual(payload["cursor"] as? String, "AoIIPw==")
    }

    @MainActor
    func testWorkshopBrowserRequestsVideoAndWebStreamsAndDeduplicatesResults() async throws {
        let httpClient = FakeSteamWorkshopHTTPClient(responses: [
            Self.workshopResponseJSON(
                nextCursor: nil,
                items: [
                    Self.workshopItemJSON(id: "1001", title: "Video One", type: "video"),
                    Self.workshopItemJSON(id: "1002", title: "Shared Item", type: "video")
                ]
            ),
            Self.workshopResponseJSON(
                nextCursor: nil,
                items: [
                    Self.workshopItemJSON(id: "2001", title: "Web One", type: "web"),
                    Self.workshopItemJSON(id: "1002", title: "Shared Item Duplicate", type: "web")
                ]
            )
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = SteamWorkshopBrowserViewModel(
            apiService: SteamWorkshopAPIService(httpClient: httpClient),
            steamCMDResolution: SteamCMDPathResolution(
                paths: SteamCMDPaths(applicationSupportDirectory: root),
                source: .managedRuntime,
                legacyPaths: []
            )
        )
        viewModel.apiKey = "steam-api-key"

        await viewModel.browse()

        XCTAssertEqual(viewModel.currentPageNumber, 1)
        XCTAssertFalse(viewModel.canLoadPreviousPage)
        XCTAssertFalse(viewModel.canLoadNextPage)
        XCTAssertEqual(viewModel.items.map(\.id), ["1001", "2001", "1002"])
        XCTAssertEqual(httpClient.requiredTags, ["Video", "Web"])
        XCTAssertEqual(httpClient.cursors, ["*", "*"])
        XCTAssertEqual(httpClient.pageSizes, [100, 100])
        XCTAssertEqual(httpClient.matchAllTags, [true, true])
    }

    @MainActor
    func testWorkshopBrowserFillsDisplayedPageFromMultipleTypedCursorRounds() async throws {
        let firstVideoItems = (1...20).map {
            Self.workshopItemJSON(id: "10\(String(format: "%02d", $0))", title: "Video \($0)", type: "video")
        }
        let firstWebItems = (1...10).map {
            Self.workshopItemJSON(id: "20\(String(format: "%02d", $0))", title: "Web \($0)", type: "web")
        }
        let secondVideoItems = (21...45).map {
            Self.workshopItemJSON(id: "10\(String(format: "%02d", $0))", title: "Video \($0)", type: "video")
        }
        let httpClient = FakeSteamWorkshopHTTPClient(responses: [
            Self.workshopResponseJSON(nextCursor: "video-cursor-2", items: firstVideoItems),
            Self.workshopResponseJSON(nextCursor: nil, items: firstWebItems),
            Self.workshopResponseJSON(nextCursor: nil, items: secondVideoItems)
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = SteamWorkshopBrowserViewModel(
            apiService: SteamWorkshopAPIService(httpClient: httpClient),
            steamCMDResolution: SteamCMDPathResolution(
                paths: SteamCMDPaths(applicationSupportDirectory: root),
                source: .managedRuntime,
                legacyPaths: []
            )
        )
        viewModel.apiKey = "steam-api-key"

        await viewModel.browse()

        XCTAssertEqual(viewModel.currentPageNumber, 1)
        XCTAssertEqual(viewModel.items.count, 36)
        XCTAssertTrue(viewModel.canLoadNextPage)
        XCTAssertEqual(httpClient.requiredTags, ["Video", "Web", "Video"])
        XCTAssertEqual(httpClient.cursors, ["*", "*", "video-cursor-2"])
    }

    @MainActor
    func testWorkshopBrowserKeepsBrowseQueryStableWhenLoadingNextPage() async throws {
        let firstVideoItems = (1...36).map {
            Self.workshopItemJSON(id: "30\(String(format: "%02d", $0))", title: "City Video \($0)", type: "video")
        }
        let firstWebItems = (1...36).map {
            Self.workshopItemJSON(id: "40\(String(format: "%02d", $0))", title: "City Web \($0)", type: "web")
        }
        let httpClient = FakeSteamWorkshopHTTPClient(responses: [
            Self.workshopResponseJSON(nextCursor: nil, items: firstVideoItems),
            Self.workshopResponseJSON(nextCursor: nil, items: firstWebItems)
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = SteamWorkshopBrowserViewModel(
            apiService: SteamWorkshopAPIService(httpClient: httpClient),
            steamCMDResolution: SteamCMDPathResolution(
                paths: SteamCMDPaths(applicationSupportDirectory: root),
                source: .managedRuntime,
                legacyPaths: []
            )
        )
        viewModel.apiKey = "steam-api-key"
        viewModel.searchText = "city"

        await viewModel.browse()
        viewModel.searchText = "mountain"
        viewModel.sort = .latest
        await viewModel.loadNextPage()

        XCTAssertEqual(viewModel.currentPageNumber, 2)
        XCTAssertEqual(httpClient.searchTexts, ["city", "city"])
        XCTAssertEqual(httpClient.queryTypes, [
            SteamWorkshopQuery.Sort.search.queryType,
            SteamWorkshopQuery.Sort.search.queryType
        ])
        XCTAssertEqual(httpClient.requiredTags, ["Video", "Web"])
    }

    @MainActor
    func testWorkshopBrowserDisablesNextPageAfterFinalPartialTypedPage() async throws {
        let httpClient = FakeSteamWorkshopHTTPClient(responses: [
            Self.workshopResponseJSON(
                nextCursor: nil,
                items: [
                    Self.workshopItemJSON(id: "1001", title: "Video One", type: "video")
                ]
            ),
            Self.workshopResponseJSON(
                nextCursor: nil,
                items: [
                    Self.workshopItemJSON(id: "2001", title: "Web One", type: "web")
                ]
            )
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = SteamWorkshopBrowserViewModel(
            apiService: SteamWorkshopAPIService(httpClient: httpClient),
            steamCMDResolution: SteamCMDPathResolution(
                paths: SteamCMDPaths(applicationSupportDirectory: root),
                source: .managedRuntime,
                legacyPaths: []
            )
        )
        viewModel.apiKey = "steam-api-key"

        await viewModel.browse()

        XCTAssertEqual(viewModel.items.map(\.id), ["1001", "2001"])
        XCTAssertFalse(viewModel.canLoadNextPage)
        XCTAssertEqual(viewModel.statusMessage, "Loaded page 1 with 2 playable Workshop items.")
    }

    @MainActor
    func testWorkshopBrowserSortsLatestMergedPageByTimeCreated() async throws {
        let httpClient = FakeSteamWorkshopHTTPClient(responses: [
            Self.workshopResponseJSON(
                nextCursor: nil,
                items: [
                    Self.workshopItemJSON(id: "1001", title: "Older Video", type: "video", timeCreated: 100),
                    Self.workshopItemJSON(id: "1002", title: "Newest Video", type: "video", timeCreated: 400)
                ]
            ),
            Self.workshopResponseJSON(
                nextCursor: nil,
                items: [
                    Self.workshopItemJSON(id: "2001", title: "Middle Web", type: "web", timeCreated: 300),
                    Self.workshopItemJSON(id: "2002", title: "Oldest Web", type: "web", timeCreated: 50)
                ]
            )
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = SteamWorkshopBrowserViewModel(
            apiService: SteamWorkshopAPIService(httpClient: httpClient),
            steamCMDResolution: SteamCMDPathResolution(
                paths: SteamCMDPaths(applicationSupportDirectory: root),
                source: .managedRuntime,
                legacyPaths: []
            )
        )
        viewModel.apiKey = "steam-api-key"
        viewModel.sort = .latest

        await viewModel.browse()

        XCTAssertEqual(viewModel.items.map(\.id), ["1002", "2001", "1001", "2002"])
    }

    @MainActor
    func testWorkshopBrowserKeepsLatestArrivalOrderWhenTimeCreatedIsMissing() async throws {
        let httpClient = FakeSteamWorkshopHTTPClient(responses: [
            Self.workshopResponseJSON(
                nextCursor: nil,
                items: [
                    Self.workshopItemJSON(id: "1001", title: "Untimed Video", type: "video")
                ]
            ),
            Self.workshopResponseJSON(
                nextCursor: nil,
                items: [
                    Self.workshopItemJSON(id: "2001", title: "Timed Web", type: "web", timeCreated: 999)
                ]
            )
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = SteamWorkshopBrowserViewModel(
            apiService: SteamWorkshopAPIService(httpClient: httpClient),
            steamCMDResolution: SteamCMDPathResolution(
                paths: SteamCMDPaths(applicationSupportDirectory: root),
                source: .managedRuntime,
                legacyPaths: []
            )
        )
        viewModel.apiKey = "steam-api-key"
        viewModel.sort = .latest

        await viewModel.browse()

        XCTAssertEqual(viewModel.items.map(\.id), ["1001", "2001"])
    }

    @MainActor
    func testWorkshopBrowserKeepsLatestArrivalOrderForEqualTimeCreated() async throws {
        let httpClient = FakeSteamWorkshopHTTPClient(responses: [
            Self.workshopResponseJSON(
                nextCursor: nil,
                items: [
                    Self.workshopItemJSON(id: "1001", title: "First Video", type: "video", timeCreated: 500)
                ]
            ),
            Self.workshopResponseJSON(
                nextCursor: nil,
                items: [
                    Self.workshopItemJSON(id: "2001", title: "Second Web", type: "web", timeCreated: 500)
                ]
            )
        ])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let viewModel = SteamWorkshopBrowserViewModel(
            apiService: SteamWorkshopAPIService(httpClient: httpClient),
            steamCMDResolution: SteamCMDPathResolution(
                paths: SteamCMDPaths(applicationSupportDirectory: root),
                source: .managedRuntime,
                legacyPaths: []
            )
        )
        viewModel.apiKey = "steam-api-key"
        viewModel.sort = .latest

        await viewModel.browse()

        XCTAssertEqual(viewModel.items.map(\.id), ["1001", "2001"])
    }

    func testSteamCMDDownloadArgumentsForceWindowsAndNeverSubscribe() {
        let command = SteamCMDDownloadCommand(
            itemID: "3004222851",
            login: .account(username: "alice", password: "secret", steamGuardCode: "ABCDE")
        )
        let savedSessionCommand = SteamCMDDownloadCommand(
            itemID: "3004222851",
            login: .savedSession(username: "alice")
        )

        XCTAssertEqual(command.arguments, [
            "+@sSteamCmdForcePlatformType", "windows",
            "+login", "alice", "secret", "ABCDE",
            "+workshop_download_item", "431960", "3004222851",
            "+quit"
        ])
        XCTAssertEqual(savedSessionCommand.arguments, [
            "+@sSteamCmdForcePlatformType", "windows",
            "+login", "alice",
            "+workshop_download_item", "431960", "3004222851",
            "+quit"
        ])
        XCTAssertFalse(command.arguments.contains("+workshop_subscribe_item"))
        XCTAssertFalse(command.arguments.contains("+workshop_unsubscribe_item"))
    }

    func testSteamCMDPathsUseManagedRuntimeDirectory() {
        let root = URL(fileURLWithPath: "/tmp/OpenWallpaperEngineSteam", isDirectory: true)
        let paths = SteamCMDPaths(managedRuntimeRoot: root)

        XCTAssertEqual(
            paths.steamCMDDirectory,
            root.appendingPathComponent("SteamCMDManaged/v1", isDirectory: true)
        )
        XCTAssertEqual(paths.executableURL, root.appendingPathComponent("SteamCMDManaged/v1/steamcmd.sh"))
        XCTAssertEqual(paths.steamHomeDirectory, root.appendingPathComponent("SteamCMDManaged/v1/Library/Application Support/Steam", isDirectory: true))
        XCTAssertEqual(
            paths.workshopContentDirectory,
            root.appendingPathComponent("SteamCMDManaged/v1/Library/Application Support/Steam/steamapps/workshop/content/431960", isDirectory: true)
        )
        XCTAssertTrue(paths.legacyWorkshopContentDirectories.contains(
            root.appendingPathComponent("SteamCMDManaged/v1/steamapps/workshop/content/431960", isDirectory: true)
        ))
        XCTAssertFalse(paths.loginSessionCandidateURLs().contains(paths.workshopContentDirectory))
    }

    func testSteamCMDPathResolverUsesManagedRuntimeAndKeepsLegacyWorkshopDirectories() {
        let sourceFile = URL(fileURLWithPath: "/tmp/not-a-project/Open Wallpaper Engine/Services/WEProject.swift")
        let appSupportRoot = URL(fileURLWithPath: "/tmp/app-support", isDirectory: true)

        let resolution = SteamCMDPathResolver.resolve(
            environment: [:],
            sourceFilePath: sourceFile.path,
            applicationSupportDirectory: appSupportRoot,
            runtimeSelection: .missing,
            isWritableDirectory: { _ in false }
        )

        let managedRuntime = appSupportRoot
            .appendingPathComponent("SteamCMDManaged", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        let v2Runtime = appSupportRoot
            .appendingPathComponent("SteamCMDRuntime", isDirectory: true)
            .appendingPathComponent("v2", isDirectory: true)
        let legacy = appSupportRoot
            .appendingPathComponent("Open Wallpaper Engine", isDirectory: true)
            .appendingPathComponent("Steam", isDirectory: true)
            .appendingPathComponent("SteamCMD", isDirectory: true)

        XCTAssertEqual(resolution.source, .managedRuntime)
        XCTAssertNil(resolution.authorizationIssue)
        XCTAssertEqual(resolution.paths.steamCMDDirectory, managedRuntime)
        XCTAssertNil(resolution.paths.securityScopedResourceURL)
        XCTAssertEqual(resolution.legacyPaths.map(\.steamCMDDirectory), [v2Runtime, legacy])
        XCTAssertEqual(resolution.workshopContentDirectories.first, managedRuntime.appendingPathComponent("Library/Application Support/Steam/steamapps/workshop/content/431960", isDirectory: true))
        XCTAssertTrue(resolution.workshopContentDirectories.contains(managedRuntime.appendingPathComponent("steamapps/workshop/content/431960", isDirectory: true)))
        XCTAssertTrue(resolution.workshopContentDirectories.contains(v2Runtime.appendingPathComponent("Library/Application Support/Steam/steamapps/workshop/content/431960", isDirectory: true)))
        XCTAssertTrue(resolution.workshopContentDirectories.contains(v2Runtime.appendingPathComponent("steamapps/workshop/content/431960", isDirectory: true)))
        XCTAssertTrue(resolution.workshopContentDirectories.contains(legacy.appendingPathComponent("Library/Application Support/Steam/steamapps/workshop/content/431960", isDirectory: true)))
        XCTAssertTrue(resolution.workshopContentDirectories.contains(legacy.appendingPathComponent("steamapps/workshop/content/431960", isDirectory: true)))
    }

    func testSteamCMDPathResolverDoesNotUseUserSelectedRuntimeForExecution() {
        let sourceFile = URL(fileURLWithPath: "/tmp/not-a-project/Open Wallpaper Engine/Services/WEProject.swift")
        let appSupportRoot = URL(fileURLWithPath: "/tmp/app-support", isDirectory: true)
        let runtimeRoot = URL(fileURLWithPath: "/Users/alice/Open Wallpaper Engine Runtime", isDirectory: true)

        let resolution = SteamCMDPathResolver.resolve(
            environment: [:],
            sourceFilePath: sourceFile.path,
            applicationSupportDirectory: appSupportRoot,
            runtimeSelection: .selected(runtimeRoot),
            isWritableDirectory: { _ in false }
        )

        let managedRuntime = appSupportRoot
            .appendingPathComponent("SteamCMDManaged", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)

        XCTAssertEqual(resolution.source, .managedRuntime)
        XCTAssertNil(resolution.authorizationIssue)
        XCTAssertEqual(resolution.paths.steamCMDDirectory, managedRuntime)
        XCTAssertNil(resolution.paths.securityScopedResourceURL)
        XCTAssertTrue(resolution.legacyPaths.map(\.steamCMDDirectory).contains(
            runtimeRoot.appendingPathComponent("SteamCMD", isDirectory: true)
        ))
        XCTAssertEqual(resolution.workshopContentDirectories.first, managedRuntime.appendingPathComponent("Library/Application Support/Steam/steamapps/workshop/content/431960", isDirectory: true))
    }

    func testSteamCMDRuntimeBookmarkStoreRefreshesStaleBookmarkAndUsesResolvedURL() {
        let runtimeRoot = URL(fileURLWithPath: "/Users/alice/SteamCmd", isDirectory: true)
        var refreshedURLs = [URL]()

        let selection = SteamCMDRuntimeBookmarkStore.currentSelection(
            resolveBookmark: { SteamCMDRuntimeBookmarkResolution(url: runtimeRoot, isStale: true) },
            refreshBookmark: { refreshedURLs.append($0) }
        )

        XCTAssertEqual(selection, .selected(runtimeRoot))
        XCTAssertEqual(refreshedURLs, [runtimeRoot])
    }

    func testSteamCMDRuntimeBookmarkStoreKeepsResolvedStaleBookmarkWhenRefreshFails() {
        let runtimeRoot = URL(fileURLWithPath: "/Users/alice/SteamCmd", isDirectory: true)

        let selection = SteamCMDRuntimeBookmarkStore.currentSelection(
            resolveBookmark: { SteamCMDRuntimeBookmarkResolution(url: runtimeRoot, isStale: true) },
            refreshBookmark: { _ in throw CocoaError(.fileWriteNoPermission) }
        )

        XCTAssertEqual(selection, .selected(runtimeRoot))
    }

    func testSteamCMDPathResolverUsesEnvironmentOverrideFirst() {
        let projectRoot = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let sourceFile = projectRoot.appendingPathComponent("Open Wallpaper Engine/Services/WEProject.swift")
        let appSupport = URL(fileURLWithPath: "/tmp/app-support", isDirectory: true)
        let override = URL(fileURLWithPath: "/tmp/custom-steamcmd", isDirectory: true)

        let resolution = SteamCMDPathResolver.resolve(
            environment: [SteamCMDPathResolver.environmentKey: override.path],
            sourceFilePath: sourceFile.path,
            applicationSupportDirectory: appSupport,
            runtimeSelection: .selected(URL(fileURLWithPath: "/tmp/user-selected", isDirectory: true)),
            isWritableDirectory: { _ in false }
        )

        XCTAssertEqual(resolution.source, .environmentOverride)
        XCTAssertEqual(resolution.paths.steamCMDDirectory, override)
        XCTAssertEqual(resolution.legacyPaths.map(\.steamCMDDirectory), [
            URL(fileURLWithPath: "/tmp/user-selected", isDirectory: true)
                .appendingPathComponent("SteamCMD", isDirectory: true),
            appSupport
                .appendingPathComponent("SteamCMDRuntime", isDirectory: true)
                .appendingPathComponent("v2", isDirectory: true),
            appSupport
                .appendingPathComponent("Open Wallpaper Engine", isDirectory: true)
                .appendingPathComponent("Steam", isDirectory: true)
                .appendingPathComponent("SteamCMD", isDirectory: true)
        ])
    }

    func testSteamCMDPathResolverDoesNotUseProjectLocalDirectoryWhenWritable() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        try FileManager.default.createDirectory(
            at: projectRoot.appendingPathComponent("Open Wallpaper Engine.xcodeproj", isDirectory: true),
            withIntermediateDirectories: true
        )
        let sourceFile = projectRoot.appendingPathComponent("Open Wallpaper Engine/Services/WEProject.swift")
        let appSupport = URL(fileURLWithPath: "/tmp/app-support", isDirectory: true)

        let resolution = SteamCMDPathResolver.resolve(
            environment: [:],
            sourceFilePath: sourceFile.path,
            applicationSupportDirectory: appSupport,
            runtimeSelection: .missing,
            isWritableDirectory: { url in url == projectRoot }
        )

        XCTAssertEqual(resolution.source, .managedRuntime)
        XCTAssertNil(resolution.authorizationIssue)
        XCTAssertEqual(
            resolution.paths.steamCMDDirectory,
            appSupport
                .appendingPathComponent("SteamCMDManaged", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
        )
    }

    func testSteamCMDPathResolverUsesManagedRuntimeWhenProjectIsNotWritable() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }
        try FileManager.default.createDirectory(
            at: projectRoot.appendingPathComponent("Open Wallpaper Engine.xcodeproj", isDirectory: true),
            withIntermediateDirectories: true
        )
        let sourceFile = projectRoot.appendingPathComponent("Open Wallpaper Engine/Services/WEProject.swift")
        let appSupport = URL(fileURLWithPath: "/tmp/app-support", isDirectory: true)

        let resolution = SteamCMDPathResolver.resolve(
            environment: [:],
            sourceFilePath: sourceFile.path,
            applicationSupportDirectory: appSupport,
            runtimeSelection: .missing,
            isWritableDirectory: { _ in false }
        )

        XCTAssertEqual(resolution.source, .managedRuntime)
        XCTAssertNil(resolution.authorizationIssue)
        XCTAssertEqual(
            resolution.paths.steamCMDDirectory,
            appSupport
                .appendingPathComponent("SteamCMDManaged", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
        )
    }

    func testSteamCMDClearSessionRemovesLoginStateAndPreservesDownloads() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let service = SteamCMDService(paths: paths)
        let config = paths.steamHomeDirectory.appendingPathComponent("config", isDirectory: true)
        let appcache = paths.steamHomeDirectory.appendingPathComponent("appcache", isDirectory: true)
        let userdata = paths.steamHomeDirectory.appendingPathComponent("userdata", isDirectory: true)
        let rootSSFN = paths.steamCMDDirectory.appendingPathComponent("ssfn1234567890")
        let homeSSFN = paths.steamHomeDirectory.appendingPathComponent("ssfn0987654321")
        let downloadedItem = paths.workshopContentDirectory
            .appendingPathComponent("3004222851", isDirectory: true)
            .appendingPathComponent("project.json")

        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appcache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userdata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadedItem.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("login".utf8).write(to: config.appendingPathComponent("loginusers.vdf"))
        try Data("cache".utf8).write(to: appcache.appendingPathComponent("appinfo.vdf"))
        try Data("user".utf8).write(to: userdata.appendingPathComponent("localconfig.vdf"))
        try Data("session".utf8).write(to: rootSSFN)
        try Data("session".utf8).write(to: homeSSFN)
        try Data("{}".utf8).write(to: downloadedItem)

        try await service.clearLoginSession()

        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: appcache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: userdata.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootSSFN.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: homeSSFN.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadedItem.path))
    }

    func testWallpaperLibraryScannerCombinesDocumentAndWorkshopWallpapers() throws {
        let documentRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workshopRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: documentRoot)
            try? FileManager.default.removeItem(at: workshopRoot)
        }
        let localItem = documentRoot.appendingPathComponent("Local Rain", isDirectory: true)
        let workshopItem = workshopRoot
            .appendingPathComponent("3004222851", isDirectory: true)

        try FileManager.default.createDirectory(at: localItem, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workshopItem, withIntermediateDirectories: true)
        try """
        {"file":"local.mp4","preview":"preview.jpg","title":"Local Rain","type":"video"}
        """.data(using: .utf8)!.write(to: localItem.appendingPathComponent("project.json"))
        try """
        {"file":"workshop.mp4","preview":"preview.jpg","title":"Workshop Rain","type":"web","workshopid":"3004222851"}
        """.data(using: .utf8)!.write(to: workshopItem.appendingPathComponent("project.json"))

        let wallpapers = WallpaperLibraryService.scanInstalledWallpapers(
            documentDirectory: documentRoot,
            workshopContentDirectory: workshopRoot
        )

        XCTAssertEqual(wallpapers.map(\.project.title).sorted(), ["Local Rain", "Workshop Rain"])
    }

    func testWallpaperLibraryScannerCombinesResolvedAndLegacyWorkshopWallpapers() throws {
        let documentRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resolvedWorkshopRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacyWorkshopRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: documentRoot)
            try? FileManager.default.removeItem(at: resolvedWorkshopRoot)
            try? FileManager.default.removeItem(at: legacyWorkshopRoot)
        }

        let localItem = documentRoot.appendingPathComponent("Local Rain", isDirectory: true)
        let resolvedWorkshopItem = resolvedWorkshopRoot.appendingPathComponent("3004222851", isDirectory: true)
        let legacyWorkshopItem = legacyWorkshopRoot.appendingPathComponent("3005000000", isDirectory: true)

        try FileManager.default.createDirectory(at: localItem, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resolvedWorkshopItem, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyWorkshopItem, withIntermediateDirectories: true)
        try """
        {"file":"local.mp4","preview":"preview.jpg","title":"Local Rain","type":"video"}
        """.data(using: .utf8)!.write(to: localItem.appendingPathComponent("project.json"))
        try """
        {"file":"resolved.mp4","preview":"preview.jpg","title":"Resolved Workshop","type":"web","workshopid":"3004222851"}
        """.data(using: .utf8)!.write(to: resolvedWorkshopItem.appendingPathComponent("project.json"))
        try """
        {"file":"legacy.mp4","preview":"preview.jpg","title":"Legacy Workshop","type":"video","workshopid":"3005000000"}
        """.data(using: .utf8)!.write(to: legacyWorkshopItem.appendingPathComponent("project.json"))

        let wallpapers = WallpaperLibraryService.scanInstalledWallpapers(
            documentDirectory: documentRoot,
            workshopContentDirectories: [resolvedWorkshopRoot, legacyWorkshopRoot]
        )

        XCTAssertEqual(
            wallpapers.map(\.project.title).sorted(),
            ["Legacy Workshop", "Local Rain", "Resolved Workshop"]
        )
    }

    func testSteamCMDInstallSkipsOfficialInstallCommandWhenExecutableExists() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()
        var states = [SteamCMDInstallState]()

        try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try writeExecutable("#!/bin/sh\n", to: paths.executableURL)
        try writeExecutable("binary", to: paths.steamCMDExecutableURL)

        let service = SteamCMDService(paths: paths, processRunner: runner)
        try await service.installIfMissing { states.append($0) }

        XCTAssertTrue(runner.runCalls.isEmpty)
        XCTAssertEqual(states, [.checking, .installed(paths.executableURL)])
    }

    func testAppSandboxEntitlementsAllowWritingExecutableSteamCMD() throws {
        let entitlementsURL = repositoryRoot()
            .appendingPathComponent("Open Wallpaper Engine", isDirectory: true)
            .appendingPathComponent("Open_Wallpaper_Engine.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(plist["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.network.client"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.files.user-selected.executable"] as? Bool, true)
        XCTAssertEqual(plist["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
    }

    func testSteamCMDServiceDefaultsToBundledXPCRunner() async {
        let appSupportRoot = URL(fileURLWithPath: "/tmp/app-support", isDirectory: true)
        let resolution = SteamCMDPathResolver.resolve(
            environment: [:],
            sourceFilePath: "/tmp/not-a-project/Open Wallpaper Engine/Services/WEProject.swift",
            applicationSupportDirectory: appSupportRoot,
            runtimeSelection: .missing,
            isWritableDirectory: { _ in false }
        )

        let service = SteamCMDService(resolution: resolution)
        let diagnostics = await service.diagnostics()

        XCTAssertTrue(diagnostics.isUsingXPCClient)
        XCTAssertEqual(diagnostics.runtimeURL, resolution.paths.steamCMDDirectory)
    }

    func testSteamCMDServiceClearSessionUsesConfiguredClient() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let client = RecordingSteamCMDClient(paths: paths)
        let service = SteamCMDService(
            resolution: SteamCMDPathResolution(paths: paths, source: .managedRuntime, legacyPaths: []),
            client: client
        )

        try await service.clearLoginSession()

        XCTAssertEqual(client.clearLoginSessionCallCount, 1)
    }

    func testSteamCMDXPCRunnerInstallsAndRunsQuitWhenIntegrationEnabled() async throws {
#if RUN_STEAMCMD_INTEGRATION
        let appSupportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OWESteamCMDIntegration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: appSupportRoot) }
        let resolution = SteamCMDPathResolver.resolve(
            environment: [:],
            sourceFilePath: "/tmp/not-a-project/Open Wallpaper Engine/Services/WEProject.swift",
            applicationSupportDirectory: appSupportRoot,
            runtimeSelection: .missing,
            isWritableDirectory: { _ in false }
        )
        let service = SteamCMDService(resolution: resolution)

        try await service.installIfNeeded()

        XCTAssertTrue(FileManager.default.fileExists(atPath: resolution.paths.executableURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolution.paths.steamCMDExecutableURL.path))
#else
        throw XCTSkip("Set OTHER_SWIFT_FLAGS=-DRUN_STEAMCMD_INTEGRATION to download SteamCMD and run the bundled XPC runner.")
#endif
    }

    func testSteamCMDRunnerTargetIsEmbeddedAndDoesNotUseAppSandboxEntitlements() throws {
        let projectURL = repositoryRoot()
            .appendingPathComponent("Open Wallpaper Engine.xcodeproj", isDirectory: true)
            .appendingPathComponent("project.pbxproj")
        let project = try String(contentsOf: projectURL, encoding: .utf8)
        let debugStart = try XCTUnwrap(project.range(of: "B500000F2EE0000000000001 /* Debug */"))
        let releaseEnd = try XCTUnwrap(project.range(of: "B50000102EE0000000000001 /* Release */", range: debugStart.upperBound..<project.endIndex))
        let runnerBuildSettings = String(project[debugStart.lowerBound..<releaseEnd.upperBound])

        XCTAssertTrue(project.contains("SteamCMDRunner.xpc in Embed XPC Services"))
        XCTAssertTrue(project.contains("dstPath = \"$(CONTENTS_FOLDER_PATH)/XPCServices\";"))
        XCTAssertTrue(project.contains("productType = \"com.apple.product-type.xpc-service\";"))
        XCTAssertFalse(runnerBuildSettings.contains("CODE_SIGN_ENTITLEMENTS"))
    }

    func testSteamCMDRunnerCoreUsesOfficialInstallPipelineAndLauncher() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(managedRuntimeRoot: root)
        let runner = FakeProcessRunner()

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDRunnerCore.installShellCommand] else { return }
            try self.writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
            try self.writeExecutable("binary", to: paths.steamCMDExecutableURL)
        }

        let core = SteamCMDRunnerCore(paths: paths, processRunner: runner)
        let result = try await core.installIfMissing()

        XCTAssertEqual(result.runtimeURL, paths.steamCMDDirectory)
        XCTAssertEqual(runner.runCalls.map(\.executableURL), [
            URL(fileURLWithPath: "/bin/sh"),
            paths.steamCMDExecutableURL
        ])
        XCTAssertEqual(runner.runCalls[0].arguments, ["-c", SteamCMDRunnerCore.installShellCommand])
        XCTAssertTrue(SteamCMDRunnerCore.installShellCommand.contains("curl -sqL"))
        XCTAssertTrue(SteamCMDRunnerCore.installShellCommand.contains(SteamCMDRunnerCore.installArchiveURL.absoluteString))
        XCTAssertTrue(SteamCMDRunnerCore.installShellCommand.contains("tar zxvf -"))
        XCTAssertEqual(runner.runCalls[1].arguments, ["+quit"])
        XCTAssertEqual(runner.runCalls[1].environment?["HOME"], paths.steamHomeDirectory.path)
    }

    func testSteamCMDRunnerCoreCreatesRuntimeDirectoriesAndRepairsQuarantine() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(managedRuntimeRoot: root)
        let runner = FakeProcessRunner()

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDRunnerCore.installShellCommand] else { return }
            try self.writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
            try self.writeExecutable("binary", to: paths.steamCMDExecutableURL)
            try self.setQuarantineAttribute(on: paths.steamCMDExecutableURL)
        }

        let core = SteamCMDRunnerCore(paths: paths, processRunner: runner)
        _ = try await core.installIfMissing()

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.steamCMDDirectory.appendingPathComponent("tmp", isDirectory: true).path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: paths.steamCMDDirectory
                .appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
                .path
        ))
        XCTAssertFalse(hasQuarantineAttribute(at: paths.steamCMDExecutableURL))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: paths.executableURL.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: paths.steamCMDExecutableURL.path))
    }

    func testSteamCMDRunnerCoreDownloadsWithoutSubscribing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(managedRuntimeRoot: root)
        let runner = FakeProcessRunner()

        try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
        try writeExecutable("binary", to: paths.steamCMDExecutableURL)

        let core = SteamCMDRunnerCore(paths: paths, processRunner: runner)
        let result = try await core.downloadItem(itemID: "3314492008", login: .anonymous, output: { _ in })

        let downloadCall = try XCTUnwrap(runner.runCalls.last)
        XCTAssertEqual(downloadCall.executableURL, paths.steamCMDExecutableURL)
        XCTAssertEqual(downloadCall.arguments, [
            "+@sSteamCmdForcePlatformType", "windows",
            "+login", "anonymous",
            "+workshop_download_item", "431960", "3314492008",
            "+quit"
        ])
        XCTAssertFalse(downloadCall.arguments.contains("+workshop_subscribe_item"))
        XCTAssertFalse(downloadCall.arguments.contains("+workshop_unsubscribe_item"))
        XCTAssertEqual(result.downloadedItemURL, paths.workshopContentDirectory.appendingPathComponent("3314492008", isDirectory: true))
    }

    func testSteamCMDInstallUsesManagedRuntimeWithoutUserSelectedDirectory() async throws {
        let appSupportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: appSupportRoot) }
        let resolution = SteamCMDPathResolver.resolve(
            environment: [:],
            sourceFilePath: "/tmp/not-a-project/Open Wallpaper Engine/Services/WEProject.swift",
            applicationSupportDirectory: appSupportRoot,
            runtimeSelection: .missing,
            isWritableDirectory: { _ in false }
        )
        let runner = FakeProcessRunner()
        var states = [SteamCMDInstallState]()

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDService.installShellCommand] else { return }
            try self.writeExecutable("#!/bin/sh\n", to: resolution.paths.executableURL)
            try self.writeExecutable("binary", to: resolution.paths.steamCMDExecutableURL)
        }

        let service = SteamCMDService(resolution: resolution, processRunner: runner)
        try await service.installIfMissing { states.append($0) }

        XCTAssertEqual(resolution.source, .managedRuntime)
        XCTAssertNil(resolution.authorizationIssue)
        XCTAssertEqual(
            resolution.paths.steamCMDDirectory,
            appSupportRoot
                .appendingPathComponent("SteamCMDManaged", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
        )
        XCTAssertEqual(runner.runCalls.map(\.executableURL), [
            URL(fileURLWithPath: "/bin/sh"),
            resolution.paths.steamCMDExecutableURL
        ])
        XCTAssertEqual(states, [.checking, .downloading, .extracting, .installed(resolution.paths.executableURL)])
    }

    func testSteamCMDInstallDoesNotUseSecurityScopedRuntimeForExecution() async throws {
        let runtimeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appSupportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: runtimeRoot)
            try? FileManager.default.removeItem(at: appSupportRoot)
        }
        let resolution = SteamCMDPathResolver.resolve(
            environment: [:],
            sourceFilePath: "/tmp/not-a-project/Open Wallpaper Engine/Services/WEProject.swift",
            applicationSupportDirectory: appSupportRoot,
            runtimeSelection: .selected(runtimeRoot),
            isWritableDirectory: { _ in false }
        )
        let paths = resolution.paths
        let runner = FakeProcessRunner()
        let securityScope = FakeSecurityScopedAccess()

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDService.installShellCommand] else { return }
            try self.writeExecutable("#!/bin/sh\n", to: paths.executableURL)
            try self.writeExecutable("binary", to: paths.steamCMDExecutableURL)
        }

        let service = SteamCMDService(
            resolution: resolution,
            processRunner: runner,
            securityScopedAccess: securityScope
        )
        try await service.installIfMissing()

        XCTAssertTrue(securityScope.startedURLs.isEmpty)
        XCTAssertTrue(securityScope.stoppedURLs.isEmpty)
        XCTAssertNotEqual(paths.steamCMDDirectory, runtimeRoot.appendingPathComponent("SteamCMD", isDirectory: true))
        XCTAssertTrue(resolution.legacyPaths.map(\.steamCMDDirectory).contains(
            runtimeRoot.appendingPathComponent("SteamCMD", isDirectory: true)
        ))
        XCTAssertEqual(runner.runCalls.map(\.currentDirectoryURL), [
            paths.steamCMDDirectory,
            paths.steamCMDDirectory
        ])
    }

    func testSteamCMDInstallRunsReadinessCheckWithContainerEnvironment() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDService.installShellCommand] else { return }
            try self.writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
            try self.writeExecutable("binary", to: paths.steamCMDExecutableURL)
        }

        let service = SteamCMDService(paths: paths, processRunner: runner)
        try await service.installIfMissing()

        XCTAssertEqual(runner.runCalls.map(\.executableURL), [
            URL(fileURLWithPath: "/bin/sh"),
            paths.steamCMDExecutableURL
        ])
        let installCall = runner.runCalls[0]
        XCTAssertEqual(installCall.currentDirectoryURL, paths.steamCMDDirectory)
        XCTAssertEqual(installCall.environment?["HOME"], paths.steamHomeDirectory.path)
        XCTAssertEqual(installCall.environment?["TMPDIR"], paths.steamCMDDirectory.appendingPathComponent("tmp", isDirectory: true).path)
        XCTAssertEqual(installCall.environment?["STEAMCMD_HOME"], paths.steamHomeDirectory.path)
        XCTAssertNotNil(installCall.environment?["PATH"])

        let readinessCall = runner.runCalls[1]
        XCTAssertEqual(readinessCall.executableURL, paths.steamCMDExecutableURL)
        XCTAssertEqual(readinessCall.arguments, ["+quit"])
        XCTAssertEqual(readinessCall.currentDirectoryURL, paths.steamCMDDirectory)
        XCTAssertEqual(readinessCall.environment?["HOME"], paths.steamHomeDirectory.path)
        XCTAssertEqual(readinessCall.environment?["TMPDIR"], paths.steamCMDDirectory.appendingPathComponent("tmp", isDirectory: true).path)
        XCTAssertEqual(readinessCall.environment?["STEAMCMD_HOME"], paths.steamHomeDirectory.path)
        XCTAssertTrue(readinessCall.environment?["DYLD_LIBRARY_PATH"]?.hasPrefix(paths.steamCMDDirectory.path) == true)
        XCTAssertTrue(readinessCall.environment?["DYLD_FRAMEWORK_PATH"]?.hasPrefix(paths.steamCMDDirectory.path) == true)
    }

    func testSteamCMDInstallRunsAbsoluteLauncherAndRetriesSteamCMDMagicRestart() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()
        runner.terminationStatuses = [42, 0]

        try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
        try writeExecutable("binary", to: paths.steamCMDExecutableURL)

        let service = SteamCMDService(paths: paths, processRunner: runner)
        try await service.repairRuntime()

        XCTAssertEqual(runner.runCalls.map(\.executableURL), [
            paths.steamCMDExecutableURL,
            paths.steamCMDExecutableURL
        ])
        XCTAssertEqual(runner.runCalls.map(\.arguments), [
            ["+quit"],
            ["+quit"]
        ])
        XCTAssertTrue(runner.runCalls[0].environment?["DYLD_LIBRARY_PATH"]?.hasPrefix(paths.steamCMDDirectory.path) == true)
        XCTAssertTrue(runner.runCalls[0].environment?["DYLD_FRAMEWORK_PATH"]?.hasPrefix(paths.steamCMDDirectory.path) == true)
    }

    func testSteamCMDInstallCreatesSteamHomeDirectoriesBeforeReadinessCheck() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDService.installShellCommand] else { return }
            try self.writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
            try self.writeExecutable("binary", to: paths.steamCMDExecutableURL)
        }

        let service = SteamCMDService(paths: paths, processRunner: runner)
        try await service.installIfMissing()

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: paths.steamCMDDirectory
                .appendingPathComponent("Library/Application Support/Steam", isDirectory: true)
                .path
        ))
    }

    func testSteamCMDInstallFailureIncludesReadinessOutput() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()
        runner.terminationStatuses = [0, 126]

        runner.onRun = { executableURL, arguments, output, _ in
            if executableURL == URL(fileURLWithPath: "/bin/sh"),
               arguments == ["-c", SteamCMDService.installShellCommand] {
                try self.writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
                try self.writeExecutable("binary", to: paths.steamCMDExecutableURL)
            }
            if executableURL == paths.steamCMDExecutableURL,
               arguments == ["+quit"] {
                output("steamcmd: Operation not permitted")
            }
        }

        let service = SteamCMDService(paths: paths, processRunner: runner)
        do {
            try await service.installIfMissing()
            XCTFail("Expected SteamCMD readiness check to fail")
        } catch SteamCMDError.installFailed(let recentOutput) {
            XCTAssertEqual(recentOutput, [
                "steamcmd: Operation not permitted",
                "SteamCMD readiness check exited with status 126."
            ])
        }
    }

    func testSteamCMDInstallIgnoresQuarantinedLegacyRuntimeAndInstallsIntoManagedRuntime() async throws {
        let appSupportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtimeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: appSupportRoot)
            try? FileManager.default.removeItem(at: runtimeRoot)
        }
        let resolution = SteamCMDPathResolver.resolve(
            environment: [:],
            sourceFilePath: "/tmp/not-a-project/Open Wallpaper Engine/Services/WEProject.swift",
            applicationSupportDirectory: appSupportRoot,
            runtimeSelection: .selected(runtimeRoot),
            isWritableDirectory: { _ in false }
        )
        let paths = resolution.paths
        let legacyPaths = try XCTUnwrap(resolution.legacyPaths.first {
            $0.steamCMDDirectory.path.contains("Open Wallpaper Engine/Steam/SteamCMD")
        })
        let runner = FakeProcessRunner()
        let securityScope = FakeSecurityScopedAccess()

        try FileManager.default.createDirectory(at: legacyPaths.steamCMDDirectory, withIntermediateDirectories: true)
        try writeExecutable("#!/usr/bin/env bash\n", to: legacyPaths.executableURL)
        try writeExecutable("legacy binary", to: legacyPaths.steamCMDExecutableURL)
        try setQuarantineAttribute(on: legacyPaths.steamCMDDirectory)

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDService.installShellCommand] else { return }
            try self.writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
            try self.writeExecutable("binary", to: paths.steamCMDExecutableURL)
        }

        let service = SteamCMDService(
            resolution: resolution,
            processRunner: runner,
            securityScopedAccess: securityScope
        )
        try await service.installIfMissing()

        XCTAssertEqual(
            paths.steamCMDDirectory,
            appSupportRoot
                .appendingPathComponent("SteamCMDManaged", isDirectory: true)
                .appendingPathComponent("v1", isDirectory: true)
        )
        XCTAssertTrue(securityScope.startedURLs.isEmpty)
        XCTAssertTrue(securityScope.stoppedURLs.isEmpty)
        XCTAssertEqual(runner.runCalls.map(\.executableURL), [
            URL(fileURLWithPath: "/bin/sh"),
            paths.steamCMDExecutableURL
        ])
        XCTAssertEqual(runner.runCalls[0].currentDirectoryURL, paths.steamCMDDirectory)
        XCTAssertEqual(runner.runCalls[1].arguments, ["+quit"])
    }

    func testSteamCMDRepairRunsReadinessCheckWithoutPatchingLauncher() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()
        let launcher = """
        #!/usr/bin/env bash
        STEAMEXE="${STEAMROOT}/${STEAMCMD}"
        if [ ! -x "${STEAMEXE}" ]; then
          STEAMEXE="${STEAMROOT}/Steam.AppBundle/Steam/Contents/MacOS/${STEAMCMD}"
        fi
        """

        try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try writeExecutable(launcher, to: paths.executableURL)
        try writeExecutable("binary", to: paths.steamCMDExecutableURL)

        let service = SteamCMDService(paths: paths, processRunner: runner)
        try await service.repairRuntime()

        XCTAssertEqual(try String(contentsOf: paths.executableURL), launcher)
        XCTAssertEqual(runner.runCalls.map(\.executableURL), [paths.steamCMDExecutableURL])
        XCTAssertEqual(runner.runCalls.map(\.arguments), [["+quit"]])
    }

    func testSteamCMDInstallRepairsQuarantinedFreshInstallProducts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDService.installShellCommand] else { return }
            try self.writeExecutable("#!/bin/sh\n", to: paths.executableURL)
            try self.writeExecutable("binary", to: paths.steamCMDExecutableURL)
            try self.setQuarantineAttribute(on: paths.steamCMDExecutableURL)
        }

        let service = SteamCMDService(paths: paths, processRunner: runner)
        try await service.installIfMissing()

        XCTAssertFalse(hasQuarantineAttribute(at: paths.steamCMDExecutableURL))
        XCTAssertEqual(runner.runCalls.map(\.executableURL), [
            URL(fileURLWithPath: "/bin/sh"),
            paths.steamCMDExecutableURL
        ])
    }

    func testSteamCMDInstallDoesNotPatchLegacyLauncherForPathsWithSpaces() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()
        let legacyLauncher = """
        #!/usr/bin/env bash
        STEAMROOT="$(cd "${0%/*}" && echo $PWD)"
        STEAMCMD=$(basename "$0" .sh)
        STEAMEXE="${STEAMROOT}/${STEAMCMD}"
        if [ ! -x ${STEAMEXE} ]; then
          STEAMEXE="${STEAMROOT}/Steam.AppBundle/Steam/Contents/MacOS/${STEAMCMD}"
        fi
        $DEBUGGER "$STEAMEXE" "$@"
        """

        try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try writeExecutable(legacyLauncher, to: paths.executableURL)
        try writeExecutable("binary", to: paths.steamCMDExecutableURL)

        let service = SteamCMDService(paths: paths, processRunner: runner)
        try await service.installIfMissing()

        let installedLauncher = try String(contentsOf: paths.executableURL)
        XCTAssertEqual(installedLauncher, legacyLauncher)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: paths.executableURL.path))
        XCTAssertTrue(runner.runCalls.isEmpty)
    }

    func testSteamCMDRepairUsesBinaryInsteadOfLauncherScript() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()
        let sandboxSensitiveLauncher = """
        #!/usr/bin/env bash
        STEAMROOT="$(cd "${0%/*}" && echo $PWD)"
        STEAMCMD=`basename "$0" .sh`
        STEAMEXE="${STEAMROOT}/${STEAMCMD}"
        if [ ! -x "${STEAMEXE}" ]; then
          STEAMEXE="${STEAMROOT}/Steam.AppBundle/Steam/Contents/MacOS/${STEAMCMD}"
        fi
        $DEBUGGER "$STEAMEXE" "$@"
        """

        try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try writeExecutable(sandboxSensitiveLauncher, to: paths.executableURL)
        try writeExecutable("binary", to: paths.steamCMDExecutableURL)

        let service = SteamCMDService(paths: paths, processRunner: runner)
        try await service.repairRuntime()

        XCTAssertEqual(try String(contentsOf: paths.executableURL), sandboxSensitiveLauncher)
        XCTAssertEqual(runner.runCalls.map(\.executableURL), [paths.steamCMDExecutableURL])
        XCTAssertEqual(runner.runCalls.map(\.arguments), [["+quit"]])
    }

    func testSteamCMDInstallUsesPOSIXPermissionsWhenExecutableCheckIsDenied() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()
        let fileManager = ExecutableDenyingFileManager()

        try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try writeExecutable("#!/bin/sh\n", to: paths.executableURL)
        try writeExecutable("binary", to: paths.steamCMDExecutableURL)

        let service = SteamCMDService(paths: paths, processRunner: runner, fileManager: fileManager)
        try await service.installIfMissing()

        XCTAssertTrue(runner.runCalls.isEmpty)
        XCTAssertTrue(fileManager.executableCheckPaths.isEmpty)
    }

    private final class ExecutableDenyingFileManager: FileManager {
        private(set) var executableCheckPaths = [String]()

        override func isExecutableFile(atPath path: String) -> Bool {
            executableCheckPaths.append(path)
            return false
        }
    }

    private final class RecordingRemoveItemFileManager: FileManager {
        private(set) var removedItems = [String]()

        override func removeItem(at URL: URL) throws {
            removedItems.append(URL.path)
            try super.removeItem(at: URL)
        }
    }

    func testSteamCMDInstallRunsOfficialCurlTarPipelineInSteamCMDDirectory() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()
        var states = [SteamCMDInstallState]()

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDService.installShellCommand] else { return }
            try self.writeExecutable("#!/bin/sh\n", to: paths.executableURL)
            try self.writeExecutable("binary", to: paths.steamCMDExecutableURL)
        }

        let service = SteamCMDService(paths: paths, processRunner: runner)
        try await service.installIfMissing { states.append($0) }

        let installCall = try XCTUnwrap(runner.runCalls.first)
        XCTAssertEqual(installCall.executableURL, URL(fileURLWithPath: "/bin/sh"))
        XCTAssertEqual(installCall.arguments, ["-c", SteamCMDService.installShellCommand])
        XCTAssertEqual(installCall.currentDirectoryURL, paths.steamCMDDirectory)
        XCTAssertTrue(SteamCMDService.installShellCommand.contains("curl -sqL"))
        XCTAssertTrue(SteamCMDService.installShellCommand.contains(SteamCMDService.installArchiveURL.absoluteString))
        XCTAssertTrue(SteamCMDService.installShellCommand.contains("tar zxvf -"))
        XCTAssertTrue(SteamCMDService.installShellCommand.contains("chmod 755 steamcmd steamcmd.sh"))
        XCTAssertEqual(runner.runCalls.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.executableURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.steamCMDExecutableURL.path))
        XCTAssertEqual(states, [.checking, .downloading, .extracting, .installed(paths.executableURL)])
    }

    func testSteamCMDInstallMakesExtractedSteamCMDFilesExecutable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDService.installShellCommand] else { return }
            try Data("#!/bin/sh\n".utf8).write(to: paths.executableURL)
            try Data("binary".utf8).write(to: paths.steamCMDExecutableURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.executableURL.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: paths.steamCMDExecutableURL.path)
        }

        let service = SteamCMDService(paths: paths, processRunner: runner)
        try await service.installIfMissing()

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: paths.executableURL.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: paths.steamCMDExecutableURL.path))
        XCTAssertEqual(runner.runCalls.count, 2)
    }

    func testSteamCMDInstallFailsWhenOfficialPipelineDoesNotCreateExecutablePair() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()
        var states = [SteamCMDInstallState]()

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDService.installShellCommand] else { return }
            try self.writeExecutable("#!/bin/sh\n", to: paths.executableURL)
        }

        let service = SteamCMDService(paths: paths, processRunner: runner)
        do {
            try await service.installIfMissing { states.append($0) }
            XCTFail("Expected SteamCMD install to fail")
        } catch SteamCMDError.installFailed(let recentOutput) {
            XCTAssertEqual(recentOutput, ["Missing steamcmd."])
            XCTAssertFalse(FileManager.default.fileExists(atPath: paths.executableURL.path))
            XCTAssertEqual(
                states,
                [.checking, .downloading, .extracting, .failed("SteamCMD could not be installed. Recent output: Missing steamcmd.")]
            )
        }
    }

    func testSteamCMDInstallFailureIncludesRecentPipelineOutput() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner(terminationStatus: 1)
        var states = [SteamCMDInstallState]()

        runner.onRun = { executableURL, _, output, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh") else { return }
            output("tar: Error opening archive: Unrecognized archive format")
        }

        let service = SteamCMDService(paths: paths, processRunner: runner)
        do {
            try await service.installIfMissing { states.append($0) }
            XCTFail("Expected SteamCMD install to fail")
        } catch let error as SteamCMDError {
            switch error {
            case .installFailed(let recentOutput):
                XCTAssertEqual(recentOutput, [
                    "tar: Error opening archive: Unrecognized archive format",
                    "Install command exited with status 1."
                ])
                XCTAssertEqual(
                    error.localizedDescription,
                    "SteamCMD could not be installed. Recent output: tar: Error opening archive: Unrecognized archive format | Install command exited with status 1."
                )
                XCTAssertEqual(states, [.checking, .downloading, .extracting, .failed(error.localizedDescription)])
            default:
                XCTFail("Expected installFailed, got \(error)")
            }
        }
    }

    func testSteamCMDInstallFailureExplainsMissingExecutablePairAfterSuccessfulPipeline() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()

        runner.onRun = { executableURL, arguments, _, _ in
            guard executableURL == URL(fileURLWithPath: "/bin/sh"),
                  arguments == ["-c", SteamCMDService.installShellCommand] else { return }
            try self.writeExecutable("binary", to: paths.steamCMDExecutableURL)
        }

        let service = SteamCMDService(paths: paths, processRunner: runner)
        do {
            try await service.installIfMissing()
            XCTFail("Expected SteamCMD install to fail")
        } catch let error as SteamCMDError {
            switch error {
            case .installFailed(let recentOutput):
                XCTAssertEqual(recentOutput, ["Missing steamcmd.sh."])
                XCTAssertEqual(
                    error.localizedDescription,
                    "SteamCMD could not be installed. Recent output: Missing steamcmd.sh."
                )
            default:
                XCTFail("Expected installFailed, got \(error)")
            }
        }
    }

    func testSteamCMDInstallRecoversFromExistingArchiveWhenOfficialPipelineFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()
        var states = [SteamCMDInstallState]()

        runner.terminationStatuses = [1, 0, 0]
        try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try Data("legacy archive".utf8)
            .write(to: paths.steamCMDDirectory.appendingPathComponent("steamcmd_osx.tar.gz"))
        runner.onRun = { executableURL, _, output, _ in
            if executableURL == URL(fileURLWithPath: "/bin/sh") {
                output("tar: Error opening archive: Unrecognized archive format")
            }
            if executableURL == URL(fileURLWithPath: "/usr/bin/tar") {
                try self.writeExecutable("#!/bin/sh\n", to: paths.executableURL)
                try self.writeExecutable("binary", to: paths.steamCMDExecutableURL)
            }
        }

        let service = SteamCMDService(paths: paths, processRunner: runner)
        try await service.installIfMissing { states.append($0) }

        XCTAssertEqual(runner.runCalls.map(\.executableURL), [
            URL(fileURLWithPath: "/bin/sh"),
            URL(fileURLWithPath: "/usr/bin/tar"),
            paths.steamCMDExecutableURL
        ])
        XCTAssertEqual(runner.runCalls[1].arguments, ["zxvf", "steamcmd_osx.tar.gz"])
        XCTAssertEqual(runner.runCalls[1].currentDirectoryURL, paths.steamCMDDirectory)
        XCTAssertEqual(runner.runCalls[2].arguments, ["+quit"])
        XCTAssertEqual(states, [.checking, .downloading, .extracting, .installed(paths.executableURL)])
    }

    func testSteamCMDDownloadRunsAbsoluteLauncher() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner()

        try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
        try writeExecutable("binary", to: paths.steamCMDExecutableURL)

        let service = SteamCMDService(paths: paths, processRunner: runner)
        let downloadedDirectory = try await service.downloadItem(
            itemID: "3314492008",
            login: .anonymous,
            output: { _ in }
        )

        let downloadCall = try XCTUnwrap(runner.runCalls.last)
        XCTAssertEqual(downloadCall.executableURL, paths.steamCMDExecutableURL)
        XCTAssertEqual(downloadCall.arguments, [
            "+@sSteamCmdForcePlatformType", "windows",
            "+login", "anonymous",
            "+workshop_download_item", "431960", "3314492008",
            "+quit"
        ])
        XCTAssertEqual(downloadCall.currentDirectoryURL, paths.steamCMDDirectory)
        XCTAssertEqual(downloadCall.environment?["HOME"], paths.steamHomeDirectory.path)
        XCTAssertEqual(downloadCall.environment?["TMPDIR"], paths.steamCMDDirectory.appendingPathComponent("tmp", isDirectory: true).path)
        XCTAssertTrue(downloadCall.environment?["DYLD_LIBRARY_PATH"]?.hasPrefix(paths.steamCMDDirectory.path) == true)
        XCTAssertEqual(downloadedDirectory, paths.workshopContentDirectory.appendingPathComponent("3314492008", isDirectory: true))
    }

    func testSteamCMDDownloadDoesNotUseSecurityScopedRuntimeForExecution() async throws {
        let runtimeRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appSupportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: runtimeRoot)
            try? FileManager.default.removeItem(at: appSupportRoot)
        }
        let resolution = SteamCMDPathResolver.resolve(
            environment: [:],
            sourceFilePath: "/tmp/not-a-project/Open Wallpaper Engine/Services/WEProject.swift",
            applicationSupportDirectory: appSupportRoot,
            runtimeSelection: .selected(runtimeRoot),
            isWritableDirectory: { _ in false }
        )
        let paths = resolution.paths
        let runner = FakeProcessRunner()
        let securityScope = FakeSecurityScopedAccess()

        try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
        try writeExecutable("binary", to: paths.steamCMDExecutableURL)

        let service = SteamCMDService(
            resolution: resolution,
            processRunner: runner,
            securityScopedAccess: securityScope
        )
        _ = try await service.downloadItem(
            itemID: "3314492008",
            login: .anonymous,
            output: { _ in }
        )

        XCTAssertTrue(securityScope.startedURLs.isEmpty)
        XCTAssertTrue(securityScope.stoppedURLs.isEmpty)
        XCTAssertNotEqual(paths.steamCMDDirectory, runtimeRoot.appendingPathComponent("SteamCMD", isDirectory: true))
        XCTAssertEqual(runner.runCalls.last?.arguments, [
            "+@sSteamCmdForcePlatformType", "windows",
            "+login", "anonymous",
            "+workshop_download_item", "431960", "3314492008",
            "+quit"
        ])
    }

    func testSteamCMDCommandFailureIncludesRecentProcessOutput() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = SteamCMDPaths(applicationSupportDirectory: root)
        let runner = FakeProcessRunner(terminationStatus: 126)
        runner.terminationStatuses = [0, 126]

        try FileManager.default.createDirectory(at: paths.steamCMDDirectory, withIntermediateDirectories: true)
        try writeExecutable("#!/usr/bin/env bash\n", to: paths.executableURL)
        try writeExecutable("binary", to: paths.steamCMDExecutableURL)
        runner.onRun = { executableURL, _, output, _ in
            guard executableURL == paths.steamCMDExecutableURL else { return }
            guard runner.runCalls.last?.arguments.contains("+workshop_download_item") == true else { return }
            output("steamcmd: operation not permitted")
        }

        let service = SteamCMDService(paths: paths, processRunner: runner)
        do {
            _ = try await service.downloadItem(itemID: "3314492008", login: .anonymous, output: { _ in })
            XCTFail("Expected SteamCMD download to fail")
        } catch let error as SteamCMDError {
            switch error {
            case .commandFailed(let status, let recentOutput):
                XCTAssertEqual(status, 126)
                XCTAssertEqual(recentOutput, ["steamcmd: operation not permitted"])
                XCTAssertEqual(
                    error.localizedDescription,
                    "SteamCMD exited with status 126. Recent output: steamcmd: operation not permitted"
                )
            default:
                XCTFail("Expected commandFailed, got \(error)")
            }
        }
    }

    private final class FakeProcessRunner: SteamCMDProcessRunning {
        struct RunCall {
            let executableURL: URL
            let arguments: [String]
            let currentDirectoryURL: URL?
            let environment: [String: String]?
        }

        private(set) var runCalls = [RunCall]()
        var terminationStatus: Int32
        var terminationStatuses: [Int32]?
        var onRun: ((URL, [String], (String) -> Void, [String: String]?) throws -> Void)?

        init(terminationStatus: Int32 = 0) {
            self.terminationStatus = terminationStatus
        }

        func run(
            executableURL: URL,
            arguments: [String],
            currentDirectoryURL: URL?,
            environment: [String: String]?,
            output: @escaping (String) -> Void
        ) async throws -> Int32 {
            runCalls.append(RunCall(
                executableURL: executableURL,
                arguments: arguments,
                currentDirectoryURL: currentDirectoryURL,
                environment: environment
            ))
            try onRun?(executableURL, arguments, output, environment)
            if terminationStatuses?.isEmpty == false {
                return terminationStatuses!.removeFirst()
            }
            return terminationStatus
        }
    }

    private final class FakeSecurityScopedAccess: SteamCMDSecurityScopedAccessing {
        private(set) var startedURLs = [URL]()
        private(set) var stoppedURLs = [URL]()
        var shouldStart = true

        func startAccessing(_ url: URL) -> Bool {
            startedURLs.append(url)
            return shouldStart
        }

        func stopAccessing(_ url: URL) {
            stoppedURLs.append(url)
        }
    }

    private final class RecordingSteamCMDClient: SteamCMDClient {
        let paths: SteamCMDPaths
        private(set) var clearLoginSessionCallCount = 0

        init(paths: SteamCMDPaths) {
            self.paths = paths
        }

        func installIfMissing(progress: @escaping (SteamCMDInstallState) -> Void) async throws -> SteamCMDRunnerResult {
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
            SteamCMDRunnerResult(
                runtimeURL: paths.steamCMDDirectory,
                downloadedItemURL: paths.workshopContentDirectory.appendingPathComponent(itemID, isDirectory: true),
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

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func repositoryRoot() -> URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while current.path != "/" {
            if FileManager.default.fileExists(
                atPath: current.appendingPathComponent("Open Wallpaper Engine.xcodeproj", isDirectory: true).path
            ) {
                return current
            }
            current.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }

    private func setQuarantineAttribute(on url: URL) throws {
        let value = Array("0086;00000000;Open Wallpaper Engine;".utf8)
        let result = value.withUnsafeBufferPointer { buffer in
            url.path.withCString { path in
                setxattr(path, "com.apple.quarantine", buffer.baseAddress, buffer.count, 0, 0)
            }
        }
        if result != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func hasQuarantineAttribute(at url: URL) -> Bool {
        let result = url.path.withCString { path in
            getxattr(path, "com.apple.quarantine", nil, 0, 0, 0)
        }
        return result >= 0
    }

    func testWorkshopSupportLinksToSteamWebAPIKeyPage() {
        XCTAssertEqual(
            SteamWorkshopSupport.webAPIKeyURL.absoluteString,
            "https://steamcommunity.com/dev/apikey"
        )
        XCTAssertEqual(
            SteamWorkshopSupport.wallpaperEngineWorkshopURL.absoluteString,
            "https://steamcommunity.com/app/431960/workshop/"
        )
    }

    func testWorkshopDownloadInputBuildsPasswordLoginWithoutPersistingPassword() throws {
        let request = try SteamWorkshopDownloadInput(
            itemInput: "https://steamcommunity.com/sharedfiles/filedetails/?id=3004222851",
            loginMode: .password,
            username: " alice ",
            password: " secret ",
            steamGuardCode: " 12345 "
        ).makeRequest()

        XCTAssertEqual(request.itemID, "3004222851")
        XCTAssertEqual(
            request.login,
            .account(username: "alice", password: "secret", steamGuardCode: "12345")
        )
    }

    func testWorkshopDownloadInputBuildsSavedSessionLoginWithoutPassword() throws {
        let request = try SteamWorkshopDownloadInput(
            itemInput: "3004222851",
            loginMode: .savedSession,
            username: " alice ",
            password: "",
            steamGuardCode: ""
        ).makeRequest()

        XCTAssertEqual(request.itemID, "3004222851")
        XCTAssertEqual(request.login, .savedSession(username: "alice"))
    }

    func testWorkshopDownloadInputBuildsAnonymousLoginExplicitly() throws {
        let request = try SteamWorkshopDownloadInput(
            itemInput: "3004222851",
            loginMode: .anonymous,
            username: "",
            password: "",
            steamGuardCode: ""
        ).makeRequest()

        XCTAssertEqual(request.itemID, "3004222851")
        XCTAssertEqual(request.login, .anonymous)
    }

    func testCachedKeychainCredentialStoreCachesLoadedString() throws {
        let key = KeychainCredentialKey(service: "service", account: "account")
        let backend = FakeKeychainCredentialBackend()
        backend.storage[key] = "secret"
        let store = CachedKeychainCredentialStore(backend: backend)

        XCTAssertEqual(try store.loadString(for: key), "secret")
        backend.storage[key] = "changed"

        XCTAssertEqual(try store.loadString(for: key), "secret")
        XCTAssertEqual(backend.loadCallCount(for: key), 1)
    }

    func testCachedKeychainCredentialStoreCachesMissingCredential() throws {
        let key = KeychainCredentialKey(service: "service", account: "missing")
        let backend = FakeKeychainCredentialBackend()
        let store = CachedKeychainCredentialStore(backend: backend)

        XCTAssertNil(try store.loadString(for: key))
        backend.storage[key] = "created-elsewhere"

        XCTAssertNil(try store.loadString(for: key))
        XCTAssertEqual(backend.loadCallCount(for: key), 1)
    }

    func testCachedKeychainCredentialStoreUpdatesCacheAfterSaveAndDelete() throws {
        let key = KeychainCredentialKey(service: "service", account: "mutable")
        let backend = FakeKeychainCredentialBackend()
        let store = CachedKeychainCredentialStore(backend: backend)

        try store.saveString("saved", for: key)

        XCTAssertEqual(try store.loadString(for: key), "saved")
        XCTAssertEqual(backend.storage[key], "saved")
        XCTAssertEqual(backend.loadCallCount(for: key), 0)

        try store.deleteString(for: key)

        XCTAssertNil(try store.loadString(for: key))
        XCTAssertNil(backend.storage[key])
        XCTAssertEqual(backend.loadCallCount(for: key), 0)
    }

    func testCachedKeychainCredentialStoreDoesNotCacheLoadFailures() throws {
        let key = KeychainCredentialKey(service: "service", account: "retry")
        let backend = FakeKeychainCredentialBackend()
        backend.loadErrors = [FakeKeychainCredentialError.loadFailed]
        let store = CachedKeychainCredentialStore(backend: backend)

        XCTAssertThrowsError(try store.loadString(for: key))
        backend.storage[key] = "recovered"

        XCTAssertEqual(try store.loadString(for: key), "recovered")
        XCTAssertEqual(backend.loadCallCount(for: key), 2)
    }

    private final class FakeKeychainCredentialBackend: KeychainCredentialBackend {
        var storage = [KeychainCredentialKey: String]()
        var loadErrors = [Error]()
        private var loadCallCounts = [KeychainCredentialKey: Int]()

        func loadString(for key: KeychainCredentialKey) throws -> String? {
            loadCallCounts[key, default: 0] += 1
            if !loadErrors.isEmpty {
                throw loadErrors.removeFirst()
            }
            return storage[key]
        }

        func saveString(_ string: String, for key: KeychainCredentialKey) throws {
            storage[key] = string
        }

        func deleteString(for key: KeychainCredentialKey) throws {
            storage[key] = nil
        }

        func loadCallCount(for key: KeychainCredentialKey) -> Int {
            loadCallCounts[key, default: 0]
        }
    }

    private enum FakeKeychainCredentialError: Error {
        case loadFailed
    }

    private final class FakeSteamWorkshopHTTPClient: SteamWorkshopHTTPClient {
        private var responses: [Data]
        private(set) var cursors = [String?]()
        private(set) var queryTypes = [Int]()
        private(set) var searchTexts = [String?]()
        private(set) var requiredTags = [String?]()
        private(set) var pageSizes = [Int]()
        private(set) var matchAllTags = [Bool?]()

        init(responses: [Data]) {
            self.responses = responses
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let url = try XCTUnwrap(request.url)
            let inputJSON = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "input_json" })?
                .value)
            let payload = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: Data(inputJSON.utf8)) as? [String: Any]
            )
            cursors.append(payload["cursor"] as? String)
            queryTypes.append(try XCTUnwrap(payload["query_type"] as? Int))
            searchTexts.append(payload["search_text"] as? String)
            requiredTags.append(payload["requiredtags"] as? String)
            pageSizes.append(try XCTUnwrap(payload["numperpage"] as? Int))
            matchAllTags.append(payload["match_all_tags"] as? Bool)
            return (
                responses.removeFirst(),
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
    }

    private static func workshopResponseJSON(nextCursor: String?, items: [String]) -> Data {
        """
        {
          "response": {
            "total": \(items.count),
            \(nextCursor.map { "\"next_cursor\": \"\($0)\"," } ?? "")
            "publishedfiledetails": [
              \(items.joined(separator: ","))
            ]
          }
        }
        """.data(using: .utf8)!
    }

    private static func workshopItemJSON(id: String, title: String, type: String, timeCreated: Int? = nil) -> String {
        """
        {
          "publishedfileid": "\(id)",
          "title": "\(title)",
          \(timeCreated.map { "\"time_created\": \($0)," } ?? "")
          "metadata": "{\\"type\\":\\"\(type)\\"}",
          "tags": [
            { "tag": "\(type)" }
          ]
        }
        """
    }

}
