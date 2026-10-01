-- ============================================================================
-- BattlefieldMap.lua - 域外战场自由移动大地图（NanoVG 渲染 + 镜头跟随）
-- ============================================================================
-- 功能：NanoVG 绘制大地图，镜头跟随玩家，点击自由移动，多玩家实时可见，
--       接近怪物触发战斗，帮会层据点可交互。
-- 依赖：config/Settings

local Settings = require("config.Settings")

local BattlefieldMap = {}

-- ============================================================================
-- 模块状态
-- ============================================================================
local state_ = {
    active       = false,
    layer        = 0,
    -- 自己
    myX          = 0,
    myY          = 0,
    targetX      = 0,
    targetY      = 0,
    isMoving     = false,
    -- 怪物（服务端驱动，uid-keyed）
    monsters     = {},      -- [uid] = { x, y, targetX, targetY, monId }
    -- 其他玩家 (从服务端同步)
    otherPlayers = {},      -- [uid] = { x, y, targetX, targetY, name, guildName, color }
    -- 据点归属 (帮会层)
    strongpointOwners = {}, -- [spId] = { guild_name = "", guild_id = "" }
    -- 回调
    onBattle     = nil,
    onBack       = nil,
    onStrongpoint = nil,    -- function(spId, spDef)
    -- NanoVG
    vg           = nil,
    font         = -1,
    -- 同步计时
    syncTimer    = 0,
    -- 近据点提示
    nearStrongpoint = nil,  -- 当前靠近的据点 id

    -- 渲染缓存
    screenW      = 0,
    screenH      = 0,
    -- 据点面板状态（NanoVG 绘制）
    selectedSp   = nil,     -- 当前选中的据点 id
    spPanelRect  = nil,     -- { x, y, w, h } 面板矩形（用于点击检测）
    spBtnRect    = nil,     -- { x, y, w, h } 操作按钮矩形
    spCloseRect  = nil,     -- { x, y, w, h } 关闭按钮矩形
    -- 确认对话框（NanoVG 绘制，覆盖全屏）
    confirmDialog = nil,    -- { title, message, onConfirm, onCancel }
    confirmBtnYes = nil,    -- { x, y, w, h }
    confirmBtnNo  = nil,    -- { x, y, w, h }
    -- Toast 提示（NanoVG 绘制）
    toastText    = nil,     -- 当前提示文字
    toastTimer   = 0,       -- 提示剩余显示时间
    -- 占领倒计时
    captureActive   = false,   -- 是否正在占领
    captureElapsed  = 0,       -- 已过时间
    captureTotal    = 10,      -- 总时间（秒）
    captureSpName   = "",      -- 占领中的据点名
    -- 占领闪光动画
    captureFlash    = {},      -- [spId] = { startTime = gameTime }
}

-- ============================================================================
-- 主题配色
-- ============================================================================
local THEMES = {
    wasteland    = { bg1 = {35, 45, 30, 255},  bg2 = {25, 35, 20, 255},  accent = {120, 140, 80, 255} },
    valley       = { bg1 = {25, 40, 35, 255},  bg2 = {15, 30, 25, 255},  accent = {80, 160, 120, 255} },
    spirit       = { bg1 = {30, 35, 55, 255},  bg2 = {20, 25, 45, 255},  accent = {100, 130, 220, 255} },
    shadow       = { bg1 = {20, 20, 30, 255},  bg2 = {10, 10, 20, 255},  accent = {80, 60, 120, 255} },
    lava         = { bg1 = {50, 25, 15, 255},  bg2 = {35, 15, 10, 255},  accent = {220, 100, 40, 255} },
    thunder      = { bg1 = {30, 30, 45, 255},  bg2 = {20, 20, 35, 255},  accent = {180, 180, 60, 255} },
    void         = { bg1 = {15, 10, 30, 255},  bg2 = {8, 5, 20, 255},    accent = {140, 60, 200, 255} },
    celestial    = { bg1 = {25, 35, 50, 255},  bg2 = {15, 25, 40, 255},  accent = {140, 200, 255, 255} },
    chaos        = { bg1 = {35, 15, 25, 255},  bg2 = {25, 10, 15, 255},  accent = {200, 50, 80, 255} },
    tribulation  = { bg1 = {40, 30, 10, 255},  bg2 = {25, 20, 5, 255},   accent = {255, 200, 50, 255} },
}

-- ============================================================================
-- 绘制工具：简笔画风格装饰物
-- ============================================================================

--- 绘制树（简笔画三角形树冠 + 矩形树干）
local function DrawTree(vg, x, y, theme)
    local c = theme.accent
    -- 树干
    nvgBeginPath(vg)
    nvgRect(vg, x - 3, y, 6, 18)
    nvgFillColor(vg, nvgRGBA(80, 60, 40, 200))
    nvgFill(vg)
    -- 树冠（三角形）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y - 24)
    nvgLineTo(vg, x - 14, y + 2)
    nvgLineTo(vg, x + 14, y + 2)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], 180))
    nvgFill(vg)
    -- 轮廓
    nvgStrokeColor(vg, nvgRGBA(c[1] + 30, c[2] + 30, c[3] + 30, 120))
    nvgStrokeWidth(vg, 1.0)
    nvgStroke(vg)
end

--- 绘制石头（简笔画不规则椭圆）
local function DrawRock(vg, x, y, theme)
    nvgBeginPath(vg)
    nvgEllipse(vg, x, y, 12, 8)
    nvgFillColor(vg, nvgRGBA(70, 75, 80, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(100, 105, 110, 150))
    nvgStrokeWidth(vg, 1.2)
    nvgStroke(vg)
    -- 高光
    nvgBeginPath(vg)
    nvgEllipse(vg, x - 3, y - 2, 5, 3)
    nvgFillColor(vg, nvgRGBA(110, 115, 120, 80))
    nvgFill(vg)
end

--- 绘制灌木（简笔画小圆丛）
local function DrawBush(vg, x, y, theme)
    local c = theme.accent
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, 8)
    nvgCircle(vg, x - 7, y + 2, 6)
    nvgCircle(vg, x + 7, y + 2, 6)
    nvgFillColor(vg, nvgRGBA(c[1] - 20, c[2] + 10, c[3] - 20, 150))
    nvgFill(vg)
end


