local DEFAULT_TEMPLATE = "ZO_GamepadItemSubEntryTemplate"
local DEFAULT_HEADER_TEMPLATE = "ZO_GamepadMenuEntryHeaderTemplate"

ZOS_GamepadInventoryList = ZO_Object:Subclass()

function ZOS_GamepadInventoryList:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

--[[
Initializes the ZO_GamepadInventoryList. This should not be called directly, as it will be called be New().

control must be an XML control for intializing a parameteric list.
inventoryType must be one of the Bag enum values.
selectedDataCallback may be a function to call when the selected item has changed. May be nil.
entryEditCallback may be a function to call when initializing the ZO_GamepadEntryData for display.
    If specified, it should take a single argument which will be the ZO_GamepadEntryData, and will
    be called after entry:InitializeInventoryVisualData() and entry.itemData is set. May be nil.
categorizationFunction may be a function to call to retrieve the category string for an inventory
    item. If specified, should take a inventoryData (as returned by SHARED_INVENTORY:GenerateSingleSlotData)
    and return a string category. If nil, defaults to ZO_InventoryUtils_Gamepad_GetBestItemCategoryDescription().
sortFunction may be a function that is passed to table.sort to sort the entries for display. If nil, a default
    will be used tgat will sort alphabetically by category than by name.
useTriggers: Should the control bind the triggers to jump categories when activated? If nil, defaults to true.
]]
function ZOS_GamepadInventoryList:Initialize(control, inventoryType, slotType, selectedDataCallback, entrySetupCallback, categorizationFunction, sortFunction, useTriggers, template, templateSetupFunction)
    self.control = control
    self.inventoryType = inventoryType
    self.selectedDataCallback = selectedDataCallback
    self.entrySetupCallback = entrySetupCallback
    self.categorizationFunction = categorizationFunction
    self.sortFunction = sortFunction
    self.dataBySlotIndex = {}
    self.isDirty = true
    self.useTriggers = (useTriggers ~= false) -- nil => true
    self.template = template or DEFAULT_TEMPLATE

    local function VendorEntryTemplateSetup(control, data, selected, selectedDuringRebuild, enabled, activated)
        ZO_Inventory_BindSlot(data, slotType, data.slotIndex, data.bagId)
        ZO_SharedGamepadEntry_OnSetup(control, data, selected, selectedDuringRebuild, enabled, activated)
    end

    self.list = ZO_GamepadVerticalParametricScrollList:New(self.control)
    self.list:AddDataTemplate(self.template, templateSetupFunction or VendorEntryTemplateSetup, ZO_GamepadMenuEntryTemplateParametricListFunction)
    self.list:AddDataTemplateWithHeader(self.template, templateSetupFunction or VendorEntryTemplateSetup, ZO_GamepadMenuEntryTemplateParametricListFunction, nil, DEFAULT_HEADER_TEMPLATE, MenuEntryHeaderTemplateSetup)

    -- generate the trigger keybinds so we can add/remove them later when necessary
    self.triggerKeybinds = {}
    ZO_Gamepad_AddListTriggerKeybindDescriptors(self.triggerKeybinds, self.list)

    local function SelectionChangedCallback(list, selectedData)
        local selectedControl = list:GetTargetControl()
        if self.selectedDataCallback then
            self.selectedDataCallback(list, selectedData)
        end
        if selectedData then
            GAMEPAD_INVENTORY:PrepareNextClearNewStatus(selectedData)
            self:GetParametricList():RefreshVisible()
        end
    end

    local function OnEffectivelyShown()
        if self.isDirty then
            self:RefreshList()
        elseif self.selectedDataCallback then
            self.selectedDataCallback(self.list, self.list:GetTargetData())
        end
        self:Activate()
    end

    local function OnEffectivelyHidden()
        GAMEPAD_INVENTORY:TryClearNewStatusOnHidden()
        self:Deactivate()
    end

    local function OnInventoryUpdated(bagId)
        if bagId == self.inventoryType then
            self:RefreshList()
        end
    end

    local function OnSingleSlotInventoryUpdate(bagId, slotIndex)
        if bagId == self.inventoryType then
            local entry = self.dataBySlotIndex[slotIndex]
            if entry then
                local itemData = SHARED_INVENTORY:GenerateSingleSlotData(self.inventoryType, slotIndex)
                if itemData then
                    itemData.bestGamepadItemCategoryName = ZO_InventoryUtils_Gamepad_GetBestItemCategoryDescription(itemData)
                    self:SetupItemEntry(entry, itemData)
                    self.list:RefreshVisible()
                else -- The item was removed.
                    self:RefreshList()
                end
            else -- The item is new.
                self:RefreshList()
            end
        end
    end

    self:SetOnSelectedDataChangedCallback(SelectionChangedCallback)

    self.control:SetHandler("OnEffectivelyShown", OnEffectivelyShown)
    self.control:SetHandler("OnEffectivelyHidden", OnEffectivelyHidden)

    SHARED_INVENTORY:RegisterCallback("FullInventoryUpdate", OnInventoryUpdated)
    SHARED_INVENTORY:RegisterCallback("SingleSlotInventoryUpdate", OnSingleSlotInventoryUpdate)
