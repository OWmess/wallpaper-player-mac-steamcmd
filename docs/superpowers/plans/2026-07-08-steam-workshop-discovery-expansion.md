# Steam Workshop Discovery Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand Workshop browsing so the app fetches many more playable Wallpaper Engine Video/Web items by using correct Steam query types, cursor pagination, typed Video/Web streams, and local deduplication.

**Architecture:** `WEProject.swift` owns Steam API request/response contracts. `WallpaperDiscover.swift` owns Workshop browser state, typed cursor streams, result merging, page caching, and UI-facing status. `Open_Wallpaper_EngineTests.swift` drives the change with API payload tests and view-model fetch tests.

**Tech Stack:** Swift, SwiftUI/AppKit, Foundation `URLSession`, XCTest, Steam `IPublishedFileService/QueryFiles/v1/`.

## Global Constraints

- Do not support `scene`, `application`, or other Wallpaper Engine project types in this change.
- Do not change SteamCMD install, SteamCMD download command behavior, account login, Steam Guard, or runtime setup.
- Keep local `SteamWorkshopItem.isSupportedByCurrentPlayer` filtering even when server-side tags are used.
- Use cursor pagination with `"*"` for the first Steam request and `next_cursor` for later requests.
- UI page size remains `36`; raw Steam fetch batch size is `100`.
- Query Video and Web as separate single-tag streams, then merge locally.
- Preserve current Workshop browser UI shape: browse, previous page, next page, selection, download, open in Steam.
- The working tree already contains uncommitted changes in implementation files. Before each commit, run `git diff --cached --name-only` and `git diff --cached` and stage only hunks belonging to the current task. Use `git add -p` for files that contain unrelated pre-existing hunks.

---

## File Structure

- `Open Wallpaper Engine/Services/WEProject.swift`
  - Extend Steam API query request fields.
  - Correct Steam query type values.
  - Decode `time_created` for ordering.
- `Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift`
  - Replace single cursor fetch state with typed Video/Web browse session.
  - Keep UI page cache and pagination controls.
- `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`
  - Add payload tests for request fields and sort mappings.
  - Add browser view-model tests for typed streams, deduplication, pagination, and stable query context.

---

### Task 1: Steam Workshop API Request Contract

**Files:**
- Modify: `Open Wallpaper Engine/Services/WEProject.swift`
- Modify: `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`

**Interfaces:**
- Consumes: existing `SteamWorkshopAPIService.makeQueryRequest(apiKey:query:)`
- Produces:
  - `SteamWorkshopItem.timeCreated: Int?`
  - `SteamWorkshopQuery.init(sort:searchText:cursor:pageSize:creatorAppID:requiredTag:matchAllTags:days:)`
  - `SteamWorkshopQuery.Sort.queryType` values `9`, `3`, `1`, `12`
  - Request payload fields `creator_appid`, `requiredtags`, `match_all_tags`, `days`, and normalized `cursor`

- [ ] **Step 1: Write failing response decoding test**

In `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`, update `testWorkshopQueryFilesResponseDecodesPreviewTagsMetadataAndStats` so the JSON item includes `time_created`, and add the assertion shown here.

```swift
"time_created": 1700000000,
```

```swift
XCTAssertEqual(item.timeCreated, 1_700_000_000)
```

- [ ] **Step 2: Write failing request payload test**

Replace `testWorkshopQueryRequestUsesSteamAPIKeyAndInputJSON` with this version.

```swift
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
```

- [ ] **Step 3: Write failing sort and trending payload tests**

Add these tests next to the request payload tests.

```swift
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
```

- [ ] **Step 4: Update search payload test expectation**

In `testWorkshopSearchRequestIncludesSearchTextAndQueryType`, keep the existing request shape and change the expected query type to the corrected value.

```swift
XCTAssertEqual(payload["query_type"] as? Int, 12)
XCTAssertEqual(payload["search_text"] as? String, "city rain")
XCTAssertEqual(payload["cursor"] as? String, "AoIIPw==")
```

- [ ] **Step 5: Run focused tests to verify failure**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -derivedDataPath DerivedData test -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopQueryFilesResponseDecodesPreviewTagsMetadataAndStats -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopQueryRequestUsesSteamAPIKeyAndInputJSON -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopSortQueryTypesMatchSteamPublishedFileQueryTypeValues -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopTrendingRequestIncludesDefaultDays -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopSearchRequestIncludesSearchTextAndQueryType
```

Expected: FAIL because `timeCreated`, `requiredTag`, corrected query type values, `creator_appid`, `days`, and normalized cursor are not implemented yet.

- [ ] **Step 6: Implement Steam response and query model**

In `Open Wallpaper Engine/Services/WEProject.swift`, update `SteamWorkshopItem` by adding `timeCreated`, a coding key, and decode assignment.

```swift
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
}
```

Update `SteamWorkshopQuery` with the new request fields and corrected mappings.

```swift
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
```

- [ ] **Step 7: Implement request payload encoding**

Replace `SteamWorkshopQueryRequestPayload` with this version.

```swift
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
```

- [ ] **Step 8: Run focused tests to verify pass**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -derivedDataPath DerivedData test -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopQueryFilesResponseDecodesPreviewTagsMetadataAndStats -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopQueryRequestUsesSteamAPIKeyAndInputJSON -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopSortQueryTypesMatchSteamPublishedFileQueryTypeValues -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopTrendingRequestIncludesDefaultDays -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopSearchRequestIncludesSearchTextAndQueryType
```

