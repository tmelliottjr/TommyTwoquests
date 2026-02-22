# Copilot Instructions — TommyTwoquests

TommyTwoquests is a World of Warcraft (retail) addon written entirely in Lua. It replaces the default quest tracker with a modern, configurable UI that includes quest tracking, Mythic+ dungeon overlays, and profession recipe tracking.

> **Golden Rule: Never make assumptions.** If the intent, scope, or expected behavior of a change is unclear, ask for clarification before writing code. Do not guess at API behavior, game mechanics, or design intent.

---

## Documentation & API Reference

- **Always** reference the official WoW addon API documentation on Wowpedia (warcraft.wiki.gg) when using or suggesting WoW API calls.
  - WoW API: https://warcraft.wiki.gg/wiki/World_of_Warcraft_API
  - Widget API: https://warcraft.wiki.gg/wiki/Widget_API
  - Events: https://warcraft.wiki.gg/wiki/Events
  - CVars: https://warcraft.wiki.gg/wiki/Console_variables
  - Lua in WoW: https://warcraft.wiki.gg/wiki/Lua_functions
- If you are unsure whether a WoW API function exists, has been renamed, or has changed signatures across patches, **say so and ask** rather than inventing a call.
- When referencing a WoW API function, include its full name (e.g., `C_QuestLog.GetInfo`, not `GetInfo`).

---

## Project Architecture

### Namespace & Module System

- All files share a single private addon table: `local AddonName, TTQ = ...`
- `TTQ` is the central namespace. All public methods, data, and state live on this table.
- `_G.TommyTwoquests = TTQ` is set once in Core.lua for external access.
- There is no `require` or module system — file load order in the `.toc` file **is** the dependency graph. Respect it.

### File Responsibilities

| File | Purpose |
|------|---------|
| `Utils.lua` | Shared helpers, font list, icon maps, object pool factory, tooltip wrappers, debounced refresh |
| `Config.lua` | `TTQ.Defaults`, `GetSetting`/`SetSetting`, font resolution and migration |
| `Core.lua` | Boot sequence, event dispatcher, saved variables, versioned migrations, slash commands |
| `QuestData.lua` | Data layer wrapping `C_QuestLog` — quest enrichment, classification, zone queries |
| `Filters.lua` | `FilterAndGroupQuests()` — type filters, zone filters, sorting, grouping |
| `ObjectiveItem.lua` | Objective row widget (pooled) |
| `QuestItem.lua` | Quest row widget — icons, hover, click handlers, context menu integration |
| `QuestTracker.lua` | Main tracker frame, `RefreshTracker()`, Blizzard tracker hiding, filter dropdown |
| `RecipeTracker.lua` | Tracked profession recipes with Auctionator integration |
| `MythicPlus.lua` | M+ timer, chest thresholds, death tracking, enemy forces, boss list, affixes |
| `DevMode.lua` | Dev tool for simulating M+ runs via mock data injection |
| `Settings.lua` | Full custom settings panel — data-driven widget generation |
| `ContextMenu.lua` | Reusable context menu factory |

### Key Patterns

- **Object Pools** — `TTQ:CreateObjectPool(createFn, resetFn)` for quest rows, objectives, headers, etc.
- **Debounced Refresh** — `TTQ:ScheduleRefresh()` coalesces rapid event bursts into a single `RefreshTracker()` call.
- **Safe Wrappers** — `TTQ:SafeRefreshTracker()` uses `xpcall` with `debugstack` and error deduplication. `TTQ:SafeSetFont()` wraps `SetFont` with `pcall` and fallback.
- **Event System** — `TTQ:RegisterEvent(event, callback)` / `TTQ:UnregisterEvent(event)` with combat-lockdown-aware deferred registration.
- **File-Scope Event Frames** — High-frequency events use dedicated `CreateFrame("Frame")` blocks outside functions for untainted registration.
- **Lazy Initialization** — Complex UI (M+ display, settings panel, context menus) created on first use.
- **Data-Driven UI** — Settings panel built from `BuildOptionCategories()`, a declarative array of `{type, name, desc, dbKey, ...}`.

---

