local TextViewer = require("ui/widget/textviewer")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")
local Device = require("device")

local TextViewerHighlight = TextViewer:extend()

-- It is useful to see what text has been highlighted, requires overriding TextViewer properties
function TextViewerHighlight:init()
    -- Call the original TextViewer init first
    TextViewer.init(self)

    -- 1. Fix the internal TextBoxWidget to enable highlighting
    if self.scroll_text_w and self.scroll_text_w.text_widget then
        self.scroll_text_w.text_widget.highlight_text_selection = true
    end

    -- 2. Correct the gesture mapping that is broken in the base TextViewer
    -- We need "hold_pan" to track movement, but base TextViewer uses "hold" for both.
    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()
    local range = Geom:new({ w = screen_w, h = screen_h })

    self.ges_events.HoldPanText = {
        GestureRange:new({
            ges = "hold_pan",
            range = range,
        }),
    }
end

-- 3. Correct the event handler to properly forward 'arg' (used for internal state)
function TextViewerHighlight:onHoldPanText(arg, ges)
    if self.movable._touch_pre_pan_was_inside then
        return self.movable:onMovableHoldPan(arg, ges)
    end
end

return TextViewerHighlight
