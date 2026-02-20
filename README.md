# TommyTwoquests

A clean, modern quest tracker replacement for World of Warcraft. It ditches the default tracker in favor of something more readable, more configurable, and nicer to look at.

## Features

- **Quest Tracking** — Displays tracked quests with icons, objective progress, and quest type grouping (campaign, world quests, dailies, dungeons, PvP, and more).
- **Mythic+ Tracker** — Built-in Mythic+ dungeon overlay with a live timer, chest tier thresholds, boss tracking, and enemy forces progress bar.
- **Recipe Tracker** — Tracks profession recipes and their reagents, with Auctionator integration for quick AH searches.
- **Filtering** — Toggle quest categories on or off, filter by current zone, or group zone quests together at the top.
- **Full Customization** — Nearly everything is configurable: fonts, font sizes, colors, background opacity, class-colored gradients, tracker dimensions, and more. All through a built-in settings panel with a dark, card-based UI.
- **Draggable & Lockable** — Move the tracker wherever you want, then lock it in place.
- **Combat Friendly** — Option to hide in combat or fade when not hovered.
- **Collapsible Sections** — Collapse individual quests, entire quest type groups, or the whole tracker.

## Slash Commands

| Command | Description |
|---|---|
| `/ttq` | Open the settings panel |
| `/ttq reset` | Reset all settings to defaults |
| `/ttq toggle` | Show or hide the tracker |
| `/ttq zone` | Toggle the current-zone filter |

## Installation

Drop the `TommyTwoquests` folder into your `World of Warcraft/_retail_/Interface/AddOns` directory and restart the game (or reload the UI with `/reload`).

## Configuration

Type `/ttq` in-game to open the settings panel. Everything — fonts, colors, filters, behavior, background style — can be tweaked from there. No external tools needed.
