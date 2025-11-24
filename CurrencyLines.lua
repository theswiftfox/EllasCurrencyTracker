-- EllasCurrencyTracker.lua
-- Simple currency tracker addon with settings window to pick currencies
-- Author: theswiftfox

local ADDON_NAME = "EllasCurrencyTracker"
local DB_DEFAULTS = {
    tracked = {},  -- array of currencyIDs { 1220, 1273, ... }
    grow = "DOWN", -- "UP" or "DOWN"
    anchor = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0, width = 240, scale = 1 },
    lineHeight = 20,
    font = (GameFontNormal and GameFontNormal:GetFont()) or "Fonts\\FRIZQT__.TTF",
    fontColor = { 1, 1, 1 },  -- r,g,b for currency line text
    titleColor = { 1, 1, 1 }, -- r,g,b for main window title
}

-- Saved variables table (populated by WoW with EllasCurrencyTrackerDB)
EllasCurrencyTrackerDB = EllasCurrencyTrackerDB or {
    profiles = {
        -- "Realm – Character" = {
        --     tracked = {1220, 1273},
        --     grow = "DOWN",
        --     anchor = {...},
        --     lineHeight = 20,
        --     font = ...,
        --     fontColor = {...},
        --     titleColor = {...}
        -- }
    },
}
EllasCurrencyCharacterProfile = EllasCurrencyCharacterProfile or {
    activeProfile = "default",
}

-- Create a shallow copy of a table
local function copyTable(t)
    local nt = {}
    for k, v in pairs(t) do nt[k] = v end
    return nt
end

local function defaultProfile()
    return {
        tracked = {},
        grow = DB_DEFAULTS.grow,
        anchor = copyTable(DB_DEFAULTS.anchor),
        lineHeight = DB_DEFAULTS.lineHeight,
        font = DB_DEFAULTS.font,
        fontColor = copyTable(DB_DEFAULTS.fontColor),
        titleColor = copyTable(DB_DEFAULTS.titleColor),
    }
end

local function InitDB()
    if EllasCurrencyTrackerDB.profiles == nil then
        EllasCurrencyTrackerDB.profiles = {}
    end
    if EllasCurrencyTrackerDB.profiles["default"] == nil then
        EllasCurrencyTrackerDB.profiles["default"] = defaultProfile()
    end

    if EllasCurrencyCharacterProfile == nil then
        EllasCurrencyCharacterProfile = {}
    end
    if EllasCurrencyCharacterProfile.activeProfile == nil then
        EllasCurrencyCharacterProfile.activeProfile = "default"
    end
end

-- Unique key for the current character
local function GetCharacterKey()
    return (GetRealmName() or "") .. " – " .. (UnitName("player") or "unknown")
end

-- Helper to fetch the profile table
local function CurrentProfile()
    return EllasCurrencyTrackerDB.profiles[EllasCurrencyCharacterProfile.activeProfile]
end

-- Load / create the profile for the current character
local function CreateProfile(name, copy)
    copy = copy or false
    if EllasCurrencyTrackerDB.profiles[name] == nil then
        if copy then
            local from = CurrentProfile()
            EllasCurrencyTrackerDB.profiles[name] = {
                tracked = copyTable(from.tracked),
                grow = from.grow,
                anchor = copyTable(from.anchor),
                lineHeight = from.lineHeight,
                font = from.font,
                fontColor = copyTable(from.fontColor),
                titleColor = copyTable(from.titleColor)
            }
        else
            EllasCurrencyTrackerDB.profiles[name] = defaultProfile()
        end
    end
    EllasCurrencyCharacterProfile.activeProfile = name
end

local framePool = {} -- pool of line frames
local mainFrame

-- Local cache of discovered currencies (reset each session)
local discoveredCurrencies = {} -- array of { id = id, name = name, amount = amount, icon = icon }

-- Utility: parse currency ID from currency link or number string
local function ParseCurrencyID(str)
    if not str then return nil end
    -- If input is a number string
    local id = tonumber(str)
    if id then return id end
    -- If it's a currency link like "|Hcurrency:1220:0|h[Some]|h"
    local parsed = str:match("currency:(%d+)")
    if parsed then return tonumber(parsed) end
    -- Allow links in chat form: "currency:1220"
    parsed = str:match("(%d+)")
    if parsed and #str < 7 then return tonumber(parsed) end
    return nil
end

-- API wrapper to get currency details by ID across WoW versions
local function GetCurrencyInfoByID(id)
    if not id then return nil end
    -- Try modern API
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
        if ok and info then
            local name = info.name
            local amount = info.quantity
            local icon = info.iconFileID
            local max = info.maxQuantity
            return { id = id, name = name or ("Currency " .. tostring(id)), amount = amount or 0, icon = icon, max = max }
        end
    end


    -- Fallback to older C_AccountStore.GetCurrencyInfo
    local ok, info = pcall(C_AccountStore.GetCurrencyInfo, id)
    if ok and info then
        return { id = id, name = info.name, amount = info.amount or 0, icon = info.icon }
    end
    return { id = id, name = ("Currency " .. tostring(id)), amount = 0, icon = nil }