Expected: PASS.

- [ ] **Step 9: Commit Task 1**

Run:

```bash
git add -p "Open Wallpaper Engine/Services/WEProject.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git diff --cached --name-only
git diff --cached
git commit -m "App: fix Steam Workshop query request"
```

Expected staged files:

```text
Open Wallpaper Engine/Services/WEProject.swift
Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift
```

---

### Task 2: Typed Video/Web Browse Session

**Files:**
- Modify: `Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift`
- Modify: `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`

**Interfaces:**
- Consumes:
  - `SteamWorkshopQuery(requiredTag:cursor:pageSize:)` from Task 1
  - `SteamWorkshopItem.timeCreated`
- Produces:
  - `WorkshopBrowseStream`
  - `WorkshopBrowseSession`
  - `SteamWorkshopBrowserViewModel.fetchPage(apiKey:session:)`
  - `SteamWorkshopBrowserViewModel.canLoadNextPage` based on cached pages and active session state

- [ ] **Step 1: Extend fake HTTP client observability**

In `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`, update `FakeSteamWorkshopHTTPClient` to record required tags, page sizes, and match mode.

```swift
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
```

- [ ] **Step 2: Replace single-stream browser tests with typed-stream tests**

Replace `testWorkshopBrowserPagesThroughCursorResultsAndCachesPreviousPages` with this typed-stream equivalent.

```swift
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
```

Replace `testWorkshopBrowserFillsDisplayedPageFromMultipleSteamCursorPages` with this typed cursor-round test.

```swift
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
```

- [ ] **Step 3: Add stable context test for typed streams**

Replace `testWorkshopBrowserKeepsBrowseQueryStableWhenLoadingNextPage` with this version.

```swift
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
```

- [ ] **Step 4: Run focused browser tests to verify failure**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -derivedDataPath DerivedData test -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserRequestsVideoAndWebStreamsAndDeduplicatesResults -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserFillsDisplayedPageFromMultipleTypedCursorRounds -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserKeepsBrowseQueryStableWhenLoadingNextPage
```

Expected: FAIL because the browser still has one stream and does not request `Video` and `Web` separately.

- [ ] **Step 5: Add typed browse session structs**

In `Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift`, replace the current `WorkshopBrowsePage` and keep `WorkshopBrowseQueryContext`, then add these private structs above `WallpaperDiscover`.

```swift
private struct WorkshopBrowsePage {
    var items: [SteamWorkshopItem]
}

private struct WorkshopBrowseStream {
    let requiredTag: String
    var nextCursor = "*"
    var isExhausted = false
    var bufferedItems = [SteamWorkshopItem]()

    var canFetch: Bool {
        !isExhausted
    }
}

private struct WorkshopBrowseSession {
    var queryContext: WorkshopBrowseQueryContext
    var streams = [
        WorkshopBrowseStream(requiredTag: "Video"),
        WorkshopBrowseStream(requiredTag: "Web")
    ]
    var seenItemIDs = Set<String>()
    var nextInterleavedStreamIndex = 0

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
            streams[index].bufferedItems.append(item)
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
                switch (left.timeCreated, right.timeCreated) {
                case let (leftTime?, rightTime?):
                    return leftTime > rightTime
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return left.id < right.id
                }
            }
            .prefix(limit)
        let selectedIDs = Set(selected.map(\.id))
        for index in streams.indices {
            streams[index].bufferedItems.removeAll { selectedIDs.contains($0.id) }
        }
        return Array(selected)
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
                pageItems.append(streams[index].bufferedItems.removeFirst())
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
```

- [ ] **Step 6: Replace view-model fetch state and methods**

In `SteamWorkshopBrowserViewModel`, keep `displayedPageSize = 36` and add `steamBatchSize = 100`. Replace `activeQueryContext` with `activeSession`.

```swift
private static let displayedPageSize = 36
private static let steamBatchSize = 100
```

```swift
private var pages = [WorkshopBrowsePage]()
private var currentPageIndex = -1
private var activeSession: WorkshopBrowseSession?
```

Update `canLoadNextPage`.

```swift
var canLoadNextPage: Bool {
    guard currentPageIndex >= 0 else { return false }
    return currentPageIndex + 1 < pages.count || activeSession?.canLoadMore == true
}
```

Replace `browse`, `loadNextPage`, and `fetchPage` with these implementations.

```swift
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
```

- [ ] **Step 7: Run focused browser tests to verify pass**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -derivedDataPath DerivedData test -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserRequestsVideoAndWebStreamsAndDeduplicatesResults -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserFillsDisplayedPageFromMultipleTypedCursorRounds -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserKeepsBrowseQueryStableWhenLoadingNextPage
```

Expected: PASS.

