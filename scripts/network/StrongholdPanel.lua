-- ============================================================================
-- StrongholdPanel.lua — 据点交互面板模块
-- ============================================================================
-- 功能：当玩家靠近据点时显示交互面板（据点信息 + 占领/攻击/防守按钮）
-- 依赖：urhox-libs/UI, Settings
-- 接口：
--   StrongholdPanel.Show(spId, context)  — 显示面板
--   StrongholdPanel.Hide()               — 隐藏面板
--   StrongholdPanel.IsVisible()          — 是否可见
--   StrongholdPanel.GetRoot()            — 获取 UI 根节点（挂到主 UI 树）
--   StrongholdPanel.OnResponse(msg)      — 收到服务端响应时更新提示
-- ============================================================================

local UI = require("urhox-libs/UI")
local Settings = require("config.Settings")

---@class StrongholdPanel
local StrongholdPanel = {}

-- ============================================================================
-- 内部状态
-- ============================================================================
local state_ = {
    visible     = false,
    spId        = nil,     -- 当前据点 ID
    spDef       = nil,     -- 据点定义 { id, name, bonus_type, bonus_value, desc }
    ownerGuild  = nil,     -- 占据帮会名（nil=无主）
    ownerGuildId= nil,
    myGuildId   = nil,     -- 自己帮会 ID
    myGuildName = nil,     -- 自己帮会名
    layer       = nil,     -- 当前层
    -- UI 引用
    root        = nil,
    titleLabel  = nil,
    bonusLabel  = nil,
    ownerLabel  = nil,
    statusLabel = nil,
    actionBtn1  = nil,
    actionBtn2  = nil,
    msgLabel    = nil,
    -- 回调
    onAttack    = nil, -- function(spId)
    onDefend    = nil, -- function(spId)
    onSwitch    = nil, -- function(spId, existSpName) 更换据点确认
    onClose     = nil, -- function()
    -- 内部状态
    isSwitch    = false, -- 当前是否处于"更换据点"模式
}

-- ============================================================================
-- 配色主题
-- ============================================================================
local COLORS = {
    panelBg     = { 10, 12, 28, 240 },
    border      = { 80, 120, 60, 220 },
    titleText   = { 255, 220, 80, 255 },
    normalText  = { 200, 200, 210, 255 },
    bonusText   = { 120, 220, 160, 255 },
    ownerEmpty  = { 180, 160, 100, 255 },
    ownerEnemy  = { 220, 80, 80, 255 },
    ownerMine   = { 80, 200, 120, 255 },
    btnAttack   = { 180, 60, 40, 255 },
    btnDefend   = { 40, 120, 180, 255 },
    btnOccupy   = { 160, 140, 40, 255 },
    msgText     = { 255, 200, 100, 255 },
}

