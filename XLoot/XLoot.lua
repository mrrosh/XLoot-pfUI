-- Thanks to #wowace for help, Arantxa for ideas and support, the PocketHelper/Squeenix/FruityLoots/oSkin addons for various code snippets and trial and error. 
-- May your brain not spontaneously explode from the reading of this disorganized mod.
-- Positioning code re-write first implimented and then inspired by Dead_LAN! Thanks
-- localization (and koKR locals) by fenlis. Thanks =)
-- Dreaded Esc bug (hopefully) fixed by ckknight! Thanks so much ^_~
-- Todo: Add "Link all to party/raid" button. Split loot frame display into modules, add Slim layout, add Block layout. Add indicator icons to the items. Dice for items that will be rolled on. Lock or something else for BoP items.
local L = AceLibrary("AceLocale-2.0"):new("XLoot")

XLoot = AceLibrary("AceAddon-2.0"):new("AceEvent-2.0", "AceDB-2.0", "AceConsole-2.0", "AceHook-2.0", "AceModuleCore-2.0");-- Shhhhh

XLoot.revision  = tonumber((string.gsub("$Revision: 12996 $", "^%$Revision: (%d+) %$$", "%1")))
--libs\AceModuleCore\AceModuleCore-2.0.lua
XLoot:SetModuleMixins("AceEvent-2.0", "AceDB-2.0", "AceHook-2.0")
XLoot.dewdrop = AceLibrary("Dewdrop-2.0")

local _G = getfenv(0) -- Lovely shortcut, if it works.

XLoot.compat = string.find(GetBuildInfo(), "^2%.")

function XLoot:OnInitialize()
	self:RegisterDB("XLootDB")
	self.dbDefaults = {
		scale = 1.0,
		cursor = true,
		debug = false,
		smartsnap = true,
		snapoffset = 0,
		altoptions = true,
		collapse = true,
		dragborder = true,
		lootexpand = true,
		swiftloot = false,
		qualityborder = false,
		qualityframe = false,
		texcolor = true,
		lootqualityborder = true,
		qualitytext = false,
		infotext = true,
		oskin = false,
		lock = false,
		pos = { x = (UIParent:GetWidth()/2), y = (UIParent:GetHeight()/2) },
		bgcolor = { 0, 0, 0, .7 },
		bordercolor = { .7, .7, .7, 1 },
		lootbgcolor = { 0, 0, 0, .9 },
		lootbordercolor = { .5, .5, .5, 1 }
	};
	self:RegisterDefaults("profile", self.dbDefaults)
	self:DoOptions()			
	--Initial session variables
	self.numButtons = 0 -- Buttons currently created
	self.buttons = {} -- Easy reference array by ID
	self.frames = {}
	self.visible = false
	self.closing = false
	self.setexpandedtext = false
	self.loothasbeenexpanded = false
	self.swiftlooting = false
	self.swifthooked = false
	self:SetupFrames()
	
	--Setup menu
	self.dewdrop:Register(XLootFrame,
		'children', function()
				self.dewdrop:FeedAceOptionsTable(self.opts)
			end,
		'cursorX', true,
		'cursorY', true
	)
	self.dewdrop:Register(UIParent,
		'children', function(level, value)
				self.dewdrop:FeedAceOptionsTable(self.opts)
			end,
		'cursorX', true,
		'cursorY', true,
		'dontHook', true
	)
end

--Hook builtin functions
function XLoot:OnEnable()
	self:Hook("CloseWindows")
	self:Hook("LootFrame_OnEvent")
	self:Hook("LootFrame_OnShow")
	self:Hook("LootFrame_OnHide")
	self:Hook("LootFrame_Update")
	if self.compat then
		self:Hook("LootButton_OnClick", "OnButtonClick")
		self:Hook("LootButton_OnModifiedClick", "OnModifiedButtonClick")
	else
		self:Hook("LootFrameItem_OnClick", "OnClick")
	end
	if self.db.profile.swiftloot then
		self:SwiftMouseEvents(true)
	end
	self:RegisterEvent("LOOT_OPENED", "OnOpen")
	self:RegisterEvent("LOOT_SLOT_CLEARED", "OnClear")
	self:RegisterEvent("LOOT_CLOSED", "OnClose")