- [ ] **Step 8: Commit Task 2**

Run:

```bash
git add -p "Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git diff --cached --name-only
git diff --cached
git commit -m "App: browse Workshop video and web streams"
```

Expected staged files:

```text
Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift
Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift
```

---

### Task 3: Pagination Exhaustion and Latest Ordering

**Files:**
- Modify: `Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift`
- Modify: `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`

**Interfaces:**
- Consumes:
  - `WorkshopBrowseSession.takePageItems(limit:)`
  - `SteamWorkshopItem.timeCreated`
- Produces:
  - Correct final-page `canLoadNextPage == false`
  - Latest pages sorted by `timeCreated` across typed stream buffers

- [ ] **Step 1: Add final-page exhaustion test**

Add this test near the other browser tests.

```swift
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
```

- [ ] **Step 2: Add latest ordering test**

Add a helper that includes `time_created`.

```swift
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
```

Add this test.

```swift
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
```

- [ ] **Step 3: Run focused tests to verify current behavior**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -derivedDataPath DerivedData test -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserDisablesNextPageAfterFinalPartialTypedPage -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserSortsLatestMergedPageByTimeCreated
```

Expected: PASS if Task 2 implementation already covered exhaustion and latest ordering. If `workshopItemJSON` still has the old signature, compile fails until the helper replacement in Step 2 is applied.

- [ ] **Step 4: Make minimal implementation adjustment if focused tests fail**

If the final-page test fails because status was not updated, ensure `browse()` calls `updateStatusForCurrentPage()` after `showPage(at: 0)` and `loadNextPage()` calls it after showing appended pages.

```swift
showPage(at: 0)
updateStatusForCurrentPage()
```

```swift
pages.append(result.page)
showPage(at: pages.count - 1)
updateStatusForCurrentPage()
```

If the latest ordering test fails, ensure `takePageItems(limit:)` dispatches to `takeLatestPageItems(limit:)` when the active query context sort is `.latest`.

```swift
mutating func takePageItems(limit: Int) -> [SteamWorkshopItem] {
    if queryContext.sort == .latest {
        return takeLatestPageItems(limit: limit)
    }
    return takeInterleavedPageItems(limit: limit)
}
```

- [ ] **Step 5: Run focused tests to verify pass**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -derivedDataPath DerivedData test -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserDisablesNextPageAfterFinalPartialTypedPage -only-testing:Open_Wallpaper_EngineTests/Open_Wallpaper_EngineTests/testWorkshopBrowserSortsLatestMergedPageByTimeCreated
```

Expected: PASS.

- [ ] **Step 6: Commit Task 3**

Run:

```bash
git add -p "Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git diff --cached --name-only
git diff --cached
git commit -m "App: finish Workshop pagination merge behavior"
```

Expected staged files:

```text
Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift
Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift
```

---

### Task 4: Regression Verification

**Files:**
- Modify: no source files
- Test: `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`

**Interfaces:**
- Consumes all implementations from Tasks 1-3.
- Produces verified app build and test status.

- [ ] **Step 1: Run full test target**

Run:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -derivedDataPath DerivedData test
```

Expected: PASS for unit and UI tests in the scheme. If UI tests fail because the local macOS environment cannot launch the app, capture the exact failure and rerun the unit-test-only subset if the scheme exposes it in Xcode.

- [ ] **Step 2: Run build-only verification if full test cannot complete**

Run this command only if Step 1 cannot complete due to a local UI-test launch or signing environment issue:

```bash
xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -derivedDataPath DerivedData build
```

Expected: PASS.

- [ ] **Step 3: Inspect final diff**

Run:

```bash
git status --short
git diff -- "Open Wallpaper Engine/Services/WEProject.swift" "Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
```

Expected:

- Remaining unstaged hunks are either intentionally uncommitted pre-existing user changes or the completed implementation ready for final commit.
- No SteamCMD download-command behavior changed.
- No unrelated docs package or localization changes are introduced by this implementation.

- [ ] **Step 4: Commit verification cleanup only if there are implementation hunks left**

Run this only if Task 4 finds small implementation hunks that were not committed by Tasks 1-3:

```bash
git add -p "Open Wallpaper Engine/Services/WEProject.swift" "Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift" "Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift"
git diff --cached --name-only
git diff --cached
git commit -m "App: verify Workshop discovery expansion"
```

Expected staged files are limited to the three implementation files from this plan.

---

## Self-Review

- Spec coverage: Task 1 covers corrected query types, cursor `"*"`, request fields, tags, trending days, and `time_created`. Task 2 covers Video/Web streams, dedupe, UI page filling, page caching, and stable browse context. Task 3 covers final exhaustion and latest merged ordering. Task 4 covers verification.
- Placeholder scan: no deferred-work markers or generic edge-case instructions remain. Each code-changing step includes concrete Swift or shell content.
- Type consistency: `requiredTag`, `WorkshopBrowseSession`, `WorkshopBrowseStream`, `WorkshopBrowseFetchResult`, `timeCreated`, `steamBatchSize`, and `fetchPage(apiKey:session:)` use the same names across tests and implementation steps.
