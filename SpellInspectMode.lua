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

-- Function to create the overlay frame or get it from the global table
-- Creates a semi-transparent black overlay to cover the screen when in inspect mode
local function createOverlay()
    if _G["InspectModeOverlay"] then
        return _G["InspectModeOverlay"]
    end
    local overlay = CreateFrame("Frame", "InspectModeOverlay", UIParent)
    overlay:SetFrameStrata("DIALOG") -- Ensure it is above the UI elements
    overlay:SetAllPoints(UIParent)
    overlay:EnableMouse(true)        -- to get mouse events
    overlay:Hide()

    -- Add a semi-transparent black texture to the overlay
    local overlayTexture = overlay:CreateTexture(nil, "BACKGROUND")
    overlayTexture:SetColorTexture(0, 0, 0, 0.6) -- Semi-transparent black
    overlayTexture:SetAllPoints(overlay)

    -- Create and position the text
    local overlayText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    overlayText:SetPoint("TOP", overlay, "TOP", 0, -10)
    overlayText:SetText("Inspect Mode")

    -- Set a much larger font size
    local fontFile, fontHeight, fontFlags = overlayText:GetFont()
    overlayText:SetFont(fontFile, fontHeight + 20, fontFlags) -- Increase the font size significantly

    -- Add that frame to the global table
    _G[overlay:GetName()] = overlay

    tinsert(UISpecialFrames, overlay:GetName())

    overlay:SetScript("OnHide", function(self)
        -- Deactivate inspect mode when the overlay is hidden
        while isInInspectMode do
            SpellInspectMode:DeactivateInspectMode()
        end
        PlaySound(SOUNDKIT.IG_MINIMAP_CLOSE);
    end)

    overlay:SetScript("OnShow", function(self)
        PlaySound(SOUNDKIT.IG_MINIMAP_OPEN);
    end)

    return overlay
end

-- Function to populate the player's spell table and preprocess spell names
-- Iterates through the spellbook and stores spells and their attributes, checking for passive vs active
local function PopulatePlayerSpells(spellTable, lookupTable)
    for i = 2, C_SpellBook.GetNumSpellBookSkillLines() do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(i)
        local offset, numSlots = skillLineInfo.itemIndexOffset, skillLineInfo.numSpellBookItems
        for j = offset + 1, offset + numSlots do
            local name = C_SpellBook.GetSpellBookItemName(j, Enum.SpellBookSpellBank.Player)
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(j, Enum.SpellBookSpellBank.Player)
            if name and spellInfo and spellInfo.actionID then
                if spellTable[name] and spellInfo.isPassive then
                    -- Skip passive spells if an active spell with the same name exists
                else
                    spellTable[name] = {
                        spellID = spellInfo.actionID,
                        isPassive = spellInfo.isPassive,
                    }
                    -- Update the lookup table
                    for word in string.gmatch(name, "%S+") do
                        if not lookupTable[word] then
                            lookupTable[word] = {}
                        end
                        table.insert(lookupTable[word], { name = name, info = spellTable[name] })
                    end
                end
            end
        end
    end
end

-- Function to populate the player's talent table and preprocess talent names
-- Retrieves talents and stores their attributes, checking for passive vs active
local function PopulatePlayerTalents(spellTable, lookupTable)
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
                local talentName = C_Spell.GetSpellInfo(talentSpellID).name
                local isPassive = C_Spell.IsSpellPassive(talentSpellID)
                if spellTable[talentName] and isPassive then
                    -- Skip passive spells if an active spell with the same name exists
                else
                    spellTable[talentName] = {
                        spellID = talentSpellID,
                        isPassive = isPassive,
                    }
                    -- Update the lookup table
                    for word in string.gmatch(talentName, "%S+") do
                        if not lookupTable[word] then
                            lookupTable[word] = {}
                        end
                        table.insert(lookupTable[word], { name = talentName, info = spellTable[talentName] })
                    end
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

    -- Get the hovered highlighted spell ID when pressing keybind while hovering over a hyperlink
    tooltip:SetScript("OnHyperlinkEnter", function(self, link)
        local linkType, spellID = strsplit(":", link)
        if linkType == "spell" then
            lastHoveredSpellID = tonumber(spellID)
        end
    end)

    -- Reset the hovered highlighted spell ID when leaving the hyperlink
    tooltip:SetScript("OnHyperlinkLeave", function(self)
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
        local overlay = createOverlay()
        overlay:Show()

        -- Position the tooltip at the cursor's current location
        local cursorX, cursorY = GetCursorPosition()
        local uiScale = UIParent:GetEffectiveScale()
        cursorX, cursorY = cursorX / uiScale, cursorY / uiScale

        -- Play a sound only if this isn't the first tooltip
        if #tooltipStack > 0 then
            PlaySound(SOUNDKIT.IG_CHAT_SCROLL_DOWN);
        end

        local newTooltip = createCustomTooltip()
        newTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        newTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cursorX, cursorY)

        -- Asynchronously load spell data
        local spell = Spell:CreateFromSpellID(spellID)
        local function OnSpellDataLoaded()
            newTooltip:SetSpellByID(spellID)

            -- Fetch the spell icon
            local spellIcon = C_Spell.GetSpellTexture(spellID)
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

        -- Check to not superpose two sounds
        if #tooltipStack > 0 then
            PlaySound(SOUNDKIT.IG_CHAT_EMOTE_BUTTON);
        end
    end

    if #tooltipStack == 0 then
        isInInspectMode = false

        -- Hide the overlay
        local overlay = createOverlay()
        overlay:Hide()
    end
end

-- Function to process tooltip data for official tooltips and custom tooltips like InspectModeTooltip(s)
-- Adds links and highlights for spells and talents within the tooltip text
function SpellInspectMode:ProcessTooltipData(tooltip)
    local numLines = tooltip:NumLines()
    for i = 2, numLines do
        local leftTextLine = _G[tooltip:GetName() .. "TextLeft" .. i]
        if leftTextLine then
            local tooltipText = leftTextLine:GetText()
            if tooltipText then
                -- Split the tooltip text into words
                for word in string.gmatch(tooltipText, "%S+") do
                    -- Check if the word is in the lookup table
                    local spellList = SpellInspectMode.spellLookup[word]
                    if spellList then
                        for _, spellData in ipairs(spellList) do
                            local name = spellData.name
                            local info = spellData.info
                            local startIndex = 1
                            -- Loop through all occurrences of the word in the tooltip text
                            while true do
                                startIndex = string.find(tooltipText, name, startIndex, true)
                                if not startIndex then
                                    -- break if there is no occurence left in the tooltip text
                                    break
                                end
                                -- Determine color based on passive or active
                                local color = info.isPassive and "ff67BCFF" or "ffffffcc"
                                
                                -- Create a highlighted link
                                local link = "|c" .. color .. "|Hspell:" .. info.spellID .. "|h" .. name .. "|h|r"
                                tooltipText = string.sub(tooltipText, 1, startIndex - 1) .. link .. string.sub(tooltipText, startIndex + #name)
                                
                                -- Move past the current match
                                startIndex = startIndex + #link
                            end
                            leftTextLine:SetText(tooltipText)
                        end
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

-- Event frame to handle initialization and updates
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("SPELLS_CHANGED")

-- Event handler function
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "SPELLS_CHANGED" then
        -- Initialize or update the spell and talent data
        SpellInspectMode.spells = {}
        SpellInspectMode.spellLookup = {}
        PopulatePlayerSpells(SpellInspectMode.spells, SpellInspectMode.spellLookup)
        PopulatePlayerTalents(SpellInspectMode.spells, SpellInspectMode.spellLookup)
    end
end)
