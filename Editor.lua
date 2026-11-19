-- Player Notes: the note editor. Our own small window, not a StaticPopup and not in
-- UISpecialFrames: both are Blizzard's, and an addon touching them taints Blizzard's
-- own dialogs and windows (secret-value errors on closing the character sheet etc.).
local ADDON, ns = ...
local U = ns.Util

local C = {
	bg      = { 0.071, 0.078, 0.094, 0.97 },
	surface = { 0.105, 0.114, 0.137, 1 },
	hi      = { 0.137, 0.149, 0.180, 1 },
	border  = { 0.180, 0.196, 0.235, 1 },
	text    = { 0.902, 0.910, 0.933, 1 },
	muted   = { 0.553, 0.580, 0.639, 1 },
	accent  = { 1.000, 0.600, 0.200, 1 },
	danger  = { 0.937, 0.365, 0.365, 1 },
}
local WHITE = "Interface\\Buttons\\WHITE8X8"
local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

local function Solid(parent, layer, c)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(WHITE)
	t:SetVertexColor(rgba(c))
	return t
end

local function Border(parent, c)
	local edges = {}
	for i, p in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = Solid(parent, "BORDER", c)
		t:SetPoint(p[1])
		t:SetPoint(p[2])
		if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
		edges[i] = t
	end
	function edges:SetColor(c2) for i = 1, 4 do self[i]:SetVertexColor(rgba(c2)) end end
	return edges
end

local function Text(parent, size, c)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	if not fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "") then fs:SetFontObject(GameFontHighlightSmall) end
	fs:SetTextColor(rgba(c))
	fs:SetJustifyH("LEFT")
	return fs
end

local function Button(parent, label, color, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(84, 24)
	b.bg = Solid(b, "BACKGROUND", C.surface)
	b.bg:SetAllPoints()
	Border(b, color or C.border)
	b.label = Text(b, 12, color or C.text)
	b.label:SetPoint("CENTER")
	b.label:SetText(label)
	b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(rgba(C.hi)) end)
	b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(rgba(C.surface)) end)
	b:SetScript("OnClick", onClick)
	return b
end

-- Escape closes the window through its own key handler (same as Lattice/Whack).
-- SetPropagateKeyboardInput is blocked in combat: then the window leaves the keyboard alone.
local function CloseOnEscape(frame)
	frame:HookScript("OnShow", function(self)
		local ok = not InCombatLockdown()
		if ok then self:SetPropagateKeyboardInput(true) end
		self:EnableKeyboard(ok)
	end)
	frame:SetScript("OnKeyDown", function(self, key)
		local esc = key == "ESCAPE"
		if not InCombatLockdown() then self:SetPropagateKeyboardInput(not esc) end
		if esc then self:Hide() end
	end)
end

local editor

local function Build()
	local f = CreateFrame("Frame", "PlayerNotesEditor", UIParent)
	f:SetSize(380, 124)
	f:SetPoint("CENTER", 0, 160)
	f:SetFrameStrata("FULLSCREEN_DIALOG") -- above the notes window (DIALOG), which opens it
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	Solid(f, "BACKGROUND", C.bg):SetAllPoints()
	Border(f, C.border)

	f.title = Text(f, 14, C.text)
	f.title:SetPoint("TOPLEFT", 14, -12)
	f.title:SetPoint("RIGHT", -36, 0)

	local close = CreateFrame("Button", nil, f)
	close:SetSize(24, 24)
	close:SetPoint("TOPRIGHT", -6, -6)
	close.label = Text(close, 14, C.muted)
	close.label:SetPoint("CENTER")
	close.label:SetText("x")
	close:SetScript("OnClick", function() f:Hide() end)

	local box = CreateFrame("EditBox", nil, f)
	box:SetSize(352, 26)
	box:SetPoint("TOPLEFT", 14, -38)
	box:SetAutoFocus(false)
	box:SetMaxLetters(ns.MAX_LEN)
	box:SetTextInsets(8, 8, 0, 0)
	if not box:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "") then box:SetFontObject(GameFontHighlightSmall) end
	box:SetTextColor(rgba(C.text))
	Solid(box, "BACKGROUND", C.surface):SetAllPoints()
	box.border = Border(box, C.border)
	box:SetScript("OnEditFocusGained", function(self) self.border:SetColor(C.accent) end)
	box:SetScript("OnEditFocusLost", function(self) self.border:SetColor(C.border) end)
	box:SetScript("OnEnterPressed", function() f:Save() end)
	box:SetScript("OnEscapePressed", function() f:Hide() end)
	f.box = box

	f.info = Text(f, 11, C.muted)
	f.info:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 2, -6)

	local save = Button(f, "Save", C.accent, function() f:Save() end)
	save:SetPoint("BOTTOMRIGHT", -14, 12)
	-- two clicks, as in the notes window: the first asks, a second within 4 seconds deletes
	local del
	del = Button(f, "Delete", C.danger, function()
		if not del.armed then
			del.armed = GetTime()
			del.label:SetText("Click again")
			local armedAt = del.armed
			C_Timer.After(4, function() if del.armed == armedAt then del.armed = nil; del.label:SetText("Delete") end end)
			return
		end
		del.armed = nil
		del.label:SetText("Delete")
		f:Delete()
	end)
	del:SetPoint("RIGHT", save, "LEFT", -8, 0)
	f.del = del

	function f:Open(name, realm)
		local key, n, r = ns.Key(name, realm)
		if not key then return end
		self.n, self.r = n, r
		local label = ns.Label({ name = n, realm = r })
		self.title:SetText("Note on " .. label)
		local e = ns.Get(n, r)
		self.box:SetText(e and e.text or "")
		self.info:SetText(e and ("Set " .. ns.Date(e) .. ". Enter saves, Escape closes.") or "Enter saves, Escape closes.")
		self.del.armed = nil
		self.del.label:SetText("Delete")
		self.del:SetShown(e ~= nil)
		self:Show()
		self.box:SetFocus()
		self.box:HighlightText()
	end

	-- No chat line: the window closing (and the notes list updating) is the answer.
	function f:Save()
		ns.Set(self.n, self.r, self.box:GetText())
		self:Hide()
	end

	function f:Delete()
		ns.Delete(self.n, self.r)
		self:Hide()
	end

	f:SetScript("OnShow", function() end)
	f:SetScript("OnHide", function() box:ClearFocus() end)
	CloseOnEscape(f)
	return f
end

function ns.OpenEditor(name, realm)
	editor = editor or Build()
	editor:Open(name, realm)
	return editor
end
