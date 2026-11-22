-- Player Notes: where notes show up and where you can set them.
-- Only official extension points: Menu.ModifyMenu, TooltipDataProcessor (through the shared EverlookTooltip), chat message
-- filters, events, OnShow/OnHide script hooks on the social and group finder windows, and our own hint frame next to
-- list rows we only read from. No Blizzard function is hooked or replaced and no Blizzard frame field is written.
local ADDON, ns = ...
local U = ns.Util

local NoteFor = ns.Get

------------------------------------------------------------------------
-- Right-click menus: "Add note..." / "Edit note...", and the note itself under the name
------------------------------------------------------------------------
-- Every unit/player menu Blizzard tags; unknown tags are harmless (ModifyMenu only subscribes).
ns.MENU_TAGS = {
	"PLAYER", "PARTY", "RAID_PLAYER", "RAID", "ENEMY_PLAYER", "TARGET", "FOCUS",
	"FRIEND", "FRIEND_OFFLINE", "GUILD", "GUILD_OFFLINE", "CHAT_ROSTER",
	"COMMUNITIES_GUILD_MEMBER", "COMMUNITIES_WOW_MEMBER", "RECENT_ALLY", "RECENT_ALLY_OFFLINE",
}

-- Name and realm a menu is about, or nil (NPC, self, unknown or secret).
function ns.MenuTarget(contextData)
	if type(contextData) ~= "table" then return nil end
	local unit = contextData.unit
	if U.Secret(unit) then return nil end
	if U.Plain(unit) then
		local exists = UnitExists and UnitExists(unit)
		if U.Secret(exists) then return nil end
		if exists then
			local isSelf = UnitIsUnit and UnitIsUnit(unit, "player")
			if U.Secret(isSelf) or isSelf then return nil end
			return ns.UnitNameParts(unit) -- nil for NPCs: never fall back to their name
		end
	end
	local name, server = contextData.name, contextData.server
	if U.Secret(name) or U.Secret(server) then return nil end
	name = U.Plain(name)
	if not name then return nil end
	return name, U.Plain(server)
end

function ns.OnMenu(owner, root, contextData)
	local name, realm = ns.MenuTarget(contextData)
	if not name or not ns.Key(name, realm) then return end
	local e = NoteFor(name, realm)
	if e and ns.Opt("menu") and MenuUtil and MenuUtil.CreateTitle and root.Insert then
		-- Right under the player's name at the top of the menu.
		root:Insert(MenuUtil.CreateTitle(ns.COLOR .. U.Escape(U.Short(e.text, 60)) .. "|r"), 2)
	end
	if root.CreateDivider then root:CreateDivider() end
	root:CreateButton(e and "Edit note\226\128\166" or "Add note\226\128\166", function()
		ns.OpenEditor(name, realm)
	end)
end

local function InitMenus()
	if not (Menu and Menu.ModifyMenu) then return end
	for _, tag in ipairs(ns.MENU_TAGS) do
		Menu.ModifyMenu("MENU_UNIT_" .. tag, ns.OnMenu)
	end
end

------------------------------------------------------------------------
-- Unit tooltips (mouseover, unit frames, portraits)
------------------------------------------------------------------------
-- The note for the player a unit tooltip shows, or nil (NPC, no note, or a secret name).
function ns.UnitTooltipNote(tooltip, data)
	if not tooltip or not tooltip.GetUnit or not ns.Opt("tooltip") then return nil end
	local name, realm
	local _, unit = tooltip:GetUnit()
	if not U.Secret(unit) then name, realm = ns.UnitNameParts(unit) end
	if not name and type(data) == "table" and GetPlayerInfoByGUID then
		local guid = data.guid
		if U.Plain(guid) and guid:find("^Player%-") then
			local _, _, _, _, _, n, r = GetPlayerInfoByGUID(guid)
			if not U.Secret(n) and not U.Secret(r) then name, realm = U.Plain(n), U.Plain(r) end
		end
	end
	-- Party and raid frames (Lattice and others): inside instances the game can hide who a frame shows from addon
	-- code. The frame still says which unit it is (party1, raid7): look that up in the group as last read.
	if not name then
		local token = not U.Secret(unit) and U.Plain(unit) or nil
		if not token and tooltip.GetOwner then
			local okO, owner = pcall(tooltip.GetOwner, tooltip)
			if okO and type(owner) == "table" then
				local u = rawget(owner, "unit")
				if (u == nil or U.Secret(u)) and owner.GetAttribute then
					local okA, a = pcall(owner.GetAttribute, owner, "unit")
					u = okA and a or nil
				end
				token = not U.Secret(u) and U.Plain(u) or nil
			end
		end
		local r = token and ns.roster and ns.roster[token]
		if r then name, realm = r[1], r[2] end
	end
	return name and NoteFor(name, realm) or nil