## Lua Best Practices

### General

- **Localize globals at file scope.** Cache frequently used WoW globals and Lua builtins at the top of each file:
  ```lua
  local C_QuestLog, C_Map, C_Timer = C_QuestLog, C_Map, C_Timer
  local table, ipairs, type, pcall, print = table, ipairs, type, pcall, print
  ```
- **Use `local` for everything** unless a value explicitly needs to be on `TTQ` or `_G`. Avoid polluting the global namespace.
- **Prefer `ipairs` for array iteration** and `pairs` for hash tables. Use numeric `for` loops when performance matters.
- **Avoid creating tables in hot paths.** Reuse tables, use object pools, or pre-allocate where possible.
- **Use `and`/`or` idioms** for nil-safe access: `mapInfo and mapInfo.name or "Unknown"`.
- **Never use `==` to compare floating-point numbers.** Use an epsilon comparison if needed.
- **String concatenation in loops** should use `table.concat` instead of repeated `..` operator.
- **Avoid `select()` in tight loops** — destructure return values directly.

### Naming Conventions

- `PascalCase` for methods on `TTQ`: `TTQ:GetSetting()`, `TTQ:RefreshTracker()`
- `camelCase` for local variables and table keys: `questID`, `numEntries`, `isCollapsed`
- `UPPER_SNAKE_CASE` for constants: `SECTION_HEADER_HEIGHT`, `FOCUS_ICON_WIDTH`
- Prefix booleans with `is`/`has`/`can`: `isComplete`, `hasQuestItem`, `canAbandon`
- Prefix private/internal fields with underscore: `TTQ._devModeActive`, `item._nameColorR`

### Code Style

- **4-space indentation** (consistent across all files).
- **70-dash separator blocks** (`------...------`) to delimit logical sections in each file.
- **File header** — Every file opens with a 3-line comment block: addon name, filename, one-line description.
- **Comment the "why"**, not the "what." Explain non-obvious decisions (e.g., why `pcall` is used, why a timer is deferred).
- **Blank lines** between logical sections within functions. Keep functions focused and short where possible.

### Error Handling

- Wrap potentially failing API calls (`SetAtlas`, `RegisterEvent`, `SetFont`) in `pcall` with meaningful fallbacks.
- Use `xpcall` with `debugstack` for critical paths like the tracker rebuild.
- Guard function entry with nil checks: `if not data then return end`.
- Implement fallback chains (e.g., try modern API → legacy API → hardcoded default).
- Deduplicate repeated error messages to avoid chat spam.

---

## WoW Addon Development Best Practices

### Taint & Secure Execution

- **Never call `RegisterEvent` from a tainted execution path.** File-scope calls are safe; calls from C_Timer callbacks or OnClick handlers may taint.
- Use dedicated, untainted frames for event dispatch (as the codebase does with `TTQ._EventDispatcher`).
- Check `InCombatLockdown()` before manipulating secure frames (`SecureActionButtonTemplate`).
- Defer operations to `PLAYER_REGEN_ENABLED` when combat lockdown prevents them.
- Use `CreateFrame("Frame")` at file scope inside `do...end` blocks for untainted event registration.

### Frame Management

- Use `BackdropTemplate` for frames that need backgrounds.
- Use `SecureActionButtonTemplate` and `CooldownFrameTemplate` where needed.
- Call `ClearAllPoints()` before `SetPoint()` when repositioning.
- Set `SetClipsChildren(true)` on scroll/collapse containers.
- Use `SetFrameStrata` appropriately: `"MEDIUM"` for tracker, `"DIALOG"` for popups, `"TOOLTIP"` for tooltips.
- Pool frames aggressively — create once, acquire/release via object pools.

### Performance

- **Debounce event-driven refreshes.** WoW fires many events in rapid succession (e.g., `QUEST_TURNED_IN` + `QUEST_REMOVED`). Coalesce with a short timer (0.1s).
- **Avoid work in `OnUpdate` unless necessary.** When used (e.g., M+ timer), keep the callback lightweight.
- **Cache API results** that don't change frequently. Avoid calling `C_QuestLog.GetInfo()` or `C_Map.GetBestMapForUnit("player")` multiple times per frame.
- Never iterate the full quest log on every event — snapshot and diff when possible.
- Use `C_Timer.NewTimer` for one-shot delays. Be aware it runs through a secure frame (use `OnUpdate` if taint is a concern).

