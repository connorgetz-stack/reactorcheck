-- Project Infinity 0.1 - Better Fusion Reactor CR-only controller
-- Connect the Fusion Reactor Logic Adapter to the BACK of this computer.
-- This program never calls setInjectionRate; it only reads the current rate.
-- It does not read TR directly. It uses reaction-efficiency feedback to
-- make small CR adjustments and reverses when the last adjustment worsens EF.

local ADAPTER_SIDE = "back"
local EXPECTED_INJECTION = 84
local TARGET_EFFICIENCY = 99.5
local SAMPLE_SECONDS = 3
local CR_STEP = 1
local REVERSE_DEADBAND = 0.05
local CRITICAL_ERROR_LEVEL = 95

local adapter = peripheral.wrap(ADAPTER_SIDE)
if not adapter then
    print("ERROR: Fusion Reactor Logic Adapter not found on " .. ADAPTER_SIDE)
    return
end

local requiredMethods = {
    "getEfficiency",
    "getErrorLevel",
    "getInjectionRate",
    "adjustReactivity"
}

for _, methodName in ipairs(requiredMethods) do
    if type(adapter[methodName]) ~= "function" then
        print("ERROR: Adapter is missing method: " .. methodName)
        return
    end
end

local function readNumber(methodName)
    local ok, value = pcall(adapter[methodName])
    if not ok or type(value) ~= "number" then
        error("Could not read numeric value from " .. methodName)
    end
    return value
end

local function draw(efficiency, errorLevel, injection, direction, status, lastAdjustment)
    term.clear()
    term.setCursorPos(1, 1)
    print("====================================")
    print("  PROJECT INFINITY - CR ONLY AUTO   ")
    print("====================================")
    print(string.format("Efficiency:   %.2f%%", efficiency))
    print(string.format("Error Level:  %.2f", errorLevel))
    print(string.format("Injection:    %.2f", injection))
    print("Injection control: DISABLED")
    print("------------------------------------")
    print("CR search direction: " .. (direction > 0 and "UP" or "DOWN"))
    print("Last CR adjustment: " .. tostring(lastAdjustment))
    print("Status: " .. status)
    print("------------------------------------")
    print("Target EF: " .. TARGET_EFFICIENCY .. "%")
    print("Adapter: " .. ADAPTER_SIDE)
    print("Press any key to stop")
end

local direction = 1
local previousEfficiency = nil
local previousAdjustment = 0

print("Fusion Reactor CR-only controller")
print("Adapter connected on: " .. ADAPTER_SIDE)
print("Injection setting will NOT be changed.")
print("Current injection: " .. string.format("%.2f", readNumber("getInjectionRate")))
print("Starting in 5 seconds. Press any key to cancel.")

local startTimer = os.startTimer(5)
while true do
    local event, timerId = os.pullEventRaw()
    if event == "key" then
        print("Start cancelled.")
        return
    elseif event == "timer" and timerId == startTimer then
        break
    elseif event == "terminate" then
        return
    end
end

while true do
    local ok, efficiency, errorLevel, injection = pcall(function()
        return readNumber("getEfficiency"),
               readNumber("getErrorLevel"),
               readNumber("getInjectionRate")
    end)

    if not ok then
        print("CONTROLLER STOPPED: " .. tostring(efficiency))
        break
    end

    local status = "MONITORING"
    local adjustment = 0

    if efficiency <= 0 then
        status = "REACTOR OFFLINE - NO CR CHANGE"
        previousEfficiency = nil
        previousAdjustment = 0
    elseif errorLevel >= CRITICAL_ERROR_LEVEL then
        status = "CRITICAL ERROR - CR CONTROL PAUSED"
        previousEfficiency = nil
        previousAdjustment = 0
    elseif efficiency >= TARGET_EFFICIENCY then
        status = "EFFICIENCY TARGET MET - HOLDING CR"
        previousEfficiency = nil
        previousAdjustment = 0
    else
        if previousEfficiency ~= nil and previousAdjustment ~= 0 then
            local change = efficiency - previousEfficiency
            if change < -REVERSE_DEADBAND then
                direction = previousAdjustment > 0 and -1 or 1
                status = "EFFICIENCY FELL - REVERSING"
            elseif change > REVERSE_DEADBAND then
                direction = previousAdjustment > 0 and 1 or -1
                status = "EFFICIENCY IMPROVED - CONTINUING"
            else
                status = "EFFICIENCY FLAT - SMALL PROBE"
            end
        else
            status = "SEARCHING FOR BETTER CR"
        end

        adjustment = direction * CR_STEP
        local adjustOK, adjustError = pcall(adapter.adjustReactivity, adjustment)
        if not adjustOK then
            print("CR adjustment failed: " .. tostring(adjustError))
            break
        end

        previousEfficiency = efficiency
        previousAdjustment = adjustment
        status = status .. " (CR " .. (adjustment > 0 and "+1" or "-1") .. ")"
    end

    if math.abs(injection - EXPECTED_INJECTION) > 0.001 then
        status = status .. " | CHECK INJECTION (EXPECTED 84)"
    end

    draw(efficiency, errorLevel, injection, direction, status, adjustment)

    local timer = os.startTimer(SAMPLE_SECONDS)
    while true do
        local event, timerId = os.pullEventRaw()
        if event == "key" then
            term.clear()
            term.setCursorPos(1, 1)
            print("CR-only controller stopped by user.")
            return
        elseif event == "timer" and timerId == timer then
            break
        elseif event == "terminate" then
            term.clear()
            term.setCursorPos(1, 1)
            print("CR-only controller terminated.")
            return
        end
    end
end

term.clear()
term.setCursorPos(1, 1)
print("CR-only controller stopped.")