end

--[[
Change the inventory type specified during initialization to another value, and refreshes the list.

inventoryType must be one of the Bag enum values.
]]--
function ZOS_GamepadInventoryList:SetInventoryType(inventoryType)
    if self.inventoryType == inventoryType then
        return
    end

    self.inventoryType = inventoryType
    self:RefreshList()
end

--[[
Add a function called when the selected item is changed.
]]--
function ZOS_GamepadInventoryList:SetOnSelectedDataChangedCallback(selectedDataCallback)
    self.list:SetOnSelectedDataChangedCallback(selectedDataCallback)
end

--[[
Remove a function called when the selected item is changed.
]]--
function ZOS_GamepadInventoryList:RemoveOnSelectedDataChangedCallback(selectedDataCallback)
    self.list:RemoveOnSelectedDataChangedCallback(selectedDataCallback)
end

--[[
categorizationFunction function may be a function which takes a inventory data and returns
    a category string.
]]--
function ZOS_GamepadInventoryList:SetCategorizationFunction(categorizationFunction)
    self.categorizationFunction = categorizationFunction
    self:RefreshList()
end

--[[
Sets the function which is passed to table.sort() when sorting the inventory inventory items.
]]--
function ZOS_GamepadInventoryList:SetSortFunction(sortFunction)
    self.sortFunction = sortFunction
    self:RefreshList()
end

--[[
entryEditCallback may be a function to call when initializing the ZO_GamepadEntryData for display.
    If specified, it should take a single argument which will be the ZO_GamepadEntryData, and will
    be called after entry:InitializeInventoryVisualData() and entry.itemData is set. May be nil.
]]--
function ZOS_GamepadInventoryList:SetEntrySetupCallback(entrySetupCallback)
    self.entrySetupCallback = entrySetupCallback
    self:RefreshList()
end

--[[
itemFilterFunction function may be a function which takes an inventory data and returns whether to
    include the item in the inventory list. If set to nil, all items will be included.
]]--
function ZOS_GamepadInventoryList:SetItemFilterFunction(itemFilterFunction)
    self.itemFilterFunction = itemFilterFunction
    self:RefreshList()
end

--[[
Sets whether to bind the triggers to jump categories while the list is active.

If the list is currently active, this will add/remove the bindings immediately.
]]--
function ZOS_GamepadInventoryList:SetUseTriggers(useTriggers)
    if self.useTriggers == useTriggers then -- Exit out if no change, to simplify later logic.
        return
    end

    self.useTriggers = useTriggers
    if self.list:IsActive() then
        if useTriggers then
            KEYBIND_STRIP:AddKeybindButtonGroup(self.triggerKeybinds)
        else
            KEYBIND_STRIP:RemoveKeybindButtonGroup(self.triggerKeybinds)
        end
    end
