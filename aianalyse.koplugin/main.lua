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

        self.ui.highlight:addToHighlightDialog("91_aianalyse_plugin_with_book", function(highlight_module)
            return {
                text = _("✨ AI Analyse with Book ✨"),
                callback = function()
                    self:onAIAnalyseWithBook(highlight_module)
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
    self:retrieveAndShowAISummary(selected_text, book_name, book_authors, false)
end

function AIAnalyse:onAIAnalyseWithBook(highlight_module)
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
    self:retrieveAndShowAISummary(selected_text, book_name, book_authors, true)
end

function AIAnalyse:handleAIResponse(response_text, code, book_name, book_authors, with_book_context)
    if code ~= 200 then
        UIManager:show(InfoMessage:new({
            text = "HTTP Error: " .. tostring(code) .. "\n" .. tostring(response_text),
        }))
        return
    end

    local response_json = JSON.decode(response_text)
    if response_json and response_json.content and response_json.content[1] and response_json.content[1].text then
        local text_content = response_json.content[1].text
        UIManager:show(TextViewerHighlight:new({
            title = _(self.settings.api_provider .. " Explanation"),
            text = text_content,
            width = Device.screen:getWidth() * 0.9,
            height = Device.screen:getHeight() * 0.9,
            show_parent = self,
            highlight_text_selection = true,
            text_selection_callback = function(selection)
                self:retrieveAndShowAISummary(selection, book_name, book_authors, with_book_context)
            end,
        }))
        logger.info("Cached tokens used: ", response_json.usage.cache_read_input_tokens)
    else
        UIManager:show(InfoMessage:new({
            text = "Failed to parse response: " .. tostring(response_text),
        }))
    end
end

function AIAnalyse:retrieveAndShowAISummary(selected_text, book_name, book_authors, with_book_context)
    local loading_text = with_book_context and _("Analysing with book context... (this may take a while)")
        or _("Asking " .. self.settings.api_provider .. "...")
    local loading_popup = InfoMessage:new({ text = loading_text, timeout = 0 })
    UIManager:show(loading_popup)
    UIManager:forceRePaint()

    local model = self.settings.api_provider == "Anthropic" and "claude-sonnet-4-5" or "deepseek-chat"
    local url = self.settings.api_provider == "Anthropic" and "https://api.anthropic.com/v1/messages"
        or "https://api.deepseek.com/anthropic/v1/messages"

    local headers = {
        ["content-type"] = "application/json",
        ["x-api-key"] = self.settings.api_key,
        ["anthropic-version"] = "2023-06-01",
        -- prompt caching is supported by both deepseek and ahthropic, save tokens on future calls
        ["anthropic-beta"] = "prompt-caching-2024-07-31",
    }
    local template = [[
I am currently reading "%1" by %2.
I have highlighted the following text:
"%3"

Please explain the meaning and context of this specific highlighted text within the book in 200 words or less.]]
    local prompt = T(template, book_name, book_authors, selected_text)

    local payload
    if with_book_context then
        local book_content = self:getFullBookText()
        if not book_content then
            UIManager:close(loading_popup)
            UIManager:show(InfoMessage:new({ text = _("Could not get book content.") }))
            return
        end

        local prompt_text = template .. "You should use the text associated from the book provided as context."
        payload = {
            model = model,
            max_tokens = 1024,
            messages = {
                {
                    role = "user",
                    content = {
                        { type = "text", text = book_content, cache_control = { type = "ephemeral" } },
                        { type = "text", text = prompt_text },
                    },
                },
            },
        }
    else -- not with_book_context
        payload = {
            model = model,
            max_tokens = 1024,
            system = "You are a literary expert. The user will provide context about a book they are reading. Explain the specific text they highlighted. Do not treat the highlighted text as the title of the work.",
            messages = {
                { role = "user", content = prompt },
            },
        }
    end

    local body_str = JSON.encode(payload)
    headers["content-length"] = #body_str

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

    self:handleAIResponse(response_text, code, book_name, book_authors, with_book_context)
end

function AIAnalyse:getFullBookText()
    local doc = self.ui.document
    if not doc or not doc.getHTMLFromXPointer then
        logger.warn("AIAnalyse: Could not get document or getHTMLFromXPointer is not available.")
        return nil
    end

    local html_content = doc:getHTMLFromXPointer(".0", 0x4000)
    if not html_content then
        logger.warn("AIAnalyse: Failed to get HTML content from document.")
        return nil
    end

    -- Step 1: Replace block-level elements with newlines to preserve structure
    -- Replace </p> with double newlines for clear paragraph separation
    local text = html_content:gsub("</p>", "\n\n")
    -- Replace </div> with double newlines (adjust to single if less spacing is desired)
    text = text:gsub("</div>", "\n\n")
    -- Replace <br> and <br/> with a single newline
    text = text:gsub("<br%s*/?>", "\n")

    -- Step 2: Remove all remaining HTML tags (this will catch <img>, <span>, <strong>, <h1>, etc.)
    text = text:gsub("<[^>]+>", "")

    -- Step 3: Decode common HTML entities
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")
    text = text:gsub("&amp;", "&")
    text = text:gsub("&quot;", '"')
    text = text:gsub("&apos;", "'")
    text = text:gsub("&nbsp;", " ")

    logger.info("found text with size: ", #text) -- Log the size of the *stripped* text
    return text
end

function AIAnalyse:stopPlugin()
    if self.ui.highlight then
        self.ui.highlight:removeFromHighlightDialog("90_aianalyse_plugin")
        self.ui.highlight:removeFromHighlightDialog("91_aianalyse_plugin_with_book")
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