### Saved Variables

- Declare saved variables in the `.toc` file (`SavedVariables: TommyTwoquestsDB`).
- Load on `ADDON_LOADED`, initialize via `DeepCopy(Defaults)` for new installs or `DeepMerge(existing, Defaults)` for upgrades.
- Implement versioned migrations (`TTQ.Migrations`) with a `_schemaVersion` field for structural changes.
- Store font **names**, not paths. Resolve paths at runtime via `ResolveFontPath`.

### API Usage Patterns

- Use the `C_` namespaced APIs (e.g., `C_QuestLog`, `C_ChallengeMode`, `C_Map`) — they are the modern, supported interfaces.
- Guard against missing APIs with `if C_SomeNamespace and C_SomeNamespace.SomeFunc then`. APIs change between patches.
- Use `pcall` when calling APIs that may not exist in all client versions.
- For quest classification, implement a fallback chain: modern `C_QuestInfoSystem.GetQuestClassification` → campaign check → tag-based → legacy `Is*` methods → frequency-based → default.

### Combat Lockdown Awareness

- Always check `InCombatLockdown()` before:
  - Registering events on frames that interact with secure content.
  - Showing/hiding frames that use `SecureActionButtonTemplate`.
  - Opening Group Finder or other protected UIs.
- Queue deferred actions for `PLAYER_REGEN_ENABLED`.

### Hiding Blizzard UI

- When replacing Blizzard frames (like the ObjectiveTracker), hide them carefully to avoid taint.
- Use `pcall` when interacting with Blizzard's own frame management functions.

---

## Modular Design Principles

### Single Responsibility

- Each file has **one clear responsibility** (see File Responsibilities table above).
- Data fetching (`QuestData.lua`) is separate from filtering (`Filters.lua`), which is separate from rendering (`QuestTracker.lua`).
- Widget creation is separate from layout logic.

### Loose Coupling

- Files communicate through the shared `TTQ` namespace by attaching methods and reading shared state.
- Cross-file calls should go through well-defined `TTQ:MethodName()` interfaces, not by reaching into internal state.
- Event-driven communication via `TTQ:RegisterEvent` keeps modules decoupled.

### Extending the Addon

- When adding a new feature module:
  1. Create a new `.lua` file with the standard header and `local AddonName, TTQ = ...`.
  2. Add it to the `.toc` file in the correct position (after its dependencies).
  3. Attach public methods to `TTQ`.
  4. Register events using `TTQ:RegisterEvent` or file-scope event frames.
  5. Use `TTQ:ScheduleRefresh()` if the feature affects tracker layout.
- When adding new settings:
  1. Add the default value to `TTQ.Defaults` in `Config.lua`.
  2. Add the UI widget entry to `BuildOptionCategories()` in `Settings.lua`.
  3. Handle `OnSettingChanged` if the setting needs immediate visual feedback.

### Factory Pattern

- Use factory functions for reusable UI components: `TTQ:CreateContextMenu()`, `TTQ:CreateObjectPool()`.
- Settings widgets (`CreateToggleSwitch`, `CreateSliderWidget`, `CreateDropdownWidget`) return configured objects with methods.

---

## Code Review Checklist

Before finalizing any change, verify:

- [ ] No global variable leaks — all variables are `local` or on `TTQ`.
- [ ] WoW API calls are wrapped in `pcall` if they can fail or may not exist.
- [ ] No operations on secure frames during `InCombatLockdown()`.
- [ ] Event registrations happen from untainted execution paths.
- [ ] New settings have defaults in `Config.lua` and UI entries in `Settings.lua`.
- [ ] Object pools are used for dynamically created frames that are shown/hidden frequently.
- [ ] Comments explain **why**, not just **what**.
- [ ] The `.toc` file load order is correct for any new files.
- [ ] No assumptions were made — unclear requirements were clarified first.