end

-- Create or reuse a line frame from pool
local function AcquireLine(index)
    local f = framePool[index]
    if f and f:IsShown() then return f end

    if not f then
        local profile = CurrentProfile()
        f = CreateFrame("Frame", ADDON_NAME .. "Line" .. index, mainFrame)
        f:SetSize(profile.anchor.width or DB_DEFAULTS.anchor.width, profile.lineHeight)
        -- Icon
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(profile.lineHeight - 4, profile.lineHeight - 4)
        f.icon:SetPoint("RIGHT", -2, 0)
        -- Amount
        f.amount = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.amount:SetPoint("RIGHT", f.icon, "LEFT", -6, 0)
        f.amount:SetJustifyH("RIGHT")
        -- Name
        f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.name:SetPoint("LEFT", 2, 0)
        f.name:SetJustifyH("LEFT")
        f.id = nil
        framePool[index] = f
    end
    f:Show()
    return f
end

local function ReleaseUnusedLines(startIndex)
    for i = startIndex, #framePool do
        if framePool[i] then framePool[i]:Hide() end
    end
end

-- Rebuild the displayed lines from the tracked list
local function RebuildLines()
    if not mainFrame then return end
    local profile = CurrentProfile()
    local tracked = profile.tracked
    local N = #tracked
    local spacing = 0
    local lineHeight = profile.lineHeight or DB_DEFAULTS.lineHeight
    mainFrame:SetWidth(profile.anchor.width or DB_DEFAULTS.anchor.width)
    -- Arrange lines
    for i = 1, N do
        local id = tracked[i]
        local info = GetCurrencyInfoByID(id)
        if info then
            local line = AcquireLine(i)
            line:SetSize(mainFrame:GetWidth(), lineHeight)
            if info.icon then
                line.icon:SetTexture(info.icon)
                line.icon:Show()
            else
                line.icon:Hide()
            end
            line.amount:SetFont(profile.font, 12)
            line.amount:SetTextColor(unpack(profile.fontColor or DB_DEFAULTS.fontColor))
            line.amount:SetText(tostring(info.amount))

            line.name:SetFont(profile.font, 12)
            line.name:SetTextColor(unpack(profile.fontColor or DB_DEFAULTS.fontColor))
            line.name:SetText(("%s"):format(info.name or ("Currency " .. id)))
            line.id = id

            line:ClearAllPoints()
            if profile.grow == "UP" then
                if i == 1 then
                    line:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 4, 16)
                else
                    line:SetPoint("BOTTOMLEFT", framePool[i - 1], "TOPLEFT", 0, spacing + 2)
                end
            else -- DOWN
                if i == 1 then
                    line:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 4, -20)
                else
                    line:SetPoint("TOPLEFT", framePool[i - 1], "BOTTOMLEFT", 0, -(spacing + 2))
                end
            end
        end
    end

    ReleaseUnusedLines(N + 1)
    -- Resize mainFrame height based on lines
    local height = 8 + (N * (lineHeight + 2))
    mainFrame:SetHeight(height)
end

-- Update all lines' amounts and icons (call when currency changes)
local function UpdateAll()
    local profile = CurrentProfile()
    local tracked = profile.tracked
    for i = 1, #tracked do
        local id = tracked[i]
        local info = GetCurrencyInfoByID(id)
        local line = framePool[i]
        if line and info then
            if info.icon then
                line.icon:SetTexture(info.icon)
                line.icon:Show()
            else
                line.icon:Hide()
            end
            line.amount:SetTextColor(unpack(profile.fontColor or DB_DEFAULTS.fontColor))
            line.amount:SetText(tostring(info.amount))

            line.name:SetTextColor(unpack(profile.fontColor or DB_DEFAULTS.fontColor))
            line.name:SetText(("%s"):format(info.name or ("Currency " .. id)))
        end
    end
    -- also refresh discovered cache amounts (for settings window)
    if discoveredCurrencies then
        for _, c in ipairs(discoveredCurrencies) do
            local info = GetCurrencyInfoByID(c.id)
            if info then
                c.amount = info.amount
                c.icon = info.icon
                c.name = info.name
            end
        end
    end
end

-- Add a currency to track
local function AddCurrency(id)
    local profile = CurrentProfile()
    if not id then return false, "invalid id" end
    if profile.tracked and #profile.tracked > 18 then
        return false, "Limit of 18 tracked currencies reached"
    end
    for _, v in ipairs(profile.tracked) do
        if v == id then return false, "already tracked" end
    end
    tinsert(profile.tracked, id)
    RebuildLines()
    return true
end

