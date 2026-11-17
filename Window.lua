-- Player Notes: the notes window (/note) with search, the options, "/note set <setting> <value>" and the
-- Settings > AddOns entry, on EverlookUI. Notes stay in PlayerNotesDB on this computer only.
local ADDON, ns = ...
local UI = LibStub("EverlookUI-1")
local U = ns.Util

local app = UI:NewApp({
	name = "Player Notes",
	addon = ADDON,
	slash = "/note",
	frameName = "PlayerNotes",
	tagline = "Your own notes on players, shown in tooltips, chat, menus and lists. They never leave this computer.",
	accent = { 1, 0.70, 0.28 },
	position = function() return ns.db end,
})
ns.app = app
-- Chat replies for settings read "/note set chat off".
app.slash = "/note set"

local function O() return ns.db.options end
local function Opt(key, kind, label, desc, extra)
	local def = {
		key = key:lower(), type = kind, label = label, desc = desc,
		get = function() return O()[key] end,
		set = function(v) O()[key] = v end,
	}
	for k, v in pairs(extra or {}) do def[k] = v end
	return app:Setting(def)
end

Opt("tooltip", "bool", "In tooltips", "The note is the last line when you mouse over the player.")
Opt("chat", "bool", "In chat, in front of their messages", "Say, yell, whispers, party, raid, guild, channels and instance chat.")
Opt("chatLength", "number", "How much of the note chat shows (letters)", nil,
	{ min = 10, max = 120, step = 5, disabled = function() return not O().chat end })
Opt("menu", "bool", "Under their name in right-click menus", "Add note / Edit note is always in the menu.")
Opt("groupJoin", "bool", "A chat line when a noted player joins your group")
Opt("hover", "bool", "Beside the group finder, who, friends and guild lists", "A small note box next to the list's own tooltip.")
Opt("color", "color", "Note colour", nil, {
	set = function(v) O().color = { v[1], v[2], v[3] } end,
	after = function() ns.ApplyColor() end,
})

-- Every note, sorted by name, matching the search (name or note text, any case).
local search = ""
function ns.Filtered(query)
	query = (query or search):lower()
	local rows = {}
	for _, e in pairs(ns.db and ns.db.notes or {}) do
		if query == "" or ns.Label(e):lower():find(query, 1, true) or e.text:lower():find(query, 1, true) then
			rows[#rows + 1] = e
		end
	end
	table.sort(rows, function(a, b) return ns.Label(a):lower() < ns.Label(b):lower() end)
	return rows
end

local function Count()
	local n = 0
	for _ in pairs(ns.db and ns.db.notes or {}) do n = n + 1 end
	return n
end

local function TargetName()
	local n, r = ns.UnitNameParts("target")
	if n and ns.Key(n, r) then return n, r end
end

app:Section("notes", "Notes", function(stack)
	UI.Header(stack, "Notes", "Your notes on players. Click one to edit it.")
	local list
	UI.Input(stack, {
		placeholder = "Search names and notes", width = 300,
		onChange = function(text) search = U.Trim(text or ""); if list then list:Refresh() end end,
	})
	-- the button and Enter do the same; a bad name says why, with an example
	local function addNote(text, box)
		local name = U.Trim(text or "")
		if not ns.Key(name) then
			ns:Print(name == "" and "type a player's name first, like Bob or Bob-Realm."
				or ("'" .. U.Escape(name) .. "' is not a player name: letters only, like Bob or Bob-Realm."))
			return
		end
		box:SetText("")
		box:ClearFocus()
		ns.OpenEditor(name)
	end
	UI.Input(stack, {
		placeholder = "Name or Name-Realm", width = 300,
		button = { label = "Add / edit note", width = 140, style = "accent", onClick = addNote },
		onEnter = addNote,
	})
	UI.ButtonRow(stack, {
		{ label = "Note on my target", width = 300, onClick = function()
			local n, r = TargetName()
			if n then ns.OpenEditor(n, r) else ns:Print("target a player first.") end
		end },
		refresh = function(row)
			local n, r = TargetName()
			row.buttons[1]:SetText(n and ("Note on " .. ns.Label({ name = n, realm = r or ns.OwnRealm() })) or "Note on my target (none targeted)")
			row.buttons[1]:SetUsable(n ~= nil)
		end,
	})
	UI.Stat(stack, "Notes", function()
		local all, shown = Count(), #ns.Filtered()
		return search ~= "" and (shown .. " of " .. all .. " match") or tostring(all)
	end)
	list = UI.List(stack, {
		items = function() return ns.Filtered() end,
		rowHeight = 40,
		empty = "No notes yet. Right-click a player > Add note, or type a name above.",
		title = function(e) return ns.Label(e) end,
		detail = function(e) return ns.COLOR .. U.Escape(e.text) .. "|r  |cff8d94a3" .. ns.Date(e) .. "|r" end,
		tooltip = function(e) return { ns.Label(e), U.Escape(e.text), "|cff8d94a3Set " .. ns.Date(e) .. "|r" } end,
		onClick = function(e) ns.OpenEditor(e.name, e.realm) end,
		buttons = {
			{ label = "Edit", width = 60, onClick = function(e) ns.OpenEditor(e.name, e.realm) end },
			{ label = "Delete", width = 70, style = "danger", confirm = true, onClick = function(e)
				ns.Delete(e.name, e.realm)
				ns:Print("Deleted the note on " .. ns.Label(e) .. ".")
			end },
		},
	})
end)

app:Section("options", "Options", function(stack)
	UI.Header(stack, "Where notes show", "Turn off any place you don't want to see them.")
	app:Widget(stack, "tooltip")
	app:Widget(stack, "chat")
	app:Widget(stack, "chatlength")
	app:Widget(stack, "menu")
	app:Widget(stack, "groupjoin")
	app:Widget(stack, "hover")
	UI.Header(stack, "Look")
	app:Widget(stack, "color")
	UI.Header(stack, "Privacy")
	UI.Note(stack, "Notes are stored only in your SavedVariables (WTF\\Account\\<account>\\SavedVariables\\PlayerNotes.lua), shared by your characters. Player Notes never sends them anywhere: no addon messages, no sync, nobody else can see them.")
	UI.Header(stack, "Chat commands")
	UI.Note(stack, "/note  this window\n/note <text>  note on your target\n/note Name <text>  note on anyone (Name-Realm for other realms)\n/note Name  show a note,  /note del Name  delete it\n/note list  every note in chat\n/note set chat off  change a setting (/note settings lists them)\n/note help  all of this in chat")
end)

-- The window follows note changes made anywhere (editor, menus, chat).
ns.listeners[#ns.listeners + 1] = function() app:Refresh() end

-- "Note on <target>" follows your target while the window is open.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:SetScript("OnEvent", function() if app:IsShown() then app:Refresh() end end)
