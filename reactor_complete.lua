-- Project Infinity 0.1 - Better Fusion Reactor CR feedback controller
-- CC: Tweaked / Advanced Computer
-- Logic Adapter must be connected to the BACK of this computer.
-- Injection rate is READ ONLY: this program never calls setInjectionRate.
--
-- Feedback strategy follows the Better Fusion Reactor wiki example:
-- read efficiency, reverse the CR adjustment direction if efficiency fell,
-- then make one small CR adjustment and wait for the next measurement.
-- TR is not exposed to computers by the mod, so direct CR=TR tracking
-- is not possible through this adapter.

local SIDE = "back"
local EXPECTED_INJECTION = 84 -- displayed as a reminder only; never written
local START_DIRECTION = -1   -- first probe DOWN, based on the reported CR > TR
local SAMPLE_SECONDS = 5.5
local TARGET_EFFICIENCY = 99.5
local PAUSE_ERROR_LEVEL = 90
local STEP = 1

if not peripheral.isPresent(SIDE) then
    print("ERROR: No peripheral on " .. SIDE)
    return
end

local methods = peripheral.getMethods(SIDE) or {}
local has = {}
for _, name in ipairs(methods) do has[name] = true end

for _, name in ipairs({"getEfficiency", "getErrorLevel", "getInjectionRate", "adjustReactivity"}) do
    if not has[name] then
        print("ERROR: Adapter is missing method: " .. name)
        return
    end
end

local function readNumber(method)
    local ok, value = pcall(peripheral.call, SIDE, method)
    if not ok or type(value) ~= "number" then
        error("Could not read " .. method .. ": " .. tostring(value))
    end
    return value
end

local function stopWait(seconds)
    local timer = os.startTimer(seconds)
    while true do
        local event, arg = os.pullEvent()
        if event == "key" then return false end
        if event == "timer" and arg == timer then return true end
    end
end

local function draw(eff, err, injection, direction, action, previous)
    term.clear()
    term.setCursorPos(1, 1)
    print("BETTER FUSION REACTOR - CR FEEDBACK")
    print("------------------------------------")
    print(string.format("Efficiency:  %.4f%%", eff))
    print(string.format("Error Level: %.3f", err))
    print(string.format("Injection:   %.2f", injection))
    print("Injection control: READ ONLY")
    print("Expected injection: " .. EXPECTED_INJECTION)
    print("------------------------------------")
    print("Previous EF: " .. (previous and string.format("%.4f%%", previous) or "n/a"))
    print("CR direction: " .. (direction < 0 and "DOWN" or "UP"))
    print("Action: " .. action)
    print("------------------------------------")
    print("TR cannot be read by the adapter.")
    print("Press any key to stop.")
end

local direction = START_DIRECTION
local previousEfficiency = nil

local ok, initialInjection = pcall(readNumber, "getInjectionRate")
if not ok then
    print("ERROR reading injection rate: " .. tostring(initialInjection))
    return
end

print("CR feedback controller connected on " .. SIDE)
print("Current injection rate: " .. tostring(initialInjection))
print("Injection rate will NOT be changed.")
print("First probe direction: DOWN")
print("Starting in 5 seconds; press any key to cancel.")
if not stopWait(5) then
    print("Cancelled.")
    return
end

while true do
    local readOK, eff, err, injection = pcall(function()
        return readNumber("getEfficiency"),
               readNumber("getErrorLevel"),
               readNumber("getInjectionRate")
    end)

    if not readOK then
        print("CONTROLLER STOPPED: " .. tostring(eff))
        break
    end

    local action = "HOLD"

    if eff <= 0 then
        action = "REACTOR OFFLINE - NO CR CHANGE"
        previousEfficiency = nil
    elseif err >= PAUSE_ERROR_LEVEL then
        action = "ERROR LEVEL HIGH - CR CONTROL PAUSED"
        previousEfficiency = nil
    else
        -- No deadband: reverse on ANY measured efficiency decrease.
        if previousEfficiency ~= nil and eff < previousEfficiency then
            direction = -direction
            action = "EFFICIENCY FELL - REVERSED DIRECTION"
        elseif previousEfficiency ~= nil and eff > previousEfficiency then
            action = "EFFICIENCY ROSE - KEEPING DIRECTION"
        else
            action = "FIRST / FLAT SAMPLE - PROBING"
        end

        if eff >= TARGET_EFFICIENCY then
            action = action .. " | TARGET MET - HOLDING"
        else
            local adjustOK, adjustError = pcall(peripheral.call, SIDE, "adjustReactivity", direction * STEP)
            if not adjustOK then
                print("CR adjustment failed: " .. tostring(adjustError))
                break
            end
            action = action .. (direction < 0 and " | CR -1" or " | CR +1")
        end
    end

    draw(eff, err, injection, direction, action, previousEfficiency)
    previousEfficiency = eff

    if not stopWait(SAMPLE_SECONDS) then
        term.clear()
        term.setCursorPos(1, 1)
        print("Controller stopped by user.")
        return
    end
end

term.clear()
term.setCursorPos(1, 1)
print("Controller stopped.")
