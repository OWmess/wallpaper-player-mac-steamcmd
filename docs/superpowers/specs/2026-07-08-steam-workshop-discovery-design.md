# Steam Workshop Discovery Result Expansion Design

## Context

The Workshop browser currently calls `IPublishedFileService/QueryFiles/v1/` through
`SteamWorkshopAPIService.makeQueryRequest`. The request uses `input_json`, which is
the correct Steam service-interface shape, but the browser returns very few usable
Wallpaper Engine items.

The current code has three result-reducing issues:

- `SteamWorkshopQuery.Sort.popular` maps to `12`, which is Steam text search, and
  `search` maps to `11`, which is ranked by up votes. Search and popular are
  effectively swapped into the wrong API modes.
- Initial browse calls omit `cursor`. Steam documents cursor pagination as starting
  with `"*"`, then continuing with the returned `next_cursor`.
- The app requests an unfiltered Workshop page and filters locally to `video` and
  `web`. Wallpaper Engine has many unsupported `scene` and `application` items, so
  one Steam page can collapse into only a few playable items.

There are already local uncommitted changes that add UI page caching and cursor
pagination. This design builds on that direction but changes the fetch model to a
complete enhancement: query supported Workshop types separately, merge them, and
let UI pages consume from a playable result pool.

## Goals

- Show substantially more playable Workshop results in the app.
- Keep the visible browser behavior simple: browse, previous page, next page,
  selection, download, and open in Steam.
- Use Steam API pagination correctly with cursor-first requests.
- Preserve local `video` / `web` validation as a safety net.
- Avoid touching SteamCMD download behavior, import behavior, or unrelated app UI.

## Non-Goals

- Supporting `scene`, `application`, or other Wallpaper Engine project types.
- Perfect global ranking across separately filtered Steam tag queries.
- Replacing Steam Web API with Steam community scraping.
- Changing account login, Steam Guard, or SteamCMD runtime setup.

## API Request Design

Extend `SteamWorkshopQuery` with the fields needed for server-side filtering:

- `creatorAppID: Int = 431960`
- `requiredTag: String?`
- `matchAllTags: Bool = true`
- `days: Int?` for trending queries, defaulting to `7` when `sort == .trending`
- `cursor: String?`, normalized to `"*"` for an initial cursor request
- `pageSize: Int`, with raw Steam fetches using a larger batch size than the UI
  page size

Fix `SteamWorkshopQuery.Sort.queryType` to match Steam's documented
`EPublishedFileQueryType` values:

- `popular` -> `9` (`RankedByTotalUniqueSubscriptions`)
- `trending` -> `3` (`RankedByTrend`)
- `latest` -> `1` (`RankedByPublicationDate`)
- `search` -> `12` (`RankedByTextSearch`)

The request payload will include:

- `appid = 431960`
- `creator_appid = 431960`
- `query_type`
- `cursor`
- `numperpage`
- `requiredtags`, encoded as one tag string per typed stream request
- `match_all_tags`
- `search_text` only when non-empty
- `days` only for trending
- existing detail flags: metadata, previews, tags, vote data

The complete enhancement deliberately avoids multi-tag OR encoding. Video and Web
are requested as independent single-tag streams, then merged locally.

## Browser Fetch Design

Replace the single cursor chain with two typed fetch streams:

- Video stream: `requiredTag = "Video"`
- Web stream: `requiredTag = "Web"`

Each stream stores:

- tag
- next cursor, initially `"*"`
- exhaustion state
- buffered playable items

The browser owns a `WorkshopBrowseSession` for the active sort and search text.
Changing sort or search creates a new session and clears UI pages. Loading the
next UI page asks the session to fill a playable pool until it has enough items or
all streams are exhausted.

Fetch loop:

1. Ask each non-exhausted stream for one Steam batch, alternating streams to avoid
   one type starving the other.
2. Filter returned items with `isSupportedByCurrentPlayer`.
3. Deduplicate by `publishedfileid` across both streams.
4. Append unique playable items to the session pool.
5. Stop when the next UI page can be filled or all streams are exhausted.

The UI page size remains `36`. Steam batch size should be larger, for example
`100`, so the app does not need excessive network round trips when a tag has a few
duplicates or unsupported items.

## Merge and Ordering

The full enhancement uses separate Steam result streams, so exact global ordering
is not guaranteed by the API. The app will make this explicit in the code model:

- Add optional `timeCreated` decoding from Steam's `time_created` field.
- For `latest`, merge by `timeCreated` descending when both items have it;
  otherwise preserve stream arrival order.
- For `popular` and `trending`, interleave Video and Web stream results while each
  stream remains sorted by Steam.
- For `search`, interleave typed search results and rely on Steam's ranking within
  each tag stream.

This gives users broad, playable coverage without pretending the merged list is a
single perfect global rank.

## UI Behavior

Keep the existing Workshop list and detail layout. The pagination bar continues to
show the current UI page number and previous/next controls.

Status messages should describe the new behavior without exposing implementation
noise:

- Success: `Loaded page N with X playable Workshop items.`
- Empty after all streams exhaust: `No playable Video/Web Workshop items found.`
- Partial final page: same success text with the actual item count.
- Errors: keep the localized error from the thrown request failure.

The `Next` button is enabled when there is a cached next page or at least one
active stream that can fetch more results.

## Error Handling

- If one stream fails with a network or decoding error, fail the browse operation
  and show the error. Silent partial success could hide real API breakage.
- Treat missing or empty `next_cursor` as stream exhaustion.
- Break loops if Steam returns the same cursor twice.
- Keep local `isSupportedByCurrentPlayer` filtering even when server-side tags are
  used, because Workshop metadata and tags are user-controlled.

## Tests

Add unit coverage for:

- Correct `query_type` values for popular, trending, latest, and search.
- Initial cursor encoding as `"*"`.
- `creator_appid`, `requiredtags`, `match_all_tags`, and trending `days`.
- Typed Video/Web streams both requested for a browse.
- Deduplication when the same `publishedfileid` appears in both streams.
- Filling one 36-item UI page from multiple Steam batches.
- Stable active search/sort context when loading later pages.
- Exhaustion handling when one stream ends before the other.
- Existing download and SteamCMD tests remain unchanged.

## Implementation Boundaries

Expected files:

- `Open Wallpaper Engine/Services/WEProject.swift`
- `Open Wallpaper Engine/ContentView/Components/WallpaperDiscover.swift`
- `Open Wallpaper EngineTests/Open_Wallpaper_EngineTests.swift`

Do not change:

- SteamCMD install or download command behavior.
- Keychain credential storage unless tests require injection already present in the
  current working tree.
- Documentation package targets.

## Rollout

The change is local to the Workshop browser. It can ship behind the existing
Workshop tab without a feature flag because it preserves the current UI contract
and only improves the result source.
