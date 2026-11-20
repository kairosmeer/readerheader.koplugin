local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ReaderView = require("apps/reader/modules/readerview")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template
local NetworkMgr
local ok_network_mgr, network_mgr = pcall(require, "ui/network/manager")
if ok_network_mgr then
    NetworkMgr = network_mgr
end

local Screen = Device.screen
local unpack = unpack or table.unpack
local templateKeyForSlot
local tokenString
local boldKeyForSlot
local templateToTokenSet
local getTemplateTokens
local tokenSetToTemplate
local faceKeyForToken
local getSlotSegments
local ReaderHeader = WidgetContainer:extend{
    name = "readerheader",
    is_doc_only = true,
}

local DEFAULT_SETTINGS = {
    enabled = true,
    center_template = "{time}",
    left_template = "{title}",
    right_template = "{battery}",
    separator = "-",
    auto_update_time = true,
    font_face = "ffont",
    font_size = nil,
    font_bold = nil,
    top_padding = "small",
    book_text_padding = "none",
    use_book_margins = true,
    margin = "large",
    max_width_pct = 100,
    hide_wifi_disconnected = false,
}

local original_paintTo = ReaderView.paintTo
local patch_installed = false
local menu_patch_installed = false
local header_paint_error_logged = false
local refreshReader
local refreshHeader
local applyHeaderMargin

local TEMPLATE_TOKENS = {
    { key = "title", text = _("Title") },
    { key = "author", text = _("Author") },
    { key = "chapter", text = _("Chapter") },
    { key = "page", text = _("Page") },
    { key = "pages", text = _("Pages") },
    { key = "page_progress", text = _("Page progress") },
    { key = "percentage", text = _("Percentage") },
    { key = "chapter_progress", text = _("Chapter progress") },
    { key = "pages_left", text = _("Pages left in chapter") },
    { key = "pages_left_book", text = _("Pages left in book") },
    { key = "time", text = _("Time") },
    { key = "wifi", text = _("Wi-Fi") },
    { key = "battery", text = _("Battery") },
    { key = "separator", text = _("Separator") },
}

local SEPARATORS = {
    { text = _("None"), value = "" },
    { text = "-", value = "-" },
    { text = "|", value = "|" },
    { text = "·", value = "·" },
    { text = "•", value = "•" },
    { text = "/", value = "/" },
}

local FONT_SIZES = { 8, 10, 12, 14, 16, 18, 20, 22, 24, 28, 32 }
local WIFI_ICON = "\u{ECA8}"
local WIFI_OFF_ICON = "\u{ECA9}"

local LAYOUT_KEYS = {
    enabled = true,
    center_template = true,
    left_template = true,
    right_template = true,
    font_face = true,
    font_size = true,
    font_bold = true,
    top_padding = true,
    book_text_padding = true,
}

local function copyDefaults()
    local settings = {}
    for key, value in pairs(DEFAULT_SETTINGS) do
        settings[key] = value
    end
    return settings
end

local function getSettings()
    local settings = G_reader_settings:readSetting("reader_header") or {}
    for key, value in pairs(DEFAULT_SETTINGS) do
        if settings[key] == nil then
            settings[key] = value
        end
    end
    if not settings.slots_migrated then
        if settings.layout == "cornered" then
            settings.center_template = ""
            settings.left_template = settings.left_template ~= "" and settings.left_template or "{author}"
            settings.right_template = settings.right_template ~= "" and settings.right_template or "{title}"
        elseif settings.layout == "centered" then
            settings.center_template = settings.center_template ~= "" and settings.center_template or DEFAULT_SETTINGS.center_template
            settings.left_template = ""
            settings.right_template = ""
        end
        settings.layout = nil
        settings.slots_migrated = true
        G_reader_settings:saveSetting("reader_header", settings)
    end
    return settings
end

local function getEffectiveSettings()
    return getSettings()
end

local function saveSetting(key, value)
    local settings = getSettings()
    settings[key] = value
    G_reader_settings:saveSetting("reader_header", settings)
end

local function getFooterSettings()
    return G_reader_settings:readSetting("footer") or {}
end

local function getDefaultBold(settings)
    if settings.font_bold == nil then
        return getFooterSettings().text_font_bold or false
    end
    return settings.font_bold
end

local function getPadding(name)
    if name == "tiny" then
        return Size.padding.tiny
    elseif name == "default" then
        return Size.padding.default
    elseif name == "large" then
        return Size.padding.large
    end
    return Size.padding.small
end

local function getBookTextPadding(name)
    if name == "large" then
        return Screen:scaleBySize(24)
    end
    return 0
end

