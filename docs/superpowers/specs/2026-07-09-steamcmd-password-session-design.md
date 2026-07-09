# SteamCMD Password Login With Automatic Session Reuse

## Context

The Workshop download UI currently exposes Password Login and Saved Session as separate login modes. This makes the user choose between implementation details and creates a fragile path where `+login <username>` can be selected without a valid SteamCMD runtime session.

SteamCMD already persists successful logins in its runtime files. The app should use that persistence internally, while keeping the user-facing model simple: one Steam login flow, with password and Steam Guard code entered only when needed.

## Goals

- Remove Saved Session as a user-facing Workshop download mode.
- Keep Password Login as the only visible login flow.
- Do not save Steam password or Steam Guard code.
- Save only the last successful username.
- Reuse SteamCMD's persisted runtime login automatically across app launches.
- If the persisted login is invalid or Steam Guard is required again, ask the user to re-enter password and Steam Guard code.
- Keep the Settings page action that clears SteamCMD login/session files.

## Non-Goals

- Do not add anonymous Workshop download back to the UI.
- Do not implement app-owned session tokens.
- Do not store password, Steam Guard code, or Steam cookies in Keychain/UserDefaults.
- Do not clear SteamCMD login state automatically on app exit.
- Do not change SteamCMD install, repair, or Workshop API browse behavior.

## User Experience

Workshop download controls show username, password, optional Steam Guard code, and download actions. There is no login mode segmented control.

On first use, the user enters username and password, plus Steam Guard code if SteamCMD asks for it. After a successful login or download, the app clears password and Steam Guard code from memory and stores the username.

On later downloads, including after app restart, if the password field is empty and the app sees a saved username plus SteamCMD login-state files, it first tries the internal reuse path. If SteamCMD accepts the stored runtime session, the download proceeds without asking for a password.

If reuse fails because SteamCMD reports Steam Guard, login failure, or session-related command failure, the app marks the runtime session invalid for the current app process and shows a clear message asking the user to enter password and Steam Guard code again.

## Architecture

`SteamWorkshopLoginMode` is removed from the Workshop UI/input layer. `SteamWorkshopDownloadInput` builds only password-login requests and validates username/password when no reusable runtime session is available.

The low-level `SteamCMDLogin.savedSession(username:)` command shape may remain as an internal runner mechanism because it maps directly to `steamcmd +login <username>`. It must not be exposed as a user-selectable Workshop download mode.

`SteamWorkshopBrowserViewModel` owns a small session state:

- `unknown`: startup/default state.
- `reusable(username)`: there is a stored username and SteamCMD runtime login indicators.
- `invalid`: reuse failed during this app process; require password until a password login succeeds.

On init and after SteamCMD install/repair/reset, the ViewModel refreshes this state from `SteamCMDService.hasSavedLoginSession()` and the saved username.

## Download Flow

1. Parse the Workshop item ID.
2. If the user entered a password, call SteamCMD with `+login <username> <password> [steamGuardCode]`.
3. If the password is empty and session state is `reusable(username)`, call SteamCMD internally with `+login <username>`.
4. If neither path is available, show a password-required error.
5. On login success or successful download, save the username, clear password/Steam Guard fields, and mark the session reusable when runtime login indicators exist.
6. On SteamCMD download failure output, preserve the existing item-specific failure behavior.
7. On login/session failure output, mark the session invalid and ask for password/Steam Guard.
8. On successful item output, use the actual `Success. Downloaded item ... to "<path>"` directory and verify folder/project availability as already designed.

## Error Handling

Add or reuse parser support for login/session failures, including Steam Guard required, login failure, and command failure output that clearly indicates authentication failure.

Download-item failures remain distinct from authentication failures. A Workshop item failing to download should not automatically invalidate the SteamCMD login session unless SteamCMD output also indicates authentication failure.

The user-facing messages should be specific:

- No reusable session and no password: ask for Steam password.
- Reused session expired: ask for password and Steam Guard code.
- Steam Guard required during password login: ask for the current 2FA code and retry.
- Download item failed: show SteamCMD's real recent output.

## Tests

- UI/input tests assert Saved Session is no longer exposed and the login mode picker is gone.
- Request tests assert password login still generates `+login username password [steamGuardCode]`.
- ViewModel tests cover automatic reuse when saved username and runtime login indicators exist.
- ViewModel tests cover no password and no reusable session showing a password-required error without calling SteamCMD.
- ViewModel tests cover reuse failure marking the session invalid and prompting for password/Steam Guard.
- ViewModel tests cover password login success saving username and enabling future automatic reuse.
- Existing runner tests continue to cover actual downloaded directory parsing and item failure output.
- Build verification runs `xcodebuild -project "Open Wallpaper Engine.xcodeproj" -scheme "Open Wallpaper Engine" -derivedDataPath DerivedData build`.