end

function XLoot:OnDisable()
	self:UnregisterAllEvents()
end

function XLoot:Defaults()
	self:Print("Default values restored.")
	for k, v in pairs(self.dbDefaults) do
		self.db.profile[k] = v
	end
end

--local ItemInfo -- Is this code familiar? Hmm.... shhh
do
	if XLoot.compat then
		-- 2.0.0
		function XLoot:ItemInfo(num) -- itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, invTexture
			local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, invTexture = GetItemInfo(num)
			return itemName, itemLink, itemRarity, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, invTexture, itemLevel
		end
	else
		function XLoot:ItemInfo(num) -- itemName, itemString, itemQuality, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture
			return GetItemInfo(num)
		end
	end
end

---------- Shift-Looting detection. Fear the monster 'if' hives -----------

function XLoot:SwiftMouseEvents(state) 
	if state and not self:IsEventRegistered("UPDATE_MOUSEOVER_UNIT") then
		self:RegisterEvent("PLAYER_TARGET_CHANGED", "SwiftTargetChange")
		self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", "SwiftMouseover")
	elseif not state and self:IsEventRegistered("UPDATE_MOUSEOVER_UNIT") then
		self:UnregisterEvent("PLAYER_TARGET_CHANGED")
		self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
	end
end

function XLoot:SwiftErrmsg(message)
	if message == ERR_INV_FULL then 
		self:SwiftHooks(false)
		self.swiftlooting = false
		self:Update()
	end		
end

function XLoot:SwiftMouseover()
	if not self.swiftlooting then
		if UnitIsDead("target")  then 
			if UnitIsUnit("mouseover", "target") then
				if not UnitIsPlayer("target") then
					if CheckInteractDistance("target", 1) then
						if not self.swifthooked then 
							self:SwiftHooks(true)
						end
					end
				end
			end
		end
	end
end

function XLoot:SwiftHooks(state)
	if state then
		--self:Print("Hooking for swiftloot...")
		self:RegisterEvent("UI_ERROR_MESSAGE", "SwiftErrmsg")
		self:HookScript(WorldFrame, "OnMouseUp", "SwiftMouseUp")
		self.swifthooked = true
	else
		--self:Print("Releasing swiftloot hooks...")
		self:UnregisterEvent("UI_ERROR_MESSAGE")
		if self:IsHooked(WorldFrame, "OnMouseUp") then
			self:Unhook(WorldFrame, "OnMouseUp")
		end
		self.swifthooked = false
	end
end

function XLoot:SwiftTargetChange(lastevent)
	if self.swifthooked then
		if not UnitIsUnit("mouseover", "target") then
			self:SwiftHooks(false)
			self.swiftlooting = false
		end
	end
	if not lastevent then
		if UnitIsDead("target") then
			if not UnitIsPlayer("target") then
				if CheckInteractDistance("target", 1) then
					self:SwiftMouseUp()
				end
			end
		end
	end
end

function XLoot:SwiftMouseUp()
	if IsShiftKeyDown() then
		--self:Print("Swiftlooting...")
		if not self.swifthooked then
			self:RegisterEvent("UI_ERROR_MESSAGE", "SwiftErrmsg")
			self.swifthooked = true
		end
		self.swiftlooting = true
	else
		self.swiftlooting = false
	end
end


function  XLoot:CloseWindows(ignoreCenter) 
	local hookedresult = self.hooks["CloseWindows"].orig(ignoreCenter)
	if self.frame:IsShown() then 
		self:AutoClose(true)
		return true
	end
	return 	hookedresult
end

function XLoot:OnOpen()
--	if not self:AutoClose() then
--		self:OnClear()
--	end
end

function XLoot:OnClear()
	self.refreshing = true
	self:Clear();
	self:Update();
end

function XLoot:OnClose()
	self:Clear();
end

function XLoot:OnHide()
	if not self.refreshing then
		self:AutoClose(true)
	else 
		self.refreshing = false
	end
end

