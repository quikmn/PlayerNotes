-- Player Notes: core (names, storage, slash command).
-- Notes live only in PlayerNotesDB (SavedVariables). Nothing is ever sent anywhere.
local ADDON, ns = ...
ns.name = ADDON

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local U = {}
ns.Util = U

ns.COLOR = "|cffffb347"          -- note text colour (light amber)
ns.RGB = { 1, 0.70, 0.28 }
ns.MAX_LEN = 255

-- Secret values (Forever, in combat/instances): comparing, indexing or joining them errors.
function U.Secret(v)
	return v ~= nil and issecretvalue ~= nil and issecretvalue(v) and true or false
end

-- A usable, non-empty, non-secret string, or nil.
function U.Plain(v)
	if v == nil or U.Secret(v) or type(v) ~= "string" or v == "" then return nil end
	return v
end

function U.Trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Shorten to `n` bytes without cutting a UTF-8 character in half.
function U.Short(s, n)
	if #s <= n then return s end
	local cut = n
	while cut > 0 do
		local b = s:byte(cut + 1)
		if not b or b < 0x80 or b >= 0xC0 then break end
		cut = cut - 1
	end
	return (s:sub(1, cut):gsub("%s+$", "")) .. "..."
end

-- Show user text literally in a font string (a lone "|" starts an escape code).
function U.Escape(s) return (s:gsub("|", "||")) end

function ns:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffff9933Player Notes|r: " .. tostring(msg))
end

------------------------------------------------------------------------
-- Names. Notes are keyed "name-realm" in lower case; own realm is filled in.
------------------------------------------------------------------------
function ns.OwnRealm()
	local r = GetNormalizedRealmName and GetNormalizedRealmName()
	if not U.Plain(r) then r = U.Plain(GetRealmName and GetRealmName()) or "" end
	return (r:gsub("[%s%-]", ""))
end

-- Case changes touch A-Z only: string.lower/upper follow the C locale and can
-- mangle UTF-8 bytes (Zoë).
local function AsciiLower(s) return (s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)) end
local function AsciiUpper(s) return (s:gsub("[a-z]", function(c) return string.char(c:byte() - 32) end)) end

-- Key("Bob"), Key("Bob-Realm"), Key("Bob", "Some Realm") -> key, Name, Realm.
-- nil for secret, empty or impossible names.
function ns.Key(name, realm)
	if U.Secret(realm) then return nil end
	name = U.Plain(name)
	if not name then return nil end
	name = U.Trim(name)
	realm = U.Plain(realm)
	if not realm then
		local n, r = name:match("^([^%-]+)%-(.+)$")
		if n then name, realm = n, r end
	end
	-- Letters only (any non-ASCII byte counts as a letter: names like Zoë).
	if name == "" or name:find("[%z\1-\64\91-\96\123-\127]") then return nil end
	if UNKNOWNOBJECT and name == UNKNOWNOBJECT then return nil end
	realm = (realm or ns.OwnRealm()):gsub("[%s%-]", "")
	if realm == "" then realm = ns.OwnRealm() end
	name = AsciiUpper(name:sub(1, 1)) .. name:sub(2)
	return AsciiLower(name .. "-" .. realm), name, realm
end

-- Name and realm of a player unit, or nil (not a player, missing, or secret).
function ns.UnitNameParts(unit)
	if not U.Plain(unit) then return nil end
	if not UnitExists or not UnitIsPlayer then return nil end
	local exists = UnitExists(unit)
	if U.Secret(exists) or not exists then return nil end
	local isPlayer = UnitIsPlayer(unit)
	if U.Secret(isPlayer) or not isPlayer then return nil end
	local name, realm = UnitName(unit)
	if U.Secret(name) or U.Secret(realm) then return nil end
	return U.Plain(name), U.Plain(realm)
end

-- "Bob" on your own realm, "Bob-Realm" otherwise.
function ns.Label(entry)
	if entry.realm == ns.OwnRealm() then return entry.name end
	return entry.name .. "-" .. entry.realm
end

------------------------------------------------------------------------
-- Storage
------------------------------------------------------------------------
local function Notes() return ns.db and ns.db.notes or {} end

function ns.Get(name, realm)
	local key = ns.Key(name, realm)
	return key and Notes()[key] or nil
end

function ns.Clean(text)
	if not U.Plain(text) then return "" end
	text = U.Trim((text:gsub("[%c]+", " ")))
	if #text > ns.MAX_LEN then text = U.Short(text, ns.MAX_LEN - 3) end
	return text
end

-- Empty text deletes. Returns the entry (or nil when deleted / bad name).
function ns.Set(name, realm, text)
	local key, n, r = ns.Key(name, realm)
	if not key then return nil end
	text = ns.Clean(text)
	if text == "" then
		Notes()[key] = nil
		ns.Changed()
		return nil
	end
	local entry = { name = n, realm = r, text = text, date = time() }
	Notes()[key] = entry
	ns.Changed()
	return entry
end