--- 绘制据点建筑（简笔画城堡 + 防护罩 + 占领闪光）
local function DrawStrongpoint(vg, x, y, spId, owners, theme, gameTime)
    local owner = owners[spId]
    local owned = owner and owner.guild_name ~= ""
    gameTime = gameTime or 0

    -- ═══ 颜色方案 ═══
    local baseColor, glowColor, shieldColor
    if owned then
        baseColor   = {60, 160, 220, 255}   -- 占领：明亮蓝
        glowColor   = {80, 200, 255, 255}   -- 发光描边
        shieldColor = {60, 180, 255}         -- 防护罩蓝
    else
        baseColor   = {100, 110, 130, 200}   -- 无主：灰色
        glowColor   = nil
        shieldColor = nil
    end

    -- ═══ 防护罩效果（已占领时） ═══
    if owned then
        local shieldRadius = 28
        local pulse = math.sin(gameTime * 1.5) * 0.15 + 0.85  -- 0.7~1.0 脉冲
        local alpha = math.floor(50 * pulse)

        -- 渐变圆形光罩（径向模拟：多层递减透明度）
        for i = 3, 1, -1 do
            local r = shieldRadius + i * 3
            local a = math.floor(alpha * (0.4 / i))
            nvgBeginPath(vg)
            nvgCircle(vg, x, y, r)
            nvgFillColor(vg, nvgRGBA(shieldColor[1], shieldColor[2], shieldColor[3], a))
            nvgFill(vg)
        end

        -- 主光罩圆
        nvgBeginPath(vg)
        nvgCircle(vg, x, y, shieldRadius)
        nvgFillColor(vg, nvgRGBA(shieldColor[1], shieldColor[2], shieldColor[3], alpha))
        nvgFill(vg)

        -- 旋转弧线（能量运行感）
        local arcAngle = gameTime * 1.2  -- 旋转速度
        nvgBeginPath(vg)
        nvgArc(vg, x, y, shieldRadius + 1, arcAngle, arcAngle + 2.0, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(shieldColor[1], shieldColor[2], shieldColor[3], math.floor(140 * pulse)))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)

        -- 第二条弧线（反向）
        nvgBeginPath(vg)
        nvgArc(vg, x, y, shieldRadius - 2, -arcAngle * 0.7, -arcAngle * 0.7 + 1.5, NVG_CW)
        nvgStrokeColor(vg, nvgRGBA(shieldColor[1], shieldColor[2], shieldColor[3], math.floor(90 * pulse)))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)
    end

    -- ═══ 城堡主体 ═══
    -- 基座
    nvgBeginPath(vg)
    nvgRect(vg, x - 18, y - 8, 36, 24)
    nvgFillColor(vg, nvgRGBA(baseColor[1], baseColor[2], baseColor[3], baseColor[4]))
    nvgFill(vg)
    -- 城垛（三个小方块）
    for i = -1, 1 do
        nvgBeginPath(vg)
        nvgRect(vg, x + i * 10 - 4, y - 16, 8, 10)
        nvgFillColor(vg, nvgRGBA(baseColor[1], baseColor[2], baseColor[3], baseColor[4]))
        nvgFill(vg)
    end
    -- 门
    nvgBeginPath(vg)
    nvgRect(vg, x - 4, y + 4, 8, 12)
    nvgFillColor(vg, nvgRGBA(40, 30, 20, 255))
    nvgFill(vg)

    -- ═══ 脉冲描边（已占领时） ═══
    if owned and glowColor then
        local strokePulse = math.sin(gameTime * 2.0) * 0.3 + 0.7
        local strokeAlpha = math.floor(200 * strokePulse)
        nvgBeginPath(vg)
        nvgRect(vg, x - 18, y - 16, 36, 32)
        nvgStrokeColor(vg, nvgRGBA(glowColor[1], glowColor[2], glowColor[3], strokeAlpha))
        nvgStrokeWidth(vg, 2.0)
        nvgStroke(vg)
    else
        -- 无主：普通轮廓
        nvgBeginPath(vg)
        nvgRect(vg, x - 18, y - 16, 36, 32)
        nvgStrokeColor(vg, nvgRGBA(200, 200, 200, 100))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)
    end

    -- ═══ 占领闪光动画 ═══
    local flash = state_.captureFlash[spId]
    if flash then
        local elapsed = gameTime - flash.startTime
        if elapsed < 2.0 then
            -- 扩散光环（0~2秒）
            local progress = elapsed / 2.0
            local radius = 20 + progress * 40  -- 20→60 扩散
            local alpha = math.floor(200 * (1.0 - progress))
            nvgBeginPath(vg)
            nvgCircle(vg, x, y, radius)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 200, alpha))
            nvgStrokeWidth(vg, 3.0 * (1.0 - progress) + 0.5)
            nvgStroke(vg)
            -- 内部爆发光
            if elapsed < 0.5 then
                local burstAlpha = math.floor(150 * (1.0 - elapsed / 0.5))
                nvgBeginPath(vg)
                nvgCircle(vg, x, y, 25)
                nvgFillColor(vg, nvgRGBA(255, 255, 220, burstAlpha))
                nvgFill(vg)
            end
        else
            -- 动画结束，清理
            state_.captureFlash[spId] = nil
        end
    end

    -- ═══ 归属标签 ═══
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if owned then
        nvgFillColor(vg, nvgRGBA(120, 220, 255, 255))
        nvgText(vg, x, y + 18, owner.guild_name)
    else
        nvgFillColor(vg, nvgRGBA(150, 150, 150, 200))
        nvgText(vg, x, y + 18, "无主")
    end
end

--- 绘制怪物标记（红色菱形 + 脉冲动画）
local function DrawMonster(vg, x, y, alive, pulse)
    if not alive then return end
    local r = 18
    local breathe = math.sin(pulse * 2.5) * 1.5

    -- 外层深色粗圆框（参考：黑色大圆框风格）
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r + breathe)
    nvgFillColor(vg, nvgRGBA(15, 10, 10, 240))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(60, 20, 20, 255))
    nvgStrokeWidth(vg, 3.5)
    nvgStroke(vg)

    -- 内部红色渐变填充
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r - 4)
    nvgFillColor(vg, nvgRGBA(80, 15, 15, 220))
    nvgFill(vg)

    -- 怪物符号：简笔兽眼（两个红色眼睛 + 獠牙）
    -- 眼睛
    nvgBeginPath(vg)
    nvgEllipse(vg, x - 5, y - 3, 3.5, 2.5)
    nvgFillColor(vg, nvgRGBA(255, 60, 60, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgEllipse(vg, x + 5, y - 3, 3.5, 2.5)
    nvgFillColor(vg, nvgRGBA(255, 60, 60, 255))
    nvgFill(vg)
    -- 瞳孔
    nvgBeginPath(vg)
    nvgCircle(vg, x - 5, y - 3, 1.2)
    nvgFillColor(vg, nvgRGBA(20, 0, 0, 255))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, x + 5, y - 3, 1.2)
    nvgFillColor(vg, nvgRGBA(20, 0, 0, 255))
    nvgFill(vg)
    -- 獠牙
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - 4, y + 4)
    nvgLineTo(vg, x - 2, y + 9)
    nvgLineTo(vg, x, y + 4)
    nvgFillColor(vg, nvgRGBA(220, 220, 200, 240))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, y + 4)
    nvgLineTo(vg, x + 2, y + 9)
    nvgLineTo(vg, x + 4, y + 4)
    nvgFillColor(vg, nvgRGBA(220, 220, 200, 240))
    nvgFill(vg)

    -- "????" 文字（未知怪物风格）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(200, 200, 200, 180))
    nvgText(vg, x, y + r + 14, "????")
