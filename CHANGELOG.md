# Changelog

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