function XLoot:ClickCheck(button)
	if IsAltKeyDown() and button == "RightButton" and self.db.profile.altoptions and not IsShiftKeyDown() and not IsControlKeyDown() then
		self.dewdrop:Open(XLootFrame)
		return 1
	end
end

function XLoot:OnClick(button)
	if not self:ClickCheck(button) then
		self.hooks["LootFrameItem_OnClick"].orig(button)
	end
end

function XLoot:OnButtonClick(button)
	if not self:ClickCheck(button) then
		self.hooks["LootButton_OnClick"].orig(button)
	end
end

function XLoot:OnModifiedButtonClick(button)
	if not self:ClickCheck(button) then
		self.hooks["LootButton_OnModifiedClick"].orig(button)
	end
end

function XLoot:LootFrame_OnEvent(event)
	if event ~= "LOOT_SLOT_CLEARED" then
		self.hooks["LootFrame_OnEvent"].orig(event)
	end
	if event == "LOOT_OPENED" then
		HideUIPanel(LootFrame);
	end
end

-- Show our frame and hide the old one
function XLoot:LootFrame_OnShow()
	--self.hooks["LootFrame_OnShow"].orig()
	if self:AutoClose() == nil then
		if not self.visible and IsFishingLoot() then
			PlaySound("FISHING REEL IN")
		end
		self:Clear()
		self:Update()
	end
end

-- Block closing loot
function XLoot:LootFrame_OnHide()
end

-- Update our lootframe
function XLoot:LootFrame_Update()
	--XLoot.hooks["LootFrame_Update"].orig()
	if self:AutoClose() then
		self:Update()
	end
end

function XLoot:AutoClose(force) -- Thanks, FruityLoots.
	if (GetNumLootItems() == 0) or force then 
		self:Clear()
		HideUIPanel(LootFrame)
		CloseLoot()
		self:msg("AutoClosing ("..GetNumLootItems() ..")"..(force and " Forced!" or ""))
		return 1
	end
	self:msg("AutoClose check passed")
	return nil
end