-- Remove currency
local function RemoveCurrency(id)
    local profile = CurrentProfile()
    if not id then return false, "invalid id" end
    for i, v in ipairs(profile.tracked) do
        if v == id then
            tremove(profile.tracked, i)
            RebuildLines()
            return true
        end
    end
    return false, "not found"
end

local function updateTitleColor()
    local profile = CurrentProfile()
    mainFrame.title:SetTextColor(unpack(profile.titleColor or DB_DEFAULTS.titleColor))
end

local function UpdateMainFrame()
    if not mainFrame then return end
    local profile = CurrentProfile()
    mainFrame:SetSize(profile.anchor.width, 100)
    mainFrame:SetPoint(profile.anchor.point, UIParent,
        profile.anchor.relativePoint, profile.anchor.x,
        profile.anchor.y)
    mainFrame:SetScale(profile.anchor.scale or 1)

    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        profile.anchor.point = point
        profile.anchor.relativePoint = relativePoint
        profile.anchor.x = x
        profile.anchor.y = y
        profile.anchor.width = mainFrame:GetWidth()
        profile.anchor.scale = mainFrame:GetScale()
    end)

    -- title
    mainFrame.title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    mainFrame.title:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 6, 0)
    mainFrame.title:SetText("Ella's Currency Tracker")
    updateTitleColor()
    -- set initial visibility of lines
    RebuildLines()
end


-- Toggle movable anchor
local function CreateMainFrame()
    if mainFrame then return end
    mainFrame = CreateFrame("Frame", ADDON_NAME .. "MainFrame", UIParent)

    mainFrame:SetMovable(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:EnableMouse(false)

    mainFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)

    UpdateMainFrame()
end

-- -------- Profiles Window ---------------------------------------

-- Profile manager window (singleton)
local profileFrame = nil

-- Refresh the dropdown list whenever profiles change
local function RefreshProfileDropdown(dropdown)
    if not dropdown then return end
    dropdown:SetSize(160, 30)
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        for name, _ in pairs(EllasCurrencyTrackerDB.profiles) do
            info.text = name
            info.value = name
            info.checked = name == EllasCurrencyCharacterProfile.activeProfile
            info.func = function(v) -- called when a name is clicked
                EllasCurrencyCharacterProfile.activeProfile = v.value
                self.selectedName = EllasCurrencyCharacterProfile.activeProfile
                self.selectedValue = EllasCurrencyCharacterProfile.activeProfile
                UIDropDownMenu_SetSelectedValue(self, EllasCurrencyCharacterProfile.activeProfile)
                UpdateMainFrame()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    dropdown.selectedName = EllasCurrencyCharacterProfile.activeProfile
    dropdown.selectedValue = EllasCurrencyCharacterProfile.activeProfile
    UIDropDownMenu_SetSelectedValue(dropdown, EllasCurrencyCharacterProfile.activeProfile)
    -- UIDropDownMenu_JustifyText(dropdown, "CENTER")
end