local function getMargin(name)
    if name == "tiny" then
        return Size.padding.tiny
    elseif name == "small" then
        return Size.padding.small
    elseif name == "default" then
        return Size.padding.default
    end
    return Size.padding.large
end

local function formatAuthor(authors)
    authors = authors or ""
    if authors:find("\n") then
        return T(_("%1 et al."), util.splitToArray(authors, "\n")[1] .. ",")
    end
    return authors
end

local function getWifiStatus(settings)
    if not NetworkMgr then
        return ""
    end
    local ok, is_wifi_on = pcall(function()
        if NetworkMgr.isWifiOn then
            return NetworkMgr:isWifiOn()
        elseif NetworkMgr.isOnline then
            return NetworkMgr:isOnline()
        end
        return nil
    end)
    if not ok or is_wifi_on == nil then
        return ""
    end
    if is_wifi_on then
        return WIFI_ICON
    end
    if settings.hide_wifi_disconnected then
        return ""
    end
    return WIFI_OFF_ICON
end

local function collectValues(view, settings)
    local book_title = ""
    local book_author = ""
    if view.ui.doc_props then
        book_title = view.ui.doc_props.display_title or ""
        book_author = formatAuthor(view.ui.doc_props.authors)
    end

    local pageno = view.state.page or 1
    local pages = view.ui.doc_settings.data.doc_pages or 1
    local pages_left_book = pages - pageno
    local percentage = (pageno / pages) * 100
    local book_chapter = ""
    local pages_chapter = 0
    local pages_left = 0
    local pages_done = 0

    if view.ui.toc then
        book_chapter = view.ui.toc:getTocTitleByPage(pageno) or ""
        pages_chapter = view.ui.toc:getChapterPageCount(pageno) or pages
        pages_left = view.ui.toc:getChapterPagesLeft(pageno) or view.ui.document:getTotalPagesLeft(pageno)
        pages_done = view.ui.toc:getChapterPagesDone(pageno) or 0
    end
    pages_done = pages_done + 1

    local battery = ""
    if Device:hasBattery() then
        local power_dev = Device:getPowerDevice()
        local batt_lvl = power_dev:getCapacity() or 0
        local is_charging = power_dev:isCharging() or false
        local batt_prefix = power_dev:getBatterySymbol(power_dev:isCharged(), is_charging, batt_lvl) or ""
        battery = batt_prefix .. batt_lvl .. "%"
    end

    return {
        title = book_title,
        author = book_author,
        chapter = book_chapter,
        page = tostring(pageno),
        pages = tostring(pages),
        page_progress = ("%d / %d"):format(pageno, pages),
        percentage = ("%.1f%%"):format(percentage),
        chapter_progress = pages_done .. " // " .. pages_chapter,
        pages_left = tostring(pages_left),
        pages_left_book = tostring(pages_left_book),
        time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) or "",
        wifi = getWifiStatus(settings),
        battery = battery,
        separator = settings.separator or "-",
    }
end

local function fitText(text, face, bold, max_width)
    if text == nil or text == "" or max_width <= 0 then
        return ""
    end
    local text_widget = TextWidget:new{
        text = text:gsub(" ", "\u{00A0}"),
        max_width = max_width,
        face = face,
        bold = bold,
        padding = 0,
    }
    local fitted_text, add_ellipsis = text_widget:getFittedText()
    text_widget:free()
    if add_ellipsis then
        fitted_text = fitted_text .. "..."
    end
    return BD.auto(fitted_text)
end

local function measureText(text, face, bold)
    if text == nil or text == "" then
        return 0
    end
    local text_widget = TextWidget:new{
        text = text:gsub(" ", "\u{00A0}"),
        face = face,
        bold = bold,
        padding = 0,
    }
    local width = text_widget:getSize().w
    text_widget:free()
    return width
end

local function hasHeaderContent(settings)
    return tostring(settings.left_template or "") ~= ""
        or tostring(settings.center_template or "") ~= ""
        or tostring(settings.right_template or "") ~= ""
end

local function templateUsesToken(template, token_key)
    for key in tostring(template or ""):gmatch("{([%w_]+)}") do
        if key == token_key then
            return true
        end
    end
    return false
end

local function settingsUseTime(settings)
    return templateUsesToken(settings.left_template, "time")
        or templateUsesToken(settings.center_template, "time")
        or templateUsesToken(settings.right_template, "time")
end

local function getSegmentHeight(segment, face, font_size)
    local segment_face = segment.face_key and Font:getFace(segment.face_key, font_size) or face
    local text_widget = TextWidget:new{
        text = (segment.text ~= "" and segment.text or "Hg"):gsub(" ", "\u{00A0}"),
        face = segment_face,
        bold = segment.bold,
        padding = 0,
    }
    local height = text_widget:getSize().h
    text_widget:free()
    return height