-- Core
function XLoot:Update()
	if self.swiftlooting then 
		self:msg("Overrode update, swiftlooting")
		return
	end
	local db = self.db.profile
	local numLoot = GetNumLootItems()
	--Build frames if we need more
	if (numLoot > self.numButtons) then
		for i = (self.numButtons + 1), numLoot do
			self:msg("Adding needed frame["..(i).."], numButtons = "..XLoot.numButtons.." & numLoot = "..numLoot)
			self:AddLootFrame(i)
		end
	end
	-- LootLoop
	local curslot, button, frame, texture, item, quantity, quality, color, qualitytext, textobj, infoobj, qualityobj
	local curshift, qualityTower, framewidth  = 0, 0, 0
	for slot = 1, numLoot do
		texture, item, quantity, quality = GetLootSlotInfo(slot)
		if (texture) then
			curshift = curshift +1
			-- If we're shifting loot, use position slots instead of item slots
			if db.collapse then
				button = self.buttons[curshift]
				frame = self.frames[curshift]
				curslot = curshift
			else
				button = self.buttons[slot]
				frame = self.frames[slot]
				curslot = slot
			end
			-- Update slot ID's for WoW's sanity
			if not self.compat then
				button:SetSlot(slot)
			end
			button:SetID(slot)
			button.slot = slot
			self:msg("Attaching loot["..slot.."] ["..item.."] to slot ["..curslot.."], bSlot = "..button.slot);
			color = ITEM_QUALITY_COLORS[quality]
			qualityTower = max(qualityTower, quality)
			SetItemButtonTexture(button, texture)
			textobj = _G["XLootButton"..curslot.."Text"]
			infoobj = _G["XLootButton"..curslot.."Description"]
			qualityobj = _G["XLootButton"..curslot.."Quality"]
			infoobj:SetText("")
			qualityobj:SetText("")
			if LootSlotIsCoin(slot) then -- Fix and performance fix thanks to Dead_LAN
				item = string.gsub(item, "\n", " ", 1, true);
			end
			if db.lootexpand then
				textobj:SetWidth(700)
				infoobj:SetWidth(700)
			else
				textobj:SetWidth(155)
				infoobj:SetWidth(155)
			end
			textobj:SetVertexColor(color.r, color.g, color.b);
			textobj:SetText(item);
			
			if db.qualitytext and not LootSlotIsCoin(slot) then 
				qualityobj:SetText(_G["ITEM_QUALITY"..quality.."_DESC"])
				qualityobj:SetVertexColor(.8, .8, .8, 1); --1
				textobj:SetPoint("TOPLEFT", button, "TOPLEFT", 42, -12)
				infoobj:SetPoint("TOPLEFT", button, "TOPLEFT", 45, -22)
				textobj:SetHeight(10)
			elseif LootSlotIsCoin(slot) then
				textobj:SetPoint("TOPLEFT", button, "TOPLEFT", 42, 2)
				qualityobj:SetText("")
				textobj:SetHeight(XLootButton1:GetHeight()+1)
			else
				qualityobj:SetText("")
				if db.infotext then
					textobj:SetPoint("TOPLEFT", button, "TOPLEFT", 42, -8)
				else
					textobj:SetPoint("TOPLEFT", button, "TOPLEFT", 42, -12)
					infoobj:SetText("")
				end
				infoobj:SetPoint("TOPLEFT", button, "TOPLEFT", 45, -18)
				textobj:SetHeight(10)
			end
			if db.lootqualityborder then
				frame:SetBackdropBorderColor(color.r, color.g, color.b, 1)
				button:SetBackdropBorderColor(color.r, color.g, color.b, 1) -- Color on Loot Icon Border by Quality
			else
				frame:SetBackdropBorderColor(unpack(db.lootbordercolor))
			end
			if db.texcolor and LootSlotIsItem(slot) and quality > 1 then
				local r, g, b, hex = GetItemQualityColor(quality)
				button.border:SetVertexColor(r, g, b)
				button.border:Show() 
			else
				button.border:Hide()
			end
			if LootSlotIsItem(slot) and db.infotext then
				self:SetSlotInfo(slot, button)
			end
			if db.lootexpand then 
				framewidth = max(framewidth, textobj:GetStringWidth(), infoobj:GetStringWidth())
			end
			
			SetItemButtonCount(button, quantity)
			button.quality = quality
			button:Show()
			frame:Show()
		elseif not db.collapse then
			curshift = curshift + 1
			self.buttons[slot]:Hide()
			self:msg("Hiding slot "..slot..", curshift: "..curshift)
		end
	end
	
	if slot == curshift then --Collapse lower buttons
		curshift = curshift -1
		self:msg("Collapsing end slot "..slot..", curshift now "..curshift)
	end
	
	XLootFrame:SetScale(db.scale)
	local color = ITEM_QUALITY_COLORS[qualityTower]
	if db.qualityborder and not self.visible then 
		self:msg("Quality tower: "..qualityTower)
		self.frame:SetBackdropBorderColor(color.r, color.g, color.b, 1)
	else
		 self.frame:SetBackdropBorderColor(unpack(db.bordercolor))
	end
	if db.qualityframe and not self.visible then
		self.frame:SetBackdropColor(color.r, color.g, color.b, db.bgcolor[4])
	else
		self.frame:SetBackdropColor(unpack(db.bgcolor))
	end
		
	XLootFrame:SetHeight( 1 + (curshift*XLootButtonFrame1:GetHeight() )) 
	
	if db.lootexpand then
		self.loothasbeenexpanded = true
		local fwidth, bwidth = (self.buttons[1]:GetWidth() + framewidth + 21), -(framewidth + 16)
		self:UpdateWidths(curshift, fwidth, bwidth, fwidth + 1) 
	elseif self.loothasbeenexpanded then
		self.loothasbeenexpanded = false
		self:UpdateWidths(curshift, 200, -163, 222)
	end
	
	
	if (db.collapse and db.cursor) or (not self.visible and db.cursor) then -- FruityLoot
		self:PositionAtCursor()
	end
	
	self.frame:Show()
	self.closebutton:Show()
	self:msg("Displaying at position: "..XLootFrame:GetLeft().." "..XLootFrame:GetTop());
	self.visible = true
	
	--Hopefully avoid non-looting/empty bar
	if self:AutoClose() then
		self:msg("Possible hanger frame. Closing.. "..numLoot..", "..curshift)
	end
