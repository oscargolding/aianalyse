--[[--
This is a debug plugin to test Plugin functionality.

@module koplugin.AIAnalyse
--]]
--

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")
local ffiUtil = require("ffi/util")
local T = ffiUtil.template
local JSON = require("rapidjson")
local TextViewerHighlight = require("textviewer_highlight")
local Device = require("device")
local http = require("socket.http")
local ltn12 = require("ltn12")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local RadioButtonTable = require("ui/widget/radiobuttontable")

local AIAnalyse = WidgetContainer:extend({
    name = "aianalyse",
    -- plugin is only enabled when you have a book open
    is_doc_only = true,
})

function AIAnalyse:init()
    -- Load settings or initialize defaults
    self.settings = G_reader_settings:readSetting("aianalyse_plugin")
    if not self.settings then
        self.settings = {
            api_provider = "DeepSeek",
            api_key = "",
        }
        self:saveSettings()
    end

    -- Always register the main menu so settings are accessible
    self.ui.menu:registerToMainMenu(self)

    -- Register highlight menu hooks
    if self.ui.highlight then
        self.ui.highlight:addToHighlightDialog("90_aianalyse_plugin", function(highlight_module)
            return {
                text = _("✨ AI Analyse ✨"),
                callback = function()
                    self:onAIAnalysePluginHighlight(highlight_module)
                end,
            }
        end)
    end
end

function AIAnalyse:saveSettings()
    G_reader_settings:saveSetting("aianalyse_plugin", self.settings)
end

function AIAnalyse:onAIAnalysePluginHighlight(highlight_module)
    local selected_text = highlight_module.selected_text.text
    local book_name = self.ui.doc_props.display_title
    local book_authors = self.ui.doc_props.authors or _("Unknown")

    if not self.settings.api_key or self.settings.api_key == "" then
        UIManager:show(InfoMessage:new({
            text = _("Please set your API key in the AI Analysis settings."),
        }))
        return
    end

    highlight_module:onClose()
    self:retrieveAndShowAISummary(selected_text, book_name, book_authors)
end

function AIAnalyse:retrieveAndShowAISummary(selected_text, book_name, book_authors)
    local loading_popup = InfoMessage:new({
        text = _("Asking " .. self.settings.api_provider .. "..."),
        timeout = 0,
    })
    UIManager:show(loading_popup)
    UIManager:forceRePaint()

    local template = [[
I am currently reading "%1" by %2.
I have highlighted the following text:
"%3"

Please explain the meaning and context of this specific highlighted text within the book in 200 words or less.]]
    local prompt = T(template, book_name, book_authors, selected_text)

    local model = "deepseek-chat"
    local url = "https://api.deepseek.com/anthropic/v1/messages"
    if self.settings.api_provider == "Anthropic" then
        model = "claude-sonnet-4-5"
        url = "https://api.anthropic.com/v1/messages"
    end

    local payload = {
        model = model,
        max_tokens = 1000,
        system = "You are a literary expert. The user will provide context about a book they are reading. Explain the specific text they highlighted. Do not treat the highlighted text as the title of the work.",
        messages = {
            {
                role = "user",
                content = prompt,
            },
        },
    }

    local body_str = JSON.encode(payload)
    local headers = {
        ["x-api-key"] = self.settings.api_key,
        ["anthropic-version"] = "2023-06-01",
        ["content-type"] = "application/json",
        ["content-length"] = #body_str,
    }
    local response_body = {}

    local _res, code = http.request({
        url = url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(body_str),
        sink = ltn12.sink.table(response_body),
    })

    UIManager:close(loading_popup)

    local response_text = table.concat(response_body)

    if code ~= 200 then
        UIManager:show(InfoMessage:new({
            text = "HTTP Error: " .. tostring(code) .. "\n" .. tostring(response_text),
        }))
        return
    end

    local body_json = JSON.decode(response_text)
    if body_json and body_json.content and body_json.content[1] and body_json.content[1].text then
        UIManager:show(TextViewerHighlight:new({
            title = _(self.settings.api_provider .. " Explanation"),
            text = body_json.content[1].text,
            width = Device.screen:getWidth() * 0.9,
            height = Device.screen:getHeight() * 0.9,
            show_parent = self,
            highlight_text_selection = true,
            text_selection_callback = function(selection)
                self:retrieveAndShowAISummary(selection, book_name, book_authors)
            end,
        }))
    else
        UIManager:show(InfoMessage:new({
            text = "Failed to parse response: " .. tostring(response_text),
        }))
    end
end

function AIAnalyse:stopPlugin()
    if self.ui.highlight then
        self.ui.highlight:removeFromHighlightDialog("90_aianalyse_plugin")
    end
end

function AIAnalyse:showSettings()
    local api_key_field = {
        text = self.settings.api_key or "",
        hint = _("Enter API Key"),
        description = _("API Key"),
    }

    local settings_dialog
    settings_dialog = MultiInputDialog:new({
        title = _("AI Analyse Settings"),
        fields = { api_key_field },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(settings_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local fields = settings_dialog:getFields()
                        self.settings.api_key = fields[1]
                        self:saveSettings()
                        UIManager:close(settings_dialog)
                    end,
                },
            },
        },
    })

    local provider_table = RadioButtonTable:new({
        width = settings_dialog:getAddedWidgetAvailableWidth(),
        radio_buttons = {
            {
                {
                    text = _("Anthropic"),
                    checked = (self.settings.api_provider == "Anthropic"),
                    provider = "Anthropic",
                },
            },
            {
                {
                    text = _("DeepSeek"),
                    checked = (self.settings.api_provider == "DeepSeek"),
                    provider = "DeepSeek",
                },
            },
        },
        button_select_callback = function(btn_entry)
            self.settings.api_provider = btn_entry.provider
            UIManager:setDirty(settings_dialog, "ui")
        end,
    })

    settings_dialog:addWidget(provider_table)
    UIManager:show(settings_dialog)
    settings_dialog:onShowKeyboard()
end

function AIAnalyse:addToMainMenu(menu_items)
    menu_items.hello_world = {
        text = _("✨ AI Analyse"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Settings"),
                callback = function()
                    self:showSettings()
                end,
            },
            {
                text = _("About"),
                callback = function()
                    UIManager:show(InfoMessage:new({
                        text = _(
                            "AI Analysis Plugin v1.0\n\nProvides AI-powered explanations for text selections using DeepSeek or Anthropic.\n\nSupports recursive lookups and selection highlighting."
                        ),
                    }))
                end,
            },
        },
    }
end

return AIAnalyse