end

--- 绘制玩家（圆形头像框 + 简笔人物 + 名字）
local function DrawPlayer(vg, x, y, name, isMe, guildColor)
    local r = 14
    -- 自己=红色粗圆框，他人=蓝绿色圆框
    local frameColor = isMe and {180, 40, 40, 255} or (guildColor or {50, 130, 180, 255})
    local bgColor = isMe and {40, 20, 20, 240} or {20, 30, 45, 240}

    -- 外层圆形框（粗边）
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    nvgFillColor(vg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4]))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(frameColor[1], frameColor[2], frameColor[3], frameColor[4]))
    nvgStrokeWidth(vg, 3.0)
    nvgStroke(vg)

    -- 简笔人物（头 + 身体）
    local headR = 3.5
    local bodyColor = isMe and {230, 200, 170, 240} or {180, 200, 220, 220}
    -- 头
    nvgBeginPath(vg)
    nvgCircle(vg, x, y - 4, headR)
    nvgFillColor(vg, nvgRGBA(bodyColor[1], bodyColor[2], bodyColor[3], bodyColor[4]))
    nvgFill(vg)
    -- 身体（梯形）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - 2.5, y + 1)
    nvgLineTo(vg, x + 2.5, y + 1)
    nvgLineTo(vg, x + 5, y + 9)
    nvgLineTo(vg, x - 5, y + 9)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(bodyColor[1], bodyColor[2], bodyColor[3], bodyColor[4] - 40))
    nvgFill(vg)

    -- 名字（上方）
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(vg, nvgRGBA(frameColor[1] + 60, frameColor[2] + 60, frameColor[3] + 60, 240))
    nvgText(vg, x, y - r - 3, name or "")
end

