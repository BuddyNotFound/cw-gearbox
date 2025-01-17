local useDebug = Config.Debug

local lowestGear = 0
local topGear = 5
local clutchUp = 1.0
local clutchDown = 1.0

local nextGear = 0
local isInVehicle = false
local isEnteringVehicle = false
local currentVehicle = 0
local currentSeat = 0
local isGearing = false

local manualFlag = 1024
local lateGearFlag = 2710

local function isDriver(vehicle)
    if (GetPedInVehicleSeat(vehicle, -1) == PlayerPedId()) then return true end
    return false
end

local function notify(text, type)
    if Config.Notify == "OX" then
        lib.notify({
            title = text,
            type = type,
        })
    end
    if Config.Notify == "QB" then
        QBCore.Functions.Notify(text, type)
    end
    if Config.Notify == "ESX" then
        ESX.ShowNotification(text, type)
    end
    if Config.Notify == "ST" then
        Prompt(text)
    end
end

function Prompt(msg) --Msg is part of the Text String at B
	SetNotificationTextEntry("STRING")
	AddTextComponentString(msg) -- B
	DrawNotification(true, false) -- Look on that website for what these mean, I forget. I think one is about flashing or not
end

local OR, XOR, AND = 1, 3, 4
local function bitOper(flag, checkFor, oper)
	local result, mask, sum = 0, 2 ^ 31
	repeat
		sum, flag, checkFor = flag + checkFor + mask, flag % mask, checkFor % mask
		result, mask = result + mask * oper % (sum - flag - checkFor), mask / 2
	until mask < 1
	return result
end

local function addManualFlag(flag)
    local hasFullAutoFlag = bitOper(flag, 512, AND) == 512
    local hasDirectShiftFlag = bitOper(flag, 2048, AND) == 2048

    -- Remove flags 512 and 2048 if present
    if hasFullAutoFlag then
        flag = bitOper(flag, 512, XOR) -- Remove flag 512
    end
    if hasDirectShiftFlag then
        flag = bitOper(flag, 2048, XOR) -- Remove flag 2048
    end

    -- Add flag 1024
    flag = bitOper(flag, manualFlag, OR)

    return math.floor(flag)
end

local function addLateGearFlag(flag)
    -- Add flag lateGearFlag
    flag = bitOper(flag, lateGearFlag, OR)

    return math.floor(flag)
end

local function removeManualFlag(flag)
    local hasFullAutoFlag = bitOper(flag, 512, AND) == 512
    local hasDirectShiftFlag = bitOper(flag, 2048, AND) == 2048

    -- Remove flags 512 and 2048 if present
    if hasFullAutoFlag then
        flag = bitOper(flag, 512, XOR) -- Remove flag 512
    end
    if hasDirectShiftFlag then
        flag = bitOper(flag, 2048, XOR) -- Remove flag 2048
    end

    -- Add flag 1024
    flag = bitOper(flag, manualFlag, XOR)

    return math.floor(flag)
end

local function hasFlag(vehicle, adv_flags)
    if adv_flags == nil then adv_flags = GetVehicleHandlingInt(vehicle, 'CCarHandlingData', 'strAdvancedFlags') end 
    if adv_flags == 0 and useDebug then 
        print('^1This vehicle either has empty advancedflags or no advanced flag in its handling file')
    end
    local flag_check_1024 = bitOper(adv_flags, manualFlag, AND)
    local vehicleHasFlag = flag_check_1024 == manualFlag
    if useDebug then print('Vehicle has flag:', vehicleHasFlag) end
    return vehicleHasFlag
end

local function createThread()
    Citizen.CreateThread(function()
        while true do
            local Player = PlayerPedId()
            local vehicle = GetVehiclePedIsUsing(Player)
            if not vehicle or not isDriver(vehicle) then 
                TerminateThisThread() 
                break;
            end
            Wait(1) -- Disable gtas gear stuff
            DisableControlAction(0, 363, true)
            DisableControlAction(0, 364, true)
        end
    end)
end

local function vehicleHasManualGearBox(vehicle)
    local adv_flags = GetVehicleHandlingInt(vehicle, 'CCarHandlingData', 'strAdvancedFlags')
    if hasFlag(vehicle, adv_flags) then
        if Config.CwTuning then
            if not exports['cw-tuning']:vehicleIsManual(vehicle) then -- If the car has the flag but no the gearbox then remove it
                local newFlag = removeManualFlag(adv_flags)
                local adv_flags = SetVehicleHandlingInt(vehicle, 'CCarHandlingData', 'strAdvancedFlags', newFlag)
                ModifyVehicleTopSpeed(vehicle, 1.0)
                return
            else
            end
        end
        topGear = GetVehicleHighGear(vehicle)
        clutchDown = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fClutchChangeRateScaleDownShift')
        clutchUp = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fClutchChangeRateScaleUpShift')
        notify('This vehicle is a manual')
        createThread()
    else
        if Config.CwTuning then
            if not exports['cw-tuning']:vehicleIsManual(vehicle) then 
                return
            else
                local newFlag = addManualFlag(adv_flags)
                if useDebug then print('after manual flag added', newFlag) end
                -- newFlag = addLateGearFlag(newFlag)
                -- if useDebug then print('after late gear flag added', newFlag) end
                local adv_flags = SetVehicleHandlingInt(vehicle, 'CCarHandlingData', 'strAdvancedFlags', newFlag)
                ModifyVehicleTopSpeed(vehicle, 1.0)
                topGear = GetVehicleHighGear(vehicle)
                clutchDown = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fClutchChangeRateScaleDownShift')
                clutchUp = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fClutchChangeRateScaleUpShift')
                notify('This vehicle is a manual')
                createThread()
            end
        elseif Config.UseOtherCheck then
            print('^1If you can see this print then someone enabled UseOtherCheck for manual gears but didnt add any code') -- REMOVE THIS IF YOU IMPLEMENT SOMETHING HERE
            -- ADD YOUR CHECK HERE
        end
    end
