local AddonName, SpellInspectMode = ...

-- This ensures the table is globally accessible
_G[AddonName] = SpellInspectMode

-- Global declarations for keybinds
BINDING_HEADER_SPELL_INSPECT_MODE = "Spell Inspect Mode"
BINDING_NAME_SPELL_INSPECT_MODE_TOGGLE_INSPECT_MODE = "Toggle Inspect Mode"

-- Initialize the Inspect Mode state
local isInInspectMode = false

-- Stack to keep track of opened tooltips
local tooltipStack = {}

-- Last hovered spell ID
local lastHoveredSpellID = nil

-- Create an overlay frame to obscure the game while in Inspect Mode
local overlay = CreateFrame("Frame", "InspectModeOverlay", UIParent)
overlay:SetFrameStrata("DIALOG") -- Ensure it is above the UI elements
overlay:SetAllPoints(UIParent)
overlay:EnableMouse(true)        -- to get mouse events
overlay:Hide()

-- Add a semi-transparent black texture to the overlay
local overlayTexture = overlay:CreateTexture(nil, "BACKGROUND")
overlayTexture:SetColorTexture(0, 0, 0, 0.6) -- Semi-transparent black
overlayTexture:SetAllPoints(overlay)

-- Function to populate the player's spell table
-- Iterates through the spellbook and stores spells and their attributes, checking for passive vs active
local function PopulatePlayerSpells(table)
    for i = 2, C_SpellBook.GetNumSpellBookSkillLines() do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(i)
        local offset, numSlots = skillLineInfo.itemIndexOffset, skillLineInfo.numSpellBookItems
        for j = offset + 1, offset + numSlots do
            local name = C_SpellBook.GetSpellBookItemName(j, Enum.SpellBookSpellBank.Player)
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(j, Enum.SpellBookSpellBank.Player)
            if name and spellInfo and spellInfo.actionID then
                if table[name] and spellInfo.isPassive then
                    -- Skip passive spells if an active spell with the same name exists
                else
                    table[name] = {
                        spellID = spellInfo.actionID,
                        isPassive = spellInfo.isPassive,
                    }
                end
            end
        end
    end
end

-- Function to populate the player's talent table
-- Retrieves talents and stores their attributes, checking for passive vs active
local function PopulatePlayerTalents(table)
    local configID = C_ClassTalents.GetActiveConfigID()

    if (not configID) then
        return {}
    end
    local configInfo = C_Traits.GetConfigInfo(configID)
    local nodeIDs = C_Traits.GetTreeNodes(configInfo.treeIDs[1])

    for i, nodeID in ipairs(nodeIDs) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
        for j, entryID in ipairs(nodeInfo.entryIDs) do
            local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
            local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
            local talentSpellID = definitionInfo.spellID
            if talentSpellID then
                local talentName = GetSpellInfo(talentSpellID)
                local isPassive = C_Spell.IsSpellPassive(talentSpellID)
                if table[talentName] and isPassive then
                    -- Skip passive spells if an active spell with the same name exists
                else
                    table[talentName] = {
                        spellID = talentSpellID,
                        isPassive = isPassive,
                    }
                end
            end
        end
    end
end

-- Function to create a new custom tooltip
-- Creates or reuses a tooltip for displaying spell information
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
-- Toggles between activating and deactivating inspect mode based on the current state and hovered spell
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
-- Shows the overlay and positions the tooltip with the spell information
function SpellInspectMode:ActivateInspectMode(spellID)
    if spellID then
        isInInspectMode = true

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
                    anchor = Enum.TooltipTextureAnchor.LeftBottom,
                    margin = { left = 0, right = 8, top = 0, bottom = 0 },
                    region = Enum.TooltipTextureRelativeRegion.LeftLine,
                }
                -- I'd love to add texture at the top left of the tooltip, but it adds the texture at the last "AddLine" position.
                -- So, I'm adding it at the bottom left of the tooltip.
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
-- Hides the tooltip and overlay, and removes the last tooltip from the stack
function SpellInspectMode:DeactivateInspectMode()
    if #tooltipStack > 0 then
        local tooltipData = table.remove(tooltipStack)
        tooltipData.tooltip:Hide()
    end

    if #tooltipStack == 0 then
        isInInspectMode = false

        -- Hide the overlay
        overlay:Hide()
    end
end

-- Function to process tooltip data for custom tooltips like InspectModeTooltip
-- Adds links and highlights for spells and talents within the tooltip text
function SpellInspectMode:ProcessTooltipData(tooltip)
    local numLines = tooltip:NumLines()
    for i = 2, numLines do
        local leftTextLine = _G[tooltip:GetName() .. "TextLeft" .. i]
        if leftTextLine then
            local tooltipText = leftTextLine:GetText()
            if tooltipText then
                for name, info in pairs(SpellInspectMode.spells) do
                    local startIndex = string.find(tooltipText, name, 1, true)
                    if startIndex then
                        -- Determine color based on passive or active
                        local color = info.isPassive and "ff67BCFF" or "ffffffcc"

                        -- Create a highlighted link
                        local link = "|c" .. color .. "|Hspell:" .. info.spellID .. "|h" .. name .. "|h|r"
                        tooltipText = string.gsub(tooltipText, name, link, 1)
                        leftTextLine:SetText(tooltipText)
                    end
                end
            end
        end
    end
end

-- Register the function for the spell tooltip data type
-- Ensures tooltips are processed when displaying spell data
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip)
    if tooltip:GetName() == "GameTooltip" then
        SpellInspectMode:ProcessTooltipData(tooltip)
    end
end)

-- Exits Inspect Mode when Escape is pressed
hooksecurefunc("StaticPopup_EscapePressed", function()
    while isInInspectMode do
        SpellInspectMode:DeactivateInspectMode()
    end
end)

-- Event frame to handle initialization and updates
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("SPELLS_CHANGED")

-- Event handler function
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "SPELLS_CHANGED" then
        -- Initialize or update the spell and talent data
        SpellInspectMode.spells = {};
        PopulatePlayerSpells(SpellInspectMode.spells)
        PopulatePlayerTalents(SpellInspectMode.spells)
    end
end)
