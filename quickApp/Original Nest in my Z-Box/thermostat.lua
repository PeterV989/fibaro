-----------------------------------------------------------------------------
--                  NEST THERMOSTAT                                        --
--                  type: com.fibaro.hvacSystemAuto                        --
-----------------------------------------------------------------------------
class 'NestThermostat' (QuickAppChild) 

SETPOINTDELTA = 2.3 -- °C or ≈ 4°F

-- __init is a constructor for this class. All new classes must have it.
function NestThermostat:__init(device)
    -- You should not insert code before QuickAppChild.__init.
    QuickAppChild.__init(self, device)

    self:trace("NestThermostat init")

    -- set supported modes for thermostat
    self:updateProperty("supportedThermostatModes", {})

    -- setup default values
    self:updateProperty("thermostatMode", "Off")
    self:updateProperty("heatingThermostatSetpoint", 8)
    self:updateProperty("coolingThermostatSetpoint", 30)
    self:updateProperty("log", "")

    -- create four flags indicating pending setpoint update events and processing setpoint events.
    self.heatEventPending = false
    self.heatEventProcessing = false
    self.coolEventPending = false
    self.coolEventProcessing = false

    -- create two tables to store the pending setpoints
    self.heatSetpointPending = {}
    self.coolSetpointPending = {}

end

function NestThermostat:updateDevice(body)
    --self:debug("updateDevice " .. self.id .. " with body " .. json.encode(body))

    self:updateMode(body)
    self:updateTemperatureSetPoint(body)
    self:updateHvacStatus(body)
end

function NestThermostat:updateMode(body)
    self:updateAvailableModes(body)

    local thermostatMode = body['traits']['sdm.devices.traits.ThermostatMode']['mode']
    local thermostatModeEco = body['traits']['sdm.devices.traits.ThermostatEco']['mode']

    if thermostatMode == "OFF" then
        self:updateProperty("thermostatMode", "Off")
    elseif thermostatModeEco == 'MANUAL_ECO' then
        self:updateProperty("thermostatMode", "Eco")
    elseif thermostatMode == "HEAT" then
        self:updateProperty("thermostatMode", "Heat")
    elseif thermostatMode == "COOL" then
        self:updateProperty("thermostatMode", "Cool")
    elseif thermostatMode == "HEATCOOL" then
        self:updateProperty("thermostatMode", "Auto")
    else
        self:error("updateMode() failed", "Unknown mode " .. thermostatMode .. " / " .. thermostatModeEco)
    end
end

function NestThermostat:updateAvailableModes(body)
    local thermostatAvailableMode = body['traits']['sdm.devices.traits.ThermostatMode']['availableModes']
    local thermostatAvailableModeEco = body['traits']['sdm.devices.traits.ThermostatEco']['availableModes']

    local index = 1
    local supportedThermostatModes = {}

    for i, mode in ipairs(thermostatAvailableMode)
    do
        if mode == "OFF"
        then
            supportedThermostatModes[index] = "Off"
            index = index + 1
        end
        if mode == "HEAT"
        then
            supportedThermostatModes[index] = "Heat"
            index = index + 1
        end
        if mode == "COOL"
        then
            supportedThermostatModes[index] = "Cool"
            index = index + 1
        end
        if mode == "HEATCOOL"
        then
            supportedThermostatModes[index] = "Auto"
            index = index + 1
        end
    end
    for i, mode in ipairs(thermostatAvailableModeEco)
    do
        if mode == "MANUAL_ECO"
        then
            supportedThermostatModes[index] = "Eco"
            index = index + 1
        end
    end
    self:updateProperty("supportedThermostatModes", supportedThermostatModes)
end