--- 绘制移动目标指示（闪烁圈）
local function DrawMoveTarget(vg, x, y, pulse)
    local alpha = math.floor(100 + math.sin(pulse * 5) * 60)
    local radius = 8 + math.sin(pulse * 4) * 3
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, radius)
    nvgStrokeColor(vg, nvgRGBA(200, 255, 200, alpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

--- 绘制地图边界
local function DrawMapBorder(vg, mapW, mapH, theme)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, mapW, mapH)
    nvgStrokeColor(vg, nvgRGBA(theme.accent[1], theme.accent[2], theme.accent[3], 80))
    nvgStrokeWidth(vg, 2.0)
    nvgStroke(vg)
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 初始化/进入战场层
---@param layer number 层数(1-10)
---@param callbacks table { onBattle, onBack, onCleared, onStrongpoint }
---@param vg userdata NanoVG 上下文
function BattlefieldMap.Activate(layer, callbacks, vg)
    local mapCfg = Settings.BATTLEFIELD_MAP[layer]
    if not mapCfg then return false end

    callbacks = callbacks or {}
    state_.active = true
    state_.layer = layer
    state_.myX = mapCfg.spawn.x
    state_.myY = mapCfg.spawn.y
    state_.targetX = mapCfg.spawn.x
    state_.targetY = mapCfg.spawn.y
    state_.isMoving = false
    state_.monsters = {}            -- 由服务端快照/同步填充
    state_.otherPlayers = {}
    state_.strongpointOwners = {}
    state_.nearStrongpoint = nil
    state_.syncTimer = 0
    state_.onBattle = callbacks.onBattle
    state_.onBack = callbacks.onBack
    state_.onStrongpoint = callbacks.onStrongpoint
    state_.getQuestState = callbacks.getQuestState
    state_.vg = vg

    -- 创建字体（如果还没创建）
    if state_.font < 0 and vg then
        state_.font = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    end

    return true
end

--- 退出战场
function BattlefieldMap.Deactivate()
    state_.active = false
    state_.layer = 0
    state_.otherPlayers = {}
end

--- 是否激活中
function BattlefieldMap.IsActive()
    return state_.active
end


--- 获取当前层
function BattlefieldMap.GetLayer()
    return state_.layer
end

--- 获取玩家位置（用于服务端同步）
function BattlefieldMap.GetMyPosition()
    return state_.myX, state_.myY
end

--- 点击地图位置（屏幕坐标→地图坐标已在外部转换）
function BattlefieldMap.OnMapClick(mapX, mapY)
    if not state_.active then
        print("[BF-MAP] OnMapClick: NOT active, ignored!")
        return
    end
    local cfg = Settings.BATTLEFIELD_MAP
    -- 边界限制
    mapX = math.max(20, math.min(cfg.MAP_WIDTH - 20, mapX))
    mapY = math.max(20, math.min(cfg.MAP_HEIGHT - 20, mapY))
    print(string.format("[BF-MAP] OnMapClick: target=(%.0f,%.0f) myPos=(%.0f,%.0f) wasMoving=%s",
        mapX, mapY, state_.myX, state_.myY, tostring(state_.isMoving)))
    state_.targetX = mapX
    state_.targetY = mapY
    state_.isMoving = true
end

--- 每帧更新（调用方传入 dt）
---@param dt number deltaTime
---@return string|nil action 返回 "sync" 时需要向服务端发送位置
function BattlefieldMap.Update(dt)
    if not state_.active then return nil end

    local action = nil
    local cfg = Settings.BATTLEFIELD_MAP

    -- 玩家移动逻辑
    if state_.isMoving then
        local dx = state_.targetX - state_.myX
        local dy = state_.targetY - state_.myY
        local dist = math.sqrt(dx * dx + dy * dy)

        -- [BF-DIAG] 首次移动帧打印
        if not state_._diagMovePrinted then
            state_._diagMovePrinted = true
            print(string.format("[BF-MAP] Update移动中: pos=(%.0f,%.0f) target=(%.0f,%.0f) dist=%.1f speed=%d dt=%.3f",
                state_.myX, state_.myY, state_.targetX, state_.targetY, dist, cfg.MOVE_SPEED, dt))
        end

        if dist < 3 then
            state_.myX = state_.targetX
            state_.myY = state_.targetY
            state_.isMoving = false
            state_._diagMovePrinted = nil  -- 下次移动再打印
        else
            local speed = cfg.MOVE_SPEED * dt
            state_.myX = state_.myX + (dx / dist) * speed
            state_.myY = state_.myY + (dy / dist) * speed
        end

        -- 据点接近检测（帮会层）
        local layerCfg = cfg[state_.layer]
        if layerCfg and layerCfg.strongpoints then
            state_.nearStrongpoint = nil
            for _, sp in ipairs(layerCfg.strongpoints) do
                local sdx = state_.myX - sp.x
                local sdy = state_.myY - sp.y
                local sdist = math.sqrt(sdx * sdx + sdy * sdy)
                if sdist < cfg.STRONGPOINT_INTERACT_RADIUS then
                    state_.nearStrongpoint = sp.id
                    break
                end
            end
        end

        -- 同步计时
        state_.syncTimer = state_.syncTimer + dt
        if state_.syncTimer >= cfg.SYNC_INTERVAL then
            state_.syncTimer = 0
            action = "sync"
        end
    end

    -- 怪物位置插值（服务端推送 targetX/targetY，客户端平滑跟随）
    for uid, mon in pairs(state_.monsters) do
        if mon.targetX and mon.targetY then
            mon.x = mon.x + (mon.targetX - mon.x) * math.min(1, dt * 6)
            mon.y = mon.y + (mon.targetY - mon.y) * math.min(1, dt * 6)
        end
    end

    -- 其他玩家插值
    for uid, p in pairs(state_.otherPlayers) do
        if p.targetX and p.targetY then
            p.x = p.x + (p.targetX - p.x) * math.min(1, dt * 8)
            p.y = p.y + (p.targetY - p.y) * math.min(1, dt * 8)
        end
    end

    -- Toast 倒计时
    if state_.toastTimer > 0 then
        state_.toastTimer = state_.toastTimer - dt
        if state_.toastTimer <= 0 then
            state_.toastText = nil
            state_.toastTimer = 0
        end
    end

    -- 占领倒计时推进
    if state_.captureActive then
        state_.captureElapsed = state_.captureElapsed + dt
        if state_.captureElapsed >= state_.captureTotal then
            state_.captureActive = false
        end
    end

    return action
end

--- 渲染大地图（在 NanoVGRender 事件中调用）
---@param screenW number 屏幕宽度
---@param screenH number 屏幕高度
---@param time number 运行时间（用于动画）
function BattlefieldMap.Render(screenW, screenH, time, dpr)
    if not state_.active then return end
    local vg = state_.vg
    if not vg then return end

    dpr = dpr or 1.0
    state_.screenW = screenW
    state_.screenH = screenH

    local cfg = Settings.BATTLEFIELD_MAP
    local layerCfg = cfg[state_.layer]
    if not layerCfg then return end

    local layerDef = Settings.BATTLEFIELD_LAYERS[state_.layer]
    local themeName = layerCfg.theme or "wasteland"
    local theme = THEMES[themeName] or THEMES.wasteland

    -- 计算镜头偏移（玩家居中）
    local camX = state_.myX - screenW / 2
    local camY = state_.myY - screenH / 2
    -- 限制镜头不超出地图边界
    camX = math.max(0, math.min(cfg.MAP_WIDTH - screenW, camX))
    camY = math.max(0, math.min(cfg.MAP_HEIGHT - screenH, camY))

    nvgBeginFrame(vg, screenW, screenH, dpr)

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(theme.bg1[1], theme.bg1[2], theme.bg1[3], theme.bg1[4]))
    nvgFill(vg)

    -- 应用镜头变换
    nvgSave(vg)
    nvgTranslate(vg, -camX, -camY)

    -- 地图边界
    DrawMapBorder(vg, cfg.MAP_WIDTH, cfg.MAP_HEIGHT, theme)

    -- 绘制网格参考线（淡色）
    nvgStrokeColor(vg, nvgRGBA(theme.accent[1], theme.accent[2], theme.accent[3], 20))
    nvgStrokeWidth(vg, 0.5)
    for gx = 0, cfg.MAP_WIDTH, 100 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, gx, 0)
        nvgLineTo(vg, gx, cfg.MAP_HEIGHT)
        nvgStroke(vg)
    end
    for gy = 0, cfg.MAP_HEIGHT, 100 do
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, gy)
        nvgLineTo(vg, cfg.MAP_WIDTH, gy)
        nvgStroke(vg)
    end

    -- 绘制装饰物
    for _, d in ipairs(layerCfg.decor or {}) do
        if d.type == "tree" then
            DrawTree(vg, d.x, d.y, theme)
        elseif d.type == "rock" then
            DrawRock(vg, d.x, d.y, theme)
        elseif d.type == "bush" then
            DrawBush(vg, d.x, d.y, theme)
        end
    end

    -- 绘制据点（帮会层）
    if layerCfg.strongpoints then
        for _, sp in ipairs(layerCfg.strongpoints) do
            DrawStrongpoint(vg, sp.x, sp.y, sp.id, state_.strongpointOwners, theme, time)
        end
    end

    -- 绘制怪物（服务端驱动，只有存活的才在表中）
    for uid, mon in pairs(state_.monsters) do
        DrawMonster(vg, mon.x, mon.y, true, time)
    end

    -- 绘制其他玩家
    for uid, p in pairs(state_.otherPlayers) do
        DrawPlayer(vg, p.x, p.y, p.name, false, p.color)
    end

    -- 绘制自己
    DrawPlayer(vg, state_.myX, state_.myY, "我", true, nil)

    -- 移动目标指示
    if state_.isMoving then
        DrawMoveTarget(vg, state_.targetX, state_.targetY, time)
    end

    nvgRestore(vg)

    -- ── HUD 层（固定在屏幕上，不随镜头移动）──

    -- 顶栏
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, 36)
    nvgFillColor(vg, nvgRGBA(10, 12, 20, 220))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 255))
    local title = layerDef and layerDef.name or ("第" .. state_.layer .. "层")
    nvgText(vg, 12, 18, title)

    -- 右侧信息
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    -- 统计当前存活怪物数量
    local monCount = 0
    for _ in pairs(state_.monsters) do monCount = monCount + 1 end
    if monCount > 0 then
        nvgFillColor(vg, nvgRGBA(220, 150, 80, 255))
        nvgText(vg, screenW - 12, 18, string.format("妖兽 x%d", monCount))
    elseif layerCfg and layerCfg.strongpoints then
        nvgFillColor(vg, nvgRGBA(140, 200, 255, 255))
        nvgText(vg, screenW - 12, 18, "帮会领地")
    end

    -- 底栏提示
    nvgBeginPath(vg)
    nvgRect(vg, 0, screenH - 30, screenW, 30)
    nvgFillColor(vg, nvgRGBA(10, 12, 20, 200))
    nvgFill(vg)

    nvgFontSize(vg, 11)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(140, 140, 160, 255))

    if state_.nearStrongpoint then
        -- 靠近据点时显示操作提示
        local spDef = nil
        local spDefs = Settings.STRONGPOINTS_BY_LAYER[state_.layer]
        if spDefs then
            for _, sp in ipairs(spDefs) do
                if sp.id == state_.nearStrongpoint then spDef = sp; break end
            end
        end
        local spName = spDef and spDef.name or state_.nearStrongpoint
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, screenW / 2, screenH - 15, "【" .. spName .. "】点击据点交互")
    else
        nvgText(vg, screenW / 2, screenH - 15, "点击地图移动 · 点击据点/怪物交互")
    end

    -- 返回按钮区域（左上角）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, 8, 42, 60, 26, 4)
    nvgFillColor(vg, nvgRGBA(120, 40, 40, 200))
    nvgFill(vg)
    nvgFontSize(vg, 12)
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(vg, nvgRGBA(255, 200, 200, 255))
    nvgText(vg, 38, 55, "← 离开")

    -- ========== 任务列表（右侧半透明常驻） ==========
    local qs = state_.getQuestState and state_.getQuestState()
    if qs then
        local panelW = 160
        local panelX = screenW - panelW - 8
        local panelY = 42
        local lineH = 16
        local py = panelY + 8  -- 内容起始 y

        -- 收集要绘制的行 { text, color, size(可选), indent(可选) }
        local lines = {}
        -- 主线
        local mq = qs.mainQuest
        if mq and mq.id ~= "" then
            table.insert(lines, { text = "【主线】" .. (mq.name or ""), color = {255, 215, 0, 230}, size = 12 })
            if mq.desc and mq.desc ~= "" then
                table.insert(lines, { text = mq.desc, color = {190, 190, 190, 200}, size = 10, indent = 4 })
            end
            local progStr = string.format("进度: %d/%d", mq.progress, mq.goal)
            local progColor = (mq.progress >= mq.goal) and {100, 255, 100, 220} or {255, 170, 0, 220}
            table.insert(lines, { text = progStr, color = progColor, size = 10, indent = 4 })
        else
            table.insert(lines, { text = "【主线】已全部完成", color = {100, 255, 100, 220}, size = 12 })
        end
        -- 分隔
        table.insert(lines, { text = "", color = nil, size = 6 })
        -- 日常标题
        table.insert(lines, { text = "【日常】", color = {136, 204, 255, 230}, size = 12 })
        local dailyDefs = Settings.DAILY_QUESTS or {}
        for i, dq in ipairs(qs.dailyQuests or {}) do
            local def = dailyDefs[i]
            local dName = def and def.name or dq.id
            local dDesc = def and def.desc or ""
            local statusStr
            if dq.claimed then
                statusStr = " ✓已领"
            elseif dq.progress >= dq.goal then
                statusStr = " ★可领"
            else
                statusStr = string.format(" %d/%d", dq.progress, dq.goal)
            end
            local nameColor = dq.claimed and {100, 100, 100, 180} or {220, 230, 255, 230}
            table.insert(lines, { text = "· " .. dName .. statusStr, color = nameColor, size = 11, indent = 2 })
            if dDesc ~= "" and not dq.claimed then
                table.insert(lines, { text = dDesc, color = {160, 160, 160, 180}, size = 9, indent = 12 })
            end
        end

        -- 计算面板高度
        local contentH = 12  -- padding top+bottom
        for _, ln in ipairs(lines) do
            contentH = contentH + (ln.size or 11) + 4
        end
        -- 绘制背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, panelX, panelY, panelW, contentH, 8)
        nvgFillColor(vg, nvgRGBA(10, 10, 26, 150))
        nvgFill(vg)

        -- 绘制内容
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        for _, ln in ipairs(lines) do
            if ln.color then
                nvgFontSize(vg, ln.size or 11)
                nvgFillColor(vg, nvgRGBA(ln.color[1], ln.color[2], ln.color[3], ln.color[4]))
                nvgText(vg, panelX + 8 + (ln.indent or 0), py, ln.text)
            end
            py = py + (ln.size or 11) + 4
        end
    end

    -- ========================================================================
    -- 据点面板（NanoVG 绘制，覆盖在地图上方）
    -- ========================================================================
    if state_.selectedSp then
        local spDef = nil
        local spsByLayer = Settings.STRONGPOINTS_BY_LAYER[state_.layer]
        if spsByLayer then
            for _, sp in ipairs(spsByLayer) do
                if sp.id == state_.selectedSp then
                    spDef = sp
                    break
                end
            end
        end
        if spDef then
            local panelW = 240
            local panelH = 150
            local panelX = (screenW - panelW) / 2
            local panelY = screenH - panelH - 60
            state_.spPanelRect = { x = panelX, y = panelY, w = panelW, h = panelH }

            -- 面板背景
            nvgBeginPath(vg)
            nvgRoundedRect(vg, panelX, panelY, panelW, panelH, 8)
            nvgFillColor(vg, nvgRGBA(20, 15, 30, 220))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(180, 140, 60, 200))
            nvgStrokeWidth(vg, 1.5)
            nvgStroke(vg)

            -- 标题（据点名称）
            nvgFontSize(vg, 16)
            nvgFontFace(vg, "sans")
            nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            nvgText(vg, panelX + panelW / 2, panelY + 10, "【" .. spDef.name .. "】")

            -- 加成描述
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
            nvgText(vg, panelX + panelW / 2, panelY + 34, "加成: " .. spDef.desc)

            -- 归属信息
            local ownerInfo = state_.strongpointOwners[state_.selectedSp]
            local ownerText = "归属: 无主"
            if ownerInfo and ownerInfo.guild_name and ownerInfo.guild_name ~= "" then
                ownerText = "归属: " .. ownerInfo.guild_name
            end
            nvgFontSize(vg, 12)
            nvgFillColor(vg, nvgRGBA(160, 220, 160, 255))
            nvgText(vg, panelX + panelW / 2, panelY + 54, ownerText)

            -- 操作按钮
            local btnW = 120
            local btnH = 30
            local btnX = panelX + (panelW - btnW) / 2
            local btnY = panelY + 80
            state_.spBtnRect = { x = btnX, y = btnY, w = btnW, h = btnH }

            local btnText = "占领据点"
            if ownerInfo and ownerInfo.guild_name and ownerInfo.guild_name ~= "" then
                btnText = "发起进攻"
            end

            nvgBeginPath(vg)
            nvgRoundedRect(vg, btnX, btnY, btnW, btnH, 5)
            nvgFillColor(vg, nvgRGBA(180, 80, 40, 220))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 160, 60, 200))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)

            nvgFontSize(vg, 14)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, btnX + btnW / 2, btnY + btnH / 2, btnText)

            -- 关闭按钮（右上角 ×）
            local closeX = panelX + panelW - 24
            local closeY = panelY + 4
            local closeSize = 20
            state_.spCloseRect = { x = closeX, y = closeY, w = closeSize, h = closeSize }

            nvgFontSize(vg, 16)
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 200))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, closeX + closeSize / 2, closeY + closeSize / 2, "×")
        else
            -- 找不到据点定义，关闭面板
            state_.selectedSp = nil
        end
    end

    -- ========================================================================
    -- 占领倒计时（屏幕中央偏上，圆环+秒数）
    -- ========================================================================
    if state_.captureActive then
        local progress = math.min(1.0, state_.captureElapsed / state_.captureTotal)
        local remain = math.max(0, state_.captureTotal - state_.captureElapsed)
        local cx, cy = screenW / 2, screenH * 0.45
        local radius = 36

        -- 外圈背景
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy, radius)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgFill(vg)

        -- 进度圆弧
        local startAngle = -math.pi / 2
        local endAngle = startAngle + progress * math.pi * 2
        nvgBeginPath(vg)
        nvgArc(vg, cx, cy, radius - 4, startAngle, endAngle, NVG_CW)
        nvgStrokeWidth(vg, 5)
        nvgStrokeColor(vg, nvgRGBA(100, 255, 100, 220))
        nvgStroke(vg)

        -- 剩余秒数
        nvgFontSize(vg, 22)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
        nvgText(vg, cx, cy, string.format("%.0f", math.ceil(remain)))

        -- 据点名 + "占领中"
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(200, 255, 200, 200))
        nvgText(vg, cx, cy + radius + 14, state_.captureSpName .. " 占领中...")
    end

    -- ========================================================================
    -- 确认对话框（全屏半透明遮罩 + 居中面板）
    -- ========================================================================
    if state_.confirmDialog then
        local dlg = state_.confirmDialog
        -- 全屏半透明遮罩
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, screenW, screenH)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
        nvgFill(vg)

        -- 居中面板
        local dlgW = 280
        local dlgH = 160
        local dlgX = (screenW - dlgW) / 2
        local dlgY = (screenH - dlgH) / 2

        nvgBeginPath(vg)
        nvgRoundedRect(vg, dlgX, dlgY, dlgW, dlgH, 10)
        nvgFillColor(vg, nvgRGBA(25, 20, 35, 240))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 160, 60, 200))
        nvgStrokeWidth(vg, 1.5)
        nvgStroke(vg)

        -- 标题
        nvgFontSize(vg, 16)
        nvgFontFace(vg, "sans")
        nvgFillColor(vg, nvgRGBA(255, 220, 100, 255))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgText(vg, dlgX + dlgW / 2, dlgY + 14, dlg.title or "确认")

        -- 内容
        nvgFontSize(vg, 13)
        nvgFillColor(vg, nvgRGBA(220, 220, 220, 255))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local msg = dlg.message or ""
        nvgText(vg, dlgX + dlgW / 2, dlgY + 42, msg)

        -- 按钮区域
        local btnW = 90
        local btnH = 32
        local btnY2 = dlgY + dlgH - 50
        local gap = 20
        local btnXYes = dlgX + dlgW / 2 - btnW - gap / 2
        local btnXNo  = dlgX + dlgW / 2 + gap / 2

        -- 确认按钮
        state_.confirmBtnYes = { x = btnXYes, y = btnY2, w = btnW, h = btnH }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnXYes, btnY2, btnW, btnH, 5)
        nvgFillColor(vg, nvgRGBA(60, 140, 60, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(100, 220, 100, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, btnXYes + btnW / 2, btnY2 + btnH / 2, "确认更换")

        -- 取消按钮
        state_.confirmBtnNo = { x = btnXNo, y = btnY2, w = btnW, h = btnH }
        nvgBeginPath(vg)
        nvgRoundedRect(vg, btnXNo, btnY2, btnW, btnH, 5)
        nvgFillColor(vg, nvgRGBA(100, 60, 60, 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(200, 100, 100, 180))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, btnXNo + btnW / 2, btnY2 + btnH / 2, "取消")
    end

    -- ========================================================================
    -- Toast 提示（屏幕中上方，淡入淡出）
    -- ========================================================================
    if state_.toastText and state_.toastTimer > 0 then
        local alpha = math.min(1.0, state_.toastTimer / 0.5) * 255  -- 最后0.5秒淡出
        local toastY = screenH * 0.3
        -- 背景
        nvgFontSize(vg, 14)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local bounds = {}
        local tw = nvgTextBounds(vg, 0, 0, state_.toastText, nil, bounds)
        local padX = 16
        local padY = 8
        local bgW = tw + padX * 2
        local bgH = 14 + padY * 2
        local bgX = (screenW - bgW) / 2
        local bgY = toastY - bgH / 2
        nvgBeginPath(vg)
        nvgRoundedRect(vg, bgX, bgY, bgW, bgH, 6)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * 0.75)))
        nvgFill(vg)
        -- 文字
        nvgFillColor(vg, nvgRGBA(255, 240, 180, math.floor(alpha)))
        nvgText(vg, screenW / 2, toastY, state_.toastText)
    end

    nvgEndFrame(vg)
