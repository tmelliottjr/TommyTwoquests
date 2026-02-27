# Changelog

## v2.0.4

- Fix percent based progress tracking

## v2.0.3

- Fix quest tracking progress
- Fix bonus objectives

## v2.0.1 - February 22, 2026

- Migrated to Ace

## v1.6.1 - February 22, 2026

**Bug Fixes**

- Fixed world quests from events and prepatch content not appearing in the tracker
- Zone-based world quests (e.g. timewalking, seasonal events) now show up correctly when filtering by current zone

## v1.6.0 - February 21, 2026

- Migrate to AceAddon-3.0, AceEvent-3.0, and AceTimer-3.0 for more robust event handling and timer management
- Refactor event registration to use AceEvent's `RegisterEvent` and `UnregisterEvent` methods, improving reliability and reducing boilerplate

## v1.5.0 - TBD

**Mythic+ Timer Overhaul**

- Timer colors now follow a WoW item-rarity theme: epic purple (plenty of time), rare blue (moderate), common green (getting tight), and red (over time)
- Timer color transitions are now clean discrete tier changes instead of interpolated gradients
- Timer progress bar fill now uses muted rarity colors that step down as chest tiers are missed: muted purple (+3 pace), muted blue (+2 pace), muted green (+1 pace), red (over time)
- Chest tier markers (+3, +2, +1) and their tick lines use fixed rarity colors: epic purple for +3, rare blue for +2, common green for +1 — greying out when no longer achievable
- Affix icons are now displayed inline in the header row as an overlapping avatar-list, freeing up vertical space
- Enemy forces progress bar is now thinner and uses the player's class color for the fill
- Boss completion now shows a proper checkmark texture instead of an inline text icon

**Death Log Improvements**

- Death tooltip now retroactively resolves "Unknown" player entries when you hover over the death log
- Class information is upgraded on later entries if it was missing initially
- Death count total now uses the authoritative API count, staying accurate even if individual deaths were missed
- Unknown deaths are displayed in a muted grey to distinguish them from identified players
- Unidentified deaths are now logged as placeholders to keep the death log in sync with the API count

**Death Detection**

- UNIT_DIED handler now filters out non-Player GUIDs (mobs, pets, NPCs) before processing
- Player identity resolution now uses `GetPlayerInfoByGUID` as the primary strategy for more reliable name and class lookups

**Bug Fixes**

- Recycled quest rows no longer flash stale text, strikethrough lines, or expand indicators from a previous quest
- Group containers now hide orphaned child frames from previous layout cycles, preventing ghost quest rows
- Tracker refresh is now fully debounced (resets on each event) instead of throttled (fire-once), ensuring the quest log is in its final state before rebuilding

## v1.4.1 - February 21, 2026

**Bug Fixes**

- Fixed a taint error ("attempt to perform arithmetic on a secret number value") that occurred when hovering over world quest POIs on the map
- Quest descriptions for quests with no objectives are now fetched asynchronously, preventing `C_QuestLog.SetSelectedQuest` from tainting the quest-log selection state during tracker refreshes
- World quest reward tooltips no longer break due to tainted money values propagating through `MoneyFrame_Update`

## v1.4.0 - February 21, 2026

**Quest Item Buttons**

- Quests with usable items now show a clickable item button directly in the tracker row — click to use without opening your bags
- Item buttons include a cooldown spinner so you can see at a glance when they're ready again
- Choose where the button appears: inside the quest row (right) or floating outside the tracker (left) — configurable in settings

**Abandon All Quests**

- New optional skull button in the tracker header lets you abandon every tracked quest at once
- Requires typing "abandon" to confirm, so you won't nuke your quest log by accident
- Disabled by default — enable it in Display settings when you want it

**Interaction Changes**

- Left-clicking a quest now focuses it and opens the map; shift-click to expand/collapse (previously left-click toggled collapse)
- Disabled context menu buttons no longer fire their action when clicked
- Share Quest now properly selects the quest before sharing

**Tooltips**

- All tracker tooltips can now be toggled off with a single setting ("Show tracker tooltips") for a cleaner look
- Tooltip hints updated to reflect the new click behavior

**Mythic+ Fixes**

- Fixed a potential divide-by-zero when the M+ timer total is zero or missing
- Cleaned up some leftover comments

**Under the Hood**

- Quest item data is now gathered in a separate pass after quest collection, avoiding conflicts with the quest log selection state
- Pooled objective items properly clear their quest ID on release, preventing stale click-to-map behavior
- Focus icon position resets correctly when quest rows are recycled from the pool
- Context menu disabled items now visually grey out consistently
