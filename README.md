# Koan

A [Zen Browser](https://zen-browser.app)-style browser for macOS, built on **WebKit** — the same engine as Safari — instead of Firefox's Gecko. It's a native SwiftUI app wrapping `WKWebView`.

## Features

| Zen feature | In Koan |
| --- | --- |
| Vertical tabs | Sidebar with pinned tabs, a separator with **Clear** (closes unpinned tabs), and regular tabs. Drag to reorder, pin, or move between sections. |
| Workspaces | Each has its own name, emoji, gradient theme and tabs. Switch from the sidebar footer, `⌥⌘←/→` or `⌃⌥1…9`. Drop a tab on a workspace icon to move it there. |
| Essentials | A grid of favicon tiles at the top of the sidebar, shared by every workspace. |
| Pinned tabs | Remember their pinned page. `⌘W` resets and unloads them instead of closing, as in Zen. |
| Compact mode | `⌃⌘S` hides the sidebar; hover the left edge of the window to slide it back in. |
| Split view | `⌃⌘\` splits the current tab with the previous one. Up to 4 panes, draggable dividers, horizontal or vertical. |
| Glance | `⌥`-click a link to preview it in a floating panel; expand it to a tab or a split. `Esc` closes it. |
| Floating URL bar | `⌘T` / `⌘L` open a command bar that searches, opens addresses, switches to open tabs and offers history and live search suggestions. |
| Tab unloader | Idle tabs unload after a set time (Settings). Unloaded tabs are dimmed and keep their back/forward history. |

Also included: session restore (workspaces, tabs and back/forward history survive relaunch), find in page, page zoom, downloads to `~/Downloads`, reopening closed tabs, a choice of search engine, Web Inspector, JavaScript dialogs and file uploads, and support for being the default browser.

## Build and run

You need macOS 13 or later and Xcode 16 or later.

```sh
scripts/build-app.sh          # builds build/Koan.app (release)
open build/Koan.app
```

For quick iteration you can `swift run`. To edit in Xcode, open `Package.swift`. Run it as `Koan.app` to make it the default browser: Settings → Default Browser.

Every push is built by [GitHub Actions](.github/workflows/build.yml), and the zipped `Koan.app` is attached to the run as an artifact. It is ad-hoc signed, so the first time you open it, right-click the app and choose **Open**.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| New tab / open location | `⌘T` / `⌘L` |
| Close tab / reopen closed tab | `⌘W` / `⇧⌘T` |
| Next / previous tab | `⌃⇥` / `⌃⇧⇥` |
| Go to tab 1–8 / last tab | `⌘1…8` / `⌘9` |
| Pin or unpin tab | `⇧⌘D` |
| Compact mode | `⌃⌘S` |
| Split view | `⌃⌘\` |
| Glance | `⌥`-click a link |
| Open link in background / foreground tab | `⌘`-click / `⇧⌘`-click |
| New workspace | `⌃⌘N` |
| Next / previous workspace | `⌥⌘→` / `⌥⌘←` |
| Find / next / previous | `⌘F` / `⌘G` / `⇧⌘G` |
| Back / forward / reload | `⌘[` / `⌘]` / `⌘R` |
| Zoom in / out / actual size | `⌘=` / `⌘-` / `⌘0` |

## Code layout

```
Sources/Koan/
  App/        App entry, app delegate, menu commands
  Models/     BrowserStore (all browser state and actions), Workspace,
              session/history persistence, favicon cache
  Web/        BrowserTab (WKWebView owner and navigation/UI delegate),
              KoanWebView, downloads
  Views/      Window layout, sidebar, content panes and split view,
              command bar, Glance, settings
```

Each `BrowserTab` owns its `WKWebView`. Switching tabs moves that view into the visible pane and never reloads the page. Unloading a tab keeps WebKit's `interactionState`, so its history comes back when it reloads.

## Not yet included

Things Zen has that Koan doesn't yet: extensions, multiple windows, private windows, content blocking, and custom CSS mods.