end

function XLoot:Layout_Default_Update(items)
end

 function XLoot:UpdateWidths(framenum, fwidth, bwidth, ofwidth)
		for i = 1, framenum do
			self.frames[i]:SetWidth(fwidth)
			self.buttons[i]:SetHitRectInsets(0, bwidth, 0, -1)
		end
		self.frame:SetWidth(ofwidth)
end 

function XLoot:SetSlotInfo(slot, button) -- Yay wowwiki demo
	local link =  GetLootSlotLink(slot)
	--local justName = string.gsub(link,"^.-%[(.*)%].*", "%1")
	local itemName, itemLink, itemRarity, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc = self:ItemInfo(self:LinkToID(link))
	if itemType == "Weapon" then
		itemEquipLoc = "Weapon"
	else
		--local ielfunc = assert(loadstring("return "..itemEquipLoc));
		itemEquipLoc = _G[itemEquipLoc]--ielfunc();
	end
	if itemSubType == "Junk" then 
		itemSubType = (itemRarity > 0) and "Quest Item" or itemSubType
	end
	_G[button:GetName().."Description"]:SetText((itemEquipLoc and itemEquipLoc..", " or "") .. ((itemSubType == itemSubType) and itemSubType or itemSubType.." "..itemType))
--((itemMinLevel > 0) and "Lv"..itemMinLevel.." " or "") .. 
end

function XLoot:PositionAtCursor() --Fruityloots mixup, only called if cursor snapping is enabled
	x, y = GetCursorPosition()
	local s = XLootFrame:GetEffectiveScale()
	x = (x / s) - 20 
	y = (y / s) + 20 
	local screenWidth = GetScreenWidth()
	if (UIParent:GetWidth() > screenWidth) then screenWidth = UIParent:GetWidth() end
	local screenHeight = GetScreenHeight()
	local windowWidth = XLootFrame:GetWidth()
	local windowHeight = XLootFrame:GetHeight()
	if (x + windowWidth) > screenWidth then x = screenWidth - windowWidth end
	if y > screenHeight then y = screenHeight end
	if x < 0 then x = 0 end
	if (y - windowHeight) < 0 then y = windowHeight end
	LootFrame:ClearAllPoints()
	if (self.db.profile.smartsnap and self.visible) then
		x = XLootFrame:GetLeft();
	else 
		x = x + self.db.profile.snapoffset
	end
	XLootFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y);
end

