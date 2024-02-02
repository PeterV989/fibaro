-----------------------------------------------------------------------------
--                  NEST THERMOSTAT                                        --
--                  type: com.fibaro.hvacSystemAuto                        --
-----------------------------------------------------------------------------
class 'NestThermostat' (QuickAppChild)

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

    -- update two variables for setpoint adjustments
    self:setVariable('heatingThermostatSetpointHold', '0')
    self:setVariable('coolingThermostatSetpointHold', '0')
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
        local roundedValue = math.ceil(temp * 10) / 10
        self:updateProperty("heatingThermostatSetpoint", roundedValue)
    end

    if body['traits']['sdm.devices.traits.ThermostatTemperatureSetpoint']['coolCelsius'] ~= nil
    then
        local temp = body['traits']['sdm.devices.traits.ThermostatTemperatureSetpoint']['coolCelsius']
        local roundedValue = math.ceil(temp * 10) / 10
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
            local roundedValue = math.ceil(temp * 10) / 10
            self:updateProperty("heatingThermostatSetpoint", roundedValue)
        end
        if body['traits']['sdm.devices.traits.ThermostatEco']['coolCelsius'] ~= nil
        then
            local temp = body['traits']['sdm.devices.traits.ThermostatEco']['coolCelsius']
            local roundedValue = math.ceil(temp * 10) / 10
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
        self:error("Unknow mode " .. mode)
    end
end

-- handle action for setting set point for heating. ** Added second argument for current display units.
function NestThermostat:setHeatingThermostatSetpoint(value, unitArg)
    self:debug(string.format('Update heating temperature %f%s with mode %s', value, unitArg,
        self.properties.thermostatMode))

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

        self:setVariable("heatingThermostatSetpointHold", roundedHeatValue)
        self:debug('Original coolingThermostatSetpoint ' .. self.properties.coolingThermostatSetpoint)

        -- The coolingThermostatSetpoint must be greater than the heatingThermostatSetpoint.
        -- Since both the heating and cooling setpoints are updated individually but the
        -- Nest API must be adjusted for both values at the same time, there are problems when
        -- the heating setpoint is hotter than the cooling setpoint. Solution (for now) is to
        -- adjust the coolingThermostatSetpoint to be 2° higher than the new heatingThermostatSetpoint.
        -- **Note: If the user has not set these two setpoints correctly, the actual heating and cooling
        -- setpoints will reflect a 2° difference from whichever setpoint has been called last.
        local coolValue = self:getVariable('coolingThermostatSetpointHold')
        coolValue = tonumber(coolValue)
        self:debug('coolingThermostatSetpointHold ' .. coolValue)
        if coolValue < 0.1 then
            coolValue = fibaro.getValue(self.id, 'coolingThermostatSetpoint')
        end
        coolValue = math.ceil(coolValue * 10) / 10
        self:debug(string.format("getValue() returned %f", coolValue))
        if (coolValue - roundedHeatValue) < 2.0 then
            coolValue = roundedHeatValue + 2.0
        end

        self:callNestApi("sdm.devices.commands.ThermostatTemperatureSetpoint.SetRange",
            { ['heatCelsius'] = roundedHeatValue, ['coolCelsius'] = coolValue },
            function()
                self:updateProperty("heatingThermostatSetpoint", roundedHeatValue)
                self:setVariable("heatingThermostatSetpointHold", "0")
                self:debug('After heating update ' .. self.properties.heatingThermostatSetpoint)
            end
        )
    end
end

-- handle action for setting set point for cooling. ** Added second argument for current display units.
function NestThermostat:setCoolingThermostatSetpoint(value, unitArg)
    self:debug(string.format('Update cooling temperature %f%s with mode %s', value, unitArg,
        self.properties.thermostatMode))

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
        self:setVariable('coolingThermostatSetpointHold', roundedCoolValue)
        self:debug('Original heatingThermostatSetpoint ' .. self.properties.heatingThermostatSetpoint)

        -- The coolingThermostatSetpoint must be greater than the heatingThermostatSetpoint.
        -- Since both the heating and cooling setpoints are updated individually but the
        -- Nest API must be adjusted for both values at the same time, there are problems when
        -- the heating setpoint is hotter than the cooling setpoint. Solution (for now) is to
        -- adjust the heatingThermostatSetpoint to be 2° lower than the new coolingThermostatSetpoint.
        -- **Note: If the user has not set these two setpoints correctly, the actual heating and cooling
        -- setpoints will reflect a 2° difference from whichever setpoint has been called last.
        local heatValue = self:getVariable('heatingThermostatSetpointHold')
        heatValue = tonumber(heatValue)
        self:debug('heatingThermostatSetpointHold ' .. heatValue)
        if heatValue < 0.1 then
            heatValue = fibaro.getValue(self.id, 'heatingThermostatSetpoint')
        end
        heatValue = math.ceil(heatValue * 10) / 10
        self:debug(string.format("getValue() returned %f", heatValue))
        if (roundedCoolValue - heatValue) < 2 then
            heatValue = roundedCoolValue - 2.0
        end

        self:callNestApi("sdm.devices.commands.ThermostatTemperatureSetpoint.SetRange",
            { ['heatCelsius'] = heatValue, ['coolCelsius'] = roundedCoolValue },
            function()
                self:updateProperty("coolingThermostatSetpoint", roundedCoolValue)
                self:setVariable("coolingThermostatSetpointHold", '0')
                self:debug('After cooling update ' .. self.properties.coolingThermostatSetpoint)
            end
        )
    end
end

--When the unit is in Fahrenheit, convert the value to Celsius
function NestThermostat:getDegreesCelsius(value, degreeUnit)
    local degreesC = value
    if (degreeUnit == 'F')
    then
        degreesC = (degreesC - 32) * 5 / 9
        self:debug(string.format('Converting %.3f°F to %.3f°C', value, degreesC))
    end
    return math.ceil(degreesC * 10) / 10
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
                self:error("callNestApi() " .. message .. " status is " .. response.status .. ": " .. response.data)
            end
        end,
        error = function(error)
            self:error("callNestApi() " .. message .. " failed: \n" .. json.encode(error))
        end
    })
end