end

--- 处理屏幕点击事件
---@param screenX number 屏幕点击 x
---@param screenY number 屏幕点击 y
---@return string|nil action "back"|"strongpoint"|nil
function BattlefieldMap.OnClick(screenX, screenY)
    if not state_.active then return nil end

    local screenW = state_.screenW
    local screenH = state_.screenH

    print(string.format("[BattlefieldMap] OnClick screen=(%.0f,%.0f) sw=%.0f sh=%.0f layer=%s myPos=(%.0f,%.0f)",
        screenX, screenY, screenW, screenH, tostring(state_.layer), state_.myX, state_.myY))


    -- ★ 确认对话框点击检测（最高优先级，对话框打开时拦截所有点击）
    if state_.confirmDialog then
        -- 检测确认按钮
        if state_.confirmBtnYes then
            local br = state_.confirmBtnYes
            if screenX >= br.x and screenX <= br.x + br.w and screenY >= br.y and screenY <= br.y + br.h then
                print("[BattlefieldMap] 确认对话框: 点击确认")
                local cb = state_.confirmDialog.onConfirm
                state_.confirmDialog = nil
                state_.confirmBtnYes = nil
                state_.confirmBtnNo = nil
                if cb then cb() end
                return "confirm_yes"
            end
        end
        -- 检测取消按钮
        if state_.confirmBtnNo then
            local br = state_.confirmBtnNo
            if screenX >= br.x and screenX <= br.x + br.w and screenY >= br.y and screenY <= br.y + br.h then
                print("[BattlefieldMap] 确认对话框: 点击取消")
                local cb = state_.confirmDialog.onCancel
                state_.confirmDialog = nil
                state_.confirmBtnYes = nil
                state_.confirmBtnNo = nil
                if cb then cb() end
                return "confirm_no"
            end
        end
        -- 点击对话框外部也不穿透（遮罩拦截）
        return "confirm_block"
    end

    -- ★ 据点面板点击检测（面板打开时优先处理）
    if state_.selectedSp and state_.spPanelRect then
        local pr = state_.spPanelRect
        -- 检测是否点击在面板区域内
        if screenX >= pr.x and screenX <= pr.x + pr.w and screenY >= pr.y and screenY <= pr.y + pr.h then
            -- 关闭按钮
            if state_.spCloseRect then
                local cr = state_.spCloseRect
                if screenX >= cr.x and screenX <= cr.x + cr.w and screenY >= cr.y and screenY <= cr.y + cr.h then
                    print("[BattlefieldMap] 据点面板: 关闭")
                    state_.selectedSp = nil
                    state_.spPanelRect = nil
                    state_.spBtnRect = nil
                    state_.spCloseRect = nil
                    return "strongpoint"
                end
            end
            -- 操作按钮（占领/进攻）
            if state_.spBtnRect then
                local br = state_.spBtnRect
                if screenX >= br.x and screenX <= br.x + br.w and screenY >= br.y and screenY <= br.y + br.h then
                    print("[BattlefieldMap] 据点面板: 操作按钮 - " .. state_.selectedSp)
                    local spId = state_.selectedSp
                    -- 关闭面板
                    state_.selectedSp = nil
                    state_.spPanelRect = nil
                    state_.spBtnRect = nil
                    state_.spCloseRect = nil
                    -- 执行操作
                    if state_.onStrongpoint then
                        state_.onStrongpoint(spId)
                    end
                    return "strongpoint"
                end
            end
            -- 点击面板其他区域，不穿透
            return "strongpoint"
        else
            -- 点击面板外部，关闭面板
            print("[BattlefieldMap] 据点面板: 点击外部关闭")
            state_.selectedSp = nil
            state_.spPanelRect = nil
            state_.spBtnRect = nil
            state_.spCloseRect = nil
            -- 继续处理地图点击（不 return）
        end
    end

    -- 返回按钮检测（左上角 8,42 ~ 68,68）
    if screenX >= 8 and screenX <= 68 and screenY >= 42 and screenY <= 68 then
        if state_.onBack then
            state_.onBack()
        end
        return "back"
    end



    -- 据点交互（靠近据点时点击屏幕中央区域）
    if state_.nearStrongpoint then
        local cx = screenW / 2
        local cy = screenH / 2
        if math.abs(screenX - cx) < 80 and math.abs(screenY - cy) < 40 then
            if state_.onStrongpoint then
                state_.onStrongpoint(state_.nearStrongpoint)
            end
            return "strongpoint"
        end
    end

    -- 顶栏/底栏区域不响应地图点击
    if screenY < 36 or screenY > screenH - 30 then
        return nil
    end

    -- 转换屏幕坐标为地图坐标
    local cfg = Settings.BATTLEFIELD_MAP
    local camX = state_.myX - screenW / 2
    local camY = state_.myY - screenH / 2
    camX = math.max(0, math.min(cfg.MAP_WIDTH - screenW, camX))
    camY = math.max(0, math.min(cfg.MAP_HEIGHT - screenH, camY))

    local mapX = screenX + camX
    local mapY = screenY + camY

    print(string.format("[BattlefieldMap] cam=(%.0f,%.0f) map=(%.0f,%.0f)", camX, camY, mapX, mapY))

    -- ★ 检测是否点击到据点（点击半径 40，据点图标较大）
    local SP_CLICK_RADIUS = 40
    local cfg2 = cfg[state_.layer]
    if cfg2 and cfg2.strongpoints then
        for _, sp in ipairs(cfg2.strongpoints) do
            local dx = mapX - sp.x
            local dy = mapY - sp.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < SP_CLICK_RADIUS then
                -- 点击到了据点，打开 NanoVG 据点面板
                print("[BattlefieldMap] 点击据点: " .. sp.id .. " dist=" .. string.format("%.1f", dist))
                -- 同时让角色走向据点（视觉效果）
                BattlefieldMap.OnMapClick(sp.x, sp.y)
                -- 设置选中据点（NanoVG 面板将在下一帧绘制）
                state_.selectedSp = sp.id
                return "strongpoint"
            end
        end
    end

    -- ★ 检测是否点击到怪物（点击半径 30，比显示半径 18 稍大方便点击）
    local CLICK_RADIUS = 30
    local BATTLE_RANGE = 80  -- 必须走到怪物附近才能战斗（地图像素距离）
    for uid, mon in pairs(state_.monsters) do
        local dx = mapX - mon.x
        local dy = mapY - mon.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < CLICK_RADIUS then
            -- 点击到了怪物，检查玩家是否足够靠近
            local pdx = state_.myX - mon.x
            local pdy = state_.myY - mon.y
            local playerDist = math.sqrt(pdx * pdx + pdy * pdy)
            if playerDist < BATTLE_RANGE then
                -- 玩家在战斗范围内，触发战斗（传递怪物定义ID，非实例uid）
                if state_.onBattle then
                    state_.onBattle(mon.monId or uid)
                end
                return "battle"
            else
                -- 玩家太远，先走到怪物附近
                BattlefieldMap.OnMapClick(mon.x, mon.y)
                return "move_to_monster"
            end
        end
    end

    -- 未点击到怪物，移动到该位置
    BattlefieldMap.OnMapClick(mapX, mapY)
    return nil