-- ============================================================================
-- 初始化：构建一次性 UI 树
-- ============================================================================
function StrongholdPanel.Init(callbacks)
    callbacks = callbacks or {}
    state_.onAttack = callbacks.onAttack
    state_.onDefend = callbacks.onDefend
    state_.onSwitch = callbacks.onSwitch
    state_.onClose  = callbacks.onClose

    -- 标题
    state_.titleLabel = UI.Label {
        text = "", fontSize = 16, fontWeight = "bold",
        color = COLORS.titleText,
        textAlign = "center",
        width = "100%",
        marginBottom = 4,
    }
    -- 加成描述
    state_.bonusLabel = UI.Label {
        text = "", fontSize = 12,
        color = COLORS.bonusText,
        textAlign = "center",
        width = "100%",
        marginBottom = 6,
    }
    -- 归属信息
    state_.ownerLabel = UI.Label {
        text = "", fontSize = 12,
        color = COLORS.normalText,
        textAlign = "center",
        width = "100%",
        marginBottom = 8,
    }
    -- 操作按钮1（攻击/占领）
    state_.actionBtn1 = UI.Button {
        text = "攻击", variant = "primary",
        width = "100%", height = 32,
        fontSize = 13, fontWeight = "bold",
        marginBottom = 4,
        backgroundColor = COLORS.btnAttack,
        onClick = function()
            if state_.isSwitch and state_.onSwitch and state_.spId then
                state_.onSwitch(state_.spId, state_.myGuildOwnedSpName)
            elseif state_.onAttack and state_.spId then
                state_.onAttack(state_.spId)
            end
        end,
    }
    -- 操作按钮2（防守/关闭）
    state_.actionBtn2 = UI.Button {
        text = "防守", variant = "secondary",
        width = "100%", height = 32,
        fontSize = 13,
        marginBottom = 4,
        backgroundColor = COLORS.btnDefend,
        onClick = function()
            if state_.onDefend and state_.spId then
                state_.onDefend(state_.spId)
            end
        end,
    }
    -- 消息提示
    state_.msgLabel = UI.Label {
        text = "", fontSize = 11,
        color = COLORS.msgText,
        textAlign = "center",
        width = "100%",
        marginTop = 4,
    }
    -- 关闭按钮
    local closeBtn = UI.Button {
        text = "×", variant = "text",
        width = 24, height = 24,
        fontSize = 16, fontWeight = "bold",
        color = { 200, 200, 200, 200 },
        position = "absolute",
        top = 2, right = 2,
        onClick = function()
            StrongholdPanel.Hide()
            if state_.onClose then state_.onClose() end
        end,
    }
    -- 状态文字（如"占领中…"）
    state_.statusLabel = UI.Label {
        text = "", fontSize = 11,
        color = { 200, 180, 80, 200 },
        textAlign = "center",
        width = "100%",
    }

    -- 根容器
    state_.root = UI.Panel {
        position = "absolute",
        bottom = 60,
        left = "50%",
        translateX = -110,  -- 等效 -50% of 220px (字符串 translateX 会导致 hit-test 崩溃)
        width = 220,
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 10,
        paddingBottom = 10,
        paddingLeft = 12,
        paddingRight = 12,
        backgroundColor = COLORS.panelBg,
        borderWidth = 2,
        borderColor = COLORS.border,
        borderRadius = 8,
        visible = false,  -- 初始隐藏（用 visible 而非 display，确保 SetVisible 能正常切换）
        children = {
            closeBtn,
            state_.titleLabel,
            state_.bonusLabel,
            state_.ownerLabel,
            state_.actionBtn1,
            state_.actionBtn2,
            state_.statusLabel,
            state_.msgLabel,
        },
    }

    return state_.root
end

