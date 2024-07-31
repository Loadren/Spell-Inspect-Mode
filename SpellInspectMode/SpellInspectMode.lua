local AddonName, SpellInspectMode = ...
local LPS = LibStub("LibPlayerSpells-1.0")
local handler = LibStub("LibAsync"):GetHandler()

-- This ensures the table is globally accessible
_G[AddonName] = SpellInspectMode

-- Global declarations for keybinds
BINDING_HEADER_SPELL_INSPECT_MODE = "Spell Inspect Mode"
BINDING_NAME_SPELL_INSPECT_MODE_TOGGLE_INSPECT_MODE = "Toggle Inspect Mode"

-- Initialize the lock state
local isInInspectMode = false
local currentSpellID = nil

-- Stack to keep track of opened tooltips
local tooltipStack = {}

-- Last hovered spell ID
local lastHoveredSpellID = nil

-- Create an overlay frame
local overlay = CreateFrame("Frame", "InspectModeOverlay", UIParent)
overlay:SetFrameStrata("DIALOG") -- Ensure it is above the UI elements
overlay:SetAllPoints(UIParent)
overlay:EnableMouse(true)        -- to get mouse events
overlay:Hide()

-- Add a semi-transparent black texture to the overlay
local overlayTexture = overlay:CreateTexture(nil, "BACKGROUND")
overlayTexture:SetColorTexture(0, 0, 0, 0.6) -- Semi-transparent black
overlayTexture:SetAllPoints(overlay)

local function GetPlayerSpells()
    local spells = {}

    local _, className = UnitClass("player")

    -- Iterate over all spells and store the ones that are available to the player
    for spellId, flags, _, modifiedSpells in LPS:IterateSpells(className, "", "") do
        handler:Async(function()
            local spellName = GetSpellInfo(spellId)
            spells[spellName] = spellId

            if type(modifiedSpells) == "number" then
                local modifiedSpellName = GetSpellInfo(modifiedSpells)
                spells[modifiedSpellName] = modifiedSpells
            elseif type(modifiedSpells) == "table" then
                for _, modifiedSpellId in ipairs(modifiedSpells) do
                    local modifiedSpellName = GetSpellInfo(modifiedSpellId)
                    spells[modifiedSpellName] = modifiedSpellId
                end
            end
        end, "ClassSpellLooper", false)
    end

    return spells
end