function NestThermostat:updateTemperatureSetPoint(body)
    if body['traits']['sdm.devices.traits.ThermostatTemperatureSetpoint']['heatCelsius'] ~= nil
    then
        local temp = body['traits']['sdm.devices.traits.ThermostatTemperatureSetpoint']['heatCelsius']
        local roundedValue = QuickApp:roundValue(temp)
        self:updateProperty("heatingThermostatSetpoint", roundedValue)
    end

    if body['traits']['sdm.devices.traits.ThermostatTemperatureSetpoint']['coolCelsius'] ~= nil
    then
        local temp = body['traits']['sdm.devices.traits.ThermostatTemperatureSetpoint']['coolCelsius']
        local roundedValue = QuickApp:roundValue(temp)
        self:updateProperty("coolingThermostatSetpoint", roundedValue)
    end

    if body['traits']['sdm.devices.traits.Settings']['temperatureScale'] ~= nil
    then
        local tempUnit = 'C'
        if body['traits']['sdm.devices.traits.Settings']['temperatureScale'] == 'FAHRENHEIT' then
            tempUnit = 'F'
        end
        self:updateProperty("unit", tempUnit)
    end

    if (self.properties.thermostatMode == "Eco")
    then
        if body['traits']['sdm.devices.traits.ThermostatEco']['heatCelsius'] ~= nil
        then
            local temp = body['traits']['sdm.devices.traits.ThermostatEco']['heatCelsius']
            local roundedValue = QuickApp:roundValue(temp)
            self:updateProperty("heatingThermostatSetpoint", roundedValue)
        end
        if body['traits']['sdm.devices.traits.ThermostatEco']['coolCelsius'] ~= nil
        then
            local temp = body['traits']['sdm.devices.traits.ThermostatEco']['coolCelsius']
            local roundedValue = QuickApp:roundValue(temp)
            self:updateProperty("coolingThermostatSetpoint", roundedValue)
        end
    end
end

function NestThermostat:updateHvacStatus(body)
    if body['traits']['sdm.devices.traits.ThermostatHvac'] ~= nil
    then
        local status = body['traits']['sdm.devices.traits.ThermostatHvac']['status']
        self:updateProperty("log", status)
    else
        self:updateProperty("log", "")
    end
end

-- handle action for mode change
function NestThermostat:setThermostatMode(mode)
    self:debug("update mode " .. mode)

    if mode == 'Eco' then
        self:callNestApi("sdm.devices.commands.ThermostatMode.SetMode",
            { ['mode'] = "HEAT" },
            function()
                self:callNestApi("sdm.devices.commands.ThermostatEco.SetMode",
                    { ['mode'] = "MANUAL_ECO" },
                    function()
                        self:updateProperty("thermostatMode", mode)
                    end
                )
            end
        )
    elseif mode == 'Off' then
        self:callNestApi("sdm.devices.commands.ThermostatMode.SetMode",
            { ['mode'] = "OFF" },
            function()
                self:updateProperty("thermostatMode", mode)
            end
        )
    elseif mode == 'Heat' then
        self:callNestApi("sdm.devices.commands.ThermostatMode.SetMode",
            { ['mode'] = "HEAT" },
            function()
                self:callNestApi("sdm.devices.commands.ThermostatEco.SetMode",
                    { ['mode'] = "OFF" },
                    function()
                        self:updateProperty("thermostatMode", mode)
                    end
                )
            end
        )
    elseif mode == 'Cool' then
        self:callNestApi("sdm.devices.commands.ThermostatMode.SetMode",
            { ['mode'] = "COOL" },
            function()
                self:callNestApi("sdm.devices.commands.ThermostatEco.SetMode",
                    { ['mode'] = "OFF" },
                    function()
                        self:updateProperty("thermostatMode", mode)
                    end
                )
            end
        )
    elseif mode == 'Auto' then
        self:callNestApi("sdm.devices.commands.ThermostatMode.SetMode",
            { ['mode'] = "HEATCOOL" },
            function()
                self:callNestApi("sdm.devices.commands.ThermostatEco.SetMode",
                    { ['mode'] = "OFF" },
                    function()
                        self:updateProperty("thermostatMode", mode)
                    end
                )
            end
        )
    else
        self:error("Unknown mode " .. mode)
    end