local function ShowProfileManager()
    if profileFrame and profileFrame:IsShown() then
        profileFrame:Raise()
        return
    end

    if not profileFrame then
        profileFrame = CreateFrame("Frame", ADDON_NAME .. "ProfileMgr", UIParent,
            BackdropTemplateMixin and "BackdropTemplate")
        profileFrame:SetSize(350, 250)
        profileFrame:SetPoint("CENTER")
        profileFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
        profileFrame:SetMovable(true)
        profileFrame:EnableMouse(true)
        profileFrame:RegisterForDrag("LeftButton")
        profileFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        profileFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

        -- Title
        profileFrame.title = profileFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        profileFrame.title:SetPoint("TOPLEFT", profileFrame, "TOPLEFT", 12, -10)
        profileFrame.title:SetText("Profile Manager")

        -- Dropdown: choose profile
        profileFrame.dropdown = CreateFrame("Button", nil, profileFrame, "UIDropDownMenuTemplate")
        profileFrame.dropdown:SetPoint("TOPLEFT", profileFrame, "TOPLEFT", 0, -40)
        RefreshProfileDropdown(profileFrame.dropdown)

        -- Label for new profile name
        profileFrame.newNameLabel = profileFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        profileFrame.newNameLabel:SetPoint("TOPLEFT", profileFrame, "TOPLEFT", 20, -80)
        profileFrame.newNameLabel:SetText("New Profile:")

        -- Editbox: new profile name
        profileFrame.newName = CreateFrame("EditBox", nil, profileFrame, "InputBoxTemplate")
        profileFrame.newName:SetSize(200, 20)
        profileFrame.newName:SetPoint("TOPLEFT", profileFrame.newNameLabel, "BOTTOMLEFT", 0, -5)
        profileFrame.newName:SetAutoFocus(false)

        -- Buttons
        local buttonSize = 80
        local buttonPad = 6

        local addBtn = CreateFrame("Button", nil, profileFrame, "UIPanelButtonTemplate")
        addBtn:SetSize(buttonSize, 22)
        addBtn:SetPoint("TOPLEFT", profileFrame.newName, "TOPRIGHT", buttonPad)
        addBtn:SetText("Add")
        addBtn:SetScript("OnClick", function()
            local name = profileFrame.newName:GetText()
            if name == "" then
                print("EllasCurrencyTracker: Using character name template")
                name = GetCharacterKey()
            end
            if EllasCurrencyTrackerDB.profiles[name] then
                print("EllasCurrencyTracker: Profile '" .. name .. "' already exists.")
                return
            end
            CreateProfile(name, nil)
            RefreshProfileDropdown(profileFrame.dropdown)
            UpdateMainFrame()
        end)

        local copyBtn = CreateFrame("Button", nil, profileFrame, "UIPanelButtonTemplate")
        copyBtn:SetSize(buttonSize, 22)
        copyBtn:SetPoint("TOPLEFT", profileFrame.dropdown, "TOPRIGHT", buttonPad, 0)
        copyBtn:SetText("Copy")
        copyBtn:SetScript("OnClick", function()
            local name = profileFrame.newName:GetText()
            if name == "" then
                print("EllasCurrencyTracker: Using character name template")
                name = GetCharacterKey()
            end
            if EllasCurrencyTrackerDB.profiles[name] then
                print("EllasCurrencyTracker: Profile '" .. name .. "' already exists.")
                return
            end
            CreateProfile(name, true)
            RefreshProfileDropdown(profileFrame.dropdown)
            UpdateMainFrame()
        end)

        local delBtn = CreateFrame("Button", nil, profileFrame, "UIPanelButtonTemplate")
        delBtn:SetSize(buttonSize, 22)
        delBtn:SetPoint("TOPLEFT", copyBtn, "TOPRIGHT", buttonPad, 0)
        delBtn:SetText("Delete")
        delBtn:SetScript("OnClick", function()
            local name = EllasCurrencyCharacterProfile.activeProfile
            if name == "default" then
                print("EllasCurrencyTracker: Cannot delete default profile.")
            end
            EllasCurrencyTrackerDB.profiles[name] = nil
            EllasCurrencyCharacterProfile.activeProfile = "default"
            RefreshProfileDropdown(profileFrame.dropdown)
            UpdateMainFrame()
        end)

        -- Close button
        local close = CreateFrame("Button", nil, profileFrame, "UIPanelButtonTemplate")
        close:SetSize(70, 22)
        close:SetPoint("BOTTOMRIGHT", profileFrame, "BOTTOMRIGHT", -10, 10)
        close:SetText("Close")
        close:SetScript("OnClick", function() profileFrame:Hide() end)
    end

    profileFrame:Show()
    profileFrame:Raise()
end

-- -------- Settings Window (currency picker with filter) --------

-- Updated to fully expand headers before collecting the list and to retry
-- until no header remains collapsed.

local function DiscoverCurrencies()
    local list = {}

    if C_CurrencyInfo
        and C_CurrencyInfo.GetCurrencyListSize
        and C_CurrencyInfo.GetCurrencyListInfo then
        -- Get the current set of expanded headers
        local openedHeaders = {}
        for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
            if ok and info and info.isHeader and info.isHeaderExpanded then
                tinsert(openedHeaders, info.name)
            end
        end

        -- Helper that expands every header that is still collapsed.
        -- Returns true if we expanded at least one header.
        local function ExpandAllHeaders()
            local size = C_CurrencyInfo.GetCurrencyListSize()
            local didExpand = false
            for i = 1, size do
                local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
                if ok and info and info.isHeader and not info.isHeaderExpanded then
                    local ok2, _ = pcall(C_CurrencyInfo.ExpandCurrencyList, i, true)
                    if ok2 then
                        didExpand = true
                    end
                end
            end
            return didExpand
        end

        -- Re‑iterate until all headers are expanded.
        repeat
            local changed = ExpandAllHeaders()
        until not changed

        -- After everything is expanded, collect all non‑header entries.
        local size = C_CurrencyInfo.GetCurrencyListSize()
        for i = 1, size do
            local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
            if ok and info and not info.isHeader then
                local id = info.currencyID
                list[id] = {
                    id = id,
                    name = info.name,
                    amount = info.quantity,
                    icon = info.iconFileID,
                }
            end
        end

        -- Helper to check if an ID exists in the table of opened headers
        local function CurrencyInOpenedHeaders(check_id)
            for _, id in pairs(openedHeaders) do
                if check_id == id then
                    return true
                end
            end
            return false
        end

        -- Helper to Restore the originally opened headers.
        local function RestoreOriginalOpenedHeaders()
            local size = C_CurrencyInfo.GetCurrencyListSize()
            for i = 1, size do
                local ok, info = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
                if ok and info and info.isHeader and info.isHeaderExpanded then
                    if not CurrencyInOpenedHeaders(info.name) then
                        local _ = pcall(C_CurrencyInfo.ExpandCurrencyList, i, false)
                        return true
                    end
                end
            end
            return false
        end

        -- Iterate until the original headers are restored
        repeat
            local changed2 = RestoreOriginalOpenedHeaders()
        until not changed2
    end

    local profile = CurrentProfile()
    for _, id in ipairs(profile.tracked) do
        if not list[id] then
            local info = GetCurrencyInfoByID(id)
            if info then
                list[id] = {
                    id = id,
                    name = info.name,
                    amount = info.amount,
                    icon = info.icon,
                }
            end
        end
    end

    local arr = {}
    for id, info in pairs(list) do
        tinsert(arr,
            {
                id = id,
                name = tostring(info.name or ("Currency " .. id)),
                amount = info.amount or 0,
                icon = info.icon
            })
    end

    discoveredCurrencies = arr
    return arr