end

--[[
Returns the currently selected entry's data.
]]--
function ZOS_GamepadInventoryList:GetTargetData()
    return self.list:GetTargetData()
end

--[[
Returns the underlying parameteric list.
]]--
function ZOS_GamepadInventoryList:GetParametricList()
    return self.list
end

--[[
Moves the selection to the next item.
]]--
function ZOS_GamepadInventoryList:MoveNext()
    return self.list:MoveNext()
end

--[[
Moves the selection to the previous item.
]]--
function ZOS_GamepadInventoryList:MovePrevious()
    return self.list:MovePrevious()
end

--[[
Query if the inventory list is empty
]]--
do
    local function HasSlotData(inventoryType, slotIndex, filterFunction)
        local slotData = SHARED_INVENTORY:GenerateSingleSlotData(inventoryType, slotIndex)
        if slotData then
            if (not filterFunction) or filterFunction(slotData) then
                return true
            end
        end
        return false
    end

    function ZOS_GamepadInventoryList:IsEmpty()
        local inventoryType = self.inventoryType
        local filterFunction = self.itemFilterFunction

        local bagId = self.inventoryType
        local slotIndex = ZO_GetNextBagSlotIndex(bagId)
        while slotIndex do
            if HasSlotData(inventoryType, slotIndex, filterFunction) then
                return false
            end
            slotIndex = ZO_GetNextBagSlotIndex(bagId, slotIndex)
        end

        return true
    end
end

--[[
Passthrough functions for operating on the parametric list itself
]]--
function ZOS_GamepadInventoryList:SetFirstIndexSelected(...)
    self.list:SetFirstIndexSelected(...)
end

function ZOS_GamepadInventoryList:SetLastIndexSelected(...)
    self.list:SetLastIndexSelected(...)
end

function ZOS_GamepadInventoryList:SetPreviousSelectedDataByEval(...)
    return self.list:SetPreviousSelectedDataByEval(...)
end

function ZOS_GamepadInventoryList:SetNextSelectedDataByEval(...)
    return self.list:SetNextSelectedDataByEval(...)
end

--[[
Moves the selection to the specified item.

The same arguments can be provided as ZO_ParametricScrollList.SetSelectedIndex() accepts.
]]--
function ZOS_GamepadInventoryList:SetSelectedIndex(...)
    self.list:SetSelectedIndex(...)
end

--[[
Activates the inventory list.
]]--
function ZOS_GamepadInventoryList:Activate()
    self.list:Activate()
    if self.useTriggers then
        KEYBIND_STRIP:AddKeybindButtonGroup(self.triggerKeybinds)
    end
end

--[[
Deactivates the inventory list.
]]--
function ZOS_GamepadInventoryList:Deactivate()
    if self.useTriggers then
        KEYBIND_STRIP:RemoveKeybindButtonGroup(self.triggerKeybinds)
    end
    self.list:Deactivate()
end

--[[
An internal helper function used to initialize or update a ZO_GamepadEntryData
 with itemData.
]]--
function ZOS_GamepadInventoryList:SetupItemEntry(entry, itemData)
    entry:InitializeInventoryVisualData(itemData)
    entry.itemData = itemData
    if self.entrySetupCallback then
        self.entrySetupCallback(entry)
    end
end

local DEFAULT_GAMEPAD_ITEM_SORT =
{
    bestGamepadItemCategoryName = { tiebreaker = "name" },
    name = { tiebreaker = "requiredLevel" },
    requiredLevel = { tiebreaker = "requiredChampionPoints", isNumeric = true },
    requiredChampionPoints = { tiebreaker = "iconFile", isNumeric = true },
    iconFile = { tiebreaker = "uniqueId" },
    uniqueId = { isId64 = true },
}