end

-- ============================================================================
-- 多玩家同步接口（由 Client.lua 网络事件调用）
-- ============================================================================

--- 收到其他玩家位置更新
function BattlefieldMap.UpdatePlayerPos(uid, x, y, name, guildName)
    if not state_.active then return end
    local p = state_.otherPlayers[uid]
    if not p then
        state_.otherPlayers[uid] = {
            x = x, y = y, targetX = x, targetY = y,
            name = name or "?",
            guildName = guildName or "",
            color = nil,  -- 默认蓝色
        }
    else
        p.targetX = x
        p.targetY = y
        p.name = name or p.name
        p.guildName = guildName or p.guildName
    end
end

--- 玩家离开本层
function BattlefieldMap.RemovePlayer(uid)
    state_.otherPlayers[uid] = nil
end

--- 设置全量快照（进入层时，服务端驱动格式）
---@param players table<string, {x:number, y:number, name:string, guildName:string, color:table}>
---@param monsters table<string, {x:number, y:number, monId:string, alive:boolean}>
---@param strongpointOwners table|nil
function BattlefieldMap.SetSnapshot(players, monsters, strongpointOwners)
    if players then
        state_.otherPlayers = {}
        for uid, p in pairs(players) do
            state_.otherPlayers[uid] = {
                x = p.x, y = p.y, targetX = p.x, targetY = p.y,
                name = p.name or "?",
                guildName = p.guildName or "",
                color = p.color,
            }
        end
    end
    if monsters then
        state_.monsters = {}
        for uid, m in pairs(monsters) do
            if m.alive then
                state_.monsters[uid] = {
                    x = m.x, y = m.y,
                    targetX = m.x, targetY = m.y,
                    monId = m.monId,
                }
            end
        end
    end
    if strongpointOwners then
        state_.strongpointOwners = strongpointOwners
    end