end

-- On the shared EverlookDB tooltip layout (Libs/EverlookUI/EverlookTooltip.lua): "Note" in the label colour, the
-- note in the note colour, wrapped, last in the block of EverlookDB lines.
function ns.OnUnitTooltip(t, ctx)
	local e = ns.UnitTooltipNote(ctx.tooltip, ctx.data)
	if e then t:Text("Note", U.Escape(e.text), { color = ns.RGB }) end
end

local function InitTooltips()
	local Tip = LibStub and LibStub("EverlookTooltip-1", true)
	if Tip then
		Tip:Register({ id = "PlayerNotes.note", kind = "unit", order = Tip.ORDER.note, add = ns.OnUnitTooltip })
	end
end

------------------------------------------------------------------------
-- Chat: "[note] message" when the sender has a note
------------------------------------------------------------------------
ns.CHAT_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_EMOTE",
}
ns.CHAT_TAG_LEN = 40 -- default; the chatLength option overrides it

-- Returning just false leaves the message untouched; secret senders/messages are skipped.
-- No notes at all (or chat tags off): back out before any name work, so chat costs nothing.
function ns.ChatFilter(_, _, msg, author, ...)
	local notes = ns.db and ns.db.notes
	if not notes or next(notes) == nil then return false end
	if not ns.Opt("chat") or not U.Plain(msg) or not U.Plain(author) then return false end
	local e = NoteFor(author)
	if not e then return false end
	return false, ns.COLOR .. "[" .. U.Escape(U.Short(e.text, ns.Opt("chatLength") or ns.CHAT_TAG_LEN)) .. "]|r " .. msg, author, ...
end

local function InitChat()
	local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
	if not add then return end
	for _, event in ipairs(ns.CHAT_EVENTS) do add(event, ns.ChatFilter) end
end

------------------------------------------------------------------------
-- Group: one chat line when noted players join (one line in all, however many)
------------------------------------------------------------------------
local inGroup, seeded = {}, false

