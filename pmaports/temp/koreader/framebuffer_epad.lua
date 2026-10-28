--[[--
Framebuffer for the E-PAD (MediaTek MT6797 + E Ink T1000 controller) on mainline Linux.

The image lives in a plain Linux framebuffer (simple-framebuffer, 32bpp BGRA). The T1000 controller reads it over
MIPI DSI and only repaints the panel when it receives a "set mode" command, which the eink-t1000 kernel driver
exposes as ioctl(0x61, waveform) on /dev/t1000. Updates are always full-screen: the controller works out which
pixels changed by itself, so the region passed by the frontend is ignored.
--]]

local ffi = require("ffi")
local bit = require("bit")
local C = ffi.C

require("ffi/posix_h")

ffi.cdef[[
int ioctl(int, unsigned long, ...);
]]

-- T1000 waveforms (eink-t1000.c)
local T1000_SET_MODE = 0x61
local WF_READING = 0x00 -- grayscale, little flashing: text pages
local WF_MIXED = 0x01 -- text + images
local WF_BROWSE = 0x02 -- fast, low quality: menus, scrolling, pen
local WF_GC = 0x11 -- full flashing clear

local framebuffer = {
    t1000_node = "/dev/t1000",
    t1000_fd = -1,
}

function framebuffer:init()
    self.t1000_fd = C.open(self.t1000_node, bit.bor(C.O_RDWR, C.O_CLOEXEC))
    if self.t1000_fd == -1 then
        self.debug("cannot open", self.t1000_node, "- the screen will not be refreshed")
    end
    framebuffer.parent.init(self)
end

function framebuffer:_t1000Refresh(waveform)
    if self.t1000_fd == -1 then
        return
    end
    -- Blocks until the controller has finished painting (HRDY), so there is nothing to wait for afterwards.
    if C.ioctl(self.t1000_fd, T1000_SET_MODE, ffi.cast("unsigned long", waveform)) < 0 then
        self.debug("T1000 refresh failed:", ffi.string(C.strerror(ffi.errno())))
    end
end

function framebuffer:refreshFullImp(x, y, w, h, dither)
    self:_t1000Refresh(WF_GC)
end

function framebuffer:refreshPartialImp(x, y, w, h, dither)
    self:_t1000Refresh(dither and WF_MIXED or WF_READING)
end

function framebuffer:refreshUIImp(x, y, w, h, dither)
    self:_t1000Refresh(dither and WF_MIXED or WF_READING)
end

function framebuffer:refreshFastImp(x, y, w, h, dither)
    self:_t1000Refresh(WF_BROWSE)
end

function framebuffer:refreshWaitForLastImp()
end

function framebuffer:close(reinit)
    if not reinit and self.t1000_fd ~= -1 then
        C.close(self.t1000_fd)
        self.t1000_fd = -1
    end
    framebuffer.parent.close(self, reinit)
end

return require("ffi/framebuffer_linux"):extend(framebuffer)
