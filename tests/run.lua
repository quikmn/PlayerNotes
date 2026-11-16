-- Offline test run for Player Notes. Loads the addon in TOC order against wowmock.lua
-- (secret values throw on compare/index/math) and drives notes, slash, chat, menus,
-- tooltips, group joins and the hover hint through it.
local ROOT = ...
local ADDON = "PlayerNotes"
local ns = {}
local failures, passes = {}, 0

local function step(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passes = passes + 1
		print("  ok   " .. name)
	else
		failures[#failures + 1] = name .. ": " .. tostring(err)
		print("  FAIL " .. name .. "\n         " .. tostring(err))
	end
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function S(v) return MOCK.Secret(v) end
local function lastLog() return MOCK.log[#MOCK.log] or "" end

------------------------------------------------------------------------
-- Extra API this addon uses
------------------------------------------------------------------------
time, date = os.time, os.date
UNKNOWNOBJECT = "Unknown"
GetNormalizedRealmName = function() return "MockRealm" end

MOCK.menuTags = {}
Menu = { ModifyMenu = function(tag, fn) MOCK.menuTags[tag] = fn end }
MenuUtil = { CreateTitle = function(text) return { kind = "title", text = text } end }
local function MenuRoot()
	local root = { items = { { kind = "title", text = "Name" } } }
	function root:Insert(d, i) table.insert(self.items, i or #self.items + 1, d) end
	function root:CreateDivider() self.items[#self.items + 1] = { kind = "divider" } end
	function root:CreateButton(text, fn) local b = { kind = "button", text = text, fn = fn }; self.items[#self.items + 1] = b; return b end
	return root
end

MOCK.tooltipCalls = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) MOCK.tooltipCalls[kind] = fn end }

MOCK.chatFilters = {}
ChatFrameUtil = { AddMessageEventFilter = function(event, fn) MOCK.chatFilters[event] = fn end }

MOCK.foci = {}
GetMouseFoci = function() return MOCK.foci end

local lfgResults = {}
C_LFGList = {
	GetSearchResultInfo = function(id) local r = lfgResults[id]; return r and { numMembers = #r.members } end,
	GetSearchResultLeaderInfo = function(id) local r = lfgResults[id]; return r and { name = r.members[1] } end,
	GetSearchResultPlayerInfo = function(id, i) local r = lfgResults[id]; return r and r.members[i] and { name = r.members[i], isLeader = i == 1 } end,
}
LFGBrowseFrame = { GetParent = function() return nil end }
FRIENDS_BUTTON_TYPE_BNET, FRIENDS_BUTTON_TYPE_WOW = 2, 3
C_FriendList = { GetFriendInfoByIndex = function(i) return { name = "Pal" .. i } end }

-- Taint guard: record every global the addon assigns, and any hooksecurefunc use.
local hooks = 0
hooksecurefunc = function() hooks = hooks + 1 end
local globalWrites = {}
local addonEnv = setmetatable({}, {
	__index = _G,
	__newindex = function(_, k, v) globalWrites[k] = true; _G[k] = v end,
})
local OWN_GLOBALS = { PlayerNotesDB = true, SLASH_PLAYERNOTES1 = true, SLASH_PLAYERNOTES2 = true }

------------------------------------------------------------------------
step("load TOC files", function()
	local toc = assert(io.open(ROOT .. "/PlayerNotes.toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^%s*#") and line:match("%.lua%s*$") then
			local chunk, err = loadfile(ROOT .. "/" .. line:gsub("%s+$", ""))
			if not chunk then error("syntax: " .. err) end
			setfenv(chunk, addonEnv)
			chunk(ADDON, ns)
		end
	end
	check(SlashCmdList.PLAYERNOTES, "slash command missing")
end)

step("ADDON_LOADED sets up storage, menus, tooltips and chat filters", function()
	MOCK.Fire("ADDON_LOADED", ADDON)
	check(PlayerNotesDB and PlayerNotesDB.notes and ns.db == PlayerNotesDB, "db not initialised")
	for _, tag in ipairs({ "PLAYER", "PARTY", "RAID_PLAYER", "FRIEND", "ENEMY_PLAYER", "TARGET", "FOCUS", "COMMUNITIES_GUILD_MEMBER" }) do
		check(MOCK.menuTags["MENU_UNIT_" .. tag], "menu tag not registered: " .. tag)
	end
	check(MOCK.tooltipCalls[Enum.TooltipDataType.Unit], "unit tooltip post-call missing")
	for _, ev in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_RAID", "CHAT_MSG_GUILD", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT" }) do
		check(MOCK.chatFilters[ev] == ns.ChatFilter, "chat filter missing: " .. ev)
	end
	MOCK.Fire("PLAYER_ENTERING_WORLD")
end)

step("name normalization", function()
	local key, name, realm = ns.Key("bob")
	eq(key, "bob-mockrealm", "key"); eq(name, "Bob", "name"); eq(realm, "MockRealm", "realm")
	eq(ns.Key("BOB"), "bob-mockrealm", "case-insensitive")
	eq(ns.Key("Bob-MockRealm"), "bob-mockrealm", "own realm spelled out")
	eq(ns.Key("Bob-Some Realm"), "bob-somerealm", "realm with space")
	eq(ns.Key("Bob", "Azjol-Nerub"), "bob-azjolnerub", "realm with hyphen")
	eq(ns.Key("Bob-Azjol-Nerub"), "bob-azjolnerub", "name-realm with hyphen")
	eq(ns.Key("  Bob  "), "bob-mockrealm", "trimmed")
	eq(ns.Key("Zoë"), "zoë-mockrealm", "non-ASCII name")
	eq(ns.Key(S("Bob")), nil, "secret name")
	eq(ns.Key("Bob", S("Realm")), nil, "secret realm")
	eq(ns.Key(""), nil, "empty"); eq(ns.Key(nil), nil, "nil")
	eq(ns.Key("two words"), nil, "spaces"); eq(ns.Key("x1"), nil, "digits"); eq(ns.Key("Unknown"), nil, "unknown")
	eq(ns.Label({ name = "Bob", realm = "MockRealm" }), "Bob", "own-realm label")
	eq(ns.Label({ name = "Bob", realm = "Other" }), "Bob-Other", "other-realm label")
end)

step("set, get, edit, delete", function()
	local e = ns.Set("bob", nil, "cool healer")
	check(e and e.text == "cool healer" and e.name == "Bob" and type(e.date) == "number", "set failed")
	eq(ns.Get("BOB-MockRealm"), e, "get by other spelling")
	ns.Set("Bob", nil, "  piece of\nshit  ")
	eq(ns.Get("bob").text, "piece of shit", "cleaned text")
	ns.Set("Bob", nil, string.rep("a", 400))
	check(#ns.Get("bob").text <= ns.MAX_LEN, "text not capped")
	check(ns.Delete("bob"), "delete returned false")
	eq(ns.Get("bob"), nil, "after delete")
	check(not ns.Delete("bob"), "second delete should be false")
	ns.Set("Bob", nil, "x"); ns.Set("Bob", nil, "")
	eq(ns.Get("bob"), nil, "empty text deletes")
	eq(ns.Set(S("Bob"), nil, "x"), nil, "secret name is ignored")
	eq(ns.Util.Short("abcdef", 3), "abc...", "short")
	eq(ns.Util.Short("aéz", 2), "a...", "short keeps UTF-8 whole")
end)

step("slash parsing", function()
	ns.Set("Known", nil, "already noted")
	local T = { "Targ", nil }
	local cases = {
		{ "", nil, { cmd = "help" } },
		{ "", T, { cmd = "edit", name = "Targ" } },
		{ "help", T, { cmd = "help" } },
		{ "list", nil, { cmd = "list" } },
		{ "cool healer", T, { cmd = "set", name = "Targ", text = "cool healer" } },
		{ "ninjalooted axe in ZF", T, { cmd = "set", name = "Targ", text = "ninjalooted axe in ZF" } },
		{ "Bob cool healer", nil, { cmd = "set", name = "Bob", text = "cool healer" } },
		{ "Bob-Other cool healer", T, { cmd = "set", name = "Bob-Other", text = "cool healer" } },
		{ "@Bob cool", T, { cmd = "set", name = "Bob", text = "cool" } },
		{ "Known", T, { cmd = "show", name = "Known" } },
		{ "Known new text", T, { cmd = "set", name = "Known", text = "new text" } },
		{ "targ is great", T, { cmd = "set", name = "targ", text = "is great" } },
		{ "Bob", nil, { cmd = "show", name = "Bob" } },
		{ "del Bob", nil, { cmd = "del", name = "Bob" } },
		{ "delete Bob-Other", T, { cmd = "del", name = "Bob-Other" } },
		{ "del", T, { cmd = "del", name = "Targ" } },
		{ "x1 hello", nil, { cmd = "bad", name = "x1" } },
	}
	for _, c in ipairs(cases) do
		local p = ns.ParseSlash(c[1], c[2])
		for k, v in pairs(c[3]) do eq(p[k], v, "'" .. c[1] .. "' " .. k) end
		for _, k in ipairs({ "cmd", "name", "text" }) do
			if c[3][k] == nil then eq(p[k], nil, "'" .. c[1] .. "' " .. k) end
		end
	end
	eq(ns.ParseSlash(S("x"), nil).cmd, "help", "secret input")
end)

step("slash end to end", function()
	SlashCmdList.PLAYERNOTES("Ninja ninjalooted axe in ZF")
	eq(ns.Get("ninja").text, "ninjalooted axe in ZF", "set via slash")
	SlashCmdList.PLAYERNOTES("ninja")
	check(lastLog():find("ninjalooted"), "show printed: " .. lastLog())
	local before = #MOCK.log
	SlashCmdList.PLAYERNOTES("list")
	check(#MOCK.log > before and table.concat(MOCK.log, "\n", before + 1):find("Ninja"), "list printed")
	SlashCmdList.PLAYERNOTES("del Ninja")
	eq(ns.Get("ninja"), nil, "deleted via slash")
	-- target a player and note them
	MOCK.secretsOn = false
	MOCK.units.target = { name = "Targ" }
	SlashCmdList.PLAYERNOTES("cool healer")
	eq(ns.Get("Targ").text, "cool healer", "note on target")
	SlashCmdList.PLAYERNOTES("")
	check(PlayerNotesEditor and PlayerNotesEditor:IsShown(), "editor for target")
	PlayerNotesEditor:Hide()
	MOCK.units.target = nil
	MOCK.secretsOn = true
end)

step("chat filter: noted, unnoted and secret senders", function()
	ns.Set("Talker", "Other Realm", "ninjalooted axe in ZF and also some more words that are long")
	local hide, msg, author, extra = ns.ChatFilter(nil, "CHAT_MSG_SAY", "hello", "Talker-OtherRealm", "lang")
	eq(hide, false, "not hidden")
	check(msg:find("%[ninjalooted axe in ZF") and msg:find("hello$"), "prefixed: " .. tostring(msg))
	check(#msg < 80, "tag truncated")
	eq(author, "Talker-OtherRealm", "author passed on"); eq(extra, "lang", "extra args passed on")
	local r = { ns.ChatFilter(nil, "CHAT_MSG_SAY", "hello", "Nobody-MockRealm") }
	check(r[1] == false and r[2] == nil, "unnoted sender untouched")
	r = { ns.ChatFilter(nil, "CHAT_MSG_PARTY", "hello", S("Talker-OtherRealm")) }
	check(r[1] == false and r[2] == nil, "secret sender untouched")
	r = { ns.ChatFilter(nil, "CHAT_MSG_PARTY", S("hello"), "Talker-OtherRealm") }
	check(r[1] == false and r[2] == nil, "secret message untouched")
	ns.Set("Pipe", nil, "a|cffff0000b")
	local _, m2 = ns.ChatFilter(nil, "CHAT_MSG_SAY", "hi", "Pipe")
	check(m2:find("a||cffff0000b", 1, true), "pipes escaped")
end)

step("unit tooltip line; secret names skipped", function()
	local lines = {}
	GameTooltip.AddLine = function(_, t) lines[#lines + 1] = t end
	GameTooltip.GetUnit = function() return "Bob", "mouseover" end
	ns.Set("Bob", nil, "cool healer")
	MOCK.units.mouseover = { name = "Bob" }
	MOCK.secretsOn = true
	MOCK.tooltipCalls[Enum.TooltipDataType.Unit](GameTooltip, {})
	eq(#lines, 0, "secret unit name must add nothing")
	MOCK.secretsOn = false
	MOCK.tooltipCalls[Enum.TooltipDataType.Unit](GameTooltip, {})
	eq(lines[1], "Note: cool healer", "tooltip line")
	GameTooltip.GetUnit = function() return S("x"), S("mouseover") end
	MOCK.tooltipCalls[Enum.TooltipDataType.Unit](GameTooltip, { guid = S("Player-1") })
	eq(#lines, 1, "secret unit token adds nothing")
	MOCK.units.mouseover = nil
	MOCK.secretsOn = true
end)

step("right-click menus", function()
	ns.Set("Bob", nil, "cool healer")
	local root = MenuRoot()
	MOCK.menuTags.MENU_UNIT_FRIEND(nil, root, { name = "Bob-MockRealm", chatTarget = "Bob-MockRealm" })
	eq(root.items[2].kind, "title", "note title under name")
	check(root.items[2].text:find("cool healer"), "note title text")
	local btn = root.items[#root.items]
	eq(btn.text, "Edit note\226\128\166", "edit label")
	btn.fn()
	check(PlayerNotesEditor:IsShown(), "editor opened")
	eq(PlayerNotesEditor.title:GetText(), "Note on Bob", "editor title")
	PlayerNotesEditor:Hide()

	root = MenuRoot()
	MOCK.menuTags.MENU_UNIT_PLAYER(nil, root, { name = "Newguy", server = "Other Realm" })
	eq(root.items[#root.items].text, "Add note\226\128\166", "add label")
	eq(#root.items, 3, "no note title for unnoted")

	-- NPC target: no entry even though the menu has a name
	MOCK.secretsOn = false
	MOCK.units.target = { name = "Hogger" }
	local isPlayer = UnitIsPlayer
	UnitIsPlayer = function() return false end
	root = MenuRoot()
	MOCK.menuTags.MENU_UNIT_TARGET(nil, root, { unit = "target", name = "Hogger" })
	eq(#root.items, 1, "NPC menu untouched")
	UnitIsPlayer = isPlayer
	MOCK.units.target = nil
	MOCK.secretsOn = true

	root = MenuRoot()
	MOCK.menuTags.MENU_UNIT_PARTY(nil, root, { name = S("Bob") })
	eq(#root.items, 1, "secret name menu untouched")
	MOCK.units.party1 = { name = "Bob" }
	root = MenuRoot()
	MOCK.menuTags.MENU_UNIT_PARTY(nil, root, { unit = "party1", name = "Bob" })
	eq(#root.items, 1, "secret unit name menu untouched")
	MOCK.units.party1 = nil
end)

step("editor: Enter saves, Escape closes, Delete deletes", function()
	local f = ns.OpenEditor("Edited", "Other")
	check(f:IsShown(), "shown")
	eq(f.title:GetText(), "Note on Edited-Other", "title")
	f.box:SetText("great tank")
	f.box:GetScript("OnEnterPressed")(f.box)
	eq(ns.Get("Edited-Other").text, "great tank", "saved")
	check(not f:IsShown(), "closed after save")
	ns.OpenEditor("Edited", "Other")
	eq(f.box:GetText(), "great tank", "prefilled")
	f:GetScript("OnKeyDown")(f, "ESCAPE")
	check(not f:IsShown(), "escape closes")
	ns.OpenEditor("Edited", "Other")
	f:Delete()
	eq(ns.Get("Edited-Other"), nil, "deleted")
	MOCK.combat = true
	ns.OpenEditor("Edited", "Other")
	f:GetScript("OnKeyDown")(f, "ESCAPE")
	check(not f:IsShown(), "escape closes in combat")
	MOCK.combat = false
end)

step("group join prints once per noted newcomer", function()
	ns.Set("Ganker", nil, "ninjalooted axe in ZF")
	MOCK.secretsOn = false
	MOCK.SetGroup(3, false)
	MOCK.units.party1.name, MOCK.units.party2.name = "Healer", "Ganker"
	local before = #MOCK.log
	MOCK.Fire("GROUP_ROSTER_UPDATE")
	eq(#MOCK.log - before, 1, "one line")
	check(lastLog():find("Ganker") and lastLog():find("ninjalooted"), "line text: " .. lastLog())
	MOCK.Fire("GROUP_ROSTER_UPDATE")
	eq(#MOCK.log - before, 1, "no repeat")
	MOCK.SetGroup(1, false); MOCK.Fire("GROUP_ROSTER_UPDATE")
	MOCK.secretsOn = true
	MOCK.SetGroup(5, true)
	for i = 2, 5 do MOCK.units["raid" .. i].name = "Ganker" end
	MOCK.Fire("GROUP_ROSTER_UPDATE") -- secret names: skipped, no error
	eq(#MOCK.log - before, 1, "secret names skipped")
	MOCK.SetGroup(1, false); MOCK.Fire("GROUP_ROSTER_UPDATE")
end)

step("hover hint: who, friends, roster, group finder; secret names skipped", function()
	local function fs(t) return { GetText = function() return t end } end
	local function row(fields, parent)
		fields.GetParent = function() return parent end
		return fields
	end
	ns.Set("Bob", nil, "cool healer")
	-- who row
	MOCK.foci = { row({ Name = fs("Bob"), Class = fs("Priest"), Level = fs("60"), Variable = fs("Orgrimmar") }) }
	ns.UpdateHover()
	check(PlayerNotesHint and PlayerNotesHint:IsShown(), "who hint shown")
	eq(PlayerNotesHint.text:GetText(), "Note: cool healer", "who hint text")
	-- unnoted row hides it
	MOCK.foci = { row({ Name = fs("Other"), Class = fs("Priest"), Level = fs("60"), Variable = fs("x") }) }
	ns.UpdateHover()
	check(not PlayerNotesHint:IsShown(), "hidden for unnoted")
	-- friends row
	ns.Set("Pal4", nil, "")
	ns.Set("Pal", nil, "old friend")
	C_FriendList.GetFriendInfoByIndex = function() return { name = "Pal" } end
	MOCK.foci = { row({ buttonType = FRIENDS_BUTTON_TYPE_WOW, id = 4 }) }
	ns.UpdateHover()
	eq(PlayerNotesHint.text:GetText(), "Note: old friend", "friends hint")
	-- guild/community roster row
	MOCK.foci = { row({ memberInfo = { name = "Bob-MockRealm" }, GetMemberList = function() end }) }
	ns.UpdateHover()
	eq(PlayerNotesHint.text:GetText(), "Note: cool healer", "roster hint")
	-- group finder listing: leader + members
	lfgResults[7] = { members = { "Leader", "Bob", "Pal" } }
	local scroll = row({}, LFGBrowseFrame)
	MOCK.foci = { row({ resultID = 7 }, scroll) }
	ns.UpdateHover()
	local t = PlayerNotesHint.text:GetText()
	check(t:find("Bob:|r cool healer", 1, true) and t:find("Pal:|r old friend", 1, true), "lfg hint: " .. t)
	-- listing outside the group finder is ignored
	MOCK.foci = { row({ resultID = 7 }, nil) }
	ns.UpdateHover()
	check(not PlayerNotesHint:IsShown(), "resultID outside LFGBrowseFrame ignored")
	-- secret names on a row
	MOCK.foci = { row({ memberInfo = { name = S("Bob") }, GetMemberList = function() end }) }
	ns.UpdateHover()
	check(not PlayerNotesHint:IsShown(), "secret roster name skipped")
	lfgResults[8] = { members = { S("Bob") } }
	MOCK.foci = { row({ resultID = 8 }, scroll) }
	ns.UpdateHover()
	check(not PlayerNotesHint:IsShown(), "secret lfg name skipped")
	MOCK.foci = {}
	ns.UpdateHover()
	check(not PlayerNotesHint:IsShown(), "nothing hovered")
end)

step("no Blizzard globals written, no hooks", function()
	local bad = {}
	for k in pairs(globalWrites) do if not OWN_GLOBALS[k] then bad[#bad + 1] = k end end
	table.sort(bad)
	check(#bad == 0, "addon wrote globals: " .. table.concat(bad, ", "))
	eq(hooks, 0, "hooksecurefunc calls")
	check(next(StaticPopupDialogs) == nil, "StaticPopupDialogs touched")
	check(#UISpecialFrames == 0, "UISpecialFrames touched")
end)

step("no errors reported", function()
	check(#MOCK.errors == 0, "errors: " .. table.concat(MOCK.errors, "\n"))
end)

print(("\n%d passed, %d failed"):format(passes, #failures))
return #failures
