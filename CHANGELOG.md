# Changelog

## Unreleased

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
- Notes are stored only in your SavedVariables and never sent anywhere.