function ns.Delete(name, realm)
	local key = ns.Key(name, realm)
	if not key or not Notes()[key] then return false end
	Notes()[key] = nil
	ns.Changed()
	return true
end

-- Other files hook in here (hover hint refresh etc.).
ns.listeners = {}
function ns.Changed()
	for _, fn in ipairs(ns.listeners) do fn() end
end

function ns.Date(entry)
	return entry.date and date("%Y-%m-%d", entry.date) or "?"
end

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------
local function TargetParts()
	local n, r = ns.UnitNameParts("target")
	if n then return { n, r } end
end

-- Pure parser (tested offline). target = { name, realm } or nil.
-- With a player targeted, "/note <text>" notes the target; the first word is
-- taken as a name only when it has a realm ("Bob-Realm"), starts with "@",
-- already has a note, or is the target's own name. Without a target the first
-- word is always the name.
function ns.ParseSlash(msg, target)
	msg = U.Trim(U.Plain(msg) or "")
	if msg == "" then
		if target then return { cmd = "edit", name = target[1], realm = target[2] } end
		return { cmd = "help" }
	end
	local first, rest = msg:match("^(%S+)%s*(.*)$")
	local word = first:lower()
	if rest == "" and (word == "help" or word == "?") then return { cmd = "help" } end
	if rest == "" and word == "list" then return { cmd = "list" } end
	if word == "del" or word == "delete" or word == "remove" then
		if rest == "" then
			if target then return { cmd = "del", name = target[1], realm = target[2] } end
			return { cmd = "help" }
		end
		if not rest:find("%s") then return { cmd = "del", name = (rest:gsub("^@", "")) } end
	end

	local who = first:gsub("^@", "")
	local asName = not target or first:sub(1, 1) == "@" or first:find("^[^%-]+%-.+$") ~= nil
	if not asName then
		local key = ns.Key(who)
		asName = key ~= nil and (Notes()[key] ~= nil or key == ns.Key(target[1], target[2]))
	end
	if asName then
		if not ns.Key(who) then return { cmd = "bad", name = who } end
		if rest == "" then return { cmd = "show", name = who } end
		return { cmd = "set", name = who, text = rest }
	end
	return { cmd = "set", name = target[1], realm = target[2], text = msg }
end

local HELP = {
	"/note <text> - note on your target",
	"/note Name <text> (or Name-Realm) - note on anyone",
	"/note Name - show a note,  /note del Name - delete it",
	"/note list - all notes,  /note - edit your target's note",
	"Or right-click a player (portrait, party/raid frame, name in chat) > Add note.",
}

function ns.RunSlash(msg)
	local p = ns.ParseSlash(msg, TargetParts())
	if p.cmd == "help" then
		for _, line in ipairs(HELP) do ns:Print(line) end
	elseif p.cmd == "list" then
		local rows = {}
		for _, e in pairs(Notes()) do rows[#rows + 1] = e end
		table.sort(rows, function(a, b) return ns.Label(a):lower() < ns.Label(b):lower() end)
		if #rows == 0 then ns:Print("No notes yet. /note help") end
		for _, e in ipairs(rows) do
			ns:Print(ns.Label(e) .. ": " .. ns.COLOR .. U.Escape(e.text) .. "|r (" .. ns.Date(e) .. ")")
		end
	elseif p.cmd == "edit" then
		ns.OpenEditor(p.name, p.realm)
	elseif p.cmd == "bad" then
		ns:Print("'" .. U.Escape(p.name) .. "' is not a player name.")
	else
		local _, n, r = ns.Key(p.name, p.realm)
		local label = ns.Label({ name = n, realm = r })
		if p.cmd == "del" then
			ns:Print(ns.Delete(p.name, p.realm) and ("Deleted the note on " .. label .. ".") or ("No note on " .. label .. "."))
		elseif p.cmd == "show" then
			local e = ns.Get(p.name, p.realm)
			if e then
				ns:Print(label .. ": " .. ns.COLOR .. U.Escape(e.text) .. "|r (" .. ns.Date(e) .. ")")
			else
				ns:Print("No note on " .. label .. ". /note " .. label .. " <text> adds one.")
			end
		elseif p.cmd == "set" then
			local e = ns.Set(p.name, p.realm, p.text)
			if e then ns:Print("Note on " .. label .. ": " .. ns.COLOR .. U.Escape(e.text) .. "|r") end
		end
	end
	return p
end

SLASH_PLAYERNOTES1 = "/note"
SLASH_PLAYERNOTES2 = "/playernotes"
SlashCmdList.PLAYERNOTES = function(msg) ns.RunSlash(msg) end

------------------------------------------------------------------------
-- Boot
------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, event, name)
	if name ~= ADDON then return end
	self:UnregisterEvent("ADDON_LOADED")
	PlayerNotesDB = PlayerNotesDB or {}
	PlayerNotesDB.version = PlayerNotesDB.version or 1
	PlayerNotesDB.notes = PlayerNotesDB.notes or {}
	ns.db = PlayerNotesDB
	if ns.Init then ns.Init() end
end)