-- The line for the noted players who just joined: "Bob — cool healer", or for several
-- "Noted players joined: Bob (cool healer), Ganker (ninjalooted...)".
function ns.JoinLine(entries)
	if #entries == 0 then return nil end
	if #entries == 1 then
		local e = entries[1]
		return ns.Label(e) .. " \226\128\148 " .. ns.COLOR .. U.Escape(e.text) .. "|r"
	end
	local parts = {}
	for _, e in ipairs(entries) do
		parts[#parts + 1] = ns.Label(e) .. " (" .. ns.COLOR .. U.Escape(U.Short(e.text, 30)) .. "|r)"
	end
	return "Noted players joined: " .. table.concat(parts, ", ")
end

function ns.ScanGroup(silent)
	local now, joined = {}, {}
	local raid = IsInRaid()
	local n = raid and GetNumGroupMembers() or GetNumSubgroupMembers()
	-- who is behind each unit token, for frames whose tooltip can't say (UnitTooltipNote); names the game hides
	-- right now keep what was read before
	local old, roster = ns.roster or {}, {}
	ns.roster = roster
	for i = 1, n or 0 do
		local token = (raid and "raid" or "party") .. i
		local name, realm = ns.UnitNameParts(token)
		roster[token] = name and { name, realm } or old[token]
		local key = name and ns.Key(name, realm)
		if key and not now[key] then
			now[key] = true
			local e = ns.db.notes[key]
			if e and not inGroup[key] then joined[#joined + 1] = e end
		end
	end
	if seeded and not silent and ns.Opt("groupJoin") and #joined > 0 then
		table.sort(joined, function(a, b) return ns.Label(a):lower() < ns.Label(b):lower() end)
		ns:Print(ns.JoinLine(joined))
	end
	inGroup = now
	seeded = true
end

------------------------------------------------------------------------
-- Hover hint: lists we can't add tooltip lines to (group finder, who, friends,
-- guild roster) get our own small note box beside Blizzard's tooltip. We only
-- read the hovered row; each provider says how to find the player(s) on it.
------------------------------------------------------------------------
local function Under(frame, ancestor)
	if not ancestor then return false end
	local f = frame
	for _ = 1, 8 do
		if not f then return false end
		if f == ancestor then return true end
		f = f.GetParent and f:GetParent()
	end
	return false
end

local function Shown(f) return f and f.IsShown and f:IsShown() and f or nil end

ns.HoverProviders = {
	{ -- Group finder (Looking for Group > Browse): leader and members of the hovered listing
		id = "lfg",
		match = function(row)
			if type(row.resultID) ~= "number" or not C_LFGList or not Under(row, LFGBrowseFrame) then return end
			local names = {}
			local leader = C_LFGList.GetSearchResultLeaderInfo and C_LFGList.GetSearchResultLeaderInfo(row.resultID)
			if leader then names[#names + 1] = leader.name end
			local info = C_LFGList.GetSearchResultInfo(row.resultID)
			local count = info and info.numMembers or 0
			if not U.Secret(count) and count <= 40 and C_LFGList.GetSearchResultPlayerInfo then
				for i = 1, count do
					local m = C_LFGList.GetSearchResultPlayerInfo(row.resultID, i)
					if m and not m.isLeader then names[#names + 1] = m.name end
				end
			end
			return names
		end,
		anchor = function() return Shown(LFGBrowseSearchEntryTooltip) end,
	},
	{ -- Who list (Friends > Who and Looking for Group > Who)
		id = "who",
		match = function(row)
			if type(row.Variable) == "table" and type(row.Class) == "table" and type(row.Name) == "table" and row.Name.GetText then
				return { row.OriginalName or row.Name:GetText() }
			end
		end,
	},
	{ -- Friends list (character friends, and Battle.net friends playing a character)
		id = "friends",
		match = function(row)
			if type(row.buttonType) ~= "number" or type(row.id) ~= "number" then return end
			if row.buttonType == FRIENDS_BUTTON_TYPE_WOW and C_FriendList and C_FriendList.GetFriendInfoByIndex then
				local info = C_FriendList.GetFriendInfoByIndex(row.id)
				return { info and info.name }
			elseif row.buttonType == FRIENDS_BUTTON_TYPE_BNET and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
				local a = C_BattleNet.GetFriendAccountInfo(row.id)
				local g = a and a.gameAccountInfo
				if g and U.Plain(g.characterName) and U.Plain(g.realmName) then
					return { g.characterName .. "-" .. g.realmName }
				end
			end
		end,
		anchor = function() return Shown(FriendsTooltip) end,
	},
	{ -- Guild and community rosters
		id = "roster",
		match = function(row)
			local m = row.memberInfo
			if type(m) == "table" and type(row.GetMemberList) == "function" then return { m.name } end
		end,
	},
}

local hint
local function Hint()
	if hint then return hint end
	hint = CreateFrame("Frame", "PlayerNotesHint", UIParent)
	hint:SetFrameStrata("TOOLTIP")
	hint:SetClampedToScreen(true)
	hint:Hide()
	local bg = hint:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	bg:SetVertexColor(0.05, 0.05, 0.07, 0.94)
	bg:SetAllPoints()
	local edge = hint:CreateTexture(nil, "BORDER")
	hint.edge = edge
	edge:SetTexture("Interface\\Buttons\\WHITE8X8")
	edge:SetVertexColor(ns.RGB[1], ns.RGB[2], ns.RGB[3], 1)
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("BOTTOMLEFT")
	edge:SetWidth(2)
	hint.text = hint:CreateFontString(nil, "OVERLAY")
	if not hint.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "") then hint.text:SetFontObject(GameFontHighlightSmall) end
	hint.text:SetTextColor(ns.RGB[1], ns.RGB[2], ns.RGB[3], 1)
	hint.text:SetJustifyH("LEFT")
	hint.text:SetWordWrap(true)
	hint.text:SetPoint("TOPLEFT", 10, -7)
	return hint
end

-- The note colour option changed: the hint follows it.
function ns.RecolorHint()
	if not hint then return end
	hint.edge:SetVertexColor(ns.RGB[1], ns.RGB[2], ns.RGB[3], 1)
	hint.text:SetTextColor(ns.RGB[1], ns.RGB[2], ns.RGB[3], 1)
end

-- Lines for the noted players among `names` (strings; anything else is skipped).
function ns.HintLines(names, single)
	local lines, seen = {}, {}
	for _, raw in ipairs(names or {}) do
		local key = ns.Key(raw)
		local e = key and not seen[key] and ns.db.notes[key]
		if e then
			seen[key] = true
			lines[#lines + 1] = single and ("Note: " .. U.Escape(e.text))
				or ("|cffffffff" .. ns.Label(e) .. ":|r " .. U.Escape(e.text))
		end
	end
	return lines
end

-- Which provider claims the hovered frame (or one of its parents), and the player names.
function ns.MatchHover(focus)
	local f = focus
	for _ = 1, 3 do
		if not f or (f.IsForbidden and f:IsForbidden()) then return end
		for _, p in ipairs(ns.HoverProviders) do
			local ok, names = pcall(p.match, f)
			if ok and names then return p, f, names end
		end
		f = f.GetParent and f:GetParent()
	end
end

local lastFocus, lastSig
function ns.UpdateHover()
	local focus
	if GetMouseFoci then
		focus = GetMouseFoci()
		focus = type(focus) == "table" and focus[1] or nil
	elseif GetMouseFocus then
		focus = GetMouseFocus()
	end
	local p, row, names
	if focus and focus ~= WorldFrame and ns.Opt("hover") then p, row, names = ns.MatchHover(focus) end
	local lines = p and ns.HintLines(names, p.id ~= "lfg") or {}
	if #lines == 0 then
		if hint and hint:IsShown() then hint:Hide() end
		lastFocus, lastSig = nil, nil
		return
	end
	local text = table.concat(lines, "\n")
	local anchor = p.anchor and p.anchor()
	if not anchor and GameTooltip and GameTooltip:IsShown() and GameTooltip.IsOwned and GameTooltip:IsOwned(row) then anchor = GameTooltip end
	local sig = text .. tostring(anchor)
	if row == lastFocus and sig == lastSig and hint:IsShown() then return end
	lastFocus, lastSig = row, sig
	local h = Hint()
	h.text:SetWidth(260)
	h.text:SetText(text)
	local w = math.min(260, (h.text.GetUnboundedStringWidth and h.text:GetUnboundedStringWidth() or 260)) + 1
	h.text:SetWidth(w)
	h:SetSize(w + 18, h.text:GetStringHeight() + 14)
	h:ClearAllPoints()
	if anchor then
		h:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	else
		h:SetPoint("TOPLEFT", row, "TOPRIGHT", 8, 0)
	end
	h:Show()
end

-- The windows whose lists the hint reads. The mouse is only watched while one of them is open: no OnUpdate the rest
-- of the time (combat included). Some load on demand, so ones missing at login are picked up as their addon loads.
ns.HOVER_WINDOWS = {
	"FriendsFrame", "WhoFrame", "LFGParentFrame", "LFGBrowseFrame", "PVEFrame",
	"CommunitiesFrame", "GuildFrame", "ClubFinderGuildFinderFrame",
}
local watched = {}

function ns.HoverWindowOpen()
	for _, name in ipairs(ns.HOVER_WINDOWS) do
		local f = watched[name] and _G[name]
		if f and f:IsShown() then return true end
	end
	return false
end

-- Start or stop watching the mouse to match the windows.
function ns.UpdateHoverWatch()
	local w = ns.hoverWatcher
	if not w then return end
	if ns.HoverWindowOpen() then
		w:Show()
	else
		w:Hide()
		if hint and hint:IsShown() then hint:Hide() end
		lastFocus, lastSig = nil, nil
	end
end

-- Script hooks only (HookScript): Blizzard's own OnShow/OnHide run untouched first.
function ns.WatchHoverWindows()
	for _, name in ipairs(ns.HOVER_WINDOWS) do
		local f = not watched[name] and _G[name]
		if type(f) == "table" and f.HookScript then
			watched[name] = true
			f:HookScript("OnShow", ns.UpdateHoverWatch)
			f:HookScript("OnHide", ns.UpdateHoverWatch)
		end
	end
	ns.UpdateHoverWatch()
end

local function InitHover()
	local watcher = CreateFrame("Frame")
	watcher:Hide()
	local elapsed = 0
	watcher:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed < 0.1 then return end
		elapsed = 0
		ns.UpdateHover()
	end)
	ns.hoverWatcher = watcher
	ns.listeners[#ns.listeners + 1] = function() lastSig = nil end
	ns.WatchHoverWindows()
end

------------------------------------------------------------------------
-- Init (called from Core once SavedVariables are loaded)
------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
	if event == "ADDON_LOADED" then
		ns.WatchHoverWindows() -- group finder, guild and community windows load on demand
	elseif event == "PLAYER_ENTERING_WORLD" then
		if not seeded then ns.ScanGroup(true) end
	else
		ns.ScanGroup()
	end
end)

function ns.Init()
	InitMenus()
	InitTooltips()
	InitChat()
	InitHover()
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("GROUP_ROSTER_UPDATE")
	events:RegisterEvent("ADDON_LOADED")
end