end

local function getHeaderReservedHeight(settings, view, base_top_margin)
    if not settings.enabled or not hasHeaderContent(settings) then
        return 0
    end
    local footer_settings = getFooterSettings()
    local font_size = settings.font_size or footer_settings.text_font_size or 14
    local face = Font:getFace(settings.font_face or "ffont", font_size)
    local default_bold = getDefaultBold(settings)
    local height = getSegmentHeight({ text = "Hg", bold = default_bold }, face, font_size)
    if view then
        local ok, values = pcall(collectValues, view, settings)
        if ok then
            for _, slot in ipairs({ "left", "center", "right" }) do
                for _, segment in ipairs(getSlotSegments(settings[templateKeyForSlot(slot)], values, settings, slot, default_bold)) do
                    height = math.max(height, getSegmentHeight(segment, face, font_size))
                end
            end
        end
    end
    local top_padding = getPadding(settings.top_padding)
    if settings.book_text_padding == "none" then
        return math.max(0, height + top_padding - (base_top_margin or 0))
    end
    return height + top_padding + getBookTextPadding(settings.book_text_padding)
end

local function getActiveHeaderReservedHeight(view, base_top_margin)
    if not view or view.render_mode ~= nil then
        return 0
    end
    return getHeaderReservedHeight(getEffectiveSettings(), view, base_top_margin)
end

local function getSlotBoldSet(settings, slot)
    local template = settings[boldKeyForSlot(slot)]
    if template == nil then
        return nil
    end
    return templateToTokenSet(template)
end

local function isSlotTokenBold(settings, slot, token_key, default_bold)
    local bold_set = getSlotBoldSet(settings, slot)
    if bold_set == nil then
        return default_bold
    end
    return bold_set[token_key] == true
end

getSlotSegments = function(template, values, settings, slot, default_bold)
    local segments = {}
    for _, key in ipairs(getTemplateTokens(template)) do
        local text = values[key] or ""
        if text ~= "" then
            if #segments > 0 then
                table.insert(segments, { text = " ", bold = default_bold })
            end
            table.insert(segments, {
                text = text,
                bold = isSlotTokenBold(settings, slot, key, default_bold),
                face_key = faceKeyForToken(key),
            })
        end
    end
    return segments
end

local function measureSegments(segments, face, font_size)
    local width = 0
    for _, segment in ipairs(segments) do
        local segment_face = segment.face_key and Font:getFace(segment.face_key, font_size) or face
        segment.width = measureText(segment.text, segment_face, segment.bold)
        width = width + segment.width
    end
    return width
end

local function copySegments(segments)
    local copied = {}
    for _, segment in ipairs(segments) do
        table.insert(copied, {
            text = segment.text,
            bold = segment.bold,
            width = segment.width,
            face_key = segment.face_key,
        })
    end
    return copied
end

