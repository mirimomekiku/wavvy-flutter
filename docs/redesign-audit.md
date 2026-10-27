# Wavvy: application audit and redesign brief

Audit date: 2026-10-27. Scope: understand the current working tree and prepare an all-screen redesign inspired by the two supplied Pastel Player images. No application implementation changes are included.

## Evidence and limits

- The current working tree is the baseline. It contains substantial modified, added, and deleted files from an existing UI/navigation refactor. Do not reset these changes or reconstruct screens from HEAD.
- Reviewed application startup, navigation, current screen implementations, shared widgets, theme generation, provider responsibilities, Android integration, persistence, assets, and existing tests.
- `flutter test --no-pub --reporter compact`: **194 tests passed**.
- `flutter analyze --no-pub`: **11 informational findings**, no warnings or errors. The command exits 1 because findings remain. Findings: three unnecessary nullable declarations, six empty catch blocks in audio effects, and two deprecated sharing API uses in the lyric-card screen.
- Existing `screenshots/*.jpg` show an older interface. For example, `home.jpg` shows a song list and two navigation items, while current source defines a feed and three tabs. They are historical evidence, not current visual acceptance baselines.
- No new APK was built or installed, and no live app walkthrough was performed. Tests use fake providers/platform responses; passing tests does not establish real playback, network, storage, or native-effects behavior.
- The supplied [Microsoft Store listing](https://apps.microsoft.com/detail/9np90smmvzpb?hl=en-US&gl=PH) could not be retrieved by the web tool. Reference analysis below is based on the two supplied images; additional Store claims are unverified.

## Product and architecture

Wavvy is an offline-first Android music player with optional online enrichment and downloads. It is not currently a desktop player: the checkout includes an Android platform project, uses Android media queries and audio effects, and has Android-specific public-storage handling. The Windows reference supplies visual direction, not a platform migration requirement.

| Layer | Current ownership | Redesign implication |
| --- | --- | --- |
| Startup | `lib/main.dart`: downloader callback, metadata plugin, audio session/service, provider overrides, saved settings | Keep native initialization separate from visual work; startup failure currently uses a plain Material error screen |
| App/theme | `lib/wavvy_app.dart`, `lib/theme/wavvy_theme.dart` | Central point for typography, Material defaults, app-wide schemes, transitions, and system brightness |
| Design system | `lib/theme/wavvy_widgets.dart` | Palette extension, shape/motion constants, buttons, switches, chips, panels, artwork frames, grouped settings |
| Pixel visuals | `lib/theme/pixel_art.dart` | Existing mascot variants, sprites, deterministic fallback covers, loaders, equalizer animation, progress, wavy slider, stepped border |
| Shell/navigation | `home.screen.dart`, `bottom_bar.dart`, `core/navigation.dart`, `core/app_context.dart` | Home/Library/Search tabs; detail pages pushed onto Navigator; player opens as a modal bottom sheet |
| Playback | `player_provider.dart`, `audio_handler.instance.dart` | Queue/source ownership, transport, shuffle/repeat, duration/position, notification metadata and background service |
| Coordination | `audio_coordinator.dart` | Track-change enrichment, palette extraction, play logging, lyrics synchronization, shake gesture, effects-session initialization, library reload on resume |
| Library/feed | `library_provider.dart`, `home_feed_provider.dart`, `library_section_provider.dart` | Device songs/albums/artists, permissions, sorting, derived local recommendations and selected library section |
| Persistence | `db/db.dart`, `playlists_provider.dart`, `settings_provider.dart` | SQLite v3 playlists/membership/history; SharedPreferences feature flags and appearance |
| Online content | `lyrics_provider.dart`, `artist_info_provider.dart`, `downloads_provider.dart` | LRCLib lyrics, Genius biography/images, YouTube audio and TikTok video fetching/download tasks |
| Native effects | `audio_effects_provider.dart`, Android `MainActivity.kt` | just_audio equalizer plus Kotlin bass boost, virtualizer and reverb channel |

The provider split is useful for a redesign: presentation can change while keeping the audio engine, database, permissions, and background behavior intact. Providers still invoke snackbars in some paths, and palette code consults global app context; they are not entirely presentation-independent.

## Complete presentation inventory

Treat each tab, detail view, overlay, and meaningful state as a redesign surface, even when several share a Dart file.

| Surface | Current content and behavior | Main source |
| --- | --- | --- |
| Application shell | Three retained tabs, safe areas, Android system colors, persistent mini-player and bottom navigation | `screens/home/home.screen.dart`, `widgets/bottom_bar.dart` |
| Home | Time-based greeting/settings entry, quick access, recently played, recent albums, top artists, more from artist, daily mix, discover, most played, recently added, playlists | `screens/home/view/home_view.dart` |
| Home without music | Mascot, empty-library or storage-permission explanation and recovery actions | same |
| Library: Songs | Pinned section chips, Title/Artist/Recently added sorting, current-song indication, rows and song actions | `screens/library/library_tab.dart` |
| Library: Albums | Responsive cover grid, album title/artist, album detail navigation | same |
| Library: Artists | Artist grid, counts, artist detail navigation | same |
| Library: Playlists | Playlist grid, new-playlist action, long-press delete; membership count | same |
| Library empty states | Separate no-songs/denied-storage recovery, no albums/artists/playlists messages | same |
| Album detail | Artwork header, album/artist metadata, play/shuffle, track list, mini-player | `screens/library/albums/view/album.screen.dart` |
| Artist detail | Artist header, album count, play/shuffle, track list, mini-player | `screens/library/artists/view/artist.screen.dart` |
| Playlist detail | Playlist artwork/header, count, play/shuffle, loading/empty state, remove-song action, mini-player | `screens/library/playlists/view/playlist.screen.dart` |
| Search: Library | Live local title/artist/album matching; grouped songs, albums and artists; prompt/no-results states | `screens/search/search_tab.dart`, `library_results.dart` |
| Search: YouTube | Submit query, video results, download/stream selection entry | `screens/search/youtube_results.dart` |
| Search: TikTok | Paste link, fetch preview, download video, loading/empty behavior | `screens/search/tiktok_panel.dart` |
| Search: Downloads | Combined task history, percentages/status, open completed files, deletion | `screens/search/downloads_list.dart` |
| Mini-player | Artwork/fallback, song/artist, play/pause, next, pixel progress; tap to expand | `widgets/bottom_bar.dart` |
| Full player: Player | Artwork with optional double-tap +/-10s seeking, title/artist, seek/time, transport, shuffle/repeat | `player_sheets/full_player_sheet.dart`, `widgets/seekable_artwork.dart` |
| Full player: Queue | Current-item highlight, follow-current scrolling, jump to selected queue item | `player_sheets/full_player_sheet.dart` |
| Full player: Lyrics | Loading/error/empty/content states, synchronized highlighting/scrolling, lyric-card entry | same |
| Full player: Artist | Biography/image, loading/fallback; tab visibility controlled by settings | same |
| Share lyrics | Select lyric lines, preview generated artwork card, share exported image | `widgets/lyric_card.dart` |
| Audio Control: Equalizer | Equalizer bands, gain controls, presets and reset/state feedback | `screens/audio_effects/effects.screen.dart` |
| Audio Control: Effects | Bass Boost and Virtualizer controls, reset; reset also clears reverb | same |
| Settings | Appearance selector; double-tap seek, shake skip, dynamic colors, dark mode, lyrics, artist info, stats, incognito, downloader | `screens/settings/settings.screen.dart`, `widgets/theme_selector.dart` |
| Startup failure | Plain text failure fallback when audio initialization fails | `main.dart` |

### Dialogs, sheets, and feedback

- Song action sheet: play next, add to queue, add to playlist, go to album/artist, share, sleep timer, edit tags, delete. Full-player menu additionally exposes custom/system equalizer and song info. Options vary by context.
- Playlist creation dialog, playlist deletion confirmation, remove-song confirmation, add-to-playlist selection sheet.
- Metadata editor: title, artist, album, year, genre; writes metadata while retaining artwork/other fields and refreshes library/player copies.
- Song/file details dialogs. Similar details UI exists in both song-menu and player-dialog helpers.
- Sleep timer picker: 15, 30, 45, 60, 90 minutes, cancel timer.
- YouTube stream-fetch/loading dialog and bitrate/format selection dialog.
- YouTube and TikTok downloaded-file deletion confirmations.
- Common confirmations, dialog actions, snackbars, progress, tooltips, and system-bar colors.
- Native permission prompts, system equalizer, file opening, sharing chooser, and notification controls are OS-owned surfaces. Align app entry/exit states; they cannot be fully skinned by Flutter theme changes.

## Behavior and data to preserve

- Playback queue order, context-list playback, play-next insertion, queue append, shuffle, repeat, seeking and background notification controls.
- Opening the mini-player resets the full-player tab to Player in the tap handler, avoiding provider writes during widget construction. Preserve this tested behavior.
- Home is derived from device music and local history. Daily mix/discover are local selections, not remote recommendations. Incognito suppresses recording new plays; Show Stats controls display of history-based sections.
- Track changes debounce palette/enrichment work; lyrics and artist requests have stale-response protection. Position ticks drive lyric synchronization and listening-history thresholds.
- Library scanning handles runtime storage/audio permission and resumes silently after returning to the app. Empty and denied access are distinct states.
- Persistent playlist membership uses song IDs; missing device tracks are skipped. SQLite uniqueness prevents duplicate memberships and foreign keys support cleanup.
- SharedPreferences uses established keys. A richer appearance model will need explicit migration rather than reinterpreting existing indices silently.
- Downloader task events arrive from a background isolate. YouTube uses `youtube_explode_dart` despite the `Ytdlp` class name; TikTok uses a scraper. Do not assume a yt-dlp subprocess or streaming playback feature exists.
- Genius uses a token loaded from the bundled `.env`; this audit did not inspect secret values. Missing-token behavior currently surfaces technical copy to users.
- File deletion and tag writing depend on Android file access. Their real-device success is outside the passing widget-test evidence.

## Current visual system

Current design intent is Material 3 Expressive with pixel accents: Roboto Flex, heavy large headings, tonal color blocks, large radii, alternating leaf-shaped tiles, morphing play controls, spring motion, rounded chips and border-light cards. Most colors are generated through `WvPalette` and consumed through `Wv.of(context)`.

There are **three** selectable appearance modes: Green, Red, Material You. Dark mode is a boolean. With Dynamic Colors enabled, a usable album-art swatch overrides the appearance seed at the app root. Material You otherwise uses wallpaper colors when available, with violet fallback. This is app-wide recoloring, even though some UI copy describes it as player theming.

The current assets primarily contain launcher/splash graphics; the pubspec asset declaration includes `.env`. Pixel UI artwork is drawn in Dart. No supplied vinyl skin, cassette skin, grain texture, particle set, or custom-theme persistence system was found.

## Reference interpretation

The supplied images show a cozy retro music appliance aesthetic:

- Lilac, mint, peach and pink families, with coordinated tinted outlines and shadows.
- Rounded rectangular outer shells, inner framed compartments, inset highlights and offset depth.
- Compact raised buttons, small segmented tabs, outlined sliders and distinct selected states.
- A vinyl record/tonearm centerpiece and a physically grouped transport dock.
- Small pixel-heart and raven accents; decorative details support the player identity.
- Coordinated palette presets, per-part colors, grain adjustment and saved looks shown in the reference UI.

The large serif headings and italic purple words belong to the promotional composition. They do not establish that every player label should use a serif font. Keep app copy readable at phone sizes, with decorative typography reserved for selected headings if adopted.

The side-by-side floating desktop panels should become vertically organized sections, tabs, or sheets on Android. Do not shrink desktop controls to fit a phone. Keep primary transport and navigation comfortably tappable; compact visual styling can sit inside larger hit areas.

| Reference element | Relationship to Wavvy |
| --- | --- |
| Pastel color families and layered player frames | Visual-system replacement using existing theme/component seams |
| Outlined buttons, tabs, sliders, control dock | Shared-component redesign; retain current actions and semantics |
| Vinyl player | New presentation/animation around existing audio state; artwork can become record-label content |
| Pixel mascot/heart accents | Existing procedural pixel infrastructure offers a starting point; reference raven is not an existing Wavvy asset |
| Multiple skins, including cassette | New preference and distinct presentation implementations; not currently supported |
| Twelve presets, arbitrary per-part colors, save named looks | New appearance data model, validation, persistence, editor and migration |
| Adjustable grain | New optional rendering effect and saved setting; needs performance/legibility checks |
| Snow, petals, confetti, hearts | New optional animation feature with reduced-motion and lifecycle handling |
| Lo-fi sequencer, keyboard, BPM, pads, crackle | New audio/instrument functionality, not an equalizer reskin |
| Hearts displayed on the reference player | Do not imply favorites/rating support without implementing its data and behavior |

## Audit findings and redesign risks

| Priority | Finding | Evidence and consequence | Recommended handling |
| --- | --- | --- | --- |
| High | Fixed pastel looks conflict with automatic global recoloring | `wavvy_app.dart` feeds album accent into both themes; Dynamic Colors defaults on | Define explicit precedence between chosen preset/custom look and album-adaptive mode before implementation |
| High | A shared-theme edit alone will not redesign all screens | Many screens contain local font sizes, radii, gradients and layouts; Search song results have their own row implementation | Change primitives, then migrate every surface against the inventory |
| High | Historical screenshots cannot validate the current implementation | Source shell/feed differ from README screenshots | Capture current runtime baselines in a later device walkthrough before visual comparison |
| Medium | Downloads search is nonfunctional in the current UI | Search shows a Downloads hint and editable field; `DownloadsList` accepts no query and renders all tasks | Filter tasks or replace/hide the field for this source; treat as a known pre-existing issue |
| Medium | YouTube search has no explicit request/loading/error state | `YtdlpState` stores results/tasks only; `search()` retains previous results and reports failures by snackbar | Specify idle/loading/results/empty/failure states; stale responses from overlapping searches need review |
| Medium | Library scanning lacks an exposed loading/error state | Provider uses private `_fetching`; UI primarily distinguishes empty music and permission denial | Distinguish initial scan, genuinely empty library and scan failure in the new state design |
| Medium | Some advertised playback features are absent or inaccessible | Speed dialog has no call site found; skip silence is initialized false; no pitch UI found; fade and wake-lock settings are commented out | Preserve reachable features and label dormant helpers separately; do not promise README parity |
| Medium | Some effect capabilities are not visible controls | Reverb channel/provider exist but Effects UI exposes Bass Boost and Virtualizer | Decide whether to expose existing reverb capability; this is a scope decision beyond styling |
| Medium | Appearance documentation has drifted | Settings/palette comments still mention Blue/Graphite; runtime uses Green/Red/Material You; README claims 50+ schemes | Use runtime code as truth and update documentation with the final design |
| Medium | Native failures can be hard to distinguish from unavailable controls | Empty catches and nullable native-effect handling; analyzer reports six empty catches | Specify unavailable/unsupported effect feedback; do not present inactive effects as working |
| Medium | Accessibility needs an explicit compact-control policy | Some existing visible controls are 28-44 logical pixels; custom gesture controls have uneven semantics | Audit actual hit bounds, focus, selected/disabled labels, slider semantics, contrast, large text and reduced motion |
| Medium | Network/token errors need product-friendly states | Artist provider can emit `Please add Token.` or raw error text | Provide useful unavailable/retry copy and avoid exposing setup details in the listening flow |
| Low | Sharing helper is deprecated | Two analyzer findings in lyric-card export | Migrate when touching sharing; verify generated image and system share flow |
| Low | Large shared files increase migration coordination | `wavvy_widgets.dart`, `pixel_art.dart`, Home and full-player files combine many responsibilities | Extract cohesive components as the redesign requires; avoid a broad unrelated architecture rewrite |

These are source-observed findings or explicitly labeled validation gaps, not claims that every path currently fails on a device.

## Proposed direction for the next phase

Working assumption: retain Wavvy's Android platform, name and existing listening capabilities while adopting the reference's pastel retro player language. A Windows port, sequencer, multiple skin engines and full theme editor are separate feature decisions.

1. Establish a small reusable visual system: semantic colors for background, shell top/bottom, inset surface, outline, text, muted text, accent, control fill, selected state, shadow and error; consistent frames, depth, corner radii, type scale and motion.
2. Define lilac, mint and peach/pink looks with readable dark counterparts. Decide how album-adaptive mode interacts with explicit choices. Keep color roles distinct from arbitrary component hex values.
3. Design one representative vertical flow: shell -> Library song list -> mini-player -> full player -> queue -> song actions. This exercises the most reused components and the desired vinyl identity.
4. Extend the same components to Home, all library sections/details, all search sources, settings, audio controls, lyrics, artist information and share cards.
5. Finish overlays, loading/error/permission/empty states, system colors, landscape/short-screen layouts, keyboard insets, long titles and enlarged text.
6. Only then consider optional particles, grain, saved custom looks or alternate skins as explicitly scoped additions.

Suggested component families: player shell/frame, inset panel, raised button, transport button, segmented tabs, track row, cover frame, seek slider, control dock, settings row, palette swatch, dialog frame, status/empty state and restrained mascot decoration. These are planning names, not implemented classes.

## Validation plan for implementation

- Retain behavior tests for navigation, sorting/search, playlist membership, feed derivation, mini-player opening, and theme contrast. Update tests that intentionally encode the old appearance, such as the pale selected-chip indicator and Green/Red labels.
- Add visual baselines for the new representative screens and overlays using deterministic fake content. Existing tests are predominantly behavior/layout checks rather than pixel-accurate reference checks.
- Exercise light/dark, chosen palettes, album adaptation, missing artwork, long metadata, sparse/large libraries, 320/360/412 logical-pixel widths, short screens, landscape, keyboard, and text scaling. Existing coverage already checks several widths and enlarged text, including shared widgets at 2x.
- Run a real Android walkthrough for first-launch permissions, settings-return recovery, background playback/notification controls, seeking/queue behavior, native effects, downloads, file opening, metadata editing, deletion and lyric-card sharing.
- Profile any vinyl rotation, grain or particles on device. Pause decorative motion when hidden, honor reduced motion, and isolate repaint work from playback-position updates.
- Preserve persisted playlists/history/settings and verify appearance migration if a new model is added.

## Decisions still open

These do not block the audit and have not been treated as authorization to add features:

- How closely to match the reference's physical controls versus a simpler phone-friendly interpretation.
- Whether vinyl is the default/only player presentation or the first of several skins.
- Whether this release includes palette presets only, or a full custom appearance editor with saved looks.
- Whether grain/mascot animation/particles are part of the first redesign pass.
- Whether album-adaptive color remains enabled by default once explicit pastel looks exist.

The application is mapped sufficiently to begin design exploration, with runtime visual and native integration validation still required before claiming a complete end-to-end audit.
