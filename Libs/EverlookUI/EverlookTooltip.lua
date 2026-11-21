-- EverlookTooltip: one tidy layout for the lines quikmn's addons add to item and unit tooltips.
--
-- Single source of truth: D:\Dev\EverlookUI\EverlookTooltip.lua. Each addon that adds tooltip lines carries a copy
-- in Libs\EverlookUI\ (sync.py writes it). Versioned with LibStub: when several addons carry it, the newest copy is
-- the one every addon uses, and there is still only one hook per tooltip type. Bump MINOR whenever this file changes.
-- The rules in words: TOOLTIP-STYLE.md next to this file.
--
--   local Tip = LibStub("EverlookTooltip-1")
--   Tip:Register({ id = "auctions.price", kind = "item", order = Tip.ORDER.auction, add = function(t, ctx)
--     t:Line("Auction house", Tip.Money(95), { note = "3,365 listed · 76 min ago" })
--     t:Detail("30-day low", Tip.Money(93))
--   end })
--
-- Layout, the same for every addon:
--   * our lines sit together in one block under Blizzard's, after a blank line, in a fixed order (Tip.ORDER), in
--     groups: prices, gear upgrades, crafting, where it comes from, notes; a blank line between two groups;
--   * t:Line(label, value, opt): label left (light neutral), an optional softer note after it, the value right
--     (white). opt.tone = "good" | "bad" | "note" colours the value (green, red, the soft note tone); opt.stale = an
--     old value (muted); opt.color = { r, g, b } for the value;
--   * t:Detail(label, value, opt): indented finer print. With Tip:SetDetail("shift") details show only while Shift
--     is held (default "always"); opt.always = true keeps a detail that its addon gates itself; opt.labelColor;
--     opt.wrap wraps a detail without a value (a sentence);
--   * t:List(items, opt): up to opt.max (4) indented rows, then "and N more"; an item is a string or
--     { text, right, color = { r, g, b } };
--   * t:Text(label, text, opt): label then wrapped text, for notes (opt.color = { r, g, b } for the text);
--   * money always through Tip.Money, always alone in the right column: coin icons, copper dropped from 1g up,
--     silver from 1,000g up. When drawn, the coins of every price in the block line up in columns.
-- ctx = { tooltip, data, kind, id, link }: id and link are nil when the game hid them (secret values).
-- Never does arithmetic on a secret value: Tip.Money, Tip.Count and the hook check issecretvalue first.
--
-- Solid background (Tip:SetSolid, on by default): an opaque layer under the game's own tooltip background, so
-- nothing shows through. Left alone when a tooltip or UI skin addon (TipTac, ElvUI, ...) is loaded.
local MAJOR, MINOR = "EverlookTooltip-1", 2
local Tip = LibStub:NewLibrary(MAJOR, MINOR)
if not Tip then return end
Tip.version = MINOR

local isSecret = issecretvalue or function() return false end
-- A value that is safe to read, compare and do sums with: nil for a secret value.
local function plain(v)
	if v == nil or isSecret(v) then return nil end
	return v
end
Tip.Plain = plain

------------------------------------------------------------------------
-- Style
------------------------------------------------------------------------
-- The order of the lines; the tens say the group (a blank line between two groups).
Tip.ORDER = {
	auction = 10, history = 20, craftCost = 25, disenchant = 30, disenchantOwn = 35, vendor = 40, verdict = 41, -- prices
	gear = 50,                                                                                                    -- gear upgrades
	crafting = 60,                                                                                                -- crafting
	quest = 70, source = 75,                                                                                      -- where it comes from
	alts = 85, note = 90,                                                                                         -- notes
}
-- The group of an order number: below 50 prices, then gear, crafting, where it comes from, notes.
function Tip.GroupOf(order)
	order = tonumber(order) or 100
	if order < 50 then return "price" end
	if order < 60 then return "gear" end
	if order < 70 then return "crafting" end
	if order < 80 then return "source" end
	return "notes"
end

