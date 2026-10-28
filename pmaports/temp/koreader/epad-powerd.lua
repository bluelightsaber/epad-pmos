local BasePowerD = require("device/generic/powerd")
local ffiUtil = require("ffi/util")

-- Front light: two PWM LED strings (pwm-leds, 0..1023), cold (white) and warm (amber).
local LED_COLD = "/sys/class/leds/frontlight-cold"
local LED_WARM = "/sys/class/leds/frontlight-warm"
local LED_MAX = 1023

local EPad_PowerD = BasePowerD:new{
    fl_min = 0,
    fl_max = 100,
    fl_warmth_min = 0,
    fl_warmth_max = 100,
    battery_path = "/sys/class/power_supply/battery",
    usb_path = "/sys/class/power_supply/usb",
    -- The fuel gauge (MT6351) has no charging state: the bq24296 charger reports it.
    status_file = "/sys/class/power_supply/bq24190-battery/status",
}

function EPad_PowerD:init()
    self.fl_warmth = G_reader_settings:readSetting("frontlight_warmth") or 0
end

-- Perceptual curve: the LEDs look much brighter than linear at low PWM duty cycles.
local function toPwm(level)
    if level <= 0 then
        return 0
    end
    return math.max(1, math.floor(LED_MAX * (level / 100) ^ 2 + 0.5))
end

function EPad_PowerD:_writeLeds(intensity, warmth)
    local cold = toPwm(intensity * (100 - warmth) / 100)
    local warm = toPwm(intensity * warmth / 100)
    ffiUtil.writeToSysfs(cold, LED_COLD .. "/brightness")
    ffiUtil.writeToSysfs(warm, LED_WARM .. "/brightness")
end

function EPad_PowerD:frontlightIntensityHW()
    -- The LEDs cannot tell the intensity/warmth split back: use the saved setting.
    return G_reader_settings:readSetting("frontlight_intensity") or 20
end

function EPad_PowerD:isFrontlightOnHW()
    return self:read_int_file(LED_COLD .. "/brightness") > 0 or self:read_int_file(LED_WARM .. "/brightness") > 0
end

function EPad_PowerD:setIntensityHW(intensity)
    self:_writeLeds(intensity, self.fl_warmth or 0)
    self:_decideFrontlightState()
end

function EPad_PowerD:frontlightWarmthHW()
    return self.fl_warmth or 0
end

function EPad_PowerD:setWarmthHW(warmth)
    self.fl_warmth = warmth
    if self:isFrontlightOn() then
        self:_writeLeds(self.fl_intensity, warmth)
    end
end

function EPad_PowerD:saveSettings()
    G_reader_settings:saveSetting("frontlight_intensity", self.fl_intensity)
    G_reader_settings:saveSetting("frontlight_warmth", self.fl_warmth)
    G_reader_settings:saveSetting("is_frontlight_on", self.is_fl_on)
end

-- Touch panel and pen input nodes (by name), so they can be inhibited while the screensaver is up:
-- the kernel then closes them (fewer wakeups, and nothing in a bag can wake the reader).
local function touchInputs()
    local nodes = {}
    for i = 0, 15 do
        local base = "/sys/class/input/input" .. i
        local f = io.open(base .. "/name")
        if f then
            local name = f:read("*l") or ""
            f:close()
            if name:find("cyttsp5") or name:find("2D1F") then
                table.insert(nodes, base .. "/inhibited")
            end
        end
    end
    return nodes
end

-- No suspend-to-RAM yet: "suspend" is the screensaver. Save what we can meanwhile: input is inhibited
-- (Device:_beforeSuspend), the panel and pen are closed, and the front light is switched off.
function EPad_PowerD:beforeSuspend()
    self.device:_beforeSuspend()
    for _, node in ipairs(touchInputs()) do
        ffiUtil.writeToSysfs(1, node)
    end
    if self.is_fl_on then
        self:_writeLeds(0, 0)
    end
end

function EPad_PowerD:afterResume()
    if self.is_fl_on then
        self:_writeLeds(self.fl_intensity, self.fl_warmth or 0)
    end
    for _, node in ipairs(touchInputs()) do
        ffiUtil.writeToSysfs(0, node)
    end
    self:invalidateCapacityCache()
    self.device:_afterResume()
end

function EPad_PowerD:getCapacityHW()
    return self:read_int_file(self.battery_path .. "/capacity")
end

function EPad_PowerD:isChargingHW()
    return self:read_str_file(self.status_file) == "Charging"
end

function EPad_PowerD:isChargedHW()
    return self:read_str_file(self.status_file) == "Full"
end

return EPad_PowerD