end

--- 更新据点归属
function BattlefieldMap.UpdateStrongpointOwner(spId, guildName, guildId)
    state_.strongpointOwners[spId] = {
        guild_name = guildName or "",
        guild_id = guildId or "",
    }
    -- 触发占领闪光动画（仅当新占领时）
    if guildName and guildName ~= "" then
        state_.captureFlash[spId] = { startTime = time:GetElapsedTime() }
    end
end

-- ============================================================================
-- 服务端驱动怪物接口
-- ============================================================================

--- 移除单个怪物（服务端通知击杀）
---@param uid string 怪物 uid
function BattlefieldMap.RemoveMonster(uid)
    state_.monsters[uid] = nil
end

--- 增量同步怪物位置（服务端定期广播）
--- 格式: "uid|x|y|monId|alive\nuid|x|y|monId|alive\n..."
---@param data string
function BattlefieldMap.SyncMonsters(data)
    for line in data:gmatch("[^\n]+") do
        local uid, mx, my, monId, alive = line:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)")
        if uid then
            local nx = tonumber(mx)
            local ny = tonumber(my)
            local isAlive = (alive == "1")

            if isAlive then
                local mon = state_.monsters[uid]
                if mon then
                    -- 已有怪物：更新目标位置用于插值
                    mon.targetX = nx or mon.targetX
                    mon.targetY = ny or mon.targetY
                else
                    -- 新出现的怪物（可能错过了 spawn 事件）
                    state_.monsters[uid] = {
                        x = nx or 0, y = ny or 0,
                        targetX = nx or 0, targetY = ny or 0,
                        monId = monId,
                    }
                end
            else
                -- 已死亡的怪物从客户端移除
                state_.monsters[uid] = nil
            end
        end
    end