local function ItemSortFunc(data1, data2)
     return ZO_TableOrderingFunction(data1, data2, "bestGamepadItemCategoryName", DEFAULT_GAMEPAD_ITEM_SORT, ZO_SORT_ORDER_UP)
end

function ZOS_GamepadInventoryList:AddSlotDataToTable(slotsTable, slotIndex)
    local itemFilterFunction = self.itemFilterFunction
    local categorizationFunction = self.categorizationFunction or ZO_InventoryUtils_Gamepad_GetBestItemCategoryDescription

    local slotData = SHARED_INVENTORY:GenerateSingleSlotData(self.inventoryType, slotIndex)
    if slotData then
        if (not itemFilterFunction) or itemFilterFunction(slotData) then
            -- itemData is shared in several places and can write their own value of bestItemCategoryName.
            -- We'll use bestGamepadItemCategoryName instead so there are no conflicts.
            slotData.bestGamepadItemCategoryName = categorizationFunction(slotData)

            table.insert(slotsTable, slotData)
        end
    end
end

function ZOS_GamepadInventoryList:GenerateSlotTable()
    local slots = {}

    local bagId = self.inventoryType
    local slotIndex = ZO_GetNextBagSlotIndex(bagId)
    while slotIndex do
        self:AddSlotDataToTable(slots, slotIndex)
        slotIndex = ZO_GetNextBagSlotIndex(bagId, slotIndex)
    end

    table.sort(slots, self.sortFunction or ItemSortFunc)
    return slots
end

--[[
If the list is hidden, queues a refresh for the next time the list is shown.
 Otherwise, clears and fully refreshes the list.
]]--
function ZOS_GamepadInventoryList:RefreshList()
    if self.control:IsHidden() then
        self.isDirty = true
        return
    end
    self.isDirty = false

    self.list:Clear()
    self.dataBySlotIndex = {}

    local slots = self:GenerateSlotTable()
    local currentBestCategoryName = nil
    for i, itemData in ipairs(slots) do
        local entry = ZO_GamepadEntryData:New(itemData.name, itemData.iconFile)
        self:SetupItemEntry(entry, itemData)

        if itemData.bestGamepadItemCategoryName ~= currentBestCategoryName then
            currentBestCategoryName = itemData.bestGamepadItemCategoryName
            entry:SetHeader(currentBestCategoryName)

            self.list:AddEntryWithHeader(self.template, entry)
        else
            self.list:AddEntry(self.template, entry)
        end

        self.dataBySlotIndex[itemData.slotIndex] = entry
    end

    self.list:Commit()
end

--[[
Refreshes the appearance of the list without clearing and fully refreshing the list
]]--
function ZOS_GamepadInventoryList:RefreshVisible()
    self.list:RefreshVisible()
end

--[[
Enables or disables direcitonal input to the list.

enable must be a boolean.
]]--
function ZOS_GamepadInventoryList:SetDirectionalInputEnabled(enable)
    self.list:SetDirectionalInputEnabled(enable)
end

--[[
Sets if the inventory list is aligned to the screen center.
Does not need an expectedEntryHeight
]]--
function ZOS_GamepadInventoryList:SetAlignToScreenCenter(alignToScreenCenter, expectedEntryHeight)
    self.list:SetAlignToScreenCenter(alignToScreenCenter, expectedEntryHeight)
end

--[[
Gets the control of the list
]]--
function ZOS_GamepadInventoryList:GetControl()
    return self.list:GetControl()
end

--[[
Returns true if the list is active
]]--
function ZOS_GamepadInventoryList:IsActive()
    return self.list:IsActive()
end

function ZOS_GamepadInventoryList:SetNoItemText(noItemText)
    self.list:SetNoItemText(noItemText)
end

function ZOS_GamepadInventoryList:ClearList()
    self.list:Clear()
end