end

-- Settings window frame (singleton)
local configFrame = nil
-- Drag state for reordering tracked list
local dragState = { active = false, from = nil, target = nil }

local function IsTracked(id)
    local profile = CurrentProfile()
    for _, v in ipairs(profile.tracked) do if v == id then return true end end
    return false
end

local function ToggleTracked(id)
    if IsTracked(id) then
        RemoveCurrency(id)
        if configFrame and configFrame.UpdateTrackedList then configFrame:UpdateTrackedList() end
        return false
    else
        AddCurrency(id)
        if configFrame and configFrame.UpdateTrackedList then configFrame:UpdateTrackedList() end
        return true
    end
end

-- Settings window: simple list UI
local function CreateConfigWindow()
    if configFrame and configFrame:IsShown() then return configFrame end
    local profile = CurrentProfile()
    if not configFrame then
        configFrame = CreateFrame("Frame", ADDON_NAME .. "Config", UIParent, BackdropTemplateMixin and "BackdropTemplate")
        configFrame:SetSize(560, 450)
        configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        configFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile =
            "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 6, right = 6, top = 6, bottom = 6 }
        })
        configFrame:EnableMouse(true)
        configFrame:SetMovable(true)
        configFrame:RegisterForDrag("LeftButton")

        configFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
        configFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
        end)

        configFrame.title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        configFrame.title:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 12, -10)
        configFrame.title:SetText("EllasCurrencyTracker — Settings")

        local close = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
        close:SetSize(70, 22)
        close:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -10, -10)
        close:SetText("Close")
        close:SetScript("OnClick", function() configFrame:Hide() end)

        -- Color pickers: currency font color and main title color
        local fontLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fontLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 12, -40)
        fontLabel:SetText("Currency Font Color:")

        local fontSwatch = CreateFrame("Button", nil, configFrame)
        fontSwatch:SetSize(20, 20)
        fontSwatch:SetPoint("LEFT", fontLabel, "RIGHT", 8, 0)
        fontSwatch.texture = fontSwatch:CreateTexture(nil, "BACKGROUND")
        fontSwatch.texture:SetAllPoints()
        local fc = profile.fontColor or DB_DEFAULTS.fontColor
        fontSwatch.texture:SetColorTexture(fc[1], fc[2], fc[3], 1)
        fontSwatch:SetScript("OnClick", function()
            local r, g, b = unpack(profile.fontColor or DB_DEFAULTS.fontColor)
            local function OnColorChanged()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                profile.fontColor = { newR, newG, newB }
                fontSwatch.texture:SetColorTexture(newR, newG, newB, 1)
                RebuildLines()
            end
            local function OnCancel()
                profile.fontColor = { r, g, b }
                fontSwatch.texture:SetColorTexture(r, g, b, 1)
                RebuildLines()
            end
            local options = {
                swatchFunc = OnColorChanged,
                opacityFunc = function() end,
                cancelFunc = OnCancel,
                hasOpacity = false,
                opacity = 1,
                r = r,
                g = g,
                b = b
            }
            ColorPickerFrame:SetupColorPickerAndShow(options)
        end)

        local titleLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        titleLabel:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 200, -40)
        titleLabel:SetText("Main Title Color:")

        local titleSwatch = CreateFrame("Button", nil, configFrame)
        titleSwatch:SetSize(20, 20)
        titleSwatch:SetPoint("LEFT", titleLabel, "RIGHT", 8, 0)
        titleSwatch.texture = titleSwatch:CreateTexture(nil, "BACKGROUND")
        titleSwatch.texture:SetAllPoints()
        local tc = profile.titleColor or DB_DEFAULTS.titleColor
        titleSwatch.texture:SetColorTexture(tc[1], tc[2], tc[3], 1)
        titleSwatch:SetScript("OnClick", function()
            local r, g, b = unpack(profile.titleColor or DB_DEFAULTS.titleColor)
            local function OnColorChanged()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                profile.titleColor = { newR, newG, newB }
                titleSwatch.texture:SetColorTexture(newR, newG, newB, 1)
                updateTitleColor()
            end
            local function OnCancel()
                profile.titleColor = { r, g, b }
                titleSwatch.texture:SetColorTexture(r, g, b, 1)
                updateTitleColor()
            end
            local options = {
                swatchFunc = OnColorChanged,
                opacityFunc = function() end,
                cancelFunc = OnCancel,
                hasOpacity = false,
                opacity = 1,
                r = r,
                g = g,
                b = b
            }
            ColorPickerFrame:SetupColorPickerAndShow(options)
        end)

        -- Filter box
        configFrame.filterBox = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
        configFrame.filterBox:SetSize(260, 20)
        configFrame.filterBox:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 12, -68)
        configFrame.filterBox:SetAutoFocus(false)
        configFrame.filterBox:SetScript("OnTextChanged",
            function() if configFrame.UpdateList then configFrame:UpdateList() end end)

        local refresh = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
        refresh:SetSize(60, 20)
        refresh:SetPoint("LEFT", configFrame.filterBox, "RIGHT", 6, 0)
        refresh:SetText("Refresh")
        refresh:SetScript("OnClick",
            function()
                DiscoverCurrencies(); if configFrame.UpdateList then configFrame:UpdateList() end
            end)

        -- Left: discovered list
        configFrame.left = CreateFrame("Frame", nil, configFrame)
        configFrame.left:SetSize(320, 340)
        configFrame.left:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 12, -100)
        configFrame.left.buttons = {}
        -- left list FauxScrollFrame (named so the scrollbar works correctly)
        configFrame.left.scroll = CreateFrame("ScrollFrame", ADDON_NAME .. "LeftFauxScroll", configFrame.left,
            "FauxScrollFrameTemplate")
        -- anchor scroll to fill left container (leave small padding for borders)
        configFrame.left.scroll:SetPoint("TOPLEFT", configFrame.left, "TOPLEFT", 6, -6)
        configFrame.left.scroll:SetPoint("BOTTOMRIGHT", configFrame.left, "BOTTOMRIGHT", -6, 6)
        local scrollLineHeight = 24
        -- handle vertical scrolling: use the FauxScroll helper for OnVerticalScroll
        configFrame.left.scroll:SetScript("OnVerticalScroll", function(self, offset)
            FauxScrollFrame_OnVerticalScroll(self, offset, scrollLineHeight)
            if configFrame.UpdateList then configFrame:UpdateList() end
        end)

        -- Right: tracked list
        configFrame.right = CreateFrame("Frame", nil, configFrame)
        configFrame.right:SetSize(200, 340)
        configFrame.right:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -12, -100)
        configFrame.right.buttons = {}
        configFrame.right.trackedCount = configFrame.right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        configFrame.right.trackedCount:SetPoint("TOPRIGHT", -4, 12)
        configFrame.right.trackedCount:SetText("Tracked " .. #profile.tracked .. " / 18")

        -- build left/right button pools
        for i = 1, 14 do
            -- parent each button to the left container (we populate visible rows manually)
            local b = CreateFrame("Button", nil, configFrame.left)
            b:SetSize(300, 22)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(16, 16)
            b.icon:SetPoint("LEFT", 4, 0)
            b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
            b.add = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
            b.add:SetSize(58, 18)
            b.add:SetPoint("RIGHT", b, "RIGHT", -4, 0)
            b:Hide()
            configFrame.left.buttons[i] = b
        end

        for i = 1, 18 do
            local b = CreateFrame("Button", nil, configFrame.right)
            b:SetSize(180, 22)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(16, 16)
            b.icon:SetPoint("LEFT", 4, 0)
            b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
            b.remove = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
            b.remove:SetSize(22, 18)
            b.remove:SetPoint("RIGHT", b, "RIGHT", -4, 0)
            -- highlight background for drag target
            b.hl = b:CreateTexture(nil, "BACKGROUND")
            b.hl:SetAllPoints(b)
            b.hl:SetColorTexture(1, 1, 1, 0.06)
            b.hl:Hide()
            b:EnableMouse(true)
            b:RegisterForDrag("LeftButton")
            -- capture index for closures
            local idx = i
            b:SetScript("OnDragStart", function(self)
                -- begin drag
                if not profile.tracked or #profile.tracked < 2 then return end
                dragState.active = true
                dragState.from = idx
                dragState.target = nil
                self:SetAlpha(0.6)
            end)
            b:SetScript("OnDragStop", function(self)
                -- end drag; perform move if target set
                self:SetAlpha(1)
                if dragState.active and dragState.from then
                    local from = dragState.from
                    local to = dragState.target or from
                    dragState.active = false
                    dragState.from = nil
                    if from and to and from ~= to and profile.tracked[from] then
                        local val = tremove(profile.tracked, from)
                        if not val then return end
                        -- insert at new position; if inserting after removal, adjust if necessary
                        if to > #profile.tracked + 1 then to = #profile.tracked + 1 end
                        tinsert(profile.tracked, to, val)
                        RebuildLines()
                        if configFrame and configFrame.UpdateTrackedList then configFrame:UpdateTrackedList() end
                        if configFrame and configFrame.UpdateList then configFrame:UpdateList() end
                    end
                end
                dragState.target = nil
                -- clear highlights
                for _, rb in ipairs(configFrame.right.buttons) do if rb and rb.hl then rb.hl:Hide() end end
            end)
            b:SetScript("OnEnter", function(self)
                if dragState.active and dragState.from and dragState.from ~= idx then
                    dragState.target = idx
                    if self.hl then self.hl:Show() end
                end
            end)
            b:SetScript("OnLeave", function(self)
                if dragState.active and dragState.target == idx then dragState.target = nil end
                if self.hl then self.hl:Hide() end
            end)
            b:Hide()
            configFrame.right.buttons[i] = b
        end

        function configFrame:UpdateList()
            local filter = (self.filterBox:GetText() or ""):lower()
            local filtered = {}
            for _, c in ipairs(discoveredCurrencies or {}) do
                -- if filter ~= "" then print("filter " .. filter .. " in " .. c.name:lower()) end
                if filter == "" or (c.name and string.find(c.name:lower(), filter, 1, true) ~= nil) then
                    -- if filter ~= "" then print("currency matched filter") end
                    tinsert(filtered, c)
                end
            end
            local total = #filtered
            local numButtons = #self.left.buttons
            local lineHeight = 24
            -- Ensure the faux-scroll offset is valid before updating the frame.
            -- If the filtered total shrank below the current offset, clamp it to the max allowed.
            local maxOffset = math.max(0, total - numButtons)
            local curOffset = FauxScrollFrame_GetOffset(self.left.scroll) or 0
            if curOffset > maxOffset then
                FauxScrollFrame_SetOffset(self.left.scroll, maxOffset)
            elseif curOffset < 0 then
                FauxScrollFrame_SetOffset(self.left.scroll, 0)
            end
            FauxScrollFrame_Update(self.left.scroll, total, numButtons, lineHeight)
            local offset = FauxScrollFrame_GetOffset(self.left.scroll) or 0

            -- print("setting up table")
            for i = 1, numButtons do
                local idx = offset + i
                local b = self.left.buttons[i]
                if idx <= total then
                    local c = filtered[idx]
                    -- print(c.name .. "at 4|" .. -((i - 1) * 24))
                    -- position visible button inside the left container
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", self.left, "TOPLEFT", 4, -((i - 1) * 24))
                    if c.icon then
                        b.icon:SetTexture(c.icon); b.icon:Show()
                    else
                        b.icon:Hide()
                    end
                    b.name:SetText((c.name or "") .. " (" .. tostring(c.amount or 0) .. ")")
                    b.name:SetTextColor(unpack(profile.fontColor or DB_DEFAULTS.fontColor))
                    b.add:SetText(IsTracked(c.id) and "Remove" or "Add")
                    local cid = c.id
                    b.add:SetScript("OnClick", function()
                        ToggleTracked(cid)
                        RebuildLines()
                        self:UpdateList(); self:UpdateTrackedList()
                    end)
                    b:Show()
                else
                    b:Hide()
                end
            end
            -- no scroll-child; ensure buttons are placed and the faux-scroll reflects total rows
        end

        function configFrame:UpdateTrackedList()
            local tracked = profile.tracked or {}
            self.right.trackedCount:SetText("Tracked " .. #tracked .. " / 18")
            for i = 1, #self.right.buttons do self.right.buttons[i]:Hide() end
            for i = 1, #tracked do
                local id = tracked[i]
                if i > #self.right.buttons then break end
                local b = self.right.buttons[i]
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self.right, "TOPLEFT", 4, -((i - 1) * 24))
                local info = GetCurrencyInfoByID(id)
                if info and info.icon then
                    b.icon:SetTexture(info.icon); b.icon:Show()
                else
                    b.icon:Hide()
                end
                b.name:SetText(info and info.name or ("Currency " .. tostring(id)))
                b.name:SetTextColor(unpack(profile.fontColor or DB_DEFAULTS.fontColor))
                b.remove:SetText("-")
                b.remove:SetScript("OnClick", function()
                    for idx, v in ipairs(profile.tracked) do
                        if v == id then
                            tremove(profile.tracked, idx); break
                        end
                    end
                    RebuildLines()
                    self:UpdateList(); self:UpdateTrackedList()
                end)
                b:Show()
            end
        end
    end

    DiscoverCurrencies()
    configFrame:Show()
    configFrame:Raise()
    configFrame:UpdateList()
    configFrame:UpdateTrackedList()
    return configFrame
end

local anchorUnlocked = false
local function ToggleAnchor()
    if not mainFrame then CreateMainFrame() end
    anchorUnlocked = not anchorUnlocked
    mainFrame:EnableMouse(anchorUnlocked)
    if anchorUnlocked then
        print("EllasCurrencyTracker: Anchor unlocked. Drag the box to move it. Use /ect anchor again to lock.")
    else
        print("EllasCurrencyTracker: Anchor locked.")
    end
end

-- Minimal help printer
local function PrintHelp()
    print("Ella's Currency Tracker commands:")
    print("/ect add <id|link> - add currency by id or link")
    print("/ect remove <id> - remove tracked currency")
    print("/ect list - list tracked currencies")
    print("/ect grow up|down - set growth direction")
    print("/ect config - open config window")
    print("/ect anchor - toggle anchor move mode")
    print("/ect reset - reset current profile")
end

SLASH_ELLASCURRENCY1 = "/ect"
SlashCmdList["ELLASCURRENCY"] = function(msg)
    local profile = CurrentProfile()
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "add" and rest ~= "" then
        local id = ParseCurrencyID(rest)
        if not id then
            print("EllasCurrencyTracker: Could not parse currency id from input.")
            return
        end
        local ok, err = AddCurrency(id)
        if ok then
            print("EllasCurrencyTracker: Added currency id " .. id)
        else
            print("EllasCurrencyTracker: " .. (err or "failed"))
        end
    elseif cmd == "remove" and rest ~= "" then
        local id = tonumber(rest)
        if not id then
            print("EllasCurrencyTracker: please provide numeric currency id to remove.")
            return
        end
        local ok, err = RemoveCurrency(id)
        if ok then print("EllasCurrencyTracker: Removed " .. id) else print("EllasCurrencyTracker: " .. (err or "failed")) end
    elseif cmd == "list" then
        if #profile.tracked == 0 then
            print("EllasCurrencyTracker: no currencies tracked.")
        else
            print("EllasCurrencyTracker tracked:")
            for i, id in ipairs(profile.tracked) do
                local info = GetCurrencyInfoByID(id)
                if info then
                    print(("[%d] %s - id:%d amount:%s"):format(i, info.name or "?", id, tostring(info.amount)))
                end
            end
        end
    elseif cmd == "grow" and rest ~= "" then
        local dir = rest:upper()
        if dir == "UP" or dir == "DOWN" then
            profile.grow = dir
            print("EllasCurrencyTracker: growth set to " .. dir)
            RebuildLines()
        else
            print("EllasCurrencyTracker: usage: /ect grow up|down")
        end
    elseif cmd == "anchor" then
        CreateMainFrame()
        ToggleAnchor()
    elseif cmd == "config" then
        CreateConfigWindow()
        if configFrame then
            configFrame:Show()
            configFrame:Raise()
        end
    elseif cmd == "reset" then
        profile.tracked = {}
        profile.grow = DB_DEFAULTS.grow
        profile.anchor = DB_DEFAULTS.anchor
        profile.lineHeight = DB_DEFAULTS.lineHeight
        print("EllasCurrencyTracker: settings reset. Reloading frame.")
        if mainFrame then
            mainFrame:Hide(); mainFrame = nil
        end
        CreateMainFrame()
        RebuildLines()
    elseif cmd == "profile" then
        ShowProfileManager()
        return
    elseif cmd == "help" or cmd == "" then
        PrintHelp()
    else
        PrintHelp()
    end
end

-- Event handling frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("CHAT_MSG_CURRENCY") -- sometimes useful
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        CreateMainFrame()
        RebuildLines()
    elseif event == "CURRENCY_DISPLAY_UPDATE" or event == "BAG_UPDATE_DELAYED" or event == "CHAT_MSG_CURRENCY" then
        UpdateAll()
    end
end)

-- OnAddonLoaded: ensure frame is created
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, name)
    if name == ADDON_NAME then
        InitDB()
        CreateMainFrame()
        RebuildLines()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Tooltip interaction for convenience (show currency tooltip)
local function ShowCurrencyTooltip(self)
    if not self.id then return end
    if GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local info = GetCurrencyInfoByID(self.id)
        if info and info.id then
            local link
            if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink then
                local ok, l = pcall(C_CurrencyInfo.GetCurrencyLink, info.id, 0)
                link = ok and l
            end
            if not link then
                GameTooltip:SetText(info.name or ("Currency " .. info.id))
                GameTooltip:AddLine("Amount: " .. tostring(info.amount), 1, 1, 1)
            else
                GameTooltip:SetHyperlink(link)
            end
        end
        GameTooltip:Show()
    end
end

-- Attach tooltip handlers to each new line when created
do
    local origAcquire = AcquireLine
    AcquireLine = function(index)
        local l = origAcquire(index)
        if not l._tooltipHooked then
            l:EnableMouse(true)
            l:SetScript("OnEnter", ShowCurrencyTooltip)
            l:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            l._tooltipHooked = true
        end
        return l
    end
end

-- End of addon