local function fitSegments(segments, face, font_size, max_width)
    if max_width <= 0 then
        return {}
    end
    local fitted = copySegments(segments)
    local width = measureSegments(fitted, face, font_size)
    local loops = 0
    while width > max_width and loops < (#fitted * 3) do
        loops = loops + 1
        local widest_index
        local widest_width = 0
        for index, segment in ipairs(fitted) do
            if segment.text ~= " " and segment.width > widest_width then
                widest_index = index
                widest_width = segment.width
            end
        end
        if not widest_index then break end
        local segment = fitted[widest_index]
        local segment_face = segment.face_key and Font:getFace(segment.face_key, font_size) or face
        local target_width = math.max(0, segment.width - (width - max_width) - measureText("...", segment_face, segment.bold))
        if target_width <= 0 then
            segment.text = ""
            segment.width = 0
        else
            segment.text = fitText(segment.text, segment_face, segment.bold, target_width)
            segment.width = measureText(segment.text, segment_face, segment.bold)
        end
        width = measureSegments(fitted, face, font_size)
    end
    while width > max_width do
        local widest_index
        local widest_width = 0
        for index, segment in ipairs(fitted) do
            if segment.width > widest_width then
                widest_index = index
                widest_width = segment.width
            end
        end
        if not widest_index then break end
        fitted[widest_index].text = ""
        fitted[widest_index].width = 0
        width = measureSegments(fitted, face, font_size)
    end
    return fitted
end

local function getContentWidth(view, settings)
    local fallback_margin = getMargin(settings.margin)
    local left_margin = fallback_margin
    local right_margin = fallback_margin
    if settings.use_book_margins then
        local margins = view.document:getPageMargins()
        left_margin = margins.left or fallback_margin
        right_margin = margins.right or fallback_margin
    end
    local screen_width = Screen:getWidth()
    local content_width = math.max(0, screen_width - left_margin - right_margin)
    return content_width, left_margin, right_margin
end

local function newHeaderTextWidget(text, face, bold, fgcolor)
    return TextWidget:new{
        text = text:gsub(" ", "\u{00A0}"),
        face = face,
        bold = bold,
        fgcolor = fgcolor,
        padding = 0,
    }
end

local function newHeaderSlotWidget(segments, face, font_size, fgcolor, max_width)
    local widgets = {}
    for _, segment in ipairs(fitSegments(segments, face, font_size, max_width)) do
        if segment.text ~= "" then
            local segment_face = segment.face_key and Font:getFace(segment.face_key, font_size) or face
            table.insert(widgets, newHeaderTextWidget(segment.text, segment_face, segment.bold, fgcolor))
        end
    end
    if #widgets == 0 then
        return nil
    end
    return HorizontalGroup:new(widgets)
end

local function paintSlotHeader(view, bb, x, y, settings, face, font_size, default_bold, fgcolor, top_padding, values)
    local avail_width, left_margin, right_margin = getContentWidth(view, settings)
    if avail_width <= 0 then
        return
    end
    local left_segments = getSlotSegments(settings.left_template, values, settings, "left", default_bold)
    local center_segments = getSlotSegments(settings.center_template, values, settings, "center", default_bold)
    local right_segments = getSlotSegments(settings.right_template, values, settings, "right", default_bold)
    local left_width = measureSegments(left_segments, face, font_size)
    local center_width = measureSegments(center_segments, face, font_size)
    local right_width = measureSegments(right_segments, face, font_size)
    local has_left = left_width > 0
    local has_center = center_width > 0
    local has_right = right_width > 0

    if not has_left and not has_center and not has_right then
        return
    end

    local left_max_width = left_width
    local right_max_width = right_width
    local center_max_width = math.min(center_width, avail_width * settings.max_width_pct / 100)

    if has_center then
        local center_x = math.floor((avail_width - center_max_width) / 2)
        left_max_width = math.min(left_width, math.max(0, center_x))
        right_max_width = math.min(right_width, math.max(0, avail_width - center_x - center_max_width))
    elseif has_left or has_right then
        if left_width + right_width > avail_width then
            local half_width = math.floor(avail_width / 2)
            left_max_width = math.min(left_width, math.max(0, avail_width - math.min(right_width, half_width)))
            right_max_width = math.min(right_width, math.max(0, avail_width - left_max_width))
        end
    end

    local left_widget = has_left and left_max_width > 0 and newHeaderSlotWidget(left_segments, face, font_size, fgcolor, left_max_width) or nil
    local center_widget = has_center and center_max_width > 0 and newHeaderSlotWidget(center_segments, face, font_size, fgcolor, center_max_width) or nil
    local right_widget = has_right and right_max_width > 0 and newHeaderSlotWidget(right_segments, face, font_size, fgcolor, right_max_width) or nil
    if not left_widget and not center_widget and not right_widget then
        return
    end
    local height = top_padding

    if left_widget then height = math.max(height, left_widget:getSize().h + top_padding) end
    if center_widget then height = math.max(height, center_widget:getSize().h + top_padding) end
    if right_widget then height = math.max(height, right_widget:getSize().h + top_padding) end

    local content_dimen = Geom:new{ w = avail_width, h = height - top_padding }
    local layers = {}
    if left_widget then
        table.insert(layers, LeftContainer:new{ dimen = content_dimen, left_widget })
    end
    if center_widget then
        table.insert(layers, CenterContainer:new{ dimen = content_dimen, center_widget })
    end
    if right_widget then
        table.insert(layers, RightContainer:new{ dimen = content_dimen, right_widget })
    end

    local header = CenterContainer:new{
        dimen = Geom:new{ w = Screen:getWidth(), h = height },
        VerticalGroup:new{
            VerticalSpan:new{ width = top_padding },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = left_margin },
                OverlapGroup:new{ dimen = content_dimen, unpack(layers) },
                HorizontalSpan:new{ width = right_margin },
            },
        },
    }
    header:paintTo(bb, x, y)
end

