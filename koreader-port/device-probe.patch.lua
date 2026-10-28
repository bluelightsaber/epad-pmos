    local epad_compat = io.open("/proc/device-tree/compatible")
    if epad_compat then
        local compat = epad_compat:read("*all") or ""
        epad_compat:close()
        if compat:find("eewrite,epad-pro", 1, true) then
            return require("device/epad/device")
        end
    end