-- Add a single lootframe
function XLoot:AddLootFrame(id)
	local frame = CreateFrame("Frame", "XLootButtonFrame"..id, self.frame)
	local button = CreateFrame(LootButton1:GetObjectType(), "XLootButton"..id, frame, "LootButtonTemplate")
	-- Equivalent of XLootButtonTemplate
	local buttontext = _G["XLootButton"..id.."Text"]
	local buttondesc = button:CreateFontString("XLootButton"..id.."Description", "ARTWORK", "GameFontNormalSmall")
	local buttonquality = button:CreateFontString("XLootButton"..id.."Quality", "GameFontNormalSmall")
	local font = {buttontext:GetFont()}
	font[2] = 10
	buttontext:SetDrawLayer("OVERLAY")
	buttondesc:SetDrawLayer("OVERLAY")
	buttonquality:SetDrawLayer("OVERLAY")
	buttondesc:SetFont(unpack(font))
	buttonquality:SetFont(unpack(font))
	buttondesc:SetJustifyH("LEFT")
	buttonquality:SetJustifyH("LEFT")
	buttondesc:SetHeight(10)	
	buttonquality:SetWidth(155)
	buttonquality:SetHeight(10)
	buttontext:SetHeight(10)
	button:IsToplevel(1)
	buttonquality:SetPoint("TOPLEFT", button, "TOPLEFT", 45, -3)
	button:SetBackdrop({bgFile = "Interface\\AddOns\\XLoot\\media\\bg", tile = true, tileSize = 8,
								edgeFile = "Interface\\AddOns\\XLoot\\media\\border_col", edgeSize = 8,
								 insets = {left = 0, right = 0, top = 0, bottom = 0 }})
	button:SetHitRectInsets(0, -165, 0, -1)
	-- End template
	local border = self:QualityBorder(button)
	frame:SetWidth(200)
	frame:SetHeight(button:GetHeight()+1)
	button:ClearAllPoints()
	frame:ClearAllPoints()
	if (id == 1) then 
		frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, 0) 
	else
		frame:SetPoint("TOPLEFT", self.frames[id-1], "BOTTOMLEFT")
	end
	button:SetPoint("LEFT", frame, "LEFT")
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function() self:DragStart() end)
	button:SetScript("OnDragStop", function() self:DragStop() end)
	button:SetScript("OnEnter", 	function() local slot = this:GetID(); if ( LootSlotIsItem(slot) ) then	 GameTooltip:SetOwner(this, "ANCHOR_RIGHT"); GameTooltip:SetLootItem(slot); CursorUpdate(); end end )
	self.buttons[id] = button
	self.buttons[id].border = border
	self.frames[id] = frame
	self:msg("Creation: self.buttons["..id.."] = ".. button:GetName())
	self.frame:SetHeight(self.frame:GetHeight() + frame:GetHeight())

	--Skin
	if (IsAddOnLoaded("oSkin") and self.db.profile.oskin) then
		oSkin:applySkin(button)
		oSkin:applySkin(frame)
 	else
 		self:BackdropFrame(frame, self.db.profile.lootbgcolor, self.db.profile.lootbordercolor)
		self:oSkinTooltipModded(frame)
 	end
	button:DisableDrawLayer("ARTWORK")
	button:Hide()
	frame:Hide()
	self.numButtons = self.numButtons +1
end

function XLoot:DragStart() 
	if not self.db.profile.lock then 
		XLootFrame:StartMoving() 
	end
end

function XLoot:DragStop()
	if not self.db.profile.lock then 
		XLootFrame:StopMovingOrSizing()
		self.db.profile.pos.x = XLootFrame:GetLeft()
		self.db.profile.pos.y = XLootFrame:GetTop()
		XLoot:msg("Setting position: "..self.db.profile.pos.x.." "..self.db.profile.pos.y) 
	end
end 

-- Setup lootframes & close button
function XLoot:SetupFrames()
	-- Alright you XML nazis. Main frame
	self.frame = CreateFrame("Frame", "XLootFrame", UIParent)
	self.frame:SetFrameStrata("DIALOG")
	self.frame:SetFrameLevel(5)
	self.frame:SetWidth(222)
	self.frame:SetHeight(20)
	self.frame:SetMovable(1)
	if self.db.profile.dragborder then
		self.frame:EnableMouse(1)
	end
	self.frame:RegisterForDrag("LeftButton")
	self.frame:SetScript("OnDragStart", function() XLoot:DragStart() end)
	self.frame:SetScript("OnDragStop", function() XLoot:DragStop() end)
	self.frame:SetScript("OnHide", function() XLoot:OnHide() end)
	self:BackdropFrame(self.frame, self.db.profile.bgcolor, self.db.profile.bordercolor)
   	self.frame:ClearAllPoints()
   	if not self.db.profile.cursor then
		self.frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", self.db.profile.pos.x, self.db.profile.pos.y)
	end

	--Skin
	if (IsAddOnLoaded("oSkin") and self.db.profile.oskin) then
		oSkin:applySkin(XLootFrame, {1})
	else
		self:oSkinTooltipModded(XLootFrame)
	end
   
    self.frame:SetScale(self.db.profile.scale)
    
   	-- Close button,  for help see /pfUI/modules/bags.lua , line 400+
	self.closebutton = CreateFrame("Button", "XLootCloseButton", XLootFrame)
	self.closebutton:SetScript("OnClick", function() XLoot:AutoClose(true); end)
	self.closebutton:SetFrameLevel(8)
	self.closebutton:ClearAllPoints()
	self.closebutton:SetPoint("TOPRIGHT", XLootFrame, "TOPRIGHT") 
	self.closebutton:SetBackdrop({bgFile = "Interface\\AddOns\\XLoot\\media\\bg", tile = true, tileSize = 8,
								edgeFile = "Interface\\AddOns\\XLoot\\media\\border", edgeSize = 8,
								 insets = {left = 0, right = 0, top = 0, bottom = 0 }})
	self.closebutton:SetWidth(12) 
	self.closebutton:SetHeight(12) 
	self.closebutton:SetHitRectInsets(0, 0, 0, 0) 
	self.closebutton:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
	self.closebutton.texture = self.closebutton:CreateTexture("pfBagClose") 
    self.closebutton.texture:SetTexture("Interface\\AddOns\\XLoot\\media\\close") 
	self.closebutton.texture:SetWidth(8) 
	self.closebutton.texture:SetHeight(8) 
	self.closebutton.texture:ClearAllPoints()
	self.closebutton.texture:SetPoint("TOPRIGHT", XLootFrame, "TOPRIGHT", -2, -2) 
	self.closebutton:SetHitRectInsets(0, 0, 0, 0) 
	self.closebutton.texture:SetVertexColor(1,.25,.25,1) 
	self.closebutton:Hide()
	self:AddLootFrame(1)
	self.frame:Hide()