end exports('vehicleHasManualGearBox', vehicleHasManualGearBox)

AddEventHandler('gameEventTriggered', function (name, args)
    if name == 'CEventNetworkPlayerEnteredVehicle' then
        local Player = PlayerPedId()
        local vehicle = GetVehiclePedIsUsing(Player)
        -- if not isDriver(vehicle) then return end -- check for if driverseat
        vehicleHasManualGearBox(vehicle)
    end
end)


local setGear = GetHashKey('SET_VEHICLE_CURRENT_GEAR') & 0xFFFFFFFF
local function setNextGear(veh)
    local currentGear = GetVehicleCurrentGear(veh)
    Citizen.InvokeNative(setGear, veh, nextGear)
    Entity(veh).state:set('gearchange', nextGear, true)
end
local function setNoGear(veh)
    Citizen.InvokeNative(setGear, veh, 0)
end

local function SetVehicleCurrentGear(veh, gear, clutch, currentGear, gearingUp)
    if useDebug then notify('next gear: '.. nextGear) end
    if isGearing then return end
    setNoGear(veh)
    isGearing = true
    SetTimeout(Config.ClutchTime/clutch, function () -- should be 900/clutch but this lets manual gearing be a tad faster
        isGearing = false
        setNextGear(veh)
    end)
end

if Config.OxLib then
    if useDebug then print('^2OxLib is enabled') end
    if not lib then
        print('^OxLib is enabled but no lib was found. Might be missing from fxmanifest')
    else
        lib.addKeybind({
            name = 'shiftup',
            description = 'Shift Up',
            defaultKey = Config.Keys.gearUp,
            onPressed = function(self)
                local Player = PlayerPedId()
                local vehicle = GetVehiclePedIsUsing(Player)
                if not isDriver(vehicle) then return end
                if not hasFlag(vehicle) then return end
                local currentGear = GetVehicleCurrentGear(vehicle)
                if currentGear == topGear then return end
                if nextGear > topGear then return end
        
                if currentGear == lowestGear then
                    nextGear = nextGear+1
                else
                    nextGear = GetVehicleNextGear(vehicle)+1
                end
                
                SetVehicleCurrentGear( vehicle, nextGear, clutchUp, currentGear, true)
                ModifyVehicleTopSpeed(vehicle,1)
            end
        })
        
        lib.addKeybind({
            name = 'shiftdown',
            description = 'Shift Down',
            defaultKey = Config.Keys.gearDown,
            onPressed = function(self)
                local Player = PlayerPedId()
                local vehicle = GetVehiclePedIsUsing(Player)
                if not isDriver(vehicle) then return end
                if not hasFlag(vehicle) then return end
        
                local currentGear = GetVehicleCurrentGear(vehicle)
                if currentGear == lowestGear then
                    local newNextGear = nextGear-1
                    if newNextGear > 0 then nextGear = newNextGear end
                else
                    local newNextGear = GetVehicleNextGear(vehicle)-1
                    if newNextGear > 0 then nextGear = newNextGear end
                end
                SetVehicleCurrentGear( vehicle,  nextGear , clutchDown, currentGear, false)
                ModifyVehicleTopSpeed(vehicle,1)
            end
        })
    end
else
    RegisterCommand("clickShiftUp", function()
        local Player = PlayerPedId()
        local vehicle = GetVehiclePedIsUsing(Player)
        if not isDriver(vehicle) then return end
        if not hasFlag(vehicle) then return end
        local currentGear = GetVehicleCurrentGear(vehicle)
        if currentGear == topGear then return end
        if nextGear > topGear then return end

        if currentGear == lowestGear then
            nextGear = nextGear+1
        else
            nextGear = GetVehicleNextGear(vehicle)+1
        end
        
        SetVehicleCurrentGear( vehicle, nextGear, clutchUp, currentGear, true)
        ModifyVehicleTopSpeed(vehicle,1)
    end, false)
    RegisterKeyMapping("clickShiftUp", "Shift Up", "keyboard", Config.Keys.gearUp)

    RegisterCommand("clickShiftDown", function()
        local Player = PlayerPedId()
        local vehicle = GetVehiclePedIsUsing(Player)
        if not isDriver(vehicle) then return end
        if not hasFlag(vehicle) then return end

        local currentGear = GetVehicleCurrentGear(vehicle)
        if currentGear == lowestGear then
            local newNextGear = nextGear-1
            if newNextGear > 0 then nextGear = newNextGear end
        else
            local newNextGear = GetVehicleNextGear(vehicle)-1
            if newNextGear > 0 then nextGear = newNextGear end
        end
        SetVehicleCurrentGear( vehicle,  nextGear , clutchDown, currentGear, false)
        ModifyVehicleTopSpeed(vehicle,1)
    end, false)
    RegisterKeyMapping("clickShiftDown", "Shift Up", "keyboard", Config.Keys.gearDown)
end

AddStateBagChangeHandler("gearchange", nil, function(bagName, key, value) 
    local veh = GetEntityFromStateBagName(bagName)
    if isDriver(veh) then return end
    if useDebug then print('gear change for veh', veh, value) end
    if veh == 0 then return end
    while not HasCollisionLoadedAroundEntity(veh) do
        if not DoesEntityExist(veh) then return end
        Wait(250)
    end
    local Player = PlayerPedId()
    Citizen.InvokeNative(setGear, veh, value)
end)