local function paintHeader(view, bb, x, y)
    if view.render_mode ~= nil then return end
    if bb ~= Screen.bb then return end

    local settings = getEffectiveSettings()
    if not settings.enabled then return end

    local footer_settings = getFooterSettings()
    local font_size = settings.font_size or footer_settings.text_font_size or 14
    local bold = getDefaultBold(settings)

    local face = Font:getFace(settings.font_face or "ffont", font_size)
    local fgcolor = Blitbuffer.COLOR_BLACK
    local top_padding = getPadding(settings.top_padding)
    local values = collectValues(view, settings)

    paintSlotHeader(view, bb, x, y, settings, face, font_size, bold, fgcolor, top_padding, values)
end

local function installPaintPatch()
    if patch_installed then return end
    ReaderView.paintTo = function(self, bb, x, y)
        original_paintTo(self, bb, x, y)
        local ok, err = pcall(paintHeader, self, bb, x, y)
        if ok then
            header_paint_error_logged = false
        elseif not header_paint_error_logged then
            header_paint_error_logged = true
            logger.warn("ReaderHeader: failed to paint header:", err)
        end
    end
    patch_installed = true
end

local function appendHeaderMenu(menu_items, plugin)
    if not menu_items.status_bar then
        menu_items.status_bar = {
            text = _("Status bar"),
            sub_item_table = {},
        }
    end

    local sub_items = menu_items.status_bar.sub_item_table or {}
    menu_items.status_bar.sub_item_table = sub_items

    for index, item in ipairs(sub_items) do
        if item.reader_header_settings then
            table.remove(sub_items, index)
            break
        end
    end

    local insert_index = #sub_items + 1
    for index, item in ipairs(sub_items) do
        if item.text == _("Alt status bar") then
            insert_index = index + 1
            break
        end
    end
    table.insert(sub_items, insert_index, plugin:getHeaderMenuTable())
end

local function installStatusBarMenuPatch(plugin)
    if menu_patch_installed then return end

    local ok, ReaderFooter = pcall(require, "apps/reader/modules/readerfooter")
    if not ok or not ReaderFooter or not ReaderFooter.addToMainMenu then
        return
    end

    local original_addToMainMenu = ReaderFooter.addToMainMenu
    ReaderFooter.addToMainMenu = function(footer, menu_items)
        original_addToMainMenu(footer, menu_items)
        appendHeaderMenu(menu_items, plugin)
    end
    menu_patch_installed = true
end

applyHeaderMargin = function(ui, margins)
    if not ui or not ui.view or not ui.document or not ui.typeset then
        return false
    end
    local base_top_margin = Screen:scaleBySize(margins[2])
    local ok_height, header_height = pcall(getActiveHeaderReservedHeight, ui.view, base_top_margin)
    if not ok_height then
        logger.warn("ReaderHeader: failed to calculate header margin:", header_height)
        return false
    end
    if header_height <= 0 then
        return false
    end

    local left = Screen:scaleBySize(margins[1])
    local top = Screen:scaleBySize(margins[2]) + header_height
    local right = Screen:scaleBySize(margins[3])
    local bottom
    if ui.view.footer.reclaim_height then
        bottom = Screen:scaleBySize(margins[4])
    else
        bottom = Screen:scaleBySize(margins[4]) + ui.view.footer:getHeight()
    end
    ui.document:setPageMargins(left, top, right, bottom)
    return true
end

local function refreshReaderLayout(ui, update_margins)
    if not ui then
        refreshReader()
        return
    end
    if update_margins and ui.typeset and ui.typeset.unscaled_margins then
        if applyHeaderMargin(ui, ui.typeset.unscaled_margins) then
            ui:handleEvent(Event:new("UpdatePos"))
        else
            ui:handleEvent(Event:new("SetPageMargins", ui.typeset.unscaled_margins))
        end
    else
        refreshReader()
    end
end

refreshReader = function()
    UIManager:setDirty(nil, "ui")
end

refreshHeader = function(ui)
    if not ui or not ui.view then
        refreshReader()
        return
    end

    local reader_dialog = ui.view.dialog or ui.dialog
    if not reader_dialog then
        refreshReader()
        return
    end

    local settings = getEffectiveSettings()
    if not settings.enabled or not hasHeaderContent(settings) then
        return
    end

    local ok_height, header_height = pcall(getHeaderReservedHeight, settings, ui.view, 0)
    if not ok_height then
        logger.warn("ReaderHeader: failed to calculate header refresh region:", header_height)
        refreshReader()
        return
    end
    if header_height <= 0 then
        return
    end

    UIManager:setDirty(reader_dialog, "ui", Geom:new{
        x = 0,
        y = 0,
        w = Screen:getWidth(),
        h = header_height,
    })
end

templateKeyForSlot = function(slot)
    return slot .. "_template"
end

tokenString = function(token_key)
    return "{" .. token_key .. "}"
