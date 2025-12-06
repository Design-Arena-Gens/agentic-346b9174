-- Real Time Stancer for Assetto Corsa + CSP
-- Requires CSP 0.1.80+

local MIN_CSP_VERSION = 180

-- Check CSP version
local function checkCSPVersion()
    if not ac then
        ac.log("ERROR: AC module not available")
        return false
    end

    local cspVersion = ac.getPatchVersionCode()
    if not cspVersion or cspVersion < MIN_CSP_VERSION then
        ac.log(string.format("ERROR: CSP 0.1.80+ required (detected: %s)", cspVersion or "none"))
        return false
    end

    ac.log(string.format("Real Time Stancer loaded (CSP version: %d)", cspVersion))
    return true
end

-- State management
local state = {
    enabled = true,
    currentCar = nil,
    wheels = {
        {name = "FL", offset = 0, trackWidth = 0, camber = 0, rideHeight = 0},
        {name = "FR", offset = 0, trackWidth = 0, camber = 0, rideHeight = 0},
        {name = "RL", offset = 0, trackWidth = 0, camber = 0, rideHeight = 0},
        {name = "RR", offset = 0, trackWidth = 0, camber = 0, rideHeight = 0}
    },
    selectedWheel = 1,
    presetName = "default",
    showSaveDialog = false,
    showLoadDialog = false,
    presets = {},
    configPath = ac.getFolder(ac.FolderID.ACApps) .. "/lua/RealTimeStancer/config_presets.json"
}

-- Load presets from file
local function loadPresets()
    local file = io.open(state.configPath, "r")
    if file then
        local content = file:read("*all")
        file:close()

        local success, data = pcall(function()
            return JSON.parse(content)
        end)

        if success and data then
            state.presets = data
            ac.log("Presets loaded successfully")
        else
            state.presets = {}
            ac.log("Failed to parse presets, starting fresh")
        end
    else
        state.presets = {}
        ac.log("No presets file found, will create on first save")
    end
end

-- Save presets to file
local function savePresets()
    local file = io.open(state.configPath, "w")
    if file then
        file:write(JSON.stringify(state.presets, true))
        file:close()
        ac.log("Presets saved successfully")
        return true
    else
        ac.log("ERROR: Failed to save presets")
        return false
    end
end

-- Save current configuration as preset
local function savePreset(name)
    if not name or name == "" then
        name = "preset_" .. os.time()
    end

    state.presets[name] = {
        wheels = {}
    }

    for i, wheel in ipairs(state.wheels) do
        state.presets[name].wheels[i] = {
            offset = wheel.offset,
            trackWidth = wheel.trackWidth,
            camber = wheel.camber,
            rideHeight = wheel.rideHeight
        }
    end

    savePresets()
    ac.log("Preset saved: " .. name)
end

-- Load preset configuration
local function loadPreset(name)
    local preset = state.presets[name]
    if not preset then
        ac.log("ERROR: Preset not found: " .. name)
        return false
    end

    for i, wheel in ipairs(preset.wheels) do
        if state.wheels[i] then
            state.wheels[i].offset = wheel.offset
            state.wheels[i].trackWidth = wheel.trackWidth
            state.wheels[i].camber = wheel.camber
            state.wheels[i].rideHeight = wheel.rideHeight
        end
    end

    ac.log("Preset loaded: " .. name)
    return true
end

-- Delete preset
local function deletePreset(name)
    if state.presets[name] then
        state.presets[name] = nil
        savePresets()
        ac.log("Preset deleted: " .. name)
        return true
    end
    return false
end

-- Reset all values to default
local function resetStance()
    for _, wheel in ipairs(state.wheels) do
        wheel.offset = 0
        wheel.trackWidth = 0
        wheel.camber = 0
        wheel.rideHeight = 0
    end
    ac.log("Stance reset to defaults")
end

-- Apply stance modifications to car
local function applyStance()
    if not state.enabled or not state.currentCar then
        return
    end

    for i = 0, 3 do
        local wheel = state.wheels[i + 1]
        if wheel then
            -- Apply wheel offset (position adjustment)
            local offsetVec = vec3(wheel.offset / 1000, 0, 0)
            if i % 2 == 1 then -- Right wheels (FR, RR)
                offsetVec.x = -offsetVec.x
            end

            -- Apply track width (lateral position)
            local trackVec = vec3(wheel.trackWidth / 1000, 0, 0)
            if i % 2 == 1 then -- Right wheels
                trackVec.x = math.abs(trackVec.x)
            else -- Left wheels
                trackVec.x = -math.abs(trackVec.x)
            end

            -- Apply ride height (vertical position)
            local heightVec = vec3(0, -wheel.rideHeight / 1000, 0)

            -- Combine transformations
            local finalOffset = offsetVec + trackVec + heightVec

            -- Apply to wheel using CSP physics API
            if ac.setWheelPosition then
                ac.setWheelPosition(i, finalOffset)
            end

            -- Apply camber angle (in radians)
            if ac.setWheelCamber then
                local camberRad = math.rad(wheel.camber)
                ac.setWheelCamber(i, camberRad)
            end
        end
    end