-- ============================================================================
-- 显示面板
-- ============================================================================
---@param spId string 据点 ID
---@param context table { layer, ownerGuild, ownerGuildId, myGuildId, myGuildName }
function StrongholdPanel.Show(spId, context)
    print("[StrongholdPanel] Show called, spId=" .. tostring(spId) .. " root=" .. tostring(state_.root))
    if not state_.root then print("[StrongholdPanel] ⚠️ root is nil, return!"); return end

    context = context or {}
    state_.spId = spId
    state_.layer = context.layer
    state_.ownerGuild = context.ownerGuild or ""
    state_.ownerGuildId = context.ownerGuildId or ""
    state_.myGuildId = context.myGuildId or ""
    state_.myGuildName = context.myGuildName or ""
    state_.myGuildOwnedSpName = context.myGuildOwnedSpName or nil  -- 帮会已有其他据点名

    -- 查找据点定义
    local spDefs = Settings.STRONGPOINTS_BY_LAYER[state_.layer]
    state_.spDef = nil
    if spDefs then
        for _, sp in ipairs(spDefs) do
            if sp.id == spId then state_.spDef = sp; break end
        end
    end

    -- 标题
    local spName = state_.spDef and state_.spDef.name or spId
    state_.titleLabel:SetText("◆ " .. spName)

    -- 加成描述
    if state_.spDef and state_.spDef.desc then
        state_.bonusLabel:SetText("占据加成: " .. state_.spDef.desc)
        state_.bonusLabel:SetVisible(true)
    else
        state_.bonusLabel:SetVisible(false)
    end

    -- 归属信息 + 按钮状态
    local hasOwner = (state_.ownerGuild ~= "")
    local isMine = (state_.ownerGuildId ~= "" and state_.ownerGuildId == state_.myGuildId)
    local hasGuild = (state_.myGuildId ~= "")

    if not hasOwner then
        state_.ownerLabel:SetText("归属: 无主")
        state_.ownerLabel:SetStyle({ color = COLORS.ownerEmpty })
    elseif isMine then
        state_.ownerLabel:SetText("归属: " .. state_.ownerGuild .. " (我的帮会)")
        state_.ownerLabel:SetStyle({ color = COLORS.ownerMine })
    else
        state_.ownerLabel:SetText("归属: " .. state_.ownerGuild)
        state_.ownerLabel:SetStyle({ color = COLORS.ownerEnemy })
    end

    -- 按钮逻辑
    local hasOwnedOther = (state_.myGuildOwnedSpName ~= nil)  -- 帮会是否已拥有其他据点
    if not hasGuild then
        -- 无帮会：不能操作
        state_.actionBtn1:SetText("需要帮会才能操作")
        state_.actionBtn1:SetDisabled(true)
        state_.actionBtn1:SetVisible(true)
        state_.actionBtn2:SetVisible(false)
    elseif isMine then
        -- 自己帮会的据点：只能防守
        state_.actionBtn1:SetVisible(false)
        state_.actionBtn2:SetText("驻守防卫")
        state_.actionBtn2:SetDisabled(false)
        state_.actionBtn2:SetVisible(true)
        state_.actionBtn2:SetStyle({ backgroundColor = COLORS.btnDefend })
    elseif hasOwner then
        -- 敌方据点
        if hasOwnedOther then
            state_.actionBtn1:SetText("更换据点（进攻）")
            state_.actionBtn1:SetStyle({ backgroundColor = { 180, 120, 40, 255 } })
            state_.isSwitch = true
        else
            state_.actionBtn1:SetText("发起进攻")
            state_.actionBtn1:SetStyle({ backgroundColor = COLORS.btnAttack })
            state_.isSwitch = false
        end
        state_.actionBtn1:SetDisabled(false)
        state_.actionBtn1:SetVisible(true)
        state_.actionBtn2:SetVisible(false)
    else
        -- 无主据点
        if hasOwnedOther then
            state_.actionBtn1:SetText("更换据点")
            state_.actionBtn1:SetStyle({ backgroundColor = { 180, 120, 40, 255 } })
            state_.isSwitch = true
        else
            state_.actionBtn1:SetText("占领据点")
            state_.actionBtn1:SetStyle({ backgroundColor = COLORS.btnOccupy })
            state_.isSwitch = false
        end
        state_.actionBtn1:SetDisabled(false)
        state_.actionBtn1:SetVisible(true)
        state_.actionBtn2:SetVisible(false)
    end

    -- 清空消息
    state_.msgLabel:SetText("")
    state_.statusLabel:SetText("")

    -- 显示
    state_.visible = true
    print("[StrongholdPanel] SetVisible(true), current visible=" .. tostring(state_.root:IsVisible()))
    state_.root:SetVisible(true)
    print("[StrongholdPanel] 面板已显示, visible=" .. tostring(state_.root:IsVisible()))
end

-- ============================================================================
-- 隐藏面板
-- ============================================================================
function StrongholdPanel.Hide()
    if not state_.root then return end
    state_.visible = false
    state_.spId = nil
    state_.root:SetVisible(false)
end

-- ============================================================================
-- 查询接口
-- ============================================================================
function StrongholdPanel.IsVisible()
    return state_.visible
end

function StrongholdPanel.GetCurrentSpId()
    return state_.spId
end

function StrongholdPanel.GetRoot()
    return state_.root
end

-- ============================================================================
-- 服务端响应回调
-- ============================================================================
---@param success boolean
---@param msg string
function StrongholdPanel.OnResponse(success, msg)
    if not state_.root then return end
    if not state_.visible then return end

    if state_.msgLabel then
        state_.msgLabel:SetText(msg or "")
        if success then
            state_.msgLabel:SetStyle({ color = { 100, 220, 100, 255 } })
        else
            state_.msgLabel:SetStyle({ color = { 255, 100, 80, 255 } })
        end
    end

    -- 成功后短暂显示再关闭
    if success then
        state_.actionBtn1:SetDisabled(true)
        state_.actionBtn2:SetDisabled(true)
        state_.statusLabel:SetText("操作成功!")
    end
end

-- ============================================================================
-- 更新归属信息（服务端广播据点被占领时刷新）
-- ============================================================================
function StrongholdPanel.RefreshOwner(ownerGuild, ownerGuildId)
    if not state_.visible or not state_.spId then return end
    state_.ownerGuild = ownerGuild or ""
    state_.ownerGuildId = ownerGuildId or ""
    -- 重新走 Show 刷新显示
    StrongholdPanel.Show(state_.spId, {
        layer = state_.layer,
        ownerGuild = state_.ownerGuild,
        ownerGuildId = state_.ownerGuildId,
        myGuildId = state_.myGuildId,
        myGuildName = state_.myGuildName,
    })
end

return StrongholdPanel
