# Changelog

## Unreleased
- Tooltip: the note line matches the other EverlookDB addons. New setting "Solid tooltip background" (on by default).

## v0.2.1 (2026-11-21)
- Notes on players from your own realm work again after the latest WoW Forever client update. Older notes on them show again once the game reports realm names again.

## v0.2.0 (2026-11-20)
- Settings window: switches, buttons and sliders use a softer shade of the accent colour, an on switch has a dark knob so it stands out, and boxes have cleaner rounded edges.

- Notes window: one box instead of two. Type to search your notes; click "Add / edit note" (or press Enter on a player's name) to add a note on whoever you typed.
- The note editor remembers where you dragged it, and uses the same colours as the notes window instead of its own orange.
- A mistyped command like `/note hepl` no longer becomes a note on your target: it asks "Did you mean /note help?" and shows how to make a one-word note if that is what you wanted (`/note @Name hepl`).
- Less chat spam: saving or deleting a note in the editor or the notes window no longer prints a chat line, and when several noted players join your group at once (a raid) you get one line naming them all instead of one line each.
- Lighter on chat: with no notes yet, chat messages are passed straight through without being checked.
- Lighter on your game: the note box beside the friends, who, guild and group finder lists only watches the mouse while one of those windows is open, never in the rest of play or in combat.

## v0.1.0 (2026-11-19)

- Settings: an AI help button copies a description of every setting for an AI assistant, and `/note apply` runs the commands it gives back.
- Chat commands now follow one pattern across all EverlookDB addons: `/note help` (or `?`) lists them in the same format as the others; `/note get` and `/note get chat`; `/note status` (how many notes) and `/note version`; `/note search` opens the window's search box. On their own only, so `/note status is unknown` is still a note on your target.
- Tooltip lines now share one tidy layout with the other EverlookDB addons: the note sits last in the EverlookDB block after a blank line, as "Note  cool healer" with the label in the shared label colour and the note in your note colour.
- The settings window has a search box at the top: type to find any setting.
- Note editor: pressing Enter on an empty box for a player with no note no longer says it deleted a note.
- Saving a note without changing it keeps the date it was set.
- Notes window: the "N of M match" count follows the search as you type.
- Options: the chat length slider explains that a longer note is cut short in chat only.
- `/note` opens the notes window: every note with search, edit and delete, and adding a note by name or on your target. Options choose where notes show (tooltips, chat and how much of the note the chat tag shows, right-click menus, group joins, list hints) and the note colour; all on, as before. Also under Settings > AddOns. Settings from chat: `/note set chat off`, `/note settings`. With a player targeted, a bare `/note` used to open that player's note: now use the window's "Note on ..." button, right-click > Edit note, or `/note <text>`.
- Note window: the hint line under the box is a size larger, easier to read.
- The "Note on <target>" button follows your target while the window is open.
- Adding a note by name: Enter works like the button, and a bad name says why, with an example.
- The note editor stays above the notes window, and its Delete asks for a second click like the list's.
- Settings window: Escape closes an open dropdown list first, then the window; Escape in a text box puts the old text back; a number typed next to a slider snaps to the slider's steps; a Delete or Reset that asks for a second click no longer forgets it early.

## v0.1.0 (2026-11-16)

- First version: notes on players from the right-click menu (portraits, unit frames, chat names, friends, guild) or `/note`.
- Notes show in unit tooltips, in front of chat messages, in the right-click menu, when a noted player joins your group, and beside the group finder, who, friends and guild lists.
- Notes are stored only on your computer and never sent anywhere.
