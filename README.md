# Player Notes

Put a note on any player for WoW Forever (interface 16001): "cool healer", "ninjalooted axe in ZF", "piece of shit". Anything you like, no limits on what you write.

Written from scratch; no third-party code or libraries.

## Set a note
- Right-click a player: their portrait or target frame, a party or raid frame, focus, a name in chat, a friend, a guild or community member. Pick **Add note…** (or **Edit note…**).
- Or type it:
  - `/note <text>` notes your target.
  - `/note Name <text>` or `/note Name-Realm <text>` notes anyone. With a player targeted, write `@Name <text>` or `Name-Realm <text>` to note someone else.
  - `/note` opens the note window for your target.
  - `/note Name` shows a note, `/note del Name` deletes it, `/note list` shows them all.

In the note window, Enter saves and Escape closes. Saving an empty note deletes it.

## Where notes show up
- **Tooltips**: mouse over the player (in the world, on unit frames and portraits) and the note is the last line.
- **Chat**: their messages get a short `[note]` in front (say, yell, whispers, party, raid, guild, channels, instance chat).
- **Right-click menu**: the note sits under their name.
- **Joining your group**: one chat line, "Player Notes: Name — note".
- **Lists**: hover a player in the group finder (Looking for Group browse list: the leader and members), the who list, your friends list or a guild/community roster and a small note box appears beside it.

Names are matched without regard to case; players on your own realm can be written without the realm.

## Privacy
Your notes stay on your computer, in your SavedVariables (`WTF\Account\<account>\SavedVariables\PlayerNotes.lua`), shared by all your characters. Player Notes never sends them anywhere: no addon messages, no sync, nobody else can see them.

## License

GPL-3.0-or-later (see LICENSE). Not affiliated with Blizzard Entertainment.