Tip.INDENT = "    "
-- A small palette, readable on the solid dark background.
Tip.COLOR = {
	label  = { 0.86, 0.87, 0.90 },   -- light neutral: what a line is
	note   = { 0.56, 0.66, 0.82 },   -- soft blue: how many, how old
	value  = { 1, 1, 1 },            -- the number that matters
	good   = { 0.36, 0.88, 0.44 },   -- profit, an upgrade, you can
	bad    = { 1.00, 0.45, 0.40 },   -- a loss, can't
	stale  = { 0.66, 0.68, 0.72 },   -- an old price, "not an upgrade"
	detail = { 0.78, 0.80, 0.85 },   -- indented finer print
	detailValue = { 0.92, 0.92, 0.94 },
	bg     = { 0.05, 0.05, 0.10 },   -- the solid layer under the tooltip (the game's own tooltip colour)
}
local function hex(c)
	return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
function Tip.Hex(c) return hex(c) end
-- Text in a palette colour ("good", "bad", "note", ...) or an { r, g, b }.
function Tip.Color(text, c)
	if text == nil then return nil end
	c = type(c) == "string" and Tip.COLOR[c] or c
	if type(c) ~= "table" then return tostring(text) end
	return hex(c) .. tostring(text) .. "|r"
end
Tip.SEP = " \194\183 "   -- " · " between the parts of a note

Tip.settings = Tip.settings or { detail = "always", spacer = true }
if Tip.settings.solid == nil then Tip.settings.solid = true end
Tip.settings.solidAt = Tip.settings.solidAt or 0
-- "always" (default) or "shift": whether detail lines need Shift held.
function Tip:SetDetail(mode) self.settings.detail = (mode == "shift") and "shift" or "always" end
function Tip:GetDetail() return self.settings.detail end

------------------------------------------------------------------------
-- Formatting
------------------------------------------------------------------------
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
local COIN = { GOLD, SILVER, COPPER }   -- by unit: 1 gold, 2 silver, 3 copper

local function group(n)
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- Whole numbers with thousands separators ("3,365"); nil for a secret or non-number.
function Tip.Count(n)
	n = plain(n)
	if type(n) ~= "number" then return nil end
	return group(math.floor(n + 0.5))
end

-- Money with coin icons, rounded the same way everywhere: exact below 1g, to the silver from 1g, to the gold from
-- 1,000g. opt.approx puts "~" in front; opt.sign puts "+" (or "-" for an amount below 0). Nil for a secret or
-- non-number.
function Tip.Money(copper, opt)
	copper = plain(copper)
	if type(copper) ~= "number" then return nil end
	copper = math.floor(copper + 0.5)
	local sign = ""
	if opt and opt.sign then
		sign = copper < 0 and "-" or "+"
		copper = math.abs(copper)
	elseif copper < 0 then
		copper = 0
	end
	if copper >= 10000000 then
		copper = math.floor(copper / 10000 + 0.5) * 10000
	elseif copper >= 10000 then
		copper = math.floor(copper / 100 + 0.5) * 100
	end
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = group(g) .. GOLD end
	if s > 0 then parts[#parts + 1] = s .. SILVER end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. COPPER end
	return ((opt and opt.approx) and "~" or "") .. sign .. table.concat(parts, " ")
end

-- The parts of a note joined with " · ", skipping empty ones.
function Tip.Join(...)
	local out = {}
	for i = 1, select("#", ...) do
		local p = select(i, ...)
		if type(p) == "string" and p ~= "" then out[#out + 1] = p end
	end
	return table.concat(out, Tip.SEP)
end

-- A player's name in their class colour (class = "MAGE", the class file name); plain when the class is unknown.
function Tip.ClassName(name, class)
	if not name then return nil end
	local cc
	if type(class) == "string" then
		if C_ClassColor and C_ClassColor.GetClassColor then
			local okC, c = pcall(C_ClassColor.GetClassColor, class)
			cc = okC and c or nil
		end
		cc = cc or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
	end
	if type(cc) == "table" and cc.r then return hex({ cc.r, cc.g, cc.b }) .. name .. "|r" end
	return name
end

-- "Anna, Bob, Cid +2": names (coloured or not), at most max (4) of them; the rest as a muted count.
function Tip.Names(list, max)
	max = max or 4
	if #list == max + 1 then max = #list end
	local shown = {}
	for i = 1, math.min(#list, max) do shown[i] = list[i] end
	local s = table.concat(shown, ", ")
	if #list > max then s = s .. " " .. hex(Tip.COLOR.note) .. "+" .. (#list - max) .. "|r" end
	return s
end

------------------------------------------------------------------------
-- Registration
------------------------------------------------------------------------
Tip.contrib = Tip.contrib or { item = {}, unit = {} }

-- spec = { id, kind = "item" | "unit", order, add = function(t, ctx) }. The same id again replaces the earlier one,
-- so a reloaded or second copy of an addon never adds its lines twice.
function Tip:Register(spec)
	assert(type(spec) == "table" and spec.id and spec.add, "EverlookTooltip: Register needs id and add")
	local list = self.contrib[spec.kind or "item"]
	assert(list, "EverlookTooltip: kind is item or unit")
	for i, c in ipairs(list) do
		if c.id == spec.id then list[i] = spec; return spec end
	end
	list[#list + 1] = spec
	return spec
end

function Tip:Unregister(id)
	for _, list in pairs(self.contrib) do
		for i = #list, 1, -1 do if list[i].id == id then table.remove(list, i) end end
	end
end

------------------------------------------------------------------------
-- Collecting and drawing
------------------------------------------------------------------------
local Sink = {}
Sink.__index = Sink

function Sink:Line(label, value, opt)
	self.rows[#self.rows + 1] = { "line", label, value, opt or {} }
end
function Sink:Detail(label, value, opt)
	self.rows[#self.rows + 1] = { "detail", label, value, opt or {} }
end
function Sink:Text(label, text, opt)
	self.rows[#self.rows + 1] = { "text", label, text, opt or {} }
end
-- Indented rows, at most opt.max (default 4), then "and N more" (opt.more = "more recipes" words it; never "and 1
-- more": that row is shown instead). Items are strings or { text, right, color = { r, g, b }, rightColor }. Finer
-- print, so behind Shift when details are, unless opt.always.
function Sink:List(items, opt)
	opt = opt or {}
	local n, max = #items, opt.max or 4
	if n == 0 then return end
	if n == max + 1 then max = n end
	for i = 1, math.min(n, max) do
		local it = items[i]
		if type(it) == "table" then
			self:Detail(it[1], it[2], { always = opt.always, labelColor = it.color, color = it.rightColor })
		else
			self:Detail(it, nil, { always = opt.always })
		end
	end
	if n > max then
		self:Detail(("and %d %s"):format(n - max, opt.more or "more"), nil, { always = opt.always, labelColor = Tip.COLOR.note })
	end
end

local function shiftDown() return IsShiftKeyDown and IsShiftKeyDown() and true or false end

-- What a contribution's rows become: { left, right or nil, lr, lg, lb, rr, rg, rb, wrap } per tooltip line.
function Tip:Render(rows, shift)
	local out = {}
	local C = self.COLOR
	local L, N = hex(C.label), hex(C.note)
	for _, row in ipairs(rows) do
		local kind, label, value, opt = row[1], row[2], row[3], row[4]
		if kind == "line" then
			local left = L .. tostring(label or "") .. "|r"
			if opt.note and opt.note ~= "" then left = left .. "  " .. N .. opt.note .. "|r" end
			local c = opt.color or (opt.tone and C[opt.tone]) or (opt.stale and C.stale) or C.value
			if value ~= nil and value ~= "" then
				out[#out + 1] = { left, tostring(value), 1, 1, 1, c[1], c[2], c[3] }
			else
				out[#out + 1] = { left, nil, 1, 1, 1 }
			end
		elseif kind == "detail" then
			if opt.always or self.settings.detail ~= "shift" or shift then
				local d = opt.labelColor or C.detail
				local dv = opt.color or (opt.tone and C[opt.tone]) or (opt.stale and C.stale) or C.detailValue
				local left = self.INDENT .. tostring(label or "")
				if opt.note and opt.note ~= "" then left = left .. "  " .. N .. opt.note .. "|r" end
				if value ~= nil and value ~= "" then
					out[#out + 1] = { left, tostring(value), d[1], d[2], d[3], dv[1], dv[2], dv[3] }
				else
					out[#out + 1] = { left, nil, d[1], d[2], d[3], nil, nil, nil, opt.wrap and true or nil }
				end
			end
		elseif kind == "text" then
			local c = opt.color or C.value
			local left = (label and label ~= "") and (L .. label .. "|r  ") or ""
			out[#out + 1] = { left .. tostring(value or ""), nil, c[1], c[2], c[3], nil, nil, nil, true }
		end
	end
	return out
end

-- Every registered contribution for this tooltip, in Tip.ORDER, as tooltip lines (see Render), with a blank line
-- between two groups. Pure: no tooltip is touched, so it can be tested and reused.
function Tip:Collect(kind, ctx, shift)
	local list = self.contrib[kind]
	if not list or #list == 0 then return {} end
	local sorted = {}
	for i, c in ipairs(list) do sorted[i] = c end
	-- stable: equal orders keep their registration order
	local pos = {}
	for i, c in ipairs(sorted) do pos[c] = i end
	table.sort(sorted, function(a, b)
		local oa, ob = a.order or 100, b.order or 100
		if oa ~= ob then return oa < ob end
		return pos[a] < pos[b]
	end)
	local lines, lastGroup = {}, nil
	for _, c in ipairs(sorted) do
		local sink = setmetatable({ rows = {} }, Sink)
		local okAdd, err = pcall(c.add, sink, ctx)
		if not okAdd then
			local handler = geterrorhandler and geterrorhandler()
			if handler then handler(err) end
		end
		local rendered = self:Render(sink.rows, shift)
		if #rendered > 0 then
			local g = Tip.GroupOf(c.order)
			if lastGroup and g ~= lastGroup then lines[#lines + 1] = { " ", nil, 1, 1, 1, gap = true } end
			lastGroup = g
			for _, l in ipairs(rendered) do lines[#lines + 1] = l end
		end
	end
	return lines
end

------------------------------------------------------------------------
-- Money in columns
------------------------------------------------------------------------
local UNIT = { Gold = 1, Silver = 2, Copper = 3 }
local COINPART = "^(.-)([%d,]+)|TInterface\\MoneyFrame\\UI%-(%a+)Icon:0:0:2:0|t$"

-- The money a right-column text ends with: its coin parts as { digits, unit } (1 gold, 2 silver, 3 copper), the
-- text before them ("+", "~") and the colour ends after them; nil when the text doesn't end in Tip.Money's coins.
local function moneyParts(text)
	if type(text) ~= "string" then return nil end
	local body, tail = text, ""
	while body:sub(-2) == "|r" do body, tail = body:sub(1, -3), tail .. "|r" end
	local parts, rest = {}, body
	while true do
		local before, digits, name = rest:match(COINPART)
		if not before or not UNIT[name] then break end
		table.insert(parts, 1, { digits, UNIT[name] })
		rest = before
		-- another coin right before, after one space
		local prev = rest:match("^(.-) $")
		if not (prev and prev:match(COINPART)) then break end
		rest = prev
	end
	if #parts == 0 then return nil end
	return parts, rest, tail
end
Tip.MoneyParts = moneyParts

-- An invisible gap w pixels wide (the transparent corner of the copper coin, stretched).
function Tip.Spacer(w)
	w = math.floor((tonumber(w) or 0) + 0.5)
	if w <= 0 then return "" end
	return ("|TInterface\\MoneyFrame\\UI-CopperIcon:1:%d:0:0:16:16:0:1:0:1|t"):format(w)
end

-- Lines up the coins of every price in the right column: silver and copper amounts take two digits' room, and a
-- price that stops at a bigger coin than the others gets the room of the missing coins after it. m = { digit,
-- space, icon }: pixel widths of one digit, a space and a coin. Changes lines in place.
function Tip:AlignMoney(lines, m)
	if type(m) ~= "table" or not m.digit or m.digit <= 0 then return lines end
	local found, smallest = {}, 1
	for i, l in ipairs(lines) do
		local parts, before, tail = moneyParts(l[2])
		if parts then
			found[i] = { parts, before, tail }
			if parts[#parts][2] > smallest then smallest = parts[#parts][2] end
		end
	end
	local coinW = (m.space or 0) + 2 * m.digit + (m.icon or 0)   -- the room of " 39c"
	for i, f in pairs(found) do
		local parts, before, tail = f[1], f[2], f[3]
		local out = {}
		for k, p in ipairs(parts) do
			local pad = (k > 1 and #p[1] == 1) and Tip.Spacer(m.digit) or ""
			out[k] = pad .. p[1] .. COIN[p[2]]
		end
		local missing = smallest - parts[#parts][2]
		lines[i][2] = before .. table.concat(out, " ") .. (missing > 0 and Tip.Spacer(missing * coinW) or "") .. tail
	end
	return lines
end

-- Pixel widths of a digit, a space and a coin in the tooltip's right-column font, measured once per font.
local measureFS
function Tip:Metrics(tooltip)
	local name = tooltip and tooltip.GetName and tooltip:GetName()
	local fs = name and _G[name .. "TextRight2"]
	local font, size, flags
	if fs and fs.GetFont then font, size, flags = fs:GetFont() end
	if not font and GameTooltipText and GameTooltipText.GetFont then font, size, flags = GameTooltipText:GetFont() end
	size = plain(size)
	if not font or type(size) ~= "number" or size <= 0 then return nil end
	self.metrics = self.metrics or {}
	local key = tostring(font) .. ":" .. size .. ":" .. tostring(flags)
	if self.metrics[key] then return self.metrics[key] end
	if not measureFS then
		if not (CreateFrame and UIParent) then return nil end
		local okF, holder = pcall(CreateFrame, "Frame", nil, UIParent)
		if not okF or type(holder) ~= "table" or not holder.CreateFontString then return nil end
		holder:Hide()
		measureFS = holder:CreateFontString(nil, "ARTWORK")
	end
	if not pcall(measureFS.SetFont, measureFS, font, size, flags or "") then return nil end
	local function width(s) measureFS:SetText(s); return plain(measureFS:GetStringWidth()) or 0 end
	local digit = width("0000000000") / 10
	if digit <= 0 then return nil end
	local m = { digit = digit, space = math.max(0, width("0 0") - width("00")), icon = size }
	self.metrics[key] = m
	return m
end

function Tip:Draw(tooltip, lines)
	if #lines == 0 then return end
	local okM, m = pcall(self.Metrics, self, tooltip)
	if okM and m then pcall(self.AlignMoney, self, lines, m) end
	local indent = #self.INDENT
	if self.settings.spacer then tooltip:AddLine(" ") end
	for _, l in ipairs(lines) do
		if l[2] then
			tooltip:AddDoubleLine(l[1], l[2], l[3], l[4], l[5], l[6], l[7], l[8])
		else
			local text = l[1]
			-- a wrapped detail keeps its indent as a gap of the same width (spaces at the start of a wrapped line can go)
			if l[9] and okM and m and m.space and text:sub(1, indent) == self.INDENT then
				text = Tip.Spacer(indent * m.space) .. text:sub(indent + 1)
			end
			tooltip:AddLine(text, l[3], l[4], l[5], l[9] and true or false)
		end
	end
end

-- The item and unit a tooltip shows, as plain values (nil when the game hid them).
local function itemContext(tooltip, data)
	local ctx = { tooltip = tooltip, data = data, kind = "item" }
	local id = type(data) == "table" and plain(data.id) or nil
	ctx.id = type(id) == "number" and id or nil
	local link = type(data) == "table" and plain(data.hyperlink) or nil
	if not link and tooltip.GetItem then
		local okItem, _, l = pcall(tooltip.GetItem, tooltip)
		link = okItem and plain(l) or nil
	end
	ctx.link = type(link) == "string" and link or nil
	return ctx
end

local function unitContext(tooltip, data)
	local ctx = { tooltip = tooltip, data = data, kind = "unit" }
	ctx.guid = type(data) == "table" and plain(data.guid) or nil
	if tooltip.GetUnit then
		local okUnit, _, unit = pcall(tooltip.GetUnit, tooltip)
		ctx.unit = okUnit and plain(unit) or nil
	end
	return ctx
end

function Tip:Run(kind, tooltip, data)
	if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
	local list = self.contrib[kind]
	if not list or #list == 0 then return end
	local ctx = kind == "item" and itemContext(tooltip, data) or unitContext(tooltip, data)
	self:Draw(tooltip, self:Collect(kind, ctx, shiftDown()))
end

------------------------------------------------------------------------
-- Solid background
------------------------------------------------------------------------
-- Addons that draw their own tooltip look: with one of them loaded the background is theirs.
Tip.SKINS = { "TipTac", "TinyTooltip", "TinyTooltip-Reforged", "ElvUI", "Tukui", "GW2_UI", "NDui", "KkthnxUI",
	"Aurora", "AuroraClassic", "RealUI", "SpartanUI", "LUI", "ShestakUI", "Skinner", "FreebTip", "CowTip", "TipTop",
	"TooltipsPlus", "BetterTooltips", "SuperVillain" }
-- The game's item and unit tooltips (the compare tooltips too, so they look the same side by side).
Tip.TOOLTIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1",
	"ItemRefShoppingTooltip2" }

local function addonLoaded(name)
	local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
	if not f then return false end
	local okL, loaded = pcall(f, name)
	return okL and plain(loaded) and true or false
end

-- The name of a loaded tooltip or UI skin addon, or nil. Asked again until the player is in the world, then kept.
function Tip:OtherSkin()
	if self.skinChecked then return self.skin end
	local found
	for _, name in ipairs(self.SKINS) do
		if addonLoaded(name) then found = name; break end
	end
	if IsLoggedIn and IsLoggedIn() then self.skinChecked = true end
	self.skin = found
	return found
end

-- on: true (default) or false. at: when the player chose it (time()); a choice older than the one in effect is
-- ignored, so the newest choice made in any of our addons wins, whatever order they load in.
function Tip:SetSolid(on, at)
	at = tonumber(at) or 0
	if at < (self.settings.solidAt or 0) then return end
	self.settings.solid = on ~= false
	self.settings.solidAt = at
	self:RefreshSolid()
end
function Tip:GetSolid() return self.settings.solid ~= false end

-- Puts the opaque layer under a tooltip's own background (same frame, lowest sublevel), or hides it.
function Tip:ApplySolid(tooltip)
	if type(tooltip) ~= "table" or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
	local layer = tooltip.EverlookSolid
	if not (self:GetSolid() and not self:OtherSkin()) then
		if layer then layer:Hide() end
		return
	end
	if not layer then
		local host = tooltip.NineSlice or tooltip
		if not host.CreateTexture then return end
		layer = host:CreateTexture(nil, "BACKGROUND", nil, -8)
		local center = tooltip.NineSlice and tooltip.NineSlice.Center
		if center then
			layer:SetAllPoints(center)
		else
			layer:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 3, -3)
			layer:SetPoint("BOTTOMRIGHT", tooltip, "BOTTOMRIGHT", -3, 3)
		end
		tooltip.EverlookSolid = layer
	end
	local c = self.COLOR.bg
	layer:SetColorTexture(c[1], c[2], c[3], 1)
	layer:Show()
end

function Tip:RefreshSolid()
	for _, name in ipairs(self.TOOLTIPS) do
		local t = _G[name]
		if type(t) == "table" then pcall(self.ApplySolid, self, t) end
	end
end

-- For an addon's settings window (EverlookUI app): the "Solid tooltip background" switch, key "tipsolid". store()
-- returns the addon's saved table, where the choice is kept (tipSolid, tipSolidAt); Tip:LoadSolid(saved) at load.
function Tip:SolidSetting(app, store)
	if not (app and app.Setting) then return end
	app:Setting({
		key = "tipsolid", type = "bool", label = "Solid tooltip background", default = true,
		desc = "Item and unit tooltips get an opaque background, so nothing shows through them. Shared by every "
			.. "EverlookDB addon; left alone when a tooltip skin addon (TipTac, ElvUI and the like) is loaded.",
		keywords = { "tooltip", "opacity", "opaque", "transparent", "see-through", "background", "solid", "alpha" },
		get = function() return Tip:GetSolid() end,
		set = function(v)
			-- what the player picks now always applies (the clock can't make it older than the choice in effect)
			local at = math.max(time and time() or 0, Tip.settings.solidAt or 0)
			local s = store and store()
			if type(s) == "table" then s.tipSolid = v and true or false; s.tipSolidAt = at end
			Tip:SetSolid(v and true or false, at)
		end,
	})
end
function Tip:LoadSolid(saved)
	if type(saved) == "table" and saved.tipSolid ~= nil then self:SetSolid(saved.tipSolid, saved.tipSolidAt or 0) end
end

-- One hook per tooltip type, whichever copy loads first; it always calls the newest Run.
Tip.hooked = Tip.hooked or {}
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	for kind, typ in pairs({ item = Enum.TooltipDataType.Item, unit = Enum.TooltipDataType.Unit }) do
		if typ ~= nil and not Tip.hooked[kind] then
			Tip.hooked[kind] = true
			TooltipDataProcessor.AddTooltipPostCall(typ, function(tooltip, data) Tip:Run(kind, tooltip, data) end)
		end
	end
end
-- The solid background, each time one of the game's tooltips shows.
Tip.hooked.solid = Tip.hooked.solid or {}
for _, name in ipairs(Tip.TOOLTIPS) do
	local t = _G[name]
	if type(t) == "table" and t.HookScript and not Tip.hooked.solid[name] then
		Tip.hooked.solid[name] = true
		pcall(t.HookScript, t, "OnShow", function(self) Tip:ApplySolid(self) end)
	end
end