end

function NestThermostat:setAutoThermostatSetpoint(value, unitArg)
    self:debug('setAutoThermostatSetpoint() called with value = ' .. value)
end

-- handle action for setting set point for heating. ** Added second argument for current display units.
function NestThermostat:setHeatingThermostatSetpoint(value, unitArg)
    local roundedHeatValue = self:getDegreesCelsius(value, unitArg)

    if (self.properties.thermostatMode == "Heat")
    then
        self:callNestApi("sdm.devices.commands.ThermostatTemperatureSetpoint.SetHeat",
            { ['heatCelsius'] = roundedHeatValue },
            function()
                self:updateProperty("heatingThermostatSetpoint", roundedHeatValue)
            end
        )
    elseif (self.properties.thermostatMode == "Auto")
    then
        -- When the cooling setpoint is being processed, defer the heating setpoint update
        if self.coolEventProcessing
        then
            -- indicate heating event has been deferred and store the new setpoints
            -- the cooling setpoint update will either use these values, or execute
            -- this method upon completion.
            self.heatEventPending = true
            self.heatSetpointPending = {
                temp = value,
                units = unitArg
            }
            self.heatEventProcessing = false
        else
            -- The coolingThermostatSetpoint must be greater than the heatingThermostatSetpoint.
            -- Since both the heating and cooling setpoints are updated individually but the
            -- Nest API must be adjusted for both values at the same time, there are problems when
            -- the heating setpoint is hotter than the cooling setpoint. Solution (for now) is to
            -- adjust the coolingThermostatSetpoint to be 2.3°C higher than the new heatingThermostatSetpoint.
            -- **Note: If the user has not set these two setpoints correctly, the actual heating and cooling
            -- setpoints will reflect a 2.3°C difference from whichever setpoint has been called last.
            self.heatEventProcessing = true
            self.heatEventPending = false
            local coolValue = 0
            local coolProcessing = false        -- assume the cooling setpoint hasn't been adjusted
            if self.coolEventPending then       -- the event is pending, so use the new value
                self.coolEventProcessing = true -- At this point we are handling the cooling setpoint as well
                coolProcessing = true
                self.coolEventPending = false
                coolValue = self:getDegreesCelsius(self.coolSetpointPending.temp, self.coolSetpointPending.units)
            else
                -- Can't get the new cooling setpoint (maybe there won't be a new one?)
                coolValue = self.properties.coolingThermostatSetpoint
            end
            coolValue = math.floor(coolValue * 100.0 + 0.5) / 100.0
            if (coolValue - roundedHeatValue) < SETPOINTDELTA then
                coolValue = roundedHeatValue + SETPOINTDELTA
            end

            self:callNestApi("sdm.devices.commands.ThermostatTemperatureSetpoint.SetRange",
                { ['heatCelsius'] = roundedHeatValue, ['coolCelsius'] = coolValue },
                function()
                    self:updateProperty("heatingThermostatSetpoint", roundedHeatValue)
                    self.heatEventProcessing = false
                    if coolProcessing then
                        self:updateProperty('coolingThermostatSetpoint', coolValue)
                        self.coolEventProcessing = false
                    elseif self.coolEventPending then
                        self.coolEventPending = false
                        return self:setCoolingThermostatSetpoint(self.coolSetpointPending.temp, self.coolSetpointPending.units)
                    end
                end
            )
        end
    end
end