end	

function XLoot:msg( text )
	if self.db.profile.debug then 
		DEFAULT_CHAT_FRAME:AddMessage("|cff7fff7fXLoot|r: "..text);
	end
end

function XLoot:Clear()
	for slot, button in pairs(self.buttons) do
		--SetItemButtonTexture(button, "")
		SetItemButtonCount(button, 0)
		--getglobal("XLootButton"..slot.."Text"):SetVertexColor(0, 0, 0)
		--getglobal("XLootButton"..slot.."Text"):SetText("")
		--getglobal("XLootButton"..slot.."Description"):SetText("")
		--getglobal("XLootButton"..slot.."Quality"):SetText("")
		button:Hide()
		self.frames[slot]:Hide()
	end
	if GetNumLootItems() < 1 then
		self.visible = false
	end
	XLootFrame:Hide()
end

function XLoot:LinkToName(link)
	return string.gsub(link,"^.-%[(.*)%].*", "%1")
end

function XLoot:LinkToID(link)
	return string.gsub(link,".-\124H([^\124]*)\124h.*", "%1")
end

function XLoot:QualityBorder(button)
	local border = button:CreateTexture(button:GetName() .. "QualBorder", "OVERLAY")
	--border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border") 
	border:SetBlendMode("ADD")
	border:SetAlpha(0.9)
	border:SetHeight(button:GetHeight()*1.8)
	border:SetWidth(button:GetWidth()*1.8)
	border:SetPoint("CENTER", button, "CENTER", 0, 1)
	border:Hide()
	return border
end

function XLoot:BackdropFrame(frame, bgcolor, bordercolor)
	frame:SetBackdrop({bgFile = "Interface\\AddOns\\XLoot\\media\\bg", 
                                            edgeFile = "Interface\\AddOns\\XLoot\\media\\border_col", 
                                            tile = true, tileSize = 8, edgeSize = 8, 
                                            insets = { left = 0, right = 0, top = 0, bottom = 0 }})
 	frame:SetBackdropColor(unpack(bgcolor))
   frame:SetBackdropBorderColor(unpack(bordercolor))
end

-- Substitute oSkin function, full credit to oSkin devs :)
function XLoot:oSkinTooltipModded(frame)
	if not frame.tfade then frame.tfade = frame:CreateTexture(nil, "BORDER") end
	frame.tfade:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")

	frame.tfade:SetPoint("TOPLEFT", frame, "TOPLEFT",1,-1)
	frame.tfade:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",-1,1)

	frame.tfade:SetBlendMode("ADD")
	frame.tfade:SetGradientAlpha("VERTICAL", .1, .1, .1, 0, .2, .2, .2, 0.3)

	frame.tfade:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
	frame.tfade:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -6, -30)
end