end

-- Initialize app
local function initialize()
    if not checkCSPVersion() then
        state.enabled = false
        return false
    end

    state.currentCar = ac.getCar(0)
    if not state.currentCar then
        ac.log("ERROR: No car found")
        state.enabled = false
        return false
    end

    loadPresets()
    ac.log("Real Time Stancer initialized successfully")
    return true
end

-- Update function (called every frame)
function script.update(dt)
    if state.enabled and state.currentCar then
        applyStance()
    end
end

-- UI Rendering
function script.drawUI()
    local ui = ac.getUI()

    -- Main window
    ui.beginWindow("RealTimeStancer", vec2(400, 600))

    if not state.enabled then
        ui.text("ERROR: CSP 0.1.80+ required")
        ui.text("This app requires Custom Shaders Patch")
        ui.endWindow()
        return
    end

    -- Header
    ui.text("Real Time Stancer v1.0")
    ui.separator()

    -- Enable/Disable toggle
    if ui.checkbox("Enable Real-Time Adjustments", state.enabled) then
        state.enabled = not state.enabled
    end

    ui.separator()

    -- Wheel selector
    ui.text("Select Wheel:")
    ui.sameLine()

    for i, wheel in ipairs(state.wheels) do
        if ui.button(wheel.name) then
            state.selectedWheel = i
        end
        if i < 4 then ui.sameLine() end
    end

    ui.separator()

    local currentWheel = state.wheels[state.selectedWheel]
    ui.text("Adjusting: " .. currentWheel.name)

    -- Sliders for adjustments
    ui.text("Wheel Offset (mm):")
    local changed, newOffset = ui.slider("##offset", currentWheel.offset, -100, 100, "%.0f mm")
    if changed then
        currentWheel.offset = newOffset
    end

    ui.text("Track Width (mm):")
    local changed, newTrack = ui.slider("##track", currentWheel.trackWidth, -100, 100, "%.0f mm")
    if changed then
        currentWheel.trackWidth = newTrack
    end

    ui.text("Camber (degrees):")
    local changed, newCamber = ui.slider("##camber", currentWheel.camber, -10, 10, "%.1f°")
    if changed then
        currentWheel.camber = newCamber
    end

    ui.text("Ride Height (mm):")
    local changed, newHeight = ui.slider("##height", currentWheel.rideHeight, -50, 50, "%.0f mm")
    if changed then
        currentWheel.rideHeight = newHeight
    end

    ui.separator()

    -- Quick actions
    if ui.button("Reset Current Wheel") then
        currentWheel.offset = 0
        currentWheel.trackWidth = 0
        currentWheel.camber = 0
        currentWheel.rideHeight = 0
    end

    ui.sameLine()

    if ui.button("Reset All Wheels") then
        resetStance()
    end

    ui.separator()

    -- Preset management
    ui.text("Preset Management:")

    local changed, newName = ui.inputText("Preset Name", state.presetName, 50)
    if changed then
        state.presetName = newName
    end

    if ui.button("Save Preset") then
        savePreset(state.presetName)
    end

    ui.sameLine()

    if ui.button("Load Preset") then
        state.showLoadDialog = true
    end

    -- Available presets list
    if next(state.presets) then
        ui.separator()
        ui.text("Available Presets:")

        for name, _ in pairs(state.presets) do
            ui.text("• " .. name)
            ui.sameLine()
            if ui.button("Load##" .. name) then
                loadPreset(name)
            end
            ui.sameLine()
            if ui.button("Delete##" .. name) then
                deletePreset(name)
            end
        end
    end

    ui.endWindow()

    -- Load dialog
    if state.showLoadDialog then
        ui.beginWindow("Load Preset", vec2(300, 200))

        for name, _ in pairs(state.presets) do
            if ui.button(name) then
                loadPreset(name)
                state.showLoadDialog = false
            end
        end

        ui.separator()
        if ui.button("Cancel") then
            state.showLoadDialog = false
        end

        ui.endWindow()
    end
end

-- Initialize on load
initialize()