-- handle action for setting set point for cooling. ** Added second argument for current display units.
function NestThermostat:setCoolingThermostatSetpoint(value, unitArg)
    local roundedCoolValue = self:getDegreesCelsius(value, unitArg)

    if (self.properties.thermostatMode == "Cool")
    then
        self:callNestApi("sdm.devices.commands.ThermostatTemperatureSetpoint.SetCool",
            { ['coolCelsius'] = roundedCoolValue },
            function()
                self:updateProperty("coolingThermostatSetpoint", roundedCoolValue)
            end
        )
    elseif (self.properties.thermostatMode == "Auto")
    then
        -- When the heating setpoint is being processed, defer the cooling setpoint update
        if self.heatEventProcessing
        then
            -- indicate cooling event has been deferred and store the new setpoints
            -- the heating setpoint update will either use these values, or execute
            -- this method upon completion.
            self.coolEventPending = true
            self.coolSetpointPending = {
                temp = value,
                units = unitArg
            }
            self.coolEventProcessing = false
        else
            -- The coolingThermostatSetpoint must be greater than the heatingThermostatSetpoint.
            -- Since both the heating and cooling setpoints are updated individually but the
            -- Nest API must be adjusted for both values at the same time, there are problems when
            -- the heating setpoint is hotter than the cooling setpoint. Solution (for now) is to
            -- adjust the heatingThermostatSetpoint to be 2.3°C lower than the new coolingThermostatSetpoint.
            -- **Note: If the user has not set these two setpoints correctly, the actual heating and cooling
            -- setpoints will reflect a 2.3°C difference from whichever setpoint has been called last.
            self.coolEventProcessing = true
            self.coolEventPending = false
            local heatValue = 0
            local heatProcessing = false -- assume the heating setpoint hasn't been adjusted
            if self.heatEventPending then -- the event has occurred, so use the new value
                self.heatEventProcessing = true
                heatProcessing = true
                self.heatEventPending = false
                heatValue = self:getDegreesCelsius(self.heatSetpointPending.temp, self.heatSetpointPending.units)
            else
                -- Can't get the new heating setpoint (maybe there won't be a new one?)
                heatValue = self.properties.heatingThermostatSetpoint
            end
            heatValue = QuickApp:roundValue(heatValue)
            if (roundedCoolValue - heatValue) < SETPOINTDELTA then
                heatValue = roundedCoolValue - SETPOINTDELTA
            end

            self:callNestApi("sdm.devices.commands.ThermostatTemperatureSetpoint.SetRange",
                { ['heatCelsius'] = heatValue, ['coolCelsius'] = roundedCoolValue },
                function()
                    self:updateProperty("coolingThermostatSetpoint", roundedCoolValue)
                    self.coolEventProcessing = false
                    if heatProcessing then
                        self:updateProperty('heatingThermostatSetpoint', heatValue)
                        self.heatEventProcessing = false
                    elseif self.heatEventPending then
                        self.heatEventPending = false
                        self:setHeatingThermostatSetpoint(self.heatSetpointPending.temp, self.heatSetpointPending.units)
                    end
                end
            )
        end
    end
end

--When the unit is in Fahrenheit, convert the value to Celsius
function NestThermostat:getDegreesCelsius(value, degreeUnit)
    local degreesC = value
    if (degreeUnit == 'F')
    then
        degreesC = (degreesC - 32.0) * 5.0 / 9.0
        self:debug(string.format('Converting %.3f°F to %.3f°C', value, degreesC))
    end
    return QuickApp:roundValue(degreesC)
end

-- Call Nest API
function NestThermostat:callNestApi(command, params, callback)
    local message = string.format("%s (%s)", command, json.encode(params))
    local url = string.format("https://smartdevicemanagement.googleapis.com/v1/%s:executeCommand",
        self:getVariable("uid"))

    self.parent.http:request(url, {
        options = {
            checkCertificate = true,
            method = 'POST',
            headers = {
                ['Content-Type'] = "application/json; charset=utf-8",
                ['Authorization'] = self.parent.accessToken
            },
            data = json.encode({
                ['command'] = command,
                ['params'] = params
            })
        },
        success = function(response)
            if response.status == 200 then
                self:debug("callNestApi() success " .. message)
                callback()
            else
                self:error("callNestApi() " .. message)
                self:error("status is " .. response.status .. ": " .. response.data)
            end
        end,
        error = function(error)
            self:error("callNestApi() " .. message .. " failed: \n" .. json.encode(error))
        end
    })
end