-- Function to create a new custom tooltip
local function createCustomTooltip()
    local tooltipName = "InspectModeTooltip" .. (#tooltipStack + 1)
    if _G[tooltipName] then
        _G[tooltipName]:ClearAllPoints()
        _G[tooltipName]:SetOwner(UIParent, "ANCHOR_TOP")
        return _G[tooltipName]
    end
    local tooltip = CreateFrame("GameTooltip", tooltipName, UIParent, "GameTooltipTemplate")
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:EnableMouse(true)          -- Enable mouse interaction
    tooltip:SetHyperlinksEnabled(true) -- Enable hyperlink support
    tooltip:SetScript("OnHyperlinkEnter", function(self, link)
        -- Handle mouseover event on hyperlinked text
        local linkType, spellID = strsplit(":", link)
        if linkType == "spell" then
            lastHoveredSpellID = tonumber(spellID)
        end
    end)
    tooltip:SetScript("OnHyperlinkLeave", function(self)
        -- Handle mouse leave event
        lastHoveredSpellID = nil
    end)
    return tooltip
end

-- Function to toggle inspect mode state
function SpellInspectMode:ToggleInspectMode()
    local spellID

    if lastHoveredSpellID then
        spellID = lastHoveredSpellID
    else
        -- Fallback to GameTooltip spellID if no hyperlink is hovered
        local _, gameTooltipSpellID = GameTooltip:GetSpell()
        spellID = gameTooltipSpellID
    end

    if spellID then
        -- Activating or swapping inspect mode for a new spell ID
        SpellInspectMode:ActivateInspectMode(spellID)
    elseif isInInspectMode then
        -- Exiting inspect mode or closing the latest opened tooltip
        SpellInspectMode:DeactivateInspectMode()
    end
end

-- Function to activate inspect mode for a specific spell ID
function SpellInspectMode:ActivateInspectMode(spellID)
    if spellID then
        isInInspectMode = true
        currentSpellID = spellID

        -- Show the overlay
        overlay:Show()

        -- Position the tooltip at the cursor's current location
        local cursorX, cursorY = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        cursorX, cursorY = cursorX / uiScale, cursorY / uiScale

        local newTooltip = createCustomTooltip()
        newTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        newTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cursorX, cursorY)

        -- Asynchronously load spell data
        local spell = Spell:CreateFromSpellID(spellID)
        local function OnSpellDataLoaded()
            newTooltip:SetSpellByID(spellID)

            -- Fetch the spell icon
            local spellIcon = GetSpellTexture(spellID)
            if spellIcon then
                local tooltipTextureInfo = {
                    width = 32,
                    height = 32,
                    anchor = Enum.TooltipTextureAnchor.LeftTop,
                    margin = { left = 0, right = 8, top = 0, bottom = 0 },
                    region = Enum.TooltipTextureRelativeRegion.LeftLine,
                }
                newTooltip:AddTexture(spellIcon, tooltipTextureInfo)
            end

            SpellInspectMode:ProcessTooltipData(newTooltip)
        end
        

        if spell:IsSpellDataCached() then
            OnSpellDataLoaded()
        else
            spell:ContinueOnSpellLoad(OnSpellDataLoaded)
        end

        -- Set frame strata and level for proper layering
        for i, tooltipData in ipairs(tooltipStack) do
            tooltipData.tooltip:SetFrameStrata("DIALOG")
            tooltipData.tooltip:SetFrameLevel(i)
        end
        newTooltip:SetFrameStrata("DIALOG")
        newTooltip:SetFrameLevel(#tooltipStack + 1)

        table.insert(tooltipStack, { tooltip = newTooltip })
    end
end

-- Function to deactivate inspect mode or close the latest opened tooltip
function SpellInspectMode:DeactivateInspectMode()
    if #tooltipStack > 0 then
        local tooltipData = table.remove(tooltipStack)
        tooltipData.tooltip:Hide()
    end

    if #tooltipStack == 0 then
        isInInspectMode = false
        currentSpellID = nil

        -- Hide the overlay
        overlay:Hide()
    end
end

-- Function to process tooltip data for custom tooltips like InspectModeTooltip
function SpellInspectMode:ProcessTooltipData(tooltip)
    local numLines = tooltip:NumLines()
    for i = 2, numLines do
        local leftTextLine = _G[tooltip:GetName() .. "TextLeft" .. i]
        if leftTextLine then
            local tooltipText = leftTextLine:GetText()
            if tooltipText then
                for spellName, id in pairs(SpellInspectMode.spells) do
                    local startIndex = string.find(tooltipText, spellName, 1, true)
                    if startIndex then
                        -- Create a clickable and highlighted link
                        local link = "|cffffffcc|Hspell:" .. id .. "|h" .. spellName .. "|h|r"
                        tooltipText = string.gsub(tooltipText, spellName, link, 1)
                        leftTextLine:SetText(tooltipText)
                    end
                end
            end
        end
    end
end

-- Register the function for the spell tooltip data type
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip)
    if tooltip:GetName() == "GameTooltip" then
        SpellInspectMode:ProcessTooltipData(tooltip)
    end
end)

-- Override the default UI behavior when the Escape key is pressed
hooksecurefunc("StaticPopup_EscapePressed", function()
    while isInInspectMode do
        SpellInspectMode:DeactivateInspectMode()
        -- Prevent the default behavior (opening the game menu)
        StaticPopup_Hide("ESCAPE")
    end
end)

-- Event frame to handle initialization
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

-- Event handler function
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == AddonName then
        SpellInspectMode.spells = GetPlayerSpells()
    end
end)