end

--- 新怪物出生（服务端通知）
---@param uid string 怪物 uid
---@param x number
---@param y number
---@param monId string
function BattlefieldMap.AddMonster(uid, x, y, monId)
    state_.monsters[uid] = {
        x = x, y = y,
        targetX = x, targetY = y,
        monId = monId,
    }
end

--- 战斗结束（服务端驱动后客户端无需特殊处理，保留空函数兼容调用）
function BattlefieldMap.OnBattleEnd(won)
    -- 服务端驱动：怪物状态完全由服务端管理，客户端无需恢复
end

--- 获取当前靠近的据点 id
function BattlefieldMap.GetNearStrongpoint()
    return state_.nearStrongpoint
end

--- 获取当前所有据点归属数据
---@return table<string, {guild_name: string, guild_id: string}>
function BattlefieldMap.GetStrongholdOwners()
    return state_.strongpointOwners
end

--- 获取当前层号
function BattlefieldMap.GetLayer()
    return state_.layer
end

--- 显示 Toast 提示（在 NanoVG 层绘制，3秒后自动消失）
---@param text string
function BattlefieldMap.ShowToast(text)
    if not text or text == "" then return end
    state_.toastText = text
    state_.toastTimer = 3.0
    print("[BattlefieldMap] ShowToast: " .. text)
end

--- 启动占领倒计时显示
---@param spName string 据点名称
---@param totalSec number 总时间（秒）
function BattlefieldMap.StartCaptureTimer(spName, totalSec)
    state_.captureActive = true
    state_.captureElapsed = 0
    state_.captureTotal = totalSec or 10
    state_.captureSpName = spName or ""
    print("[BattlefieldMap] StartCaptureTimer: " .. tostring(spName) .. " " .. tostring(totalSec) .. "s")
end

--- 停止占领倒计时（占领成功或失败时调用）
function BattlefieldMap.StopCaptureTimer()
    state_.captureActive = false
    state_.captureElapsed = 0
end


--- 显示确认对话框（在地图 NanoVG 层绘制）
---@param opts { title: string, message: string, onConfirm: function, onCancel: function? }
function BattlefieldMap.ShowConfirmDialog(opts)
    if not opts then return end
    state_.confirmDialog = {
        title = opts.title or "确认",
        message = opts.message or "",
        onConfirm = opts.onConfirm,
        onCancel = opts.onCancel,
    }
    state_.confirmBtnYes = nil
    state_.confirmBtnNo = nil
    print("[BattlefieldMap] ShowConfirmDialog: " .. (opts.title or ""))
end

--- 隐藏确认对话框
function BattlefieldMap.HideConfirmDialog()
    state_.confirmDialog = nil
    state_.confirmBtnYes = nil
    state_.confirmBtnNo = nil
end

--- 确认对话框是否正在显示
function BattlefieldMap.IsConfirmDialogVisible()
    return state_.confirmDialog ~= nil
end

return BattlefieldMap