end

boldKeyForSlot = function(slot)
    return slot .. "_bold_template"
end

templateToTokenSet = function(template)
    local set = {}
    for key in tostring(template or ""):gmatch("{([%w_]+)}") do
        set[key] = true
    end
    return set
end

getTemplateTokens = function(template)
    local used = {}
    local tokens = {}
    for key in tostring(template or ""):gmatch("{([%w_]+)}") do
        if not used[key] then
            table.insert(tokens, key)
            used[key] = true
        end
    end
    return tokens
end

tokenSetToTemplate = function(set, order_template)
    local parts = {}
    local added = {}
    for _, key in ipairs(getTemplateTokens(order_template)) do
        if set[key] then
            table.insert(parts, tokenString(key))
            added[key] = true
        end
    end
    for _, token in ipairs(TEMPLATE_TOKENS) do
        if set[token.key] and not added[token.key] then
            table.insert(parts, tokenString(token.key))
        end
    end
    return table.concat(parts, " ")
end

faceKeyForToken = function(token_key)
    if token_key == "wifi" then
        return "infofont"
    end
end

local function updateTokenItemText(item)
    item.text = item.label
    if item.bold_set and item.bold_set[item.key] then
        item.text = T(_("%1 (bold)"), item.text)
    end
    item.text = item.text .. " ▶"
end

local function toggleBoldItem(item, refresh_callback)
    item.bold_set[item.key] = not item.bold_set[item.key]
    updateTokenItemText(item)
    if refresh_callback then refresh_callback() end
end

local function newTokenItem(token, checked, bold_set)
    local entry = {
        label = token.text,
        key = token.key,
        checked = checked,
        dim = not checked,
        bold_set = bold_set,
    }
    updateTokenItemText(entry)
    entry.checked_func = function()
        return entry.checked
    end
    entry.callback = function(item)
        item.checked = not item.checked
        item.dim = not item.checked
    end
    entry.hold_callback = function(item, refresh_callback)
        toggleBoldItem(item, refresh_callback)
    end
    return entry
end

local function templateToTokenItems(template, bold_set)
    local used = {}
    local items = {}
    local known = {}

    for _, token in ipairs(TEMPLATE_TOKENS) do
        known[token.key] = token
    end

    for key in tostring(template or ""):gmatch("{([%w_]+)}") do
        if known[key] and not used[key] then
            table.insert(items, newTokenItem(known[key], true, bold_set))
            used[key] = true
        end
    end

    local selected = templateToTokenSet(template)
    for _, token in ipairs(TEMPLATE_TOKENS) do
        if not used[token.key] then
            table.insert(items, newTokenItem(token, selected[token.key] == true, bold_set))
        end
    end

    return items
end

local function tokenItemsToTemplate(items)
    local parts = {}
    for _, item in ipairs(items) do
        if item.checked then
            table.insert(parts, tokenString(item.key))
        end
    end
    return table.concat(parts, " ")
end

local function getInitialSlotBoldSet(settings, slot)
    local bold_set = getSlotBoldSet(settings, slot)
    if bold_set ~= nil then
        return bold_set
    end
    bold_set = {}
    if getDefaultBold(settings) then
        for _, key in ipairs(getTemplateTokens(settings[templateKeyForSlot(slot)])) do
            bold_set[key] = true
        end
    end
    return bold_set
end

local function getSeparatorMenu(plugin)
    local items = {}
    for _, separator in ipairs(SEPARATORS) do
        table.insert(items, {
            text = separator.text,
            checked_func = function()
                return getSettings().separator == separator.value
            end,
            callback = function(touchmenu_instance)
                plugin:saveAndRefresh("separator", separator.value, touchmenu_instance)
            end,
        })
    end
    return items
end

local function getFontSizeMenu(plugin)
    local items = {}
    for _, size in ipairs(FONT_SIZES) do
        table.insert(items, {
            text = tostring(size),
            checked_func = function()
                return (getSettings().font_size or getFooterSettings().text_font_size or 14) == size
            end,
            callback = function(touchmenu_instance)
                plugin:saveAndRefresh("font_size", size, touchmenu_instance)
            end,
        })
    end
    return items
end

function ReaderHeader:shouldAutoUpdateTime()
    local settings = getEffectiveSettings()
    return settings.enabled and settings.auto_update_time and settingsUseTime(settings)
        and self.ui and self.ui.view and self.ui.view.render_mode == nil
end

function ReaderHeader:unscheduleTimeRefresh()
    if self._time_refresh_callback then
        UIManager:unschedule(self._time_refresh_callback)
        self._time_refresh_callback = nil
    end
