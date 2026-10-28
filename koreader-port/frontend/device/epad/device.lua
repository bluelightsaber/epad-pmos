--[[--
E-PAD (Eewrite Epad_PRO): 10.3" E Ink tablet (MediaTek MT6797, E Ink T1000 controller) running mainline Linux.

Hardware: 1872x1404 panel (landscape framebuffer), cold/warm front light (pwm-leds), Cypress TT21000 capacitive touch reporting in framebuffer
coordinates, Wacom-like HID-over-I2C pen (20967x15725), power key on the MT6351 PMIC (gpio-keys, "1000d000.pwrap:power-key").
--]]

local Generic = require("device/generic/device")
local logger = require("logger")
local ffi = require("ffi")
local C = ffi.C
require("ffi/linux_input_h")

local function yes() return true end
local function no() return false end

local screen_width = 1872 -- unscaled_size_check: ignore
local screen_height = 1404 -- unscaled_size_check: ignore
local pen_width = 20967 -- unscaled_size_check: ignore
local pen_height = 15725 -- unscaled_size_check: ignore

-- Finds /dev/input/eventN by (a substring of) the device name.
local function findInput(pattern)
    for i = 0, 31 do
        local f = io.open("/sys/class/input/event" .. i .. "/device/name")
        if f then
            local name = f:read("*line") or ""
            f:close()
            if name:lower():find(pattern) then
                return "/dev/input/event" .. i, name
            end
        end
    end
end

local EPad = Generic:extend{
    model = "E-PAD",
    isEPad = yes,
    hasKeys = yes,
    hasOTAUpdates = no,
    hasFastWifiStatusQuery = yes,
    hasWifiManager = os.getenv("KO_DONT_MANAGE_NETWORK") ~= "1" and yes or no,
    hasWifiToggle = os.getenv("KO_DONT_MANAGE_NETWORK") ~= "1" and yes or no,
    canReboot = yes,
    canPowerOff = yes,
    canSuspend = no, -- no suspend-to-RAM on mainline yet (MT6797 SPM)
    isTouchDevice = yes,
    hasFrontlight = yes,
    hasNaturalLight = yes, -- cold (white) + warm (amber) LED strings
    canTurnFrontlightOff = yes,
    hasSystemFonts = yes,
    canHWInvert = no,
    display_dpi = 227,
    -- The framebuffer is landscape (1872x1404) but the tablet is used in portrait: rotate in software.
    isAlwaysPortrait = yes,
    home_dir = os.getenv("HOME") or "/home",
    needsScreenRefreshAfterResume = no,
}

