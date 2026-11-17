-- EverlookTooltip: one tidy layout for the lines quikmn's addons add to item and unit tooltips.
--
-- Single source of truth: D:\Dev\EverlookUI\EverlookTooltip.lua. Each addon that adds tooltip lines carries a copy
-- in Libs\EverlookUI\ (sync.py writes it). Versioned with LibStub: when several addons carry it, the newest copy is
-- the one every addon uses, and there is still only one hook per tooltip type. Bump MINOR whenever this file changes.
--
--   local Tip = LibStub("EverlookTooltip-1")
--   Tip:Register({ id = "auctions.price", kind = "item", order = Tip.ORDER.auction, add = function(t, ctx)
--     t:Line("Auction house", Tip.Money(95), { note = "3,365 listed · 76 min ago" })
--     t:Detail("30-day low / median", Tip.Money(93) .. " / " .. Tip.Money(95))
--   end })
--
-- Layout, the same for every addon:
--   * our lines sit together in one block under Blizzard's, after a blank line, in a fixed order (Tip.ORDER):
--     prices (auction house, 30-day, disenchant, vendor), then quest and source info, then notes;
--   * t:Line(label, value, opt): label left in the label colour, an optional muted note after it, the value right
--     (white; grey when opt.stale);
--   * t:Detail(label, value, opt): indented, grey, for the finer print. With Tip:SetDetail("shift") details show only
--     while Shift is held (default "always"); opt.always = true keeps a detail that its addon gates itself;
--   * t:Text(label, text, opt): label then wrapped text, for notes and lists (opt.color = { r, g, b } for the text);
--   * money always through Tip.Money: coin icons, copper dropped from 1g up, silver from 1,000g up.
-- ctx = { tooltip, data, kind, id, link }: id and link are nil when the game hid them (secret values).
-- Never does arithmetic on a secret value: Tip.Money, Tip.Count and the hook check issecretvalue first.
local MAJOR, MINOR = "EverlookTooltip-1", 1
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
Tip.ORDER = {
	auction = 10, history = 20, disenchant = 30, disenchantOwn = 35, vendor = 40,   -- prices
	quest = 50, source = 60,                                                          -- quest and source info
	alts = 70, note = 80,                                                             -- notes
}
Tip.INDENT = "    "
Tip.COLOR = {
	label  = { 0.74, 0.79, 0.88 },   -- muted blue-grey: what a line is
	note   = { 0.50, 0.54, 0.62 },   -- muted: how many, how old
	value  = { 1, 1, 1 },            -- the number that matters
	stale  = { 0.60, 0.60, 0.60 },   -- an old price
	detail = { 0.60, 0.63, 0.70 },   -- indented finer print
	detailValue = { 0.82, 0.82, 0.82 },
}
local function hex(c)
	return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
function Tip.Hex(c) return hex(c) end
Tip.SEP = " \194\183 "   -- " · " between the parts of a note

Tip.settings = Tip.settings or { detail = "always", spacer = true }
-- "always" (default) or "shift": whether detail lines need Shift held.
function Tip:SetDetail(mode) self.settings.detail = (mode == "shift") and "shift" or "always" end
function Tip:GetDetail() return self.settings.detail end

------------------------------------------------------------------------
-- Formatting
------------------------------------------------------------------------
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

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
-- 1,000g. opt.approx puts "~" in front. Nil for a secret or non-number.
function Tip.Money(copper, opt)
	copper = plain(copper)
	if type(copper) ~= "number" then return nil end
	copper = math.floor(copper + 0.5)
	if copper < 0 then copper = 0 end
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
	return ((opt and opt.approx) and "~" or "") .. table.concat(parts, " ")
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
	opt = opt or {}
	self.rows[#self.rows + 1] = { "line", label, value, opt }
end
function Sink:Detail(label, value, opt)
	opt = opt or {}
	self.rows[#self.rows + 1] = { "detail", label, value, opt }
end
function Sink:Text(label, text, opt)
	opt = opt or {}
	self.rows[#self.rows + 1] = { "text", label, text, opt }
end

local function shiftDown() return IsShiftKeyDown and IsShiftKeyDown() and true or false end

-- What a contribution's rows become: { left, right or nil, lr, lg, lb, rr, rg, rb, wrap } per tooltip line.
function Tip:Render(rows, shift)
	local out = {}
	local L, N = hex(self.COLOR.label), hex(self.COLOR.note)
	for _, row in ipairs(rows) do
		local kind, label, value, opt = row[1], row[2], row[3], row[4]
		if kind == "line" then
			local left = L .. tostring(label or "") .. "|r"
			if opt.note and opt.note ~= "" then left = left .. "  " .. N .. opt.note .. "|r" end
			local c = opt.stale and self.COLOR.stale or self.COLOR.value
			if value ~= nil and value ~= "" then
				out[#out + 1] = { left, tostring(value), 1, 1, 1, c[1], c[2], c[3] }
			else
				out[#out + 1] = { left, nil, 1, 1, 1 }
			end
		elseif kind == "detail" then
			if opt.always or self.settings.detail ~= "shift" or shift then
				local d, dv = self.COLOR.detail, self.COLOR.detailValue
				local left = self.INDENT .. tostring(label or "")
				if value ~= nil and value ~= "" then
					out[#out + 1] = { left, tostring(value), d[1], d[2], d[3], dv[1], dv[2], dv[3] }
				else
					out[#out + 1] = { left, nil, d[1], d[2], d[3] }
				end
			end
		elseif kind == "text" then
			local c = opt.color or self.COLOR.value
			local left = (label and label ~= "") and (L .. label .. "|r  ") or ""
			out[#out + 1] = { left .. tostring(value or ""), nil, c[1], c[2], c[3], nil, nil, nil, true }
		end
	end
	return out
end

-- Every registered contribution for this tooltip, in Tip.ORDER, as tooltip lines (see Render). Pure: no tooltip
-- is touched, so it can be tested and reused.
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
	local lines = {}
	for _, c in ipairs(sorted) do
		local sink = setmetatable({ rows = {} }, Sink)
		local okAdd, err = pcall(c.add, sink, ctx)
		if not okAdd then
			local handler = geterrorhandler and geterrorhandler()
			if handler then handler(err) end
		end
		for _, l in ipairs(self:Render(sink.rows, shift)) do lines[#lines + 1] = l end
	end
	return lines
end

function Tip:Draw(tooltip, lines)
	if #lines == 0 then return end
	if self.settings.spacer then tooltip:AddLine(" ") end
	for _, l in ipairs(lines) do
		if l[2] then
			tooltip:AddDoubleLine(l[1], l[2], l[3], l[4], l[5], l[6], l[7], l[8])
		else
			tooltip:AddLine(l[1], l[3], l[4], l[5], l[9] and true or false)
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