end

function ReaderHeader:scheduleTimeRefresh()
    self:unscheduleTimeRefresh()
    if not self:shouldAutoUpdateTime() then
        return
    end

    self._time_refresh_callback = function()
        self._time_refresh_callback = nil
        if self:shouldAutoUpdateTime() then
            refreshHeader(self.ui)
            self:scheduleTimeRefresh()
        end
    end
    UIManager:scheduleIn(60 - (os.time() % 60), self._time_refresh_callback)
end

function ReaderHeader:init()
    installPaintPatch()
    installStatusBarMenuPatch(self)
    if self.ui and self.ui.menu and not self._menu_registered then
        self.ui.menu:registerToMainMenu(self)
        self._menu_registered = true
    end
    self:scheduleTimeRefresh()
end

function ReaderHeader:onReaderReady()
    installPaintPatch()
    installStatusBarMenuPatch(self)
    if self.ui and self.ui.menu and not self._menu_registered then
        self.ui.menu:registerToMainMenu(self)
        self._menu_registered = true
    end
    self:scheduleTimeRefresh()
end

function ReaderHeader:configureSlotItems(title, slot, touchmenu_instance)
    local key = templateKeyForSlot(slot)
    local bold_key = boldKeyForSlot(slot)
    local settings = getSettings()
    local bold_set = getInitialSlotBoldSet(settings, slot)
    local item_table = templateToTokenItems(settings[key], bold_set)
    local SortWidget = require("ui/widget/sortwidget")
    local sort_widget
    sort_widget = SortWidget:new{
        title = title,
        item_table = item_table,
        callback = function()
            local template = tokenItemsToTemplate(item_table)
            saveSetting(key, template)
            saveSetting(bold_key, tokenSetToTemplate(bold_set, template))
            refreshReaderLayout(self.ui, true)
            self:scheduleTimeRefresh()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
    UIManager:show(sort_widget)
end

function ReaderHeader:resetSettings()
    local confirm_box
    confirm_box = ConfirmBox:new{
        text = _("Reset reader header settings to defaults?"),
        ok_text = _("Reset"),
        ok_callback = function()
            G_reader_settings:saveSetting("reader_header", copyDefaults())
            refreshReaderLayout(self.ui, true)
            self:scheduleTimeRefresh()
        end,
    }
    UIManager:show(confirm_box)
end

function ReaderHeader:saveAndRefresh(key, value, touchmenu_instance)
    saveSetting(key, value)
    refreshReaderLayout(self.ui, LAYOUT_KEYS[key] == true)
    self:scheduleTimeRefresh()
    if touchmenu_instance then touchmenu_instance:updateItems() end
end

function ReaderHeader:free(full)
    self:unscheduleTimeRefresh()
    WidgetContainer.free(self, full)
end

function ReaderHeader:onPreRenderDocument()
    if self.ui and self.ui.typeset and self.ui.typeset.unscaled_margins then
        applyHeaderMargin(self.ui, self.ui.typeset.unscaled_margins)
    end
end

function ReaderHeader:onSetPageMargins(margins)
    if self._applying_header_margin then
        return
    end
    if not self.ui or not self.ui.document or not self.ui.typeset or not self.ui.typeset.unscaled_margins then
        return
    end
    if margins ~= self.ui.typeset.unscaled_margins then
        return
    end

    self._applying_header_margin = true
    local ok_margin, err = pcall(applyHeaderMargin, self.ui, margins)
    self._applying_header_margin = false
    if not ok_margin then
        logger.warn("ReaderHeader: failed to apply header margin:", err)
    end
end

function ReaderHeader:getHeaderMenuTable()
    return {
        reader_header_settings = true,
        text = _("Header"),
        sub_item_table = {
            {
                text = _("Enable header"),
                checked_func = function()
                    return getSettings().enabled
                end,
                callback = function(touchmenu_instance)
                    self:saveAndRefresh("enabled", not getSettings().enabled, touchmenu_instance)
                end,
            },
            {
                text = _("Center items"),
                help_text = _("Tap a checkmark to show or hide an item. Tap an item row to select it, then use the move buttons to change its order. Long-press an item to toggle bold."),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:configureSlotItems(_("Center items"), "center", touchmenu_instance)
                end,
            },
            {
                text = _("Left items"),
                help_text = _("Tap a checkmark to show or hide an item. Tap an item row to select it, then use the move buttons to change its order. Long-press an item to toggle bold."),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:configureSlotItems(_("Left items"), "left", touchmenu_instance)
                end,
            },
            {
                text = _("Right items"),
                help_text = _("Tap a checkmark to show or hide an item. Tap an item row to select it, then use the move buttons to change its order. Long-press an item to toggle bold."),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    self:configureSlotItems(_("Right items"), "right", touchmenu_instance)
                end,
            },
            {
                text_func = function()
                    local separator = getSettings().separator
                    if separator == "" then separator = _("None") end
                    return T(_("Separator: %1"), separator)
                end,
                sub_item_table = getSeparatorMenu(self),
            },
            {
                text_func = function()
                    local settings = getSettings()
                    return T(_("Font size: %1"), settings.font_size or getFooterSettings().text_font_size or 14)
                end,
                sub_item_table = getFontSizeMenu(self),
            },
            {
                text = _("Bold by default"),
                checked_func = function()
                    return getDefaultBold(getSettings())
                end,
                callback = function(touchmenu_instance)
                    local settings = getSettings()
                    self:saveAndRefresh("font_bold", not getDefaultBold(settings), touchmenu_instance)
                end,
            },
            {
                text = _("Hide Wi-Fi when disconnected"),
                checked_func = function()
                    return getSettings().hide_wifi_disconnected
                end,
                callback = function(touchmenu_instance)
                    self:saveAndRefresh("hide_wifi_disconnected", not getSettings().hide_wifi_disconnected, touchmenu_instance)
                end,
            },
            {
                text = _("Auto-update time"),
                checked_func = function()
                    return getSettings().auto_update_time
                end,
                callback = function(touchmenu_instance)
                    self:saveAndRefresh("auto_update_time", not getSettings().auto_update_time, touchmenu_instance)
                end,
            },
            {
                text = _("Top padding"),
                sub_item_table = {
                    { text = _("Tiny"), checked_func = function() return getSettings().top_padding == "tiny" end, callback = function(touchmenu_instance) self:saveAndRefresh("top_padding", "tiny", touchmenu_instance) end },
                    { text = _("Small"), checked_func = function() return getSettings().top_padding == "small" end, callback = function(touchmenu_instance) self:saveAndRefresh("top_padding", "small", touchmenu_instance) end },
                    { text = _("Default"), checked_func = function() return getSettings().top_padding == "default" end, callback = function(touchmenu_instance) self:saveAndRefresh("top_padding", "default", touchmenu_instance) end },
                    { text = _("Large"), checked_func = function() return getSettings().top_padding == "large" end, callback = function(touchmenu_instance) self:saveAndRefresh("top_padding", "large", touchmenu_instance) end },
                },
            },
            {
                text = _("Book text padding"),
                help_text = _("Extra space between the header and the book text."),
                sub_item_table = {
                    { text = _("None"), checked_func = function() return getSettings().book_text_padding == "none" end, callback = function(touchmenu_instance) self:saveAndRefresh("book_text_padding", "none", touchmenu_instance) end },
                    { text = _("Default"), checked_func = function() return getSettings().book_text_padding == "default" end, callback = function(touchmenu_instance) self:saveAndRefresh("book_text_padding", "default", touchmenu_instance) end },
                    { text = _("Large"), checked_func = function() return getSettings().book_text_padding == "large" end, callback = function(touchmenu_instance) self:saveAndRefresh("book_text_padding", "large", touchmenu_instance) end },
                },
            },
            {
                text = _("Use book margins"),
                checked_func = function()
                    return getSettings().use_book_margins
                end,
                callback = function(touchmenu_instance)
                    self:saveAndRefresh("use_book_margins", not getSettings().use_book_margins, touchmenu_instance)
                end,
            },
            {
                text = _("Fixed margin"),
                sub_item_table = {
                    { text = _("Tiny"), checked_func = function() return getSettings().margin == "tiny" end, callback = function(touchmenu_instance) self:saveAndRefresh("margin", "tiny", touchmenu_instance) end },
                    { text = _("Small"), checked_func = function() return getSettings().margin == "small" end, callback = function(touchmenu_instance) self:saveAndRefresh("margin", "small", touchmenu_instance) end },
                    { text = _("Default"), checked_func = function() return getSettings().margin == "default" end, callback = function(touchmenu_instance) self:saveAndRefresh("margin", "default", touchmenu_instance) end },
                    { text = _("Large"), checked_func = function() return getSettings().margin == "large" end, callback = function(touchmenu_instance) self:saveAndRefresh("margin", "large", touchmenu_instance) end },
                },
            },
            {
                text = _("Reset defaults"),
                callback = function()
                    self:resetSettings()
                end,
            },
        },
    }
end

function ReaderHeader:addToMainMenu(menu_items)
    appendHeaderMenu(menu_items, self)
end

return ReaderHeader