function EPad:init()
    self.screen = require("ffi/framebuffer_epad"):new{
        device = self,
        debug = logger.dbg,
        is_always_portrait = self.isAlwaysPortrait(),
    }
    self.powerd = require("device/epad/powerd"):new{ device = self }

    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [116] = "Power", -- KEY_POWER
        },
        wacom_protocol = true,
    }

    local ts, ts_name = findInput("cyttsp5")
    local pen, pen_name = findInput("stylus")
    if not pen then pen, pen_name = findInput("pen") end
    local keys, keys_name = findInput("pwrkey")
    if not keys then keys, keys_name = findInput("power%-key") end
    logger.info("E-PAD input:", ts_name, pen_name, keys_name)
    -- Touch and pen send both ABS_MT_* and ABS_* coordinates: only scale the pen's ABS_X/ABS_Y.
    self.input.handleTouchEv = self.input.handleMixedTouchEv
    if ts then self.input:open(ts) end
    if pen then self.input:open(pen) end
    if keys then self.input:open(keys) end
    self.input:open("fake_events")

    local sx, sy = screen_width / pen_width, screen_height / pen_height
    self.input:registerEventAdjustHook(function(this, ev)
        if ev.type == C.EV_ABS then
            if ev.code == C.ABS_X then
                ev.value = ev.value * sx
            elseif ev.code == C.ABS_Y then
                ev.value = ev.value * sy
            end
        end
    end)

    -- The HID pen's BTN_TOUCH means "in range" (it only drops when the pen is lifted away), and it comes *before*
    -- BTN_TOOL_PEN in the report. Decide contact from ABS_PRESSURE instead, and drive the pen slot directly
    -- (as Input does for BTN_TOUCH on wacom_protocol). Pen reports start with MSC_SCAN (the panel never sends it).
    local pen_frame = false
    local pen_down = false
    local pen_min_pressure = tonumber(os.getenv("EPAD_PEN_PRESSURE")) or 1
    local pen_debug = os.getenv("EPAD_PEN_DEBUG")
    local function penContact(this, down)
        if down == pen_down then return end
        pen_down = down
        this:setupSlotData(this.pen_slot)
        this:setCurrentMtSlot("tool", this.TOOL_TYPE_PEN)
        this:setCurrentMtSlot("id", down and this.pen_slot or -1)
    end
    self.input:registerEventAdjustHook(function(this, ev)
        if ev.type == C.EV_MSC then
            pen_frame = true
        elseif ev.type == C.EV_SYN then
            if pen_frame and pen_debug then
                logger.info("pen", this:getCurrentMtSlotData("x"), this:getCurrentMtSlotData("y"),
                            this:getCurrentMtSlotData("id"), pen_down)
            end
            pen_frame = false
        elseif pen_frame and ev.type == C.EV_ABS and ev.code == C.ABS_PRESSURE then
            if pen_debug then logger.info("pen pressure", ev.value) end
            penContact(this, ev.value >= pen_min_pressure)
        elseif pen_frame and ev.type == C.EV_KEY and ev.code == C.BTN_TOUCH then
            -- Out of range always means lifted; otherwise ignore it (Input would treat it as contact).
            if ev.value == 0 then penContact(this, false) end
            ev.type = C.EV_ABS
            ev.code = C.ABS_PRESSURE
        end
    end)

    -- Portrait: the framebuffer is drawn rotated by -90 degrees, so map landscape panel coordinates to it.
    self.input:registerEventAdjustHook(self.input.adjustTouchSwitchAxesAndMirrorX, screen_height - 1)

    Generic.init(self)
end

function EPad:supportsScreensaver() return true end

function EPad:saveSettings()
    self.powerd:saveSettings()
end

function EPad:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOnWifi(complete_callback, interactive)
        os.execute("ip link set wlan0 up")
        return self:reconnectOrShowNetworkMenu(complete_callback, interactive)
    end

    function NetworkMgr:turnOffWifi(complete_callback)
        os.execute("ip link set wlan0 down")
        if complete_callback then
            complete_callback()
        end
    end

    function NetworkMgr:getNetworkInterfaceName()
        return "wlan0"
    end

    NetworkMgr:setWirelessBackend("wpa_supplicant", {ctrl_interface = "/var/run/wpa_supplicant/wlan0"})
    NetworkMgr.isWifiOn = NetworkMgr.sysfsWifiOn
    NetworkMgr.isConnected = NetworkMgr.ifHasAnAddress
end

function EPad:setEventHandlers(UIManager)
    UIManager.event_handlers.PowerPress = function()
        UIManager:scheduleIn(2, UIManager.poweroff_action)
    end
    UIManager.event_handlers.Suspend = function()
        self:onPowerEvent("Suspend")
    end
    UIManager.event_handlers.Resume = function()
        self:onPowerEvent("Resume")
    end
    -- Short press: screensaver on/off (no suspend-to-RAM yet). Long press (2 s): power off.
    UIManager.event_handlers.PowerRelease = function()
        if not UIManager._entered_poweroff_stage then
            UIManager:unschedule(UIManager.poweroff_action)
            if self.screen_saver_mode and not self.screen_saver_lock then
                UIManager.event_handlers.Resume()
            else
                UIManager.event_handlers.Suspend()
            end
        end
    end
end

function EPad:powerOff()
    os.execute("poweroff")
end

function EPad:reboot()
    os.execute("reboot")
end

return EPad
