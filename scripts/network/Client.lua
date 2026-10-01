---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- network/Client.lua - 客户端主模块（武林豪侠传风格 MUD UI）
-- ============================================================================

---@diagnostic disable-next-line: undefined-global
local sdk = sdk  -- 引擎注入的全局 SDK 对象

local Client = {}
local Shared  = require("network.Shared")
local Settings = Shared.Settings
local EV = Settings.EVENTS

local UI = require("urhox-libs/UI")
local cjson = require("cjson")
local Theme = require("config.Theme")
local TC = Theme.C  -- 快捷引用调色板
local Tutorial = require("game.Tutorial")
local BattlefieldMap = require("network.BattlefieldMap")
local StrongholdPanel = require("network.StrongholdPanel")
local EntryFlow = require("network.EntryFlow")

-- ============================================================================
-- 前置声明（解决定义在后、使用在前的问题）
-- ============================================================================
local PlaySFX  -- 战斗音效播放，定义在 Client.Start() 附近

local BuildBattlefieldLayerPanel  -- 域外战场层选择面板，定义在后面
-- ============================================================================
-- 状态变量
-- ============================================================================

---@type table  玩家本地缓存数据
local player_ = nil
---@type table  背包物品列表
local inventory_ = {}
-- 交易阁状态（合并为单 table 节省 local 槽位）
local market_ = {
    listings      = {},       -- 交易阁列表
    history       = nil,      -- 我的交易记录（nil=未加载）
    page          = 1,        -- 当前页
    filterQuality = "all",    -- 品质筛选（"all"/"1"/"2"/"3"/"4"/"5"）
    sortBy        = "time_desc",-- 排序方式
    filterType    = "all",    -- 列表类型筛选（"all"/"mine"）
    fetched       = false,    -- 是否已发起过请求
    dataReceived  = false,    -- 数据是否已接收
    tab           = "browse", -- 当前Tab（"browse"/"sell"）
    sellIdx       = nil,      -- 上架选中的物品索引
    sellPrice     = 100,      -- 上架定价
    sellCurrency  = "silver", -- 上架货币类型
    trends        = nil,      -- 行情数据缓存
    pendingBuyId  = nil,      -- 待购买 listing id
}
---@type table|nil  管理员查询到的玩家信息
local adminPlayerInfo_ = nil
-- 管理员玩家列表（分页）
---@type table  当前页玩家列表数据
local adminPlayerList_      = nil
local adminPlayerListTotal_ = 0
local adminPlayerListPage_  = 1
local adminPlayerListMode_  = "online"   -- "online" | "all"
-- 管理员面板当前激活 tab（跨面板重建保持状态）
local adminPanelCurrentTab_ = 1   -- 1=传闻修改 2=玩家查询
-- 管理员查看的玩家详情目标（uid + 数据，nil 表示未打开详情）
---@type table|nil
local adminDetailTarget_ = nil

-- 服务器连接对象（Connected 事件后赋值）
---@type Connection
local serverConn_ = nil

-- 战斗状态
local inBattle_      = false
local battleLog_     = {}
-- 战斗面板动态数据（由 PUSH_BATTLE_STATE 填充）
---@type table
local battleState_   = nil   -- { myHp, myMp, myMaxHp, atkHp, atkMaxHp, atkName, round, autoFight }
local skillCooldowns_= {}    -- { [skillId] = remaining_rounds }
local autoFight_     = false -- 本地 auto-fight 镜像（20级前强制手动）
local pendingSkill_  = ""    -- 手动模式下已排队等待的技能 id（空字符串=无）
local battleSlots_   = {}    -- 从 player_.battle_slots 读取（战斗槽配置）
local npcDialog_     = nil   -- { npcName, dialog, options } 当前挂起的 NPC 对话（选项待响应）
-- NanoVG 战斗场景
---@type NVGContextWrapper
local vg_battle_     = nil   -- NanoVG 上下文（战斗场景用）
local battleNvgW_    = 0
local battleNvgH_    = 0     -- 场景区域高度（逻辑像素）
local battleNvgOffY_ = 0     -- 场景区域顶部偏移（回退值）
-- NanoVG 大地图（域外战场自由移动）
---@type NVGContextWrapper
local vg_map_        = nil   -- NanoVG 上下文（大地图用）
local mapNvgActive_  = false -- 地图 NanoVG 渲染激活标识
-- 战斗剪影贴图句柄（nvgCreateImage 返回值，-1 表示未加载）
local battleImg_ = {
    playerIdle = -1, playerRun = -1, playerAttack = -1, playerHurt = -1,
    monsterIdle = -1, monsterRun = -1, monsterAttack = -1, monsterHurt = -1,
}
---@type Widget
local battleSceneArea_ = nil -- sceneArea widget 引用，战斗结束时必须置 nil
-- 战斗动画状态机：phase=idle/run_to/hit/run_back，queue 是本回合要执行的动画段序列
local battleAnim_    = { phase = "idle", timer = 0, queue = {}, qidx = 1,
                         playerX = 0.25, monsterX = 0.75,
                         pendingFloat = {}, pendingFloatIdx = 1,
                         endPending = nil, endTimer = 0 }
local battleFloatDmg_= {}    -- 浮动伤害数字：{text,x,y,alpha,vy,color}
local lastBattleTime_= 0     -- 上一帧时间（动画 dt 用）
-- lastBattleResult 存放于 battleAnim_.lastResult（节省 local 槽位）
local logScrollPending_ = nil -- 日志面板重建后延迟滚动计数

-- 任务追踪状态（合并为单 table 以节省 local 槽位）
local questState_ = {
    active = nil,           -- Boss信息 (兼容旧字段)
    completeMsg = nil,      -- Boss击败弹窗文字
    completeMsgTimer = 0,   -- 弹窗倒计时
    -- 新任务系统
    mainQuest = nil,        -- {id, name, desc, chapter, progress, goal}
    dailyQuests = {},       -- {{id, progress, goal, claimed}, ...}
    maxLayer = 3,           -- 最大可用层
}

-- 当前面板枚举
local PANEL = {
    MAIN      = "main",     -- 主场景面板（默认：场景导航）
    MAP       = "map",      -- 地图/移动（全屏）
    SKILLS    = "skills",   -- 角色（底部子面板）
    CULTIVATE = "cultivate",-- 修炼（底部子面板）
    INVENTORY = "inventory",-- 背包（全屏）
    MARKET    = "market",   -- 交易阁（全屏）
    BATTLE    = "battle",   -- 战斗（战斗中全屏，否则子面板）
    SHOP      = "shop",     -- NPC 商店（全屏）
    ADMIN     = "admin",    -- 管理员面板（全屏）
    ADMIN_SELL= "admin_sell",-- 管理员上架（全屏）
    JIANGHU   = "jianghu",  -- 江湖（底部子面板）
    CHAT      = "chat",     -- 聊天（底部子面板）
    SETTINGS  = "settings", -- 设置（底部子面板）
    REALM_PILL= "realm_pill",-- 修为丹药铺（全屏）
}

-- UI 就绪标志：UI.SetRoot() 完成后置为 true
local uiReady_ = false
local entryFlowActive_ = false  -- 进入游戏流程是否激活中

-- 待处理数据缓存：UI 就绪前收到的服务器消息先存这里
local pendingEvents_ = {}  -- { {handler, snap}, ... }

-- 最新传闻文本缓存（解决 PUSH_NEWS_UPDATE 到达时 UI 未就绪的时序问题）
local latestNews_ = "交流提意见进Q群：584352243"

-- 游戏时间（秒，用于计算时辰）
local gameTimeElapsed_ = 0
local timeUpdateTimer_ = 0
local currentSpot_     = nil   -- 当前所在小地点 id（场景内导航高亮）
local lastScene_       = nil   -- 上次 UpdateStatusBar 中检测到的场景 id（用于场景切换判定）
local sameSpotPlayers_ = {}   -- 同小地点玩家列表 { {name, spot}, ... }

-- 子面板配置（定义在此处供 SwitchPanel 提前引用）
local NAV_PANELS = {
    [PANEL.SKILLS]    = { title = "角色", subs = {"背包","属性","称号"} },
    [PANEL.CULTIVATE] = { title = "修炼", subs = {"武学","打坐","炼丹","炼器"} },
    [PANEL.BATTLE]    = { title = "战斗", subs = {"战报"} },
    [PANEL.JIANGHU]   = { title = "江湖", subs = {"排名","好友","帮会","门派","藏书阁","天梯"} },
    [PANEL.CHAT]      = { title = "聊天", subs = {"世界","门派","帮会频道","私信","系统"} },
    [PANEL.SETTINGS]  = { title = "设置", subs = {"音效","账号","帮助"} },
}

-- 前向声明（定义在文件后半段，早期代码中调用需提前声明）
local FlushPendingEvents
local BuildLogPanel
local RebuildMainContent
local BuildSceneNav
local BuildNavSubPanel
local SendToServer

-- 场景 ID → 显示名（提前定义，供 BuildMapPanel 等早期函数使用）
local SCENE_NAMES = {
    battlefield     = "域外战场",
    main_city       = "扬州城",
    sword_sect      = "剑宗",
    iron_sect       = "铁壁宗",
    medicine_sect   = "药王谷",
    shadow_sect     = "天影楼",
    qidan_sect      = "器丹宗",
    ancient_village = "古　村",
}

-- 门派显示名辅助函数（从 Settings.SECT_INFO 读取，避免硬编码）
local function GetSectDisplay(sectId)
    if not sectId or sectId == "" then return "无门无派" end
    local info = Settings.SECT_INFO and Settings.SECT_INFO[sectId]
    return info and info.display or sectId
end
local function GetSectShort(sectId)
    if not sectId or sectId == "" then return "散修" end
    local info = Settings.SECT_INFO and Settings.SECT_INFO[sectId]
    return info and info.short or sectId
end
local function GetSectColor(sectId)
    local info = Settings.SECT_INFO and Settings.SECT_INFO[sectId]
    if info and info.color then
        return { info.color[1], info.color[2], info.color[3], 255 }
    end
    return { 200, 180, 120, 255 }
end

-- 当前 NPC 商店数据（PUSH_SHOP_DATA 后填充）
local shopData_ = {
    shopType  = "",
    shopTitle = "商店",
    items     = {},
    currency  = "silver",
}
local currentPanel_ = PANEL.MAIN
local currentSubTab_ = {}  -- 记住各面板当前子 tab, e.g. currentSubTab_[PANEL.CULTIVATE] = "打坐"
local viewingBattlefieldLayers_ = false  -- 正在查看域外战场层面板（防止自动刷新覆盖）

---@type {skillId: string, value: integer}|nil
local cultivateSlider_ = nil  -- 打坐滑条状态（非nil时表示滑条展开中）

-- ============================================================================
-- UI 控件引用（动态更新用）
-- ============================================================================

---@type table  UI组件根引用
local ui_ = {
    -- 顶部新闻滚动文字
    newsLabel    = nil,
    newsText     = nil,   -- 传闻 Label 控件（用于实时更新文字）
    -- 场景标题区
    sceneTitle   = nil,   -- 场景大字标题
    sceneLabel   = nil,   -- 旧兼容引用（指向 sceneTitle）
    timeLabel    = nil,   -- 时辰标签（灯笼+卯时）
    -- 场景氛围描述
    sceneDesc    = nil,   -- 青色场景氛围文字
    -- 主日志区域（ScrollView）
    logScroll    = nil,
    logContent   = nil,
    -- 状态栏进度条
    hpBar        = nil,   -- 气血进度条填充块
    mpBar        = nil,   -- 内力进度条填充块
    hpLabel      = nil,   -- 气血文字
    mpLabel      = nil,   -- 内力文字
    -- 全屏 overlay（弹出层）
    overlay      = nil,   -- 整个遮罩 Panel
    overlayTitle = nil,   -- overlay 标题文字
    overlayBody  = nil,   -- overlay 内容容器
    -- NPC按钮区域
    npcPanel     = nil,
    -- 主内容区（动态切换）
    mainArea     = nil,
    -- 左侧同地点玩家列
    playerListCol = nil,
    -- 底部可换区（场景导航 or 子面板）
    bottomSection = nil,
    -- 全屏地图时需隐藏的外围 bar
    sceneBar     = nil,
    statusBar    = nil,
    navBar       = nil,
    -- 大境界进度百分比
    realmPctLabel = nil,
    -- 兼容旧代码
    statusLabel  = nil,
    panelContainer = nil,
}

-- 日志文字颜色（精致古风）
local LOG_COLOR = {
    system  = TC.success,              -- 翠玉绿（系统/战报）
    info    = TC.textPrimary,          -- 暖绢色（普通信息）
    good    = { 100, 200, 130, 255 },  -- 灵翠（好消息/获得物品）
    warn    = TC.warning,              -- 琥珀金（警告/提示）
    danger  = TC.danger,               -- 朱砂赤（受伤/危险）
    gold    = TC.textTitle,            -- 鎏金（稀有物品/特殊）
    title   = TC.textAccent,           -- 金辉（场景名/标题）
}

-- 日志行列表（{text, color}）
local logLines_ = {}

-- 渲染单行日志到指定容器（含颜色标签解析）
local function RenderLogLine(parent, line)
    local TAGS = {
        { open = "<金>", close = "</金>", c = {210,180,60,255} },
        { open = "<黄>", close = "</黄>", c = {220,185,60,255} },
        { open = "<红>", close = "</红>", c = {220,75,70,255} },
        { open = "<绿>", close = "</绿>", c = {80,200,120,255} },
    }
    if line.loot then
        local lootData = line.loot
        local captured_token = lootData.token
        local captured_name  = lootData.name
        local lootBtn = UI.Button {
            text = "  ✦ " .. lootData.name .. "  （点击拾取）",
            fontSize = 16,
            color = TC.textTitle,
            backgroundColor = TC.bgPanel,
            borderWidth = 1,
            borderColor = TC.borderGold,
            height = 28,
            marginBottom = 2,
            paddingHorizontal = 8,
            flexShrink = 0,
            onClick = function(self_btn)
                self_btn.text = "  ✦ " .. captured_name .. "  （已拾取）"
                self_btn.color = TC.textMuted
                self_btn.backgroundColor = TC.bgOverlay
                self_btn.borderColor = TC.borderLight
                SendToServer(EV.REQ_PICKUP_LOOT, { Token = captured_token })
                Tutorial.Advance("loot_picked")
            end,
        }
        Tutorial.RegisterTarget("loot_link", lootBtn)
        parent:AddChild(lootBtn)
        return
    end
    -- 检查是否包含颜色标签
    local hasTag = line.text and (
        line.text:find("<金>", 1, true) or line.text:find("<黄>", 1, true) or
        line.text:find("<红>", 1, true) or line.text:find("<绿>", 1, true))
    if hasTag then
        local segments = {}
        local pos = 1
        local src = line.text
        local srcLen = #src
        while pos <= srcLen do
            local bestS, bestE, bestTag = nil, nil, nil
            for _, tg in ipairs(TAGS) do
                local s, e = src:find(tg.open, pos, true)
                if s and (not bestS or s < bestS) then
                    bestS, bestE, bestTag = s, e, tg
                end
            end
            if bestS then
                if bestS > pos then
                    table.insert(segments, { t = src:sub(pos, bestS - 1), c = line.color })
                end
                local cs, ce = src:find(bestTag.close, bestE + 1, true)
                if cs then
                    local inner = src:sub(bestE + 1, cs - 1)
                    if #inner > 0 then
                        table.insert(segments, { t = inner, c = bestTag.c })
                    end
                    pos = ce + 1
                else
                    local inner = src:sub(bestE + 1)
                    if #inner > 0 then
                        table.insert(segments, { t = inner, c = bestTag.c })
                    end
                    pos = srcLen + 1
                end
            else
                table.insert(segments, { t = src:sub(pos), c = line.color })
                pos = srcLen + 1
            end
        end
        local row = UI.Panel {
            flexDirection = "row",
            flexWrap = "wrap",
            marginBottom = 2,
            flexShrink = 0,
        }
        for _, seg in ipairs(segments) do
            row:AddChild(UI.Label {
                text = seg.t,
                fontSize = 16,
                color = seg.c,
            })
        end
        parent:AddChild(row)
    else
        parent:AddChild(UI.Label {
            text = line.text,
            fontSize = 16,
            color = line.color,
            marginBottom = 2,
            flexShrink = 0,
        })
    end
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

local function AddLog(text, colorKey)
    local color = LOG_COLOR[colorKey or "info"]
    table.insert(logLines_, { text = text, color = color })
    if #logLines_ > 100 then
        table.remove(logLines_, 1)
    end
    -- 刷新日志显示
    if ui_.logContent then
        ui_.logContent:ClearChildren()
        for _, line in ipairs(logLines_) do
            RenderLogLine(ui_.logContent, line)
        end
        -- 滚动到底部（延迟多帧等 Yoga 布局完成）
        if ui_.logScroll then
            ui_.logScroll:ScrollToBottom()
        end
        logScrollPending_ = 10
    end
end

-- 在日志区添加可点击的战利品拾取链接
local function AddLootLink(itemName, token)
    -- 存入 logLines_ 以便重建时恢复（标记为 loot 类型）
    table.insert(logLines_, { text = nil, loot = { name = itemName, token = token } })
    if #logLines_ > 100 then
        table.remove(logLines_, 1)
    end

    if not ui_.logContent then return end

    -- 创建可点击按钮样式的日志条目
    local captured_token = token
    local captured_name  = itemName
    local lootBtn = UI.Button {
        text = "  ✦ " .. itemName .. "  （点击拾取）",
        fontSize = 16,
        color = TC.textTitle,
        backgroundColor = TC.bgPanel,
        borderWidth = 1,
        borderColor = TC.borderGold,
        height = 28,
        marginBottom = 2,
        paddingHorizontal = 8,
        flexShrink = 0,
        onClick = function(self_btn)
            -- 置灰防止重复点击
            self_btn.text = "  ✦ " .. captured_name .. "  （已拾取）"
            self_btn.color = TC.textMuted
            self_btn.backgroundColor = TC.bgOverlay
            self_btn.borderColor = TC.borderLight
            SendToServer(EV.REQ_PICKUP_LOOT, { Token = captured_token })
            Tutorial.Advance("loot_picked")
        end,
    }
    -- 注册为教程高亮目标（覆盖之前的）
    Tutorial.RegisterTarget("loot_link", lootBtn)
    ui_.logContent:AddChild(lootBtn)

    if ui_.logScroll then
        ui_.logScroll:ScrollToBottom()
    end
    logScrollPending_ = 10
end

SendToServer = function(eventName, data)
    if not serverConn_ then
        print("[Client] 警告：尚未连接服务器，无法发送 " .. eventName)
        return
    end
    local vm = VariantMap()
    if data then
        for k, v in pairs(data) do
            if type(v) == "string" then
                vm:SetString(k, v)
            elseif type(v) == "number" then
                if math.type(v) == "integer" then
                    if v > 2147483647 or v < -2147483648 then
                        vm:SetInt64(k, v)
                    else
                        vm:SetInt(k, v)
                    end
                else
                    vm:SetFloat(k, v)
                end
            elseif type(v) == "boolean" then
                vm:SetBool(k, v)
            elseif type(v) == "table" then
                vm:SetString(k, cjson.encode(v))
            end
        end
    end
    serverConn_:SendRemoteEvent(eventName, true, vm)
end

local function QualityColor(quality)
    local qc = {
        common    = { 200, 200, 200, 255 },
        uncommon  = { 80,  220, 80,  255 },
        rare      = { 60,  120, 240, 255 },
        epic      = { 160, 60,  240, 255 },
        legendary = { 255, 140, 0,   255 },
        divine    = { 255, 80,  80,  255 },
    }
    return qc[quality] or qc.common
end

local function QualityName(quality)
    local qn = {
        common    = "白",
        uncommon  = "绿",
        rare      = "蓝",
        epic      = "紫",
        legendary = "橙",
        divine    = "红",
    }
    return "[" .. (qn[quality] or "白") .. "]"
end

local function FormatSilver(amount)
    if amount >= 10000 then
        return string.format("%.1f万两", amount / 10000)
    end
    return amount .. "两"
end

-- ============================================================================
-- UI 面板构建函数
-- ============================================================================

-- 构建 NPC 按钮面板（左侧，按当前场景 + 当前小地点过滤）
local function BuildNpcPanel()
    if not ui_.npcPanel then return end
    ui_.npcPanel:ClearChildren()

    -- 如果有挂起的 NPC 对话选项，优先渲染对话界面
    if npcDialog_ and npcDialog_.options then
        local dlg = npcDialog_
        -- NPC 姓名标题
        ui_.npcPanel:AddChild(UI.Label {
            text = "【" .. (dlg.npcName or "???") .. "】",
            fontSize = 13,
            color = TC.textTitle,
            textAlign = "center",
            width = "100%",
            marginBottom = 4,
        })
        -- 选项按钮
        for _, opt in ipairs(dlg.options) do
            local isBattle = (opt.action == "battle")
            ui_.npcPanel:AddChild(UI.Button {
                text = opt.text,
                width = "100%",
                height = 38,
                fontSize = 15,
                backgroundColor = isBattle and TC.btnPrimary or TC.bgPanel,
                borderWidth = 1,
                borderColor   = isBattle and TC.danger or TC.border,
                marginBottom = 5,
                onClick = function()
                    if opt.action == "battle" then
                        AddLog(">> 你挺身而出，迎向挑战！", "danger")
                        npcDialog_  = nil
                        inBattle_   = true
                        battleState_    = nil
                        skillCooldowns_ = {}
                        SendToServer(EV.REQ_START_BATTLE, { MonsterId = opt.data })
                        Client.SwitchPanel(PANEL.BATTLE)
                    elseif opt.action == "tutorial_accept" then
                        -- 接受老村长任务：通知服务端推进 tutorial_step
                        AddLog(">> 你拱手应诺：晚辈愿意效劳！", "info")
                        npcDialog_ = nil
                        SendToServer(EV.REQ_NPC_OPTION, {
                            NpcId  = dlg.npcName == "老村长" and "village_elder" or (opt.npcId or ""),
                            Action = "tutorial_accept",
                            Data   = "",
                        })
                        -- 立即本地推进（不等服务端 PushPlayerData）
                        if player_ then player_.tutorial_step = 1 end
                        Tutorial.Advance("tutorial_accepted")
                        BuildNpcPanel()
                    elseif opt.action == "learn_skill" then
                        -- 向长老学习功法
                        AddLog(">> 你躬身行礼：「弟子恭聆长老传功！」", "info")
                        npcDialog_ = nil
                        SendToServer(EV.REQ_NPC_OPTION, {
                            NpcId  = opt.npcId or "",
                            Action = "learn_skill",
                            Data   = opt.data or "",
                        })
                        BuildNpcPanel()
                    elseif opt.action == "trial_accept" then
                        -- 接受宗门试炼
                        AddLog(">> 你抱拳道：「弟子愿往！」", "info")
                        npcDialog_ = nil
                        SendToServer(EV.REQ_NPC_OPTION, {
                            NpcId  = opt.npcId or "",
                            Action = "trial_accept",
                            Data   = opt.data or "",
                        })
                        BuildNpcPanel()
                    elseif opt.action == "trial_abandon" then
                        -- 放弃试炼
                        AddLog(">> 你摇了摇头，决定暂时放下。", "info")
                        npcDialog_ = nil
                        SendToServer(EV.REQ_NPC_OPTION, {
                            NpcId  = opt.npcId or "",
                            Action = "trial_abandon",
                            Data   = opt.data or "",
                        })
                        BuildNpcPanel()
                    elseif opt.action == "trial_join" then
                        -- 通过试炼，正式拜入门派
                        AddLog(">> 你撩袍跪地：「弟子叩谢师恩！」", "info")
                        npcDialog_ = nil
                        SendToServer(EV.REQ_NPC_OPTION, {
                            NpcId  = opt.npcId or "",
                            Action = "trial_join",
                            Data   = opt.data or "",
                        })
                        BuildNpcPanel()
                    elseif opt.action == "close" or opt.action == "leave" then
                        -- 关闭对话 / 离开
                        AddLog(">> 你转身离去。", "info")
                        npcDialog_ = nil
                        -- 若正处于教程复命阶段（step刚变为3），服务端已推进，此时结束引导覆盖层（仅触发一次）
                        if dlg.npcName == "老村长" and player_ and (player_.tutorial_step or 0) >= 3
                            and not questState_.elderDialogDone then
                            questState_.elderDialogDone = true
                            Tutorial.Advance("elder_dialog_complete")
                            AddLog("<黄>【提示】修炼之路刚刚开始，查看「任务」了解下一步目标！</黄>", "info")
                            questState_.guideTimer = 1.5
                        end
                        BuildNpcPanel()
                    else
                        -- 通用 action：发送到服务端处理
                        npcDialog_ = nil
                        SendToServer(EV.REQ_NPC_OPTION, {
                            NpcId  = opt.npcId or "",
                            Action = opt.action or "",
                            Data   = opt.data or "",
                        })
                        BuildNpcPanel()
                    end
                end,
            })
        end
        return
    end

    local scene    = player_ and player_.scene or "ancient_village"
    local allNpcs  = Settings.NPCS[scene] or {}
    -- 按当前所在小地点过滤；无地点时显示提示
    local visible = {}
    if currentSpot_ then
        for _, npc in ipairs(allNpcs) do
            if npc.spot == currentSpot_ then
                visible[#visible + 1] = npc
            end
        end
    end
    if not currentSpot_ then
        ui_.npcPanel:AddChild(UI.Label {
            text = "选择地点后显示人物",
            fontSize = 13,
            color = TC.textMuted,
            textAlign = "center",
            paddingVertical = 6,
            width = "100%",
        })
    elseif #visible == 0 then
        ui_.npcPanel:AddChild(UI.Label {
            text = "此处无人",
            fontSize = 13,
            color = TC.textMuted,
            textAlign = "center",
            paddingVertical = 6,
            width = "100%",
        })
    else
        -- 标题行
        ui_.npcPanel:AddChild(UI.Label {
            text = Theme.ORNAMENT.sectionLeft .. "此处人物" .. Theme.ORNAMENT.sectionRight,
            fontSize = 13,
            fontWeight = "bold",
            color = TC.textTitle,
            textAlign = "center",
            width = "100%",
            marginBottom = 6,
        })
        for _, npc in ipairs(visible) do
            local capturedNpc = npc
            local npcBtn = UI.Button {
                text = Theme.ORNAMENT.bullet .. npc.name,
                height = 38,
                paddingHorizontal = 16,
                fontSize = 16,
                fontWeight = "bold",
                borderRadius = 19,
                backgroundColor = TC.bgPanel,
                borderWidth = 1,
                borderColor = TC.border,
                color = TC.textPrimary,
                marginRight = 6,
                marginBottom = 6,
                onClick = function()
                    AddLog(">> 向 " .. capturedNpc.name .. " 搭话...", "info")
                    if capturedNpc.id == "village_elder" then
                        Tutorial.Advance("npc_elder_talked")
                    end
                    SendToServer(EV.REQ_INTERACT_NPC, { NpcId = capturedNpc.id })
                end,
            }
            -- 注册老村长按钮为教程目标（步骤1：新手找老村长；步骤14：复命）
            if npc.id == "village_elder" then
                Tutorial.RegisterTarget("npc_村长", npcBtn)
            end
            ui_.npcPanel:AddChild(npcBtn)
        end
    end

    -- ── 教程引导怪物：竹林 + tutorial_step==1 时显示迷失幼妖 ──
    local tutStep = player_ and (player_.tutorial_step or 0) or 0
    if currentSpot_ == "bamboo_grove" and tutStep == 1 then
        ui_.npcPanel:AddChild(UI.Label {
            text = Theme.ORNAMENT.sectionLeft .. "此处妖兽" .. Theme.ORNAMENT.sectionRight,
            fontSize = 13,
            fontWeight = "bold",
            color = TC.danger,
            textAlign = "center",
            width = "100%",
            marginTop = 8,
            marginBottom = 6,
        })
        local monsterBtn = UI.Button {
            text = Theme.ORNAMENT.diamond .. " 迷失幼妖 [驱散]",
            height = 38,
            paddingHorizontal = 16,
            fontSize = 16,
            fontWeight = "bold",
            borderRadius = 19,
            backgroundColor = TC.btnPrimary,
            borderWidth = 1,
            borderColor = TC.borderGold,
            color = TC.textAccent,
            marginRight = 6,
            marginBottom = 6,
            onClick = function()
                AddLog(">> 向 迷失幼妖 发起挑战！", "warn")
                SendToServer(EV.REQ_START_BATTLE, { MonsterId = "tutorial_beast" })
                inBattle_ = true
                battleState_ = nil
                skillCooldowns_ = {}
                RebuildMainContent()
            end,
        }
        Tutorial.RegisterTarget("battle_迷失幼妖", monsterBtn)
        ui_.npcPanel:AddChild(monsterBtn)
    end
end

-- 刷新左侧同地点玩家列
local function RefreshPlayerList()
    if not ui_.playerListCol then return end
    ui_.playerListCol:ClearChildren()

    if not currentSpot_ then
        -- 未选地点：显示占位图标
        ui_.playerListCol:AddChild(UI.Label {
            text = "人",
            fontSize = 13,
            color = TC.textMuted,
            textAlign = "center",
            width = "100%",
        })
        return
    end

    -- 过滤出与自己同地点的其他玩家
    local selfName = player_ and player_.name or ""
    local shown = 0
    for _, p in ipairs(sameSpotPlayers_) do
        if p.spot == currentSpot_ and p.name ~= selfName then
            -- 名字取前3个字符（汉字），UTF-8 汉字3字节，取3字 = 9字节
            local shortName = p.name:sub(1, 9)
            local pill = UI.Panel {
                width = 60,
                flexShrink = 0,
                flexDirection = "column",
                alignItems = "center",
                paddingVertical = 3,
                paddingHorizontal = 2,
                backgroundColor = TC.bgOverlay,
                borderWidth = 1,
                borderColor = TC.borderLight,
            }
            pill:AddChild(UI.Label {
                text = "👤",
                fontSize = 14,
                textAlign = "center",
                color = TC.textPrimary,
            })
            pill:AddChild(UI.Label {
                text = shortName,
                fontSize = 11,
                textAlign = "center",
                color = TC.textSecondary,
                width = 58,
            })
            ui_.playerListCol:AddChild(pill)
            shown = shown + 1
        end
    end

    -- 无他人时显示空提示
    if shown == 0 then
        ui_.playerListCol:AddChild(UI.Label {
            text = "┄",
            fontSize = 12,
            color = TC.textMuted,
            textAlign = "center",
            width = "100%",
            marginTop = 8,
        })
    end
end

-- 构建怪物列表面板（新手野外战斗入口）
-- ── 水墨武侠剪影绘制系统（浅色水墨风，纯黑剪影）────────────
-- 纯黑填充辅助
local function InkFill(vg, r, g, b, a, spread)
    -- 忽略 r,g,b，统一用近黑色
    nvgFillColor(vg, nvgRGBAf(0.05, 0.04, 0.04, a))
    nvgFill(vg)
    -- spread 参数保留兼容，不再输出晕边（浅背景下不需要）
end

-- ── 是否妖兽型敌人（用于选剪影形态）─────────────────────────
local function IsBeastEnemy(name)
    if not name then return false end
    local keywords = {"妖","兽","魔","鬼","虎","狼","蛇","熊","龙","狐","怪","兽"}
    for _, kw in ipairs(keywords) do
        if name:find(kw, 1, true) then return true end
    end
    return false
end

-- ── 动画队列系统 ─────────────────────────────────────────────
-- 每个队列元素：{ who="player"|"monster", phase="run_to"|"hit"|"run_back", dur=秒 }
-- 动画参数常量
local ANIM = {
    RUN_TO   = 0.40,  -- 冲向对方
    HIT      = 0.15,  -- 命中停顿
    RUN_BACK = 0.30,  -- 返回
    -- X 比例（相对场景宽度）
    P_BASE   = 0.18,  M_BASE  = 0.82,
    P_ATK    = 0.44,  M_ATK   = 0.56,
}

-- 触发一回合动画队列；firstAtk = "player"|"monster"|"none"
local function TriggerRoundAnim(firstAtk)
    local q = {}
    local function addSeq(who)
        local runTo  = { who=who, phase="run_to",   dur=ANIM.RUN_TO   }
        local hit    = { who=who, phase="hit",       dur=ANIM.HIT      }
        local runBk  = { who=who, phase="run_back",  dur=ANIM.RUN_BACK }
        q[#q+1] = runTo
        q[#q+1] = hit
        q[#q+1] = runBk
    end
    -- 读取当前 HP 判断是否已死亡
    local playerAlive  = battleState_ and battleState_.myHp  > 0
    local monsterAlive = battleState_ and battleState_.atkHp > 0
    if firstAtk == "none" then
        -- 战斗开始，不播放攻击动画
    elseif firstAtk == "monster" then
        if monsterAlive then addSeq("monster") end
        if playerAlive  then addSeq("player")  end
    else
        if playerAlive  then addSeq("player")  end
        if monsterAlive then addSeq("monster") end
    end
    battleAnim_.queue = q
    battleAnim_.qidx  = 1
    battleAnim_.timer = (q[1] and q[1].dur) or 0
    battleAnim_.phase = (q[1] and q[1].phase) or "idle"
    -- 重置 X 位置到基础站位
    battleAnim_.playerX  = ANIM.P_BASE
    battleAnim_.monsterX = ANIM.M_BASE
end

-- 绘制水墨剑客（主角，持剑前倾攻击姿）
local function DrawInkSwordsman(vg, h, r, g, b, a)
    local u = h / 12.0
    -- 浅背景下不需要底晕，直接绘制剑客形体

    -- ── 斗笠（三角帽沿）──────────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 2.8, -h * 0.48)
    nvgLineTo(vg,  u * 2.2, -h * 0.48)
    nvgLineTo(vg,  u * 0.3, -h * 0.60)
    nvgClosePath(vg)
    InkFill(vg, r*0.5, g*0.5, b*0.5, a)
    -- 帽顶
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 0.4, -h * 0.60)
    nvgLineTo(vg,  u * 1.0, -h * 0.60)
    nvgLineTo(vg,  u * 0.5, -h * 0.70)
    nvgClosePath(vg)
    InkFill(vg, r*0.5, g*0.5, b*0.5, a)

    -- ── 头部 ─────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgCircle(vg, u * 0.3, -h * 0.44, u * 1.05)
    InkFill(vg, r, g, b, a, 1)

    -- ── 颈 ───────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, -u * 0.1, -h * 0.375, u * 0.7, u * 0.9)
    InkFill(vg, r, g, b, a)

    -- ── 躯干（前倾姿势，重心向右）────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 1.1, -h * 0.32)
    nvgLineTo(vg,  u * 1.6, -h * 0.30)
    nvgLineTo(vg,  u * 1.3,  h * 0.05)
    nvgLineTo(vg, -u * 0.9,  h * 0.04)
    nvgClosePath(vg)
    InkFill(vg, r, g, b, a)

    -- ── 披风（向后飘逸）──────────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 1.1, -h * 0.30)
    nvgLineTo(vg, -u * 3.2, -h * 0.10)
    nvgLineTo(vg, -u * 3.5,  h * 0.18)
    nvgLineTo(vg, -u * 2.8,  h * 0.22)
    nvgLineTo(vg, -u * 0.9,  h * 0.04)
    nvgClosePath(vg)
    InkFill(vg, r*0.7, g*0.7, b*0.7, a * 0.80)

    -- ── 右臂（持剑前刺，斜向右上）────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg,  u * 1.5, -h * 0.28)
    nvgLineTo(vg,  u * 3.8, -h * 0.40)
    nvgLineTo(vg,  u * 3.4, -h * 0.28)
    nvgLineTo(vg,  u * 1.1, -h * 0.16)
    nvgClosePath(vg)
    InkFill(vg, r, g, b, a)

    -- ── 剑（右臂延伸，细长）──────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg,  u * 3.6, -h * 0.42)
    nvgLineTo(vg,  u * 5.8, -h * 0.54)
    nvgLineTo(vg,  u * 5.6, -h * 0.46)
    nvgLineTo(vg,  u * 3.4, -h * 0.34)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(r*1.2, g*1.2, b*1.2, a * 0.9))
    nvgFill(vg)
    -- 剑尖高光
    nvgBeginPath(vg)
    nvgMoveTo(vg,  u * 5.6, -h * 0.52)
    nvgLineTo(vg,  u * 6.5, -h * 0.58)
    nvgLineTo(vg,  u * 6.2, -h * 0.50)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBAf(1.0, 1.0, 1.0, a * 0.5))
    nvgFill(vg)

    -- ── 左臂（后撑平衡）──────────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 1.0, -h * 0.28)
    nvgLineTo(vg, -u * 2.6,  h * 0.06)
    nvgLineTo(vg, -u * 2.0,  h * 0.15)
    nvgLineTo(vg, -u * 0.5, -h * 0.10)
    nvgClosePath(vg)
    InkFill(vg, r, g, b, a)

    -- ── 腰带 ─────────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, -u * 0.9, h * 0.02, u * 2.2, u * 0.55)
    InkFill(vg, r*0.55, g*0.55, b*0.55, a)

    -- ── 弓步前腿（右腿踏出）──────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg,  u * 0.3,  h * 0.06)
    nvgLineTo(vg,  u * 1.4,  h * 0.50)
    nvgLineTo(vg,  u * 2.2,  h * 0.50)
    nvgLineTo(vg,  u * 1.2,  h * 0.06)
    nvgClosePath(vg)
    InkFill(vg, r, g, b, a)

    -- ── 弓步后腿（左腿蹬直）──────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 0.7,  h * 0.06)
    nvgLineTo(vg, -u * 1.8,  h * 0.50)
    nvgLineTo(vg, -u * 0.9,  h * 0.50)
    nvgLineTo(vg,  u * 0.1,  h * 0.06)
    nvgClosePath(vg)
    InkFill(vg, r, g, b, a)

    -- 前脚
    nvgBeginPath(vg)
    nvgMoveTo(vg,  u * 1.4,  h * 0.50)
    nvgLineTo(vg,  u * 1.2,  h * 0.50 + u * 0.45)
    nvgLineTo(vg,  u * 2.5,  h * 0.50 + u * 0.45)
    nvgLineTo(vg,  u * 2.7,  h * 0.50)
    nvgClosePath(vg)
    InkFill(vg, r*0.8, g*0.8, b*0.8, a)
    -- 后脚
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 1.8,  h * 0.50)
    nvgLineTo(vg, -u * 2.2,  h * 0.50 + u * 0.45)
    nvgLineTo(vg, -u * 0.7,  h * 0.50 + u * 0.45)
    nvgLineTo(vg, -u * 0.7,  h * 0.50)
    nvgClosePath(vg)
    InkFill(vg, r*0.8, g*0.8, b*0.8, a)
end

-- 绘制水墨妖兽（弓腰持爪前扑姿）
local function DrawInkMonster(vg, h, r, g, b, a)
    local u = h / 12.0
    -- 浅背景下不需要底晕，直接绘制妖兽形体

    -- ── 头部（低垂凶相）──────────────────────────────────
    nvgBeginPath(vg)
    nvgCircle(vg, -u * 0.4, -h * 0.34, u * 1.15)
    InkFill(vg, r, g, b, a, 1)
    -- 角（两侧尖突）
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 1.1, -h * 0.41)
    nvgLineTo(vg, -u * 2.0, -h * 0.52)
    nvgLineTo(vg, -u * 0.9, -h * 0.44)
    nvgClosePath(vg)
    InkFill(vg, r*0.8, g*0.6, b*0.6, a)
    nvgBeginPath(vg)
    nvgMoveTo(vg,  u * 0.4, -h * 0.41)
    nvgLineTo(vg,  u * 1.1, -h * 0.52)
    nvgLineTo(vg,  u * 0.3, -h * 0.44)
    nvgClosePath(vg)
    InkFill(vg, r*0.8, g*0.6, b*0.6, a)

    -- ── 颈（粗短）────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, -u * 0.7, -h * 0.22, u * 1.0, u * 0.9)
    InkFill(vg, r, g, b, a)

    -- ── 躯干（弓背前倾）──────────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 1.8, -h * 0.20)
    nvgLineTo(vg,  u * 1.5, -h * 0.18)
    nvgLineTo(vg,  u * 1.8,  h * 0.10)
    nvgLineTo(vg, -u * 1.5,  h * 0.12)
    nvgClosePath(vg)
    InkFill(vg, r, g, b, a)

    -- ── 右爪（前伸抓击）──────────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg,  u * 1.4, -h * 0.16)
    nvgLineTo(vg,  u * 3.5, -h * 0.08)
    nvgLineTo(vg,  u * 3.2,  h * 0.05)
    nvgLineTo(vg,  u * 1.1,  h * 0.00)
    nvgClosePath(vg)
    InkFill(vg, r, g, b, a)
    -- 爪尖（三指）
    for ci = -1, 1 do
        nvgBeginPath(vg)
        nvgMoveTo(vg,  u * (3.4 + ci * 0.25), -h * 0.10)
        nvgLineTo(vg,  u * (4.4 + ci * 0.35),  h * 0.02)
        nvgLineTo(vg,  u * (3.9 + ci * 0.30),  h * 0.06)
        nvgClosePath(vg)
        InkFill(vg, r*1.1, g*0.7, b*0.7, a)
    end

    -- ── 左爪（侧撑）──────────────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 1.6, -h * 0.16)
    nvgLineTo(vg, -u * 3.2,  h * 0.10)
    nvgLineTo(vg, -u * 2.7,  h * 0.20)
    nvgLineTo(vg, -u * 1.1,  h * 0.00)
    nvgClosePath(vg)
    InkFill(vg, r, g, b, a)

    -- ── 腰带/腰甲 ────────────────────────────────────────
    nvgBeginPath(vg)
    nvgRect(vg, -u * 1.5, h * 0.08, u * 3.0, u * 0.50)
    InkFill(vg, r*0.55, g*0.45, b*0.45, a)

    -- ── 后腿（蹲势，宽腿分站）────────────────────────────
    -- 右腿
    nvgBeginPath(vg)
    nvgMoveTo(vg,  u * 0.5,  h * 0.14)
    nvgLineTo(vg,  u * 1.6,  h * 0.50)
    nvgLineTo(vg,  u * 2.4,  h * 0.50)
    nvgLineTo(vg,  u * 1.4,  h * 0.14)
    nvgClosePath(vg)
    InkFill(vg, r, g, b, a)
    -- 左腿
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 1.3,  h * 0.14)
    nvgLineTo(vg, -u * 2.2,  h * 0.50)
    nvgLineTo(vg, -u * 1.0,  h * 0.50)
    nvgLineTo(vg, -u * 0.3,  h * 0.14)
    nvgClosePath(vg)
    InkFill(vg, r, g, b, a)
    -- 右脚
    nvgBeginPath(vg)
    nvgMoveTo(vg,  u * 1.6,  h * 0.50)
    nvgLineTo(vg,  u * 1.4,  h * 0.50 + u * 0.45)
    nvgLineTo(vg,  u * 2.8,  h * 0.50 + u * 0.45)
    nvgLineTo(vg,  u * 2.8,  h * 0.50)
    nvgClosePath(vg)
    InkFill(vg, r*0.8, g*0.7, b*0.7, a)
    -- 左脚
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 2.2,  h * 0.50)
    nvgLineTo(vg, -u * 2.8,  h * 0.50 + u * 0.45)
    nvgLineTo(vg, -u * 0.8,  h * 0.50 + u * 0.45)
    nvgLineTo(vg, -u * 0.8,  h * 0.50)
    nvgClosePath(vg)
    InkFill(vg, r*0.8, g*0.7, b*0.7, a)

    -- ── 尾巴（弧线）──────────────────────────────────────
    nvgBeginPath(vg)
    nvgMoveTo(vg, -u * 1.5,  h * 0.06)
    nvgBezierTo(vg, -u * 3.0, h * 0.00, -u * 3.5, -h * 0.15, -u * 2.8, -h * 0.28)
    nvgBezierTo(vg, -u * 2.5, -h * 0.26, -u * 2.6, -h * 0.10, -u * 1.3, h * 0.08)
    nvgClosePath(vg)
    InkFill(vg, r*0.75, g*0.55, b*0.55, a * 0.85)
end

-- 统一入口：纯黑剪影；isBeast=true 绘怪兽形，false 绘剑客形
-- cx=中心X，groundY=脚底Y，h=身高，flipped=是否镜像（朝左）
local function DrawSilhouette(vg, cx, groundY, h, isBeast, flipped)
    local r, g, b, a = 0.05, 0.04, 0.04, 0.88

    -- ── 脚底淡墨晕（深灰，与浅背景对比）────────────────────
    local shadowPaint = nvgRadialGradient(vg, cx, groundY, 0, h * 0.14,
        nvgRGBAf(0.2, 0.18, 0.16, 0.25), nvgRGBAf(0.2, 0.18, 0.16, 0.0))
    nvgBeginPath(vg)
    nvgEllipse(vg, cx, groundY, h * 0.28, h * 0.06)
    nvgFillPaint(vg, shadowPaint)
    nvgFill(vg)

    nvgSave(vg)
    nvgTranslate(vg, cx, groundY - h)
    if flipped then nvgScale(vg, -1, 1) end

    if isBeast then
        DrawInkMonster(vg, h, r, g, b, a)
    else
        DrawInkSwordsman(vg, h, r, g, b, a)
    end

    nvgRestore(vg)
end

-- ── 延迟处理战斗结束：在动画播完后真正执行清理 ────────────────
---@param pending table {won, logText, expGain, silverGain, lootToken, lootItemName}
local function ProcessBattleEnd(pending)
    print("[Client] ProcessBattleEnd 执行，切回普通视图")
    inBattle_     = false
    battleState_  = nil
    skillCooldowns_ = {}
    pendingSkill_   = ""
    battleLog_      = {}

    -- 清理战斗场景引用（NanoVG 上下文保持常驻复用，避免反复创建/泄漏）
    battleSceneArea_ = nil
    battleNvgW_  = 0
    battleNvgH_  = 0

    -- ★ 如果战场地图激活，战斗结束后返回地图视图（NanoVG 大地图模式）
    if BattlefieldMap.IsActive() then
        local won = pending and pending.won or false
        BattlefieldMap.OnBattleEnd(won)
        -- 大地图是 NanoVG 全屏渲染，不需要 UI panel；只需恢复激活标识
        mapNvgActive_ = true
        Client.SwitchBGM("battle")
        -- ★ 重新订阅地图渲染事件（战斗期间被 HandleBattleNanoVGRender 覆盖了）
        SubscribeToEvent("NanoVGRender", "HandleMapNanoVGRender")
        -- 隐藏外围 bar，让 NanoVG 地图全屏
        if ui_.newsLabel then ui_.newsLabel:SetVisible(false) end
        if ui_.sceneBar then ui_.sceneBar:SetVisible(false) end
        if ui_.descBar then ui_.descBar:SetVisible(false) end
        if ui_.playerListCol then ui_.playerListCol:Hide() end
        if ui_.statusBar then ui_.statusBar:SetVisible(false) end
        if ui_.navBar then ui_.navBar:SetVisible(false) end
        if ui_.mainArea then
            ui_.mainArea:ClearChildren()
            ui_.bottomSection = nil
        end
        return
    end

    -- 恢复主场景视图
    RebuildMainContent()

    -- ★ 战斗胜利后在主区域顶部显示"炫耀"横幅（6秒后自动消失）
    if pending and pending.won and battleAnim_.lastResult and ui_.mainArea then
        local banner = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            backgroundColor = { 40, 80, 50, 240 },
            borderBottomWidth = 1, borderColor = { 80, 200, 100, 180 },
            padding = { 6, 10 }, gap = 8, flexShrink = 0,
        }
        banner:AddChild(UI.Label {
            text = "战斗胜利！" .. (battleAnim_.lastResult.desc or ""),
            fontSize = 12, color = { 180, 255, 180, 255 }, flexGrow = 1, flexShrink = 1,
        })
        banner:AddChild(UI.Button {
            text = "炫耀一下", fontSize = 12, height = 26,
            paddingHorizontal = 12, borderRadius = 13,
            backgroundColor = { 220, 170, 50, 240 },
            color = { 30, 20, 0, 255 },
            onClick = function()
                local resultTag = battleAnim_.lastResult.won and "胜利" or "失败"
                local desc = battleAnim_.lastResult.desc or ""
                local shareText = "[battle:" .. resultTag .. ":" .. desc .. "]"
                SendToServer(EV.REQ_CHAT_SEND, { Channel = "world", Text = shareText })
                AddLog(">> 已炫耀到世界频道！", "good")
                UI.Toast.Show("已发送到世界频道", { type = "success", duration = 1.5 })
                banner:SetVisible(false)
            end,
        })
        -- 插入到 mainArea 最前面（logPanel 之前）
        local children = ui_.mainArea:GetChildren()
        if children and #children > 0 then
            ui_.mainArea:InsertChild(banner, 1)
        else
            ui_.mainArea:AddChild(banner)
        end
    end

    -- ★ Boss 战结束后自动打开域外战场层面板（方便用户看到解锁结果并进入新层）
    if pending and pending.wasBossChallenge then
        currentPanel_ = PANEL.MAP
        viewingBattlefieldLayers_ = true
        local mainArea = ui_.mainArea
        if mainArea then
            mainArea:ClearChildren()
            ui_.bottomSection = nil
            -- 返回主页按钮
            mainArea:AddChild(UI.Button {
                text = "← 返回主页",
                height = 32,
                paddingHorizontal = 14,
                fontSize = 16,
                fontWeight = "bold",
                borderRadius = 16,
                backgroundColor = TC.bgPanelLight,
                borderWidth = 1,
                borderColor = TC.borderLight,
                color = TC.textPrimary,
                marginBottom = 4,
                marginHorizontal = 6,
                marginTop = 4,
                flexShrink = 0,
                onClick = function()
                    viewingBattlefieldLayers_ = false
                    currentPanel_ = PANEL.MAIN
                    RebuildMainContent()
                    BuildSceneNav()
                end,
            })
            mainArea:AddChild(BuildBattlefieldLayerPanel())
        end
    end
end

-- ── NanoVG 大地图渲染（域外战场自由移动）────────────────────────
function HandleMapNanoVGRender(eventType, eventData)
    if not vg_map_ then return end
    if not mapNvgActive_ then return end
    if not BattlefieldMap.IsActive() then return end

    local dpr = graphics:GetDPR()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local screenW = physW / dpr
    local screenH = physH / dpr
    local gameTime = time:GetElapsedTime()

    BattlefieldMap.Render(screenW, screenH, gameTime, dpr)
end

-- ── NanoVG 战斗场景渲染（浅色水墨风）────────────────────────
-- 调试计数器，每60帧打印一次NanoVG参数
local nvgDebugCounter_ = 0
function HandleBattleNanoVGRender(eventType, eventData)
    if not vg_battle_ then return end
    -- 大地图激活时跳过战斗渲染（不应同时出现，保险）
    if mapNvgActive_ and BattlefieldMap.IsActive() then return end
    local w   = battleNvgW_
    local scH = battleNvgH_
    -- GetAbsoluteLayout 返回逻辑像素，需乘以 DPR 转为物理像素（NanoVG 物理坐标系）
    local dpr  = graphics:GetDPR()
    local offY = battleNvgOffY_ * dpr
    if battleSceneArea_ then
        local abs = battleSceneArea_:GetAbsoluteLayout()
        if abs then
            -- 只用 abs.y 确定场景区域的屏幕起点（逻辑→物理）
            -- scH 不从 abs.h 覆盖：abs.h 在 Yoga 第一帧可能返回父容器高度，
            -- 导致 NanoVG 水墨背景覆盖 nameRow / barSection
            if abs.y and abs.y > 0 then offY = abs.y * dpr end
        end
    end
    if w <= 0 or scH <= 0 then return end

    -- ── 诊断日志：每60帧打印一次 ─────────────────────────────
    nvgDebugCounter_ = nvgDebugCounter_ + 1
    if nvgDebugCounter_ % 60 == 1 then
        local physH = graphics:GetHeight()
        local absInfo = "nil"
        if battleSceneArea_ then
            local abs = battleSceneArea_:GetAbsoluteLayout()
            if abs then
                absInfo = string.format("x=%.1f y=%.1f w=%.1f h=%.1f", abs.x or 0, abs.y or 0, abs.w or 0, abs.h or 0)
            end
        end
        print(string.format("[NVG-DBG] physH=%.0f dpr=%.1f w=%.0f scH=%.0f offY=%.1f | sceneArea.abs={%s}",
            physH, dpr, w, scH, offY, absInfo))
    end

    -- 计算 dt
    local now = time:GetElapsedTime()
    local dt  = math.min(now - lastBattleTime_, 0.05)
    lastBattleTime_ = now

    -- ── 动画队列推进 ─────────────────────────────────────────
    local anim = battleAnim_
    local q    = anim.queue
    if anim.qidx <= #q then
        anim.timer = anim.timer - dt
        local seg  = q[anim.qidx]
        -- 计算当前段的进度（0→1）
        local segDur  = seg.dur
        local elapsed = segDur - anim.timer
        local prog    = segDur > 0 and math.max(0, math.min(1, elapsed / segDur)) or 1

        -- 根据段类型更新 X 位置
        if seg.who == "player" then
            if seg.phase == "run_to" then
                anim.playerX = ANIM.P_BASE + (ANIM.P_ATK - ANIM.P_BASE) * prog
            elseif seg.phase == "hit" then
                anim.playerX = ANIM.P_ATK
            elseif seg.phase == "run_back" then
                anim.playerX = ANIM.P_ATK + (ANIM.P_BASE - ANIM.P_ATK) * prog
            end
        else -- monster
            if seg.phase == "run_to" then
                anim.monsterX = ANIM.M_BASE + (ANIM.M_ATK - ANIM.M_BASE) * prog
            elseif seg.phase == "hit" then
                anim.monsterX = ANIM.M_ATK
            elseif seg.phase == "run_back" then
                anim.monsterX = ANIM.M_ATK + (ANIM.M_BASE - ANIM.M_ATK) * prog
            end
        end

        if anim.timer <= 0 then
            -- hit 阶段结束时触发飘字
            if seg.phase == "hit" and battleAnim_.pendingFloat and battleAnim_.pendingFloatIdx then
                local pf = battleAnim_.pendingFloat[battleAnim_.pendingFloatIdx]
                if pf then
                    local W = battleNvgW_ > 0 and battleNvgW_ or 400
                    local H = battleNvgH_ > 0 and battleNvgH_ or 200
                    local fdpr = graphics:GetDPR()
                    local jitter = math.floor(15 * fdpr)
                    local xPos, clr
                    if pf.target == "monster" then
                        xPos = W * 0.72
                        clr  = { 200, 60, 50 }
                    else
                        xPos = W * 0.25
                        clr  = { 150, 40, 160 }
                    end
                    battleFloatDmg_[#battleFloatDmg_ + 1] = {
                        text  = "-" .. pf.dmg,
                        x     = xPos + math.random(-jitter, jitter),
                        y     = H * 0.30,
                        alpha = 255,
                        vy    = -55 * fdpr,
                        color = clr,
                    }
                end
                battleAnim_.pendingFloatIdx = battleAnim_.pendingFloatIdx + 1
            end
            -- 当前段结束，切到下一段
            anim.qidx = anim.qidx + 1
            if anim.qidx <= #q then
                anim.timer = q[anim.qidx].dur
                -- ★ hit 阶段开始时播放攻击音效
                if q[anim.qidx].phase == "hit" then
                    local pf = battleAnim_.pendingFloat and battleAnim_.pendingFloat[battleAnim_.pendingFloatIdx]
                    if pf and pf.dmg and battleState_ then
                        local maxHp = (pf.target == "player") and (battleState_.myMaxHp or 100) or (battleState_.atkMaxHp or 100)
                        if pf.dmg > maxHp * 0.3 then
                            PlaySFX("crit")
                        else
                            PlaySFX("attack")
                        end
                    else
                        PlaySFX("attack")
                    end
                end
            else
                -- 全队列结束，回到基础位置
                anim.playerX  = ANIM.P_BASE
                anim.monsterX = ANIM.M_BASE
                -- 动画播完，重建界面使技能按钮变为可点击
                if inBattle_ and not battleAnim_.endPending then
                    RebuildMainContent()
                end
            end
        end
    end

    local pX  = w * anim.playerX
    local mX  = w * anim.monsterX

    -- nvgBeginFrame 使用物理像素（与示例 01-nanovg-standalone 一致）
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    nvgBeginFrame(vg_battle_, physW, physH, 1.0)

    nvgSave(vg_battle_)
    nvgScissor(vg_battle_, 0, offY, w, scH)
    nvgTranslate(vg_battle_, 0, offY)

    -- ── 浅色水墨背景 ──────────────────────────────────────────
    -- 天空：暖白→浅灰（宣纸感）
    local bg = nvgLinearGradient(vg_battle_, 0, 0, 0, scH,
        nvgRGBA(245, 240, 230, 255), nvgRGBA(210, 204, 195, 255))
    nvgBeginPath(vg_battle_)
    nvgRect(vg_battle_, 0, 0, w, scH)
    nvgFillPaint(vg_battle_, bg)
    nvgFill(vg_battle_)

    -- ── 远景建筑剪影（中式飞檐，极淡灰）────────────────────
    nvgFillColor(vg_battle_, nvgRGBA(185, 178, 168, 130))
    -- 左侧屋顶
    nvgBeginPath(vg_battle_)
    nvgMoveTo(vg_battle_, 0,       scH * 0.58)
    nvgLineTo(vg_battle_, w*0.06,  scH * 0.44)
    nvgLineTo(vg_battle_, w*0.22,  scH * 0.50)
    nvgLineTo(vg_battle_, w*0.22,  scH * 0.58)
    nvgClosePath(vg_battle_)
    nvgFill(vg_battle_)
    -- 左侧飞檐翘角
    nvgBeginPath(vg_battle_)
    nvgMoveTo(vg_battle_, w*0.02,  scH * 0.44)
    nvgLineTo(vg_battle_, -w*0.02, scH * 0.40)
    nvgLineTo(vg_battle_, w*0.00,  scH * 0.46)
    nvgClosePath(vg_battle_)
    nvgFillColor(vg_battle_, nvgRGBA(185, 178, 168, 90))
    nvgFill(vg_battle_)
    -- 右侧屋顶
    nvgFillColor(vg_battle_, nvgRGBA(185, 178, 168, 110))
    nvgBeginPath(vg_battle_)
    nvgMoveTo(vg_battle_, w*0.78,  scH * 0.50)
    nvgLineTo(vg_battle_, w*0.94,  scH * 0.44)
    nvgLineTo(vg_battle_, w,       scH * 0.56)
    nvgLineTo(vg_battle_, w*0.78,  scH * 0.58)
    nvgClosePath(vg_battle_)
    nvgFill(vg_battle_)
    -- 右侧飞檐翘角
    nvgBeginPath(vg_battle_)
    nvgMoveTo(vg_battle_, w*0.96,  scH * 0.44)
    nvgLineTo(vg_battle_, w*1.02,  scH * 0.40)
    nvgLineTo(vg_battle_, w*1.00,  scH * 0.46)
    nvgClosePath(vg_battle_)
    nvgFillColor(vg_battle_, nvgRGBA(185, 178, 168, 80))
    nvgFill(vg_battle_)

    -- 远山（两层，极浅灰-蓝）
    nvgBeginPath(vg_battle_)
    nvgMoveTo(vg_battle_, 0, scH * 0.65)
    nvgBezierTo(vg_battle_, w*0.15, scH*0.38, w*0.30, scH*0.48, w*0.46, scH*0.40)
    nvgBezierTo(vg_battle_, w*0.58, scH*0.33, w*0.70, scH*0.46, w*0.82, scH*0.40)
    nvgBezierTo(vg_battle_, w*0.90, scH*0.35, w*0.96, scH*0.50, w,      scH*0.60)
    nvgLineTo(vg_battle_, w, scH); nvgLineTo(vg_battle_, 0, scH); nvgClosePath(vg_battle_)
    nvgFillColor(vg_battle_, nvgRGBA(195, 192, 188, 100))
    nvgFill(vg_battle_)

    nvgBeginPath(vg_battle_)
    nvgMoveTo(vg_battle_, 0, scH * 0.74)
    nvgBezierTo(vg_battle_, w*0.18, scH*0.56, w*0.35, scH*0.62, w*0.50, scH*0.57)
    nvgBezierTo(vg_battle_, w*0.62, scH*0.52, w*0.75, scH*0.60, w*0.88, scH*0.55)
    nvgBezierTo(vg_battle_, w*0.94, scH*0.52, w*0.98, scH*0.65, w,      scH*0.70)
    nvgLineTo(vg_battle_, w, scH); nvgLineTo(vg_battle_, 0, scH); nvgClosePath(vg_battle_)
    nvgFillColor(vg_battle_, nvgRGBA(175, 170, 163, 130))
    nvgFill(vg_battle_)

    -- ── 地面（浅暖灰，带细纹）────────────────────────────────
    local groundY = scH * 0.84
    local groundPaint = nvgLinearGradient(vg_battle_, 0, groundY, 0, scH,
        nvgRGBA(195, 188, 178, 255), nvgRGBA(175, 168, 158, 255))
    nvgBeginPath(vg_battle_)
    nvgRect(vg_battle_, 0, groundY, w, scH - groundY)
    nvgFillPaint(vg_battle_, groundPaint)
    nvgFill(vg_battle_)

    -- 地面分割线（淡墨线）
    nvgBeginPath(vg_battle_)
    nvgMoveTo(vg_battle_, 0, groundY)
    nvgLineTo(vg_battle_, w, groundY)
    nvgStrokeColor(vg_battle_, nvgRGBA(130, 120, 108, 160))
    nvgStrokeWidth(vg_battle_, 1.0 * dpr)
    nvgStroke(vg_battle_)

    -- ── 地面晨雾（底部向上渐散）──────────────────────────────
    local mistPaint = nvgLinearGradient(vg_battle_, 0, groundY - scH*0.06, 0, groundY + scH*0.10,
        nvgRGBA(235, 230, 222, 0), nvgRGBA(235, 230, 222, 90))
    nvgBeginPath(vg_battle_)
    nvgRect(vg_battle_, 0, groundY - scH*0.06, w, scH*0.16)
    nvgFillPaint(vg_battle_, mistPaint)
    nvgFill(vg_battle_)

    -- ── 人物剪影（PNG 贴图渲染）────────────────────────────────
    local charH   = scH * 0.40          -- 图片渲染高度（脚底对齐 groundY）
    local charW   = charH * (258 / 384) -- 保持 2:3 比例
    local bs      = battleState_ or {}
    local atkName = bs.atkName or ""

    -- 根据动画阶段为玩家和怪物各自选图
    -- 攻击方：run_to/run_back→run图，hit→attack图，其余→idle图
    -- 受击方：对方hit阶段→hurt图，其余→idle图
    local curSeg   = anim.queue[anim.qidx]
    local curPhase = curSeg and curSeg.phase or "idle"
    local curWho   = curSeg and curSeg.who   or ""

    local pImg, mImg
    if curWho == "player" then
        if curPhase == "run_to" or curPhase == "run_back" then
            pImg = battleImg_.playerRun
            mImg = battleImg_.monsterIdle
        elseif curPhase == "hit" then
            pImg = battleImg_.playerAttack
            mImg = battleImg_.monsterHurt
        else
            pImg = battleImg_.playerIdle
            mImg = battleImg_.monsterIdle
        end
    elseif curWho == "monster" then
        if curPhase == "run_to" or curPhase == "run_back" then
            pImg = battleImg_.playerIdle
            mImg = battleImg_.monsterRun
        elseif curPhase == "hit" then
            pImg = battleImg_.playerHurt
            mImg = battleImg_.monsterAttack
        else
            pImg = battleImg_.playerIdle
            mImg = battleImg_.monsterIdle
        end
    else
        pImg = battleImg_.playerIdle
        mImg = battleImg_.monsterIdle
    end

    -- 辅助函数：用 nvgImagePattern 绘制角色图片，支持水平翻转
    local function DrawCharImg(img, cx, footY, imgW, imgH, flipped)
        if img < 0 then return end
        local x0 = cx - imgW * 0.5
        local y0 = footY - imgH
        nvgSave(vg_battle_)
        if flipped then
            -- 水平翻转：先平移到中心，缩放 -1，再移回
            nvgTranslate(vg_battle_, cx, 0)
            nvgScale(vg_battle_, -1, 1)
            nvgTranslate(vg_battle_, -cx, 0)
        end
        local paint = nvgImagePattern(vg_battle_, x0, y0, imgW, imgH, 0, img, 1.0)
        nvgBeginPath(vg_battle_)
        nvgRect(vg_battle_, x0, y0, imgW, imgH)
        nvgFillPaint(vg_battle_, paint)
        nvgFill(vg_battle_)
        nvgRestore(vg_battle_)
    end

    -- 玩家（图片已内置朝右，无需翻转）
    DrawCharImg(pImg, pX, groundY, charW, charH, false)
    -- 怪物（图片已内置朝左，无需翻转）
    DrawCharImg(mImg, mX, groundY, charW, charH, false)

    -- ── 浮动伤害数字 ─────────────────────────────────────────
    nvgFontFace(vg_battle_, "sans")
    nvgTextAlign(vg_battle_, 18)   -- NVG_ALIGN_CENTER | NVG_ALIGN_MIDDLE
    for i = #battleFloatDmg_, 1, -1 do
        local f = battleFloatDmg_[i]
        f.y     = f.y + f.vy * dt
        f.alpha = f.alpha - 280 * dt
        if f.alpha <= 0 then
            table.remove(battleFloatDmg_, i)
        else
            local a = math.min(255, math.floor(f.alpha))
            nvgFontSize(vg_battle_, 22 * dpr)
            -- 白色描边（浅背景下增强可读性）
            nvgFillColor(vg_battle_, nvgRGBA(255, 255, 255, math.floor(a * 0.7)))
            nvgText(vg_battle_, f.x + dpr, f.y + dpr, f.text)
            nvgFillColor(vg_battle_, nvgRGBA(f.color[1], f.color[2], f.color[3], a))
            nvgText(vg_battle_, f.x, f.y, f.text)
        end
    end

    nvgRestore(vg_battle_)
    nvgEndFrame(vg_battle_)

    -- ── 延迟战斗结束处理：等动画播完再切回正常视图 ────────────
    if battleAnim_.endPending then
        battleAnim_.endTimer = battleAnim_.endTimer - dt
        -- 动画队列已播完 或 超时保底 → 执行实际结束逻辑
        local animDone = (battleAnim_.qidx > #battleAnim_.queue)
        if animDone or battleAnim_.endTimer <= 0 then
            local pending = battleAnim_.endPending
            battleAnim_.endPending = nil
            battleAnim_.endTimer   = 0
            -- 执行实际的战斗结束清理（与原 OnPushBattleEnd 后半段一致）
            ProcessBattleEnd(pending)
        end
    end
end

-- ── 富文本标签剥离（用于战斗日志纯文本显示）────────────────
local function StripRichTags(text)
    if not text then return "" end
    return (text:gsub("<[^>]+>", ""))
end

-- ── 战斗顶部区：水墨场景 + HP条 + 日志（嵌入主界面中间区）──
local function BuildBattleTopSection()
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr   = graphics:GetDPR()
    local logW  = physW / dpr
    local logH  = physH / dpr

    local bs      = battleState_ or {}
    local pStats  = player_ and player_.stats
    local myHp    = bs.myHp    or (player_ and (player_.hp_base or player_.hp or (pStats and pStats.hp) or 0) or 0)
    local myMp    = bs.myMp    or (player_ and (player_.mp_base or player_.mp or (pStats and pStats.mp) or 0) or 0)
    local myMaxHp = bs.myMaxHp or (player_ and (player_.max_hp or player_.hp_base or (pStats and pStats.hp) or 1) or 1)
    local myMaxMp = bs.myMaxMp or (player_ and (player_.max_mp or player_.mp_base or (pStats and pStats.mp) or 1) or 1)
    local atkHp   = bs.atkHp   or 0
    local atkMaxHp= bs.atkMaxHp or 1
    local atkName = bs.atkName  or "妖兽"
    local round   = bs.round    or 0
    local isAuto  = autoFight_

    local section = UI.Panel {
        width = "100%", flexGrow = 1, flexShrink = 1,
        flexDirection = "column", gap = 0,
        minHeight = 0,
    }

    -- 顶部控制栏（h=36）：回合数 + 逃跑 + 自动切换
    local topBar = UI.Panel {
        width = "100%", height = 36, flexShrink = 0,
        flexDirection = "row", alignItems = "center",
        justifyContent = "space-between",
        backgroundColor = TC.bgPanel,
        paddingHorizontal = 10,
        borderBottomWidth = 1, borderColor = TC.border,
    }
    topBar:AddChild(UI.Label {
        text = "第 " .. round .. " 回合",
        fontSize = 15, color = TC.textTitle,
    })
    topBar:AddChild(UI.Button {
        text = "逃跑", fontSize = 14,
        backgroundColor = TC.btnPrimary,
        borderColor = TC.danger,
        onClick = function()
            SendToServer(EV.REQ_FLEE_BATTLE)
            AddLog(">> 试图逃跑...", "warn")
        end,
    })
    local playerLv = player_ and player_.level or 1
    local autoLabel = isAuto and "自动  ON" or "手动  OFF"
    local autoBg    = isAuto and { 20, 60, 30, 230 } or { 50, 30, 10, 230 }
    topBar:AddChild(UI.Button {
        text = autoLabel, fontSize = 14,
        backgroundColor = autoBg,
        borderColor = isAuto and { 40, 160, 70, 200 } or { 160, 100, 20, 200 },
        onClick = function()
            if (player_ and player_.realm or 1) < 2 then
                battleLog_[#battleLog_ + 1] = ">> 自动战斗需筑基期方可开启"
                if #battleLog_ > 3 then table.remove(battleLog_, 1) end
                RebuildMainContent()
                return
            end
            autoFight_ = not autoFight_
            SendToServer(EV.REQ_TOGGLE_AUTO, { Enabled = autoFight_ })
            RebuildMainContent()
        end,
    })
    section:AddChild(topBar)

    -- 战斗日志区（固定52px，在场景上方）
    local logArea = UI.Panel {
        width = "100%", height = 52, flexShrink = 0,
        flexDirection = "column", gap = 2,
        paddingHorizontal = 10, paddingVertical = 5,
        backgroundColor = TC.bgDeep,
        borderBottomWidth = 1, borderColor = TC.borderLight,
        overflow = "hidden",
    }
    if #battleLog_ == 0 then
        logArea:AddChild(UI.Label {
            text = "── 战斗进行中 ──",
            fontSize = 12, color = TC.textMuted, textAlign = "center",
        })
    else
        for i = #battleLog_, math.max(1, #battleLog_ - 2), -1 do
            local alpha = i == #battleLog_ and 255 or (i == #battleLog_ - 1 and 180 or 110)
            logArea:AddChild(UI.Label {
                text = StripRichTags(battleLog_[i]),
                fontSize = 12, color = { 220, 190, 140, alpha }, flexShrink = 1,
            })
        end
    end
    section:AddChild(logArea)

    -- NanoVG 场景区域（透明，让 NanoVG 透出）
    -- 场景高度上限降至170，为barSection留足空间
    local sceneH = math.max(130, math.min(220, math.floor(logW * 0.35)))
    battleNvgW_    = physW          -- 物理像素宽（NanoVG 全屏坐标系）
    battleNvgH_    = sceneH * dpr   -- 物理像素高

    print(string.format("[BATTLE-BUILD] physW=%.0f physH=%.0f dpr=%.1f logW=%.1f logH=%.1f sceneH=%.0f battleNvgH_=%.0f",
        physW, physH, dpr, logW, logH, sceneH, battleNvgH_))

    -- 场景区域（flexGrow=1 填满剩余空间，最小80px，可随屏幕缩小）
    local sceneArea = UI.Panel { width = "100%", flexGrow = 1, flexShrink = 1, minHeight = 80 }
    battleSceneArea_ = sceneArea   -- 保存引用，供 NanoVG 渲染动态定位
    section:AddChild(sceneArea)

    -- 初始化 NanoVG（只创建一次）
    if not vg_battle_ then
        vg_battle_ = nvgCreate(1)
        nvgCreateFont(vg_battle_, "sans", "Fonts/MiSans-Regular.ttf")
        battleImg_.playerIdle    = nvgCreateImage(vg_battle_, "image/p_idle_20260525120201.png",    0)
        battleImg_.playerRun     = nvgCreateImage(vg_battle_, "image/p_run_20260525120349.png",     0)
        battleImg_.playerAttack  = nvgCreateImage(vg_battle_, "image/p_attack_20260525120346.png",  0)
        battleImg_.playerHurt    = nvgCreateImage(vg_battle_, "image/p_hurt_20260525120348.png",    0)
        battleImg_.monsterIdle   = nvgCreateImage(vg_battle_, "image/m_idle_20260525120234.png",    0)
        battleImg_.monsterRun    = nvgCreateImage(vg_battle_, "image/m_run_20260525120348.png",     0)
        battleImg_.monsterAttack = nvgCreateImage(vg_battle_, "image/m_attack_20260525120347.png",  0)
        battleImg_.monsterHurt   = nvgCreateImage(vg_battle_, "image/m_hurt_20260525120345.png",    0)
    end
    -- ★ 每次进入战斗都重新订阅（地图渲染可能覆盖了此事件）
    SubscribeToEvent("NanoVGRender", "HandleBattleNanoVGRender")

    print(string.format("[BATTLE-BUILD] topSection 构建完毕，myHp=%d/%d atkHp=%d/%d", myHp, myMaxHp, atkHp, atkMaxHp))

    return section
end

-- ── 战场信息栏（姓名 + 血条 + 内力条）作为独立 mainArea 子节点 ──
local function BuildBattleInfoBar()
    local bs      = battleState_ or {}
    local pStats  = player_ and player_.stats
    local myHp    = bs.myHp    or (player_ and (player_.hp_base or player_.hp or (pStats and pStats.hp) or 0) or 0)
    local myMp    = bs.myMp    or (player_ and (player_.mp_base or player_.mp or (pStats and pStats.mp) or 0) or 0)
    local myMaxHp = bs.myMaxHp or (player_ and (player_.max_hp or player_.hp_base or (pStats and pStats.hp) or 1) or 1)
    local myMaxMp = bs.myMaxMp or (player_ and (player_.max_mp or player_.mp_base or (pStats and pStats.mp) or 1) or 1)
    local atkHp   = bs.atkHp   or 0
    local atkMaxHp= bs.atkMaxHp or 1
    local atkName = bs.atkName  or "妖兽"
    local myName  = player_ and player_.name or "侠客"

    -- 辅助：创建带标签和数值的进度条行
    local function MakeBattleBar(label, cur, max, trackBg, fillColor, labelColor)
        local pct = math.floor(cur / math.max(max, 1) * 100)
        local row = UI.Panel { width = "100%", flexDirection = "column", gap = 1, flexShrink = 0 }
        local labelRow = UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
        }
        labelRow:AddChild(UI.Label { text = label, fontSize = 12, color = labelColor })
        labelRow:AddChild(UI.Label {
            text = cur .. "/" .. max, fontSize = 11,
            color = { labelColor[1], labelColor[2], labelColor[3], 200 },
        })
        row:AddChild(labelRow)
        local track = UI.Panel { width = "100%", height = 10, backgroundColor = trackBg }
        track:AddChild(UI.Panel { width = pct .. "%", height = "100%", backgroundColor = fillColor })
        row:AddChild(track)
        return row
    end

    local infoBar = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "row", gap = 6,
        paddingHorizontal = 10, paddingVertical = 8,
        backgroundColor = TC.bgDeep,
        borderTopWidth = 1, borderBottomWidth = 1, borderColor = TC.border,
    }

    -- 我方：姓名 + 气血 + 内力
    local mySide = UI.Panel { flexGrow = 1, flexShrink = 1, flexDirection = "column", gap = 4, minWidth = 0 }
    mySide:AddChild(UI.Label { text = myName, fontSize = 14, color = TC.info })
    mySide:AddChild(MakeBattleBar("气血", myHp, myMaxHp,
        { 12, 35, 12, 200 }, { 55, 210, 75, 255 }, { 110, 240, 120, 255 }))
    mySide:AddChild(MakeBattleBar("内力", myMp, myMaxMp,
        { 10, 18, 45, 200 }, { 50, 130, 230, 255 }, { 100, 175, 255, 255 }))

    infoBar:AddChild(mySide)
    infoBar:AddChild(UI.Label {
        text = "对", fontSize = 13, color = TC.rare,
        alignSelf = "center", width = 22, textAlign = "center", flexShrink = 0,
    })

    -- 敌方：姓名 + 气血
    local atkSide = UI.Panel { flexGrow = 1, flexShrink = 1, flexDirection = "column", gap = 4, minWidth = 0 }
    atkSide:AddChild(UI.Label { text = atkName, fontSize = 14, color = TC.danger })
    atkSide:AddChild(MakeBattleBar("气血", atkHp, atkMaxHp,
        { 35, 12, 12, 200 }, { 215, 60, 50, 255 }, { 255, 155, 130, 255 }))
    infoBar:AddChild(atkSide)

    print(string.format("[BATTLE-INFOBAR] myHp=%d/%d atkHp=%d/%d", myHp, myMaxHp, atkHp, atkMaxHp))
    return infoBar
end

-- ── 战斗技能区：填充 ui_.bottomSection（嵌入主界面底部区）──
local function BuildBattleSkillSection()
    if not ui_.bottomSection then return end
    ui_.bottomSection:ClearChildren()

    local bs     = battleState_ or {}
    local isAuto = autoFight_

    local slots = (player_ and player_.battle_slots) or battleSlots_ or {}
    local learnedIds = {}
    if player_ and player_.skills then
        for _, sk in ipairs(player_.skills) do local sid = sk.id or sk.skill_id; if sid then learnedIds[sid] = true end end
    end
    local slotDefs = {}
    for _, sid in ipairs(slots) do
        local def = Shared.GetSkillDef(sid)
        if def then slotDefs[#slotDefs + 1] = def end
    end
    local normalDef = Shared.GetSkillDef("basic_sword")

    local BATTLE_TYPE_COLOR = {
        normal = { 160, 160, 160, 220 }, damage = { 255, 120, 60, 220 },
        buff   = {  80, 210, 130, 220 }, dodge  = { 120, 200, 255, 220 },
    }
    local BATTLE_TYPE_LABEL = {
        normal = "普攻", damage = "伤害", buff = "增强", dodge = "闪避",
    }

    local function MakeSkillBtn(def, isNormal)
        local cd       = skillCooldowns_[def.id] or 0
        local onCD     = cd > 0
        local noMp     = (not isNormal) and player_ and (player_.mp or 0) < (def.mp_cost or 0)
        local locked   = isAuto
        local animBusy = (#battleAnim_.queue > 0) and (battleAnim_.qidx <= #battleAnim_.queue)
        local isPending = (not isAuto) and (pendingSkill_ ~= "") and (def.id == pendingSkill_)
        local hasPending = (not isAuto) and (pendingSkill_ ~= "") and (def.id ~= pendingSkill_)
        local btnBg = locked    and { 18, 14, 30, 180 }
            or animBusy         and { 18, 14, 30, 180 }
            or isPending        and { 30, 60, 20, 230 }
            or hasPending       and { 18, 14, 30, 160 }
            or onCD             and { 25, 18, 38, 200 }
            or noMp             and { 30, 20, 20, 200 }
            or                      { 22, 30, 55, 230 }
        local bdCol = locked    and { 40, 35, 55, 140 }
            or animBusy         and { 40, 35, 55, 140 }
            or isPending        and { 60, 200, 60, 220 }
            or hasPending       and { 35, 50, 30, 100 }
            or onCD             and { 70, 50, 100, 160 }
            or noMp             and { 120, 40, 40, 160 }
            or                      { 80, 120, 200, 200 }
        -- 手动模式下：无 pending 且无 CD 且内力够 且动画播完 才可点击
        local canClick = not locked and not animBusy and not isPending and not hasPending and not onCD and not noMp
        local cellOnClick = nil
        if canClick then
            cellOnClick = function()
                SendToServer(EV.REQ_USE_SKILL, { SkillId = def.id })
                AddLog(">> 排队技能 【" .. def.name .. "】，等待回合结算...", "warn")
                pendingSkill_ = def.id
                BuildBattleSkillSection()
            end
        end
        local cell = UI.Panel {
            width = "23%", height = 70,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            backgroundColor = btnBg, borderWidth = 1, borderColor = bdCol, gap = 1,
            onClick = cellOnClick,
        }
        cell:AddChild(UI.Label { text = def.name, fontSize = 12, color = TC.textPrimary, textAlign = "center" })
        local btype = def.battle_type or "normal"
        cell:AddChild(UI.Label { text = BATTLE_TYPE_LABEL[btype] or btype, fontSize = 10,
            color = BATTLE_TYPE_COLOR[btype] or { 180, 180, 180, 200 }, textAlign = "center" })
        if isPending then
            cell:AddChild(UI.Label { text = "⏳ 等待中", fontSize = 10,
                color = TC.success, textAlign = "center" })
        elseif onCD then
            cell:AddChild(UI.Label { text = "冷却 " .. cd, fontSize = 11,
                color = TC.textTitle, textAlign = "center" })
        elseif (def.mp_cost or 0) > 0 then
            cell:AddChild(UI.Label { text = "内力 " .. def.mp_cost, fontSize = 10,
                color = TC.info, textAlign = "center" })
        end
        return cell
    end

    local skillGrid = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "row", flexWrap = "wrap",
        paddingHorizontal = 6, paddingVertical = 5, gap = 5,
        backgroundColor = TC.bgOverlay,
    }
    for _, def in ipairs(slotDefs) do
        skillGrid:AddChild(MakeSkillBtn(def, false))
    end
    for i = #slotDefs + 1, Settings.BATTLE_SKILL_SLOTS do
        skillGrid:AddChild(UI.Panel {
            width = "23%", height = 70,
            backgroundColor = TC.bgOverlay,
            borderWidth = 1, borderColor = TC.borderLight,
        })
    end
    if normalDef then
        skillGrid:AddChild(MakeSkillBtn(normalDef, true))
    end
    ui_.bottomSection:AddChild(skillGrid)
end

-- ── 构建战斗面板 ─────────────────────────────────────────────
local function BuildBattlePanel()
    -- ── 未在战斗时：显示怪物列表 ────────────────────────────
    if not inBattle_ then
        local container = UI.Panel {
            width = "100%", flexGrow = 1,
            padding = 8, gap = 6,
        }
        container:AddChild(UI.Label {
            text = "── 野外妖兽 ──",
            fontSize = 17, color = LOG_COLOR.title,
            marginBottom = 6, alignSelf = "center",
        })

        local scene = player_ and player_.scene or "ancient_village"
        local tutStep = player_ and (player_.tutorial_step or 0) or 0

        -- 收集当前场景可战斗的怪物列表（域外战场按层过滤）
        local sceneMonsters = {}
        local currentLayer = nil
        if scene == "battlefield" and currentSpot_ then
            local layerStr = currentSpot_:match("layer_(%d+)")
            if layerStr then currentLayer = tonumber(layerStr) end
        end

        for _, m in ipairs(Settings.MONSTERS) do
            if m.scene == scene then
                -- 古村引导怪只在 tutorial_step == 1 时显示
                if m.tutorial_beast then
                    if tutStep == 1 then
                        sceneMonsters[#sceneMonsters + 1] = m
                    end
                elseif scene == "battlefield" then
                    -- 域外战场按层数过滤
                    if currentLayer and m.layer == currentLayer then
                        sceneMonsters[#sceneMonsters + 1] = m
                    end
                else
                    sceneMonsters[#sceneMonsters + 1] = m
                end
            end
        end

        if #sceneMonsters == 0 then
            local hint = (scene == "ancient_village")
                and (tutStep == 0 and "先去找老村长说话吧" or
                     tutStep >= 2 and "幼妖已被驱散，回老村长处复命" or "此处暂无妖兽")
                or (scene == "battlefield" and currentLayer and Settings.BATTLEFIELD_LAYERS[currentLayer] and Settings.BATTLEFIELD_LAYERS[currentLayer].is_guild_zone)
                and "此层为帮会福地，无妖兽出没"
                or "此处无妖兽，前往域外战场探索"
            container:AddChild(UI.Label {
                text = hint,
                fontSize = 17, color = TC.textMuted, alignSelf = "center",
            })
            return container
        end

        for _, m in ipairs(sceneMonsters) do
            local row = UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                backgroundColor = m.tutorial_beast and { 50, 30, 15, 210 } or { 30, 38, 25, 200 },
                padding = { 6, 8 }, marginBottom = 4,
                borderWidth = m.tutorial_beast and 1 or 0,
                borderColor = TC.border,
            }
            local info = UI.Panel { flexGrow = 1 }
            local nameColor = m.tutorial_beast and { 220, 160, 60, 255 } or LOG_COLOR.warn
            info:AddChild(UI.Label {
                text = m.name .. "  " .. Settings.REALM.GetDisplayName(m.realm or 1, m.realm_layer or 1)
                    .. (m.tutorial_beast and "  【引导任务】" or ""),
                fontSize = 16, color = nameColor,
            })
            info:AddChild(UI.Label {
                text = "气血：" .. m.hp .. "  攻击：" .. m.atk,
                fontSize = 16, color = TC.textSecondary,
            })
            row:AddChild(info)
            local fightBtn = UI.Button {
                text = m.tutorial_beast and "驱散" or "出手",
                fontSize = 16,
                backgroundColor = m.tutorial_beast and { 120, 70, 20, 220 } or nil,
                onClick = function()
                    AddLog(">> 向 " .. m.name .. " 发起挑战！", "warn")
                    SendToServer(EV.REQ_START_BATTLE, { MonsterId = m.id })
                    inBattle_ = true
                    battleState_ = nil
                    skillCooldowns_ = {}
                    Client.SwitchPanel(PANEL.BATTLE)
                end,
            }
            -- 注册教程引导怪物按钮为高亮目标
            if m.tutorial_beast then
                Tutorial.RegisterTarget("battle_迷失幼妖", fightBtn)
            end
            row:AddChild(fightBtn)
            container:AddChild(row)
        end
        return container
    end

    -- ═══════════════════════════════════════════════════════
    -- 战斗进行中：全新战斗面板
    -- ═══════════════════════════════════════════════════════
    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr   = graphics:GetDPR()
    local logW  = physW / dpr
    local logH  = physH / dpr

    -- 从战斗状态读数据
    local bs = battleState_ or {}
    local pStats  = player_ and player_.stats
    local myHp    = bs.myHp    or (player_ and (player_.hp_base or player_.hp or (pStats and pStats.hp) or 0) or 0)
    local myMp    = bs.myMp    or (player_ and (player_.mp_base or player_.mp or (pStats and pStats.mp) or 0) or 0)
    local myMaxHp = bs.myMaxHp or (player_ and (player_.max_hp or player_.hp_base or (pStats and pStats.hp) or 1) or 1)
    local myMaxMp = bs.myMaxMp or (player_ and (player_.max_mp or player_.mp_base or (pStats and pStats.mp) or 1) or 1)
    local atkHp   = bs.atkHp   or 0
    local atkMaxHp= bs.atkMaxHp or 1
    local atkName = bs.atkName  or "妖兽"
    local round   = bs.round    or 0
    local isAuto  = autoFight_

    -- 读取玩家技能槽配置
    local slots = (player_ and player_.battle_slots) or battleSlots_ or {}
    -- 收集已学技能 def
    local learnedIds = {}
    if player_ and player_.skills then
        for _, sk in ipairs(player_.skills) do local sid = sk.id or sk.skill_id; if sid then learnedIds[sid] = true end end
    end

    -- 装配技能定义列表（普攻固定追加在末位）
    local slotDefs = {}
    for _, sid in ipairs(slots) do
        local def = Shared.GetSkillDef(sid)
        if def then slotDefs[#slotDefs + 1] = def end
    end
    -- 固定普攻（插在末位）
    local normalDef = Shared.GetSkillDef("basic_sword")

    -- ── 外层容器 ─────────────────────────────────────────────
    local root = UI.Panel {
        width = "100%", flexGrow = 1,
        flexDirection = "column", gap = 0,
        backgroundColor = TC.bgDeep,
    }

    -- ── 顶部状态行：回合 + 自动/手动切换 ───────────────────
    local topBar = UI.Panel {
        width = "100%", height = 36, flexShrink = 0,
        flexDirection = "row", alignItems = "center",
        justifyContent = "space-between",
        backgroundColor = TC.bgPanel,
        paddingHorizontal = 10,
        borderBottomWidth = 1, borderColor = TC.border,
    }
    topBar:AddChild(UI.Label {
        text = "第 " .. round .. " 回合",
        fontSize = 15, color = TC.textTitle,
    })
    -- 逃跑按钮
    topBar:AddChild(UI.Button {
        text = "逃跑", fontSize = 14,
        backgroundColor = TC.btnPrimary,
        borderColor = TC.danger,
        onClick = function()
            SendToServer(EV.REQ_FLEE_BATTLE)
            AddLog(">> 试图逃跑...", "warn")
        end,
    })
    -- 自动/手动切换
    local autoLabel = isAuto and "自动  ON" or "手动  OFF"
    local autoBg    = isAuto and { 20, 60, 30, 230 } or { 50, 30, 10, 230 }
    local autoBtn = UI.Button {
        text = autoLabel, fontSize = 14,
        backgroundColor = autoBg,
        borderColor = isAuto and { 40, 160, 70, 200 } or { 160, 100, 20, 200 },
        onClick = function()
            if (player_ and player_.realm or 1) < 2 then
                battleLog_[#battleLog_ + 1] = ">> 自动战斗需筑基期方可开启"
                if #battleLog_ > 3 then table.remove(battleLog_, 1) end
                Client.SwitchPanel(PANEL.BATTLE)
                return
            end
            autoFight_ = not autoFight_
            SendToServer(EV.REQ_TOGGLE_AUTO, { Enabled = autoFight_ })
            Client.SwitchPanel(PANEL.BATTLE)
        end,
    }
    topBar:AddChild(autoBtn)
    root:AddChild(topBar)

    -- ── NanoVG 战斗场景区域 ──────────────────────────────────
    -- mainArea 宽度 = 屏幕宽 - 左侧玩家列64px
    -- 以实际可用宽度为基准：宽度45%，上限280，下限150
    local mainW = logW - 64
    local sceneH = math.max(150, math.min(280, math.floor(mainW * 0.45)))
    battleNvgOffY_ = 36   -- topBar 高度，NanoVG 坐标偏移量

    -- sceneArea 不设置背景色，保持透明让 NanoVG 透出来
    local sceneArea = UI.Panel {
        width = "100%", height = sceneH, flexShrink = 0,
    }
    battleSceneArea_ = sceneArea   -- 保存引用供渲染动态定位
    root:AddChild(sceneArea)

    -- 初始化 NanoVG 上下文（只创建一次）
    if not vg_battle_ then
        vg_battle_ = nvgCreate(1)
        nvgCreateFont(vg_battle_, "sans", "Fonts/MiSans-Regular.ttf")
        battleImg_.playerIdle    = nvgCreateImage(vg_battle_, "image/p_idle_20260525120201.png",    0)
        battleImg_.playerRun     = nvgCreateImage(vg_battle_, "image/p_run_20260525120349.png",     0)
        battleImg_.playerAttack  = nvgCreateImage(vg_battle_, "image/p_attack_20260525120346.png",  0)
        battleImg_.playerHurt    = nvgCreateImage(vg_battle_, "image/p_hurt_20260525120348.png",    0)
        battleImg_.monsterIdle   = nvgCreateImage(vg_battle_, "image/m_idle_20260525120234.png",    0)
        battleImg_.monsterRun    = nvgCreateImage(vg_battle_, "image/m_run_20260525120348.png",     0)
        battleImg_.monsterAttack = nvgCreateImage(vg_battle_, "image/m_attack_20260525120347.png",  0)
        battleImg_.monsterHurt   = nvgCreateImage(vg_battle_, "image/m_hurt_20260525120345.png",    0)
    end
    -- ★ 每次进入战斗都重新订阅（地图渲染可能覆盖了此事件）
    SubscribeToEvent("NanoVGRender", "HandleBattleNanoVGRender")
    battleNvgW_ = mainW
    battleNvgH_ = sceneH

    -- 敌方标题（贴在场景区域上方右侧）
    local enemyTitle = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "row", justifyContent = "space-between",
        paddingHorizontal = 12, paddingVertical = 3,
        backgroundColor = TC.bgOverlay,
    }
    -- 我方名字
    local myName = player_ and player_.name or "侠客"
    enemyTitle:AddChild(UI.Label {
        text = myName, fontSize = 14, color = TC.info,
    })
    -- VS
    enemyTitle:AddChild(UI.Label {
        text = "对", fontSize = 13, color = TC.rare,
    })
    -- 敌方名字
    enemyTitle:AddChild(UI.Label {
        text = atkName, fontSize = 14, color = TC.danger,
    })
    root:AddChild(enemyTitle)

    -- ── 双方血量/内力条 ──────────────────────────────────────
    local barSection = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "row", gap = 6,
        paddingHorizontal = 8, paddingVertical = 4,
        backgroundColor = TC.bgOverlay,
    }

    -- 我方：HP + MP
    local myBars = UI.Panel { flexGrow = 1, gap = 3 }
    local myHpPct = math.floor(myHp / math.max(myMaxHp, 1) * 100)
    myBars:AddChild(UI.Label {
        text = "气血  " .. myHp .. "/" .. myMaxHp,
        fontSize = 12, color = TC.success,
    })
    local myHpTrack = UI.Panel {
        width = "100%", height = 8, backgroundColor = TC.barBg,
    }
    local myHpFill = UI.Panel {
        width = myHpPct .. "%", height = "100%",
        backgroundColor = TC.barExp,
    }
    myHpTrack:AddChild(myHpFill)
    myBars:AddChild(myHpTrack)

    local myMpPct = math.floor(myMp / math.max(myMaxMp, 1) * 100)
    myBars:AddChild(UI.Label {
        text = "内力  " .. myMp .. "/" .. myMaxMp,
        fontSize = 12, color = TC.info,
    })
    local myMpTrack = UI.Panel {
        width = "100%", height = 6, backgroundColor = TC.barBg,
    }
    local myMpFill = UI.Panel {
        width = myMpPct .. "%", height = "100%",
        backgroundColor = TC.info,
    }
    myMpTrack:AddChild(myMpFill)
    myBars:AddChild(myMpTrack)
    barSection:AddChild(myBars)

    -- 分隔
    barSection:AddChild(UI.Panel {
        width = 1, height = "100%", backgroundColor = TC.border,
    })

    -- 敌方：仅 HP
    local atkBars = UI.Panel { flexGrow = 1, gap = 3 }
    local atkHpPct = math.floor(atkHp / math.max(atkMaxHp, 1) * 100)
    atkBars:AddChild(UI.Label {
        text = "气血  " .. atkHp .. "/" .. atkMaxHp,
        fontSize = 12, color = TC.warning,
    })
    local atkHpTrack = UI.Panel {
        width = "100%", height = 8, backgroundColor = TC.barBg,
    }
    local atkHpFill = UI.Panel {
        width = atkHpPct .. "%", height = "100%",
        backgroundColor = TC.barFill,
    }
    atkHpTrack:AddChild(atkHpFill)
    atkBars:AddChild(atkHpTrack)
    barSection:AddChild(atkBars)
    root:AddChild(barSection)

    -- ── 战斗日志内嵌区（最近 3 条）──────────────────────────
    local logArea = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "column", gap = 2,
        paddingHorizontal = 10, paddingVertical = 5,
        backgroundColor = TC.bgDeep,
        borderTopWidth = 1, borderColor = TC.borderLight,
    }
    if #battleLog_ == 0 then
        logArea:AddChild(UI.Label {
            text = "── 战斗进行中 ──",
            fontSize = 12, color = TC.textMuted, textAlign = "center",
        })
    else
        for i = #battleLog_, math.max(1, #battleLog_ - 2), -1 do
            local alpha = i == #battleLog_ and 255 or (i == #battleLog_ - 1 and 180 or 110)
            logArea:AddChild(UI.Label {
                text = battleLog_[i],
                fontSize = 12,
                color = { 220, 190, 140, alpha },
                flexShrink = 1,
            })
        end
    end
    root:AddChild(logArea)

    -- ── 技能格（2 行 × 4 列）────────────────────────────────
    local skillGrid = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "row", flexWrap = "wrap",
        paddingHorizontal = 6, paddingVertical = 5, gap = 5,
        backgroundColor = TC.bgOverlay,
        borderTopWidth = 1, borderColor = TC.border,
    }

    -- 技能类型颜色标签
    local BATTLE_TYPE_COLOR = {
        normal = { 160, 160, 160, 220 },
        damage = { 255, 120,  60, 220 },
        buff   = {  80, 210, 130, 220 },
        dodge  = { 120, 200, 255, 220 },
    }
    local BATTLE_TYPE_LABEL = {
        normal = "普攻", damage = "伤害", buff = "增强", dodge = "闪避",
    }

    -- 渲染单个技能格子
    local function MakeSkillBtn(def, isNormal)
        local cd         = skillCooldowns_[def.id] or 0
        local onCD       = cd > 0
        local noMp       = (not isNormal) and player_ and (player_.mp or 0) < (def.mp_cost or 0)
        local locked     = isAuto
        local animBusy   = (#battleAnim_.queue > 0) and (battleAnim_.qidx <= #battleAnim_.queue)
        local isPending  = (not isAuto) and (pendingSkill_ ~= "") and (def.id == pendingSkill_)
        local hasPending = (not isAuto) and (pendingSkill_ ~= "") and (def.id ~= pendingSkill_)

        local btnBg = locked     and { 18, 14, 30, 180 }
            or animBusy          and { 18, 14, 30, 180 }
            or isPending         and { 30, 60, 20, 230 }
            or hasPending        and { 18, 14, 30, 160 }
            or onCD              and { 25, 18, 38, 200 }
            or noMp              and { 30, 20, 20, 200 }
            or                       { 22, 30, 55, 230 }
        local bdCol = locked     and { 40, 35, 55, 140 }
            or animBusy          and { 40, 35, 55, 140 }
            or isPending         and { 60, 200, 60, 220 }
            or hasPending        and { 35, 50, 30, 100 }
            or onCD              and { 70, 50, 100, 160 }
            or noMp              and { 120, 40, 40, 160 }
            or                       { 80, 120, 200, 200 }

        -- 手动模式下：无 pending 且无 CD 且内力够 且动画播完 才可点击
        local canClick = not locked and not animBusy and not isPending and not hasPending and not onCD and not noMp
        local cellOnClick = nil
        if canClick then
            cellOnClick = function()
                SendToServer(EV.REQ_USE_SKILL, { SkillId = def.id })
                AddLog(">> 排队技能 【" .. def.name .. "】，等待回合结算...", "warn")
                pendingSkill_ = def.id
                BuildBattleSkillSection()
            end
        end

        local cell = UI.Panel {
            width = "23%", aspectRatio = 1,
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            backgroundColor = btnBg,
            borderWidth = 1, borderColor = bdCol,
            gap = 1,
            onClick = cellOnClick,
        }

        -- 技能名
        cell:AddChild(UI.Label {
            text = def.name, fontSize = 12, color = TC.textPrimary,
            textAlign = "center",
        })

        -- 类型标签 / 等待中 / 冷却 / 内力消耗（互斥，优先级从高到低）
        local btype = def.battle_type or "normal"
        cell:AddChild(UI.Label {
            text = BATTLE_TYPE_LABEL[btype] or btype,
            fontSize = 10,
            color = BATTLE_TYPE_COLOR[btype] or { 180, 180, 180, 200 },
            textAlign = "center",
        })

        if isPending then
            cell:AddChild(UI.Label {
                text = "⏳ 等待中",
                fontSize = 10, color = TC.success, textAlign = "center",
            })
        elseif onCD then
            cell:AddChild(UI.Label {
                text = "冷却 " .. cd,
                fontSize = 11, color = TC.textTitle, textAlign = "center",
            })
        elseif (def.mp_cost or 0) > 0 then
            cell:AddChild(UI.Label {
                text = "内力 " .. def.mp_cost,
                fontSize = 10, color = TC.info, textAlign = "center",
            })
        end

        return cell
    end

    -- 填充技能槽
    for _, def in ipairs(slotDefs) do
        skillGrid:AddChild(MakeSkillBtn(def, false))
    end
    -- 补空槽占位（使普攻始终在第 8 格）
    for i = #slotDefs + 1, Settings.BATTLE_SKILL_SLOTS do
        skillGrid:AddChild(UI.Panel {
            width = "23%", aspectRatio = 1,
            backgroundColor = TC.bgOverlay,
            borderWidth = 1, borderColor = TC.borderLight,
        })
    end
    -- 固定普攻（第 8 格）
    if normalDef then
        skillGrid:AddChild(MakeSkillBtn(normalDef, true))
    end

    root:AddChild(skillGrid)
    return root
end


-- 构建地图/移动面板
local function BuildMapPanel()
    local scene  = player_ and player_.scene or "ancient_village"

    -- 域外战场：先显示世界地图（主功能），再显示战场层数
    if scene == "battlefield" then
        local wrapper = UI.Panel {
            width = "100%", flexGrow = 1,
            flexDirection = "column", alignItems = "center",
        }
        -- 世界地图标题
        wrapper:AddChild(UI.Label {
            text = "🗺️ 世界地图",
            fontSize = 17, fontWeight = "bold", color = TC.textPrimary,
            alignSelf = "center", marginBottom = 8, marginTop = 6,
        })
        -- 世界地图地点列表
        local worldOrder = {
            { id = "ancient_village", icon = "🏘" },
            { id = "battlefield",     icon = "⚔️" },
            { id = "main_city",       icon = "🏯" },
            { id = "sword_sect",      icon = "⚔" },
            { id = "iron_sect",       icon = "🛡" },
            { id = "medicine_sect",   icon = "🧪" },
            { id = "shadow_sect",     icon = "🌑" },
            { id = "qidan_sect",      icon = "🔥" },
        }
        local worldArea = UI.Panel {
            width = "100%", flexDirection = "column",
            alignItems = "center", gap = 5, paddingHorizontal = 12,
        }
        for _, loc in ipairs(worldOrder) do
            local locId = loc.id
            local locName = SCENE_NAMES[locId] or locId
            if locId == scene then
                worldArea:AddChild(UI.Panel {
                    width = "92%", flexShrink = 0,
                    flexDirection = "row", alignItems = "center", justifyContent = "center",
                    backgroundColor = TC.info,
                    borderWidth = 2, borderColor = TC.info,
                    borderRadius = 20, padding = { 4, 14 }, minHeight = 42,
                    children = {
                        UI.Label {
                            text = loc.icon .. "  " .. locName .. "  （当前）",
                            fontSize = 16, fontWeight = "bold", color = TC.info,
                        },
                    },
                })
            else
                local capturedId = locId
                worldArea:AddChild(UI.Button {
                    text = loc.icon .. "  " .. locName,
                    width = "92%", height = 42, fontSize = 16,
                    fontWeight = "bold",
                    backgroundColor = TC.bgPanel,
                    borderWidth = 1, borderColor = TC.border,
                    borderRadius = 20,
                    color = TC.textPrimary,
                    onClick = function()
                        AddLog(">> 前往" .. (SCENE_NAMES[capturedId] or capturedId) .. "...", "info")
                        SendToServer(EV.REQ_MOVE_SCENE, { Scene = capturedId })
                        Client.SwitchPanel(PANEL.MAIN)
                    end,
                })
            end
        end
        wrapper:AddChild(worldArea)
        return wrapper
    end

    local spots  = (Settings.SCENE_SPOTS and Settings.SCENE_SPOTS[scene]) or {}
    local exits  = Settings.SCENE_EXITS[scene] or {}
    local scName = SCENE_NAMES[scene] or scene

    -- ── 外层容器（全高，垂直滚动）───────────────────────────
    local container = UI.Panel {
        width = "100%", flexGrow = 1,
        flexDirection = "column", alignItems = "center",
    }

    -- ── 标题行 ──────────────────────────────────────────────
    local titleRow = UI.Panel {
        width = "100%", height = 36, flexShrink = 0,
        flexDirection = "row", alignItems = "center", justifyContent = "center",
        borderBottomWidth = 1, borderColor = TC.borderLight,
        backgroundColor = TC.bgPanel,
    }
    titleRow:AddChild(UI.Label {
        text = "地图  ·  " .. scName,
        fontSize = 17, fontWeight = "bold", color = TC.textPrimary,
    })
    container:AddChild(titleRow)
    -- ── 构建方位网格（地点 + 连线）─────────────────────────
    if #spots > 0 then
        -- 1. 填入查找表
        local grid = {}
        local maxRow, maxCol = 0, 0
        for _, sp in ipairs(spots) do
            local r, c = sp.pos[1], sp.pos[2]
            if not grid[r] then grid[r] = {} end
            grid[r][c] = sp
            if r > maxRow then maxRow = r end
            if c > maxCol then maxCol = c end
        end

        -- 节点尺寸、连线尺寸
        local NODE_W   = 90
        local NODE_H   = 50
        local HCONN_W  = 28    -- 水平连线宽
        local VCONN_H  = 18    -- 垂直连线行高
        local ROW_GAP  = 0

        -- 2. 外层网格区域（居中）
        local mapArea = UI.Panel {
            width = "100%",
            flexDirection = "column", alignItems = "center", justifyContent = "center",
            gap = ROW_GAP, paddingVertical = 18,
        }

        -- 3. 渲染「交错行」：奇数行=地点行，偶数行=垂直连线行
        for r = 1, maxRow do
            -- ── 地点行 ──
            local spotRow = UI.Panel {
                flexDirection = "row", alignItems = "center", flexShrink = 0,
            }
            for c = 1, maxCol do
                local sp = grid[r] and grid[r][c]
                if sp then
                    local isHere = (currentSpot_ == sp.id)
                    -- 查找当前位置 pos 用于可达判断
                    local curPos2 = nil
                    if currentSpot_ then
                        for _, s2 in ipairs(spots) do
                            if s2.id == currentSpot_ then curPos2 = s2.pos; break end
                        end
                    end
                    local dr = curPos2 and math.abs(curPos2[1] - sp.pos[1]) or 0
                    local dc = curPos2 and math.abs(curPos2[2] - sp.pos[2]) or 0
                    local canReach = (currentSpot_ == nil)
                        or isHere
                        or (dr + dc == 1 and (dr == 0 or dc == 0))

                    -- 节点颜色
                    local bgC, bdC, txC
                    if isHere then
                        bgC = { 0, 50, 65, 255 }
                        bdC = { 0, 200, 220, 255 }
                        txC = { 60, 230, 245, 255 }
                    elseif canReach then
                        bgC = { 22, 20, 35, 230 }
                        bdC = { 90, 75, 50, 200 }
                        txC = { 200, 190, 165, 255 }
                    else
                        bgC = { 12, 10, 18, 170 }
                        bdC = { 35, 30, 45, 100 }
                        txC = { 80, 75, 95, 160 }
                    end

                    local capturedSpot = sp
                    local node = UI.Button {
                        width = NODE_W, height = NODE_H, flexShrink = 0,
                        flexDirection = "column", alignItems = "center", justifyContent = "center",
                        backgroundColor = bgC,
                        borderWidth = isHere and 2 or 1, borderColor = bdC,
                        borderRadius = 10,
                        gap = 1,
                        onClick = function()
                            if isHere then
                                -- 已在此地，直接切回主页
                                Client.SwitchPanel(PANEL.MAIN)
                                return
                            end
                            if not canReach then
                                AddLog("❌ 需先到达相邻地点才能前往 " .. capturedSpot.name, "warn")
                                return
                            end
                            currentSpot_ = capturedSpot.id
                            npcDialog_   = nil
                            AddLog(">> 前往 " .. capturedSpot.name .. "...", "info")
                            SendToServer(EV.REQ_CHANGE_SPOT, { Spot = capturedSpot.id })
                            Client.SwitchPanel(PANEL.MAIN)
                        end,
                    }
                    node:AddChild(UI.Label {
                        text = sp.name, fontSize = 15,
                        fontWeight = "bold",
                        color = txC, textAlign = "center",
                    })
                    spotRow:AddChild(node)
                else
                    -- 空格占位
                    spotRow:AddChild(UI.Panel { width = NODE_W, height = NODE_H, flexShrink = 0 })
                end

                -- 水平连线（在非最后列后渲染）
                if c < maxCol then
                    local spR  = grid[r] and grid[r][c]
                    local spR1 = grid[r] and grid[r][c + 1]
                    local hasH = spR and spR1
                    if hasH then
                        local connRow = UI.Panel {
                            width = HCONN_W, height = NODE_H, flexShrink = 0,
                            alignItems = "center", justifyContent = "center",
                        }
                        connRow:AddChild(UI.Label {
                            text = "─", fontSize = 18,
                            color = TC.textSecondary, textAlign = "center",
                        })
                        spotRow:AddChild(connRow)
                    else
                        spotRow:AddChild(UI.Panel { width = HCONN_W, height = NODE_H, flexShrink = 0 })
                    end
                end
            end
            mapArea:AddChild(spotRow)

            -- ── 垂直连线行（非最后行后渲染）──
            if r < maxRow then
                local connLineRow = UI.Panel {
                    flexDirection = "row", alignItems = "center", flexShrink = 0,
                }
                for c = 1, maxCol do
                    local spTop = grid[r]   and grid[r][c]
                    local spBot = grid[r+1] and grid[r+1][c]
                    local hasV  = spTop and spBot
                    local cell = UI.Panel {
                        width = NODE_W, height = VCONN_H, flexShrink = 0,
                        alignItems = "center", justifyContent = "center",
                    }
                    if hasV then
                        cell:AddChild(UI.Label {
                            text = "│", fontSize = 16,
                            color = TC.textSecondary, textAlign = "center",
                        })
                    end
                    connLineRow:AddChild(cell)
                    -- 水平连线列的占位（保持对齐）
                    if c < maxCol then
                        connLineRow:AddChild(UI.Panel { width = HCONN_W, height = VCONN_H, flexShrink = 0 })
                    end
                end
                mapArea:AddChild(connLineRow)
            end
        end

        container:AddChild(mapArea)
    end

    -- ── 分隔线 ──────────────────────────────────────────────
    container:AddChild(UI.Panel {
        width = "90%", height = 1, flexShrink = 0,
        backgroundColor = TC.borderLight, marginVertical = 6,
    })

    -- ── 世界地图（所有大地点列表）──────────────────────────
    container:AddChild(UI.Label {
        text = "世界地图",
        fontSize = 15, fontWeight = "bold", color = TC.textPrimary,
        alignSelf = "center", marginBottom = 8,
    })

    -- 构建可达目标集合（从当前场景出口获取）
    local reachableSet = {}
    for _, exit in ipairs(exits) do
        reachableSet[exit.to] = exit.name
    end

    -- 古村引导锁
    local tutorialLocked = (scene == "ancient_village")
        and ((player_ and (player_.tutorial_step or 0) or 0) < 3)

    -- 地点列表（固定顺序展示）
    local worldOrder = {
        { id = "ancient_village", icon = "🏘" },
        { id = "battlefield",     icon = "⚔️" },
        { id = "main_city",       icon = "🏯" },
        { id = "sword_sect",      icon = "⚔" },
        { id = "iron_sect",       icon = "🛡" },
        { id = "medicine_sect",   icon = "🧪" },
        { id = "shadow_sect",     icon = "🌑" },
        { id = "qidan_sect",      icon = "🔥" },
    }

    local worldArea = UI.Panel {
        width = "100%", flexDirection = "column",
        alignItems = "center", gap = 5, paddingHorizontal = 12,
    }

    for _, loc in ipairs(worldOrder) do
        local locId = loc.id
        local locName = SCENE_NAMES[locId] or locId
        local isHere = (locId == scene)

        if isHere then
            -- 当前所在：高亮青色胶囊
            local hereCard = UI.Panel {
                width = "92%", flexShrink = 0,
                flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                backgroundColor = TC.info,
                borderWidth = 2, borderColor = TC.info,
                borderRadius = 20, padding = { 4, 14 }, minHeight = 42,
            }
            hereCard:AddChild(UI.Label {
                text = loc.icon .. "  " .. locName .. "  （当前）",
                fontSize = 16, fontWeight = "bold", color = TC.info, flexGrow = 1,
            })
            -- 战场特殊：添加"查看层数"按钮
            if locId == "battlefield" then
                hereCard:AddChild(UI.Button {
                    text = "查看层数", fontSize = 11, height = 24,
                    paddingHorizontal = 10,
                    borderRadius = 12,
                    backgroundColor = TC.success,
                    color = TC.success,
                    onClick = function()
                        local mainArea = ui_.mainArea
                        if mainArea then
                            mainArea:RemoveAllChildren()
                            mainArea:AddChild(BuildBattlefieldLayerPanel())
                        end
                    end,
                })
            end
            worldArea:AddChild(hereCard)
        elseif tutorialLocked then
            -- 引导锁定：灰显胶囊
            worldArea:AddChild(UI.Panel {
                width = "92%", height = 42, flexShrink = 0,
                flexDirection = "row", alignItems = "center", justifyContent = "center",
                backgroundColor = TC.bgOverlay,
                borderWidth = 1, borderColor = TC.borderLight,
                borderRadius = 20,
                children = {
                    UI.Label {
                        text = loc.icon .. "  " .. locName .. "  （完成引导后解锁）",
                        fontSize = 15, color = TC.textMuted,
                    },
                },
            })
        else
            -- 所有地点可直接到达
            local capturedId = locId
            if capturedId == "battlefield" then
                -- 域外战场特殊：直接显示层数选择面板
                worldArea:AddChild(UI.Button {
                    text = loc.icon .. "  " .. locName,
                    width = "92%", height = 42, fontSize = 16,
                    fontWeight = "bold",
                    backgroundColor = TC.bgPanel,
                    borderWidth = 1, borderColor = TC.border,
                    borderRadius = 20,
                    color = TC.textPrimary,
                    onClick = function()
                        local mainArea = ui_.mainArea
                        if mainArea then
                            viewingBattlefieldLayers_ = true
                            mainArea:RemoveAllChildren()
                            -- 返回上一页按钮
                            mainArea:AddChild(UI.Button {
                                text = "← 返回上一页",
                                height = 32,
                                paddingHorizontal = 14,
                                fontSize = 16,
                                fontWeight = "bold",
                                borderRadius = 16,
                                backgroundColor = TC.bgPanelLight,
                                borderWidth = 1,
                                borderColor = TC.borderLight,
                                color = TC.textPrimary,
                                marginBottom = 4,
                                marginHorizontal = 6,
                                marginTop = 4,
                                flexShrink = 0,
                                onClick = function()
                                    viewingBattlefieldLayers_ = false
                                    -- 重建地图面板
                                    local ma = ui_.mainArea
                                    if ma then
                                        ma:RemoveAllChildren()
                                        -- 恢复返回主页按钮
                                        ma:AddChild(UI.Button {
                                            text = "← 返回主页",
                                            height = 32,
                                            paddingHorizontal = 14,
                                            fontSize = 16,
                                            fontWeight = "bold",
                                            borderRadius = 16,
                                            backgroundColor = TC.bgPanelLight,
                                            borderWidth = 1,
                                            borderColor = TC.borderLight,
                                            color = TC.textPrimary,
                                            marginBottom = 4,
                                            marginHorizontal = 6,
                                            marginTop = 4,
                                            flexShrink = 0,
                                            onClick = function()
                                                currentPanel_ = PANEL.MAIN
                                                RebuildMainContent()
                                                BuildSceneNav()
                                            end,
                                        })
                                        ma:AddChild(BuildMapPanel())
                                    end
                                end,
                            })
                            mainArea:AddChild(BuildBattlefieldLayerPanel())
                        end
                    end,
                })
            else
                worldArea:AddChild(UI.Button {
                    text = loc.icon .. "  " .. locName,
                    width = "92%", height = 42, fontSize = 16,
                    fontWeight = "bold",
                    backgroundColor = TC.bgPanel,
                    borderWidth = 1, borderColor = TC.border,
                    borderRadius = 20,
                    color = TC.textPrimary,
                    onClick = function()
                        AddLog(">> 前往" .. (SCENE_NAMES[capturedId] or capturedId) .. "...", "info")
                        SendToServer(EV.REQ_MOVE_SCENE, { Scene = capturedId })
                        Client.SwitchPanel(PANEL.MAIN)
                    end,
                })
            end
        end
    end

    container:AddChild(worldArea)

    return container
end

-- 构建功法面板
local function BuildSkillsPanel()
    local container = UI.Panel {
        width = "100%",
        padding = 8,
        gap = 4,
    }

    container:AddChild(UI.Label {
        text = "── 已修功法 ──",
        fontSize = 17,
        color = LOG_COLOR.title,
        marginBottom = 6,
        alignSelf = "center",
    })

    if not player_ or not player_.skills or #player_.skills == 0 then
        container:AddChild(UI.Label {
            text = "尚未习得任何功法",
            fontSize = 19,
            color = TC.textMuted,
            alignSelf = "center",
        })
        return container
    end

    for _, sk in ipairs(player_.skills) do
        local def = Shared.GetSkillDef(sk.id or sk.skill_id)
        if def then
            local card = UI.Panel {
                width = "100%",
                backgroundColor = TC.bgPanel,
                padding = { 6, 8 },
                marginBottom = 5,
            }

            local topRow = UI.Panel { flexDirection = "row", justifyContent = "space-between", alignItems = "center", marginBottom = 3 }
            local nameLbl = UI.Label {
                text = def.name .. (sk.bound and "  [绑定]" or "  [未绑定]"),
                fontSize = 17,
                color = sk.bound and LOG_COLOR.warn or LOG_COLOR.good,
            }
            topRow:AddChild(nameLbl)

            if not sk.bound then
                local unbindBtn = UI.Button {
                    text = "解绑",
                    fontSize = 16,
                    onClick = function()
                        AddLog(">> 解绑 " .. def.name .. "，功法将化为灵器回归背包...", "warn")
                        SendToServer(EV.REQ_UNBIND_SKILL, { SkillId = sk.id or sk.skill_id })
                    end,
                }
                topRow:AddChild(unbindBtn)
            end
            card:AddChild(topRow)

            local progress = def.max_proficiency > 0 and
                string.format("熟练度：%d / %d (%.0f%%)", math.floor(sk.proficiency or 0), math.floor(def.max_proficiency), (sk.proficiency or 0) / def.max_proficiency * 100)
                or "满级"
            card:AddChild(UI.Label { text = progress, fontSize = 19, color = LOG_COLOR.info })

            if def.stat_bonus then
                local STAT_NAMES = { atk = "攻击", def = "防御", agi = "身法", wis = "灵力", hp = "气血", mp = "内力" }
                local bonusText = ""
                for k, v in pairs(def.stat_bonus) do
                    bonusText = bonusText .. (STAT_NAMES[k] or k) .. "+" .. v .. " "
                end
                card:AddChild(UI.Label { text = "加成：" .. bonusText, fontSize = 16, color = TC.info })
            end

            container:AddChild(card)
        end
    end

    -- ── 出战技能槽配置 ────────────────────────────────────────
    container:AddChild(UI.Panel {
        width = "90%", height = 1, flexShrink = 0,
        backgroundColor = TC.bgPanel,
        marginVertical = 10, alignSelf = "center",
    })
    container:AddChild(UI.Label {
        text = "── 出战技能槽 ──",
        fontSize = 17, color = TC.rare,
        alignSelf = "center", marginBottom = 6,
    })
    container:AddChild(UI.Label {
        text = "最多配置 " .. Settings.BATTLE_SKILL_SLOTS .. " 个技能（不含固定普攻）",
        fontSize = 13, color = TC.textSecondary,
        alignSelf = "center", marginBottom = 6,
    })

    -- 读当前槽配置
    local currentSlots = (player_ and player_.battle_slots) or {}
    -- 可选技能：已学且非 normal 类型
    local availableSkills = {}
    if player_ and player_.skills then
        for _, sk in ipairs(player_.skills) do
            local def = Shared.GetSkillDef(sk.id or sk.skill_id)
            if def and (def.battle_type ~= "normal") then
                availableSkills[#availableSkills + 1] = def
            end
        end
    end

    -- 槽编辑区（临时状态用闭包局部变量）
    local editSlots = {}
    for i = 1, Settings.BATTLE_SKILL_SLOTS do
        editSlots[i] = currentSlots[i] or ""
    end

    -- 保存按钮（提前声明，更新函数引用它）
    local slotsContainer = UI.Panel {
        width = "100%", flexDirection = "column", gap = 5,
    }

    local function RebuildSlotRows()
        slotsContainer:ClearChildren()
        for i = 1, Settings.BATTLE_SKILL_SLOTS do
            local sid = editSlots[i]
            local def = sid ~= "" and Shared.GetSkillDef(sid) or nil
            local slotName = def and def.name or "（空）"

            local slotRow = UI.Panel {
                width = "100%", height = 36, flexShrink = 0,
                flexDirection = "row", alignItems = "center",
                backgroundColor = TC.bgPanel,
                borderWidth = 1, borderColor = TC.borderLight,
                paddingHorizontal = 8, gap = 6,
            }
            -- 槽序号
            slotRow:AddChild(UI.Label {
                text = "技能" .. i, fontSize = 13, width = 42,
                color = TC.textSecondary,
            })
            -- 当前名称
            slotRow:AddChild(UI.Label {
                text = slotName, flexGrow = 1, fontSize = 14,
                color = def and { 220, 210, 255, 255 } or { 100, 95, 130, 180 },
            })
            -- 循环选择按钮
            local prevBtn = UI.Button {
                text = "◀", fontSize = 13, width = 28, height = 28,
                backgroundColor = TC.bgPanel,
                onClick = function()
                    -- 向前循环（空 → 最后一个 → 倒数第二... ）
                    local cur = editSlots[i]
                    if cur == "" then
                        editSlots[i] = #availableSkills > 0 and availableSkills[#availableSkills].id or ""
                    else
                        local idx = 0
                        for j, d in ipairs(availableSkills) do
                            if d.id == cur then idx = j; break end
                        end
                        if idx <= 1 then
                            editSlots[i] = ""
                        else
                            editSlots[i] = availableSkills[idx - 1].id
                        end
                    end
                    RebuildSlotRows()
                end,
            }
            local nextBtn = UI.Button {
                text = "▶", fontSize = 13, width = 28, height = 28,
                backgroundColor = TC.bgPanel,
                onClick = function()
                    local cur = editSlots[i]
                    if cur == "" then
                        editSlots[i] = #availableSkills > 0 and availableSkills[1].id or ""
                    else
                        local idx = 0
                        for j, d in ipairs(availableSkills) do
                            if d.id == cur then idx = j; break end
                        end
                        if idx >= #availableSkills then
                            editSlots[i] = ""
                        else
                            editSlots[i] = availableSkills[idx + 1].id
                        end
                    end
                    RebuildSlotRows()
                end,
            }
            slotRow:AddChild(prevBtn)
            slotRow:AddChild(nextBtn)
            slotsContainer:AddChild(slotRow)
        end
    end
    RebuildSlotRows()
    container:AddChild(slotsContainer)

    -- 保存按钮
    container:AddChild(UI.Button {
        text = "保存出战配置", width = "80%", height = 36,
        alignSelf = "center", marginTop = 8,
        backgroundColor = TC.bgPanel,
        borderColor = TC.success,
        onClick = function()
            -- 过滤空槽
            local finalSlots = {}
            for _, sid in ipairs(editSlots) do
                if sid ~= "" then finalSlots[#finalSlots + 1] = sid end
            end
            battleSlots_ = finalSlots
            SendToServer(EV.REQ_SET_BATTLE_SLOTS, { Slots = cjson.encode(finalSlots) })
            AddLog(">> 出战技能槽已更新（" .. #finalSlots .. " 个）", "good")
        end,
    })

    return container
end

-- ============================================================================
-- 构建炼丹面板（仅器丹宗弟子可用）
-- ============================================================================
local function BuildAlchemyPanel()
    local container = UI.Panel {
        width = "100%",
        padding = 8,
        gap = 6,
    }

    container:AddChild(UI.Label {
        text = "── 炼丹炉 ──",
        fontSize = 17,
        color = LOG_COLOR.title,
        marginBottom = 4,
        alignSelf = "center",
    })

    if not player_ then return container end

    -- 非器丹宗弟子提示
    if player_.sect ~= "qidan_sect" then
        container:AddChild(UI.Label {
            text = "「丹术乃器丹宗不传之秘，外人不得窥探。」",
            fontSize = 15,
            color = TC.warning,
            alignSelf = "center",
            marginTop = 20,
        })
        container:AddChild(UI.Label {
            text = "（需加入器丹宗方可炼丹）",
            fontSize = 13,
            color = TC.textMuted,
            alignSelf = "center",
            marginTop = 8,
        })
        return container
    end

    -- 炼丹等级信息
    local alchemyLv = player_.alchemy_level or 0
    local alchemyExp = player_.alchemy_exp or 0
    local lvNames = { [0] = "未入门", "学徒", "熟练", "精通", "大师", "宗师" }
    local lvName = lvNames[alchemyLv] or "未知"
    local nextLvExp = (alchemyLv < 5) and ((alchemyLv + 1) * 100) or 0
    local expText = (alchemyLv < 5)
        and string.format("%s（经验 %d/%d）", lvName, alchemyExp, nextLvExp)
        or string.format("%s（已满级）", lvName)

    container:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = TC.bgPanel,
        padding = 8,
        borderRadius = 4,
        marginBottom = 6,
        children = {
            UI.Label {
                text = "炼丹等级：" .. expText,
                fontSize = 15,
                color = TC.warning,
            },
        },
    })

    -- 配方列表
    container:AddChild(UI.Label {
        text = "可炼配方：",
        fontSize = 15,
        color = LOG_COLOR.info,
        marginBottom = 4,
    })

    local recipes = Settings.ALCHEMY_RECIPES
    if not recipes then
        container:AddChild(UI.Label { text = "（无配方数据）", fontSize = 13, color = TC.textMuted })
        return container
    end

    -- 按 min_skill_level 排序显示
    local sortedKeys = {}
    for k, _ in pairs(recipes) do sortedKeys[#sortedKeys + 1] = k end
    table.sort(sortedKeys, function(a, b)
        return (recipes[a].min_skill_level or 0) < (recipes[b].min_skill_level or 0)
    end)

    for _, recipeId in ipairs(sortedKeys) do
        local recipe = recipes[recipeId]
        local pillDef = Settings.PILLS[recipeId]
        local pillName = pillDef and pillDef.name or recipe.name or recipeId
        local canCraft = alchemyLv >= (recipe.min_skill_level or 1)
        local rateText = string.format("%d%%", math.floor((recipe.success_rate or 0) * 100))

        -- 材料文本
        local matTexts = {}
        for _, mat in ipairs(recipe.materials or {}) do
            local matDef = Settings.ALCHEMY_MATERIALS[mat.id]
            local matName = matDef and matDef.name or mat.id
            matTexts[#matTexts + 1] = string.format("%s×%d", matName, mat.count or 1)
        end
        local matStr = table.concat(matTexts, "、")

        local row = UI.Panel {
            width = "100%",
            backgroundColor = canCraft and { 30, 40, 25, 200 } or { 30, 30, 30, 150 },
            padding = { 6, 8 },
            marginBottom = 4,
            borderRadius = 3,
            gap = 3,
        }

        -- 丹药名 + 成功率
        row:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = pillName,
                    fontSize = 15,
                    color = canCraft and { 255, 220, 100, 255 } or { 120, 120, 120, 255 },
                },
                UI.Label {
                    text = string.format("成功率%s  产出%d~%d", rateText, recipe.yield.min, recipe.yield.max),
                    fontSize = 12,
                    color = TC.textSecondary,
                },
            },
        })

        -- 所需材料
        row:AddChild(UI.Label {
            text = "材料：" .. matStr,
            fontSize = 12,
            color = TC.success,
        })

        -- 等级要求 + 炼制按钮
        if not canCraft then
            row:AddChild(UI.Label {
                text = string.format("（需炼丹等级 %d）", recipe.min_skill_level or 1),
                fontSize = 12,
                color = TC.danger,
            })
        else
            local capturedId = recipeId
            row:AddChild(UI.Button {
                text = "炼制",
                fontSize = 14,
                height = 28,
                width = "100%",
                backgroundColor = TC.warning,
                marginTop = 4,
                onClick = function()
                    SendToServer(EV.REQ_ALCHEMY_CRAFT, { RecipeId = capturedId })
                    AddLog(string.format(">> 点燃丹炉，开始炼制【%s】...", pillName), "system")
                end,
            })
        end

        container:AddChild(row)
    end

    -- 购买材料入口
    container:AddChild(UI.Panel {
        width = "100%",
        marginTop = 10,
        backgroundColor = TC.bgPanel,
        padding = 8,
        borderRadius = 4,
        gap = 4,
        children = {
            UI.Label {
                text = "── 药材商店 ──",
                fontSize = 14,
                color = TC.info,
                alignSelf = "center",
            },
        },
    })

    local shopItems = Settings.ALCHEMY_MATERIAL_SHOP or {}
    for _, item in ipairs(shopItems) do
        local matDef = Settings.ALCHEMY_MATERIALS[item.id]
        local matName = matDef and matDef.name or item.id
        local capturedId = item.id
        local capturedPrice = item.price

        container:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            backgroundColor = TC.bgOverlay,
            padding = { 4, 8 },
            marginBottom = 2,
            borderRadius = 2,
            children = {
                UI.Label {
                    text = string.format("%s  %d银", matName, capturedPrice),
                    fontSize = 13,
                    color = TC.textPrimary,
                    flexGrow = 1,
                },
                UI.Button {
                    text = "购买",
                    fontSize = 12,
                    height = 24,
                    paddingHorizontal = 10,
                    backgroundColor = TC.info,
                    onClick = function()
                        SendToServer(EV.REQ_BUY_MATERIAL, { MaterialId = capturedId, Count = 1 })
                        AddLog(string.format(">> 购买%s...", matName), "system")
                    end,
                },
            },
        })
    end

    return container
end

-- ============================================================================
-- 构建藏书阁面板（江湖tab·购买图纸）
-- ============================================================================
local function BuildLibraryPanel()
    local container = UI.Panel {
        width = "100%",
        padding = 8,
        gap = 6,
    }

    container:AddChild(UI.Label {
        text = "── 藏书阁·锻造图纸 ──",
        fontSize = 17,
        color = LOG_COLOR.title,
        marginBottom = 4,
        alignSelf = "center",
    })

    if not player_ then return container end

    local realmIndex = player_.realm or 1
    local learned = player_.blueprints_learned or {}

    -- 按 tier 收集可见图纸
    local bpList = {}
    for bpId, bp in pairs(Settings.BLUEPRINTS or {}) do
        if realmIndex >= bp.realm_req then
            bpList[#bpList + 1] = {
                id       = bpId,
                name     = bp.name,
                tier     = bp.tier,
                slot     = bp.slot,
                price    = bp.price,
                learned  = learned[bpId] and true or false,
            }
        end
    end
    table.sort(bpList, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        return a.id < b.id
    end)

    if #bpList == 0 then
        container:AddChild(UI.Label {
            text = "当前境界暂无可购图纸（筑基后解锁）",
            fontSize = 14,
            color = TC.textSecondary,
            alignSelf = "center",
            marginTop = 12,
        })
        return container
    end

    -- 说明
    container:AddChild(UI.Label {
        text = "购买图纸后可在【修炼→炼器】中锻造装备",
        fontSize = 12,
        color = TC.textSecondary,
        alignSelf = "center",
        marginBottom = 4,
    })

    local tierNames = { [2]="筑基", [3]="金丹", [4]="元婴", [5]="化神", [6]="大乘", [7]="渡劫" }
    local slotNames = { weapon="武器", helmet="头盔", armor="铠甲", boots="战靴", ring="戒指", necklace="项链" }
    local lastTier = 0

    for _, bp in ipairs(bpList) do
        -- 分组标题
        if bp.tier ~= lastTier then
            lastTier = bp.tier
            container:AddChild(UI.Label {
                text = string.format("【%s期·%d阶图纸】", tierNames[bp.tier] or "?", bp.tier),
                fontSize = 14,
                color = TC.textTitle,
                marginTop = 6,
                marginBottom = 2,
            })
        end

        local isLearned = bp.learned
        local row = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            backgroundColor = isLearned and { 20, 40, 20, 180 } or { 20, 30, 45, 200 },
            padding = { 5, 8 },
            marginBottom = 3,
            borderRadius = 3,
        }

        local nameColor = isLearned and { 80, 200, 80, 255 } or { 180, 220, 255, 255 }
        row:AddChild(UI.Label {
            text = string.format("[%s] %s", slotNames[bp.slot] or bp.slot, bp.name),
            fontSize = 14,
            color = nameColor,
        })

        if isLearned then
            row:AddChild(UI.Label {
                text = "✓ 已购买",
                fontSize = 12,
                color = TC.success,
            })
        else
            local capturedId = bp.id
            local capturedName = bp.name
            local capturedPrice = bp.price
            row:AddChild(UI.Button {
                text = string.format("购买（%s银）", Shared.FormatSilver(capturedPrice)),
                fontSize = 12,
                height = 26,
                paddingHorizontal = 8,
                backgroundColor = TC.info,
                onClick = function()
                    if (player_.silver or 0) < capturedPrice then
                        AddLog("<红>银两不足！</红>", "system")
                        return
                    end
                    SendToServer(EV.REQ_BUY_BLUEPRINT, { BlueprintId = capturedId })
                    AddLog(string.format(">> 正在购买【%s】...", capturedName), "system")
                end,
            })
        end

        container:AddChild(row)
    end

    return container
end

-- ============================================================================
-- 构建炼器面板（新系统·所有门派可用）
-- ============================================================================
local function BuildForgePanel()
    local container = UI.Panel {
        width = "100%",
        padding = 8,
        gap = 6,
    }

    container:AddChild(UI.Label {
        text = "── 锻造炉 ──",
        fontSize = 17,
        color = LOG_COLOR.title,
        marginBottom = 4,
        alignSelf = "center",
    })

    if not player_ then return container end

    local learned = player_.blueprints_learned or {}
    local isQidan = (player_.sect == "qidan_sect")

    -- 收集已学图纸
    local learnedList = {}
    for bpId, _ in pairs(learned) do
        local bp = Settings.BLUEPRINTS[bpId]
        if bp then
            learnedList[#learnedList + 1] = { id = bpId, bp = bp }
        end
    end
    table.sort(learnedList, function(a, b)
        if a.bp.tier ~= b.bp.tier then return a.bp.tier < b.bp.tier end
        return a.id < b.id
    end)

    if #learnedList == 0 then
        container:AddChild(UI.Label {
            text = "尚未购买任何图纸",
            fontSize = 14,
            color = TC.textSecondary,
            alignSelf = "center",
            marginTop = 12,
        })
        container:AddChild(UI.Label {
            text = "前往【江湖→藏书阁】购买图纸",
            fontSize = 12,
            color = TC.info,
            alignSelf = "center",
            marginTop = 6,
        })
        return container
    end

    -- 器丹宗优势提示
    if isQidan then
        container:AddChild(UI.Label {
            text = "器丹宗弟子：失败率降低，高品质概率提升",
            fontSize = 12,
            color = TC.success,
            alignSelf = "center",
            marginBottom = 4,
        })
    end

    local slotNames = { weapon="武器", helmet="头盔", armor="铠甲", boots="战靴", ring="戒指", necklace="项链" }
    local tierNames = { [2]="筑基", [3]="金丹", [4]="元婴", [5]="化神", [6]="大乘", [7]="渡劫" }
    local lastTier = 0

    for _, entry in ipairs(learnedList) do
        local bpId = entry.id
        local bp   = entry.bp
        local tier = bp.tier
        local recipe = Settings.FORGE.RECIPES[tier]

        -- 分组标题
        if tier ~= lastTier then
            lastTier = tier
            container:AddChild(UI.Label {
                text = string.format("【%s期·%d阶】", tierNames[tier] or "?", tier),
                fontSize = 14,
                color = TC.textTitle,
                marginTop = 6,
                marginBottom = 2,
            })
        end

        -- 材料信息：统计持有量
        local matStr = "材料：未配置"
        local haveMain, haveSub = 0, 0
        local needMain, needSub = 0, 0
        local canForge = false
        if recipe then
            local mainDef = Settings.ALCHEMY_MATERIALS[recipe.main.id]
            local subDef  = Settings.ALCHEMY_MATERIALS[recipe.sub.id]
            local mainName = mainDef and mainDef.name or recipe.main.id
            local subName  = subDef  and subDef.name  or recipe.sub.id
            needMain = recipe.main.count
            needSub  = recipe.sub.count
            -- 统计背包持有量
            for _, item in ipairs(inventory_) do
                if item.id == recipe.main.id then haveMain = haveMain + (item.count or 1) end
                if item.id == recipe.sub.id  then haveSub  = haveSub  + (item.count or 1) end
            end
            canForge = (haveMain >= needMain and haveSub >= needSub)
            matStr = string.format("材料：%s %d/%d + %s %d/%d",
                mainName, haveMain, needMain, subName, haveSub, needSub)
        end

        -- 失败率信息
        local failRates = Settings.FORGE.FAIL_RATE[tier]
        local failRate = failRates and (isQidan and failRates.qidan or failRates.normal) or 0.20
        local successPct = math.floor((1 - failRate) * 100)

        -- 保底信息
        local pityCount = (player_.forge_pity and player_.forge_pity[bpId]) or 0
        local pityMax = Settings.FORGE.PITY[tier] or 150

        local row = UI.Panel {
            width = "100%",
            backgroundColor = TC.bgPanel,
            padding = { 6, 8 },
            marginBottom = 4,
            borderRadius = 3,
            gap = 2,
        }

        -- 名称行
        row:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = string.format("[%s] %s", slotNames[bp.slot] or bp.slot, bp.equip_name or bp.name),
                    fontSize = 14,
                    color = TC.info,
                },
                UI.Label {
                    text = string.format("成功率%d%%", successPct),
                    fontSize = 12,
                    color = successPct >= 80 and {100,200,100,255} or {220,180,80,255},
                },
            },
        })

        -- 材料 + 保底
        row:AddChild(UI.Label {
            text = matStr,
            fontSize = 12,
            color = canForge and { 100, 200, 100, 255 } or { 220, 80, 80, 255 },
        })
        row:AddChild(UI.Label {
            text = string.format("史诗保底：%d/%d", pityCount, pityMax),
            fontSize = 11,
            color = TC.textPrimary,
        })

        -- 炼制按钮行
        local capturedBpId = bpId
        local capturedName = bp.equip_name or bp.name
        local btnColorEnabled  = { 30, 80, 140, 255 }
        local btnColorDisabled = { 60, 60, 60, 255 }

        local function makeForgeBtn(label, count)
            -- 检查 count 倍材料是否足够
            local enough = (haveMain >= needMain * count and haveSub >= needSub * count)
            local btn = UI.Button {
                text = label,
                fontSize = 13,
                height = 26,
                flex = 1,
                backgroundColor = enough and btnColorEnabled or btnColorDisabled,
                disabled = not enough,
                onClick = function()
                    SendToServer(EV.REQ_FORGE_NEW, { BlueprintId = capturedBpId, Count = count })
                    AddLog(string.format(">> 开始锻造【%s】×%d...", capturedName, count), "system")
                end,
            }
            return btn
        end

        row:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 6,
            marginTop = 4,
            children = {
                makeForgeBtn("炼制×1", 1),
                makeForgeBtn("炼制×5", 5),
                makeForgeBtn("炼制×10", 10),
            },
        })

        container:AddChild(row)
    end

    return container
end

local cachedGuildInfo_ = nil  -- 帮会详情缓存
local cachedGuildDaily_ = nil  -- 帮会日常任务缓存（来自 Server_OnReqGuildInfo）

-- ============================================================================
-- 构建帮会面板
-- ============================================================================
local function BuildGuildPanel()
    local container = UI.Panel {
        width = "100%",
        padding = 8,
        gap = 6,
    }

    container:AddChild(UI.Label {
        text = "── 帮会 ──",
        fontSize = 17,
        color = LOG_COLOR.title,
        marginBottom = 4,
        alignSelf = "center",
    })

    if not player_ then return container end

    local guildId = player_.guild_id or ""

    -- ════════════════════════════════════════════════════════════════
    -- 未加入帮会
    -- ════════════════════════════════════════════════════════════════
    if guildId == "" then
        container:AddChild(UI.Label {
            text = "尚未加入帮会",
            fontSize = 15,
            color = TC.textSecondary,
            alignSelf = "center",
            marginTop = 10,
        })

        -- 创建帮会
        local guildCfg = Settings.GUILD or {}
        local realmReq = guildCfg.CREATE_MIN_REALM or 2
        local costSilver = guildCfg.CREATE_COST_SILVER or 5000
        local canCreate = (player_.realm or 1) >= realmReq

        container:AddChild(UI.Panel {
            width = "100%",
            backgroundColor = TC.bgPanel,
            padding = 8, borderRadius = 4, marginTop = 8, gap = 4,
            children = {
                UI.Label {
                    text = string.format("创建帮会（需境界≥%s，花费%d银两）",
                        Settings.REALM.STAGES[realmReq] and Settings.REALM.STAGES[realmReq].name or "?", costSilver),
                    fontSize = 13,
                    color = canCreate and { 200, 200, 200, 255 } or { 120, 80, 80, 255 },
                },
            },
        })

        if canCreate then
            local guildNameField = UI.TextField {
                placeholder = "输入帮会名称(2-8字)",
                fontSize = 14, height = 32, width = "100%", marginTop = 6,
            }
            container:AddChild(guildNameField)
            container:AddChild(UI.Button {
                text = "创建帮会",
                fontSize = 14, height = 32, width = "100%",
                backgroundColor = TC.success, marginTop = 4,
                onClick = function()
                    local name = guildNameField:GetText() or ""
                    if #name < 2 then
                        AddLog("帮会名称至少需要2个字。", "system")
                        return
                    end
                    SendToServer(EV.REQ_CREATE_GUILD, { GuildName = name })
                    AddLog(string.format(">> 请求创建帮会【%s】...", name), "system")
                end,
            })
        end

        -- 加入帮会
        container:AddChild(UI.Panel {
            width = "100%",
            backgroundColor = TC.bgPanel,
            padding = 8, borderRadius = 4, marginTop = 12, gap = 4,
            children = {
                UI.Label { text = "加入已有帮会：", fontSize = 13, color = TC.textPrimary },
            },
        })

        local joinNameField = UI.TextField {
            placeholder = "输入要加入的帮会名称",
            fontSize = 14, height = 32, width = "100%", marginTop = 4,
        }
        container:AddChild(joinNameField)
        container:AddChild(UI.Button {
            text = "申请加入",
            fontSize = 14, height = 32, width = "100%",
            backgroundColor = TC.info, marginTop = 4,
            onClick = function()
                local name = joinNameField:GetText() or ""
                if #name < 1 then
                    AddLog("请输入帮会名称。", "system")
                    return
                end
                SendToServer(EV.REQ_JOIN_GUILD, { GuildName = name })
                AddLog(string.format(">> 申请加入帮会【%s】...", name), "system")
            end,
        })


        -- 浏览所有帮会
        container:AddChild(UI.Panel {
            width = "100%",
            backgroundColor = TC.bgPanel,
            padding = 8, borderRadius = 4, marginTop = 12, gap = 4,
            children = {
                UI.Label { text = "或浏览所有帮会：", fontSize = 13, color = TC.textPrimary },
            },
        })
        container:AddChild(UI.Button {
            text = "浏览帮会列表",
            fontSize = 14, height = 32, width = "100%",
            backgroundColor = TC.info, marginTop = 4,
            onClick = function()
                SendToServer(EV.REQ_GUILD_LIST, {})
                AddLog(">> 正在获取帮会列表...", "system")
            end,
        })
        return container
    end

    -- ════════════════════════════════════════════════════════════════
    -- 已有帮会 - 自动请求最新信息
    -- ════════════════════════════════════════════════════════════════
    local info = cachedGuildInfo_

    -- 如果没有缓存数据，先请求并显示加载中
    if not info then
        SendToServer(EV.REQ_GUILD_INFO, {})
        container:AddChild(UI.Label {
            text = "正在加载帮会信息...",
            fontSize = 14, color = TC.textSecondary,
            alignSelf = "center", marginTop = 20,
        })
        return container
    end

    -- ── 帮会基本信息卡片 ──
    local isLeader = (info.leader_name == (player_.name or ""))

    container:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = TC.bgPanel,
        padding = 10, borderRadius = 6, gap = 4,
        children = {
            UI.Label {
                text = "【" .. (info.name or "?") .. "】",
                fontSize = 18, color = TC.info, alignSelf = "center",
            },
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between",
                children = {
                    UI.Label { text = "帮主：" .. (info.leader_name or "?"), fontSize = 13, color = LOG_COLOR.gold },
                    UI.Label {
                        text = string.format("人数：%d/%d", info.member_count or 0, info.max_members or 20),
                        fontSize = 13, color = TC.textSecondary,
                    },
                },
            },
        },
    })

    -- ── 帮会公告 ──
    local noticeText = (info.notice and info.notice ~= "") and info.notice or "暂无公告"
    container:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = TC.bgPanel,
        padding = 8, borderRadius = 4, marginTop = 4, gap = 4,
        children = {
            UI.Label { text = "公告", fontSize = 12, color = TC.textSecondary },
            UI.Label { text = noticeText, fontSize = 13, color = TC.textPrimary },
        },
    })

    -- 帮主可编辑公告
    if isLeader then
        local noticeField = UI.TextField {
            placeholder = "输入新公告（最多100字）",
            fontSize = 13, height = 30, width = "100%", marginTop = 4,
        }
        container:AddChild(noticeField)
        container:AddChild(UI.Button {
            text = "更新公告",
            fontSize = 13, height = 28, width = "100%",
            backgroundColor = TC.success, marginTop = 2,
            onClick = function()
                local text = noticeField:GetText() or ""
                if #text < 1 then
                    AddLog("公告不能为空。", "system")
                    return
                end
                SendToServer(EV.REQ_SET_GUILD_NOTICE, { Notice = text })
            end,
        })

        -- 帮会改名（仅帮主可见）
        local guildRenameCost = Settings.SPIRIT_STONE.GUILD_RENAME_COST
        local guildRenameField = UI.TextField {
            placeholder = "新帮会名(2-8字)", fontSize = 12, height = 28, width = "100%", marginTop = 4,
        }
        container:AddChild(guildRenameField)
        container:AddChild(UI.Button {
            text = "💎帮会改名(" .. guildRenameCost .. "灵石)",
            fontSize = 12, height = 28, width = "100%",
            variant = "outline", marginTop = 2,
            onClick = function()
                local newName = guildRenameField:GetText() or ""
                if newName == "" then
                    AddLog("请输入新帮会名。", "warning")
                    return
                end
                if (player_.spirit_stone or 0) < guildRenameCost then
                    AddLog("灵石不足！帮会改名需要 " .. guildRenameCost .. " 灵石。", "warning")
                    return
                end
                SendToServer(EV.REQ_GUILD_RENAME, { NewName = newName })
                AddLog(">> 正在修改帮会名称...", "system")
            end,
        })
    end

    -- ── 帮会等级与资金 ──
    local guildLvl = info.level or 1
    local guildFund = info.fund or 0
    local guildExp = info.exp or 0
    local gCfg = Settings.GUILD
    local maxLvl = gCfg.MAX_LEVEL or 10
    local lvCfg = gCfg.LEVELS and gCfg.LEVELS[guildLvl]
    local nextCfg = gCfg.LEVELS and gCfg.LEVELS[guildLvl + 1]
    local cultBonus = info.cult_bonus or 1.0
    local combatBonus = info.combat_bonus or 0
    local silverBonus = info.silver_bonus or 0

    local lvlChildren = {
        UI.Label { text = string.format("\xe7\xad\x89\xe7\xba\xa7\xef\xbc\x9a%d/%d", guildLvl, maxLvl), fontSize = 13, color = TC.textAccent },
        UI.Label { text = string.format("\xe8\xb5\x84\xe9\x87\x91\xef\xbc\x9a%d", guildFund), fontSize = 12, color = TC.textPrimary },
    }
    if nextCfg then
        lvlChildren[#lvlChildren + 1] = UI.Label {
            text = string.format("\xe5\x8d\x87\xe7\xba\xa7\xe9\x9c\x80\xe8\xa6\x81\xef\xbc\x9a\xe7\xbb\x8f\xe9\xaa\x8c%d/%d \xe8\xb5\x84\xe9\x87\x91%d/%d", guildExp, nextCfg.exp, guildFund, nextCfg.fund),
            fontSize = 11, color = TC.textSecondary,
        }
    else
        lvlChildren[#lvlChildren + 1] = UI.Label { text = "\xe5\xb7\xb2\xe6\xbb\xa1\xe7\xba\xa7", fontSize = 11, color = TC.success }
    end
    -- BUFF\xe5\x8a\xa0\xe6\x88\x90\xe6\x98\xbe\xe7\xa4\xba
    if cultBonus > 1.0 or combatBonus > 0 or silverBonus > 0 then
        local buffStr = string.format("\xe4\xbf\xae\xe7\x82\xbc\xc3\x97%.2f \xe6\x94\xbb\xe5\x87\xbb+%d \xe9\x93\xb6\xe4\xb8\xa4+%d%%", cultBonus, combatBonus, math.floor(silverBonus * 100))
        lvlChildren[#lvlChildren + 1] = UI.Label { text = "\xe5\x8a\xa0\xe6\x88\x90\xef\xbc\x9a" .. buffStr, fontSize = 11, color = TC.success }
    end

    container:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = TC.bgPanel,
        padding = 8, borderRadius = 4, marginTop = 6, gap = 3,
        children = lvlChildren,
    })

    -- ── 捐献操作 ──
    local donateOpts = gCfg.DONATE_OPTIONS or {}
    local donateChildren = { UI.Label { text = "\xe6\x8d\x90\xe7\x8c\xae\xe5\xb8\xae\xe4\xbc\x9a", fontSize = 13, color = TC.info } }
    for _, opt in ipairs(donateOpts) do
        donateChildren[#donateChildren + 1] = UI.Button {
            text = string.format("%s(%d\xe9\x93\xb6)", opt.label, opt.silver),
            fontSize = 12, height = 26, width = "100%",
            backgroundColor = TC.info, marginTop = 2,
            onClick = function()
                SendToServer(EV.REQ_GUILD_DONATE, { OptionId = opt.id })
                AddLog(">> \xe6\x8d\x90\xe7\x8c\xae" .. opt.label .. "...", "system")
            end,
        }
    end
    container:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = TC.bgPanel,
        padding = 8, borderRadius = 4, marginTop = 6, gap = 3,
        children = donateChildren,
    })

    -- ── 灵石加速升级 ──
    if nextCfg then
        local boostCost = Settings.SPIRIT_STONE.GUILD_BOOST_COST
        local boostExp = Settings.SPIRIT_STONE.GUILD_BOOST_EXP
        container:AddChild(UI.Button {
            text = string.format("💎灵石加速(-%d灵石 +%d帮会经验)", boostCost, boostExp),
            fontSize = 12, height = 28, width = "100%",
            variant = "warning", marginTop = 4,
            onClick = function()
                if (player_.spirit_stone or 0) < boostCost then
                    AddLog(string.format("灵石不足！加速需要 %d 灵石。", boostCost), "warning")
                    return
                end
                SendToServer(EV.REQ_GUILD_BOOST, {})
                AddLog(">> 消耗灵石加速帮会升级...", "system")
            end,
        })
    end

    -- ── 升级按钮 ──
    if nextCfg and isLeader then
        local canUpgrade = guildExp >= nextCfg.exp and guildFund >= nextCfg.fund
        container:AddChild(UI.Button {
            text = canUpgrade and "\xe5\x8d\x87\xe7\xba\xa7\xe5\xb8\xae\xe4\xbc\x9a" or "\xe5\x8d\x87\xe7\xba\xa7(\xe6\x9d\xa1\xe4\xbb\xb6\xe4\xb8\x8d\xe8\xb6\xb3)",
            fontSize = 13, height = 30, width = "100%",
            backgroundColor = canUpgrade and { 60, 130, 60, 255 } or { 60, 60, 60, 200 },
            marginTop = 4,
            onClick = function()
                if canUpgrade then
                    SendToServer(EV.REQ_GUILD_UPGRADE, {})
                else
                    AddLog("\xe5\xb8\xae\xe4\xbc\x9a\xe7\xbb\x8f\xe9\xaa\x8c\xe6\x88\x96\xe8\xb5\x84\xe9\x87\x91\xe4\xb8\x8d\xe8\xb6\xb3\xef\xbc\x8c\xe6\x97\xa0\xe6\xb3\x95\xe5\x8d\x87\xe7\xba\xa7\xe3\x80\x82", "warning")
                end
            end,
        })
    end

    -- ── 占领据点 ──
    local sp = info.strongpoint  -- 单个据点对象或 nil
    local spChildren = {}
    spChildren[#spChildren + 1] = UI.Label {
        text = sp and "占领据点" or "占领据点（无）",
        fontSize = 13, color = TC.success,
    }
    if sp then
        spChildren[#spChildren + 1] = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            paddingHorizontal = 4, gap = 6, marginTop = 4,
            children = {
                UI.Label { text = "·", fontSize = 13, color = TC.success },
                UI.Label {
                    text = string.format("%s（第%d层）", sp.name or "?", sp.layer or 0),
                    fontSize = 12, color = TC.success, flex = 1,
                },
                UI.Button {
                    text = "前往据点",
                    fontSize = 11, paddingHorizontal = 10, paddingVertical = 4,
                    backgroundColor = TC.success,
                    color = TC.textPrimary, borderRadius = 3,
                    onClick = function()
                        SendToServer(EV.REQ_ENTER_LAYER, { Layer = sp.layer })
                    end,
                },
            },
        }
        if sp.bonus_desc and sp.bonus_desc ~= "" then
            spChildren[#spChildren + 1] = UI.Label {
                text = "   加成：" .. sp.bonus_desc,
                fontSize = 11, color = TC.textSecondary, marginLeft = 8,
            }
        end
    else
        spChildren[#spChildren + 1] = UI.Label {
            text = "   尚未占领任何据点，前往第3/8层争夺！",
            fontSize = 12, color = TC.textMuted, marginLeft = 8,
        }
    end
    container:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = TC.bgPanel,
        padding = 8, borderRadius = 4, marginTop = 6, gap = 3,
        children = spChildren,
    })

    -- ── 成员列表 ──
    local members = info.members or {}
    container:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = TC.bgPanel,
        padding = 8, borderRadius = 4, marginTop = 6, gap = 2,
        children = {
            UI.Label {
                text = "成员列表",
                fontSize = 13, color = TC.info,
            },
        },
    })

    local ROLE_NAMES = (Settings.GUILD and Settings.GUILD.ROLE_NAMES) or {}
    local ROLES = (Settings.GUILD and Settings.GUILD.ROLES) or {}
    for _, m in ipairs(members) do
        local mRole = m.role or "member"
        local roleName = ROLE_NAMES[mRole] or "成员"
        local roleColor = mRole == "leader" and LOG_COLOR.gold
            or mRole == "vice_leader" and { 255, 180, 80, 255 }
            or mRole == "elder" and { 140, 200, 140, 255 }
            or { 160, 160, 180, 200 }
        local realmStr = Settings.REALM.GetDisplayName(m.realm or 1, m.realm_layer or 1)
        local onlineColor = m.online and { 80, 220, 80, 255 } or { 100, 100, 100, 200 }
        local nameColor = mRole == "leader" and LOG_COLOR.gold or { 210, 210, 230, 255 }

        local rowChildren = {
            UI.Label {
                text = m.online and "●" or "○",
                fontSize = 10, color = onlineColor, width = 14,
            },
            UI.Label {
                text = string.format("[%s] %s", roleName, m.name or "?"),
                fontSize = 13, color = nameColor, flexGrow = 1,
            },
            UI.Label {
                text = string.format("%s C:%d", realmStr, m.contribution or 0),
                fontSize = 10, color = TC.textSecondary,
            },
        }

        -- 帮主可对其他成员执行踢出/转让/设置职位
        if isLeader and mRole ~= "leader" and m.uid then
            -- 职位设置按钮
            local roleActions = {}
            if mRole ~= "vice_leader" then
                roleActions[#roleActions + 1] = { role = "vice_leader", label = "副帮" }
            end
            if mRole ~= "elder" then
                roleActions[#roleActions + 1] = { role = "elder", label = "长老" }
            end
            if mRole ~= "member" then
                roleActions[#roleActions + 1] = { role = "member", label = "成员" }
            end
            for _, ra in ipairs(roleActions) do
                rowChildren[#rowChildren + 1] = UI.Button {
                    text = ra.label,
                    fontSize = 9, paddingHorizontal = 4, paddingVertical = 1,
                    backgroundColor = TC.info, borderRadius = 3,
                    onClick = function()
                        SendToServer(EV.REQ_SET_GUILD_ROLE, { TargetUid = m.uid, Role = ra.role })
                    end,
                }
            end
            rowChildren[#rowChildren + 1] = UI.Button {
                text = "转让",
                fontSize = 10, paddingHorizontal = 6, paddingVertical = 2,
                backgroundColor = TC.success, borderRadius = 3,
                onClick = function()
                    SendToServer(EV.REQ_TRANSFER_LEADER, { TargetUid = m.uid })
                    AddLog(string.format(">> 请求转让帮主给【%s】...", m.name or "?"), "system")
                end,
            }
            rowChildren[#rowChildren + 1] = UI.Button {
                text = "踢出",
                fontSize = 10, paddingHorizontal = 6, paddingVertical = 2,
                backgroundColor = TC.btnPrimary, borderRadius = 3,
                onClick = function()
                    SendToServer(EV.REQ_KICK_MEMBER, { TargetUid = m.uid })
                    AddLog(string.format(">> 请求踢出【%s】...", m.name or "?"), "system")
                end,
            }
        end

        container:AddChild(UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            paddingHorizontal = 10, paddingVertical = 3, gap = 4, flexWrap = "wrap",
            backgroundColor = mRole == "leader" and { 40, 35, 20, 150 } or { 0, 0, 0, 0 },
            children = rowChildren,
        })
    end

    -- ── 帮会日常任务 ──
    if not cachedGuildDaily_ then
        SendToServer(EV.REQ_GUILD_DAILY, {})
    end
    local dailyCfg = Settings.GUILD.DAILY_TASKS or {}
    local dailyProgress = cachedGuildDaily_ or {}
    local dailyChildren = { UI.Label { text = "\xe5\xb8\xae\xe4\xbc\x9a\xe6\x97\xa5\xe5\xb8\xb8", fontSize = 13, color = TC.textTitle } }
    for _, task in ipairs(dailyCfg) do
        local prog = dailyProgress[task.id] or { count = 0, claimed = false }
        local done = prog.count >= task.goal
        local claimed = prog.claimed
        local statusText = claimed and "\xe2\x9c\x93\xe5\xb7\xb2\xe9\xa2\x86" or (done and "\xe5\x8f\xaf\xe9\xa2\x86\xe5\x8f\x96" or string.format("%d/%d", prog.count, task.goal))
        local statusColor = claimed and { 100, 180, 100, 200 } or (done and { 255, 220, 60, 255 } or { 180, 180, 180, 200 })
        local taskRow = {
            UI.Label { text = task.name, fontSize = 12, color = TC.textPrimary, width = 70 },
            UI.Label { text = task.desc, fontSize = 10, color = TC.textSecondary, flexGrow = 1 },
            UI.Label { text = statusText, fontSize = 11, color = statusColor, width = 50 },
        }
        if done and not claimed then
            taskRow[#taskRow + 1] = UI.Button {
                text = "\xe9\xa2\x86\xe5\x8f\x96",
                fontSize = 10, paddingHorizontal = 6, paddingVertical = 2,
                backgroundColor = TC.success, borderRadius = 3,
                onClick = function()
                    SendToServer(EV.REQ_CLAIM_GUILD_TASK, { TaskId = task.id })
                end,
            }
        end
        dailyChildren[#dailyChildren + 1] = UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", gap = 4,
            paddingVertical = 2,
            children = taskRow,
        }
    end
    container:AddChild(UI.Panel {
        width = "100%",
        backgroundColor = TC.bgPanel,
        padding = 8, borderRadius = 4, marginTop = 6, gap = 3,
        children = dailyChildren,
    })

    -- ── 操作按钮 ──
    container:AddChild(UI.Panel {
        width = "100%", flexDirection = "row", gap = 8, marginTop = 10,
        children = {
            UI.Button {
                text = "刷新",
                fontSize = 13, height = 30, flexGrow = 1,
                backgroundColor = TC.info,
                onClick = function()
                    SendToServer(EV.REQ_GUILD_INFO, {})
                end,
            },
            UI.Button {
                text = "退出帮会",
                fontSize = 13, height = 30, flexGrow = 1,
                backgroundColor = TC.btnPrimary,
                onClick = function()
                    SendToServer(EV.REQ_LEAVE_GUILD, {})
                    AddLog(">> 请求退出帮会...", "system")
                end,
            },
        },
    })

    return container
end

-- ============================================================================
-- 构建域外战场层选择面板
-- ============================================================================
BuildBattlefieldLayerPanel = function()

    local container = UI.Panel {
        width = "100%",
        padding = 8,
        gap = 6,
    }

    container:AddChild(UI.Label {
        text = "── 域外战场 ──",
        fontSize = 17,
        color = LOG_COLOR.title,
        marginBottom = 4,
        alignSelf = "center",
    })

    if not player_ then
        return container
    end

    local playerRealm = player_.realm or 1
    local playerLayer = player_.layer or 1
    local layers = Settings.BATTLEFIELD_LAYERS or {}

    container:AddChild(UI.Label {
        text = "选择进入的战场层数：",
        fontSize = 14,
        color = TC.textPrimary,
        marginBottom = 4,
    })

    local maxLayer = player_ and player_.max_battlefield_layer or Settings.BATTLEFIELD_INITIAL_LAYERS
    local bossDefeated = (player_ and player_.boss_defeated) or {}

    for i = 1, 10 do
        local layerDef = layers[i]
        if not layerDef then goto continue end

        -- 解锁条件：层数 <= maxLayer，或者该层守关 Boss 已被击败
        local canEnter = (i <= maxLayer)
        if not canEnter then
            local guard = Settings.LAYER_GUARD[i]
            if guard then
                for _, bid in ipairs(bossDefeated) do
                    if bid == guard.id then canEnter = true; break end
                end
            end
        end
        local isGuild = layerDef.is_guild_zone

        -- 颜色
        local nameColor = canEnter
            and (isGuild and { 100, 255, 180, 255 } or { 220, 220, 255, 255 })
            or { 100, 100, 100, 255 }

        local capturedI_row = i
        local capturedName_row = layerDef.name
        local row = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            backgroundColor = canEnter
                and (isGuild and { 20, 40, 30, 200 } or { 25, 25, 40, 200 })
                or { 30, 30, 30, 120 },
            padding = { 6, 8 },
            marginBottom = 3,
            borderRadius = 3,
            -- 整行可点击（备用入口：即使按钮 hit-test 异常，行本身也可以响应）
            onClick = canEnter and function(self)
                SendToServer(EV.REQ_ENTER_LAYER, { Layer = capturedI_row })
                AddLog(string.format(">> 进入%s...", capturedName_row), "system")
            end or nil,
        }

        -- 层名 + 描述
        local labelText = layerDef.name
        if isGuild then
            labelText = labelText .. string.format(" [帮会×%.1f]", layerDef.guild_bonus or 1.0)
        end
        row:AddChild(UI.Label {
            text = labelText,
            fontSize = 14,
            color = nameColor,
            flexGrow = 1,
        })

        -- 锁/进入按钮
        if not canEnter then
            -- 使用 LAYER_GUARD 表获取该层独立的守关怪物
            local guard = Settings.LAYER_GUARD[i]
            if guard then
                local capturedBossId = guard.id
                local guardName = guard.name
                row:AddChild(UI.Button {
                    text = string.format("⚔ 挑战【%s】", guardName),
                    fontSize = 12,
                    height = 28,
                    minWidth = 90,
                    paddingHorizontal = 10,
                    borderRadius = 4,
                    backgroundColor = TC.btnPrimary,
                    onClick = function(self)
                        self:SetText("挑战中...")
                        self:SetDisabled(true)
                        SendToServer(EV.REQ_CHALLENGE_BOSS, { BossId = capturedBossId })
                        AddLog(string.format(">> 向【%s】发起挑战！", guardName), "system")
                    end,
                })
            else
                row:AddChild(UI.Label {
                    text = "🔒 未解锁",
                    fontSize = 12,
                    color = TC.danger,
                })
            end
        else
            local capturedI = i
            local capturedName = layerDef.name
            row:AddChild(UI.Button {
                text = "⚔ 进入战斗",
                fontSize = 13,
                height = 30,
                minWidth = 80,
                paddingHorizontal = 14,
                borderRadius = 4,
                backgroundColor = isGuild and { 30, 100, 60, 255 } or { 60, 70, 140, 255 },
                onClick = function(self)
                    self:SetText("进入中...")
                    self:SetDisabled(true)
                    SendToServer(EV.REQ_ENTER_LAYER, { Layer = capturedI })
                    AddLog(string.format(">> 进入%s...", capturedName), "system")
                end,
            })
        end

        container:AddChild(row)
        ::continue::
    end

    -- 底部提示
    container:AddChild(UI.Label {
        text = "提示：击败怪物可获得矿石等锻造材料",
        fontSize = 12,
        color = TC.textSecondary,
        marginTop = 8,
        alignSelf = "center",
    })

    return container
end

-- 构建修炼面板
local function BuildCultivatePanel()
    local container = UI.Panel {
        width = "100%",
        padding = 8,
        gap = 6,
    }

    container:AddChild(UI.Label {
        text = "── 打坐修炼 ──",
        fontSize = 17,
        color = LOG_COLOR.title,
        marginBottom = 4,
        alignSelf = "center",
    })

    if not player_ then return container end

    local potentialLbl = UI.Label {
        text = "剩余潜能：" .. math.floor(player_.potential or 0),
        fontSize = 16,
        color = LOG_COLOR.gold,
        marginBottom = 8,
        alignSelf = "center",
    }
    container:AddChild(potentialLbl)

    -- 当前修炼状态
    if player_.cultivating and player_.cultivating ~= "" then
        local def = Shared.GetSkillDef(player_.cultivating)
        local cultivName = def and def.name or player_.cultivating
        container:AddChild(UI.Label {
            text = "【正在修炼】" .. cultivName,
            fontSize = 16,
            color = LOG_COLOR.good,
            marginBottom = 6,
            alignSelf = "center",
        })
        local stopBtn = UI.Button {
            text = "停止打坐",
            width = "80%",
            alignSelf = "center",
            marginBottom = 8,
            onClick = function()
                SendToServer(EV.REQ_STOP_CULTIVATE)
                AddLog(">> 收功，停止修炼。", "info")
                -- 立即清除本地状态并刷新面板（不等服务端回包）
                player_.cultivating = nil
                Client.SwitchPanel(currentPanel_)
            end,
        }
        container:AddChild(stopBtn)
    end

    -- 可修炼的功法列表
    container:AddChild(UI.Label {
        text = "选择修炼：",
        fontSize = 19,
        color = LOG_COLOR.info,
        marginBottom = 4,
    })

    if not player_.skills or #player_.skills == 0 then
        container:AddChild(UI.Label {
            text = "（尚无可修炼的功法）",
            fontSize = 19,
            color = TC.textMuted,
        })
    else
        for _, sk in ipairs(player_.skills) do
            local def = Shared.GetSkillDef(sk.id)
            if def then
                local maxed = sk.proficiency >= def.max_proficiency
                local isCurrent = player_.cultivating == sk.id
                local row = UI.Panel {
                    width = "100%",
                    backgroundColor = TC.bgPanel,
                    padding = { 5, 8 },
                    marginBottom = 3,
                }
                -- 第一行：功法名 + 按钮/状态
                local topRow = UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                }
                topRow:AddChild(UI.Label {
                    text = def.name .. (maxed and "  [已满]" or ""),
                    fontSize = 16,
                    color = maxed and { 100, 100, 100, 255 } or LOG_COLOR.info,
                    flexGrow = 1,
                })
                if not maxed then
                    -- 判断是否阶段刚满（进度100%但功法未满级）→ 显示"继续打坐"
                    local _, _, tp = Shared.GetProficiencyTier(sk.proficiency, def.max_proficiency)
                    local btnText = (tp >= 0.999 and sk.proficiency > 0) and "继续打坐" or "打坐"
                    local btn = UI.Button {
                        text = btnText,
                        fontSize = 19,
                        onClick = function()
                            -- 潜能不足检查
                            if (player_.potential or 0) <= 0 then
                                AddLog("潜能不足，无法修炼！先去打怪积攒潜能吧。", "warning")
                                return
                            end
                            -- 展开滑条：标记此功法为"选中"状态，重建面板
                            cultivateSlider_ = { skillId = sk.id, value = 1 }
                            Client.SwitchPanel(currentPanel_)
                        end,
                    }
                    Tutorial.RegisterTarget("cultivate_btn", btn)
                    -- 如果当前正在展开此功法的滑条，隐藏按钮
                    if not (cultivateSlider_ and cultivateSlider_.skillId == sk.id) then
                        topRow:AddChild(btn)
                    end
                elseif maxed then
                    -- 升阶按钮（熟练度满后可用灵石升阶）
                    local curTier = sk.tier or 0
                    local maxTier = Settings.SKILL_TIER_UP.MAX_TIER
                    local tierInfo = Settings.SKILL_TIER_UP.TIERS[curTier + 1]
                    local tierName = tierInfo and tierInfo.name or "大成"
                    if curTier < maxTier then
                        local tierCost = Settings.SKILL_TIER_UP.COSTS[curTier]
                        local nextInfo = Settings.SKILL_TIER_UP.TIERS[curTier + 2]
                        local nextName = nextInfo and nextInfo.name or "大成"
                        topRow:AddChild(UI.Button {
                            text = string.format("💎升阶→%s(-%d灵石)", nextName, tierCost),
                            fontSize = 12, variant = "warning", marginLeft = 4,
                            onClick = function()
                                if (player_.spirit_stone or 0) < tierCost then
                                    AddLog(string.format("灵石不足！升阶需要 %d 灵石。", tierCost), "warning")
                                    return
                                end
                                SendToServer(EV.REQ_SKILL_TIER_UP, { SkillId = sk.id })
                                AddLog(">> 消耗灵石，提升功法阶层...", "system")
                            end,
                        })
                    end
                    topRow:AddChild(UI.Label {
                        text = "[" .. tierName .. "]",
                        fontSize = 13, color = LOG_COLOR.gold, marginLeft = 4,
                    })
                end
                row:AddChild(topRow)

                -- 滑条面板：当此功法被选中展开时显示
                if cultivateSlider_ and cultivateSlider_.skillId == sk.id then
                    local potential = player_.potential or 0
                    local costMult = Settings.CULTIVATE_COST_MULT.SELF
                    local maxBudget, _ = Shared.CalcCultivateBudgetCap(
                        sk.proficiency, def.max_proficiency, def.grade, potential, costMult)
                    local profPerSec, drainPerSec = Shared.CalcCultivateRate(def.grade, def.max_proficiency, costMult)
                    local profPerPotential = profPerSec / drainPerSec

                    -- 滑条初始值 = 上限（默认全投）
                    local sliderValue = cultivateSlider_.value or maxBudget

                    local sliderPanel = UI.Panel {
                        width = "100%",
                        backgroundColor = { 30, 40, 30, 255 },
                        borderRadius = 4,
                        padding = { 8, 8 },
                        marginTop = 4,
                        gap = 6,
                    }

                    -- 预估熟练度增量（服务端修炼到阶段边界会停止，客户端预览需模拟此行为）
                    local estGain = sliderValue * profPerPotential
                    local curTier, _, curTierProgress = Shared.GetProficiencyTier(sk.proficiency, def.max_proficiency)
                    local newProf = math.min(def.max_proficiency, sk.proficiency + estGain)
                    local newTier, _, newTierProgress = Shared.GetProficiencyTier(newProf, def.max_proficiency)
                    -- 服务端会在阶段边界停止，预览也应显示100%而非跨入下阶的0%
                    if newTier > curTier and newProf < def.max_proficiency then
                        newTierProgress = 1.0
                    end
                    local curPct = math.floor(curTierProgress * 100)
                    local newPct = math.floor(newTierProgress * 100)

                    local previewLabel = UI.Label {
                        id = "cultivate_preview",
                        text = string.format("投入潜能：%d / %d    预计：%d%% → %d%%", sliderValue, maxBudget, curPct, newPct),
                        fontSize = 14,
                        color = TC.textSecondary,
                    }
                    sliderPanel:AddChild(previewLabel)

                    -- 滑条
                    sliderPanel:AddChild(UI.Slider {
                        value = sliderValue,
                        min = 1,
                        max = maxBudget,
                        step = 1,
                        width = "100%",
                        onChange = function(self, v)
                            cultivateSlider_.value = math.floor(v)
                            local eg = cultivateSlider_.value * profPerPotential
                            local np2 = math.min(def.max_proficiency, sk.proficiency + eg)
                            local nt, _, np = Shared.GetProficiencyTier(np2, def.max_proficiency)
                            if nt > curTier and np2 < def.max_proficiency then
                                np = 1.0
                            end
                            local npPct = math.floor(np * 100)
                            previewLabel:SetText(string.format(
                                "投入潜能：%d / %d    预计：%d%% → %d%%",
                                cultivateSlider_.value, maxBudget, curPct, npPct))
                        end,
                    })

                    -- 按钮行
                    local btnRow = UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "center",
                        gap = 12,
                        marginTop = 4,
                    }
                    btnRow:AddChild(UI.Button {
                        text = "确认修炼",
                        fontSize = 16,
                        variant = "primary",
                        onClick = function()
                            local budget = cultivateSlider_.value or maxBudget
                            SendToServer(EV.REQ_CULTIVATE, { SkillId = sk.id, Budget = budget })
                            AddLog(string.format(">> 投入 %d 潜能修炼《%s》……", budget, def.name), "system")
                            cultivateSlider_ = nil
                            Tutorial.Advance("cultivate_started")
                            -- PushPlayerData 回来后会自动刷新面板
                        end,
                    })
                    btnRow:AddChild(UI.Button {
                        text = "取消",
                        fontSize = 16,
                        onClick = function()
                            cultivateSlider_ = nil
                            Client.SwitchPanel(currentPanel_)
                        end,
                    })
                    sliderPanel:AddChild(btnRow)
                    row:AddChild(sliderPanel)
                end

                -- 境界标签（只显示境界名，进度由进度条展示）
                local tier, tierName, tierProgress = Shared.GetProficiencyTier(sk.proficiency, def.max_proficiency)
                local tierColor = tier >= 3 and { 255, 200, 60, 255 } or { 160, 160, 160, 255 }
                row:AddChild(UI.Label {
                    text = string.format("境界：%s（第%d阶）", tierName, tier),
                    fontSize = 13,
                    color = tierColor,
                    marginTop = 2,
                })

                -- 进度条：显示当前阶段内进度
                local tierPct = math.floor(tierProgress * 100)

                local barRow = UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    alignItems = "center",
                    marginTop = 4,
                    gap = 6,
                }
                -- 进度条背景
                local barBg = UI.Panel {
                    flexGrow = 1, height = 10,
                    backgroundColor = TC.bgDeep,
                    borderRadius = 5,
                    overflow = "hidden",
                }
                -- 进度条填充（阶内进度）
                local barFill = UI.Panel {
                    width = math.max(1, tierPct) .. "%",
                    height = "100%",
                    backgroundColor = isCurrent and { 60, 180, 80, 255 } or { 80, 130, 80, 200 },
                    borderRadius = 5,
                }
                barBg:AddChild(barFill)
                barRow:AddChild(barBg)
                -- 百分比文字（阶内进度）
                local pctLabel = UI.Label {
                    text = tierPct .. "%",
                    fontSize = 14,
                    color = TC.success,
                    width = 36,
                }
                barRow:AddChild(pctLabel)
                row:AddChild(barRow)


                container:AddChild(row)
            end
        end
    end

    return container
end

-- ============================================================================
-- 角色属性面板
-- ============================================================================
local function BuildStatsPanel()
    local container = UI.Panel {
        width = "100%",
        padding = { 10, 8 }, gap = 6,
    }

    container:AddChild(UI.Label {
        text = "── 角色属性 ──",
        fontSize = 17, color = LOG_COLOR.title,
        marginBottom = 6, alignSelf = "center",
    })

    if not player_ then
        container:AddChild(UI.Label { text = "数据加载中...", fontSize = 16,
            color = TC.textMuted, alignSelf = "center" })
        return container
    end

    local p = player_

    -- 战力（红色大字）
    local stats = Shared.CalcStats(p)
    local power = Settings.CalcPower(stats)
    container:AddChild(UI.Label {
        text = string.format("⚔ 战力 %d", power),
        fontSize = 22, color = TC.danger,
        alignSelf = "center", marginBottom = 6,
    })

    -- 辅助：一行属性
    local function StatRow(label, value, color)
        local row = UI.Panel {
            width = "100%", height = 32, flexDirection = "row",
            alignItems = "center",
            backgroundColor = TC.bgPanel,
            paddingHorizontal = 10,
            borderBottomWidth = 1, borderColor = TC.borderLight,
        }
        row:AddChild(UI.Label { text = label, fontSize = 16,
            color = TC.textSecondary, width = 80 })
        row:AddChild(UI.Label { text = tostring(value), fontSize = 16,
            color = color or { 220, 220, 255, 255 }, flexGrow = 1 })
        return row
    end

    -- 基本信息块
    local function SectionTitle(t)
        return UI.Label { text = t, fontSize = 14,
            color = TC.textSecondary,
            marginTop = 8, marginBottom = 2, marginLeft = 4 }
    end

    -- 门派文字
    local sectText = GetSectDisplay(p.sect)

    -- 境界经验进度
    local realmExpMax = p.realm_exp_max or 100
    local realmExpPct = (p.realm_exp and realmExpMax > 0) and math.floor(p.realm_exp / realmExpMax * 100) or 0
    local realmName = p.realm_name or "练气一层"

    -- 装备加成汇总
    local eqAtk, eqDef, eqHp, eqAgi = 0, 0, 0, 0
    if p.equipment then
        for _, it in pairs(p.equipment) do
            if it and it.stats then
                eqAtk = eqAtk + (it.stats.atk or 0)
                eqDef = eqDef + (it.stats.def or 0)
                eqHp  = eqHp  + (it.stats.hp  or 0)
                eqAgi = eqAgi + (it.stats.agi or 0)
            end
        end
    end

    -- 功法加成汇总
    local skAtk, skDef, skAgi, skWis = 0, 0, 0, 0
    if p.skills then
        for _, sk in ipairs(p.skills) do
            local def = Shared.GetSkillDef(sk.id or sk.skill_id)
            if def and def.stat_bonus then
                skAtk = skAtk + (def.stat_bonus.atk or 0)
                skDef = skDef + (def.stat_bonus.def or 0)
                skAgi = skAgi + (def.stat_bonus.agi or 0)
                skWis = skWis + (def.stat_bonus.wis or 0)
            end
        end
    end

    container:AddChild(SectionTitle("基本信息"))
    container:AddChild(StatRow("名字",   p.name  or "未知",              LOG_COLOR.gold))
    -- 改名按钮
    local renameCost = Settings.SPIRIT_STONE.RENAME_COST
    local renameRow = UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        paddingHorizontal = 10, marginBottom = 2, gap = 4,
    }
    local renameField = UI.TextField {
        placeholder = "新名字(2-8字)", fontSize = 12, height = 26, flexGrow = 1,
    }
    renameRow:AddChild(renameField)
    renameRow:AddChild(UI.Button {
        text = "💎改名(" .. renameCost .. ")",
        fontSize = 11, height = 26, variant = "outline",
        onClick = function()
            local newName = renameField:GetText() or ""
            if newName == "" then
                AddLog("请输入新名字。", "warning")
                return
            end
            if (p.spirit_stone or 0) < renameCost then
                AddLog("灵石不足！改名需要 " .. renameCost .. " 灵石。", "warning")
                return
            end
            SendToServer(EV.REQ_RENAME, { NewName = newName })
            AddLog(">> 正在改名...", "system")
        end,
    })
    container:AddChild(renameRow)
    container:AddChild(StatRow("境界",   realmName, { 180, 220, 255, 255 }))
    container:AddChild(StatRow("修为",   string.format("%d / %d  (%d%%)", p.realm_exp or 0, realmExpMax, realmExpPct)))
    container:AddChild(StatRow("门派",   sectText, { 200, 180, 120, 255 }))

    -- 境界突破按钮（经验已满时显示）
    local expFull = (p.realm_exp or 0) >= realmExpMax and realmExpMax > 0
    local isMaxRealm = Settings.REALM.IsMaxRealm(p.realm or 1, p.realm_layer or 1)
    if expFull and not isMaxRealm then
        local pillInfo = Settings.REALM_PILLS[p.realm or 1]
        local pillName = pillInfo and pillInfo.name or "突破丹"
        local baseRate = Settings.REALM.SUCCESS_RATE[p.realm or 1] or 0.5
        local pityBonus = (p.breakthrough_fails or 0) * 0.10
        local successRate = math.min(1.0, baseRate + pityBonus)
        local rateText = pityBonus > 0
            and string.format("%d%%（含保底+%d%%）", math.floor(successRate * 100), math.floor(pityBonus * 100))
            or string.format("%d%%", math.floor(successRate * 100))
        local protectCost = Settings.SPIRIT_STONE.BREAKTHROUGH_PROTECT_COST
        local canAffordProtect = (p.spirit_stone or 0) >= protectCost
        local useProtect = { value = false }  -- 闭包引用

        local protectToggle = UI.Button {
            text = canAffordProtect
                and string.format("💎灵石保护(-%d)", protectCost)
                or string.format("💎保护(需%d灵石)", protectCost),
            fontSize = 12,
            variant = canAffordProtect and "outline" or "disabled",
            marginBottom = 4,
            onClick = function(self)
                if not canAffordProtect then
                    AddLog("灵石不足！突破保护需要 " .. protectCost .. " 灵石。", "warning")
                    return
                end
                useProtect.value = not useProtect.value
                if useProtect.value then
                    self:SetVariant("warning")
                    self:SetText("💎保护已开启(失败不掉层)")
                else
                    self:SetVariant("outline")
                    self:SetText(string.format("💎灵石保护(-%d)", protectCost))
                end
            end,
        }

        container:AddChild(UI.Panel {
            width = "100%",
            backgroundColor = TC.bgPanelLight,
            padding = 8,
            marginTop = 6,
            marginBottom = 4,
            borderRadius = 4,
            gap = 4,
            children = {
                UI.Label {
                    text = string.format("修为圆满，可尝试突破！（需%s，成功率%s）", pillName, rateText),
                    fontSize = 13,
                    color = TC.textAccent,
                },
                protectToggle,
                UI.Button {
                    text = "尝试突破",
                    width = "100%",
                    backgroundColor = TC.warning,
                    fontSize = 16,
                    onClick = function()
                        SendToServer(EV.REQ_BREAKTHROUGH, { Protected = useProtect.value })
                        local protMsg = useProtect.value and "（灵石保护中）" or ""
                        AddLog(">> 盘膝吞丹，冲击境界..." .. protMsg, "system")
                    end,
                },
            },
        })
    elseif isMaxRealm then
        container:AddChild(StatRow("", "已达最高境界：渡劫圆满", { 255, 215, 0, 255 }))
    end

    container:AddChild(SectionTitle("战斗属性（基础 + 功法加成 + 装备加成）"))
    local function CombinedStat(label, base, sk, eq)
        local total = math.floor((base or 0) + sk + eq)
        local detail = string.format("%d  (+%d +%d)", total, math.floor(sk), math.floor(eq))
        return StatRow(label, detail, { 200, 230, 255, 255 })
    end
    container:AddChild(CombinedStat("攻击力", p.atk_base, skAtk, eqAtk))
    container:AddChild(CombinedStat("防御力", p.def_base, skDef, eqDef))
    container:AddChild(CombinedStat("敏捷",   p.agi_base, skAgi, eqAgi))
    container:AddChild(CombinedStat("悟性",   p.wis_base, skWis, 0))

    container:AddChild(SectionTitle("气血 / 内力"))
    container:AddChild(StatRow("最大气血", string.format("%d  (+%d装备)", math.floor(p.max_hp or p.hp_base or 0), math.floor(eqHp))))
    container:AddChild(StatRow("当前气血", string.format("%d", math.floor(p.hp_base or 0)),
        (p.hp_base or 0) < math.floor((p.max_hp or p.hp_base or 1) * 0.3)
            and { 255, 100, 100, 255 } or { 100, 220, 120, 255 }))
    container:AddChild(StatRow("最大内力", string.format("%d", math.floor(p.max_mp or p.mp_base or 0))))
    container:AddChild(StatRow("剩余潜能", string.format("%d", math.floor(p.potential or 0)), LOG_COLOR.gold))

    -- 灵石免死开关
    container:AddChild(SectionTitle("灵石功能"))
    local reviveCost = Settings.SPIRIT_STONE.REVIVE_COST
    local reviveOn = p.revive_shield and true or false
    local reviveBtn = UI.Button {
        text = reviveOn
            and string.format("💎免死已开启(战败-%d灵石)", reviveCost)
            or string.format("💎免死关闭(开启后战败-%d灵石)", reviveCost),
        fontSize = 12,
        width = "100%",
        variant = reviveOn and "warning" or "outline",
        onClick = function(self)
            local newState = not reviveOn
            SendToServer(EV.REQ_TOGGLE_REVIVE, { Enabled = newState })
            if newState then
                self:SetVariant("warning")
                self:SetText(string.format("💎免死已开启(战败-%d灵石)", reviveCost))
            else
                self:SetVariant("outline")
                self:SetText(string.format("💎免死关闭(开启后战败-%d灵石)", reviveCost))
            end
            reviveOn = newState
        end,
    }
    container:AddChild(reviveBtn)
    container:AddChild(StatRow("灵石", string.format("%d", math.floor(p.spirit_stone or 0)), LOG_COLOR.gold))

    return container
end

-- 排行榜数据缓存（多类型）
local rankData_ = {}          -- rankData_[type] = decoded data
local rankCurrentTab_ = "power"  -- 当前选中的排行榜类型
local rankSectTab_ = "sword_sect" -- 门派榜当前选中的门派

-- ============================================================================
-- 聊天频道消息缓存（最新 100 条）
-- 结构：{ channel, sender, sect, text, time }
local CHAT_MAX_LOCAL = 100
local chatBuffers_ = { world = {}, sect = {}, system = {}, guild = {} }
-- 当前激活的聊天频道（"世界"/"门派"/"系统"/"私信"）
local chatActiveChannel_ = "世界"
-- 私信状态 { target = "", history = { [name] = { {sender, text, time}, ... } } }
local pmState_ = { target = "", history = {} }
-- 好友列表缓存 { {uid, name, online}, ... }
local friendList_ = {}
-- 活动数据缓存 { signed_today, sign_streak, total_signs, double_exp_until }
local activityData_ = {}
-- 聊天面板 UI 引用（合并节省 local 槽位）
local chatUI_ = { scrollView = nil, msgContainer = nil, exclusive = false }

-- ============================================================================
-- 聊天面板
-- ============================================================================

-- 频道 tab 名 → channel key 映射
local CHAT_CHANNEL_KEY = { ["世界"] = "world", ["门派"] = "sect", ["帮会"] = "guild", ["帮会频道"] = "guild", ["系统"] = "system" }

-- 向本地缓冲区追加一条消息，超出上限时丢弃最旧的
local function AppendLocalChatMsg(msg)
    local ch = msg.channel
    -- 门派消息统一映射到 sect 缓冲
    if ch and ch:sub(1, 5) == "sect_" then ch = "sect" end
    local buf = chatBuffers_[ch]
    if not buf then return end
    buf[#buf + 1] = msg
    if #buf > CHAT_MAX_LOCAL then
        table.remove(buf, 1)
    end
end

-- 把 os.time() 转为 HH:MM 格式
local function FormatChatTime(t)
    if not t or t == 0 then return "" end
    -- 服务器时间为 UTC，转换为 UTC+8（中国时区）
    local chinaTime = t + 8 * 3600
    local h = math.floor(chinaTime / 3600) % 24
    local m = math.floor(chinaTime / 60) % 60
    return string.format("%02d:%02d", h, m)
end

-- ============================================================================
-- 富文本标签解析（聊天消息中 [item:xx] [equip:xx] [battle:xx] 渲染）
-- ============================================================================
-- 标签格式：
--   [item:名称:品质]         → 带品质颜色的物品名
--   [equip:名称:品质:属性]   → 带品质颜色的装备名+属性
--   [battle:结果:描述]       → 战斗结果（胜利绿/失败红）
-- 解析后返回一组 segments: { {text=, color=}, ... }

local function ParseRichText(rawText)
    if not rawText or rawText == "" then return { { text = rawText or "", color = nil } } end
    -- 快速判断：无方括号直接返回
    if not rawText:find("%[") then return { { text = rawText, color = nil } } end

    local segments = {}
    local pos = 1
    local len = #rawText

    while pos <= len do
        -- 查找下一个 [ 标签开始
        local tagStart = rawText:find("%[", pos)
        if not tagStart then
            -- 剩余部分作为普通文本
            if pos <= len then
                segments[#segments + 1] = { text = rawText:sub(pos), color = nil }
            end
            break
        end

        -- 标签前的普通文本
        if tagStart > pos then
            segments[#segments + 1] = { text = rawText:sub(pos, tagStart - 1), color = nil }
        end

        -- 查找配对的 ]
        local tagEnd = rawText:find("%]", tagStart + 1)
        if not tagEnd then
            -- 无配对，剩余作为普通文本
            segments[#segments + 1] = { text = rawText:sub(tagStart), color = nil }
            break
        end

        local tagContent = rawText:sub(tagStart + 1, tagEnd - 1)
        local parts = {}
        for part in tagContent:gmatch("[^:]+") do
            parts[#parts + 1] = part
        end

        local tagType = parts[1]
        local parsed = false

        if tagType == "item" and parts[2] then
            -- [item:名称:品质]
            local name = parts[2]
            local quality = parts[3] or "common"
            local color = QualityColor(quality)
            segments[#segments + 1] = { text = "[" .. name .. "]", color = color }
            parsed = true
        elseif tagType == "equip" and parts[2] then
            -- [equip:名称:品质:属性]
            local name = parts[2]
            local quality = parts[3] or "common"
            local stats = parts[4] or ""
            local color = QualityColor(quality)
            local display = "[" .. name .. "]"
            if stats ~= "" then display = display .. " " .. stats end
            segments[#segments + 1] = { text = display, color = color }
            parsed = true
        elseif tagType == "battle" and parts[2] then
            -- [battle:结果:描述]
            local result = parts[2]
            local desc = parts[3] or ""
            local isWin = (result == "胜利" or result == "win")
            local color = isWin and { 80, 230, 120, 255 } or { 255, 100, 80, 255 }
            local display = isWin and "【胜】" or "【败】"
            if desc ~= "" then display = display .. desc end
            segments[#segments + 1] = { text = display, color = color }
            parsed = true
        end

        if not parsed then
            -- 未识别标签，原样显示
            segments[#segments + 1] = { text = rawText:sub(tagStart, tagEnd), color = nil }
        end

        pos = tagEnd + 1
    end

    return segments
end

-- 将富文本 segments 渲染为多个 Label 添加到 row
local function RenderRichTextToRow(row, segments, defaultColor)
    for _, seg in ipairs(segments) do
        row:AddChild(UI.Label {
            text = seg.text,
            fontSize = 14,
            color = seg.color or defaultColor or TC.textPrimary,
        })
    end
end

-- 刷新聊天消息区（如果当前面板打开的话）
local function RefreshChatMessages()
    if not chatUI_.msgContainer then return end
    chatUI_.msgContainer:ClearChildren()

    local key = CHAT_CHANNEL_KEY[chatActiveChannel_] or "world"
    local buf = chatBuffers_[key] or {}

    if #buf == 0 then
        chatUI_.msgContainer:AddChild(UI.Label {
            text = "暂无消息", fontSize = 14,
            color = TC.textMuted,
            alignSelf = "center", marginTop = 16,
        })
        return
    end

    local senderColors = {
        system = { 255, 200, 80, 255 },
        default = { 180, 200, 255, 255 },
        me = { 120, 255, 160, 255 },
    }

    for _, msg in ipairs(buf) do
        local isMe = (player_ and msg.sender == player_.name)
        local isSystem = (msg.channel == "system")
        local senderColor = isSystem and senderColors.system
                         or isMe and senderColors.me
                         or senderColors.default
        local timeStr = FormatChatTime(msg.time)

        local row = UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            paddingHorizontal = 6, paddingVertical = 2,
            marginBottom = 1,
            backgroundColor = isMe and { 20, 40, 20, 120 } or { 0, 0, 0, 0 },
        }
        -- 时间
        if timeStr ~= "" then
            row:AddChild(UI.Label {
                text = timeStr .. " ",
                fontSize = 12, color = TC.textMuted,
            })
        end
        -- 发送者名
        if not isSystem then
            row:AddChild(UI.Label {
                text = "[" .. (msg.sender or "?") .. "] ",
                fontSize = 14, color = senderColor,
            })
        end
        -- 正文（支持富文本标签）
        local textColor = isSystem and { 255, 220, 120, 240 } or { 220, 220, 230, 255 }
        local segments = ParseRichText(msg.text or "")
        if #segments == 1 and not segments[1].color then
            -- 纯文本快速路径
            row:AddChild(UI.Label {
                text = segments[1].text,
                fontSize = 14, color = textColor, flexShrink = 1,
            })
        else
            RenderRichTextToRow(row, segments, textColor)
        end
        chatUI_.msgContainer:AddChild(row)
    end

    -- 滚动到底部
    if chatUI_.scrollView then
        chatUI_.scrollView:ScrollToBottom()
    end
end

-- ── 门派面板 ─────────────────────────────────────────────────
-- 未入门派：展示四个门派招募卡，点击互动前往
local function BuildSectRecruitView()
    local scroll = UI.ScrollView {
        width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0,
    }
    local content = UI.Panel {
        width = "100%", flexDirection = "column", flexShrink = 0,
        paddingVertical = 8, paddingHorizontal = 6,
        gap = 8,
    }

    -- 试炼系统说明
    content:AddChild(UI.Label {
        text = "各门派均设有入门试炼，前往本部找执事即可领取。完成试炼可获得修炼资源，通过后方可正式拜入。",
        fontSize = 13, color = TC.textSecondary,
        marginBottom = 4, marginLeft = 4,
    })

    local p = player_
    local trials = (p and p.sect_trials) or {}
    local sectOrder = { "sword_sect", "iron_sect", "medicine_sect", "shadow_sect", "qidan_sect" }

    for _, sectId in ipairs(sectOrder) do
        local info = Settings.SECT_INFO and Settings.SECT_INFO[sectId]
        local quest = Settings.SECT_TRIAL and Settings.SECT_TRIAL.QUESTS and Settings.SECT_TRIAL.QUESTS[sectId]
        if info and quest then
            local c = info.color or { 160, 160, 200 }
            local cardBg   = { math.floor(c[1]*0.18), math.floor(c[2]*0.18), math.floor(c[3]*0.18), 240 }
            local borderC  = { c[1], c[2], c[3], 160 }
            local titleC   = { c[1], c[2], c[3], 255 }

            -- 试炼状态
            local trial = trials[sectId]
            local statusText, statusColor
            if trial and trial.status == "completed" then
                statusText = "试炼通过"
                statusColor = { 100, 220, 100, 255 }
            elseif trial and trial.status == "accepted" then
                local progress = trial.progress or 0
                local total = quest.count or 1
                statusText = string.format("进行中 %d/%d", progress, total)
                statusColor = { 255, 200, 80, 255 }
            else
                statusText = "未开始"
                statusColor = { 140, 140, 160, 180 }
            end

            local card = UI.Panel {
                width = "100%", flexDirection = "column",
                backgroundColor = cardBg,
                borderWidth = 1, borderColor = borderC,
                borderRadius = 6, paddingVertical = 10, paddingHorizontal = 12,
            }

            -- 标题行：门派名 + 试炼状态
            local hdr = UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                marginBottom = 6,
            }
            hdr:AddChild(UI.Label {
                text = info.display,
                fontSize = 18, fontWeight = "bold", color = titleC, flexGrow = 1,
            })
            hdr:AddChild(UI.Panel {
                paddingHorizontal = 8, paddingVertical = 2,
                backgroundColor = { statusColor[1], statusColor[2], statusColor[3], 40 },
                borderRadius = 4,
                children = {
                    UI.Label { text = statusText, fontSize = 12, color = statusColor },
                }
            })
            card:AddChild(hdr)

            -- 简介
            card:AddChild(UI.Label {
                text = info.intro or "",
                fontSize = 13, color = TC.textSecondary,
                marginBottom = 6,
            })

            -- 两个分支标签
            local branchRow = UI.Panel {
                flexDirection = "row", gap = 8, marginBottom = 8,
            }
            for _, bName in pairs(info.branches or {}) do
                branchRow:AddChild(UI.Panel {
                    paddingHorizontal = 8, paddingVertical = 2,
                    backgroundColor = { c[1], c[2], c[3], 60 },
                    borderRadius = 4,
                    borderWidth = 1, borderColor = borderC,
                    children = {
                        UI.Label { text = bName, fontSize = 12, color = titleC },
                    }
                })
            end
            card:AddChild(branchRow)

            -- 试炼信息
            local trialDesc = quest.name .. "：" .. (quest.desc or "")
            card:AddChild(UI.Label {
                text = trialDesc,
                fontSize = 12, color = TC.textSecondary,
                marginBottom = 4,
            })

            -- 执事位置提示
            card:AddChild(UI.Label {
                text = "试炼执事：" .. info.display .. "本部",
                fontSize = 12, color = TC.success,
            })

            content:AddChild(card)
        end
    end

    scroll:AddChild(content)
    ui_.bottomSection:AddChild(scroll)
end

-- 已入门派：展示本门信息 + 技能树进度
local function BuildSectMemberView(p)
    local sectId = p.sect or ""
    local info   = Settings.SECT_INFO and Settings.SECT_INFO[sectId]
    local c      = (info and info.color) or { 160, 160, 200 }
    local titleC = { c[1], c[2], c[3], 255 }
    local dimC   = { c[1], c[2], c[3], 180 }

    local scroll = UI.ScrollView {
        width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0,
    }
    local content = UI.Panel {
        width = "100%", flexDirection = "column", flexShrink = 0,
        paddingVertical = 8, paddingHorizontal = 8, gap = 10,
    }

    -- 门派徽标区
    local badge = UI.Panel {
        width = "100%", paddingVertical = 14, paddingHorizontal = 12,
        backgroundColor = { math.floor(c[1]*0.2), math.floor(c[2]*0.2), math.floor(c[3]*0.2), 250 },
        borderWidth = 1, borderColor = { c[1], c[2], c[3], 120 },
        borderRadius = 8, flexDirection = "row", alignItems = "center",
    }
    badge:AddChild(UI.Label {
        text = info and info.display or sectId,
        fontSize = 22, fontWeight = "bold", color = titleC, flexGrow = 1,
    })
    local branchName = ""
    if p.branch and info and info.branches then
        branchName = info.branches[p.branch] or p.branch
    end
    if branchName ~= "" then
        badge:AddChild(UI.Label {
            text = branchName,
            fontSize = 14, color = dimC, marginRight = 8,
        })
    end
    -- 退出门派按钮
    badge:AddChild(UI.Button {
        text = "退出门派",
        fontSize = 11, height = 26, paddingHorizontal = 8,
        backgroundColor = { 120, 40, 40, 200 },
        color = { 255, 180, 180, 255 },
        borderRadius = 4,
        onClick = function()
            -- 显示二次确认（用一个覆盖面板）
            local overlay = UI.Panel {
                position = "absolute", width = "100%", height = "100%",
                backgroundColor = { 0, 0, 0, 180 },
                justifyContent = "center", alignItems = "center",
            }
            local dialog = UI.Panel {
                width = 260, paddingVertical = 16, paddingHorizontal = 16,
                backgroundColor = { 30, 25, 40, 250 },
                borderWidth = 1, borderColor = { 200, 80, 80, 180 },
                borderRadius = 10, alignItems = "center", gap = 12,
            }
            dialog:AddChild(UI.Label {
                text = "确认退出门派？",
                fontSize = 16, fontWeight = "bold", color = { 255, 200, 200, 255 },
            })
            dialog:AddChild(UI.Label {
                text = "退出后将清除门派技能熟练度，\n需重新通过试炼方可再次加入。",
                fontSize = 12, color = { 200, 180, 180, 200 }, textAlign = "center",
            })
            local btnRow = UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "center", gap = 16,
            }
            btnRow:AddChild(UI.Button {
                text = "取消", fontSize = 13, height = 32, paddingHorizontal = 20,
                backgroundColor = { 60, 60, 70, 220 },
                onClick = function()
                    overlay:Dispose()
                end,
            })
            btnRow:AddChild(UI.Button {
                text = "确认退出", fontSize = 13, height = 32, paddingHorizontal = 16,
                backgroundColor = { 160, 40, 40, 240 },
                color = { 255, 220, 220, 255 },
                onClick = function()
                    overlay:Dispose()
                    SendToServer(EV.REQ_NPC_OPTION, {
                        NpcId  = "",
                        Action = "leave_sect",
                        Data   = sectId,
                    })
                    AddLog(">> 你决意离去，不再回头。", "system")
                end,
            })
            dialog:AddChild(btnRow)
            overlay:AddChild(dialog)
            UI.SetOverlay(overlay)
        end,
    })
    content:AddChild(badge)

    -- 门派简介
    if info and info.intro then
        content:AddChild(UI.Label {
            text = info.intro,
            fontSize = 13, color = TC.textSecondary,
        })
    end

    -- 技能树进度
    content:AddChild(UI.Label {
        text = "本门武学",
        fontSize = 15, fontWeight = "bold", color = titleC,
        marginTop = 4, marginBottom = 2,
    })

    -- 收集本门技能
    local mySect   = sectId
    local mySkills = p.skills or {}
    -- 构建已学技能 id → proficiency 映射
    local learnedMap = {}
    for _, sk in ipairs(mySkills) do
        learnedMap[sk.id] = sk.proficiency or 0
    end

    -- 遍历 Settings.SKILLS 找属于本门的技能
    local sectSkills = {}
    for _, sk in ipairs(Settings.SKILLS or {}) do
        -- 通过检查 id 前缀判断是否属于本门（iron_/herb_/shadow_/...）
        local prefixMap = {
            sword_sect    = { "basic_sword", "swift_", "heavy_", "wind_", "lone_", "shadowless_sword", "dragon_", "sky_", "broken_" },
            iron_sect     = { "iron_", "shield_", "bastion_", "stone_", "diamond_", "undying_" },
            medicine_sect = { "herb_", "spring_", "marrow_", "golden_needle", "life_death", "venom_", "viper_", "ten_thousand", "soul_devouring" },
            shadow_sect   = { "shadow_", "ghost_", "phantom_", "night_flash", "heaven_shadow", "hidden_dart", "needle_rain", "ten_dir_darts", "shadowless_strike" },
        }
        local belongs = false
        for _, prefix in ipairs(prefixMap[mySect] or {}) do
            if sk.id:sub(1, #prefix) == prefix or sk.id == prefix then
                belongs = true; break
            end
        end
        if belongs then
            sectSkills[#sectSkills + 1] = sk
        end
    end

    -- 按 branch 分组展示
    local branchOrder = {}
    local branchSkills = {}
    for _, sk in ipairs(sectSkills) do
        local br = sk.branch or "common"
        if not branchSkills[br] then
            branchSkills[br] = {}
            branchOrder[#branchOrder + 1] = br
        end
        branchSkills[br][#branchSkills[br] + 1] = sk
    end

    -- 排序：common 优先
    table.sort(branchOrder, function(a, b)
        if a == "common" then return true end
        if b == "common" then return false end
        return a < b
    end)

    for _, br in ipairs(branchOrder) do
        local brDisplay = "通用"
        if info and info.branches and info.branches[br] then
            brDisplay = info.branches[br]
        end
        -- 分支标题
        content:AddChild(UI.Label {
            text = "▸ " .. brDisplay,
            fontSize = 14, color = dimC,
            marginTop = 4, marginBottom = 2, marginLeft = 2,
        })

        for _, sk in ipairs(branchSkills[br]) do
            local prof     = learnedMap[sk.id]
            local learned  = prof ~= nil
            local maxProf  = sk.max_proficiency or 100
            local pct      = learned and math.min(1, prof / maxProf) or 0
            local barW     = math.floor(pct * 120)

            local rowBg    = learned and { 20, 30, 20, 200 } or { 22, 22, 32, 160 }
            local nameC    = learned and { 220, 230, 220, 255 } or { 100, 100, 110, 180 }
            local barFillC = { math.floor(c[1] * 0.7), math.floor(c[2] * 0.7), math.floor(c[3] * 0.7), 200 }

            local row = UI.Panel {
                width = "100%", height = 40, flexDirection = "row", alignItems = "center",
                backgroundColor = rowBg, borderRadius = 4,
                paddingHorizontal = 10, gap = 6,
                borderBottomWidth = 1, borderColor = TC.borderLight,
            }
            -- 技能名
            row:AddChild(UI.Panel {
                flexGrow = 1, flexDirection = "column", justifyContent = "center",
                children = {
                    UI.Label { text = sk.name or sk.id, fontSize = 14, color = nameC },
                    UI.Label { text = sk.grade .. "阶  " .. (sk.desc and sk.desc:sub(1, 18) .. "…" or ""), fontSize = 10, color = TC.textMuted },
                }
            })
            -- 熟练度进度条
            local barBg = UI.Panel {
                width = 120, height = 8,
                backgroundColor = TC.bgOverlay, borderRadius = 4,
            }
            if barW > 0 then
                barBg:AddChild(UI.Panel {
                    width = barW, height = 8,
                    backgroundColor = barFillC, borderRadius = 4,
                })
            end
            row:AddChild(barBg)
            -- 数值
            row:AddChild(UI.Label {
                text = learned and (prof .. "/" .. maxProf) or "未修",
                width = 55, fontSize = 11,
                color = learned and LOG_COLOR.gold or { 80, 80, 90, 180 },
                textAlign = "right",
            })
            content:AddChild(row)
        end
    end

    scroll:AddChild(content)
    ui_.bottomSection:AddChild(scroll)
end

-- 称号面板已提取到 network/TitlePanel.lua（避免 local-limit）

-- 门派面板入口：根据玩家是否入门派路由
local function BuildSectPanel()
    local p = player_
    if not p then return end

    -- 标题行
    local titleRow = UI.Panel {
        width = "100%", height = 32, flexDirection = "row", alignItems = "center",
        paddingHorizontal = 10, flexShrink = 0,
        backgroundColor = TC.bgDeep,
        borderBottomWidth = 1, borderColor = TC.borderLight,
    }
    local hasSect = p.sect and p.sect ~= ""
    local titleText = hasSect and ("门派  ·  " .. GetSectDisplay(p.sect)) or "门派  ·  入门试炼"
    titleRow:AddChild(UI.Label {
        text = titleText, fontSize = 16,
        color = hasSect and GetSectColor(p.sect) or LOG_COLOR.gold,
        flexGrow = 1,
    })
    ui_.bottomSection:AddChild(titleRow)

    if hasSect then
        BuildSectMemberView(p)
    else
        BuildSectRecruitView()
    end
end

local function BuildChatPanel(channelName)
    chatActiveChannel_ = channelName or chatActiveChannel_

    -- 与 BuildNavSubPanel 保持一致的 areaH 计算：
    -- 顶栏36 + tab栏44 + 描述80 + 底部tab44 + 面板标题30 + 按钮行(32+5*2+6*2=54)
    local dpr  = graphics:GetDPR()
    local logH = graphics:GetHeight() / dpr
    local areaH = math.max(180, logH - 36 - 44 - 80 - 44 - 30 - 54)
    -- 消息区 = areaH 减去 输入行(44) 和 容器内边距(8)
    local msgH = math.max(80, areaH - 44 - 8)

    -- 外层容器高度固定与 areaH 一致，防止内部 ScrollView 被外层 ScrollView 二次滚动
    local container = UI.Panel {
        width = "100%", height = areaH,
        flexShrink = 0,
        flexDirection = "column",
        paddingHorizontal = 4, paddingVertical = 4,
        gap = 4,
    }

    -- 消息滚动区
    local scrollView = UI.ScrollView {
        width = "100%", height = msgH,
        flexShrink = 0, scrollY = true,
        backgroundColor = TC.bgDeep,
    }
    local msgContainer = UI.Panel {
        width = "100%", gap = 1,
        padding = { 4, 4 },
    }
    scrollView:AddChild(msgContainer)
    container:AddChild(scrollView)

    -- 更新模块级引用，供事件回调使用
    chatUI_.scrollView   = scrollView
    chatUI_.msgContainer = msgContainer

    -- 渲染当前频道历史
    RefreshChatMessages()

    -- 输入行（系统频道只读，世界/门派可发言）
    local isReadOnly = (chatActiveChannel_ == "系统")
    local inputRow = UI.Panel {
        width = "100%", height = 44,
        flexDirection = "row", gap = 6,
        alignItems = "center",
        flexShrink = 0,
        paddingHorizontal = 4,
        borderTopWidth = 1, borderColor = TC.borderLight,
    }

    if isReadOnly then
        inputRow:AddChild(UI.Label {
            text = "系统频道为只读",
            flexGrow = 1, fontSize = 14,
            color = TC.textSecondary,
            alignSelf = "center",
        })
    else
        local chKey = CHAT_CHANNEL_KEY[chatActiveChannel_] or "world"
        ---@type Widget
        local tf = UI.TextField {
            flexGrow = 1, height = 34, fontSize = 15,
            placeholder = "输入消息…",
            backgroundColor = TC.bgPanel,
            color = TC.textPrimary,
            borderWidth = 1, borderColor = TC.border,
        }
        local sendBtn = UI.Button {
            text = "发送", width = 58, height = 34, fontSize = 15,
            backgroundColor = TC.bgPanel,
            onClick = function()
                local text = tf:GetValue()
                text = text:match("^%s*(.-)%s*$")
                if text == "" then return end
                SendToServer(EV.REQ_CHAT_SEND, { Channel = chKey, Text = text })
                tf:Clear()
            end,
        }
        inputRow:AddChild(tf)
        inputRow:AddChild(sendBtn)
    end
    container:AddChild(inputRow)

    return container
end

-- ============================================================================
-- 聊天独占模式（全屏聊天面板）
-- ============================================================================

-- 构建全屏聊天面板（独占 mainArea）
local function BuildChatExclusiveMode(defaultChannel)
    chatUI_.exclusive = true
    chatActiveChannel_ = defaultChannel or chatActiveChannel_ or "世界"

    if not ui_.mainArea then return end
    ui_.mainArea:ClearChildren()
    ui_.bottomSection = nil  -- 不再使用子面板区域

    -- 隐藏场景描述和左侧玩家列，释放空间
    if ui_.descBar then ui_.descBar:SetVisible(false) end
    if ui_.playerListCol then ui_.playerListCol:Hide() end

    -- 隐藏场景描述和玩家列后，mainArea 使用 flexGrow=1 自动占满全部剩余高度

    -- 外层容器
    local chatRoot = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        minHeight = 0,
        flexDirection = "column",
        overflow = "hidden",
    }

    -- ── 频道 Tab 栏 ──
    local tabRow = UI.Panel {
        width = "100%", height = 36, flexShrink = 0,
        flexDirection = "row", alignItems = "center",
        justifyContent = "center",
        gap = 4, paddingHorizontal = 6,
        backgroundColor = TC.bgDeep,
        borderBottomWidth = 1, borderColor = TC.borderLight,
    }
    local CHAT_TABS = { "世界", "门派", "帮会频道", "私信", "系统" }
    local tabBtns = {}

    local function SwitchChatTab(tabName)
        chatActiveChannel_ = tabName
        currentSubTab_[PANEL.CHAT] = tabName
        -- 更新 Tab 高亮
        for name, btn in pairs(tabBtns) do
            if name == tabName then
                btn.backgroundColor = { 60, 45, 30, 240 }
                btn.color = { 235, 210, 150, 255 }
                btn.borderColor = { 180, 140, 70, 200 }
            else
                btn.backgroundColor = { 25, 23, 30, 220 }
                btn.color = { 170, 160, 145, 255 }
                btn.borderColor = { 60, 55, 45, 150 }
            end
        end
        -- 重建内容区
        BuildChatExclusiveMode(tabName)
    end

    for _, tab in ipairs(CHAT_TABS) do
        local isActive = (tab == chatActiveChannel_)
        local btn = UI.Button {
            text = tab, height = 28, paddingHorizontal = 10, fontSize = 13,
            fontWeight = "bold",
            borderRadius = 14,
            backgroundColor = isActive and { 60, 45, 30, 240 } or { 25, 23, 30, 220 },
            color = isActive and { 235, 210, 150, 255 } or { 170, 160, 145, 255 },
            borderWidth = 1,
            borderColor = isActive and { 180, 140, 70, 200 } or { 60, 55, 45, 150 },
            onClick = function() SwitchChatTab(tab) end,
        }
        tabBtns[tab] = btn
        tabRow:AddChild(btn)
    end
    chatRoot:AddChild(tabRow)

    -- ── 消息内容区（区分私信和普通频道）──
    if chatActiveChannel_ == "私信" then
        -- 私信面板：目标选择行 + 消息 + 输入
        -- 顶部：选择对象行
        local topRow = UI.Panel {
            width = "100%", height = 34, flexShrink = 0,
            flexDirection = "row", alignItems = "center", gap = 6,
            paddingHorizontal = 8,
            borderBottomWidth = 1, borderColor = TC.borderLight,
        }
        topRow:AddChild(UI.Label {
            text = "私信对象：", fontSize = 14, color = TC.textSecondary,
        })
        ---@type Widget
        local targetField = UI.TextField {
            flexGrow = 1, height = 28, fontSize = 14,
            placeholder = "输入玩家名称…",
            backgroundColor = TC.bgPanel,
            color = TC.textPrimary,
            borderWidth = 1, borderColor = TC.border,
        }
        if pmState_.target ~= "" then targetField:SetValue(pmState_.target) end
        topRow:AddChild(targetField)
        chatRoot:AddChild(topRow)

        -- 消息滚动区（占满剩余空间）
        local scrollView = UI.ScrollView {
            width = "100%",
            flexGrow = 1, flexShrink = 1, minHeight = 0,
            scrollY = true,
            backgroundColor = TC.bgDeep,
        }
        local msgContainer = UI.Panel {
            width = "100%", gap = 1, padding = { 6, 6 },
        }
        scrollView:AddChild(msgContainer)
        chatRoot:AddChild(scrollView)

        chatUI_.scrollView   = scrollView
        chatUI_.msgContainer = msgContainer

        -- 渲染私信历史
        msgContainer:ClearChildren()
        local history = pmState_.history[pmState_.target]
        if not history or #history == 0 then
            msgContainer:AddChild(UI.Label {
                text = pmState_.target == "" and "请输入玩家名称开始私聊"
                    or "暂无与【" .. pmState_.target .. "】的聊天记录",
                fontSize = 14, color = TC.textMuted,
                alignSelf = "center", marginTop = 16,
            })
        else
            for _, msg in ipairs(history) do
                local isMine = (msg.sender == (player_ and player_.name or ""))
                local prefix = isMine and "我" or msg.sender
                local timeStr = FormatChatTime(msg.time)
                local row = UI.Panel {
                    width = "100%", flexDirection = "row", flexWrap = "wrap",
                    paddingHorizontal = 6, paddingVertical = 2, marginBottom = 1,
                    backgroundColor = isMine and { 20, 40, 20, 120 } or { 0, 0, 0, 0 },
                }
                if timeStr ~= "" then
                    row:AddChild(UI.Label { text = timeStr .. " ", fontSize = 12, color = TC.textMuted })
                end
                row:AddChild(UI.Label {
                    text = prefix .. "：" .. msg.text,
                    fontSize = 14,
                    color = isMine and { 140, 200, 255, 255 } or { 200, 220, 180, 255 },
                })
                msgContainer:AddChild(row)
            end
        end

        -- 输入行
        local inputRow = UI.Panel {
            width = "100%", height = 44, flexShrink = 0,
            flexDirection = "row", gap = 6,
            alignItems = "center", paddingHorizontal = 8,
            borderTopWidth = 1, borderColor = TC.borderLight,
        }
        ---@type Widget
        local tf = UI.TextField {
            flexGrow = 1, height = 34, fontSize = 15,
            placeholder = "输入消息…",
            backgroundColor = TC.bgPanel,
            color = TC.textPrimary,
            borderWidth = 1, borderColor = TC.border,
        }
        inputRow:AddChild(tf)
        inputRow:AddChild(UI.Button {
            text = "发送", width = 58, height = 34, fontSize = 15,
            backgroundColor = TC.bgPanel,
            color = TC.textAccent,
            onClick = function()
                local target = targetField:GetValue()
                target = target:match("^%s*(.-)%s*$")
                if target == "" then
                    AddLog("请先输入私信对象的名称", "warn"); return
                end
                pmState_.target = target
                local text = tf:GetValue()
                text = text:match("^%s*(.-)%s*$")
                if text == "" then return end
                SendToServer(EV.REQ_CHAT_SEND, { Channel = "private", Target = target, Text = text })
                if not pmState_.history[target] then pmState_.history[target] = {} end
                local h = pmState_.history[target]
                h[#h + 1] = { sender = (player_ and player_.name or "我"), text = text, time = os.time() }
                tf:Clear()
                BuildChatExclusiveMode("私信")
            end,
        })
        chatRoot:AddChild(inputRow)
    else
        -- 普通频道：消息 + 输入
        local isReadOnly = (chatActiveChannel_ == "系统")

        -- 消息滚动区（flexGrow=1 占满剩余空间）
        local scrollView = UI.ScrollView {
            width = "100%",
            flexGrow = 1, flexShrink = 1, minHeight = 0,
            scrollY = true,
            backgroundColor = TC.bgDeep,
        }
        local msgContainer = UI.Panel {
            width = "100%", gap = 1, padding = { 6, 6 },
        }
        scrollView:AddChild(msgContainer)
        chatRoot:AddChild(scrollView)

        chatUI_.scrollView   = scrollView
        chatUI_.msgContainer = msgContainer

        -- 渲染消息
        RefreshChatMessages()

        -- 输入行
        local inputRow = UI.Panel {
            width = "100%", height = 44, flexShrink = 0,
            flexDirection = "row", gap = 6,
            alignItems = "center", paddingHorizontal = 8,
            borderTopWidth = 1, borderColor = TC.borderLight,
        }

        -- 分享选项面板（默认隐藏，点+号展开）
        local sharePanel = UI.Panel {
            width = "100%", flexShrink = 0,
            flexDirection = "row", flexWrap = "wrap",
            gap = 6, paddingHorizontal = 8, paddingVertical = 6,
            backgroundColor = { 30, 28, 35, 240 },
            borderTopWidth = 1, borderColor = TC.borderLight,
        }
        sharePanel:SetVisible(false)

        -- 分享按钮生成器
        local function MakeShareBtn(label, icon, onClickFn)
            return UI.Button {
                text = icon .. " " .. label, height = 30, paddingHorizontal = 10, fontSize = 13,
                borderRadius = 15,
                backgroundColor = TC.bgPanel,
                color = TC.textAccent,
                borderWidth = 1, borderColor = TC.borderLight,
                onClick = onClickFn,
            }
        end

        sharePanel:AddChild(MakeShareBtn("物品", "+", function()
            -- 打开背包选择物品分享
            sharePanel:SetVisible(false)
            Client.SwitchPanel(PANEL.INVENTORY)
            AddLog(">> 请在背包中选择物品点击[分享]按钮", "info")
        end))
        sharePanel:AddChild(MakeShareBtn("装备", "+", function()
            sharePanel:SetVisible(false)
            Client.SwitchPanel(PANEL.INVENTORY)
            AddLog(">> 请在背包中选择装备点击[分享]按钮", "info")
        end))
        sharePanel:AddChild(MakeShareBtn("战绩", "+", function()
            sharePanel:SetVisible(false)
            -- 分享最近一次战斗结果
            if battleAnim_.lastResult then
                local chKey = CHAT_CHANNEL_KEY[chatActiveChannel_] or "world"
                local resultTag = battleAnim_.lastResult.won and "胜利" or "失败"
                local desc = battleAnim_.lastResult.desc or ""
                local text = "[battle:" .. resultTag .. ":" .. desc .. "]"
                SendToServer(EV.REQ_CHAT_SEND, { Channel = chKey, Text = text })
            else
                AddLog("暂无战斗记录可分享", "warn")
            end
        end))
        chatRoot:AddChild(sharePanel)

        if isReadOnly then
            inputRow:AddChild(UI.Label {
                text = "系统频道为只读",
                flexGrow = 1, fontSize = 14,
                color = TC.textSecondary, alignSelf = "center",
            })
        else
            local chKey = CHAT_CHANNEL_KEY[chatActiveChannel_] or "world"
            -- "+" 按钮
            inputRow:AddChild(UI.Button {
                text = "+", width = 34, height = 34, fontSize = 18,
                borderRadius = 17,
                backgroundColor = TC.bgPanelLight,
                color = TC.textAccent,
                borderWidth = 1, borderColor = TC.borderLight,
                onClick = function()
                    sharePanel:SetVisible(not sharePanel:IsVisible())
                end,
            })
            ---@type Widget
            local tf = UI.TextField {
                flexGrow = 1, height = 34, fontSize = 15,
                placeholder = "输入消息…",
                backgroundColor = TC.bgPanel,
                color = TC.textPrimary,
                borderWidth = 1, borderColor = TC.border,
            }
            inputRow:AddChild(tf)
            inputRow:AddChild(UI.Button {
                text = "发送", width = 58, height = 34, fontSize = 15,
                backgroundColor = TC.bgPanel,
                color = TC.textAccent,
                onClick = function()
                    local text = tf:GetValue()
                    text = text:match("^%s*(.-)%s*$")
                    if text == "" then return end
                    SendToServer(EV.REQ_CHAT_SEND, { Channel = chKey, Text = text })
                    tf:Clear()
                end,
            })
        end
        chatRoot:AddChild(inputRow)
    end

    ui_.mainArea:AddChild(chatRoot)
end

-- 退出聊天独占模式（恢复隐藏元素）
local function ExitChatExclusiveMode()
    if not chatUI_.exclusive then return end
    chatUI_.exclusive = false
    -- 恢复被隐藏的元素
    if ui_.descBar then ui_.descBar:SetVisible(true) end
    if ui_.playerListCol then ui_.playerListCol:Show() end
end

-- 排名面板（多类型排行榜）
-- ============================================================================

-- 排行榜 Tab 定义
local RANK_TABS = {
    { id = "power",  label = "战力" },
    { id = "sect",   label = "门派" },
    { id = "guild",  label = "帮会" },
    { id = "equip",  label = "装备" },
    { id = "realm",  label = "境界" },
    { id = "ladder", label = "天梯" },
}
local RANK_SECT_ORDER = { "sword_sect", "iron_sect", "medicine_sect", "shadow_sect", "qidan_sect" }

-- 通用：渲染名次颜色
local function RankColor(i)
    if i == 1 then return { 255, 200, 50, 255 }
    elseif i == 2 then return { 200, 200, 200, 255 }
    elseif i == 3 then return { 200, 140, 80, 255 }
    else return { 160, 160, 180, 220 } end
end
local function RankRowBg(i, isMe)
    if isMe then return { 30, 50, 30, 230 } end
    if i <= 3 then return { 40, 30, 15, 220 } end
    return { 22, 26, 44, 200 }
end
local function RankPrefix(i)
    return i <= 3 and ("★" .. i) or tostring(i)
end

-- 品质颜色
local function RankQualityColor(quality)
    local map = {
        common = { 180, 180, 180, 255 },
        uncommon = { 100, 200, 100, 255 },
        rare = { 80, 140, 255, 255 },
        epic = { 180, 80, 255, 255 },
        legendary = { 255, 160, 0, 255 },
        divine = { 255, 60, 60, 255 },
    }
    return map[quality] or { 160, 160, 160, 255 }
end
local function RankQualityName(quality)
    local map = {
        common = "普通", uncommon = "优秀", rare = "稀有",
        epic = "史诗", legendary = "传说", divine = "神品",
    }
    return map[quality] or ""
end

-- 渲染总战力榜
local function RenderRankPower(listArea, list)
    if not list or #list == 0 then
        listArea:AddChild(UI.Label { text = "暂无数据", fontSize = 14,
            color = TC.textSecondary, alignSelf = "center", marginTop = 16 })
        return
    end
    -- 表头
    local header = UI.Panel {
        width = "100%", height = 26, flexDirection = "row",
        backgroundColor = TC.bgDeep, alignItems = "center", paddingHorizontal = 6,
    }
    header:AddChild(UI.Label { text = "#", width = 30, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "玩家", flexGrow = 1, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "战力", width = 55, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "境界", width = 60, fontSize = 12, color = TC.textSecondary })
    listArea:AddChild(header)

    for i, e in ipairs(list) do
        local isMe = e.name == (player_ and player_.name)
        local row = UI.Panel {
            width = "100%", height = 28, flexDirection = "row",
            backgroundColor = RankRowBg(i, isMe), alignItems = "center",
            paddingHorizontal = 6, borderBottomWidth = 1, borderColor = TC.borderLight,
        }
        row:AddChild(UI.Label { text = RankPrefix(i), width = 30, fontSize = 13, color = RankColor(i) })
        row:AddChild(UI.Label {
            text = e.name .. (isMe and " [我]" or ""),
            flexGrow = 1, fontSize = 14,
            color = isMe and LOG_COLOR.good or { 220, 220, 240, 255 },
        })
        row:AddChild(UI.Label { text = tostring(e.power or 0), width = 55, fontSize = 13, color = LOG_COLOR.danger })
        row:AddChild(UI.Label {
            text = Settings.REALM.GetDisplayName(e.realm or 1, e.realm_layer or 1),
            width = 60, fontSize = 11, color = LOG_COLOR.gold,
        })
        listArea:AddChild(row)
    end
end

-- 渲染门派英豪榜
local function RenderRankSect(listArea, sectData)
    if not sectData then
        listArea:AddChild(UI.Label { text = "暂无数据", fontSize = 14,
            color = TC.textSecondary, alignSelf = "center", marginTop = 16 })
        return
    end
    -- 门派子Tab
    local sectTabRow = UI.Panel {
        width = "100%", height = 30, flexDirection = "row",
        gap = 2, marginBottom = 4, flexShrink = 0,
    }
    for _, sid in ipairs(RANK_SECT_ORDER) do
        local info = Settings.SECT_INFO and Settings.SECT_INFO[sid]
        local shortName = info and info.short or sid
        local c = info and info.color or { 160, 160, 200 }
        local isActive = (rankSectTab_ == sid)
        sectTabRow:AddChild(UI.Button {
            text = shortName, flexGrow = 1, height = 26,
            fontSize = 12,
            backgroundColor = isActive and { c[1], c[2], c[3], 180 } or TC.bgDeep,
            color = isActive and { 255, 255, 255, 255 } or { c[1], c[2], c[3], 200 },
            borderWidth = isActive and 1 or 0,
            borderColor = { c[1], c[2], c[3], 255 },
            onClick = function()
                rankSectTab_ = sid
                if currentPanel_ == PANEL.JIANGHU then
                    BuildNavSubPanel(PANEL.JIANGHU, "排名")
                end
            end,
        })
    end
    listArea:AddChild(sectTabRow)

    -- 当前门派数据
    local curSect = sectData[rankSectTab_]
    if not curSect then return end

    -- 门派统计
    local info = Settings.SECT_INFO and Settings.SECT_INFO[rankSectTab_]
    local sectColor = info and { info.color[1], info.color[2], info.color[3], 255 } or TC.textSecondary
    listArea:AddChild(UI.Label {
        text = string.format("弟子 %d 人  |  平均战力 %d", curSect.count or 0, curSect.avg_power or 0),
        fontSize = 12, color = sectColor, alignSelf = "center", marginBottom = 4,
    })

    local list = curSect.list
    if not list or #list == 0 then
        listArea:AddChild(UI.Label { text = "该门派暂无弟子", fontSize = 13,
            color = TC.textSecondary, alignSelf = "center", marginTop = 8 })
        return
    end
    -- 表头
    local header = UI.Panel {
        width = "100%", height = 26, flexDirection = "row",
        backgroundColor = TC.bgDeep, alignItems = "center", paddingHorizontal = 6,
    }
    header:AddChild(UI.Label { text = "#", width = 30, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "弟子", flexGrow = 1, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "战力", width = 55, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "境界", width = 60, fontSize = 12, color = TC.textSecondary })
    listArea:AddChild(header)

    for i, e in ipairs(list) do
        local isMe = e.name == (player_ and player_.name)
        local row = UI.Panel {
            width = "100%", height = 28, flexDirection = "row",
            backgroundColor = RankRowBg(i, isMe), alignItems = "center",
            paddingHorizontal = 6, borderBottomWidth = 1, borderColor = TC.borderLight,
        }
        row:AddChild(UI.Label { text = RankPrefix(i), width = 30, fontSize = 13, color = RankColor(i) })
        row:AddChild(UI.Label {
            text = e.name .. (isMe and " [我]" or ""),
            flexGrow = 1, fontSize = 14,
            color = isMe and LOG_COLOR.good or { 220, 220, 240, 255 },
        })
        row:AddChild(UI.Label { text = tostring(e.power or 0), width = 55, fontSize = 13, color = LOG_COLOR.danger })
        row:AddChild(UI.Label {
            text = Settings.REALM.GetDisplayName(e.realm or 1, e.realm_layer or 1),
            width = 60, fontSize = 11, color = LOG_COLOR.gold,
        })
        listArea:AddChild(row)
    end
end

-- 渲染帮会总战力榜
local function RenderRankGuild(listArea, list)
    if not list or #list == 0 then
        listArea:AddChild(UI.Label { text = "暂无帮会", fontSize = 14,
            color = TC.textSecondary, alignSelf = "center", marginTop = 16 })
        return
    end
    local header = UI.Panel {
        width = "100%", height = 26, flexDirection = "row",
        backgroundColor = TC.bgDeep, alignItems = "center", paddingHorizontal = 6,
    }
    header:AddChild(UI.Label { text = "#", width = 24, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "帮会", flexGrow = 1, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "总战力", width = 55, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "人数", width = 30, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "均战力", width = 50, fontSize = 12, color = TC.textSecondary })
    listArea:AddChild(header)

    for i, e in ipairs(list) do
        local isMyGuild = (player_ and player_.guild_name == e.name)
        local row = UI.Panel {
            width = "100%", height = 28, flexDirection = "row",
            backgroundColor = RankRowBg(i, isMyGuild), alignItems = "center",
            paddingHorizontal = 6, borderBottomWidth = 1, borderColor = TC.borderLight,
        }
        row:AddChild(UI.Label { text = RankPrefix(i), width = 24, fontSize = 13, color = RankColor(i) })
        row:AddChild(UI.Label {
            text = e.name .. (isMyGuild and " [我]" or ""),
            flexGrow = 1, fontSize = 14,
            color = isMyGuild and LOG_COLOR.good or { 220, 220, 240, 255 },
        })
        row:AddChild(UI.Label { text = tostring(e.total_power or 0), width = 55, fontSize = 12, color = LOG_COLOR.danger })
        row:AddChild(UI.Label { text = tostring(e.members or 0), width = 30, fontSize = 12, color = TC.textSecondary })
        row:AddChild(UI.Label { text = tostring(e.avg_power or 0), width = 50, fontSize = 11, color = LOG_COLOR.gold })
        listArea:AddChild(row)
    end
end

-- 渲染装备战力榜
local function RenderRankEquip(listArea, list)
    if not list or #list == 0 then
        listArea:AddChild(UI.Label { text = "暂无数据", fontSize = 14,
            color = TC.textSecondary, alignSelf = "center", marginTop = 16 })
        return
    end
    local header = UI.Panel {
        width = "100%", height = 26, flexDirection = "row",
        backgroundColor = TC.bgDeep, alignItems = "center", paddingHorizontal = 6,
    }
    header:AddChild(UI.Label { text = "#", width = 30, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "玩家", flexGrow = 1, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "装备战力", width = 60, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "最高品质", width = 55, fontSize = 12, color = TC.textSecondary })
    listArea:AddChild(header)

    for i, e in ipairs(list) do
        local isMe = e.name == (player_ and player_.name)
        local qName = RankQualityName(e.best_quality or "")
        local qColor = RankQualityColor(e.best_quality or "")
        local row = UI.Panel {
            width = "100%", height = 28, flexDirection = "row",
            backgroundColor = RankRowBg(i, isMe), alignItems = "center",
            paddingHorizontal = 6, borderBottomWidth = 1, borderColor = TC.borderLight,
        }
        row:AddChild(UI.Label { text = RankPrefix(i), width = 30, fontSize = 13, color = RankColor(i) })
        row:AddChild(UI.Label {
            text = e.name .. (isMe and " [我]" or ""),
            flexGrow = 1, fontSize = 14,
            color = isMe and LOG_COLOR.good or { 220, 220, 240, 255 },
        })
        row:AddChild(UI.Label { text = tostring(e.equip_power or 0), width = 60, fontSize = 13, color = { 100, 200, 255, 255 } })
        row:AddChild(UI.Label { text = qName, width = 55, fontSize = 12, color = qColor })
        listArea:AddChild(row)
    end
end

-- 渲染境界榜
local function RenderRankRealm(listArea, list)
    if not list or #list == 0 then
        listArea:AddChild(UI.Label { text = "暂无数据", fontSize = 14,
            color = TC.textSecondary, alignSelf = "center", marginTop = 16 })
        return
    end
    local header = UI.Panel {
        width = "100%", height = 26, flexDirection = "row",
        backgroundColor = TC.bgDeep, alignItems = "center", paddingHorizontal = 6,
    }
    header:AddChild(UI.Label { text = "#", width = 30, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "玩家", flexGrow = 1, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "境界", width = 70, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "门派", width = 55, fontSize = 12, color = TC.textSecondary })
    listArea:AddChild(header)

    for i, e in ipairs(list) do
        local isMe = e.name == (player_ and player_.name)
        local row = UI.Panel {
            width = "100%", height = 28, flexDirection = "row",
            backgroundColor = RankRowBg(i, isMe), alignItems = "center",
            paddingHorizontal = 6, borderBottomWidth = 1, borderColor = TC.borderLight,
        }
        row:AddChild(UI.Label { text = RankPrefix(i), width = 30, fontSize = 13, color = RankColor(i) })
        row:AddChild(UI.Label {
            text = e.name .. (isMe and " [我]" or ""),
            flexGrow = 1, fontSize = 14,
            color = isMe and LOG_COLOR.good or { 220, 220, 240, 255 },
        })
        row:AddChild(UI.Label {
            text = Settings.REALM.GetDisplayName(e.realm or 1, e.realm_layer or 1),
            width = 70, fontSize = 12, color = LOG_COLOR.gold,
        })
        row:AddChild(UI.Label {
            text = GetSectShort(e.sect or ""),
            width = 55, fontSize = 12, color = GetSectColor(e.sect or ""),
        })
        listArea:AddChild(row)
    end
end

-- 渲染天梯排行榜
local function RenderRankLadder(listArea, list)
    if not list or #list == 0 then
        listArea:AddChild(UI.Label { text = "暂无天梯数据", fontSize = 14,
            color = TC.textSecondary, alignSelf = "center", marginTop = 16 })
        return
    end
    local header = UI.Panel {
        width = "100%", height = 26, flexDirection = "row",
        backgroundColor = TC.bgDeep, alignItems = "center", paddingHorizontal = 6,
    }
    header:AddChild(UI.Label { text = "#", width = 24, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "玩家", flexGrow = 1, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "积分", width = 45, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "胜/负", width = 50, fontSize = 12, color = TC.textSecondary })
    header:AddChild(UI.Label { text = "门派", width = 40, fontSize = 12, color = TC.textSecondary })
    listArea:AddChild(header)

    for i, e in ipairs(list) do
        local isMe = e.name == (player_ and player_.name)
        local row = UI.Panel {
            width = "100%", height = 28, flexDirection = "row",
            backgroundColor = RankRowBg(i, isMe), alignItems = "center",
            paddingHorizontal = 6, borderBottomWidth = 1, borderColor = TC.borderLight,
        }
        row:AddChild(UI.Label { text = RankPrefix(i), width = 24, fontSize = 13, color = RankColor(i) })
        row:AddChild(UI.Label {
            text = e.name .. (isMe and " [我]" or ""),
            flexGrow = 1, fontSize = 14,
            color = isMe and LOG_COLOR.good or { 220, 220, 240, 255 },
        })
        row:AddChild(UI.Label { text = tostring(e.rating or 0), width = 45, fontSize = 13, color = { 255, 180, 50, 255 } })
        row:AddChild(UI.Label {
            text = string.format("%d/%d", e.wins or 0, e.losses or 0),
            width = 50, fontSize = 11, color = TC.textSecondary,
        })
        row:AddChild(UI.Label {
            text = GetSectShort(e.sect or ""),
            width = 40, fontSize = 11, color = GetSectColor(e.sect or ""),
        })
        listArea:AddChild(row)
    end
end

local function BuildRankPanel()
    local container = UI.Panel {
        width = "100%",
        padding = { 6, 4 }, gap = 3,
    }

    -- 标题
    container:AddChild(UI.Label {
        text = "── 江湖排行榜 ──",
        fontSize = 16, color = LOG_COLOR.title,
        marginBottom = 2, alignSelf = "center",
    })

    -- 顶部 Tab 栏
    local tabRow = UI.Panel {
        width = "100%", height = 30, flexDirection = "row",
        gap = 2, marginBottom = 4, flexShrink = 0,
    }
    for _, tab in ipairs(RANK_TABS) do
        local isActive = (rankCurrentTab_ == tab.id)
        tabRow:AddChild(UI.Button {
            text = tab.label, flexGrow = 1, height = 26,
            fontSize = 12,
            backgroundColor = isActive and { 60, 80, 140, 240 } or TC.bgDeep,
            color = isActive and { 255, 255, 255, 255 } or TC.textSecondary,
            borderBottomWidth = isActive and 2 or 0,
            borderColor = { 100, 160, 255, 255 },
            onClick = function()
                rankCurrentTab_ = tab.id
                -- 自动拉取该类型数据（如果缓存中没有）
                if not rankData_[tab.id] then
                    SendToServer(EV.REQ_RANK, { RankType = tab.id })
                end
                if currentPanel_ == PANEL.JIANGHU then
                    BuildNavSubPanel(PANEL.JIANGHU, "排名")
                end
            end,
        })
    end
    container:AddChild(tabRow)

    -- 内容区域
    local listArea = UI.Panel { width = "100%", gap = 2 }

    local data = rankData_[rankCurrentTab_]
    if data then
        if rankCurrentTab_ == "power" then
            RenderRankPower(listArea, data)
        elseif rankCurrentTab_ == "sect" then
            RenderRankSect(listArea, data)
        elseif rankCurrentTab_ == "guild" then
            RenderRankGuild(listArea, data)
        elseif rankCurrentTab_ == "equip" then
            RenderRankEquip(listArea, data)
        elseif rankCurrentTab_ == "realm" then
            RenderRankRealm(listArea, data)
        elseif rankCurrentTab_ == "ladder" then
            RenderRankLadder(listArea, data)
        end
    else
        listArea:AddChild(UI.Label {
            text = "点击刷新获取排行榜",
            fontSize = 14, color = TC.textSecondary,
            alignSelf = "center", marginTop = 16,
        })
    end

    container:AddChild(listArea)

    -- 底部刷新按钮
    local refreshBtn = UI.Button {
        text = "刷新排行榜", width = "80%", height = 30,
        alignSelf = "center", marginTop = 6, flexShrink = 0,
        backgroundColor = TC.bgPanel,
        onClick = function()
            SendToServer(EV.REQ_RANK, { RankType = rankCurrentTab_ })
            AddLog(">> 正在拉取排行榜...", "system")
        end,
    }
    container:AddChild(refreshBtn)

    return container
end

-- ============================================================================
-- 构建背包面板（方案B：左右分栏）
-- ============================================================================
local SLOT_ICON_MAP = {
    weapon   = "剑",
    helmet   = "盔",
    armor    = "甲",
    boots    = "靴",
    ring     = "戒",
    necklace = "链",
}
local TYPE_ICON_MAP = {
    equipment = nil,
    medicine  = "丹",
    material  = "材",
    skill     = "书",
}

-- 背包 UI 状态（合并为单 table 节省 local 槽位）
local invUI_ = { tab = "equipment", detailIdx = nil, opLock = 0 }

local function GetItemIcon(item)
    if not item then return "—" end
    local t = item.type or item.item_type
    if t == "equipment" then
        return SLOT_ICON_MAP[item.slot] or "器"
    end
    return TYPE_ICON_MAP[t] or "物"
end

local function GetItemShortName(item)
    if not item then return "" end
    local name = item.name or ""
    if not name or name == "" then
        if item.id and Settings.ALCHEMY_MATERIALS[item.id] then
            name = Settings.ALCHEMY_MATERIALS[item.id].name
        end
    end
    local dot = name:find("·")
    if dot then name = name:sub(1, dot - 1) end
    local chars = {}
    for _, code in utf8.codes(name) do
        chars[#chars + 1] = utf8.char(code)
        if #chars >= 4 then break end
    end
    return table.concat(chars)
end

-- 计算物品售价（客户端展示用）
local function CalcSellPriceClient(item)
    local SELL_BASE_PRICE_C = { [1] = 30, [2] = 80, [3] = 200, [4] = 500, [5] = 1200, [6] = 3000, [7] = 8000 }
    local QUALITY_SELL_MULT_C = { common = 1.0, uncommon = 1.5, rare = 2.5, epic = 4.0, legendary = 7.0, divine = 12.0 }
    if not item then return 0 end
    local itemType = item.type or item.item_type
    if itemType == "equipment" then
        local tier = item.tier or 1
        local base = SELL_BASE_PRICE_C[tier] or 30
        local mult = QUALITY_SELL_MULT_C[item.quality] or 1.0
        return math.floor(base * mult)
    elseif itemType == "medicine" then
        for _, def in ipairs(Settings.MEDICINE_SHOP) do
            if def.id == item.id then return math.floor((def.price or 20) * 0.5) end
        end
        return 10
    elseif itemType == "material" then
        local def = Settings.ALCHEMY_MATERIALS[item.id]
        if def then return math.floor((def.price or 10) * 0.4 * (item.count or 1)) end
        return 5
    end
    return 10
end

local function BuildInventoryPanel()
    local container = UI.Panel {
        width = "100%",
        flexGrow = 1,
        padding = 4,
        gap = 3,
    }

    local equip = (player_ and player_.equipment) or {}

    -- ══════════════════════════════════════════════════════════════════
    -- 顶部操作栏
    -- ══════════════════════════════════════════════════════════════════
    local topBar = UI.Panel {
        width = "100%", flexDirection = "row", gap = 4, marginBottom = 3,
        alignItems = "center",
    }
    topBar:AddChild(UI.Label {
        text = string.format("背包 (%d)", #inventory_),
        fontSize = 14, color = LOG_COLOR.title, flexGrow = 1,
    })
    topBar:AddChild(UI.Button {
        text = "一键最强", fontSize = 11, height = 22,
        paddingHorizontal = 8,
        backgroundColor = TC.bgPanel,
        onClick = function()
            SendToServer(EV.REQ_AUTO_EQUIP_BEST, {})
            AddLog(">> 执行一键最强装备...", "system")
        end,
    })
    container:AddChild(topBar)

    -- ══════════════════════════════════════════════════════════════════════════
    -- ── 主体：左右分栏 ───────────────────────────────────────────────────────
    -- ══════════════════════════════════════════════════════════════════════════
    local mainRow = UI.Panel {
        width = "100%", flexGrow = 1, flexDirection = "row", gap = 4,
    }

    -- ════════════════════════════════════════════════
    -- 左栏：已装备区
    -- ════════════════════════════════════════════════
    local leftPanel = UI.Panel {
        width = "38%", gap = 3,
        backgroundColor = TC.bgDeep,
        borderWidth = 1, borderColor = TC.border,
        padding = 5,
    }

    -- 属性汇总
    local totalAtk, totalDef, totalHp, totalAgi = 0, 0, 0, 0
    for _, it in pairs(equip) do
        if it and it.stats then
            totalAtk = totalAtk + (it.stats.atk or 0)
            totalDef = totalDef + (it.stats.def or 0)
            totalHp  = totalHp  + (it.stats.hp  or 0)
            totalAgi = totalAgi + (it.stats.agi or 0)
        end
    end
    local statLine = ""
    if totalAtk > 0 or totalDef > 0 then
        local parts = {}
        if totalAtk > 0 then parts[#parts+1] = "攻" .. totalAtk end
        if totalDef > 0 then parts[#parts+1] = "防" .. totalDef end
        if totalHp  > 0 then parts[#parts+1] = "血" .. totalHp end
        if totalAgi > 0 then parts[#parts+1] = "敏" .. totalAgi end
        statLine = table.concat(parts, " ")
    end
    leftPanel:AddChild(UI.Label {
        text = "装备栏", fontSize = 13, color = TC.info, alignSelf = "center",
    })
    if statLine ~= "" then
        leftPanel:AddChild(UI.Label {
            text = statLine, fontSize = 11, color = TC.success, alignSelf = "center",
        })
    end

    -- 6个装备槽（纵向排列）
    for _, slotId in ipairs(Settings.EQUIPMENT_SLOTS) do
        local slotName = Settings.EQUIPMENT_SLOT_NAME[slotId] or slotId
        local eqItem = equip[slotId]
        local qColor = eqItem and QualityColor(eqItem.quality) or { 50, 55, 65, 150 }

        local slotCell = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            backgroundColor = eqItem and { math.floor(qColor[1]*0.12), math.floor(qColor[2]*0.12), math.floor(qColor[3]*0.12), 220 } or { 18, 22, 28, 140 },
            borderWidth = 1,
            borderColor = eqItem and { qColor[1], qColor[2], qColor[3], 160 } or { 35, 40, 50, 100 },
            borderRadius = 3,
            padding = { 3, 5 },
            gap = 4,
        }

        -- 槽位图标
        local slotIcon = SLOT_ICON_MAP[slotId] or "◇"
        slotCell:AddChild(UI.Label {
            text = slotIcon, fontSize = 14,
            color = eqItem and qColor or { 60, 65, 70, 150 },
            width = 18,
        })

        -- 装备名（或"空"）
        local displayName = eqItem and GetItemShortName(eqItem) or "空"
        slotCell:AddChild(UI.Label {
            text = displayName, fontSize = 11,
            color = eqItem and qColor or { 70, 75, 80, 160 },
            flexGrow = 1, flexShrink = 1,
        })

        -- 卸下按钮
        if eqItem then
            local capturedSlot = slotId
            local capturedName = eqItem.name
            slotCell:AddChild(UI.Button {
                text = "卸", fontSize = 9, width = 20, height = 16,
                backgroundColor = TC.btnPrimary,
                borderRadius = 2,
                onClick = function()
                    if invUI_.opLock > 0 and (os.clock() - invUI_.opLock) < 3 then return end
                    invUI_.opLock = os.clock()
                    SendToServer(EV.REQ_UNEQUIP_ITEM, { Slot = capturedSlot })
                    AddLog(">> 卸下 " .. capturedName, "info")
                end,
            })
        end

        leftPanel:AddChild(slotCell)
    end
    mainRow:AddChild(leftPanel)

    -- ══════════════════════════════════════════════════════════════════════════
    -- ── 右面板：Tab 列表 ─────────────────────────────────────────────────────
    -- ══════════════════════════════════════════════════════════════════════════
    local rightPanel = UI.Panel {
        flexGrow = 1, flexShrink = 1,
        gap = 3,
    }

    -- Tab 标签栏
    local TAB_DEFS = {
        { key = "equipment", label = "装备" },
        { key = "material",  label = "材料" },
        { key = "medicine",  label = "丹药" },
    }
    local tabRow = UI.Panel {
        width = "100%", flexDirection = "row", gap = 3, marginBottom = 2,
    }
    for _, td in ipairs(TAB_DEFS) do
        local isActive = (invUI_.tab == td.key)
        local capturedKey = td.key
        tabRow:AddChild(UI.Button {
            text = td.label, fontSize = 11,
            flexGrow = 1,
            height = 22,
            backgroundColor = isActive and { 40, 80, 60, 240 } or { 25, 30, 35, 200 },
            borderWidth = isActive and 1 or 0,
            borderColor = TC.success,
            borderRadius = 3,
            onClick = function()
                invUI_.tab = capturedKey
                invUI_.detailIdx = nil
                Client.SwitchPanel(PANEL.INVENTORY)
            end,
        })
    end
    rightPanel:AddChild(tabRow)

    -- 过滤当前 tab 的物品（"medicine" Tab 同时匹配 medicine 和 pill 类型）
    local filteredItems = {}
    for i, item in ipairs(inventory_) do
        local itemType = item.type or item.item_type
        local match = (itemType == invUI_.tab)
            or (invUI_.tab == "medicine" and (itemType == "pill" or itemType == "realm_pill"))
        if match then
            -- 补充材料名称
            if itemType == "material" and not item.name and item.id and Settings.ALCHEMY_MATERIALS[item.id] then
                item.name = Settings.ALCHEMY_MATERIALS[item.id].name
                item.quality = item.quality or Settings.ALCHEMY_MATERIALS[item.id].quality or 1
            end
            -- 补充丹药名称（从 PILLS 定义中获取）
            if itemType == "pill" and not item.name and item.id and Settings.PILLS and Settings.PILLS[item.id] then
                item.name = Settings.PILLS[item.id].name
                item.quality = item.quality or Settings.PILLS[item.id].quality or 1
            end
            filteredItems[#filteredItems + 1] = { idx = i, item = item }
        end
    end

    -- 批量出售按钮（装备/材料tab可用）
    if invUI_.tab ~= "medicine" and #filteredItems > 0 then
        local sellAllRow = UI.Panel { width = "100%", flexDirection = "row", justifyContent = "flex-end" }
        sellAllRow:AddChild(UI.Button {
            text = "批量出售全部", fontSize = 10, height = 20,
            paddingHorizontal = 8,
            backgroundColor = TC.warning,
            borderRadius = 3,
            onClick = function()
                if invUI_.opLock > 0 and (os.clock() - invUI_.opLock) < 3 then return end
                invUI_.opLock = os.clock()
                local ids = {}
                for _, fi in ipairs(filteredItems) do
                    ids[#ids + 1] = fi.item.id
                end
                SendToServer(EV.REQ_BATCH_SELL, { ItemIds = cjson.encode(ids) })
                AddLog(string.format(">> 批量出售 %d 件物品...", #ids), "system")
                invUI_.detailIdx = nil
            end,
        })
        rightPanel:AddChild(sellAllRow)
    end

    -- 物品列表（包裹在 ScrollView 中，防止列表过长挤掉详情面板）
    local listScroll = UI.ScrollView { width = "100%", flexGrow = 1, flexShrink = 1, minHeight = 0 }
    local listPanel = UI.Panel {
        width = "100%", gap = 2,
    }

    if #filteredItems == 0 then
        listPanel:AddChild(UI.Label {
            text = "（空）", fontSize = 12, color = TC.textMuted,
            alignSelf = "center", marginTop = 20,
        })
    else
        for _, fi in ipairs(filteredItems) do
            local item = fi.item
            local idx = fi.idx
            local isSelected = (invUI_.detailIdx == idx)
            local qColor = QualityColor(item.quality)
            local sellPrice = CalcSellPriceClient(item)

            local row = UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                backgroundColor = isSelected and { qColor[1], qColor[2], qColor[3], 40 } or { 15, 18, 22, 180 },
                borderWidth = isSelected and 1 or 0,
                borderColor = qColor,
                borderRadius = 3,
                padding = { 3, 5 },
                gap = 4,
                onClick = function()
                    if invUI_.detailIdx == idx then
                        invUI_.detailIdx = nil
                    else
                        invUI_.detailIdx = idx
                    end
                    Client.SwitchPanel(PANEL.INVENTORY)
                end,
            }

            -- 图标
            row:AddChild(UI.Label {
                text = GetItemIcon(item), fontSize = 14, color = qColor, width = 18,
            })

            -- 名称
            local nameStr = item.name or "???"
            if item.count and item.count > 1 then
                nameStr = nameStr .. " x" .. item.count
            end
            row:AddChild(UI.Label {
                text = nameStr, fontSize = 11, color = qColor,
                flexGrow = 1, flexShrink = 1,
            })

            -- 售价标签
            if sellPrice > 0 then
                row:AddChild(UI.Label {
                    text = sellPrice .. "银", fontSize = 9,
                    color = TC.textTitle,
                })
            end

            -- 快捷出售按钮
            if invUI_.tab ~= "medicine" then
                local capturedItem = item
                row:AddChild(UI.Button {
                    text = "售", fontSize = 9, width = 20, height = 16,
                    backgroundColor = TC.warning,
                    borderRadius = 2,
                    onClick = function()
                        if invUI_.opLock > 0 and (os.clock() - invUI_.opLock) < 3 then return end
                        invUI_.opLock = os.clock()
                        SendToServer(EV.REQ_SELL_ITEM, { ItemId = capturedItem.id })
                        AddLog(">> 出售 " .. (capturedItem.name or "物品"), "info")
                        invUI_.detailIdx = nil
                    end,
                })
            end

            listPanel:AddChild(row)
        end
    end
    listScroll:AddChild(listPanel)
    rightPanel:AddChild(listScroll)

    -- ══════════════════════════════════════════════════════════════════════════
    -- ── 详情面板（选中物品时显示）────────────────────────────────────────────
    -- ══════════════════════════════════════════════════════════════════════════
    if invUI_.detailIdx and inventory_[invUI_.detailIdx] then
        local item = inventory_[invUI_.detailIdx]
        -- 补充材料名
        if not item.name and item.id and Settings.ALCHEMY_MATERIALS[item.id] then
            item.name = Settings.ALCHEMY_MATERIALS[item.id].name
            item.quality = item.quality or Settings.ALCHEMY_MATERIALS[item.id].quality or 1
        end
        local qColor = QualityColor(item.quality)
        local itemType = item.type or item.item_type

        local detail = UI.Panel {
            width = "100%",
            backgroundColor = TC.bgDeep,
            borderWidth = 1,
            borderColor = qColor,
            borderRadius = 4,
            padding = 8,
            gap = 4,
            marginTop = 4,
        }

        -- 名称
        detail:AddChild(UI.Label {
            text = QualityName(item.quality) .. (item.name or "???"),
            fontSize = 14, color = qColor,
        })

        -- 属性
        if item.stats then
            local parts = {}
            if (item.stats.atk or 0) > 0 then parts[#parts+1] = "攻+" .. item.stats.atk end
            if (item.stats.def or 0) > 0 then parts[#parts+1] = "防+" .. item.stats.def end
            if (item.stats.hp or 0)  > 0 then parts[#parts+1] = "血+" .. item.stats.hp end
            if (item.stats.agi or 0) > 0 then parts[#parts+1] = "敏+" .. item.stats.agi end
            if #parts > 0 then
                detail:AddChild(UI.Label {
                    text = table.concat(parts, "  "), fontSize = 11, color = TC.success,
                })
            end
        end

        -- 效果描述（丹药）
        if item.effect then
            local effStr = ""
            if item.effect.hp then effStr = "恢复气血 " .. item.effect.hp end
            if effStr ~= "" then
                detail:AddChild(UI.Label {
                    text = effStr, fontSize = 11, color = TC.success,
                })
            end
        end
        -- 修为丹效果描述
        if itemType == "realm_pill" and item.exp then
            detail:AddChild(UI.Label {
                text = "修为 +" .. item.exp, fontSize = 11, color = TC.success,
            })
        end

        -- 类型 + 售价
        local infoLine = ""
        if itemType == "equipment" then
            infoLine = "装备·" .. (Settings.EQUIPMENT_SLOT_NAME[item.slot] or "")
        elseif itemType == "medicine" or itemType == "realm_pill" then
            infoLine = "丹药"
        elseif itemType == "material" then
            infoLine = "材料" .. (item.count and item.count > 1 and (" x" .. item.count) or "")
        end
        local sellPrice = CalcSellPriceClient(item)
        if sellPrice > 0 then infoLine = infoLine .. "  |  售价: " .. sellPrice .. "银" end
        if infoLine ~= "" then
            detail:AddChild(UI.Label {
                text = infoLine, fontSize = 10, color = TC.textMuted,
            })
        end

        -- 操作按钮行
        local btnRow = UI.Panel {
            flexDirection = "row", flexWrap = "wrap", gap = 6, marginTop = 4,
        }

        if itemType == "equipment" then
            local capturedItem = item
            local equipBtn = UI.Button {
                text = "装备", fontSize = 12, paddingHorizontal = 12, height = 24,
                borderRadius = 3,
                onClick = function()
                    if invUI_.opLock > 0 and (os.clock() - invUI_.opLock) < 3 then return end
                    invUI_.opLock = os.clock()
                    local curEquip = (player_ and player_.equipment) or {}
                    if capturedItem.slot and curEquip[capturedItem.slot] then
                        UI.Toast.Show("替换：" .. curEquip[capturedItem.slot].name, { type = "warning", duration = 2 })
                    end
                    SendToServer(EV.REQ_EQUIP_ITEM, { ItemId = capturedItem.id })
                    AddLog(">> 装备 " .. capturedItem.name, "good")
                    Tutorial.Advance("item_equipped")
                    invUI_.detailIdx = nil
                end,
            }
            Tutorial.RegisterTarget("inventory_first_equip", equipBtn)
            btnRow:AddChild(equipBtn)
        elseif itemType == "medicine" or itemType == "realm_pill" then
            local medId = tostring(item.id or "")
            local medName = item.name or "???"
            local useEvent = (itemType == "realm_pill") and EV.REQ_USE_REALM_PILL or EV.REQ_USE_ITEM
            local useKey   = (itemType == "realm_pill") and "PillIndex" or "ItemId"
            local useVal   = (itemType == "realm_pill") and (item.realm_index or 1) or medId
            btnRow:AddChild(UI.Button {
                text = "服用", fontSize = 12, paddingHorizontal = 12, height = 24,
                borderRadius = 3,
                onClick = function()
                    if medId == "" and itemType ~= "realm_pill" then AddLog("数据异常", "warn"); return end
                    if invUI_.opLock > 0 and (os.clock() - invUI_.opLock) < 3 then return end
                    invUI_.opLock = os.clock()
                    if itemType == "realm_pill" then
                        local vm = VariantMap()
                        vm:SetInt("PillIndex", useVal)
                        serverConn_:SendRemoteEvent(useEvent, true, vm)
                    else
                        SendToServer(useEvent, { ItemId = medId })
                    end
                    AddLog(">> 服用 " .. medName, "good")
                    invUI_.detailIdx = nil
                end,
            })
        end

        -- 出售
        if sellPrice > 0 then
            local capturedSellItem = item
            btnRow:AddChild(UI.Button {
                text = "出售(" .. sellPrice .. "银)", fontSize = 11, paddingHorizontal = 10, height = 24,
                backgroundColor = TC.warning,
                borderRadius = 3,
                onClick = function()
                    if invUI_.opLock > 0 and (os.clock() - invUI_.opLock) < 3 then return end
                    invUI_.opLock = os.clock()
                    SendToServer(EV.REQ_SELL_ITEM, { ItemId = capturedSellItem.id })
                    AddLog(">> 出售 " .. (capturedSellItem.name or "物品"), "info")
                    invUI_.detailIdx = nil
                end,
            })
        end

        -- 丢弃
        local capturedDiscard = item
        btnRow:AddChild(UI.Button {
            text = "丢弃", fontSize = 11, paddingHorizontal = 10, height = 24,
            backgroundColor = TC.btnPrimary,
            borderRadius = 3,
            onClick = function()
                if invUI_.opLock > 0 and (os.clock() - invUI_.opLock) < 3 then return end
                invUI_.opLock = os.clock()
                SendToServer(EV.REQ_DISCARD_ITEM, { ItemId = capturedDiscard.id })
                AddLog(">> 丢弃 " .. (capturedDiscard.name or "物品"), "warn")
                invUI_.detailIdx = nil
            end,
        })

        -- 分享到聊天
        local capturedShare = item
        local capturedShareType = itemType
        btnRow:AddChild(UI.Button {
            text = "分享", fontSize = 11, paddingHorizontal = 10, height = 24,
            backgroundColor = { 50, 100, 160, 220 },
            borderRadius = 3,
            onClick = function()
                local chKey = CHAT_CHANNEL_KEY[chatActiveChannel_] or "world"
                local text
                if capturedShareType == "equipment" then
                    local statsStr = ""
                    if capturedShare.stats then
                        local ps = {}
                        if (capturedShare.stats.atk or 0) > 0 then ps[#ps+1] = "攻" .. capturedShare.stats.atk end
                        if (capturedShare.stats.def or 0) > 0 then ps[#ps+1] = "防" .. capturedShare.stats.def end
                        if (capturedShare.stats.hp or 0)  > 0 then ps[#ps+1] = "血" .. capturedShare.stats.hp end
                        if (capturedShare.stats.agi or 0) > 0 then ps[#ps+1] = "敏" .. capturedShare.stats.agi end
                        statsStr = table.concat(ps, "/")
                    end
                    text = "[equip:" .. (capturedShare.name or "???") .. ":" .. (capturedShare.quality or "common") .. ":" .. statsStr .. "]"
                else
                    text = "[item:" .. (capturedShare.name or "???") .. ":" .. (capturedShare.quality or "common") .. "]"
                end
                SendToServer(EV.REQ_CHAT_SEND, { Channel = chKey, Text = text })
                AddLog(">> 已分享到" .. (chatActiveChannel_ or "世界") .. "频道", "good")
                UI.Toast.Show("已分享到聊天", { type = "success", duration = 1.5 })
            end,
        })

        -- 关闭
        btnRow:AddChild(UI.Button {
            text = "×", fontSize = 12, width = 24, height = 24,
            backgroundColor = TC.bgPanelLight,
            borderRadius = 3,
            onClick = function()
                invUI_.detailIdx = nil
                Client.SwitchPanel(PANEL.INVENTORY)
            end,
        })

        detail:AddChild(btnRow)
        rightPanel:AddChild(detail)
    end

    mainRow:AddChild(rightPanel)
    container:AddChild(mainRow)

    return container
end

-- 构建交易阁面板
local function BuildMarketPanel()
    -- ═══ 精致古风配色 ═══
    local INK = { 15, 12, 10, 255 }             -- 深墨底（更纯净的黑）
    local PARCHMENT = { 38, 32, 22, 245 }       -- 竹简深底
    local PARCHMENT_L = { 50, 42, 30, 245 }     -- 竹简浅底
    local SCROLL_BORDER = { 155, 125, 60, 220 } -- 鎏金描边（提亮）
    local GOLD_TEXT = { 235, 200, 85, 255 }     -- 鎏金字（更明亮）
    local GOLD_DIM = { 180, 150, 60, 200 }      -- 暗金（装饰用）
    local RED_SEAL = { 195, 50, 40, 255 }       -- 朱砂印（更鲜艳）
    local INK_TEXT = { 228, 218, 198, 255 }     -- 宣纸白（主文字）
    local INK_GRAY = { 150, 140, 120, 255 }     -- 淡墨（次要文字）
    local JADE_GREEN = { 88, 205, 130, 255 }    -- 翠玉绿（更通透）
    local BRUSH_BROWN = { 130, 100, 50, 200 }   -- 笔触褐（提亮）
    local TAB_ACTIVE = { 55, 42, 22, 255 }      -- 书页选中（更饱和）
    local TAB_INACTIVE = { 25, 20, 14, 220 }    -- 书页未选中
    local CARD_BG = { 32, 27, 18, 250 }         -- 卡片底色
    local CARD_HOVER = { 42, 35, 24, 250 }      -- 卡片悬浮

    -- 古风品质称谓 & 配色
    local QUALITY_ANCIENT = {
        [1] = { name = "凡品", color = TC.textPrimary },
        [2] = { name = "良品", color = TC.success },
        [3] = { name = "精品", color = TC.info },
        [4] = { name = "极品", color = TC.rare },
        [5] = { name = "仙品", color = TC.textTitle },
        [6] = { name = "神品", color = TC.danger },
    }
    local function AncientQualityName(q)
        local def = QUALITY_ANCIENT[q or 1] or QUALITY_ANCIENT[1]
        return "〔" .. def.name .. "〕"
    end
    local function AncientQualityColor(q)
        local def = QUALITY_ANCIENT[q or 1] or QUALITY_ANCIENT[1]
        return def.color
    end

    -- ═══ 外层容器（竹简墨底） ═══
    local container = UI.Panel {
        width = "100%",
        flexGrow = 1,
        padding = 12,
        gap = 0,
        backgroundColor = INK,
        borderWidth = 1, borderColor = TC.borderLight,
        borderRadius = 2,
    }



    -- ═══ 倒爷等级区 → 仅在"我的"Tab显示（函数化） ═══
    local function BuildTraderRankCard()
        local traderLevel = player_ and player_.trader_level or 0
        local tradeProfit = player_ and player_.trade_profit or 0
        local curTitle = "无名商贩"
        local curDiscount = 0.0
        local nextProfit = Settings.TRADER_LEVELS[1] and Settings.TRADER_LEVELS[1].profit or 100
        if traderLevel > 0 and Settings.TRADER_LEVELS[traderLevel] then
            curTitle = Settings.TRADER_LEVELS[traderLevel].title
            curDiscount = Settings.TRADER_LEVELS[traderLevel].tax_discount
        end
        if traderLevel < #Settings.TRADER_LEVELS then
            nextProfit = Settings.TRADER_LEVELS[traderLevel + 1].profit
        else
            nextProfit = tradeProfit
        end
        local progress = math.min(1, tradeProfit / math.max(1, nextProfit))

        local rankCard = UI.Panel {
            width = "100%",
            backgroundColor = PARCHMENT,
            borderWidth = 1, borderColor = SCROLL_BORDER,
            borderRadius = 4,
            padding = { 8, 12 },
            marginBottom = 10,
        }
        -- 称号行
        local rankRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 8, justifyContent = "center" }
        rankRow:AddChild(UI.Label {
            text = "◈",
            fontSize = 13, color = GOLD_TEXT,
        })
        local titleColor = traderLevel >= 4 and GOLD_TEXT or (traderLevel >= 2 and JADE_GREEN or INK_TEXT)
        rankRow:AddChild(UI.Label {
            text = "商号：【" .. curTitle .. "】",
            fontSize = 15, color = titleColor,
        })
        if curDiscount > 0 then
            rankRow:AddChild(UI.Label {
                text = "· 税减" .. string.format("%.1f%%", curDiscount * 100),
                fontSize = 12, color = JADE_GREEN,
            })
        end
        rankCard:AddChild(rankRow)
        -- 进度行（朱砂印进度条）
        local progRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 8, marginTop = 6 }
        progRow:AddChild(UI.Label {
            text = "商誉", fontSize = 12, color = INK_GRAY,
        })
        local barBg = UI.Panel {
            flexGrow = 1, height = 8,
            backgroundColor = TC.bgPanel,
            borderRadius = 4, borderWidth = 1, borderColor = BRUSH_BROWN,
        }
        local barW = math.max(2, math.floor(progress * 100)) .. "%"
        barBg:AddChild(UI.Panel {
            width = barW, height = "100%",
            backgroundColor = GOLD_TEXT, borderRadius = 3,
        })
        progRow:AddChild(barBg)
        progRow:AddChild(UI.Label {
            text = string.format("%d/%d", tradeProfit, nextProfit),
            fontSize = 12, color = GOLD_DIM,
        })
        rankCard:AddChild(progRow)
        return rankCard
    end

    -- ═══ Tab 栏（书页翻页意象） ═══
    local function DoFetchListings(page)
        page = page or market_.page
        market_.page = page
        SendToServer(EV.REQ_MARKET_LIST, {
            FilterType    = market_.filterType,
            FilterQuality = market_.filterQuality,
            SortBy        = market_.sortBy,
            Page          = page,
        })
    end

    if market_.tab == "browse" and #market_.listings == 0 and not market_.history and not market_.fetched then
        market_.fetched = true
        market_.dataReceived = false
        DoFetchListings(1)
    end

    local tabRow = UI.Panel {
        flexDirection = "row", gap = 3, marginBottom = 10,
        width = "100%",
        borderBottomWidth = 2, borderColor = BRUSH_BROWN,
        paddingBottom = 0,
    }
    local function makeTab(label, icon, isActive, action)
        local tab = UI.Panel {
            flexGrow = 1, alignItems = "center",
        }
        tab:AddChild(UI.Button {
            text = icon .. " " .. label, fontSize = 13,
            width = "100%",
            paddingVertical = 8,
            backgroundColor = isActive and TAB_ACTIVE or { 0, 0, 0, 0 },
            color = isActive and GOLD_TEXT or INK_GRAY,
            borderTopLeftRadius = 4, borderTopRightRadius = 4,
            borderBottomLeftRadius = 0, borderBottomRightRadius = 0,
            borderWidth = 0,
            onClick = action,
        })
        if isActive then
            tab:AddChild(UI.Panel {
                width = "70%", height = 2,
                backgroundColor = GOLD_TEXT, borderRadius = 1,
            })
        else
            tab:AddChild(UI.Panel { width = "70%", height = 2 })
        end
        return tab
    end
    local isBrowseAll = market_.tab == "browse" and market_.filterType == "all" and not market_.history
    local isBrowseMine = market_.tab == "browse" and market_.filterType == "mine" and not market_.history
    tabRow:AddChild(makeTab("集市", "📜", isBrowseAll, function()
        market_.tab = "browse"
        market_.filterType = "all"
        market_.history = nil
        market_.page = 1
        market_.listings = {}
        market_.fetched = true
        market_.dataReceived = false
        DoFetchListings(1)
        Client.SwitchPanel(PANEL.MARKET)
    end))
    tabRow:AddChild(makeTab("我的", "🏷", isBrowseMine, function()
        market_.tab = "browse"
        market_.filterType = "mine"
        market_.history = nil
        market_.page = 1
        market_.listings = {}
        market_.fetched = true
        market_.dataReceived = false
        SendToServer(EV.REQ_MARKET_LIST, {
            FilterType = "mine", FilterQuality = "all", SortBy = "time_desc", Page = 1,
        })
        Client.SwitchPanel(PANEL.MARKET)
    end))
    tabRow:AddChild(makeTab("寄售", "🖋", market_.tab == "sell", function()
        market_.tab = "sell"
        market_.history = nil
        market_.sellIdx = nil
        Client.SwitchPanel(PANEL.MARKET)
    end))
    tabRow:AddChild(makeTab("账簿", "📖", market_.history ~= nil, function()
        market_.tab = "browse"
        ---@diagnostic disable-next-line: assign-type-mismatch
        market_.history = "loading"
        SendToServer(EV.REQ_MARKET_HISTORY, {})
        Client.SwitchPanel(PANEL.MARKET)
        AddLog(">> 查阅账簿...", "info")
    end))
    tabRow:AddChild(makeTab("行情", "📈", market_.tab == "trends", function()
        market_.tab = "trends"
        market_.history = nil
        print("[Client] 发送 REQ_MARKET_TRENDS, EV=" .. tostring(EV.REQ_MARKET_TRENDS))
        SendToServer(EV.REQ_MARKET_TRENDS, {})
        Client.SwitchPanel(PANEL.MARKET)
        AddLog(">> 查阅行情...", "info")
    end))
    container:AddChild(tabRow)

    -- ═══ 寄售 Tab ═══
    if market_.tab == "sell" then
        local items = inventory_ or {}
        local sellable = {}
        for i, item in ipairs(items) do
            if item and not item.bound then
                sellable[#sellable + 1] = { idx = i, item = item }
            end
        end

        local scroll = UI.ScrollView { width = "100%", flexGrow = 1, minHeight = 0 }
        local listPanel = UI.Panel { width = "100%", flexDirection = "column", gap = 5, flexShrink = 0, padding = 2 }


        for si, entry in ipairs(sellable) do
            local item = entry.item
            local qColor = AncientQualityColor(item.quality or 1)
            local isSelected = (market_.sellIdx == entry.idx)
            local card = UI.Panel {
                width = "100%",
                flexDirection = "column",
                backgroundColor = isSelected and PARCHMENT_L or PARCHMENT,
                borderWidth = 1,
                borderColor = isSelected and qColor or BRUSH_BROWN,
                borderRadius = 3,
                padding = { 6, 8 },
            }
            local itemRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 6 }
            itemRow:AddChild(UI.Label {
                text = AncientQualityName(item.quality or 1) .. (item.name or "未知"),
                fontSize = 15, color = qColor, flexGrow = 1, flexShrink = 1,
            })
            local statsText = ""
            if item.type == "equipment" and item.stats then
                local parts = {}
                if item.stats.attack and item.stats.attack > 0 then parts[#parts+1] = "攻" .. item.stats.attack end
                if item.stats.defense and item.stats.defense > 0 then parts[#parts+1] = "防" .. item.stats.defense end
                if item.stats.hp and item.stats.hp > 0 then parts[#parts+1] = "血" .. item.stats.hp end
                statsText = table.concat(parts, "/")
            elseif item.type == "medicine" then
                statsText = "丹药"
            end
            if statsText ~= "" then
                itemRow:AddChild(UI.Label { text = statsText, fontSize = 12, color = INK_GRAY })
            end
            itemRow:AddChild(UI.Button {
                text = isSelected and "▼ 收起" or "定价",
                fontSize = 13,
                paddingHorizontal = 10,
                backgroundColor = isSelected and TAB_ACTIVE or { 50, 40, 25, 220 },
                color = isSelected and GOLD_TEXT or INK_TEXT,
                borderWidth = 1, borderColor = BRUSH_BROWN,
                borderRadius = 2,
                onClick = function()
                    market_.sellIdx = isSelected and nil or entry.idx
                    Client.SwitchPanel(PANEL.MARKET)
                end,
            })
            card:AddChild(itemRow)

            -- 展开定价面板
            if isSelected then
                -- 强制灵石标价
                market_.sellCurrency = "spirit_stone"
                local pricePanel = UI.Panel {
                    width = "100%", flexDirection = "column", gap = 5,
                    marginTop = 6, paddingTop = 6,
                    borderTopWidth = 1, borderColor = BRUSH_BROWN,
                }
                -- 标价币种提示（固定灵石）
                pricePanel:AddChild(UI.Label {
                    text = "💎 以灵石标价", fontSize = 12, color = JADE_GREEN, marginBottom = 2,
                })

                -- 定价行
                local priceRow = UI.Panel { flexDirection = "row", gap = 5, alignItems = "center" }
                priceRow:AddChild(UI.Label { text = "开价：", fontSize = 13, color = INK_GRAY })
                priceRow:AddChild(UI.Button {
                    text = "－", fontSize = 16, width = 30, height = 30,
                    backgroundColor = TC.bgPanelLight, color = INK_TEXT,
                    borderWidth = 1, borderColor = BRUSH_BROWN, borderRadius = 2,
                    onClick = function()
                        market_.sellPrice = math.max(1, market_.sellPrice - 1)
                        Client.SwitchPanel(PANEL.MARKET)
                    end,
                })
                local priceLabel = tostring(market_.sellPrice) .. " 💎"
                priceRow:AddChild(UI.Label {
                    text = priceLabel, fontSize = 16, color = GOLD_TEXT,
                    minWidth = 70, textAlign = "center",
                })
                priceRow:AddChild(UI.Button {
                    text = "＋", fontSize = 16, width = 30, height = 30,
                    backgroundColor = TC.bgPanelLight, color = INK_TEXT,
                    borderWidth = 1, borderColor = BRUSH_BROWN, borderRadius = 2,
                    onClick = function()
                        market_.sellPrice = market_.sellPrice + 1
                        Client.SwitchPanel(PANEL.MARKET)
                    end,
                })
                pricePanel:AddChild(priceRow)

                -- 快捷定价（灵石）
                local quickRow = UI.Panel { flexDirection = "row", gap = 4, flexWrap = "wrap", marginTop = 2 }
                local quickPrices = { 1, 3, 5, 10, 20, 50, 100 }
                for _, qp in ipairs(quickPrices) do
                    quickRow:AddChild(UI.Button {
                        text = tostring(qp), fontSize = 12,
                        paddingHorizontal = 8, paddingVertical = 3,
                        backgroundColor = TAB_INACTIVE,
                        color = INK_TEXT, borderWidth = 1, borderColor = BRUSH_BROWN,
                        borderRadius = 2,
                        onClick = function()
                            market_.sellPrice = qp
                            Client.SwitchPanel(PANEL.MARKET)
                        end,
                    })
                end
                pricePanel:AddChild(quickRow)

                -- 确认上架
                pricePanel:AddChild(UI.Button {
                    text = "⊱ 确认寄售 · " .. priceLabel .. " ⊰",
                    fontSize = 15,
                    backgroundColor = TC.bgPanelLight,
                    color = GOLD_TEXT,
                    borderWidth = 1, borderColor = GOLD_TEXT,
                    borderRadius = 3,
                    marginTop = 4,
                    paddingVertical = 9,
                    onClick = function()
                        local sellItem = (inventory_ or {})[entry.idx]
                        if not sellItem or not sellItem.id then
                            AddLog("<红>物品不存在</红>", "danger")
                            return
                        end
                        SendToServer(EV.REQ_MARKET_SELL, {
                            ItemId   = sellItem.id,
                            Price    = market_.sellPrice,
                            Currency = "spirit_stone",
                        })
                        AddLog(">> 寄售 " .. (sellItem.name or "物品") .. "，开价 " .. market_.sellPrice .. "💎...", "gold")
                        market_.sellIdx = nil
                    end,
                })
                card:AddChild(pricePanel)
            end
            listPanel:AddChild(card)
        end
        scroll:AddChild(listPanel)
        container:AddChild(scroll)
        return container
    end

    -- ═══ 行情 Tab ═══
    if market_.tab == "trends" then
        local CAT_NAMES = {
            pill = "丹药", equipment = "兵器", skill = "功法",
            medicine = "灵药", material = "材料", other = "杂货",
        }
        local CAT_ICONS = {
            pill = "🏺", equipment = "⚔️", skill = "📜",
            medicine = "🌿", material = "🪨", other = "📦",
        }
        if not market_.trends then
            container:AddChild(UI.Panel {
                width = "100%", alignItems = "center", paddingVertical = 30,
                children = {
                    UI.Label { text = "正在查阅行情...", fontSize = 15, color = INK_GRAY },
                },
            })
            return container
        end
        if #market_.trends == 0 then
            container:AddChild(UI.Panel {
                width = "100%", alignItems = "center", paddingVertical = 30,
                children = {
                    UI.Label { text = "～ 市面冷清 ～", fontSize = 16, color = INK_GRAY },
                    UI.Label { text = "当前无在售货品", fontSize = 13, color = TC.textSecondary, marginTop = 4 },
                },
            })
            return container
        end
        container:AddChild(UI.Label {
            text = "▬▬ 市 场 行 情 ▬▬",
            fontSize = 15, color = GOLD_TEXT, alignSelf = "center", marginBottom = 6,
        })
        local scroll = UI.ScrollView { width = "100%", flexGrow = 1, minHeight = 0 }
        local listPanel = UI.Panel { width = "100%", flexDirection = "column", gap = 7, padding = 2, flexShrink = 0 }
        for _, trend in ipairs(market_.trends) do
            local catName = CAT_NAMES[trend.category] or trend.category
            local catIcon = CAT_ICONS[trend.category] or "📦"
            local card = UI.Panel {
                width = "100%", flexDirection = "column",
                backgroundColor = PARCHMENT,
                borderWidth = 1, borderColor = BRUSH_BROWN,
                borderRadius = 3, padding = { 7, 10 },
            }
            local headerRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, marginBottom = 5 }
            headerRow:AddChild(UI.Label { text = catIcon .. " " .. catName, fontSize = 15, color = GOLD_TEXT })
            headerRow:AddChild(UI.Label { text = "在售 " .. trend.listing_count .. " 件", fontSize = 12, color = INK_GRAY })
            headerRow:AddChild(UI.Panel { flexGrow = 1 })
            headerRow:AddChild(UI.Label { text = "均价 " .. trend.avg_price .. " 灵石", fontSize = 13, color = JADE_GREEN })
            card:AddChild(headerRow)
            if trend.hot_items and #trend.hot_items > 0 then
                for _, item in ipairs(trend.hot_items) do
                    local itemRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, marginLeft = 10, marginTop = 2 }
                    local changeText = ""
                    local changeColor = INK_GRAY
                    if item.base and item.base > 0 then
                        local pct = math.floor((item.avg - item.base) / item.base * 100)
                        if pct > 0 then
                            changeText = " ▲+" .. pct .. "%"
                            changeColor = RED_SEAL
                        elseif pct < 0 then
                            changeText = " ▼" .. pct .. "%"
                            changeColor = JADE_GREEN
                        else
                            changeText = " ━ 平"
                        end
                    end
                    itemRow:AddChild(UI.Label { text = "· " .. item.name, fontSize = 13, color = INK_TEXT, flexShrink = 1 })
                    itemRow:AddChild(UI.Panel { flexGrow = 1 })
                    itemRow:AddChild(UI.Label { text = item.avg .. "灵石", fontSize = 12, color = JADE_GREEN })
                    itemRow:AddChild(UI.Label { text = changeText, fontSize = 12, color = changeColor })
                    itemRow:AddChild(UI.Label { text = " ×" .. item.count, fontSize = 11, color = INK_GRAY })
                    card:AddChild(itemRow)
                end
            end
            listPanel:AddChild(card)
        end
        scroll:AddChild(listPanel)
        container:AddChild(scroll)
        return container
    end

    -- ═══ 筛选+排序（合并一行，紧凑布局） ═══
    local QUAL_FILTERS = {
        { id = "all", label = "全" },
        { id = "1",   label = "凡" },
        { id = "2",   label = "良" },
        { id = "3",   label = "精" },
        { id = "4",   label = "极" },
        { id = "5",   label = "仙" },
        { id = "6",   label = "神" },
    }
    local SORT_OPTIONS = {
        { id = "time_desc",  label = "新" },
        { id = "price_asc",  label = "低" },
        { id = "price_desc", label = "高" },
    }
    local filterSortRow = UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 3, marginBottom = 8, alignItems = "center", width = "100%" }
    -- 品阶筛选
    filterSortRow:AddChild(UI.Label { text = "品阶", fontSize = 11, color = INK_GRAY })
    for _, qf in ipairs(QUAL_FILTERS) do
        local isActive = market_.filterQuality == qf.id
        local qn = tonumber(qf.id)
        local txtColor = (qn and QUALITY_ANCIENT[qn]) and QUALITY_ANCIENT[qn].color or INK_TEXT
        filterSortRow:AddChild(UI.Button {
            text = qf.label, fontSize = 11,
            paddingHorizontal = 6, paddingVertical = 3,
            backgroundColor = isActive and TAB_ACTIVE or CARD_BG,
            color = isActive and txtColor or INK_GRAY,
            borderWidth = isActive and 1 or 0,
            borderColor = txtColor,
            borderRadius = 2,
            onClick = function()
                market_.filterQuality = qf.id
                market_.page = 1
                market_.dataReceived = false
                DoFetchListings(1)
                Client.SwitchPanel(PANEL.MARKET)
            end,
        })
    end
    -- 分隔
    filterSortRow:AddChild(UI.Panel { width = 1, height = 14, backgroundColor = BRUSH_BROWN, marginHorizontal = 4 })
    -- 排序
    filterSortRow:AddChild(UI.Label { text = "序", fontSize = 11, color = INK_GRAY })
    for _, so in ipairs(SORT_OPTIONS) do
        local isActive = market_.sortBy == so.id
        filterSortRow:AddChild(UI.Button {
            text = so.label, fontSize = 11,
            paddingHorizontal = 6, paddingVertical = 3,
            backgroundColor = isActive and TAB_ACTIVE or CARD_BG,
            color = isActive and JADE_GREEN or INK_GRAY,
            borderWidth = isActive and 1 or 0,
            borderColor = JADE_GREEN,
            borderRadius = 2,
            onClick = function()
                market_.sortBy = so.id
                market_.page = 1
                market_.dataReceived = false
                DoFetchListings(1)
                Client.SwitchPanel(PANEL.MARKET)
            end,
        })
    end
    container:AddChild(filterSortRow)

    -- ═══ "我的"Tab 显示商号等级 ═══
    if market_.filterType == "mine" then
        container:AddChild(BuildTraderRankCard())
    end

    -- ═══ 账簿（交易记录） ═══
    if market_.history == "loading" then
        container:AddChild(UI.Panel {
            width = "100%", alignItems = "center", paddingVertical = 25,
            children = { UI.Label { text = "翻阅账簿中...", fontSize = 15, color = INK_GRAY } },
        })
        return container
    end
    if type(market_.history) == "table" then
        if #market_.history == 0 then
            container:AddChild(UI.Panel {
                width = "100%", alignItems = "center", paddingVertical = 25,
                children = {
                    UI.Label { text = "～ 账簿空白 ～", fontSize = 16, color = INK_GRAY },
                    UI.Label { text = "尚无交易往来", fontSize = 13, color = TC.textSecondary, marginTop = 4 },
                },
            })
        else
            local scroll = UI.ScrollView { width = "100%", flexGrow = 1, minHeight = 0 }
            local listPanel = UI.Panel { width = "100%", flexDirection = "column", gap = 5, flexShrink = 0, padding = 2 }
            for _, rec in ipairs(market_.history) do
                local isBuy = rec.record_type == "buy"
                local card = UI.Panel {
                    width = "100%",
                    backgroundColor = PARCHMENT,
                    padding = { 7, 10 },
                    borderLeftWidth = 3,
                    borderColor = isBuy and JADE_GREEN or GOLD_TEXT,
                    borderRadius = 2,
                }
                local topRow = UI.Panel { flexDirection = "row", justifyContent = "space-between", alignItems = "center" }
                local typeLabel = isBuy and "购入" or "售出"
                local typeColor = isBuy and JADE_GREEN or GOLD_TEXT
                topRow:AddChild(UI.Label {
                    text = "【" .. typeLabel .. "】" .. (rec.item_name or "未知物品"),
                    fontSize = 14, color = typeColor,
                })
                local priceStr = tostring(rec.price) .. " 💎"
                topRow:AddChild(UI.Label { text = priceStr, fontSize = 14, color = GOLD_TEXT })
                card:AddChild(topRow)

                local infoRow = UI.Panel { flexDirection = "row", justifyContent = "space-between", marginTop = 3 }
                local counterLabel = isBuy and ("卖方：" .. (rec.counterpart_name or "匿名"))
                                             or ("买方：" .. (rec.counterpart_name or "匿名"))
                infoRow:AddChild(UI.Label { text = counterLabel, fontSize = 12, color = INK_GRAY })
                local t = rec.time or 0
                local timeStr = t > 0 and os.date("%m/%d %H:%M", t + 8 * 3600) or "——"
                infoRow:AddChild(UI.Label { text = timeStr, fontSize = 12, color = TC.textMuted })
                card:AddChild(infoRow)
                listPanel:AddChild(card)
            end
            scroll:AddChild(listPanel)
            container:AddChild(scroll)
        end
        return container
    end

    -- ═══ 在售列表（竹简商品卡） ═══
    if #market_.listings == 0 then
        local emptyText = market_.filterType == "mine"
            and "～ 尚未寄售任何货品 ～"
            or "～ 暂无在售货品 ～"
        container:AddChild(UI.Panel {
            width = "100%", alignItems = "center", paddingVertical = 40,
            children = {
                UI.Label { text = "◇", fontSize = 20, color = GOLD_DIM, marginBottom = 6 },
                UI.Label { text = emptyText, fontSize = 15, color = INK_GRAY },
            },
        })
        return container
    end

    local scroll = UI.ScrollView { width = "100%", flexGrow = 1, minHeight = 0 }
    local listPanel = UI.Panel { width = "100%", flexDirection = "column", gap = 8, flexShrink = 0, padding = 3 }

    for _, listing in ipairs(market_.listings) do
        local itemQuality = listing.item and listing.item.quality or 1
        local qColor = AncientQualityColor(itemQuality)
        local card = UI.Panel {
            width = "100%",
            backgroundColor = CARD_BG,
            padding = { 10, 12 },
            borderWidth = 1, borderColor = BRUSH_BROWN,
            borderLeftWidth = 3, borderLeftColor = qColor,
            borderRadius = 4,
        }

        local listingPriceStr = tostring(listing.price) .. " 💎"

        -- 第一行：品名 + 价格
        local topRow = UI.Panel { flexDirection = "row", justifyContent = "space-between", alignItems = "center" }
        topRow:AddChild(UI.Label {
            text = AncientQualityName(itemQuality) .. (listing.item_name or "未知"),
            fontSize = 15, color = qColor, flexShrink = 1,
        })
        topRow:AddChild(UI.Label {
            text = listingPriceStr,
            fontSize = 16, color = GOLD_TEXT,
        })
        card:AddChild(topRow)

        -- 第二行：卖家 + 操作按钮
        local infoRow = UI.Panel { flexDirection = "row", justifyContent = "space-between", alignItems = "center", marginTop = 6 }
        infoRow:AddChild(UI.Label {
            text = "寄售：" .. (listing.seller_name or "匿名"),
            fontSize = 12, color = INK_GRAY,
        })

        local isMyListing = player_ and listing.seller_uid == player_.uid
        if isMyListing then
            infoRow:AddChild(UI.Button {
                text = "撤回", fontSize = 13,
                paddingHorizontal = 14, paddingVertical = 5,
                backgroundColor = TC.btnPrimary,
                color = RED_SEAL,
                borderWidth = 1, borderColor = RED_SEAL,
                borderRadius = 3,
                onClick = function()
                    SendToServer(EV.REQ_MARKET_CANCEL, { ListingId = tostring(listing.listing_id) })
                    AddLog(">> 撤回 " .. (listing.item_name or "货品") .. "...", "warn")
                end,
            })
        else
            infoRow:AddChild(UI.Button {
                text = "购入",
                fontSize = 13,
                paddingHorizontal = 14, paddingVertical = 5,
                backgroundColor = TC.bgPanel,
                color = JADE_GREEN,
                borderWidth = 1, borderColor = JADE_GREEN,
                borderRadius = 3,
                onClick = function()
                    AddLog(">> 购入 " .. (listing.item_name or "货品") .. "，报价 " .. listingPriceStr .. "...", "gold")
                    market_.pendingBuyId = listing.listing_id
                    print("[Market] 购买请求发出 pendingBuyId=" .. tostring(listing.listing_id))
                    SendToServer(EV.REQ_MARKET_BUY, {
                        ListingId = tostring(listing.listing_id),
                        Price     = listing.price,
                    })
                end,
            })
        end
        card:AddChild(infoRow)
        listPanel:AddChild(card)
    end
    scroll:AddChild(listPanel)
    container:AddChild(scroll)

    -- ═══ 翻页（精致古风） ═══
    local pageRow = UI.Panel {
        flexDirection = "row", justifyContent = "center",
        gap = 16, marginTop = 10, alignItems = "center",
        paddingVertical = 4,
    }
    if market_.page > 1 then
        pageRow:AddChild(UI.Button {
            text = "◂ 前页", fontSize = 14,
            paddingHorizontal = 16, paddingVertical = 6,
            backgroundColor = CARD_BG, color = INK_TEXT,
            borderWidth = 1, borderColor = BRUSH_BROWN, borderRadius = 3,
            onClick = function()
                market_.dataReceived = false
                DoFetchListings(market_.page - 1)
            end,
        })
    end
    pageRow:AddChild(UI.Label {
        text = "第 " .. market_.page .. " 页",
        fontSize = 14, color = GOLD_DIM,
    })
    pageRow:AddChild(UI.Button {
        text = "后页 ▸", fontSize = 14,
        paddingHorizontal = 16, paddingVertical = 6,
        backgroundColor = CARD_BG, color = INK_TEXT,
        borderWidth = 1, borderColor = BRUSH_BROWN, borderRadius = 3,
        onClick = function()
            market_.dataReceived = false
            DoFetchListings(market_.page + 1)
        end,
    })
    container:AddChild(pageRow)

    return container
end
-- 构建管理员上架面板
local function BuildAdminSellPanel()
    -- 物品类型选项
    local TYPE_OPTIONS = {
        { id = "skill_book",  label = "功法书" },
        { id = "equipment",   label = "装备"   },
        { id = "medicine",    label = "药品"   },
        { id = "other",       label = "其他"   },
    }
    -- 品质选项
    local QUALITY_OPTIONS = {
        { id = "common",    label = "普通" },
        { id = "uncommon",  label = "优秀" },
        { id = "rare",      label = "精良" },
        { id = "epic",      label = "史诗" },
        { id = "legendary", label = "传说" },
        { id = "divine",    label = "神器" },
    }

    local selectedType    = "skill_book"
    local selectedQuality = "common"
    local selectedSkillId = ""   -- 当前选中的功法 ID
    local typeBtns    = {}
    local qualityBtns = {}

    local container = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexDirection = "column",
        padding = 10,
        gap = 7,
    }
    container:AddChild(UI.Label {
        text = "── 管理员上架 ──",
        fontSize = 17,
        color = LOG_COLOR.danger,
        marginBottom = 4,
        alignSelf = "center",
        flexShrink = 0,
    })

    -- ── 物品类型按钮组 ────────────────────────────────────────────────────────
    container:AddChild(UI.Label { text = "物品类型", fontSize = 14, color = LOG_COLOR.warn, flexShrink = 0 })
    local typeRow = UI.Panel { flexDirection = "row", gap = 5, flexShrink = 0, flexWrap = "wrap" }

    local function UpdateTypeBtns()
        for _, b in ipairs(typeBtns) do
            b.backgroundColor = (b._typeId == selectedType)
                and { 80, 50, 20, 255 } or { 20, 40, 22, 200 }
        end
    end

    for _, opt in ipairs(TYPE_OPTIONS) do
        local btn = UI.Button {
            text = opt.label,
            height = 28, paddingHorizontal = 10, fontSize = 14,
            backgroundColor = TC.bgPanel,
        }
        btn._typeId = opt.id
        btn.onClick = function()
            selectedType = opt.id
            UpdateTypeBtns()
        end
        typeBtns[#typeBtns + 1] = btn
        typeRow:AddChild(btn)
    end
    UpdateTypeBtns()
    container:AddChild(typeRow)

    -- ── 品质按钮组 ────────────────────────────────────────────────────────────
    container:AddChild(UI.Label { text = "品质", fontSize = 14, color = LOG_COLOR.warn, flexShrink = 0 })
    local qualityRow = UI.Panel { flexDirection = "row", gap = 5, flexShrink = 0, flexWrap = "wrap" }
    local QUALITY_COLORS = {
        common    = { 20, 40, 22, 200 },
        uncommon  = { 20, 70, 30, 200 },
        rare      = { 20, 50, 100, 200 },
        epic      = { 60, 20, 90, 200 },
        legendary = { 90, 55, 10, 200 },
        divine    = { 90, 20, 20, 200 },
    }
    local QUALITY_COLORS_SEL = {
        common    = { 60, 80, 160, 255 },
        uncommon  = { 30, 130, 50, 255 },
        rare      = { 30, 90, 200, 255 },
        epic      = { 110, 40, 180, 255 },
        legendary = { 200, 120, 20, 255 },
        divine    = { 200, 40, 40, 255 },
    }

    local function UpdateQualityBtns()
        for _, b in ipairs(qualityBtns) do
            b.backgroundColor = (b._qualId == selectedQuality)
                and QUALITY_COLORS_SEL[b._qualId]
                or  QUALITY_COLORS[b._qualId]
        end
    end

    for _, opt in ipairs(QUALITY_OPTIONS) do
        local btn = UI.Button {
            text = opt.label,
            height = 28, paddingHorizontal = 10, fontSize = 14,
            backgroundColor = QUALITY_COLORS[opt.id],
        }
        btn._qualId = opt.id
        btn.onClick = function()
            selectedQuality = opt.id
            UpdateQualityBtns()
        end
        qualityBtns[#qualityBtns + 1] = btn
        qualityRow:AddChild(btn)
    end
    UpdateQualityBtns()
    container:AddChild(qualityRow)

    -- ── 功法联想搜索 ──────────────────────────────────────────────────────────
    container:AddChild(UI.Label { text = "功法（可留空）", fontSize = 14, color = LOG_COLOR.warn, flexShrink = 0 })

    -- 构建功法数据：{ id, name, grade }
    local skillList = {}
    for _, sk in ipairs(Settings.SKILLS) do
        skillList[#skillList + 1] = { id = sk.id, name = sk.name, grade = sk.grade or 1 }
    end

    -- 联想结果面板（懒加载）
    local skillResultPanel = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 2,
        flexShrink = 0,
    }

    local skillSearchInput = UI.TextField {
        width = "100%", height = 32, fontSize = 15,
        placeholder = "搜索功法名...",
        flexShrink = 0,
    }

    -- 选中功法标签
    local skillSelLabel = UI.Label {
        text = "（未选择）",
        fontSize = 14,
        color = TC.info,
        flexShrink = 0,
        marginBottom = 2,
    }

    local function RebuildSkillResults(keyword)
        skillResultPanel:ClearChildren()
        if keyword == "" then return end
        local kl = keyword:lower()
        local count = 0
        for _, sk in ipairs(skillList) do
            if count >= 6 then break end
            local nameL = sk.name:lower()
            local idL   = sk.id:lower()
            if nameL:find(kl, 1, true) or idL:find(kl, 1, true) then
                count = count + 1
                local skRef = sk
                local resultBtn = UI.Button {
                    text = sk.name .. "  [" .. sk.id .. "]",
                    width = "100%",
                    height = 26, fontSize = 13,
                    textAlign = "left",
                    backgroundColor = TC.bgPanel,
                    onClick = function()
                        selectedSkillId = skRef.id
                        skillSelLabel.text = "已选：" .. skRef.name .. " (" .. skRef.id .. ")"
                        skillSelLabel.color = TC.success
                        skillSearchInput.value = ""
                        skillResultPanel:ClearChildren()
                    end,
                }
                skillResultPanel:AddChild(resultBtn)
            end
        end
    end

    skillSearchInput.onValueChange = function(self, val)
        RebuildSkillResults(val or "")
    end

    container:AddChild(skillSearchInput)
    container:AddChild(skillSelLabel)
    container:AddChild(skillResultPanel)

    -- 清除选中功法按钮
    container:AddChild(UI.Button {
        text = "清除功法选择",
        height = 24, fontSize = 13,
        backgroundColor = TC.btnPrimary,
        color = TC.danger,
        alignSelf = "flex-start",
        onClick = function()
            selectedSkillId = ""
            skillSelLabel.text = "（未选择）"
            skillSelLabel.color = TC.info
        end,
    })

    -- ── 物品名（可自动填充） ──────────────────────────────────────────────────
    container:AddChild(UI.Label { text = "物品名称", fontSize = 14, color = LOG_COLOR.warn, flexShrink = 0 })
    local nameInput = UI.TextField {
        width = "100%", height = 32, fontSize = 15,
        placeholder = "留空则按功法/类型自动命名",
        flexShrink = 0,
    }
    container:AddChild(nameInput)

    -- ── 价格 & 数量 ───────────────────────────────────────────────────────────
    local priceCountRow = UI.Panel { flexDirection = "row", gap = 8, flexShrink = 0 }
    local priceInput = UI.TextField {
        flexGrow = 1, height = 32, fontSize = 15, placeholder = "定价（银两）",
    }
    local countInput = UI.TextField {
        width = 80, height = 32, fontSize = 15, placeholder = "数量",
    }
    priceCountRow:AddChild(priceInput)
    priceCountRow:AddChild(countInput)
    container:AddChild(priceCountRow)

    -- ── 确认 & 返回 ───────────────────────────────────────────────────────────
    container:AddChild(UI.Button {
        text = "确认上架",
        width = "80%",
        alignSelf = "center",
        marginTop = 4,
        onClick = function()
            local price = tonumber(priceInput.value)
            if not price or price <= 0 then AddLog("价格无效！", "danger") return end
            local count = math.max(1, math.floor(tonumber(countInput.value) or 1))

            -- 自动生成物品名
            local itemName = nameInput.value ~= "" and nameInput.value or nil
            if not itemName then
                if selectedSkillId ~= "" then
                    -- 从功法列表查名字
                    for _, sk in ipairs(skillList) do
                        if sk.id == selectedSkillId then
                            itemName = sk.name
                            break
                        end
                    end
                end
                itemName = itemName or "神秘货品"
            end

            local itemData = {
                name      = itemName,
                item_type = selectedType,
                quality   = selectedQuality,
                skill_id  = selectedSkillId ~= "" and selectedSkillId or nil,
                bound     = false,
            }
            for i = 1, count do
                SendToServer(EV.REQ_ADMIN_SELL, {
                    Item  = cjson.encode(itemData),
                    Price = price,
                })
            end
            AddLog(string.format(">> 管理员上架 %d 件 [%s]，定价 %s",
                count, itemData.name, FormatSilver(price)), "danger")
        end,
    })

    container:AddChild(UI.Button {
        text = "← 返回",
        width = "80%",
        alignSelf = "center",
        marginTop = 4,
        onClick = function() Client.SwitchPanel(PANEL.ADMIN) end,
    })

    return container
end

-- 构建管理员面板（三 tab：传闻修改 / 玩家查询 / 加货币）
local function BuildAdminPanel()
    local container = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexDirection = "column",
        padding = 8,
        gap = 6,
    }

    -- 标题行 + 上架按钮
    local titleRow = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        flexShrink = 0,
        marginBottom = 4,
    }
    titleRow:AddChild(UI.Label {
        text = "── 管理员后台 ──",
        fontSize = 17,
        color = LOG_COLOR.danger,
    })
    titleRow:AddChild(UI.Button {
        text = "上架商品",
        height = 28,
        paddingHorizontal = 10,
        fontSize = 15,
        onClick = function() Client.SwitchPanel(PANEL.ADMIN_SELL) end,
    })
    container:AddChild(titleRow)

    -- ── tab 切换区 ──────────────────────────────────
    local TAB_NEWS    = 1
    local TAB_PLAYER  = 2
    local TAB_ACTIVITY = 3
    local currentTab  = adminPanelCurrentTab_

    local tabBody = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexDirection = "column",
        overflow = "scroll",
    }

    -- Tab 按钮行
    local tabRow = UI.Panel {
        flexDirection = "row",
        gap = 4,
        flexShrink = 0,
        marginBottom = 6,
    }
    local tabBtns = {}
    local tabLabels = { "传闻修改", "玩家查询", "活动管理" }

    local function RebuildTabBody()
        tabBody:ClearChildren()

        if currentTab == TAB_NEWS then
            -- ── 传闻修改 ──────────────────────────────────────
            local hint = UI.Label {
                text = "修改全服传闻（持久化，重启后保留）：",
                fontSize = 15,
                color = LOG_COLOR.info,
                marginBottom = 4,
                flexShrink = 0,
            }
            tabBody:AddChild(hint)

            local input = UI.TextField {
                width = "100%",
                height = 36,
                fontSize = 16,
                placeholder = "输入新传闻内容...",
                flexShrink = 0,
            }
            tabBody:AddChild(input)

            local confirmBtn = UI.Button {
                text = "发布传闻",
                width = "60%",
                alignSelf = "center",
                marginTop = 8,
                onClick = function()
                    local text = input.value or ""
                    text = text:match("^%s*(.-)%s*$") -- trim
                    if text == "" then
                        AddLog("传闻内容不能为空", "danger")
                        return
                    end
                    SendToServer(EV.REQ_ADMIN_SET_NEWS, { Text = text })
                    AddLog(">> 正在发布传闻...", "warn")
                end,
            }
            tabBody:AddChild(confirmBtn)

        elseif currentTab == TAB_PLAYER then
            -- ── 玩家查询（双子Tab：在线 / 全部） ──────────────

            -- 如果有详情目标，显示详情/编辑面板
            if adminDetailTarget_ and adminPlayerInfo_ then
                if adminPlayerInfo_.error then
                    if adminDetailTarget_.pending then
                        AddLog("查询失败：" .. (adminPlayerInfo_.error or ""), "danger")
                        adminDetailTarget_ = nil
                    end
                else
                    for k, v in pairs(adminPlayerInfo_) do
                        adminDetailTarget_[k] = v
                    end
                    adminDetailTarget_.pending = nil
                end
                adminPlayerInfo_ = nil  -- 消费掉，避免重复合并
            end
            if adminDetailTarget_ then
                -- 返回按钮
                tabBody:AddChild(UI.Button {
                    text = "← 返回列表", fontSize = 13,
                    height = 26, paddingHorizontal = 10,
                    backgroundColor = TC.bgPanel,
                    flexShrink = 0, marginBottom = 6,
                    onClick = function()
                        adminDetailTarget_ = nil
                        Client.SwitchPanel(PANEL.ADMIN)
                    end,
                })

                if adminDetailTarget_.pending then
                    -- 等待服务器响应
                    tabBody:AddChild(UI.Label {
                        text = "正在加载玩家数据...",
                        fontSize = 14, color = LOG_COLOR.warn,
                        alignSelf = "center", flexShrink = 0,
                    })
                else
                    local dt = adminDetailTarget_
                    local targetUid = tostring(dt.uid or "")

                    -- 标题
                    tabBody:AddChild(UI.Label {
                        text = string.format("【%s】详情%s",
                            dt.name or "?", dt.online and "（在线）" or "（离线）"),
                        fontSize = 16, color = LOG_COLOR.title,
                        flexShrink = 0, marginBottom = 6,
                    })

                    -- 辅助：获取境界名称
                    local function GetRealmName(realmIdx)
                        local stages = Settings.REALM.STAGES
                        if stages[realmIdx] then return stages[realmIdx].name end
                        return "未知"
                    end

                    -- 辅助：获取功法名称
                    local function GetSkillName(skillId)
                        for _, sk in ipairs(Settings.SKILLS) do
                            if sk.id == skillId then return sk.name end
                        end
                        return skillId
                    end

                    -- ── 境界信息 ──
                    local realmPanel = UI.Panel {
                        flexDirection = "column", gap = 4,
                        backgroundColor = TC.bgOverlay,
                        padding = 6, flexShrink = 0, marginBottom = 6,
                    }
                    realmPanel:AddChild(UI.Label {
                        text = "▸ 境界信息", fontSize = 14, color = LOG_COLOR.gold, flexShrink = 0,
                    })
                    local realmName = GetRealmName(dt.realm or 1)
                    realmPanel:AddChild(UI.Label {
                        text = string.format("  当前：%s 第%d层（经验 %d）",
                            realmName, dt.realm_layer or 1, dt.realm_exp or 0),
                        fontSize = 13, color = LOG_COLOR.info, flexShrink = 0,
                    })
                    -- 修改境界
                    local realmEditRow = UI.Panel {
                        flexDirection = "row", gap = 4, alignItems = "center", flexShrink = 0,
                    }
                    local realmInput = UI.TextField {
                        width = 40, height = 26, fontSize = 13,
                        placeholder = tostring(dt.realm or 1),
                    }
                    local layerInput = UI.TextField {
                        width = 40, height = 26, fontSize = 13,
                        placeholder = tostring(dt.realm_layer or 1),
                    }
                    realmEditRow:AddChild(UI.Label { text = "境界:", fontSize = 12, color = LOG_COLOR.warn })
                    realmEditRow:AddChild(realmInput)
                    realmEditRow:AddChild(UI.Label { text = "层:", fontSize = 12, color = LOG_COLOR.warn })
                    realmEditRow:AddChild(layerInput)
                    realmEditRow:AddChild(UI.Button {
                        text = "保存", fontSize = 11, height = 24, paddingHorizontal = 8,
                        backgroundColor = TC.bgPanel,
                        onClick = function()
                            local newRealm = tonumber(realmInput.value)
                            local newLayer = tonumber(layerInput.value)
                            if newRealm then
                                SendToServer(EV.REQ_ADMIN_MODIFY_PLAYER, {
                                    TargetUid = targetUid, Field = "realm", Value = math.floor(newRealm), Extra = "",
                                })
                            end
                            if newLayer then
                                SendToServer(EV.REQ_ADMIN_MODIFY_PLAYER, {
                                    TargetUid = targetUid, Field = "realm_layer", Value = math.floor(newLayer), Extra = "",
                                })
                            end
                            if newRealm or newLayer then
                                AddLog(">> 正在修改境界...", "warn")
                            end
                        end,
                    })
                    realmPanel:AddChild(realmEditRow)
                    tabBody:AddChild(realmPanel)

                    -- ── 货币信息 ──
                    local moneyPanel = UI.Panel {
                        flexDirection = "column", gap = 4,
                        backgroundColor = TC.bgOverlay,
                        padding = 6, flexShrink = 0, marginBottom = 6,
                    }
                    moneyPanel:AddChild(UI.Label {
                        text = "▸ 货币", fontSize = 14, color = LOG_COLOR.gold, flexShrink = 0,
                    })
                    moneyPanel:AddChild(UI.Label {
                        text = string.format("  银两: %s  |  灵石: %d  |  潜能: %d",
                            FormatSilver(dt.silver or 0), dt.spirit_stone or 0, dt.potential or 0),
                        fontSize = 13, color = LOG_COLOR.info, flexShrink = 0,
                    })
                    -- 修改货币
                    local moneyEditRow = UI.Panel {
                        flexDirection = "row", gap = 4, alignItems = "center", flexShrink = 0,
                    }
                    local silverInput = UI.TextField {
                        width = 60, height = 26, fontSize = 13,
                        placeholder = tostring(dt.silver or 0),
                    }
                    local stoneInput = UI.TextField {
                        width = 50, height = 26, fontSize = 13,
                        placeholder = tostring(dt.spirit_stone or 0),
                    }
                    moneyEditRow:AddChild(UI.Label { text = "银两:", fontSize = 12, color = LOG_COLOR.warn })
                    moneyEditRow:AddChild(silverInput)
                    moneyEditRow:AddChild(UI.Label { text = "灵石:", fontSize = 12, color = LOG_COLOR.warn })
                    moneyEditRow:AddChild(stoneInput)
                    moneyEditRow:AddChild(UI.Button {
                        text = "保存", fontSize = 11, height = 24, paddingHorizontal = 8,
                        backgroundColor = TC.bgPanel,
                        onClick = function()
                            local newSilver = tonumber(silverInput.value)
                            local newStone  = tonumber(stoneInput.value)
                            if newSilver then
                                SendToServer(EV.REQ_ADMIN_MODIFY_PLAYER, {
                                    TargetUid = targetUid, Field = "silver", Value = math.floor(newSilver), Extra = "",
                                })
                            end
                            if newStone then
                                SendToServer(EV.REQ_ADMIN_MODIFY_PLAYER, {
                                    TargetUid = targetUid, Field = "spirit_stone", Value = math.floor(newStone), Extra = "",
                                })
                            end
                            if newSilver or newStone then
                                AddLog(">> 正在修改货币...", "warn")
                            end
                        end,
                    })
                    moneyPanel:AddChild(moneyEditRow)
                    -- 修改潜能
                    local potentialEditRow = UI.Panel {
                        flexDirection = "row", gap = 4, alignItems = "center", flexShrink = 0,
                    }
                    local potentialInput = UI.TextField {
                        width = 70, height = 26, fontSize = 13,
                        placeholder = tostring(math.floor(dt.potential or 0)),
                    }
                    potentialEditRow:AddChild(UI.Label { text = "潜能:", fontSize = 12, color = LOG_COLOR.warn })
                    potentialEditRow:AddChild(potentialInput)
                    potentialEditRow:AddChild(UI.Button {
                        text = "保存", fontSize = 11, height = 24, paddingHorizontal = 8,
                        backgroundColor = TC.bgPanel,
                        onClick = function()
                            local newPotential = tonumber(potentialInput.value)
                            if newPotential then
                                SendToServer(EV.REQ_ADMIN_MODIFY_PLAYER, {
                                    TargetUid = targetUid, Field = "potential", Value = math.floor(newPotential), Extra = "",
                                })
                                AddLog(">> 正在修改潜能...", "warn")
                            end
                        end,
                    })
                    moneyPanel:AddChild(potentialEditRow)
                    tabBody:AddChild(moneyPanel)

                    -- ── 材料编辑 ──
                    local matPanel = UI.Panel {
                        flexDirection = "column", gap = 4,
                        backgroundColor = TC.bgOverlay,
                        padding = 6, flexShrink = 0, marginBottom = 6,
                    }
                    matPanel:AddChild(UI.Label {
                        text = "▸ 材料（炼器矿石）", fontSize = 14, color = LOG_COLOR.gold, flexShrink = 0,
                    })
                    -- 统计目标玩家各材料持有量
                    local targetInv = dt.inventory or {}
                    local matHave = {}
                    for _, item in ipairs(targetInv) do
                        if Settings.ALCHEMY_MATERIALS[item.id] then
                            matHave[item.id] = (matHave[item.id] or 0) + (item.count or 1)
                        end
                    end
                    -- 只显示炼器相关矿石
                    local oreList = { "ore_copper", "ore_iron", "ore_silver", "ore_mithril", "ore_darksteel", "ore_starfall", "ore_celestial" }
                    for _, matId in ipairs(oreList) do
                        local matDef = Settings.ALCHEMY_MATERIALS[matId]
                        if matDef then
                            local have = matHave[matId] or 0
                            local matRow = UI.Panel {
                                flexDirection = "row", gap = 4, alignItems = "center", flexShrink = 0,
                            }
                            matRow:AddChild(UI.Label {
                                text = string.format("  %s: %d", matDef.name, have),
                                fontSize = 12, color = have > 0 and LOG_COLOR.info or { 100, 100, 100, 200 },
                                flexShrink = 0, width = 110,
                            })
                            local matInput = UI.TextField {
                                width = 50, height = 24, fontSize = 12,
                                placeholder = tostring(have),
                            }
                            matRow:AddChild(matInput)
                            local capturedMatId = matId
                            matRow:AddChild(UI.Button {
                                text = "设", fontSize = 11, height = 24, paddingHorizontal = 6,
                                backgroundColor = TC.bgPanel,
                                onClick = function()
                                    local newVal = tonumber(matInput.value)
                                    if newVal then
                                        SendToServer(EV.REQ_ADMIN_MODIFY_PLAYER, {
                                            TargetUid = targetUid, Field = "material",
                                            Value = math.floor(newVal), Extra = capturedMatId,
                                        })
                                        AddLog(string.format(">> 设置 %s = %d", matDef.name, math.floor(newVal)), "warn")
                                    end
                                end,
                            })
                            matPanel:AddChild(matRow)
                        end
                    end
                    tabBody:AddChild(matPanel)

                    -- ── 功法列表 ──
                    local skillPanel = UI.Panel {
                        flexDirection = "column", gap = 4,
                        backgroundColor = TC.bgOverlay,
                        padding = 6, flexShrink = 0,
                    }
                    skillPanel:AddChild(UI.Label {
                        text = "▸ 功法", fontSize = 14, color = LOG_COLOR.gold, flexShrink = 0,
                    })
                    local skills = dt.skills or {}
                    if #skills == 0 then
                        skillPanel:AddChild(UI.Label {
                            text = "  （无功法）", fontSize = 13, color = TC.textSecondary, flexShrink = 0,
                        })
                    else
                        for _, sk in ipairs(skills) do
                            local skRow = UI.Panel {
                                flexDirection = "row", gap = 4, alignItems = "center", flexShrink = 0,
                            }
                            local skName = GetSkillName(sk.id)
                            skRow:AddChild(UI.Label {
                                text = string.format("  %s %d级", skName, sk.level or 1),
                                fontSize = 12, color = LOG_COLOR.info, flexShrink = 0,
                            })
                            local skLvInput = UI.TextField {
                                width = 36, height = 24, fontSize = 12,
                                placeholder = tostring(sk.level or 1),
                            }
                            skRow:AddChild(skLvInput)
                            local skId = sk.id  -- 闭包捕获
                            skRow:AddChild(UI.Button {
                                text = "改", fontSize = 11, height = 22, paddingHorizontal = 6,
                                backgroundColor = TC.bgPanel,
                                onClick = function()
                                    local newLv = tonumber(skLvInput.value)
                                    if not newLv or newLv < 1 then
                                        AddLog("等级须为正整数", "danger")
                                        return
                                    end
                                    SendToServer(EV.REQ_ADMIN_MODIFY_PLAYER, {
                                        TargetUid = targetUid, Field = "skill_level",
                                        Value = math.floor(newLv), Extra = skId,
                                    })
                                    AddLog(string.format(">> 正在修改 %s 等级为 %d...", skName, math.floor(newLv)), "warn")
                                end,
                            })
                            skillPanel:AddChild(skRow)
                        end
                    end
                    -- 添加功法区域：列出所有未拥有的功法
                    local ownedSet = {}
                    for _, sk in ipairs(skills) do ownedSet[sk.id] = true end
                    local unowned = {}
                    for _, skDef in ipairs(Settings.SKILLS) do
                        if not ownedSet[skDef.id] then
                            table.insert(unowned, skDef)
                        end
                    end
                    if #unowned > 0 then
                        skillPanel:AddChild(UI.Label {
                            text = "── 添加功法 ──", fontSize = 12,
                            color = TC.success, flexShrink = 0, marginTop = 8,
                        })
                        for _, skDef in ipairs(unowned) do
                            local addRow = UI.Panel {
                                flexDirection = "row", gap = 4, alignItems = "center", flexShrink = 0,
                            }
                            addRow:AddChild(UI.Label {
                                text = string.format("  %s (G%d)", skDef.name, skDef.grade or 1),
                                fontSize = 12, color = TC.textSecondary, flexShrink = 0,
                            })
                            local addSkillId = skDef.id
                            local addSkillName = skDef.name
                            addRow:AddChild(UI.Button {
                                text = "+添加", fontSize = 11, height = 22, paddingHorizontal = 6,
                                backgroundColor = TC.info,
                                onClick = function()
                                    SendToServer(EV.REQ_ADMIN_MODIFY_PLAYER, {
                                        TargetUid = targetUid, Field = "add_skill",
                                        Value = 1, Extra = addSkillId,
                                    })
                                    AddLog(string.format(">> 正在为玩家添加功法 %s...", addSkillName), "warn")
                                end,
                            })
                            skillPanel:AddChild(addRow)
                        end
                    end

                    tabBody:AddChild(skillPanel)

                    -- ── 测试开关 ──
                    local debugPanel = UI.Panel {
                        flexDirection = "column", gap = 4,
                        backgroundColor = TC.bgOverlay,
                        padding = 6, flexShrink = 0, marginTop = 6,
                    }
                    debugPanel:AddChild(UI.Label {
                        text = "▸ 测试开关", fontSize = 14, color = LOG_COLOR.gold, flexShrink = 0,
                    })
                    local dtFlags = dt.debug_flags or {}
                    for _, flagDef in ipairs(Settings.ADMIN_DEBUG_FLAGS) do
                        local isOn = dtFlags[flagDef.key] == true
                        local flagRow = UI.Panel {
                            flexDirection = "row", gap = 6, alignItems = "center", flexShrink = 0,
                        }
                        flagRow:AddChild(UI.Label {
                            text = string.format("  %s（%s）", flagDef.label, flagDef.desc),
                            fontSize = 12, color = isOn and TC.success or TC.textSecondary, flexShrink = 0,
                        })
                        local capturedKey = flagDef.key
                        local capturedOn = isOn
                        flagRow:AddChild(UI.Button {
                            text = isOn and "关闭" or "开启",
                            fontSize = 11, height = 22, paddingHorizontal = 8,
                            backgroundColor = isOn and TC.danger or TC.success,
                            onClick = function()
                                SendToServer(EV.REQ_ADMIN_MODIFY_PLAYER, {
                                    TargetUid = targetUid, Field = "toggle_debug_flag",
                                    Value = capturedOn and 0 or 1, Extra = capturedKey,
                                })
                                AddLog(">> 切换测试开关...", "warn")
                            end,
                        })
                        debugPanel:AddChild(flagRow)
                    end
                    tabBody:AddChild(debugPanel)
                end
                return  -- 显示详情时不渲染查询列表
            end

            -- ① 单玩家精确查询行（保留）
            local searchRow = UI.Panel {
                flexDirection = "row", gap = 6, alignItems = "center",
                flexShrink = 0, marginBottom = 6,
            }
            local nameInput = UI.TextField {
                flexGrow = 1, height = 30, fontSize = 15,
                placeholder = "精确查询单个玩家...",
            }
            searchRow:AddChild(nameInput)
            searchRow:AddChild(UI.Button {
                text = "查",
                height = 30, paddingHorizontal = 10, fontSize = 14,
                onClick = function()
                    local name = (nameInput.value or ""):match("^%s*(.-)%s*$")
                    if name == "" then AddLog("请输入玩家名", "danger") return end
                    adminPlayerInfo_ = nil
                    SendToServer(EV.REQ_ADMIN_QUERY_PLAYER, { Name = name })
                    AddLog(">> 查询玩家：" .. name, "warn")
                    Client.SwitchPanel(PANEL.ADMIN)
                end,
            })
            tabBody:AddChild(searchRow)

            -- 精确查询结果（折叠显示）
            if adminPlayerInfo_ ~= nil then
                if adminPlayerInfo_.error then
                    tabBody:AddChild(UI.Label {
                        text = "未找到：" .. (adminPlayerInfo_.error or ""),
                        fontSize = 14, color = LOG_COLOR.danger, flexShrink = 0,
                    })
                else
                    local info = adminPlayerInfo_
                    local infoPanel = UI.Panel {
                        flexDirection = "row", flexWrap = "wrap",
                        gap = 6, marginBottom = 4,
                        backgroundColor = TC.bgOverlay,
                        padding = 6, flexShrink = 0,
                    }
                    local function kv(k, v)
                        local p = UI.Panel { flexDirection = "row", gap = 4 }
                        p:AddChild(UI.Label { text = k .. ":", fontSize = 13, color = LOG_COLOR.warn, flexShrink = 0 })
                        p:AddChild(UI.Label { text = tostring(v), fontSize = 13, color = LOG_COLOR.info })
                        return p
                    end
                    infoPanel:AddChild(kv("名", info.name or "-"))
                    infoPanel:AddChild(kv("境界", Settings.REALM.GetDisplayName(info.realm or 1, info.realm_layer or 1)))
                    infoPanel:AddChild(kv("状态", info.online and "在线" or "离线"))
                    infoPanel:AddChild(kv("银", FormatSilver(info.silver or 0)))
                    infoPanel:AddChild(kv("灵石", info.spirit_stone or 0))
                    infoPanel:AddChild(kv("场景", info.scene or "-"))
                    -- 详情按钮
                    infoPanel:AddChild(UI.Button {
                        text = "详情/修改", fontSize = 12,
                        height = 22, paddingHorizontal = 8,
                        backgroundColor = TC.info,
                        onClick = function()
                            adminDetailTarget_ = info
                            Client.SwitchPanel(PANEL.ADMIN)
                        end,
                    })
                    tabBody:AddChild(infoPanel)
                end
            end

            -- ② 子Tab：在线 / 全部
            local PAGE_SIZE = 10
            -- 使用模块状态变量保持跨重建的 mode/page
            local listSubMode  = adminPlayerListMode_  -- "online" | "all"
            local listPage     = adminPlayerListPage_

            -- 子Tab按钮行
            local subTabRow = UI.Panel {
                flexDirection = "row", gap = 5,
                flexShrink = 0, marginBottom = 5,
            }
            ---@type any
            local btnOnline = nil
            ---@type any
            local btnAll    = nil

            local function DoFetchList(mode, page)
                adminPlayerList_     = nil   -- 清空旧数据，触发"加载中"
                adminPlayerListMode_ = mode
                adminPlayerListPage_ = page
                SendToServer(EV.REQ_ADMIN_LIST_PLAYERS, {
                    Mode     = mode,
                    Page     = page,
                    PageSize = PAGE_SIZE,
                })
                Client.SwitchPanel(PANEL.ADMIN)
            end

            local function UpdateSubTabBtns()
                if btnOnline then
                    btnOnline.backgroundColor = (adminPlayerListMode_ == "online")
                        and { 60, 40, 100, 255 } or { 20, 40, 22, 200 }
                end
                if btnAll then
                    btnAll.backgroundColor = (adminPlayerListMode_ == "all")
                        and { 60, 40, 100, 255 } or { 20, 40, 22, 200 }
                end
            end

            btnOnline = UI.Button {
                text = "在线玩家", height = 26, paddingHorizontal = 12, fontSize = 14,
                backgroundColor = TC.bgPanel,
                onClick = function()
                    DoFetchList("online", 1)
                end,
            }
            btnAll = UI.Button {
                text = "全部玩家", height = 26, paddingHorizontal = 12, fontSize = 14,
                backgroundColor = TC.bgPanel,
                onClick = function()
                    DoFetchList("all", 1)
                end,
            }
            subTabRow:AddChild(btnOnline)
            subTabRow:AddChild(btnAll)
            tabBody:AddChild(subTabRow)
            UpdateSubTabBtns()

            -- 列表区域
            if adminPlayerList_ == nil then
                -- 首次进入或请求中：显示提示
                tabBody:AddChild(UI.Label {
                    text = "点击「在线玩家」或「全部玩家」加载列表",
                    fontSize = 14, color = TC.textSecondary,
                    alignSelf = "center", flexShrink = 0,
                })
            elseif #adminPlayerList_ == 0 then
                tabBody:AddChild(UI.Label {
                    text = "暂无玩家数据",
                    fontSize = 14, color = TC.textSecondary,
                    alignSelf = "center", flexShrink = 0,
                })
            else
                -- 列表表头
                local headerRow = UI.Panel {
                    flexDirection = "row", gap = 4,
                    flexShrink = 0, marginBottom = 3,
                    paddingHorizontal = 4,
                }
                local function hdr(t, w)
                    return UI.Label { text = t, fontSize = 12,
                        color = LOG_COLOR.warn, width = w, flexShrink = 0 }
                end
                headerRow:AddChild(hdr("名字",    72))
                headerRow:AddChild(hdr("境界",    55))
                headerRow:AddChild(hdr("状态",    30))
                headerRow:AddChild(hdr("银两",    50))
                headerRow:AddChild(hdr("灵石",    36))
                headerRow:AddChild(hdr("操作",    90))
                tabBody:AddChild(headerRow)

                -- 列表行
                for _, p in ipairs(adminPlayerList_) do
                    local pUid = p.uid
                    local row = UI.Panel {
                        flexDirection = "row", gap = 4,
                        flexShrink = 0, marginBottom = 2,
                        paddingHorizontal = 4,
                        backgroundColor = p.online and { 20, 45, 30, 160 } or { 22, 22, 40, 140 },
                    }
                    local function cell(t, w, col)
                        return UI.Label { text = tostring(t or "-"), fontSize = 12,
                            color = col or LOG_COLOR.info, width = w, flexShrink = 0 }
                    end
                    row:AddChild(cell(p.name,         72))
                    row:AddChild(cell(Settings.REALM.GetDisplayName(p.realm or 1, p.realm_layer or 1), 55))
                    row:AddChild(cell(p.online and "在线" or "离线", 30,
                        p.online and { 80, 220, 100, 255 } or { 130, 130, 160, 200 }))
                    row:AddChild(cell(p.silver and FormatSilver(p.silver) or "?", 50))
                    row:AddChild(cell(p.spirit_stone or "?", 36))
                    -- 操作按钮组
                    local opsPanel = UI.Panel {
                        flexDirection = "row", gap = 3, width = 90, flexShrink = 0,
                    }
                    opsPanel:AddChild(UI.Button {
                        text = "详情", fontSize = 11,
                        width = 40, height = 22, flexShrink = 0,
                        backgroundColor = TC.info,
                        onClick = function()
                            -- 先设置目标，然后查询详情数据
                            adminPlayerInfo_ = nil
                            SendToServer(EV.REQ_ADMIN_QUERY_PLAYER, { Name = p.name })
                            -- 查询返回后 adminPlayerInfo_ 会被填充，利用回调打开详情
                            adminDetailTarget_ = { uid = pUid, name = p.name, pending = true }
                            Client.SwitchPanel(PANEL.ADMIN)
                        end,
                    })
                    if p.online then
                        opsPanel:AddChild(UI.Button {
                            text = "清除", fontSize = 11,
                            width = 40, height = 22, flexShrink = 0,
                            backgroundColor = TC.btnPrimary,
                            onClick = function()
                                AddLog(string.format(">> 正在清除玩家 %s 的账号...", tostring(p.name)), "warn")
                                SendToServer(EV.REQ_ADMIN_RESET_PLAYER, { TargetUid = pUid })
                                DoFetchList(adminPlayerListMode_, adminPlayerListPage_)
                            end,
                        })
                    end
                    row:AddChild(opsPanel)
                    tabBody:AddChild(row)
                end

                -- 分页控制行
                local totalPages = math.max(1, math.ceil(adminPlayerListTotal_ / PAGE_SIZE))
                local pageRow = UI.Panel {
                    flexDirection = "row", gap = 6,
                    alignItems = "center", justifyContent = "center",
                    flexShrink = 0, marginTop = 6,
                }
                pageRow:AddChild(UI.Button {
                    text = "◀", height = 26, paddingHorizontal = 10, fontSize = 14,
                    onClick = function()
                        if adminPlayerListPage_ > 1 then
                            DoFetchList(adminPlayerListMode_, adminPlayerListPage_ - 1)
                        end
                    end,
                })
                pageRow:AddChild(UI.Label {
                    text = string.format("%d / %d（共%d人）",
                        adminPlayerListPage_, totalPages, adminPlayerListTotal_),
                    fontSize = 13, color = LOG_COLOR.info,
                })
                pageRow:AddChild(UI.Button {
                    text = "▶", height = 26, paddingHorizontal = 10, fontSize = 14,
                    onClick = function()
                        if adminPlayerListPage_ < totalPages then
                            DoFetchList(adminPlayerListMode_, adminPlayerListPage_ + 1)
                        end
                    end,
                })
                tabBody:AddChild(pageRow)
            end

        elseif currentTab == TAB_ACTIVITY then
            -- ── 活动管理 ──────────────────────────────────────
            tabBody:AddChild(UI.Label {
                text = "活动与时间配置（即时生效，重启后恢复默认）",
                fontSize = 14,
                color = LOG_COLOR.info,
                marginBottom = 8,
                flexShrink = 0,
            })

            -- ── Boss/怪物刷新时间 ──
            local bossSection = UI.Panel {
                flexDirection = "column", gap = 4,
                backgroundColor = TC.bgOverlay,
                padding = 8, flexShrink = 0, marginBottom = 8,
            }
            bossSection:AddChild(UI.Label {
                text = "▸ 怪物刷新延迟（秒）",
                fontSize = 14, color = LOG_COLOR.gold, flexShrink = 0,
            })
            local respawnCurrentLabel = UI.Label {
                text = string.format("当前值: %.1f 秒", Settings.BATTLEFIELD_MAP.MONSTER_RESPAWN_DELAY or 6.0),
                fontSize = 12, color = LOG_COLOR.info, flexShrink = 0,
            }
            bossSection:AddChild(respawnCurrentLabel)
            local respawnRow = UI.Panel {
                flexDirection = "row", gap = 4, alignItems = "center", flexShrink = 0,
            }
            local respawnInput = UI.TextField {
                width = 80, height = 30, fontSize = 14,
                placeholder = "秒数",
                value = tostring(Settings.BATTLEFIELD_MAP.MONSTER_RESPAWN_DELAY or 6.0),
            }
            respawnRow:AddChild(respawnInput)
            respawnRow:AddChild(UI.Button {
                text = "修改", height = 30, paddingHorizontal = 12, fontSize = 13,
                onClick = function()
                    local val = tonumber(respawnInput.value)
                    if not val or val < 1 or val > 3600 then
                        AddLog("刷新延迟须在 1~3600 秒之间", "danger")
                        return
                    end
                    SendToServer(EV.REQ_ADMIN_SET_ACTIVITY, {
                        Action = "set_respawn_delay",
                        Value  = tostring(val),
                    })
                    respawnCurrentLabel:SetText(string.format("当前值: %.1f 秒 (已提交)", val))
                    AddLog(">> 正在修改怪物刷新延迟...", "warn")
                end,
            })
            bossSection:AddChild(respawnRow)
            tabBody:AddChild(bossSection)

            -- ── 据点战（领地战）时间 ──
            local warSection = UI.Panel {
                flexDirection = "column", gap = 4,
                backgroundColor = TC.bgOverlay,
                padding = 8, flexShrink = 0, marginBottom = 8,
            }
            warSection:AddChild(UI.Label {
                text = "▸ 领地战时间段",
                fontSize = 14, color = LOG_COLOR.gold, flexShrink = 0,
            })
            local tw = Settings.TERRITORY_WAR
            local warCurrentLabel = UI.Label {
                text = string.format("当前: %02d:%02d ~ %02d:%02d",
                    tw.START_HOUR, tw.START_MIN, tw.END_HOUR, tw.END_MIN),
                fontSize = 12, color = LOG_COLOR.info, flexShrink = 0,
            }
            warSection:AddChild(warCurrentLabel)
            -- 开始时间
            local startRow = UI.Panel {
                flexDirection = "row", gap = 4, alignItems = "center", flexShrink = 0,
            }
            startRow:AddChild(UI.Label { text = "开始:", fontSize = 13, color = TC.textPrimary, width = 40 })
            local startHourInput = UI.TextField {
                width = 50, height = 30, fontSize = 14,
                placeholder = "时",
                value = tostring(tw.START_HOUR),
            }
            startRow:AddChild(startHourInput)
            startRow:AddChild(UI.Label { text = ":", fontSize = 13, color = TC.textPrimary })
            local startMinInput = UI.TextField {
                width = 50, height = 30, fontSize = 14,
                placeholder = "分",
                value = tostring(tw.START_MIN),
            }
            startRow:AddChild(startMinInput)
            warSection:AddChild(startRow)

            -- 结束时间
            local endRow = UI.Panel {
                flexDirection = "row", gap = 4, alignItems = "center", flexShrink = 0,
            }
            endRow:AddChild(UI.Label { text = "结束:", fontSize = 13, color = TC.textPrimary, width = 40 })
            local endHourInput = UI.TextField {
                width = 50, height = 30, fontSize = 14,
                placeholder = "时",
                value = tostring(tw.END_HOUR),
            }
            endRow:AddChild(endHourInput)
            endRow:AddChild(UI.Label { text = ":", fontSize = 13, color = TC.textPrimary })
            local endMinInput = UI.TextField {
                width = 50, height = 30, fontSize = 14,
                placeholder = "分",
                value = tostring(tw.END_MIN),
            }
            endRow:AddChild(endMinInput)
            warSection:AddChild(endRow)

            warSection:AddChild(UI.Button {
                text = "修改领地战时间", height = 32, paddingHorizontal = 12, fontSize = 13,
                marginTop = 4,
                onClick = function()
                    print("[Admin] 修改领地战时间按钮被点击")
                    local shRaw = startHourInput.value
                    local smRaw = startMinInput.value
                    local ehRaw = endHourInput.value
                    local emRaw = endMinInput.value
                    print("[Admin] raw values: sh=" .. tostring(shRaw) .. " sm=" .. tostring(smRaw) .. " eh=" .. tostring(ehRaw) .. " em=" .. tostring(emRaw))
                    local sh = tonumber(shRaw)
                    local sm = tonumber(smRaw)
                    local eh = tonumber(ehRaw)
                    local em = tonumber(emRaw)
                    print("[Admin] parsed: sh=" .. tostring(sh) .. " sm=" .. tostring(sm) .. " eh=" .. tostring(eh) .. " em=" .. tostring(em))
                    if not sh or not sm or not eh or not em then
                        print("[Admin] 验证失败: 有nil值")
                        AddLog("请输入有效的时间数字", "danger")
                        return
                    end
                    if sh < 0 or sh > 23 or eh < 0 or eh > 23 or sm < 0 or sm > 59 or em < 0 or em > 59 then
                        print("[Admin] 验证失败: 范围不正确")
                        AddLog("时间范围不正确（时:0~23 分:0~59）", "danger")
                        return
                    end
                    local valStr = string.format("%d:%d-%d:%d", sh, sm, eh, em)
                    print("[Admin] 发送 set_war_time Value=" .. valStr)
                    SendToServer(EV.REQ_ADMIN_SET_ACTIVITY, {
                        Action = "set_war_time",
                        Value  = valStr,
                    })
                    warCurrentLabel:SetText(string.format("当前: %02d:%02d ~ %02d:%02d (已提交)", sh, sm, eh, em))
                    AddLog(">> 正在修改领地战时间...", "warn")
                end,
            })
            tabBody:AddChild(warSection)

            -- ── 手动开启/关闭领地战 ──
            local manualSection = UI.Panel {
                flexDirection = "row", gap = 6,
                flexShrink = 0, marginBottom = 8,
            }
            manualSection:AddChild(UI.Button {
                text = "立即开启领地战", height = 32, paddingHorizontal = 10, fontSize = 13,
                backgroundColor = TC.success,
                onClick = function()
                    print("[Admin] 点击: 立即开启领地战")
                    SendToServer(EV.REQ_ADMIN_SET_ACTIVITY, {
                        Action = "force_war_start",
                        Value  = "1",
                    })
                    AddLog(">> 正在强制开启领地战...", "warn")
                end,
            })
            manualSection:AddChild(UI.Button {
                text = "立即结束领地战", height = 32, paddingHorizontal = 10, fontSize = 13,
                backgroundColor = TC.btnPrimary,
                onClick = function()
                    print("[Admin] 点击: 立即结束领地战")
                    SendToServer(EV.REQ_ADMIN_SET_ACTIVITY, {
                        Action = "force_war_end",
                        Value  = "0",
                    })
                    AddLog(">> 正在强制结束领地战...", "warn")
                end,
            })
            tabBody:AddChild(manualSection)

        end
    end

    -- 渲染 tab 按钮
    local function UpdateTabBtns()
        for i, btn in ipairs(tabBtns) do
            btn.backgroundColor = (i == currentTab)
                and { 60, 40, 100, 255 }
                or  { 20, 40, 22, 200 }
        end
    end

    for i, label in ipairs(tabLabels) do
        local btn = UI.Button {
            text = label,
            height = 30,
            paddingHorizontal = 12,
            fontSize = 15,
            backgroundColor = TC.bgPanel,
            onClick = function()
                currentTab = i
                adminPanelCurrentTab_ = i
                UpdateTabBtns()
                RebuildTabBody()
            end,
        }
        tabBtns[i] = btn
        tabRow:AddChild(btn)
    end
    UpdateTabBtns()

    container:AddChild(tabRow)
    RebuildTabBody()
    container:AddChild(tabBody)

    return container
end

-- 构建 NPC 商店面板
local function BuildShopPanel()
    local container = UI.Panel {
        width = "100%",
        flexGrow = 1,
        padding = 8,
        gap = 5,
    }

    local titleColor = shopData_.currency == "spirit_stone"
        and LOG_COLOR.gold or LOG_COLOR.title

    container:AddChild(UI.Label {
        text = "── " .. shopData_.shopTitle .. " ──",
        fontSize = 17,
        color = titleColor,
        marginBottom = 4,
        alignSelf = "center",
    })

    -- 货币提示
    local currencyHint = shopData_.currency == "spirit_stone" and "灵石" or "银两"
    local playerBalance = 0
    if player_ then
        playerBalance = shopData_.currency == "spirit_stone"
            and (player_.spirit_stone or 0)
            or (player_.silver or 0)
    end
    container:AddChild(UI.Label {
        text = string.format("持有%s：%s", currencyHint,
            shopData_.currency == "spirit_stone"
                and tostring(playerBalance) .. "灵石"
                or FormatSilver(playerBalance)),
        fontSize = 19,
        color = LOG_COLOR.gold,
        marginBottom = 8,
        alignSelf = "center",
    })

    -- 商品列表（可滚动）
    local scrollList = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
    }

    if #shopData_.items == 0 then
        scrollList:AddChild(UI.Label {
            text = "（暂无商品）",
            fontSize = 19,
            color = TC.textMuted,
            alignSelf = "center",
        })
    else
        for _, shopItem in ipairs(shopData_.items) do
            local priceStr = shopData_.currency == "spirit_stone"
                and (shopItem.price .. "灵石")
                or FormatSilver(shopItem.price)

            local card = UI.Panel {
                width = "100%",
                backgroundColor = TC.bgPanel,
                padding = { 5, 8 },
                marginBottom = 4,
            }

            local topRow = UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
            }
            topRow:AddChild(UI.Label {
                text = shopItem.name,
                fontSize = 16,
                color = LOG_COLOR.info,
            })
            topRow:AddChild(UI.Label {
                text = priceStr,
                fontSize = 16,
                color = LOG_COLOR.gold,
            })
            card:AddChild(topRow)

            -- 描述
            if shopItem.desc then
                card:AddChild(UI.Label {
                    text = shopItem.desc,
                    fontSize = 16,
                    color = TC.success,
                    marginTop = 2,
                })
            end

            -- 属性/效果
            local statText = ""
            if shopItem.stats then
                local STAT_NAMES = { atk = "攻击", def = "防御", agi = "身法", wis = "灵力", hp = "气血", mp = "内力" }
                for k, v in pairs(shopItem.stats) do
                    statText = statText .. (STAT_NAMES[k] or k) .. "+" .. v .. " "
                end
            elseif shopItem.effect then
                for k, v in pairs(shopItem.effect) do
                    local label = k == "hp" and "气血" or (k == "mp" and "内力" or k)
                    statText = statText .. "恢复" .. label .. "+" .. v .. " "
                end
            end
            if statText ~= "" then
                card:AddChild(UI.Label {
                    text = statText,
                    fontSize = 16,
                    color = TC.info,
                })
            end

            -- 购买按钮行
            local btnRow = UI.Panel {
                flexDirection = "row",
                justifyContent = "flex-end",
                marginTop = 4,
            }
            local buyBtn = UI.Button {
                text = "购买 " .. priceStr,
                fontSize = 16,
                onClick = function()
                    SendToServer(EV.REQ_SHOP_BUY, {
                        ShopType = shopData_.shopType,
                        ItemId   = shopItem.id,
                    })
                    AddLog(">> 购买 " .. shopItem.name .. "...", "gold")
                end,
            }
            btnRow:AddChild(buyBtn)
            card:AddChild(btnRow)

            scrollList:AddChild(card)
        end
    end

    container:AddChild(scrollList)

    -- 关闭按钮（固定在底部，不随列表滚动）
    container:AddChild(UI.Button {
        text = "← 离开商店",
        width = "80%",
        alignSelf = "center",
        marginTop = 8,
        onClick = function()
            Client.SwitchPanel(PANEL.MAIN)
        end,
    })

    return container
end

-- ========== 修为丹药铺面板 ==========
local realmPillShopData_ = nil  -- { pills = {...}, dailyUsed = 0, dailyLimit = 5 }

local function BuildRealmPillShopPanel()
    local data = realmPillShopData_
    if not data then return UI.Panel { width = "100%" } end

    local container = UI.Panel {
        width = "100%",
        flexGrow = 1,
        padding = 10,
        gap = 6,
    }

    -- 标题
    container:AddChild(UI.Label {
        text = "💊 药铺 · 修为丹",
        fontSize = 18,
        fontWeight = "bold",
        color = {220, 200, 100, 255},
        alignSelf = "center",
    })

    -- 每日服用次数提示
    local usedText = string.format("今日已服用: %d/%d", data.dailyUsed or 0, data.dailyLimit or 5)
    local usedColor = (data.dailyUsed or 0) >= (data.dailyLimit or 5) and LOG_COLOR.danger or LOG_COLOR.system
    container:AddChild(UI.Label {
        text = usedText,
        fontSize = 13,
        color = usedColor,
        alignSelf = "center",
        marginBottom = 4,
    })

    -- 当前境界信息
    local myRealm = player_ and player_.realm or 1
    local myRealmName = Settings.REALM.STAGES[myRealm] and Settings.REALM.STAGES[myRealm].name or "练气"
    container:AddChild(UI.Label {
        text = "当前境界: " .. myRealmName .. "（仅可服用对应境界丹药）",
        fontSize = 12,
        color = {180, 180, 180, 255},
        alignSelf = "center",
        marginBottom = 6,
    })

    -- 丹药列表
    local pills = data.pills or {}
    for i, pill in ipairs(pills) do
        local isMyRealm = (pill.realm_index == myRealm)
        local nameColor = isMyRealm and {255, 255, 200, 255} or {140, 140, 140, 255}
        local realmTag = pill.realm_name or ""

        local row = UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            padding = 6,
            gap = 6,
            backgroundColor = isMyRealm and {60, 50, 30, 200} or {40, 40, 50, 150},
            borderRadius = 4,
        }

        -- 丹药名称+境界
        local infoCol = UI.Panel {
            flexGrow = 1,
            flexShrink = 1,
            gap = 2,
        }
        infoCol:AddChild(UI.Label {
            text = pill.name .. "  [" .. realmTag .. "]",
            fontSize = 14,
            color = nameColor,
        })
        infoCol:AddChild(UI.Label {
            text = string.format("修为+%d | 💰%d灵石", pill.exp or 0, pill.cost or 0),
            fontSize = 11,
            color = {160, 160, 160, 255},
        })
        row:AddChild(infoCol)

        -- 购买按钮
        local buyBtn = UI.Button {
            text = "购买",
            fontSize = 12,
            paddingHorizontal = 8,
            paddingVertical = 4,
            onClick = function()
                local vm = VariantMap()
                vm:SetInt("PillIndex", i)
                serverConn_:SendRemoteEvent(EV.REQ_BUY_REALM_PILL, true, vm)
            end,
        }
        row:AddChild(buyBtn)

        -- 服用按钮（仅当前境界可用）
        if isMyRealm then
            local canUse = (data.dailyUsed or 0) < (data.dailyLimit or 5)
            local useBtn = UI.Button {
                text = "服用",
                fontSize = 12,
                paddingHorizontal = 8,
                paddingVertical = 4,
                variant = canUse and "primary" or "ghost",
                disabled = not canUse,
                onClick = function()
                    local vm = VariantMap()
                    vm:SetInt("PillIndex", i)
                    serverConn_:SendRemoteEvent(EV.REQ_USE_REALM_PILL, true, vm)
                end,
            }
            row:AddChild(useBtn)
        end

        container:AddChild(row)
    end

    -- 关闭按钮
    container:AddChild(UI.Button {
        text = "← 离开药铺",
        width = "80%",
        alignSelf = "center",
        marginTop = 8,
        onClick = function()
            Client.SwitchPanel(PANEL.MAIN)
        end,
    })

    return container
end

-- 构建管理员登录面板（首次进入）
local function BuildAdminLoginPanel()
    local container = UI.Panel {
        width = "100%",
        flexGrow = 1,
        padding = 12,
        justifyContent = "center",
        alignItems = "center",
        gap = 10,
    }
    container:AddChild(UI.Label {
        text = "管理员验证",
        fontSize = 19,
        color = LOG_COLOR.danger,
    })
    local codeInput = UI.TextField {
        placeholder = "输入激活码",
        width = "80%",
        height = 36,
        fontSize = 17,
    }
    container:AddChild(codeInput)
    container:AddChild(UI.Button {
        text = "验证",
        width = "50%",
        onClick = function()
            local code = codeInput.value
            if code and code ~= "" then
                SendToServer(EV.REQ_ADMIN_LOGIN, { Code = code })
                AddLog(">> 正在验证管理员身份...", "warn")
            end
        end,
    })
    container:AddChild(UI.Button {
        text = "取消",
        width = "50%",
        onClick = function() Client.SwitchPanel(PANEL.MAIN) end,
    })
    return container
end

-- ============================================================================
-- 面板切换
-- ============================================================================

-- 全屏面板构建函数表
local FULL_PANEL_BUILDERS = nil  -- 延迟初始化（函数在后面定义）

local function EnsureFullPanelBuilders()
    if FULL_PANEL_BUILDERS then return end
    FULL_PANEL_BUILDERS = {
        [PANEL.MAP]        = BuildMapPanel,
        [PANEL.INVENTORY]  = BuildInventoryPanel,
        [PANEL.MARKET]     = BuildMarketPanel,
        [PANEL.SHOP]       = BuildShopPanel,
        [PANEL.ADMIN]      = BuildAdminPanel,
        [PANEL.ADMIN_SELL] = BuildAdminSellPanel,
        ["admin_login"]    = BuildAdminLoginPanel,
        [PANEL.REALM_PILL] = BuildRealmPillShopPanel,
    }
end

function Client.SwitchPanel(panelName)
    currentPanel_ = panelName
    viewingBattlefieldLayers_ = false  -- 切换面板时重置战场层浏览标记
    if not ui_.mainArea then return end

    -- 离开聊天独占模式时恢复隐藏的 UI 元素
    if panelName ~= PANEL.CHAT then
        ExitChatExclusiveMode()
    end

    EnsureFullPanelBuilders()

    -- ── 战斗中：直接走 RebuildMainContent（嵌入式战斗视图）──
    if panelName == PANEL.BATTLE and inBattle_ then
        RebuildMainContent()
        return
    end

    -- ── 全屏面板（背包/地图/交易/商店/管理）─────────────
    if FULL_PANEL_BUILDERS[panelName] then
        ui_.mainArea:ClearChildren()
        ui_.bottomSection = nil
        -- 返回主页按钮
        local backBtn = UI.Button {
            text = "← 返回主页",
            height = 32,
            paddingHorizontal = 14,
            fontSize = 16,
            fontWeight = "bold",
            borderRadius = 16,
            backgroundColor = TC.bgPanelLight,
            borderWidth = 1,
            borderColor = TC.borderLight,
            color = TC.textPrimary,
            marginBottom = 4,
            marginHorizontal = 6,
            marginTop = 4,
            flexShrink = 0,
            onClick = function()
                currentPanel_ = PANEL.MAIN
                RebuildMainContent()
                BuildSceneNav()
            end,
        }
        local content = FULL_PANEL_BUILDERS[panelName]()
        ui_.mainArea:AddChild(backBtn)
        if content then ui_.mainArea:AddChild(content) end
        return
    end

    -- ── 聊天独占模式（全屏聊天，隐藏场景/NPC/地图）──
    if panelName == PANEL.CHAT then
        local defaultSub = currentSubTab_[PANEL.CHAT]
        BuildChatExclusiveMode(defaultSub)
        return
    end

    -- ── 子面板模式（主页/角色/修炼/战斗子面板/江湖/设置）──
    -- 若 mainArea 没有 bottomSection（如从全屏返回），先重建内容
    if not ui_.bottomSection then
        RebuildMainContent()
    end

    if panelName == PANEL.MAIN then
        BuildSceneNav()
        -- 确保切回主面板时日志滚到底部
        logScrollPending_ = 10
    elseif NAV_PANELS and NAV_PANELS[panelName] then
        BuildNavSubPanel(panelName)
    end
end

-- ============================================================================
-- 状态栏更新
-- ============================================================================

local function UpdateStatusBar()
    if not player_ then return end

    -- 服务端序列化字段为 hp_base / mp_base（InitPlayer），或 stats.hp / stats.mp（PushPlayerData）
    local pStats = player_.stats
    local hp    = player_.hp or player_.hp_base or (pStats and pStats.hp) or 0
    local maxHp = math.max(player_.max_hp or player_.hp_base or (pStats and pStats.hp) or 1, 1)
    local mp    = player_.mp or player_.mp_base or (pStats and pStats.mp) or 0
    local maxMp = math.max(player_.max_mp or player_.mp_base or (pStats and pStats.mp) or 1, 1)
    local hpPct = hp / maxHp
    local mpPct = mp / maxMp

    -- 境界+名字合并标签（格式：练气九层·樊华清）
    if ui_.statusLabel then
        local name = player_.name or "未知"
        local rName = player_.realm_name or Settings.REALM.GetDisplayName(player_.realm or 1, player_.realm_layer or 1)
        ui_.statusLabel.text = string.format("%s·%s", rName, name)
    end

    -- 大境界进度百分比
    if ui_.realmPctLabel then
        local realm = player_.realm or 1
        local layer = player_.realm_layer or 1
        local curExp = player_.realm_exp or 0
        local stage = Settings.REALM.STAGES[realm]
        if stage then
            -- 已完成层的累计经验
            local doneExp = 0
            for i = 1, layer - 1 do
                doneExp = doneExp + stage.exp_base * i
            end
            -- 总经验
            local totalExp = Settings.REALM.GetTotalExp(realm)
            local pct = 0
            if totalExp > 0 then
                pct = (doneExp + curExp) / totalExp * 100
                if pct > 100 then pct = 100 end
            end
            ui_.realmPctLabel.text = string.format("%.1f%%", pct)
        end
    end

    -- 气血条
    if ui_.hpBar then
        ui_.hpBar.width = string.format("%d%%", math.floor(hpPct * 100))
    end
    if ui_.hpLabel then
        ui_.hpLabel.text = string.format("气血 %d/%d", hp, maxHp)
    end

    -- 内力条
    if ui_.mpBar then
        ui_.mpBar.width = string.format("%d%%", math.floor(mpPct * 100))
    end
    if ui_.mpLabel then
        ui_.mpLabel.text = string.format("内力 %d/%d", mp, maxMp)
    end


    -- 场景标题栏
    if ui_.sceneTitle then
        local sceneId = player_.scene or "ancient_village"
        ui_.sceneTitle.text = "【" .. (SCENE_NAMES[sceneId] or sceneId) .. "】"
    end

    -- 顶部货币栏
    if ui_.topSilverLabel then
        local silver = player_.silver or 0
        if silver >= 10000 then
            ui_.topSilverLabel.text = string.format("💰 %.1f万", silver / 10000)
        else
            ui_.topSilverLabel.text = "💰 " .. silver
        end
    end
    if ui_.topStoneLabel then
        ui_.topStoneLabel.text = "💎 " .. (player_.spirit_stone or 0)
    end

    -- 场景氛围描述
    if ui_.sceneDesc then
        local sceneId = player_.scene or "ancient_village"
        local desc = Settings.SCENE_DESC and Settings.SCENE_DESC[sceneId] or ""
        ui_.sceneDesc.text = desc
    end

    -- 刷新场景导航（仅在场景真正变化时重置当前小地点）
    local newScene = player_.scene or "ancient_village"
    -- 数据同步（不依赖当前面板）
    if lastScene_ ~= newScene then
        -- ★ 从域外战场切换到其他场景时，关闭战场地图并重建主内容
        local wasInBattlefield = (lastScene_ == "battlefield")
        currentSpot_ = nil
        npcDialog_   = nil
        sameSpotPlayers_ = {}
        lastScene_ = newScene

        if wasInBattlefield and newScene ~= "battlefield" then
            if BattlefieldMap.IsActive() then
                BattlefieldMap.Deactivate()
            end
            mapNvgActive_ = false
            StrongholdPanel.Hide()
            Client.SwitchBGM("town")
            if currentPanel_ == PANEL.MAIN and not inBattle_ then
                RebuildMainContent()
            end
        end
    end
    if not currentSpot_ and player_.spot and player_.spot ~= "" then
        currentSpot_ = player_.spot
    end

    -- UI 刷新（仅在主面板且非战斗时操作 UI 控件）
    if currentPanel_ == PANEL.MAIN and ui_.bottomSection and not inBattle_ then
        BuildSceneNav()
        RefreshPlayerList()
    end

    -- 刷新 NPC 区域（注册 Tutorial 目标等，即使面板非 MAIN 也执行，但战斗中跳过）
    if not inBattle_ then
        BuildNpcPanel()
    end
end

-- ============================================================================
-- 事件处理
-- ============================================================================

-- 显示暂存的离线奖励（游戏UI就绪后调用）
function Client._ShowOfflineRewards()
    local rewards = Client._pendingOfflineRewards
    if not rewards then return end
    Client._pendingOfflineRewards = nil

    local hours = math.floor((rewards.seconds or 0) / 3600)
    local mins  = math.floor(((rewards.seconds or 0) % 3600) / 60)
    local timeStr = ""
    if hours > 0 then timeStr = hours .. "小时" end
    if mins > 0 then timeStr = timeStr .. mins .. "分钟" end
    if timeStr == "" then timeStr = "不到1分钟" end

    AddLog(string.format("<黄>── 离线收益（%s）──</黄>", timeStr), "system")
    AddLog(string.format("  经验 +%d", rewards.exp or 0), "info")
    AddLog(string.format("  银两 +%d", rewards.silver or 0), "info")
    if (rewards.potential or 0) > 0 then
        AddLog(string.format("  潜能 +%d", rewards.potential), "info")
    end
    if (rewards.proficiency or 0) > 0 then
        AddLog(string.format("  修炼熟练度 +%.1f", rewards.proficiency), "good")
    end
    -- 大境界进度百分比变化
    if player_ and (rewards.exp or 0) > 0 then
        local realm = player_.realm or 1
        local layer = player_.realm_layer or 1
        local curExp = player_.realm_exp or 0
        local stage = Settings.REALM.STAGES[realm]
        if stage then
            local totalExp = Settings.REALM.GetTotalExp(realm)
            if totalExp > 0 then
                local doneExp = 0
                for i = 1, layer - 1 do
                    doneExp = doneExp + stage.exp_base * i
                end
                local nowPct = (doneExp + curExp) / totalExp * 100
                if nowPct > 100 then nowPct = 100 end
                local prevTotal = doneExp + curExp - (rewards.exp or 0)
                if prevTotal < 0 then prevTotal = 0 end
                local prevPct = prevTotal / totalExp * 100
                if prevPct > 100 then prevPct = 100 end
                local deltaPct = nowPct - prevPct
                AddLog(string.format("  【%s】%.1f%% → %.1f%% (+%.1f%%)",
                    stage.name, prevPct, nowPct, deltaPct), "good")
            end
        end
    end
end

local function OnInitPlayer(eventType, eventData)
    local jsonStr = eventData:GetString("data_json")
    if jsonStr and jsonStr ~= "" then
        local ok, data = pcall(cjson.decode, jsonStr)
        if ok and data then
            -- 检查是否新玩家需要创建角色
            if data._needCreate then
                data._needCreate = nil
                player_ = data
                if entryFlowActive_ then
                    -- 首次进入：欢迎页已显示，只需更新状态
                    print("[Client] INIT_PLAYER 新玩家（首次），标记为新玩家流程")
                    EntryFlow.SetConn(serverConn_)
                    EntryFlow.MarkNewPlayer()
                else
                    -- 游戏中被管理员清除：重新显示完整 EntryFlow
                    print("[Client] INIT_PLAYER 存档被重置，重新进入角色创建流程")
                    entryFlowActive_ = true
                    EntryFlow.Show({
                        conn = serverConn_,
                        isNew = true,
                        onComplete = function()
                            entryFlowActive_ = false
                            Client._BuildAndShowGameUI()
                        end,
                    })
                end
                return
            end

            player_ = data
            print("[Client] INIT_PLAYER 收到，uid=" .. tostring(player_.uid)
                .. " name=" .. tostring(player_.name) .. " lv=" .. tostring(player_.level))

            -- 解析离线奖励（不论 entryFlow 状态都先暂存）
            local rewardsStr = eventData:GetString("offline_rewards_json")
            if rewardsStr and rewardsStr ~= "" then
                local rok, rewards = pcall(cjson.decode, rewardsStr)
                if rok and rewards then
                    Client._pendingOfflineRewards = rewards
                end
            end

            -- 如果进入流程还在活动中（老玩家欢迎页），跳过 UI 更新
            if entryFlowActive_ then return end

            UpdateStatusBar()
            Tutorial.UpdatePlayer(player_)
            Tutorial.Check()
            -- 直接显示离线奖励
            Client._ShowOfflineRewards()
        else
            print("[Client] INIT_PLAYER JSON 解析失败:", tostring(data))
        end
    else
        print("[Client] INIT_PLAYER data_json 为空")
    end
end

local function OnPushPlayerData(eventType, eventData)
    local jsonStr = eventData:GetString("data_json")
    if jsonStr and jsonStr ~= "" then
        local ok, data = pcall(cjson.decode, jsonStr)
        if ok and data then
            player_ = data
            -- PushPlayerData 发 stats={hp,mp,...} 而非 hp_base/mp_base，展平以统一访问
            if data.stats then
                if not data.hp_base then data.hp_base = data.stats.hp end
                if not data.mp_base then data.mp_base = data.stats.mp end
                if not data.max_hp  then data.max_hp  = data.stats.hp end
                if not data.max_mp  then data.max_mp  = data.stats.mp end
            end
            -- 游戏 UI 尚未构建时只更新数据，不刷新 UI
            if entryFlowActive_ then return end
            UpdateStatusBar()
            Tutorial.UpdatePlayer(player_)
            Tutorial.Check()

            -- 如果当前在某面板，刷新（域外战场层面板查看时不刷新地图）
            if currentPanel_ == PANEL.SKILLS or
               currentPanel_ == PANEL.CULTIVATE or
               currentPanel_ == PANEL.INVENTORY or
               (currentPanel_ == PANEL.MAP and not viewingBattlefieldLayers_) then
                Client.SwitchPanel(currentPanel_)
            elseif currentPanel_ == PANEL.MARKET then
                -- 无论是购买成功还是其他事件触发，都强制从服务端拉最新列表
                print("[Market][OnPushPlayerData] MARKET面板收到PushPlayerData，pendingBuyId=" .. tostring(market_.pendingBuyId) .. " 强制刷新")
                market_.pendingBuyId = nil
                market_.dataReceived = false
                market_.fetched = false
                market_.listings = {}
                Client.SwitchPanel(PANEL.MARKET)
            end
        end
    end
end

--- 轻量经验推送（修炼中每5秒）
local function OnPushExpUpdate(eventType, eventData)
    if not player_ then return end
    local realmExp = eventData:GetInt("realm_exp")
    local realm = eventData:GetInt("realm")
    local realmLayer = eventData:GetInt("realm_layer")
    player_.realm_exp = realmExp
    player_.realm = realm
    player_.realm_layer = realmLayer
    if not entryFlowActive_ then
        UpdateStatusBar()
    end
end

local function OnPushInventory(eventType, eventData)
    local jsonStr = eventData:GetString("items_json")
    if jsonStr and jsonStr ~= "" then
        local ok, data = pcall(cjson.decode, jsonStr)
        if ok then
            inventory_ = data
            invUI_.opLock = 0  -- 解锁操作按钮
            -- 游戏 UI 尚未构建时只更新数据
            if entryFlowActive_ then return end
            if currentPanel_ == PANEL.INVENTORY then
                Client.SwitchPanel(PANEL.INVENTORY)
            end
        end
    end
end

--- 从带颜色标签的文本中提取 Toast 类型和纯文本
--- 标签格式: <绿>...</绿>  <红>...</红>  <黄>...</黄>  <金>...</金>
local function ParseToastFromLog(text)
    local toastType = "info"
    if text:find("<绿>") then
        toastType = "success"
    elseif text:find("<红>") then
        toastType = "error"
    elseif text:find("<黄>") or text:find("<金>") then
        toastType = "warning"
    end
    -- 去掉所有颜色标签，得到纯文本
    local plain = text:gsub("<[^>]+>", "")
    -- 去掉前后空白和换行
    plain = plain:match("^%s*(.-)%s*$") or plain
    return plain, toastType
end

local function OnPushGameLog(eventType, eventData)
    local text = eventData:GetString("text")
    local colorKey = eventData:GetString("color") or "info"
    if text and text ~= "" then
        AddLog(text, colorKey)
        -- 同时显示浮动 Toast 通知（跳过纯叙事/场景描述等长文本）
        local plain, toastType = ParseToastFromLog(text)
        if plain ~= "" and #plain <= 80 then
            UI.Toast.Show(plain, { type = toastType, duration = 2.5 })
        end
    end

    -- 购买失败时自动刷新交易阁（成功走 PushPlayerData，收到 PushLog 说明失败）
    print("[Market][OnPushGameLog] pendingBuyId=" .. tostring(market_.pendingBuyId) .. " currentPanel=" .. tostring(currentPanel_) .. " PANEL.MARKET=" .. tostring(PANEL.MARKET))
    if market_.pendingBuyId and currentPanel_ == PANEL.MARKET then
        print("[Market][OnPushGameLog] 购买失败检测到，强制刷新交易阁")
        market_.pendingBuyId = nil
        market_.dataReceived = false
        market_.fetched = false
        market_.listings = {}
        Client.SwitchPanel(PANEL.MARKET)
    end
end

local function OnNpcDialog(eventType, eventData)
    local npcName  = eventData:GetString("npc_name")
    local dialog   = eventData:GetString("dialog")
    local options  = eventData:GetString("options_json")

    -- 如果新方式取不到，尝试旧方式
    if (not options or options == "") then
        local ok2, v = pcall(function() return eventData["options_json"]:GetString() end)
        if ok2 and v and v ~= "" then
            options = v
        end
    end

    if npcName and dialog then
        AddLog("\n【" .. npcName .. "】", "gold")
        AddLog(dialog, "system")
    end

    local opts = nil
    if options and options ~= "" then
        local ok, decoded = pcall(cjson.decode, options)
        if ok and type(decoded) == "table" and #decoded > 0 then
            opts = decoded
        end
    end

    -- 缓存对话状态，BuildNpcPanel 会渲染选项按钮
    npcDialog_ = { npcName = npcName, dialog = dialog, options = opts }

    -- 如果当前不在主面板（比如从商店返回后），需要先切回主面板确保 npcPanel 存在
    if currentPanel_ ~= PANEL.MAIN or not ui_.npcPanel then
        currentPanel_ = PANEL.MAIN
        RebuildMainContent()
        BuildSceneNav()
    else
        BuildNpcPanel()
    end
end

local function OnNpcSkillGrant(eventType, eventData)
    local skillsJson = eventData:GetString("skills_json")
    if not skillsJson then return end
    local ok, skills = pcall(cjson.decode, skillsJson)
    if not ok then return end

    AddLog("\n═══ 传功仪式 ═══", "gold")
    for _, s in ipairs(skills) do
        local def = Shared.GetSkillDef(s.skill_id)
        local name = def and def.name or s.skill_id
        AddLog("获得：《" .. name .. "》" .. (s.bound and " [绑定]" or " [未绑定可交易]"), "gold")
    end
    AddLog("═══════════════", "gold")
end

local function OnPushBattleState(eventType, eventData)
    local logText      = eventData:GetString("Log")
    local myHp         = eventData:GetInt("PlayerHp")
    local myMp         = eventData:GetInt("PlayerMp")
    local myMaxHp      = eventData:GetInt("PlayerHpMax")
    local myMaxMpSrv   = eventData:GetInt("PlayerMpMax")
    local atkHp        = eventData:GetInt("MonsterHp")
    local atkMaxHp     = eventData:GetInt("MonsterHpMax")
    local atkName      = eventData:GetString("MonsterName")
    local autoFight    = eventData:GetBool("AutoFight")
    local cooldownsJson  = eventData:GetString("Cooldowns")
    local round          = eventData:GetInt("Round")
    local firstAttacker  = eventData:GetString("FirstAttacker") or "player"
    local pendingSkill   = eventData:GetString("PendingSkill") or ""

    -- 解析冷却 JSON
    if cooldownsJson and cooldownsJson ~= "" then
        local ok, cd = pcall(cjson.decode, cooldownsJson)
        if ok and type(cd) == "table" then
            skillCooldowns_ = cd
        end
    end
    autoFight_    = autoFight
    pendingSkill_ = pendingSkill

    -- 保存旧 HP 用于浮动伤害数字
    local prevMyHp  = battleState_ and battleState_.myHp  or myMaxHp
    local prevAtkHp = battleState_ and battleState_.atkHp or atkMaxHp

    -- 更新战斗状态缓存
    battleState_ = {
        myHp    = myHp,
        myMp    = myMp,
        myMaxHp = myMaxHp,
        myMaxMp = myMaxMpSrv,
        atkHp   = atkHp,
        atkMaxHp= atkMaxHp,
        atkName = atkName,
        round   = round,
        autoFight = autoFight,
    }

    if logText and logText ~= "" then
        AddLog(logText, "danger")
        -- 同步写入战斗内嵌日志（最多保留 3 条）
        battleLog_[#battleLog_ + 1] = logText
        if #battleLog_ > 3 then table.remove(battleLog_, 1) end
    end

    -- 更新状态栏
    if player_ then
        player_.hp     = myHp
        player_.mp     = myMp
        player_.max_hp = myMaxHp
        if myMaxMpSrv > 0 then player_.max_mp = myMaxMpSrv end
        UpdateStatusBar()
    end

    -- ── 触发回合动画队列（由 firstAttacker 驱动，非 HP 差值）──
    TriggerRoundAnim(firstAttacker)

    -- ── 浮动伤害数字：存入待定列表，等 hit 动画阶段再显示 ────
    -- battleAnim_.pendingFloat[1] = 先手攻击造成的伤害(显示在被攻击方头顶)
    -- battleAnim_.pendingFloat[2] = 后手攻击造成的伤害(显示在被攻击方头顶)
    battleAnim_.pendingFloat = {}
    if firstAttacker == "monster" then
        -- 怪先手：怪打玩家 → 玩家掉血；玩家后手：玩家打怪 → 怪掉血
        if myHp < prevMyHp then
            battleAnim_.pendingFloat[1] = { dmg = prevMyHp - myHp, target = "player" }
        end
        if atkHp < prevAtkHp then
            battleAnim_.pendingFloat[2] = { dmg = prevAtkHp - atkHp, target = "monster" }
        end
    else
        -- 玩家先手：玩家打怪 → 怪掉血；怪后手：怪打玩家 → 玩家掉血
        if atkHp < prevAtkHp then
            battleAnim_.pendingFloat[1] = { dmg = prevAtkHp - atkHp, target = "monster" }
        end
        if myHp < prevMyHp then
            battleAnim_.pendingFloat[2] = { dmg = prevMyHp - myHp, target = "player" }
        end
    end
    battleAnim_.pendingFloatIdx = 1  -- 下一个待触发的索引

    -- 自动切换到嵌入式战斗视图
    inBattle_ = true
    Tutorial.Advance("battle_start")
    RebuildMainContent()
end

local function OnPushBattleEnd(eventType, eventData)
    local won       = eventData:GetBool("Win")
    local logText   = eventData:GetString("Log")
    local expGain   = eventData:GetInt("ExpGain")
    local potentialGain = eventData:GetInt("PotentialGain")
    local silverGain= eventData:GetInt("SilverGain")
    local lootToken    = eventData:GetString("LootToken")    or ""
    local lootItemName = eventData:GetString("LootItemName") or ""

    print(string.format("[Client] OnPushBattleEnd: won=%s potential=%d silver=%d",
        tostring(won), potentialGain or 0, silverGain or 0))

    -- ★ 战斗结果音效
    PlaySFX(won and "victory" or "defeat")

    -- 立即显示战斗日志（玩家可以先看到文字结果）
    AddLog("\n── 战斗结束 ──", "title")
    if logText and logText ~= "" then AddLog(logText, won and "good" or "danger") end
    if won then
        if potentialGain > 0 then AddLog("获得潜能：+" .. potentialGain,    "good") end
        if silverGain> 0 then AddLog("获得银两：+" .. silverGain .. "两","gold") end
        if lootToken ~= "" and lootItemName ~= "" then
            if lootToken == "auto" then
                AddLog("自动拾取：" .. lootItemName, "good")
            else
                AddLog("掉落物品：", "gold")
                AddLootLink(lootItemName, lootToken)
                Tutorial.Advance("loot_appeared")
            end
        end
    end
    Tutorial.Advance("battle_end")

    -- ★ 同步解锁层数（Boss 击败后服务端附带）
    local newMaxLayer = eventData:GetInt("MaxBattlefieldLayer")
    local wasBossChallenge = (newMaxLayer > 0)
    if wasBossChallenge and player_ then
        player_.max_battlefield_layer = newMaxLayer
    end

    -- ★ 保存战斗结果供聊天分享使用
    local enemyName = (battleState_ and battleState_.monster and battleState_.monster.name) or "敌人"
    battleAnim_.lastResult = {
        won = won,
        desc = won and ("击败了" .. enemyName) or ("败于" .. enemyName .. "之手"),
        expGain = expGain,
        silverGain = silverGain,
        lootItemName = lootItemName,
    }

    -- ★ 延迟执行清理：将数据存入 pending，等动画播完后由渲染循环触发 ProcessBattleEnd
    local pending = {
        won = won, logText = logText, expGain = expGain,
        silverGain = silverGain, lootToken = lootToken, lootItemName = lootItemName,
        wasBossChallenge = wasBossChallenge,
    }
    -- 如果 NanoVG 上下文不存在（战斗界面未初始化），直接执行清理
    if not vg_battle_ then
        ProcessBattleEnd(pending)
    else
        battleAnim_.endPending = pending
        battleAnim_.endTimer = 2.5  -- 安全超时（秒），即使动画异常也会强制结束
    end
end

market_.dataReceived = false  -- 重置标记（变量声明在文件顶部）
local function OnPushMarketData(eventType, eventData)
    local listingsJson = eventData:GetString("listings_json")
    if listingsJson and listingsJson ~= "" then
        local ok, data = pcall(cjson.decode, listingsJson)
        if ok and data then
            print("[Market][OnPushMarketData] 收到服务端列表数据，共 " .. #data .. " 条")
            if #data > 0 then
                for i = 1, math.min(3, #data) do
                    print(string.format("[Market][OnPushMarketData] data[%d].listing_id=%s type=%s", i, tostring(data[i].listing_id), type(data[i].listing_id)))
                end
            end
            market_.listings = data
            -- 仅当在市场面板且尚未刷新过时才重建（防止循环）
            if currentPanel_ == PANEL.MARKET and not market_.dataReceived then
                market_.dataReceived = true
                Client.SwitchPanel(PANEL.MARKET)
            end
            -- 只在有货品时打印日志，避免空列表刷屏
            if #data > 0 then
                AddLog("交易阁：共 " .. #data .. " 件在售货品", "info")
            end
        end
    end
end

local function OnAdminLoginResult(eventType, eventData)
    local ok = eventData:GetBool("Success")
    if ok then
        if player_ then player_.is_admin = true end
        AddLog("【管理员模式已激活】", "danger")
        Client.SwitchPanel(PANEL.ADMIN)
    else
        AddLog("激活码错误，验证失败", "danger")
    end
end

local function OnPushShopData(eventType, eventData)
    local shopType  = eventData:GetString("ShopType")
    local shopTitle = eventData:GetString("ShopTitle")
    local itemsJson = eventData:GetString("Items")
    local currency  = eventData:GetString("Currency")

    local ok, items = pcall(cjson.decode, itemsJson)
    if not ok or not items then
        AddLog("商店数据解析失败", "danger")
        return
    end

    shopData_.shopType  = shopType  or "equipment"
    shopData_.shopTitle = shopTitle or "商店"
    shopData_.items     = items
    shopData_.currency  = currency  ~= "" and currency or "silver"

    -- 打开商店面板
    Client.SwitchPanel(PANEL.SHOP)
    AddLog(string.format("【%s】共%d件商品，使用%s结算",
        shopData_.shopTitle, #items,
        shopData_.currency == "spirit_stone" and "灵石" or "银两"), "gold")
end

local function OnPushMarketHistory(eventType, eventData)
    local json = eventData:GetString("history_json")
    if json and json ~= "" then
        local ok, data = pcall(cjson.decode, json)
        market_.history = (ok and type(data) == "table") and data or {}
    else
        market_.history = {}
    end
    -- 刷新交易阁面板（此时 tab 已切到"交易记录"）
    if currentPanel_ == PANEL.MARKET then
        Client.SwitchPanel(PANEL.MARKET)
    end
end



local function OnPushMarketTrends(eventType, eventData)
    print("[Client] OnPushMarketTrends called")

    local json = eventData:GetString("trends_json")

    if json and json ~= "" then

        local ok, data = pcall(cjson.decode, json)

        market_.trends = (ok and type(data) == "table") and data or {}

    else

        market_.trends = {}

    end

    if currentPanel_ == PANEL.MARKET then

        Client.SwitchPanel(PANEL.MARKET)

    end

end
-- 接收服务端推送的传闻更新（管理员修改后广播）
local function OnPushNewsUpdate(eventType, eventData)
    local text = eventData:GetString("Text")
    if not text or text == "" then return end
    -- 缓存最新传闻（即使 UI 未就绪也不丢失）
    latestNews_ = text
    -- 更新传闻栏文字
    if ui_.newsText then
        ui_.newsText.text = "【传闻】" .. text
    end
    AddLog("【传闻更新】" .. text, "system")
end

-- 接收管理员查询玩家结果
local function OnPushAdminPlayerInfo(eventType, eventData)
    local json = eventData:GetString("info_json")
    if not json or json == "" then
        adminPlayerInfo_ = nil
    else
        local ok, data = pcall(cjson.decode, json)
        adminPlayerInfo_ = (ok and type(data) == "table") and data or nil
    end
    -- 刷新管理员面板
    if currentPanel_ == PANEL.ADMIN then
        Client.SwitchPanel(PANEL.ADMIN)
    end
end

-- 接收管理员操作结果（传闻修改/加货币等）
local function OnPushAdminResult(eventType, eventData)
    local ok  = eventData:GetBool("Ok")
    local msg = eventData:GetString("Msg")
    if ok then
        AddLog("【管理操作成功】" .. (msg or ""), "good")
    else
        AddLog("【管理操作失败】" .. (msg or ""), "danger")
    end
    -- 刷新管理员面板（例如传闻修改后更新输入框状态）
    if currentPanel_ == PANEL.ADMIN then
        Client.SwitchPanel(PANEL.ADMIN)
    end
end

-- 接收管理员玩家列表（分页）
local function OnPushAdminPlayerList(eventType, eventData)
    local json     = eventData:GetString("list_json")
    local total    = eventData:GetInt("total")
    local page     = eventData:GetInt("page")
    local pageSize = eventData:GetInt("page_size")
    local mode     = eventData:GetString("mode")

    local ok, list = pcall(cjson.decode, json or "[]")
    adminPlayerList_      = (ok and type(list) == "table") and list or {}
    adminPlayerListTotal_ = total or 0
    adminPlayerListPage_  = page or 1
    adminPlayerListMode_  = mode or "online"

    if currentPanel_ == PANEL.ADMIN then
        Client.SwitchPanel(PANEL.ADMIN)
    end
end

-- ============================================================================
-- 聊天事件处理
-- ============================================================================

-- 收到单条消息推送（广播/门派/系统/私信）
local function OnPushChatMsg(eventType, eventData)
    local json = eventData:GetString("MsgJson")
    if not json or json == "" then return end
    local ok, msg = pcall(cjson.decode, json)
    if not ok or type(msg) ~= "table" then return end

    -- 私信特殊处理：存入 pmState_.history
    if msg.channel == "private" then
        local from = msg.sender or ""
        if from ~= "" then
            if not pmState_.history[from] then pmState_.history[from] = {} end
            local h = pmState_.history[from]
            h[#h + 1] = { sender = from, text = msg.text or "", time = msg.time or 0 }
            AddLog("【私信】" .. from .. "：" .. (msg.text or ""), "info")
            -- 如果当前正在看私信面板且对象匹配，刷新
            if currentPanel_ == PANEL.CHAT and chatActiveChannel_ == "私信" and pmState_.target == from then
                currentSubTab_[PANEL.CHAT] = "私信"
                if chatUI_.exclusive then
                    BuildChatExclusiveMode("私信")
                end
            end
        end
        return
    end

    AppendLocalChatMsg(msg)

    -- 若聊天面板正在展示且是对应频道，立即刷新
    if currentPanel_ == PANEL.CHAT and chatUI_.msgContainer then
        local chName = msg.channel
        if chName == "world" then chName = "世界"
        elseif chName == "system" then chName = "系统"
        elseif chName == "sect" or (chName and chName:sub(1,5) == "sect_") then chName = "门派"
        end
        if chName == chatActiveChannel_ then
            RefreshChatMessages()
        end
    end
end

-- 收到历史消息批量推送（上线时服务端推送）
local function OnPushChatHistory(eventType, eventData)
    local json = eventData:GetString("HistoryJson")
    if not json or json == "" then return end
    local ok, list = pcall(cjson.decode, json)
    if not ok or type(list) ~= "table" then return end

    for _, msg in ipairs(list) do
        AppendLocalChatMsg(msg)
    end
    -- 如果当前正在看聊天面板，刷新显示
    if currentPanel_ == PANEL.CHAT and chatUI_.msgContainer then
        RefreshChatMessages()
    end
end

-- ============================================================================
-- UI 构建主体
-- ============================================================================

-- ── 进度条工具（BuildMainUI 和 BuildLogPanel 共用）─────────
local function MakeBar(bgColor, fillColor)
    local track = UI.Panel {
        flex = 1, height = 8,
        backgroundColor = bgColor,
        overflow = "hidden",
        borderRadius = 4,
    }
    local fill = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = fillColor,
        borderRadius = 4,
    }
    track:AddChild(fill)
    return track, fill
end

-- ── 时辰计算 ──────────────────────────────────────────────
local TIME_PERIODS = {"子","丑","寅","卯","辰","巳","午","未","申","酉","戌","亥"}
local function GetGameTime()
    local idx = math.floor(gameTimeElapsed_ / 120) % 12 + 1
    return "🏮" .. TIME_PERIODS[idx] .. "时"
end

-- ── 快捷操作栏（打坐/任务/助战/信件/地图）────────────────
local function BuildQuickBar()
    -- 外层行：左侧留白 + 小按钮组 + 右弹性空白
    local row = UI.Panel {
        width = "100%", height = 46,
        flexDirection = "row",
        alignItems = "center",
        gap = 0,
        paddingHorizontal = 6,
        backgroundColor = TC.bgDeep,
        flexShrink = 0,
        borderTopWidth = 1,
        borderColor = TC.borderLight,
    }

    -- 左侧留白占位
    row:AddChild(UI.Panel { width = 6, height = "100%" })

    local quickActions = {
        { "恢复", function()
            print("[Client] 恢复按钮被点击，发送 REQ_RESTORE")
            SendToServer(EV.REQ_RESTORE, {})
            AddLog(">> 正在恢复气血内力...", "info")
        end },
        { "突破", function()
            SendToServer(EV.REQ_BREAKTHROUGH, {})
        end },
        { "任务", function() SendToServer(EV.REQ_QUEST_INFO_REQ, {}); Client.ShowQuestPanel() end, highlight = true },
        { "交易阁", function() Client.SwitchPanel(PANEL.MARKET) end, highlight = true },
    }

    -- 小按钮组（胶囊风格）
    local btnGroup = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        paddingHorizontal = 4,
        flexShrink = 0,
    }
    for _, qa in ipairs(quickActions) do
        local isHL = qa.highlight
        btnGroup:AddChild(UI.Button {
            text = qa[1],
            paddingHorizontal = 16,
            height = 34,
            fontSize = 15,
            fontWeight = "bold",
            borderRadius = 17,
            backgroundColor = isHL and { 50, 18, 15, 230 } or { 30, 28, 35, 220 },
            color = isHL and { 255, 140, 90, 255 } or { 190, 180, 160, 255 },
            borderWidth = 1,
            borderColor = isHL and { 200, 80, 50, 200 } or { 80, 70, 50, 150 },
            onClick = qa[2],
        })
    end
    row:AddChild(btnGroup)

    -- 右侧弹性空白（撑开布局）
    row:AddChild(UI.Panel { flexGrow = 1 })

    -- 右侧地图按钮（胶囊）
    row:AddChild(UI.Button {
        text = "地图",
        paddingHorizontal = 18, height = 34,
        fontSize = 15,
        fontWeight = "bold",
        borderRadius = 17,
        backgroundColor = TC.bgPanel,
        color = TC.success,
        borderWidth = 1,
        borderColor = TC.border,
        onClick = function() Client.SwitchPanel(PANEL.MAP) end,
    })

    return row
end

-- ── 场景导航（bottomSection：当前大地点内小地点，宽按钮+高亮风格）────
BuildSceneNav = function()
    if not ui_.bottomSection then return end
    ui_.bottomSection:ClearChildren()

    local scene = player_ and player_.scene or "ancient_village"

    -- 域外战场不显示 spot 网格（层选择由地图面板的 BuildBattlefieldLayerPanel 处理）
    if scene == "battlefield" then
        ui_.bottomSection:AddChild(UI.Panel {
            width = "100%", alignItems = "center",
            justifyContent = "center", paddingVertical = 12,
        })
        return
    end

    local spots = (Settings.SCENE_SPOTS and Settings.SCENE_SPOTS[scene]) or {}

    -- 顶部刻意留白
    ui_.bottomSection:AddChild(UI.Panel { width = "100%", height = 40 })

    -- 无小地点数据时显示占位
    if #spots == 0 then
        local empty = UI.Panel {
            width = "100%", alignItems = "center",
            justifyContent = "center", paddingVertical = 8,
        }
        empty:AddChild(UI.Label {
            text = "── 无可探索地点 ──", fontSize = 15,
            color = TC.textMuted,
        })
        ui_.bottomSection:AddChild(empty)
        return
    end

    -- ── 构建方位网格 ──────────────────────────────────────────
    -- 1. 将 spots 按 pos 放入二维查找表，并统计行列范围
    local grid = {}      -- grid[row][col] = spot
    local maxRow, maxCol = 0, 0
    for _, spot in ipairs(spots) do
        local r, c = spot.pos[1], spot.pos[2]
        if not grid[r] then grid[r] = {} end
        grid[r][c] = spot
        if r > maxRow then maxRow = r end
        if c > maxCol then maxCol = c end
    end

    -- 单元格尺寸
    local CELL_W = 110
    local CELL_H = 62
    local CELL_GAP = 5

    -- 2. 外层容器（垂直排列各行，水平居左，留内边距）
    local gridPanel = UI.Panel {
        width = "100%",
        flexDirection = "column",
        alignItems = "center",
        gap = CELL_GAP,
        paddingHorizontal = 10,
        paddingBottom = 8,
    }

    -- 查找当前所在地点的 pos
    local curPos = nil
    if currentSpot_ then
        for _, sp in ipairs(spots) do
            if sp.id == currentSpot_ then curPos = sp.pos; break end
        end
    end

    -- 判断两个地点是否相邻（上下左右，曼哈顿距离=1）
    local function isAdjacent(posA, posB)
        if not posA or not posB then return false end
        local dr = math.abs(posA[1] - posB[1])
        local dc = math.abs(posA[2] - posB[2])
        return (dr == 1 and dc == 0) or (dr == 0 and dc == 1)
    end

    -- 3. 按行生成
    for r = 1, maxRow do
        local rowPanel = UI.Panel {
            flexDirection = "row",
            flexShrink = 0,
            gap = CELL_GAP,
        }
        for c = 1, maxCol do
            local spot = grid[r] and grid[r][c]
            if spot then
                local isActive  = (currentSpot_ == spot.id)
                -- 首次进入（无当前位置）：所有格可点；否则只有相邻格可点
                local canMove   = (curPos == nil) or isAdjacent(curPos, spot.pos)
                -- 外观：当前位置=翠玉高亮；可到达=淡绿；不可达=暗灰
                local bgColor, bdColor, nameColor
                if isActive then
                    bgColor   = { 8, 40, 20, 245 }
                    bdColor   = { 60, 200, 100, 255 }
                    nameColor = { 140, 235, 160, 255 }
                elseif canMove then
                    bgColor   = { 12, 28, 16, 230 }
                    bdColor   = { 50, 120, 60, 200 }
                    nameColor = { 175, 215, 180, 255 }
                else
                    bgColor   = { 10, 14, 10, 180 }
                    bdColor   = { 30, 40, 28, 120 }
                    nameColor = { 80, 90, 75, 180 }
                end

                local btn = UI.Button {
                    width = CELL_W, height = CELL_H, flexShrink = 0,
                    flexDirection = "column",
                    alignItems = "center", justifyContent = "center",
                    gap = 2, paddingHorizontal = 6,
                    backgroundColor = bgColor,
                    borderWidth = isActive and 2 or 1,
                    borderColor = bdColor,
                    onClick = function()
                        if isActive then return end
                        if not canMove then
                            AddLog("❌ 需先到达相邻地点才能前往 " .. spot.name, "warn")
                            return
                        end
                        currentSpot_ = spot.id
                        npcDialog_   = nil   -- 切换地点时清除挂起的 NPC 对话
                        AddLog(">> 前往 " .. spot.name .. "...", "info")
                        -- 通知服务端更新小地点，触发同场景玩家列表广播
                        SendToServer(EV.REQ_CHANGE_SPOT, { Spot = spot.id })
                        BuildSceneNav()
                        BuildNpcPanel()
                        RefreshPlayerList()
                        -- 教程推进：用 spot.id 而非 name（name 含全角空格会不匹配）
                        Tutorial.Advance("spot_" .. spot.id .. "_arrived")
                    end,
                }
                btn:AddChild(UI.Label {
                    text = spot.name, fontSize = 16,
                    color = nameColor, textAlign = "center",
                })
                -- 注册地图按钮为教程高亮目标
                Tutorial.RegisterTarget("map_" .. spot.name, btn)
                rowPanel:AddChild(btn)
            else
                -- 空位：透明占位格
                rowPanel:AddChild(UI.Panel {
                    width = CELL_W, height = CELL_H, flexShrink = 0,
                })
            end
        end
        gridPanel:AddChild(rowPanel)
    end

    ui_.bottomSection:AddChild(gridPanel)
end

-- ── 帮助面板 ──────────────────────────────────────────────
local function BuildSoundPanel()
    local container = UI.Panel {
        width = "100%", padding = { 8, 6 }, gap = 10,
    }
    container:AddChild(UI.Label {
        text = "── 音效设置 ──", fontSize = 17,
        color = LOG_COLOR.title, alignSelf = "center", marginBottom = 4,
    })

    -- BGM 音量
    local bgmGain = (ui_.bgmSource and ui_.bgmSource.gain or 0.4)
    container:AddChild(UI.Label { text = "背景音乐音量", fontSize = 14, color = TC.success })
    container:AddChild(UI.Slider {
        width = "90%", alignSelf = "center",
        min = 0, max = 100, value = math.floor(bgmGain * 100 + 0.5),
        onChange = function(self, v)
            local gain = v / 100
            if ui_.bgmSource then ui_.bgmSource.gain = gain end
        end,
    })

    -- 全局音量
    local masterVol = audio:GetMasterGain(SOUND_MASTER) or 1.0
    container:AddChild(UI.Label { text = "全局音量", fontSize = 14, color = TC.success, marginTop = 6 })
    container:AddChild(UI.Slider {
        width = "90%", alignSelf = "center",
        min = 0, max = 100, value = math.floor(masterVol * 100 + 0.5),
        onChange = function(self, v)
            audio:SetMasterGain(SOUND_MASTER, v / 100)
        end,
    })

    -- 静音按钮
    container:AddChild(UI.Button {
        text = "一键静音 / 恢复",
        fontSize = 14, marginTop = 10, alignSelf = "center",
        paddingHorizontal = 16, paddingVertical = 6,
        backgroundColor = TC.btnPrimary,
        onClick = function(self)
            local cur = audio:GetMasterGain(SOUND_MASTER)
            if cur > 0 then
                audio:SetMasterGain(SOUND_MASTER, 0)
                self:SetText("已静音（点击恢复）")
            else
                audio:SetMasterGain(SOUND_MASTER, 1.0)
                self:SetText("一键静音 / 恢复")
            end
        end,
    })

    return container
end

local function BuildAccountPanel()
    local container = UI.Panel {
        width = "100%", padding = { 8, 6 }, gap = 8,
    }
    container:AddChild(UI.Label {
        text = "── 账号信息 ──", fontSize = 17,
        color = LOG_COLOR.title, alignSelf = "center", marginBottom = 4,
    })

    local uid = player_ and tostring(player_.uid) or "未登录"
    local name = player_ and player_.name or "未知"
    local realm = player_ and (player_.realm_name or Settings.REALM.GetDisplayName(player_.realm or 1, player_.realm_layer or 1)) or "凡人"
    local silver = player_ and tostring(player_.silver or 0) or "0"
    local spirit = player_ and tostring(player_.spirit_stone or 0) or "0"

    local rows = {
        { "UID", uid },
        { "角色名", name },
        { "境界", realm },
        { "银两", silver },
        { "灵石", spirit },
    }

    for _, row in ipairs(rows) do
        local rowPanel = UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between",
            paddingHorizontal = 8, paddingVertical = 3,
        }
        rowPanel:AddChild(UI.Label { text = row[1], fontSize = 14, color = TC.success })
        rowPanel:AddChild(UI.Label { text = row[2], fontSize = 14, color = TC.textPrimary })
        container:AddChild(rowPanel)
    end

    -- 复制 UID 按钮
    container:AddChild(UI.Button {
        text = "复制编号", fontSize = 14, marginTop = 12, alignSelf = "center",
        paddingHorizontal = 20, paddingVertical = 6,
        backgroundColor = TC.bgPanel,
        onClick = function()
            ui.clipboardText = uid
            AddLog(">> UID 已复制到剪贴板：" .. uid, "good")
        end,
    })

    return container
end

local function BuildHelpPanel()
    local container = UI.Panel {
        width = "100%", padding = { 8, 6 }, gap = 6,
    }
    container:AddChild(UI.Label {
        text = "── 新手指南 ──", fontSize = 17,
        color = LOG_COLOR.title, alignSelf = "center", marginBottom = 4,
    })
    local helpSections = {
        { "【基本操作】",
          "• 点击场景中的怪物/NPC 进行交互\n" ..
          "• 底部快捷栏可一键打坐/接取任务\n" ..
          "• 上方面板按钮切换各功能" },
        { "【修炼成长】",
          "• 打坐：消耗灵石获取修为，修为满后可突破境界\n" ..
          "• 武学：学习/升级技能，战斗中使用\n" ..
          "• 炼丹/炼器：消耗材料制作丹药和装备" },
        { "【战斗系统】",
          "• 野外遇敌自动进入回合制战斗\n" ..
          "• 选择技能释放，注意灵力消耗和冷却\n" ..
          "• 战报面板查看历史战斗记录" },
        { "【域外战场】",
          "• 点击地图按钮进入大地图自由移动\n" ..
          "• 接近怪物触发战斗，击杀获取掉落\n" ..
          "• 击杀怪物可获得经验和装备掉落" },
        { "【社交玩法】",
          "• 世界频道：与全服玩家聊天\n" ..
          "• 门派频道：与同门交流\n" ..
          "• 私信：点击玩家名称发送私聊\n" ..
          "• 帮会：加入帮会争夺据点" },
        { "【小贴士】",
          "• 观看广告（福利按钮）可获得灵石\n" ..
          "• 每日登录有灵石奖励\n" ..
          "• 首领每日可挑战，掉落稀有材料" },
    }
    for _, sec in ipairs(helpSections) do
        container:AddChild(UI.Label {
            text = sec[1], fontSize = 16,
            color = TC.textTitle, marginTop = 4,
        })
        container:AddChild(UI.Label {
            text = sec[2], fontSize = 14,
            color = TC.success, marginLeft = 4,
        })
    end
    return container
end

-- ── 私信面板 ──────────────────────────────────────────────
local function BuildPrivateMsgPanel()
    local dpr  = graphics:GetDPR()
    local logH = graphics:GetHeight() / dpr
    local areaH = math.max(180, logH - 36 - 44 - 80 - 44 - 30 - 54)
    local msgH = math.max(80, areaH - 44 - 36 - 8)

    local container = UI.Panel {
        width = "100%", height = areaH,
        flexShrink = 0, flexDirection = "column",
        paddingHorizontal = 4, paddingVertical = 4, gap = 4,
    }

    -- 顶部：选择对象行
    local topRow = UI.Panel {
        width = "100%", height = 32, flexShrink = 0,
        flexDirection = "row", alignItems = "center", gap = 6,
        paddingHorizontal = 4,
        borderBottomWidth = 1, borderColor = TC.borderLight,
    }
    topRow:AddChild(UI.Label {
        text = "私信：", fontSize = 15, color = TC.textSecondary,
    })
    ---@type Widget
    local targetField = UI.TextField {
        flexGrow = 1, height = 26, fontSize = 14,
        placeholder = "输入玩家名称…",
        backgroundColor = TC.bgPanel,
        color = TC.textPrimary,
        borderWidth = 1, borderColor = TC.border,
    }
    if pmState_.target ~= "" then targetField:SetValue(pmState_.target) end
    topRow:AddChild(targetField)
    container:AddChild(topRow)

    -- 消息显示区
    local scrollView = UI.ScrollView {
        width = "100%", height = msgH,
        flexShrink = 0, scrollY = true,
        backgroundColor = TC.bgDeep,
    }
    local msgContainer = UI.Panel {
        width = "100%", gap = 1, padding = { 4, 4 },
    }
    scrollView:AddChild(msgContainer)
    container:AddChild(scrollView)

    -- 渲染历史消息
    local function RenderPmHistory()
        msgContainer:ClearChildren()
        local history = pmState_.history[pmState_.target]
        if not history or #history == 0 then
            msgContainer:AddChild(UI.Label {
                text = pmState_.target == "" and "请输入玩家名称开始私聊"
                    or "暂无与【" .. pmState_.target .. "】的聊天记录",
                fontSize = 14, color = TC.textMuted,
                alignSelf = "center", marginTop = 16,
            })
            return
        end
        for _, msg in ipairs(history) do
            local isMine = (msg.sender == (player_ and player_.name or ""))
            local prefix = isMine and "我" or msg.sender
            msgContainer:AddChild(UI.Label {
                text = prefix .. "：" .. msg.text,
                fontSize = 14,
                color = isMine and { 140, 200, 255, 255 } or { 200, 220, 180, 255 },
            })
        end
    end
    RenderPmHistory()

    -- 输入行
    local inputRow = UI.Panel {
        width = "100%", height = 44, flexShrink = 0,
        flexDirection = "row", gap = 6,
        alignItems = "center", paddingHorizontal = 4,
        borderTopWidth = 1, borderColor = TC.borderLight,
    }
    ---@type Widget
    local tf = UI.TextField {
        flexGrow = 1, height = 34, fontSize = 15,
        placeholder = "输入消息…",
        backgroundColor = TC.bgPanel,
        color = TC.textPrimary,
        borderWidth = 1, borderColor = TC.border,
    }
    local sendBtn = UI.Button {
        text = "发送", width = 58, height = 34, fontSize = 15,
        backgroundColor = TC.bgPanel,
        onClick = function()
            -- 获取目标名
            local target = targetField:GetValue()
            target = target:match("^%s*(.-)%s*$")
            if target == "" then
                AddLog("请先输入私信对象的名称", "warn")
                return
            end
            pmState_.target = target
            -- 获取消息文本
            local text = tf:GetValue()
            text = text:match("^%s*(.-)%s*$")
            if text == "" then return end
            -- 发送到服务端
            SendToServer(EV.REQ_CHAT_SEND, { Channel = "private", Target = target, Text = text })
            -- 本地追加
            if not pmState_.history[target] then pmState_.history[target] = {} end
            local h = pmState_.history[target]
            h[#h + 1] = { sender = (player_ and player_.name or "我"), text = text, time = os.time() }
            tf:Clear()
            RenderPmHistory()
        end,
    }
    inputRow:AddChild(tf)
    inputRow:AddChild(sendBtn)
    container:AddChild(inputRow)

    return container
end

-- ── 好友面板 ────────────────────────────────────────────────
local function BuildFriendPanel()
    -- 请求最新好友列表
    SendToServer(EV.REQ_FRIEND_LIST, {})

    local container = UI.Panel {
        width = "100%", flexGrow = 1,
        flexDirection = "column", gap = 4,
        paddingHorizontal = 6, paddingVertical = 6,
    }

    -- 添加好友行
    local addRow = UI.Panel {
        width = "100%", height = 36, flexShrink = 0,
        flexDirection = "row", alignItems = "center", gap = 6,
        paddingHorizontal = 4,
    }
    ---@type Widget
    local addField = UI.TextField {
        flexGrow = 1, height = 30, fontSize = 14,
        placeholder = "输入玩家名添加好友…",
        backgroundColor = TC.bgPanel,
        color = TC.textPrimary,
        borderWidth = 1, borderColor = TC.border,
    }
    addRow:AddChild(addField)
    addRow:AddChild(UI.Button {
        text = "+添加", width = 60, height = 30, fontSize = 14,
        backgroundColor = TC.success,
        onClick = function()
            local name = addField:GetValue()
            name = name:match("^%s*(.-)%s*$")
            if name == "" then AddLog("请输入玩家名称", "warn") return end
            SendToServer(EV.REQ_ADD_FRIEND, { TargetName = name })
            addField:Clear()
        end,
    })
    container:AddChild(addRow)

    -- 好友列表
    local listContainer = UI.Panel {
        width = "100%", flexGrow = 1, gap = 2,
        paddingVertical = 4,
    }

    local function RenderList()
        listContainer:ClearChildren()
        if #friendList_ == 0 then
            listContainer:AddChild(UI.Label {
                text = "暂无好友，添加好友一起闯荡江湖吧",
                fontSize = 14, color = TC.textMuted,
                alignSelf = "center", marginTop = 16,
            })
            return
        end
        -- 在线排前面
        local sorted = {}
        for _, f in ipairs(friendList_) do sorted[#sorted+1] = f end
        table.sort(sorted, function(a, b)
            if a.online ~= b.online then return a.online end
            return a.name < b.name
        end)
        for _, f in ipairs(sorted) do
            local row = UI.Panel {
                width = "100%", height = 34, flexShrink = 0,
                flexDirection = "row", alignItems = "center",
                paddingHorizontal = 8, gap = 6,
                backgroundColor = TC.bgOverlay,
                borderBottomWidth = 1, borderColor = TC.borderLight,
            }
            -- 在线指示
            row:AddChild(UI.Label {
                text = f.online and "●" or "○",
                fontSize = 14,
                color = f.online and { 80, 220, 80, 255 } or { 100, 100, 100, 180 },
            })
            -- 名字
            row:AddChild(UI.Label {
                text = f.name, fontSize = 14, flexGrow = 1,
                color = f.online and { 220, 230, 200, 255 } or { 140, 140, 150, 200 },
            })
            -- 私信按钮
            row:AddChild(UI.Button {
                text = "私信", width = 46, height = 26, fontSize = 12,
                backgroundColor = TC.info,
                onClick = function()
                    pmState_.target = f.name
                    -- 切换到私信 tab（独占模式自动处理）
                    currentSubTab_[PANEL.CHAT] = "私信"
                    Client.SwitchPanel(PANEL.CHAT)
                end,
            })
            -- 删除按钮
            row:AddChild(UI.Button {
                text = "删除", width = 46, height = 26, fontSize = 12,
                backgroundColor = TC.btnPrimary,
                onClick = function()
                    SendToServer(EV.REQ_REMOVE_FRIEND, { TargetUid = f.uid })
                end,
            })
            listContainer:AddChild(row)
        end
    end
    RenderList()
    container:AddChild(listContainer)

    -- 保存刷新回调（收到 PUSH_FRIEND_LIST 时调用）
    ui_.friendListRefresh = RenderList

    return container
end

-- ── 天梯面板 ────────────────────────────────────────────────
local ladderCache_ = {}  -- 缓存天梯推送数据

local function BuildLadderPanel()
    -- 请求最新天梯数据
    SendToServer(EV.REQ_PVP_LADDER_INFO, {})

    local d = ladderCache_
    local container = UI.Panel {
        width = "100%", flexGrow = 1,
        flexDirection = "column", gap = 8,
        paddingHorizontal = 8, paddingVertical = 8,
    }

    -- 赛季信息条
    local seasonBar = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "row", justifyContent = "space-between",
        alignItems = "center",
        padding = { 8, 6, 8, 6 },
        backgroundColor = { 60, 40, 80, 200 },
        borderRadius = 6,
    }
    seasonBar:AddChild(UI.Label {
        text = string.format("第%d赛季", d.season_id or 1),
        fontSize = 14, color = TC.warning,
    })
    seasonBar:AddChild(UI.Label {
        text = string.format("剩余%d天", d.season_days_left or 0),
        fontSize = 13, color = TC.textSecondary,
    })
    container:AddChild(seasonBar)

    -- 段位/积分卡片
    local infoCard = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "column", gap = 6,
        padding = { 12, 10, 12, 10 },
        backgroundColor = TC.bgPanel,
        borderWidth = 1, borderColor = TC.border,
        borderRadius = 6,
    }
    infoCard:AddChild(UI.Label {
        text = d.rank_name or "青铜",
        fontSize = 22, color = TC.textTitle,
        textAlign = "center",
    })
    infoCard:AddChild(UI.Label {
        text = string.format("积分: %d", d.rating or 1000),
        fontSize = 16, color = TC.accent,
        textAlign = "center",
    })
    -- 战绩
    local wins = d.wins or 0
    local losses = d.losses or 0
    local total = wins + losses
    local winRate = total > 0 and math.floor(wins / total * 100) or 0
    infoCard:AddChild(UI.Label {
        text = string.format("战绩: %d胜 %d负 (胜率%d%%)", wins, losses, winRate),
        fontSize = 13, color = TC.textSecondary,
        textAlign = "center",
    })
    infoCard:AddChild(UI.Label {
        text = string.format("赛季最高: %s", d.season_peak_rank or "-"),
        fontSize = 13, color = TC.success,
        textAlign = "center",
    })
    container:AddChild(infoCard)

    -- 剩余次数
    local attemptsLeft = (d.max_attempts or 10) - (d.daily_attempts or 0)
    local attemptsLabel = UI.Label {
        text = string.format("今日剩余次数: %d/%d", attemptsLeft, d.max_attempts or 10),
        fontSize = 13, color = attemptsLeft > 0 and TC.textSecondary or TC.danger,
        textAlign = "center",
    }
    container:AddChild(attemptsLabel)

    -- 匹配按钮
    local matchBtn = UI.Button {
        text = "开始匹配",
        width = 160, height = 40, fontSize = 16,
        backgroundColor = attemptsLeft > 0 and { 140, 50, 50, 230 } or { 60, 60, 60, 200 },
        disabled = attemptsLeft <= 0,
        alignSelf = "center",
        onClick = function()
            if attemptsLeft <= 0 then
                AddLog("今日挑战次数已用完", LOG_COLOR.warning)
                return
            end
            AddLog("正在匹配对手...", LOG_COLOR.system)
            SendToServer(EV.REQ_PVP_LADDER_MATCH, {})
        end,
    }
    container:AddChild(matchBtn)

    -- 赛季奖励提示
    local rewardSection = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "column", gap = 4,
        padding = { 8, 6, 8, 6 },
        backgroundColor = { 40, 50, 60, 180 },
        borderRadius = 6,
        marginTop = 8,
    }
    rewardSection:AddChild(UI.Label {
        text = "赛季奖励", fontSize = 14, color = TC.warning,
    })
    rewardSection:AddChild(UI.Label {
        text = "赛季结束后根据最高段位发放奖励",
        fontSize = 12, color = TC.textSecondary,
    })
    rewardSection:AddChild(UI.Label {
        text = "黄金+: 灵石×50 | 钻石+: 灵石×100 | 大师+: 灵石×200",
        fontSize = 12, color = TC.textSecondary,
    })
    container:AddChild(rewardSection)

    -- 注册刷新回调
    ui_.ladderRefresh = function()
        BuildNavSubPanel(PANEL.JIANGHU, "天梯")
    end

    return container
end

-- ── 活动面板 ────────────────────────────────────────────────
local function BuildActivityPanel()
    -- 打开面板时触发服务端推送活动数据（已签到不会重复奖励，只推送数据）
    SendToServer(EV.REQ_DAILY_SIGN, {})
    -- 用现有缓存先渲染

    local container = UI.Panel {
        width = "100%", flexGrow = 1,
        flexDirection = "column", gap = 8,
        paddingHorizontal = 8, paddingVertical = 8,
    }

    -- 签到区
    local signSection = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "column", gap = 6,
        padding = { 8, 8, 8, 8 },
        backgroundColor = TC.bgPanel,
        borderWidth = 1, borderColor = TC.border,
        borderRadius = 6,
    }
    signSection:AddChild(UI.Label {
        text = "📅 每日签到", fontSize = 16, color = TC.textTitle,
    })
    local streak = activityData_.sign_streak or 0
    local total  = activityData_.total_signs or 0
    local signed = activityData_.signed_today or false
    signSection:AddChild(UI.Label {
        text = string.format("连续签到：%d天 | 累计：%d天", streak, total),
        fontSize = 14, color = TC.textSecondary,
    })
    signSection:AddChild(UI.Label {
        text = string.format("今日奖励：银两+%d%s",
            200 + math.min(streak + 1, 7) * 50,
            (streak + 1) % 7 == 0 and "，灵石+20" or ""),
        fontSize = 13, color = TC.success,
    })
    signSection:AddChild(UI.Button {
        text = signed and "已签到 ✓" or "立即签到",
        width = 120, height = 36, fontSize = 15,
        backgroundColor = signed and { 60, 60, 60, 200 } or { 40, 120, 50, 230 },
        disabled = signed,
        onClick = function()
            if not signed then
                SendToServer(EV.REQ_DAILY_SIGN, {})
            end
        end,
    })
    container:AddChild(signSection)

    -- 限时活动区
    local eventSection = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "column", gap = 4,
        padding = { 8, 8, 8, 8 },
        backgroundColor = TC.bgPanel,
        borderWidth = 1, borderColor = TC.border,
        borderRadius = 6,
    }
    eventSection:AddChild(UI.Label {
        text = "⚔️ 限时活动", fontSize = 16, color = TC.warning,
    })
    eventSection:AddChild(UI.Label {
        text = "• 域外战场·精英首领（每日刷新）",
        fontSize = 14, color = TC.textPrimary,
    })
    eventSection:AddChild(UI.Label {
        text = "• 双倍经验时段：每日 20:00-22:00",
        fontSize = 14, color = TC.textPrimary,
    })
    -- 双倍经验倒计时
    local doubleUntil = activityData_.double_exp_until or 0
    local now = os.time()
    if doubleUntil > now then
        local remaining = doubleUntil - now
        local min = math.floor(remaining / 60)
        eventSection:AddChild(UI.Label {
            text = string.format("🔥 双倍经验剩余：%d分钟", min),
            fontSize = 14, color = TC.textTitle,
        })
    end
    container:AddChild(eventSection)

    -- 福利提示
    local welfareSection = UI.Panel {
        width = "100%", flexShrink = 0,
        flexDirection = "column", gap = 4,
        padding = { 8, 8, 8, 8 },
        backgroundColor = TC.bgPanel,
        borderWidth = 1, borderColor = TC.border,
        borderRadius = 6,
    }
    welfareSection:AddChild(UI.Label {
        text = "🎁 福利提醒", fontSize = 16, color = TC.info,
    })
    welfareSection:AddChild(UI.Label {
        text = "• 顶部「福利」按钮可观看广告获得灵石",
        fontSize = 14, color = TC.textSecondary,
    })
    welfareSection:AddChild(UI.Label {
        text = "• 连续签到7天额外赠送20灵石",
        fontSize = 14, color = TC.textSecondary,
    })
    container:AddChild(welfareSection)

    -- 注册刷新回调，供 PUSH_ACTIVITY_DATA 到达时通知（下次打开面板即刷新）
    ui_.activityRefresh = nil  -- 目前面板采用打开时读缓存模式，无需实时刷新

    return container
end

-- ── 导航子面板（角色/修炼/战斗/江湖/聊天/设置）────────────
-- 子面板内容构建器映射
local SUB_BUILDERS = nil
local function EnsureSubBuilders()
    if SUB_BUILDERS then return end
    SUB_BUILDERS = {
        -- 角色 tab
        ["属性"]  = BuildStatsPanel,
        ["称号"]  = function()
            require("network.TitlePanel").Build({
                UI = UI,
                player = player_,
                Settings = Settings,
                SendToServer = SendToServer,
                EV = EV,
                AddLog = AddLog,
                LOG_COLOR = LOG_COLOR,
                bottomSection = ui_.bottomSection,
            })
        end,
        ["排名"]  = BuildRankPanel,
        -- 修炼 tab
        ["武学"]  = BuildSkillsPanel,
        ["打坐"]  = BuildCultivatePanel,
        ["炼丹"]  = BuildAlchemyPanel,
        ["炼器"]  = BuildForgePanel,
        -- 聊天 tab
        ["世界"]  = function() return BuildChatPanel("世界") end,
        ["门派"]  = BuildSectPanel,
        ["帮会"]  = BuildGuildPanel,
        ["帮会频道"] = function() return BuildChatPanel("帮会频道") end,
        ["私信"]  = BuildPrivateMsgPanel,
        ["系统"]  = function() return BuildChatPanel("系统") end,
        -- 江湖 tab
        ["好友"]  = BuildFriendPanel,
        ["藏书阁"] = BuildLibraryPanel,
        ["天梯"]  = BuildLadderPanel,
        ["活动"]  = BuildActivityPanel,
        -- 设置 tab
        ["音效"]  = BuildSoundPanel,
        ["账号"]  = BuildAccountPanel,
        ["帮助"]  = BuildHelpPanel,
    }
end

BuildNavSubPanel = function(panelId, defaultSub)
    if not ui_.bottomSection then return end
    ui_.bottomSection:ClearChildren()
    -- 切换面板时清空聊天引用，避免访问已销毁控件
    chatUI_.scrollView   = nil
    chatUI_.msgContainer = nil

    local cfg = NAV_PANELS[panelId]
    if not cfg then return end

    -- 恢复上次选中的子 tab（优先使用显式传入的 defaultSub）
    if not defaultSub then
        defaultSub = currentSubTab_[panelId]
    end

    -- 标题行：面板名 + 关闭按钮
    local titleRow = UI.Panel {
        width = "100%", height = 34,
        flexDirection = "row", alignItems = "center",
        justifyContent = "center",
        paddingHorizontal = 10,
        backgroundColor = TC.bgDeep,
        flexShrink = 0,
        borderBottomWidth = 1, borderColor = TC.borderLight,
    }
    titleRow:AddChild(UI.Label {
        text = cfg.title,
        fontSize = 17, fontWeight = "bold",
        color = TC.textPrimary,
        flexGrow = 1, textAlign = "center",
    })
    titleRow:AddChild(UI.Button {
        text = "✕", width = 28, height = 24, fontSize = 15,
        borderRadius = 12,
        backgroundColor = TC.btnPrimary,
        color = TC.danger,
        onClick = function() Client.SwitchPanel(PANEL.MAIN) end,
    })
    ui_.bottomSection:AddChild(titleRow)

    -- 内容区（可滚动，按内容自适应高度，设最大高度防溢出）
    local dpr       = graphics:GetDPR()
    local logH      = graphics:GetHeight() / dpr
    local maxAreaH  = math.max(180, logH - 36 - 44 - 80 - 44 - 30 - 48)
    local contentArea = UI.ScrollView {
        width = "100%", maxHeight = maxAreaH,
        flexShrink = 1,
        scrollY = true,
    }
    -- 按钮引用表（用于切换高亮）
    local subBtns = {}
    -- 仅在调用方显式传入 defaultSub 时才预选；否则留空，用户自己点
    local activeSub = defaultSub

    -- 设置面板额外按钮（前置声明，ShowSubContent 中会追加）
    local settingsExtra = nil

    -- 刷新内容区
    local function ShowSubContent(subName)
        contentArea:ClearChildren()
        EnsureSubBuilders()
        -- 路由到全屏面板
        if subName == "背包" then
            Client.SwitchPanel(PANEL.INVENTORY); return
        elseif subName == "地图" then
            Client.SwitchPanel(PANEL.MAP); return
        end
        -- 有专属构建器
        if SUB_BUILDERS[subName] then
            local panel = SUB_BUILDERS[subName]()
            if panel then contentArea:AddChild(panel) end
        else
            -- 即将开放占位
            contentArea:AddChild(UI.Panel {
                width = "100%", flexGrow = 1,
                alignItems = "center", justifyContent = "center",
            }):AddChild(UI.Label {
                text = subName .. "  功能即将开放",
                fontSize = 17, color = TC.textSecondary,
            })
        end
        -- 设置面板：切换 tab 后追加管理员/教程按钮
        if settingsExtra then
            contentArea:AddChild(settingsExtra)
        end
    end

    -- 功能按钮行（胶囊风格）
    local btnRow = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap",
        gap = 6, padding = 8, flexShrink = 0,
        justifyContent = "center",
    }
    -- 需要红色高亮的子Tab（任务入口/重要功能）
    local HIGHLIGHT_SUBS = { ["天梯"] = true }
    for _, sub in ipairs(cfg.subs) do
        local isActive = (sub == activeSub)
        local isHL = HIGHLIGHT_SUBS[sub]
        local capturedSub = sub
        local bgC, txC, bdC
        if isActive then
            bgC = { 60, 45, 30, 240 }
            txC = { 235, 210, 150, 255 }
            bdC = { 180, 140, 70, 200 }
        elseif isHL then
            bgC = { 50, 18, 15, 230 }
            txC = { 255, 140, 90, 255 }
            bdC = { 200, 80, 50, 200 }
        else
            bgC = { 25, 23, 30, 220 }
            txC = { 170, 160, 145, 255 }
            bdC = { 60, 55, 45, 150 }
        end
        local btn = UI.Button {
            text = sub, height = 30, paddingHorizontal = 14, fontSize = 15,
            fontWeight = "bold",
            borderRadius = 15,
            backgroundColor = bgC,
            color = txC,
            borderWidth = 1,
            borderColor = bdC,
            onClick = function(self_btn)
                -- 重置所有按钮高亮
                for _, b in pairs(subBtns) do
                    b.backgroundColor = TC.bgPanel
                    b.color = { 170, 160, 145, 255 }
                    b.borderColor = TC.borderLight
                end
                -- 激活当前按钮
                self_btn.backgroundColor = TC.bgPanelLight
                self_btn.color = TC.textPrimary
                self_btn.borderColor = TC.borderGold
                activeSub = capturedSub
                currentSubTab_[panelId] = capturedSub  -- 持久记住选择
                Tutorial.Advance("subtab_" .. capturedSub .. "_click")
                ShowSubContent(capturedSub)
            end,
        }
        subBtns[sub] = btn
        Tutorial.RegisterTarget("subtab_" .. sub, btn)
        btnRow:AddChild(btn)
    end
    ui_.bottomSection:AddChild(btnRow)
    ui_.bottomSection:AddChild(contentArea)

    -- 设置面板额外按钮（放入 contentArea 内部，确保可见）
    if panelId == PANEL.SETTINGS then
        settingsExtra = UI.Panel {
            width = "100%",
            flexDirection = "column",
            alignItems = "center",
            gap = 6,
            paddingVertical = 12,
            paddingHorizontal = 8,
        }
        settingsExtra:AddChild(UI.Button {
            text = "重置新手引导",
            width = "80%",
            height = 34, fontSize = 15,
            backgroundColor = TC.btnPrimary,
            color = TC.textAccent,
            borderWidth = 1,
            borderColor = TC.warning,
            onClick = function()
                Tutorial.Reset()  -- 清除教程内部状态，确保步骤1能重新显示
                SendToServer(EV.REQ_RESET_TUTORIAL, {})
                AddLog(">> 正在重置新手引导…", "info")
            end,
        })
        settingsExtra:AddChild(UI.Button {
            text = (player_ and player_.is_admin) and "管理员后台" or "管理员登录",
            width = "80%",
            height = 34, fontSize = 15,
            backgroundColor = TC.bgPanel,
            color = TC.info,
            borderWidth = 1,
            borderColor = TC.border,
            onClick = function()
                if player_ and player_.is_admin then
                    Client.SwitchPanel(PANEL.ADMIN)
                else
                    Client.SwitchPanel("admin_login")
                end
            end,
        })
        contentArea:AddChild(settingsExtra)
    end

    -- 只在调用方显式指定 defaultSub 时才展开内容
    -- 但路由型子tab（会跳全屏面板的）不自动展开，避免打开面板直接跳走
    local ROUTE_SUBS = { ["背包"]=true, ["地图"]=true }
    if activeSub and not ROUTE_SUBS[activeSub] then
        ShowSubContent(activeSub)
    end
end

-- ── 重建主内容区（日志+快捷栏+NPC+bottomSection）────────────
RebuildMainContent = function()
    if not ui_.mainArea then return end
    -- 退出聊天独占模式（恢复 descBar / playerListCol）
    ExitChatExclusiveMode()
    ui_.mainArea:ClearChildren()

    -- ── 战斗模式：隐藏 descBar，中间区显示战斗场景，底部显示技能 ──
    if inBattle_ then
        if ui_.descBar then ui_.descBar:SetVisible(false) end
        -- 战斗期间隐藏左侧玩家列，mainArea 占满全屏，NanoVG 场景居中
        if ui_.playerListCol then ui_.playerListCol:Hide() end

        -- 战斗顶部区（替换 logPanel + quickBar + npcArea）
        print("[REBUILD] 进入战斗模式，调用 BuildBattleTopSection")
        local topSection = BuildBattleTopSection()
        ui_.mainArea:AddChild(topSection)
        print("[REBUILD] topSection 已添加到 mainArea")

        -- 战场信息栏（独立子节点，不被场景区域压缩）
        local infoBarPanel = BuildBattleInfoBar()
        ui_.mainArea:AddChild(infoBarPanel)
        ui_.battleInfoBar = infoBarPanel
        print("[REBUILD] infoBar 已添加到 mainArea（独立节点）")

        -- 底部技能区（替换地图/场景导航）
        local bottomSec = UI.Panel {
            width = "100%",
            flexDirection = "column",
            flexShrink = 0,
            minHeight = 0,
            backgroundColor = TC.bgDeep,
            borderTopWidth = 2,
            borderColor = TC.border,
        }
        ui_.bottomSection = bottomSec
        ui_.mainArea:AddChild(bottomSec)
        BuildBattleSkillSection()

        -- 战斗模式也需要刷新教程卡片（ClearChildren 会销毁之前的卡片）
        Tutorial.RefreshUI(ui_.mainArea)
        return
    end

    -- ── 战场地图激活：NanoVG 全屏渲染，不占 UI 空间 ──
    if BattlefieldMap.IsActive() and mapNvgActive_ then
        if ui_.newsLabel then ui_.newsLabel:SetVisible(false) end
        if ui_.sceneBar then ui_.sceneBar:SetVisible(false) end
        if ui_.descBar then ui_.descBar:SetVisible(false) end
        if ui_.playerListCol then ui_.playerListCol:Hide() end
        if ui_.statusBar then ui_.statusBar:SetVisible(false) end
        if ui_.navBar then ui_.navBar:SetVisible(false) end
        ui_.bottomSection = nil
        -- 大地图由 HandleMapNanoVGRender 渲染，mainArea 保持空
        return
    end

    -- ── 普通模式：恢复所有 bar，清除已销毁的 sceneArea 引用 ──
    battleSceneArea_ = nil
    if ui_.newsLabel then ui_.newsLabel:SetVisible(true) end
    if ui_.sceneBar then ui_.sceneBar:SetVisible(true) end
    if ui_.descBar then ui_.descBar:SetVisible(true) end
    if ui_.statusBar then ui_.statusBar:SetVisible(true) end
    if ui_.navBar then ui_.navBar:SetVisible(true) end
    -- 战斗结束后恢复左侧玩家列
    if ui_.playerListCol then ui_.playerListCol:Show() end

    -- 日志滚动区
    local logPanel = BuildLogPanel()
    ui_.mainArea:AddChild(logPanel)

    -- 刷新教程对日志区域的引用（每次重建 mainArea 后 logContent 会变）
    Tutorial.RefreshUI(ui_.mainArea)

    -- 快捷操作栏
    local quickBar = BuildQuickBar()
    ui_.mainArea:AddChild(quickBar)

    -- NPC 区域（顶部分隔线 + 独立背景色）
    local npcArea = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        paddingHorizontal = 8,
        paddingTop = 4,
        paddingBottom = 6,
        backgroundColor = TC.bgDeep,
        flexShrink = 0,
        borderTopWidth = 2,
        borderColor = TC.border,
        minHeight = 0,
    }
    ui_.npcPanel = npcArea   -- 更新引用，BuildNpcPanel 会立即重建内容
    ui_.mainArea:AddChild(npcArea)
    -- 直接调用过滤版构建，保持逻辑统一
    BuildNpcPanel()

    -- bottomSection（场景地点/子面板；顶部用明显双像素线分隔）
    local bottomSec = UI.Panel {
        width = "100%",
        flexDirection = "column",
        flexShrink = 0,
        minHeight = 0,
        backgroundColor = TC.bgDeep,
        borderTopWidth = 2,
        borderColor = TC.info,
    }
    ui_.bottomSection = bottomSec
    ui_.mainArea:AddChild(bottomSec)

    -- 默认显示场景导航
    BuildSceneNav()
    RefreshPlayerList()

    -- 回到主面板后重新检查教程状态（从设置面板重置后需要这一步）
    if player_ then
        Tutorial.Check()
    end
end

-- 日志面板（PANEL.MAIN 时挂入 mainArea）
-- 结构：日志滚动区（flexGrow=1）+ 快捷行（固定高 36px）
BuildLogPanel = function()
    local scroll = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        minHeight = 0,
        backgroundColor = { 0, 0, 0, 0 },
    }
    local content = UI.Panel {
        width = "100%",
        padding = { 6, 8 },
        gap = 3,
        flexShrink = 0,
    }
    scroll:AddChild(content)
    ui_.logScroll  = scroll
    ui_.logContent = content

    -- 回放已有日志（使用统一的渲染函数，支持颜色标签）
    content:ClearChildren()
    for _, line in ipairs(logLines_) do
        RenderLogLine(content, line)
    end

    -- 布局完成后滚动到最新内容（每帧尝试，持续 10 帧确保 Yoga 排版完成）
    logScrollPending_ = 10

    return scroll
end

local function BuildMainUI()
    -- ── 1. 传闻条（34px）──────────────────────────────────
    local newsBar = UI.Panel {
        width = "100%", height = 30,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = TC.bgDeep,
        paddingHorizontal = 10,
        flexShrink = 0,
        borderBottomWidth = 1,
        borderColor = TC.border,
    }
    local newsTextLabel = UI.Label {
        text = "【传闻】" .. latestNews_,
        fontSize = 14,
        color = TC.textSecondary,
        flexGrow = 1,
    }
    newsBar:AddChild(newsTextLabel)
    ui_.newsLabel = newsBar
    ui_.newsText  = newsTextLabel

    -- ── 2. 全局顶部栏（42px）：🏮时辰 + 场景名 + 福利/活动/+ ──
    local sceneBar = UI.Panel {
        width = "100%", height = 42,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = TC.bgDeep,
        backgroundImage = Theme.TEX_BG_MAIN,
        imageTint = { 255, 255, 255, 40 },
        paddingHorizontal = 8,
        gap = 4,
        flexShrink = 0,
        borderBottomWidth = 1,
        borderColor = TC.borderGold,
    }
    -- 左侧时辰（灯笼emoji + 时辰文字）
    local timeLbl = UI.Label {
        text = GetGameTime(),
        fontSize = 16,
        color = TC.textTitle,
        width = 60,
        flexShrink = 0,
    }
    ui_.timeLabel = timeLbl
    sceneBar:AddChild(timeLbl)

    -- 银两+灵石（胶囊组合，紧跟时辰右侧）
    local currencyGroup = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        height = 26,
        paddingHorizontal = 8,
        borderRadius = 13,
        backgroundColor = TC.bgPanel,
        borderWidth = 1,
        borderColor = TC.border,
        flexShrink = 0,
    }
    local silverLbl = UI.Label {
        text = "💰 0",
        fontSize = 13,
        fontWeight = "bold",
        color = TC.gold,
    }
    ui_.topSilverLabel = silverLbl
    currencyGroup:AddChild(silverLbl)

    -- 分隔竖线
    currencyGroup:AddChild(UI.Panel {
        width = 1, height = 14,
        backgroundColor = TC.borderLight,
    })

    local stoneLbl = UI.Label {
        text = "💎 0",
        fontSize = 13,
        fontWeight = "bold",
        color = TC.rare,
    }
    ui_.topStoneLabel = stoneLbl
    currencyGroup:AddChild(stoneLbl)
    sceneBar:AddChild(currencyGroup)

    -- 场景名（居中 flexGrow）
    local sceneTitle = UI.Label {
        text = "【新手野外】",
        fontSize = 18,
        fontWeight = "bold",
        color = TC.textPrimary,
        flexGrow = 1,
        textAlign = "center",
    }
    ui_.sceneTitle = sceneTitle
    ui_.sceneLabel = sceneTitle
    sceneBar:AddChild(sceneTitle)

    -- 右侧功能按钮（胶囊风格）
    -- 福利按钮：高亮胶囊，点击观看广告获得灵石
    sceneBar:AddChild(UI.Button {
        text = "福利",
        fontSize = 14,
        fontWeight = "bold",
        height = 26,
        paddingHorizontal = 10,
        borderRadius = 13,
        backgroundColor = TC.btnPrimary,
        color = TC.textPrimary,
        borderWidth = 1,
        borderColor = TC.danger,
        onClick = function()
            sdk:ShowRewardVideoAd(function(result)
                if result.success then
                    SendToServer(EV.REQ_AD_REWARD, {})
                else
                    if result.msg == "embed manual close" then
                        AddLog("需完整观看广告才能获得奖励哦~", "warn")
                    else
                        AddLog("广告加载失败，请稍后再试", "warn")
                    end
                end
            end)
        end,
    })
    -- 活动按钮（跳转江湖·活动子面板）
    sceneBar:AddChild(UI.Button {
        text = "活动",
        fontSize = 14,
        fontWeight = "bold",
        height = 26,
        paddingHorizontal = 10,
        borderRadius = 13,
        backgroundColor = TC.btnSecondary,
        color = TC.textPrimary,
        borderWidth = 1,
        borderColor = TC.border,
        onClick = function()
            currentSubTab_[PANEL.JIANGHU] = "活动"
            Client.SwitchPanel(PANEL.JIANGHU)
        end,
    })

    -- ── 3. 场景氛围描述区（水墨淡雅文字）────────────
    local descBar = UI.Panel {
        width = "100%",
        paddingHorizontal = 12,
        paddingVertical = 6,
        backgroundColor = TC.bgDeep,
        flexShrink = 0,
        borderBottomWidth = 1,
        borderColor = TC.borderLight,
    }
    local descLbl = UI.Label {
        text = "微风拂过，草木轻摇，远处隐约传来妖兽低吼...",
        fontSize = 15,
        color = TC.textSecondary,
        flexShrink = 1,
    }
    ui_.sceneDesc = descLbl
    ui_.descBar   = descBar
    descBar:AddChild(descLbl)

    -- ── 4. 中间行（flexGrow=1）：左侧玩家列 + 主内容区 ──
    local middleRow = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        minHeight = 0,
        flexDirection = "row",
        overflow = "hidden",
    }

    -- 左侧同地点玩家列（46px，深色背景）
    local playerListCol = UI.Panel {
        width = 64,
        height = "100%",
        flexShrink = 0,
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 4,
        gap = 3,
        backgroundColor = TC.bgDeep,
        borderRightWidth = 1,
        borderColor = TC.border,
        overflow = "hidden",
    }
    ui_.playerListCol = playerListCol
    middleRow:AddChild(playerListCol)

    -- 主内容区（右侧，flexGrow=1）
    local mainArea = UI.Panel {
        flexGrow = 1,
        flexShrink = 1,
        minHeight = 0,
        flexDirection = "column",
        backgroundColor = TC.bgPanel,
        backgroundImage = Theme.TEX_BG_MAIN,
        imageTint = { 255, 255, 255, 30 },
        overflow = "hidden",
    }
    ui_.mainArea = mainArea
    middleRow:AddChild(mainArea)

    -- ── 5. 状态栏（46px）：lv+name + 气血/内力 两条 ──
    local statusBar = UI.Panel {
        width = "100%", height = 46,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = TC.bgDeep,
        backgroundImage = Theme.TEX_BG_MAIN,
        imageTint = { 255, 255, 255, 35 },
        paddingHorizontal = 8,
        gap = 6,
        flexShrink = 0,
        borderTopWidth = 1,
        borderColor = TC.borderGold,
    }

    -- 境界+名字（格式：练气一层·侠客）
    local lvLabel = UI.Label {
        text = "练气一层·侠客",
        fontSize = 12,
        fontWeight = "bold",
        color = TC.textTitle,
        flexShrink = 0,
    }
    ui_.statusLabel = lvLabel
    statusBar:AddChild(lvLabel)

    -- 气血组（红色）
    local hpGroup = UI.Panel {
        flexGrow = 1, flexDirection = "row",
        alignItems = "center", gap = 4,
    }
    local hpLbl = UI.Label {
        text = "气血", fontSize = 13,
        color = TC.danger, flexShrink = 0,
    }
    local hpTrack, hpFill = MakeBar(TC.barBg, { 190, 55, 45, 255 })
    hpGroup:AddChild(hpLbl)
    hpGroup:AddChild(hpTrack)
    statusBar:AddChild(hpGroup)
    ui_.hpLabel = hpLbl
    ui_.hpBar   = hpFill

    -- 内力组（蓝色）
    local mpGroup = UI.Panel {
        flexGrow = 1, flexDirection = "row",
        alignItems = "center", gap = 4,
    }
    local mpLbl = UI.Label {
        text = "内力", fontSize = 13,
        color = TC.info, flexShrink = 0,
    }
    local mpTrack, mpFill = MakeBar(TC.barBg, { 70, 130, 200, 255 })
    mpGroup:AddChild(mpLbl)
    mpGroup:AddChild(mpTrack)
    statusBar:AddChild(mpGroup)
    ui_.mpLabel = mpLbl
    ui_.mpBar   = mpFill


    -- ── 6. 底部导航栏（50px，角色/修炼/战斗/江湖/聊天/设置+管理）──
    local navBar = UI.Panel {
        width = "100%", height = 50,
        flexDirection = "row",
        backgroundColor = TC.bgDeep,
        backgroundImage = Theme.TEX_BG_MAIN,
        imageTint = { 255, 255, 255, 35 },
        flexShrink = 0,
        alignItems = "center",
        justifyContent = "center",
        paddingHorizontal = 4,
        gap = 6,
        borderTopWidth = 1,
        borderColor = TC.borderGold,
    }
    local navItems = {
        { label = "角色", panel = PANEL.SKILLS,    event = "nav_skills_click"   },
        { label = "修炼", panel = PANEL.CULTIVATE, event = "nav_cultivate_click" },
        { label = "战斗", panel = PANEL.BATTLE,    event = "nav_battle_click"   },
        { label = "江湖", panel = PANEL.JIANGHU,   event = nil                  },
        { label = "聊天", panel = PANEL.CHAT,      event = nil                  },
        { label = "设置", panel = PANEL.SETTINGS,  event = nil                  },
    }
    for _, item in ipairs(navItems) do
        local p   = item.panel
        local evt = item.event
        local lbl = item.label
        local btn = UI.Button {
            text = lbl,
            flex = 1,
            height = 36,
            fontSize = 16,
            fontWeight = "bold",
            borderRadius = 18,
            backgroundColor = TC.bgPanel,
            color = TC.textPrimary,
            borderWidth = 1,
            borderColor = TC.border,
            onClick = function()
                if evt then Tutorial.Advance(evt) end
                Client.SwitchPanel(p)
            end,
        }
        -- 注册为可高亮目标
        Tutorial.RegisterTarget("nav_" .. lbl, btn)
        navBar:AddChild(btn)
    end


    -- ── 7. 根容器 ──────────────────────────────────────────
    local root = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        backgroundColor = TC.bgDeep,
        backgroundImage = Theme.TEX_BG_MAIN,
        imageTint = { 255, 255, 255, 20 },
        overflow = "hidden",
    }
    root:AddChild(newsBar)
    root:AddChild(sceneBar)
    root:AddChild(descBar)
    root:AddChild(middleRow)

    root:AddChild(statusBar)

    -- 大境界进度百分比条（状态栏下方）
    local realmPctBar = UI.Panel {
        width = "100%", height = 16,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = TC.bgDeep,
        paddingHorizontal = 8,
        flexShrink = 0,
    }
    local realmPctLabel = UI.Label {
        text = "",
        fontSize = 11,
        color = TC.textMuted,
    }
    ui_.realmPctLabel = realmPctLabel
    realmPctBar:AddChild(realmPctLabel)
    root:AddChild(realmPctBar)

    root:AddChild(navBar)

    -- 保存引用供地图全屏时隐藏
    ui_.sceneBar  = sceneBar
    ui_.statusBar = statusBar
    ui_.navBar    = navBar

    return root
end

-- ============================================================================
-- Client._BuildAndShowGameUI - 构建并显示主游戏 UI（EntryFlow 结束后调用）
-- ============================================================================

function Client._BuildAndShowGameUI()
    print("[Client] 构建主游戏 UI...")
    -- ★ 重新订阅 Update 事件（EntryFlow._Finish 中 UnsubscribeFromEvent("Update") 会清除所有 Update 订阅）
    SubscribeToEvent("Update", "Client_HandleUpdate")
    local root = BuildMainUI()
    UI.SetRoot(root)
    ui_.root = root  -- 保存引用，域外战场等全屏场景需要挂载浮层到根节点
    RebuildMainContent()
    BuildSceneNav()

    -- 初始化教程系统（UI 构建完成后，ui_ 引用已全部就绪）
    Tutorial.Init({
        mainArea = ui_.mainArea,
    })

    -- 刷新状态（玩家数据可能在 EntryFlow 期间已到达）
    if player_ then
        UpdateStatusBar()
        Tutorial.UpdatePlayer(player_)
        Tutorial.Check()
    end

    -- 回放 EntryFlow 期间缓存的事件
    FlushPendingEvents()

    -- 显示离线奖励（entryFlow期间到达的数据延迟到此处显示）
    Client._ShowOfflineRewards()

    print("[Client] 主游戏 UI 构建完成")
end

-- ============================================================================
-- Client.Start / Stop
-- ============================================================================

function Client.Start()
    print("[Client] 启动客户端...")

    -- ⚠️ 必须最先注册所有事件处理函数！
    -- Persistent world 模式：服务端可能在客户端脚本启动前就完成了 ClientIdentity
    -- 并推送了 INIT_PLAYER / PUSH_PLAYER_DATA，若此时未订阅则消息永久丢失。
    Shared.RegisterClientEvents()
    SubscribeToEvent(EV.INIT_PLAYER,       "Client_OnInitPlayer")
    SubscribeToEvent(EV.PUSH_PLAYER_DATA,  "Client_OnPushPlayerData")
    SubscribeToEvent(EV.PUSH_EXP_UPDATE,   "Client_OnPushExpUpdate")
    SubscribeToEvent(EV.PUSH_INVENTORY,    "Client_OnPushInventory")
    SubscribeToEvent(EV.PUSH_GAME_LOG,     "Client_OnPushGameLog")
    SubscribeToEvent(EV.NPC_DIALOG,        "Client_OnNpcDialog")
    SubscribeToEvent(EV.NPC_SKILL_GRANT,   "Client_OnNpcSkillGrant")
    SubscribeToEvent(EV.PUSH_BATTLE_STATE, "Client_OnPushBattleState")
    SubscribeToEvent(EV.PUSH_BATTLE_END,   "Client_OnPushBattleEnd")
    SubscribeToEvent(EV.PUSH_MARKET_DATA,  "Client_OnPushMarketData")
    SubscribeToEvent(EV.ADMIN_LOGIN_RESULT,"Client_OnAdminLoginResult")
    SubscribeToEvent(EV.PUSH_SHOP_DATA,     "Client_OnPushShopData")
    SubscribeToEvent(EV.PUSH_SPOT_PLAYERS,  "Client_OnPushSpotPlayers")
    SubscribeToEvent(EV.PUSH_MARKET_HISTORY,    "Client_OnPushMarketHistory")
    SubscribeToEvent(EV.PUSH_MARKET_TRENDS,     "Client_OnPushMarketTrends")
    SubscribeToEvent(EV.PUSH_NEWS_UPDATE,       "Client_OnPushNewsUpdate")
    SubscribeToEvent(EV.PUSH_ADMIN_PLAYER_INFO, "Client_OnPushAdminPlayerInfo")
    SubscribeToEvent(EV.PUSH_ADMIN_RESULT,      "Client_OnPushAdminResult")
    SubscribeToEvent(EV.PUSH_ADMIN_PLAYER_LIST, "Client_OnPushAdminPlayerList")
    SubscribeToEvent(EV.PUSH_RANK,              "Client_OnPushRank")
    SubscribeToEvent(EV.PUSH_CHAT_MSG,          "Client_OnPushChatMsg")
    SubscribeToEvent(EV.PUSH_CHAT_HISTORY,      "Client_OnPushChatHistory")
    SubscribeToEvent(EV.PUSH_LOOT_RESULT,       "Client_OnPushLootResult")
    SubscribeToEvent(EV.PUSH_AD_REWARD,        "Client_OnPushAdReward")
    SubscribeToEvent(EV.PUSH_BREAKTHROUGH,     "Client_OnPushBreakthrough")
    SubscribeToEvent(EV.PUSH_ALCHEMY_RESULT,   "Client_OnPushAlchemyResult")
    SubscribeToEvent(EV.PUSH_REALM_PILL_SHOP,  "Client_OnPushRealmPillShop")
    SubscribeToEvent(EV.PUSH_REALM_PILL_RESULT,"Client_OnPushRealmPillResult")
    SubscribeToEvent(EV.RES_ENTER_LAYER,        "Client_OnResEnterLayer")
    SubscribeToEvent(EV.RES_FORGE_CRAFT,        "Client_OnResForgeCraft")
    SubscribeToEvent(EV.RES_BUY_BLUEPRINT,      "Client_OnResBuyBlueprint")
    SubscribeToEvent(EV.RES_FORGE_NEW,           "Client_OnResForgeNew")
    SubscribeToEvent(EV.RES_CREATE_GUILD,       "Client_OnResCreateGuild")
    SubscribeToEvent(EV.RES_GUILD_INFO,         "Client_OnResGuildInfo")
    SubscribeToEvent(EV.RES_JOIN_GUILD,         "Client_OnResJoinGuild")
    SubscribeToEvent(EV.RES_LEAVE_GUILD,        "Client_OnResLeaveGuild")
    SubscribeToEvent(EV.RES_SET_GUILD_NOTICE,  "Client_OnResSetGuildNotice")
    SubscribeToEvent(EV.RES_GUILD_LIST,          "Client_OnResGuildList")
    SubscribeToEvent(EV.RES_KICK_MEMBER,        "Client_OnResKickMember")
    SubscribeToEvent(EV.RES_TRANSFER_LEADER,   "Client_OnResTransferLeader")
    SubscribeToEvent(EV.NOTIFY_GUILD_ONLINE,    "Client_OnNotifyGuildOnline")
    -- 帮会等级/职位/日常事件
    SubscribeToEvent(EV.RES_GUILD_DONATE,      "Client_OnResGuildDonate")
    SubscribeToEvent(EV.RES_GUILD_UPGRADE,     "Client_OnResGuildUpgrade")
    SubscribeToEvent(EV.RES_SET_GUILD_ROLE,    "Client_OnResSetGuildRole")
    SubscribeToEvent(EV.RES_GUILD_DAILY,       "Client_OnResGuildDaily")
    SubscribeToEvent(EV.RES_CLAIM_GUILD_TASK,  "Client_OnResClaimGuildTask")
    -- 领地战事件
    SubscribeToEvent(EV.RES_STRONGPOINT_LIST,    "Client_OnResStrongpointList")
    SubscribeToEvent(EV.RES_ATTACK_STRONGPOINT,  "Client_OnResAttackStrongpoint")
    SubscribeToEvent(EV.RES_SWITCH_STRONGPOINT, "Client_OnResSwitchStrongpoint")
    SubscribeToEvent(EV.RES_DEFEND_STRONGPOINT,  "Client_OnResDefendStrongpoint")
    SubscribeToEvent(EV.RES_PVP_CHALLENGE,       "Client_OnResPvpChallenge")
    SubscribeToEvent(EV.NOTIFY_WAR_START,        "Client_OnNotifyWarStart")
    SubscribeToEvent(EV.NOTIFY_WAR_END,          "Client_OnNotifyWarEnd")
    SubscribeToEvent(EV.NOTIFY_UNDER_ATTACK,     "Client_OnNotifyUnderAttack")
    SubscribeToEvent(EV.NOTIFY_SP_CAPTURED,      "Client_OnNotifySpCaptured")
    -- 域外战场·大地图同步事件
    SubscribeToEvent(EV.RES_LAYER_SNAPSHOT,     "Client_OnResLayerSnapshot")
    SubscribeToEvent(EV.NOTIFY_PLAYER_POS,      "Client_OnNotifyPlayerPos")
    SubscribeToEvent(EV.NOTIFY_PLAYER_ENTER,    "Client_OnNotifyPlayerEnter")
    SubscribeToEvent(EV.NOTIFY_PLAYER_LEAVE,    "Client_OnNotifyPlayerLeave")
    SubscribeToEvent(EV.NOTIFY_MONSTER_DEAD,    "Client_OnNotifyMonsterDead")
    SubscribeToEvent(EV.NOTIFY_MONSTER_SYNC,    "Client_OnNotifyMonsterSync")
    SubscribeToEvent(EV.NOTIFY_MONSTER_SPAWN,   "Client_OnNotifyMonsterSpawn")
    SubscribeToEvent(EV.NOTIFY_BATTLE_TRIGGER,  "Client_OnNotifyBattleTrigger")
    -- 任务系统事件
    SubscribeToEvent(EV.PUSH_QUEST_UPDATE,      "Client_OnPushQuestUpdate")
    SubscribeToEvent(EV.PUSH_QUEST_COMPLETE,    "Client_OnPushQuestComplete")
    SubscribeToEvent(EV.RES_QUEST_INFO,         "Client_OnResQuestInfo")
    -- 好友系统
    SubscribeToEvent(EV.PUSH_FRIEND_LIST,       "Client_OnPushFriendList")
    -- 天梯系统
    SubscribeToEvent(EV.PUSH_PVP_LADDER_DATA,   "Client_OnPushPvpLadderData")
    SubscribeToEvent(EV.RES_PVP_LADDER_MATCH,   "Client_OnResPvpLadderMatch")
    -- 活动系统
    SubscribeToEvent(EV.PUSH_ACTIVITY_DATA,     "Client_OnPushActivityData")
    -- 灵石改名
    SubscribeToEvent(EV.RES_RENAME,             "Client_OnResRename")
    SubscribeToEvent(EV.RES_GUILD_RENAME,       "Client_OnResGuildRename")
    -- 角色创建
    SubscribeToEvent(EV.RES_CREATE_CHARACTER,   "Client_OnResCreateCharacter")

    SubscribeToEvent("Connected",               "Client_OnConnected")
    SubscribeToEvent("ConnectionFailed",   "Client_OnConnectionFailed")
    SubscribeToEvent("ServerDisconnected", "Client_OnServerDisconnected")

    -- 订阅 Update 事件（时辰更新）
    SubscribeToEvent("Update", "Client_HandleUpdate")

    -- 域外战场：事件级点击检测（绕过 GetMouseButtonPress 轮询）
    SubscribeToEvent("MouseButtonDown", "Client_MapMouseDown")

    -- 初始化 UI 框架（事件注册后再构建，确保收到数据时处理函数已就绪）
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
                bold   = "Fonts/MiSans-Regular.ttf",
            } },
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 显示欢迎页（所有玩家每次进入都先看到欢迎页）
    entryFlowActive_ = true
    EntryFlow.Show({
        conn = nil,  -- 连接可能还没建立，OnInitPlayer 中会传入
        isNew = false,  -- 默认老玩家；OnInitPlayer 收到 _needCreate 时会切换为新玩家流程
        onComplete = function()
            entryFlowActive_ = false
            Client._BuildAndShowGameUI()
        end,
    })

    -- UI 标记就绪（EntryFlow 也算 UI，事件可以开始处理）
    uiReady_ = true
    FlushPendingEvents()

    print("[Client] EntryFlow 欢迎页已显示，等待服务器连接")

    -- Persistent world：连接可能在脚本启动前就已建立，补发 CLIENT_READY
    local existingConn = network:GetServerConnection()
    if existingConn and existingConn:IsConnected() then
        print("[Client] 连接已就绪（启动前建立），直接初始化")
        serverConn_ = existingConn
        EntryFlow.SetConn(serverConn_)
        SendToServer(EV.CLIENT_READY)
    end

    -- 背景音乐
    local bgmScene = Scene()
    local bgmNode = bgmScene:CreateChild("BGM")
    local bgmSource = bgmNode:CreateComponent("SoundSource")
    bgmSource.soundType = SOUND_MUSIC
    bgmSource.gain = 0.4
    local bgmTown = cache:GetResource("Sound", "audio/music_1780329458038.ogg")
    local bgmBattle = cache:GetResource("Sound", "audio/music_1780330016001.ogg")
    if bgmTown then bgmTown.looped = true end
    if bgmBattle then bgmBattle.looped = true end
    if bgmTown then
        bgmSource:Play(bgmTown)
        print("[Client] BGM 开始播放（主城）")
    end
    ui_.bgmSource = bgmSource
    ui_.bgmScene = bgmScene
    ui_.bgmTown = bgmTown
    ui_.bgmBattle = bgmBattle
    ui_.bgmCurrent = "town"

    -- 战斗音效（SFX）
    local sfxNode = bgmScene:CreateChild("SFX")
    local sfxSource = sfxNode:CreateComponent("SoundSource")
    sfxSource.soundType = SOUND_EFFECT
    sfxSource.gain = 0.6
    ui_.sfxSource = sfxSource
    ui_.sfx = {
        attack  = cache:GetResource("Sound", "audio/sfx/sfx_attack.ogg"),
        hit     = cache:GetResource("Sound", "audio/sfx/sfx_hit.ogg"),
        crit    = cache:GetResource("Sound", "audio/sfx/sfx_crit.ogg"),
        victory = cache:GetResource("Sound", "audio/sfx/sfx_victory.ogg"),
        defeat  = cache:GetResource("Sound", "audio/sfx/sfx_defeat.ogg"),
    }
    print("[Client] 战斗音效加载完成")
end

function Client.SwitchBGM(track)
    if not ui_.bgmSource then return end
    if track == ui_.bgmCurrent then return end
    if track == "battle" and ui_.bgmBattle then
        ui_.bgmSource:Play(ui_.bgmBattle)
        ui_.bgmCurrent = "battle"
    elseif track == "town" and ui_.bgmTown then
        ui_.bgmSource:Play(ui_.bgmTown)
        ui_.bgmCurrent = "town"
    end
end

PlaySFX = function(name)
    if not ui_.sfxSource or not ui_.sfx then return end
    local snd = ui_.sfx[name]
    if snd then ui_.sfxSource:Play(snd) end
end

function Client.Stop()
    UI.Shutdown()
    print("[Client] 客户端已停止")
end

-- ============================================================================
-- 全局事件处理函数（供 SubscribeToEvent 回调）
-- ============================================================================

function Client_OnConnected(eventType, eventData)
    serverConn_ = network:GetServerConnection()
    -- 通知 EntryFlow 连接已就绪
    if entryFlowActive_ then
        EntryFlow.SetConn(serverConn_)
    end
    SendToServer(EV.CLIENT_READY)
end

function Client_OnConnectionFailed(eventType, eventData)
    AddLog("连接服务器失败！请检查网络。", "danger")
end

function Client_OnServerDisconnected(eventType, eventData)
    AddLog("与服务器断开连接...", "danger")
end

-- 将 eventData 的字段提取为普通 Lua table（UI 就绪前缓存用）
local function SnapshotEventData(eventData, fields)
    local snap = {}
    for _, f in ipairs(fields) do
        local ftype = f[2]
        if ftype == "string" then
            snap[f[1]] = eventData:GetString(f[1])
        elseif ftype == "int" then
            snap[f[1]] = eventData:GetInt(f[1])
        elseif ftype == "bool" then
            snap[f[1]] = eventData:GetBool(f[1])
        end
    end
    return snap
end

-- 快照 eventData 包装器，让缓存的数据支持 GetString/GetInt/GetBool
local function MakeFakeEventData(snap)
    return setmetatable({}, {
        __index = function(_, k)
            -- 兼容 eventData:GetString(key) / eventData:GetInt(key) 调用方式
            return {
                GetString = function() return snap[k] or "" end,
                GetInt    = function() return snap[k] or 0 end,
                GetBool   = function() return snap[k] or false end,
            }
        end,
        GetString = function(_, k) return snap[k] or "" end,
        GetInt    = function(_, k) return snap[k] or 0 end,
        GetBool   = function(_, k) return snap[k] or false end,
    })
end

-- UI 就绪后，回放所有缓存的事件（前向声明在文件顶部）
FlushPendingEvents = function()
    if #pendingEvents_ == 0 then return end
    print(string.format("[Client] 回放 %d 条缓存事件", #pendingEvents_))
    for _, ev in ipairs(pendingEvents_) do
        local fakeED = MakeFakeEventData(ev.snap)
        ev.handler(nil, fakeED)
    end
    pendingEvents_ = {}
end

-- 公共调度器：UI 未就绪则缓存，就绪则直接调用
local function Dispatch(handler, eventType, eventData, fields)
    if uiReady_ then
        handler(eventType, eventData)
    else
        local snap = SnapshotEventData(eventData, fields)
        table.insert(pendingEvents_, { handler = handler, snap = snap })
        print("[Client] UI 未就绪，缓存事件 #" .. #pendingEvents_)
    end
end

-- 事件字段映射表（合并为单表以节省 local 槽位）
Client._F = {
    INIT_PLAYER       = { {"data_json","string"}, {"offline_rewards_json","string"} },
    PUSH_PLAYER       = { {"data_json","string"} },
    PUSH_INVENTORY    = { {"items_json","string"} },
    PUSH_GAME_LOG     = { {"text","string"}, {"color","string"} },
    NPC_DIALOG        = { {"npc_name","string"}, {"dialog","string"}, {"options_json","string"} },
    NPC_SKILL_GRANT   = { {"skills_json","string"} },
    PUSH_BATTLE_STATE = {
        {"Log","string"},
        {"PlayerHp","int"}, {"PlayerHpMax","int"},
        {"PlayerMp","int"}, {"PlayerMpMax","int"},
        {"MonsterName","string"}, {"MonsterHp","int"}, {"MonsterHpMax","int"},
        {"AutoFight","bool"}, {"Cooldowns","string"}, {"Round","int"},
        {"FirstAttacker","string"},
    },
    PUSH_BATTLE_END   = { {"Win","bool"}, {"Log","string"}, {"ExpGain","int"}, {"SilverGain","int"} },
    PUSH_MARKET_DATA  = { {"listings_json","string"}, {"page","int"}, {"total_pages","int"} },
    ADMIN_LOGIN_RESULT = { {"Success","bool"} },
    PUSH_SHOP_DATA    = { {"ShopType","string"}, {"ShopTitle","string"}, {"Items","string"}, {"Currency","string"} },
    PUSH_MARKET_HISTORY = { {"history_json","string"} },
    PUSH_MARKET_TRENDS  = { {"trends_json","string"} },
    PUSH_NEWS_UPDATE  = { {"Text","string"} },
    PUSH_ADMIN_PLAYER_INFO = { {"info_json","string"} },
    PUSH_ADMIN_RESULT = { {"Ok","bool"}, {"Msg","string"} },
    PUSH_ADMIN_PLAYER_LIST = { {"list_json","string"}, {"total","int"}, {"page","int"}, {"page_size","int"}, {"mode","string"} },
    PUSH_CHAT_MSG     = { {"MsgJson","string"} },
    PUSH_CHAT_HISTORY = { {"HistoryJson","string"} },
    -- 好友系统
    PUSH_FRIEND_LIST  = { {"FriendsJson","string"} },
    -- 活动系统
    PUSH_ACTIVITY_DATA = { {"DataJson","string"} },
    PUSH_REALM_PILL_SHOP   = { {"PillsJson","string"}, {"DailyUsed","int"}, {"DailyLimit","int"} },
    PUSH_REALM_PILL_RESULT = { {"Ok","bool"}, {"Msg","string"}, {"Action","string"} },
    PUSH_EXP_UPDATE        = { {"realm_exp","int"}, {"realm","int"}, {"realm_layer","int"} },
}

function Client_OnInitPlayer(eventType, eventData)
    Dispatch(OnInitPlayer, eventType, eventData, Client._F.INIT_PLAYER)
end

function Client_OnPushPlayerData(eventType, eventData)
    Dispatch(OnPushPlayerData, eventType, eventData, Client._F.PUSH_PLAYER)
end

function Client_OnPushExpUpdate(eventType, eventData)
    Dispatch(OnPushExpUpdate, eventType, eventData, Client._F.PUSH_EXP_UPDATE)
end

function Client_OnPushInventory(eventType, eventData)
    Dispatch(OnPushInventory, eventType, eventData, Client._F.PUSH_INVENTORY)
end

function Client_OnPushGameLog(eventType, eventData)
    Dispatch(OnPushGameLog, eventType, eventData, Client._F.PUSH_GAME_LOG)
end

function Client_OnNpcDialog(eventType, eventData)
    Dispatch(OnNpcDialog, eventType, eventData, Client._F.NPC_DIALOG)
end

function Client_OnNpcSkillGrant(eventType, eventData)
    Dispatch(OnNpcSkillGrant, eventType, eventData, Client._F.NPC_SKILL_GRANT)
end

function Client_OnPushBattleState(eventType, eventData)
    Dispatch(OnPushBattleState, eventType, eventData, Client._F.PUSH_BATTLE_STATE)
end

function Client_OnPushBattleEnd(eventType, eventData)
    print("[Client] Client_OnPushBattleEnd 收到事件，uiReady_=" .. tostring(uiReady_))
    Dispatch(OnPushBattleEnd, eventType, eventData, Client._F.PUSH_BATTLE_END)
end

function Client_OnPushMarketData(eventType, eventData)
    Dispatch(OnPushMarketData, eventType, eventData, Client._F.PUSH_MARKET_DATA)
end

function Client_OnAdminLoginResult(eventType, eventData)
    Dispatch(OnAdminLoginResult, eventType, eventData, Client._F.ADMIN_LOGIN_RESULT)
end

function Client_OnPushShopData(eventType, eventData)
    Dispatch(OnPushShopData, eventType, eventData, Client._F.PUSH_SHOP_DATA)
end

function Client_OnPushMarketHistory(eventType, eventData)
    Dispatch(OnPushMarketHistory, eventType, eventData, Client._F.PUSH_MARKET_HISTORY)
end
function Client_OnPushMarketTrends(eventType, eventData)
    print("[Client] Client_OnPushMarketTrends DISPATCH")
    Dispatch(OnPushMarketTrends, eventType, eventData, Client._F.PUSH_MARKET_TRENDS)
end

function Client_OnPushNewsUpdate(eventType, eventData)
    Dispatch(OnPushNewsUpdate, eventType, eventData, Client._F.PUSH_NEWS_UPDATE)
end

function Client_OnPushAdminPlayerInfo(eventType, eventData)
    Dispatch(OnPushAdminPlayerInfo, eventType, eventData, Client._F.PUSH_ADMIN_PLAYER_INFO)
end

function Client_OnPushAdminResult(eventType, eventData)
    Dispatch(OnPushAdminResult, eventType, eventData, Client._F.PUSH_ADMIN_RESULT)
end

function Client_OnPushAdminPlayerList(eventType, eventData)
    Dispatch(OnPushAdminPlayerList, eventType, eventData, Client._F.PUSH_ADMIN_PLAYER_LIST)
end

-- 接收排行榜数据（多类型）
function Client_OnPushRank(eventType, eventData)
    local json = eventData["RankJson"]:GetString()
    local ok, data = pcall(cjson.decode, json)
    if not ok or type(data) ~= "table" then return end

    local rankType = "power"
    if eventData["RankType"] then
        rankType = eventData["RankType"]:GetString()
    end
    rankData_[rankType] = data
    -- 如果当前正处于江湖面板且正在看该类型排行，刷新显示
    if currentPanel_ == PANEL.JIANGHU and rankCurrentTab_ == rankType then
        BuildNavSubPanel(PANEL.JIANGHU, "排名")
    end
end

-- 接收聊天单条消息
function Client_OnPushChatMsg(eventType, eventData)
    Dispatch(OnPushChatMsg, eventType, eventData, Client._F.PUSH_CHAT_MSG)
end

-- 接收聊天历史（上线时批量推送）
function Client_OnPushChatHistory(eventType, eventData)
    Dispatch(OnPushChatHistory, eventType, eventData, Client._F.PUSH_CHAT_HISTORY)
end

-- ── 好友列表推送 ──────────────────────────────────────────────
function Client_OnPushFriendList(eventType, eventData)
    local json = eventData["FriendsJson"]:GetString()
    local ok, list = pcall(cjson.decode, json)
    if ok and type(list) == "table" then
        friendList_ = list
        -- 如果好友面板已打开，刷新UI
        if ui_.friendListRefresh then
            pcall(ui_.friendListRefresh)
        end
    end
end

-- ── 天梯数据推送 ──────────────────────────────────────────────
function Client_OnPushPvpLadderData(eventType, eventData)
    local json = eventData["DataJson"]:GetString()
    local ok, data = pcall(cjson.decode, json)
    if ok and type(data) == "table" then
        ladderCache_ = data
        if ui_.ladderRefresh then
            pcall(ui_.ladderRefresh)
        end
    end
end

function Client_OnResPvpLadderMatch(eventType, eventData)
    local json = eventData["DataJson"]:GetString()
    local ok, data = pcall(cjson.decode, json)
    if not ok or type(data) ~= "table" then return end

    if data.error then
        AddLog(data.error, LOG_COLOR.warning)
        return
    end

    if data.started then
        -- 服务端已开始PvP战斗，战斗流程走Combat系统
        AddLog(string.format("匹配成功！对手: %s (%s %d分)",
            data.opponent_name or "???",
            data.opponent_rank or "?",
            data.opponent_rating or 0), LOG_COLOR.system)
    end
end

-- ── 活动数据推送 ──────────────────────────────────────────────
function Client_OnPushActivityData(eventType, eventData)
    local json = eventData["DataJson"]:GetString()
    local ok, data = pcall(cjson.decode, json)
    if ok and type(data) == "table" then
        activityData_ = data
        -- 如果活动面板已打开，刷新UI
        if ui_.activityRefresh then
            pcall(ui_.activityRefresh)
        end
    end
end

-- 接收同场景玩家小地点列表
function Client_OnPushSpotPlayers(eventType, eventData)
    local json = eventData["Players"]:GetString()
    local ok, list = pcall(cjson.decode, json)
    if not ok or type(list) ~= "table" then return end
    sameSpotPlayers_ = list
    RefreshPlayerList()
end

-- 战利品拾取结果回调
function Client_OnPushLootResult(eventType, eventData)
    local success  = eventData:GetBool("Success")
    local itemName = eventData:GetString("ItemName") or ""
    if success then
        AddLog(">> 拾取成功：" .. itemName .. " 已放入背包！", "good")
    else
        AddLog(">> 拾取失败，物品已过期或不存在。", "warn")
    end
end

function Client_OnPushAdReward(eventType, eventData)
    local success = eventData:GetBool("Success")
    local amount  = eventData:GetInt("Amount")
    local msg     = eventData:GetString("Msg")
    if success then
        AddLog("【福利】观看广告成功，获得 " .. amount .. " 灵石！", "good")
        if player_ then
            player_.spirit_stone = (player_.spirit_stone or 0) + amount
        end
    else
        AddLog("【福利】" .. (msg or "领取失败"), "warn")
    end
end

-- ── 境界突破结果 ──
function Client_OnPushBreakthrough(eventType, eventData)
    local success = eventData:GetBool("Success")
    local msg     = eventData:GetString("Msg")
    local newRealm = eventData:GetInt("Realm")
    local newLayer = eventData:GetInt("Layer")

    if success then
        local newName = Settings.REALM.GetDisplayName(newRealm, newLayer)
        AddLog(string.format("【突破成功】%s", msg ~= "" and msg or ("进入" .. newName)), "good")
        if player_ then
            player_.realm = newRealm
            player_.realm_layer = newLayer
            player_.realm_exp = 0
            player_.realm_name = newName
            player_.realm_exp_max = Settings.REALM.GetExpNeeded(newRealm, newLayer)
            UpdateStatusBar()
        end
    else
        AddLog("【突破失败】" .. (msg ~= "" and msg or "突破失败，修为受损。"), "warning")
        if player_ then
            player_.realm_layer = newLayer
            player_.realm_name = Settings.REALM.GetDisplayName(player_.realm or 1, newLayer)
            UpdateStatusBar()
        end
    end
    -- 刷新当前面板（服务端也会 PushPlayerData，但先即时更新）
    if currentPanel_ == PANEL.SKILLS then
        Client.SwitchPanel(currentPanel_)
    end
end

-- ── 炼丹结果 ──
function Client_OnPushAlchemyResult(eventType, eventData)
    local success = eventData:GetBool("Success")
    local pillId  = eventData:GetString("PillId")
    local count   = eventData:GetInt("Count")
    local msg     = eventData:GetString("Msg")

    if success then
        local pillDef = Settings.PILLS[pillId]
        local pillName = pillDef and pillDef.name or pillId
        AddLog(string.format("【炼丹成功】%s", msg ~= "" and msg or (pillName .. "×" .. count)), "good")
    else
        AddLog("【炼丹失败】" .. (msg ~= "" and msg or "炼丹失败，材料已损耗。"), "warning")
    end
    -- 服务端会 PushPlayerData + PushInventory 来刷新数据，面板会自动更新
    if currentPanel_ == PANEL.CULTIVATE then
        Client.SwitchPanel(currentPanel_)
    end
end

-- ========== 修为丹药铺事件处理 ==========
function Client_OnPushRealmPillShop(eventType, eventData)
    local pillsJson = eventData:GetString("PillsJson")
    local dailyUsed = eventData:GetInt("DailyUsed")
    local dailyLimit = eventData:GetInt("DailyLimit")

    local ok, pills = pcall(cjson.decode, pillsJson)
    if not ok or type(pills) ~= "table" then
        AddLog("[药铺] 数据解析失败", "danger")
        return
    end

    realmPillShopData_ = {
        pills = pills,
        dailyUsed = dailyUsed,
        dailyLimit = dailyLimit,
    }

    Client.SwitchPanel(PANEL.REALM_PILL)
end

function Client_OnPushRealmPillResult(eventType, eventData)
    local ok   = eventData:GetBool("Ok")
    local msg  = eventData:GetString("Msg")
    local action = eventData:GetString("Action")

    if ok then
        AddLog("【药铺】" .. msg, "good")
        -- 购买/服用成功后刷新药铺（如果当前面板是药铺）
        if action == "use" and realmPillShopData_ then
            realmPillShopData_.dailyUsed = (realmPillShopData_.dailyUsed or 0) + 1
        end
        -- 重建面板刷新显示
        if currentPanel_ == PANEL.REALM_PILL then
            Client.SwitchPanel(PANEL.REALM_PILL)
        end
    else
        AddLog("【药铺】" .. (msg ~= "" and msg or "操作失败"), "warning")
    end
end

-- ★ 地图点击事件处理（事件驱动，不依赖 GetMouseButtonPress 轮询）
-- 原因：UI 框架全屏根元素消费了 native UI 的 hit-test，导致 GetMouseButtonPress 轮询失效
function Client_MapMouseDown(eventType, eventData)
    local btn = eventData:GetInt("Button")
    local x   = eventData:GetInt("X")
    local y   = eventData:GetInt("Y")

    -- 只处理左键点击 + 地图活跃状态
    if btn ~= MOUSEB_LEFT then return end
    if not mapNvgActive_ then return end
    if not (BattlefieldMap and BattlefieldMap.IsActive and BattlefieldMap.IsActive()) then return end

    local dpr = graphics:GetDPR()
    local mouseX = x / dpr
    local mouseY = y / dpr

    local clickAction = BattlefieldMap.OnClick(mouseX, mouseY)

    if clickAction == "back" then
        if not mapNvgActive_ then
            StrongholdPanel.Hide()
            BattlefieldMap.Deactivate()
            Client.SwitchBGM("town")
        end
    elseif clickAction == "battle" then
        StrongholdPanel.Hide()
    end
end

-- 时辰更新（每帧累加，每10秒刷新一次时辰标签）
function Client_HandleUpdate(eventType, eventData)
    local dt = eventData:GetFloat("TimeStep")
    gameTimeElapsed_ = gameTimeElapsed_ + dt
    timeUpdateTimer_ = timeUpdateTimer_ + dt

    if timeUpdateTimer_ >= 10.0 then
        timeUpdateTimer_ = 0
        if ui_.timeLabel then
            ui_.timeLabel.text = GetGameTime()
        end
    end

    -- 帮会信息加载重试
    if (ui_.guildRetryTimer or 0) > 0 then
        ui_.guildRetryTimer = ui_.guildRetryTimer - dt
        if ui_.guildRetryTimer <= 0 then
            ui_.guildRetryTimer = 0
            SendToServer(EV.REQ_GUILD_INFO, {})
        end
    end

    -- 任务完成 Toast 自动消失
    if questState_.completeMsgTimer > 0 then
        questState_.completeMsgTimer = questState_.completeMsgTimer - dt
        if questState_.completeMsgTimer <= 0 then
            questState_.completeMsg = nil
            if ui_.questToast and ui_.questToast.Remove then
                ui_.questToast:Remove()
                ui_.questToast = nil
            end
        end
    end

    -- 新手教程结束后延迟自动打开任务面板
    if (questState_.guideTimer or 0) > 0 then
        questState_.guideTimer = questState_.guideTimer - dt
        if questState_.guideTimer <= 0 then
            questState_.guideTimer = 0
            SendToServer(EV.REQ_QUEST_INFO_REQ, {})
            Client.ShowQuestPanel()
        end
    end

    -- ── 域外战场大地图每帧更新 ──
    if mapNvgActive_ and BattlefieldMap.IsActive() then
        local action = BattlefieldMap.Update(dt)
        if action == "sync" then
            -- 向服务端同步位置
            local mx, my = BattlefieldMap.GetMyPosition()
            SendToServer(EV.REQ_MAP_MOVE, {
                X = math.floor(mx),
                Y = math.floor(my),
            })
        elseif action == "battle" then
            -- 战斗触发由 onBattle 回调处理，这里暂停地图渲染
            mapNvgActive_ = false
            StrongholdPanel.Hide()
        end

        -- 据点面板自动隐藏：走出交互范围时关闭
        if StrongholdPanel.IsVisible() then
            local nearSp = BattlefieldMap.GetNearStrongpoint()
            if nearSp ~= StrongholdPanel.GetCurrentSpId() then
                StrongholdPanel.Hide()
            end
        end

        -- 点击处理已迁移到 Client_DiagMouseDown 事件（GetMouseButtonPress 被 UI 层消费，不可用）
        -- 移动端触摸同样会触发 MouseButtonDown 事件，无需额外处理
    end

    -- 延迟滚动日志到底部（每帧尝试，持续 10 帧确保 Yoga 排版完成）
    if logScrollPending_ and logScrollPending_ > 0 then
        logScrollPending_ = logScrollPending_ - 1
        if ui_.logScroll then
            ui_.logScroll:ScrollToBottom()
        end
        if logScrollPending_ <= 0 then
            logScrollPending_ = nil
        end
    end

end

-- ============================================================================
-- 域外战场进入结果
-- ============================================================================
function Client_OnResEnterLayer(eventType, eventData)
    local ok    = eventData:GetBool("Success")
    local msg   = eventData:GetString("Msg")
    local layer = eventData:GetInt("Layer")
    if ok then
        AddLog(string.format("【域外战场】成功进入第%d层！%s", layer, msg), "good")
        viewingBattlefieldLayers_ = false
        currentPanel_ = PANEL.MAIN

        -- ★ 初始化 NanoVG 大地图上下文（首次）
        if not vg_map_ then
            vg_map_ = nvgCreate(1)
            nvgCreateFont(vg_map_, "sans", "Fonts/MiSans-Regular.ttf")
        end
        -- ★ 每次进入战场层都重新订阅（Boss战等场景会覆盖此事件为 HandleBattleNanoVGRender）
        SubscribeToEvent("NanoVGRender", "HandleMapNanoVGRender")

        -- ★ 激活大地图（NanoVG 全屏渲染，不需要 UI panel）
        Client.SwitchBGM("battle")
        BattlefieldMap.Activate(layer, {
            onBattle = function(monsterId)
                AddLog(">> 踩到妖兽，发起战斗！", "warn")
                SendToServer(EV.REQ_START_BATTLE, { MonsterId = monsterId })
                inBattle_ = true
                battleState_ = nil
                skillCooldowns_ = {}
                mapNvgActive_ = false  -- 暂停地图渲染
                StrongholdPanel.Hide()  -- 确保据点面板关闭
                -- 清除更换据点确认弹窗
                BattlefieldMap.HideConfirmDialog()
                Client.SwitchPanel(PANEL.BATTLE)
            end,
            onBack = function()
                -- 如果更换据点确认弹窗正在显示，先关闭弹窗不退出地图
                if BattlefieldMap.IsConfirmDialogVisible() then
                    BattlefieldMap.HideConfirmDialog()
                    return
                end
                AddLog("离开战场层，返回层选择...", "system")
                mapNvgActive_ = false
                StrongholdPanel.Hide()
                BattlefieldMap.Deactivate()
                Client.SwitchBGM("town")
                -- 返回域外战场层选择面板（而非主页）
                currentPanel_ = PANEL.MAP
                viewingBattlefieldLayers_ = true
                local mainArea = ui_.mainArea
                if mainArea then
                    mainArea:RemoveAllChildren()
                    mainArea:AddChild(UI.Button {
                        text = "← 返回上一页",
                        height = 32,
                        paddingHorizontal = 14,
                        fontSize = 16,
                        fontWeight = "bold",
                        borderRadius = 16,
                        backgroundColor = TC.bgPanelLight,
                        borderWidth = 1,
                        borderColor = TC.borderLight,
                        color = TC.textPrimary,
                        marginBottom = 4,
                        marginHorizontal = 6,
                        marginTop = 4,
                        flexShrink = 0,
                        onClick = function()
                            viewingBattlefieldLayers_ = false
                            currentPanel_ = PANEL.MAIN
                            RebuildMainContent()
                            BuildSceneNav()
                        end,
                    })
                    mainArea:AddChild(BuildBattlefieldLayerPanel())
                end
            end,
            onCleared = function()
                AddLog("【域外战场】本层妖兽已全部清除！", "good")
            end,
            onStrongpoint = function(spId)
                -- 据点面板操作按钮点击：发起占领/进攻
                print("[Client] onStrongpoint action: " .. tostring(spId))
                AddLog("【据点】正在发起占领请求...", "info")
                SendToServer(EV.REQ_ATTACK_STRONGPOINT, { SpId = spId })
            end,
            getQuestState = function()
                return questState_
            end,
        }, vg_map_)
        mapNvgActive_ = true

        -- 初始化据点交互面板（挂到 UI 层顶部覆盖）
        Client.InitStrongholdPanel()

        -- 隐藏外围 bar，让 NanoVG 地图全屏
        if ui_.newsLabel then ui_.newsLabel:SetVisible(false) end
        if ui_.sceneBar then ui_.sceneBar:SetVisible(false) end
        if ui_.descBar then ui_.descBar:SetVisible(false) end
        if ui_.playerListCol then ui_.playerListCol:Hide() end
        if ui_.statusBar then ui_.statusBar:SetVisible(false) end
        if ui_.navBar then ui_.navBar:SetVisible(false) end

        -- 清空主面板（大地图用 NanoVG 全屏绘制，不占 UI 空间）
        if ui_.mainArea then
            ui_.mainArea:ClearChildren()
            ui_.bottomSection = nil
        end

        -- 进入战场时请求任务数据（由 NanoVG 地图层绘制任务列表）
        SendToServer(EV.REQ_QUEST_INFO_REQ, {})
    else
        AddLog("【域外战场】" .. msg, "warning")
    end
    -- 服务端 PushPlayerData 会自动刷新场景
end

-- ============================================================================
-- 域外战场·大地图同步事件处理
-- ============================================================================

--- 层快照（进入层时收到完整状态）
function Client_OnResLayerSnapshot(eventType, eventData)
    if not BattlefieldMap.IsActive() then return end
    local playersStr      = eventData:GetString("Players")      -- "uid|x|y|name|guild\n..."
    local monstersStr     = eventData:GetString("Monsters")     -- "uid|x|y|monId|alive\n..."
    local strongpointsStr = eventData:GetString("Strongpoints") -- "spId|guildName|guildId\n..."

    -- 解析玩家列表
    local players = {}
    if playersStr ~= "" then
        for line in playersStr:gmatch("[^\n]+") do
            local uid, x, y, name, guild = line:match("([^|]+)|([^|]+)|([^|]+)|([^|]*)|?(.*)")
            if uid then
                players[uid] = {
                    x = tonumber(x) or 0,
                    y = tonumber(y) or 0,
                    name = name or "?",
                    guildName = guild or "",
                }
            end
        end
    end

    -- 解析怪物列表（新格式：uid|x|y|monId|alive）
    local monsters = {}
    if monstersStr ~= "" then
        for line in monstersStr:gmatch("[^\n]+") do
            local mUid, mx, my, monId, alive = line:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)")
            if mUid then
                monsters[mUid] = {
                    x = tonumber(mx) or 0,
                    y = tonumber(my) or 0,
                    monId = monId,
                    alive = alive == "1",
                }
            end
        end
    end

    -- 解析据点归属
    local spOwners = nil
    if strongpointsStr ~= "" then
        spOwners = {}
        for line in strongpointsStr:gmatch("[^\n]+") do
            local spId, gName, gId = line:match("([^|]+)|([^|]*)|?(.*)")
            if spId then
                spOwners[spId] = {
                    guild_name = gName or "",
                    guild_id = gId or "",
                }
            end
        end
    end

    BattlefieldMap.SetSnapshot(players, monsters, spOwners)
    -- DEBUG: 打印据点归属数据
    local spCount = 0
    local ownedCount = 0
    if spOwners then
        for spId, info in pairs(spOwners) do
            spCount = spCount + 1
            if info.guild_name ~= "" then
                ownedCount = ownedCount + 1
                print(string.format("[MapSync] 据点归属: %s -> 帮会「%s」(id=%s)", spId, info.guild_name, info.guild_id))
            end
        end
    end
    print(string.format("[MapSync] 收到层快照: %d个玩家, %d个怪物, %d个据点(%d有主)",
        playersStr ~= "" and select(2, playersStr:gsub("\n","")) + 1 or 0,
        monstersStr ~= "" and select(2, monstersStr:gsub("\n","")) + 1 or 0,
        spCount, ownedCount))

end

--- 定时位置广播（每200ms，同层所有玩家位置）
function Client_OnNotifyPlayerPos(eventType, eventData)
    if not BattlefieldMap.IsActive() then return end
    local data = eventData:GetString("Data")  -- "uid|x|y\nuid|x|y\n..."
    if data == "" then return end

    for line in data:gmatch("[^\n]+") do
        local uid, x, y = line:match("([^|]+)|([^|]+)|([^|]+)")
        if uid then
            BattlefieldMap.UpdatePlayerPos(uid, tonumber(x) or 0, tonumber(y) or 0, nil, nil)
        end
    end
end

--- 新玩家进入本层
function Client_OnNotifyPlayerEnter(eventType, eventData)
    if not BattlefieldMap.IsActive() then return end
    local uid   = eventData:GetString("Uid")
    local name  = eventData:GetString("Name")
    local guild = eventData:GetString("Guild")
    local x     = eventData:GetInt("X")
    local y     = eventData:GetInt("Y")
    BattlefieldMap.UpdatePlayerPos(uid, x, y, name, guild)
    AddLog(string.format("【战场】%s 进入了本层", name), "system")
end

--- 玩家离开本层
function Client_OnNotifyPlayerLeave(eventType, eventData)
    if not BattlefieldMap.IsActive() then return end
    local uid  = eventData:GetString("Uid")
    local name = eventData:GetString("Name")
    BattlefieldMap.RemovePlayer(uid)
    if name ~= "" then
        AddLog(string.format("【战场】%s 离开了本层", name), "system")
    end
end

--- 怪物被击杀通知（服务端 MonsterManager 广播）
function Client_OnNotifyMonsterDead(eventType, eventData)
    if not BattlefieldMap.IsActive() then return end
    local monsterUid = eventData:GetString("MonsterUid")
    BattlefieldMap.RemoveMonster(monsterUid)
end

--- 怪物位置批量同步（每 300ms 服务端广播）
function Client_OnNotifyMonsterSync(eventType, eventData)
    if not BattlefieldMap.IsActive() then return end
    local data = eventData:GetString("Data")  -- "uid|x|y|monId|alive\n..."
    if data == "" then return end
    BattlefieldMap.SyncMonsters(data)
end

--- 新怪物刷出通知
function Client_OnNotifyMonsterSpawn(eventType, eventData)
    if not BattlefieldMap.IsActive() then return end
    local uid   = eventData:GetString("Uid")
    local x     = eventData:GetFloat("X")
    local y     = eventData:GetFloat("Y")
    local monId = eventData:GetString("MonId")
    BattlefieldMap.AddMonster(uid, x, y, monId)
end

--- 服务端触发战斗通知（怪物碰到玩家，服务端权威判定）
function Client_OnNotifyBattleTrigger(eventType, eventData)
    local monsterUid = eventData:GetString("MonsterUid")
    local monsterId  = eventData:GetString("MonsterId")
    -- 客户端只需进入战斗画面，战斗逻辑由服务端 Combat 驱动
    print(string.format("[Client] 服务端触发战斗: monster=%s id=%s", monsterUid, monsterId))
end

-- ============================================================================
-- 炼器结果
-- ============================================================================
function Client_OnResForgeCraft(eventType, eventData)
    local success = eventData:GetBool("Success")
    local msg     = eventData:GetString("Msg")
    if success then
        AddLog("【锻造成功】" .. msg, "good")
    else
        AddLog("【锻造失败】" .. msg, "warning")
    end
    if currentPanel_ == PANEL.CULTIVATE then
        Client.SwitchPanel(currentPanel_)
    end
end

-- ============================================================================
-- 新炼器系统·事件响应
-- ============================================================================
function Client_OnResBuyBlueprint(eventType, eventData)
    local success = eventData:GetBool("Success")
    local msg     = eventData:GetString("Msg")
    if success then
        local bpId = eventData:GetString("BlueprintId")
        -- 本地立即更新（不等 PushPlayerData）
        if player_ then
            if not player_.blueprints_learned then
                player_.blueprints_learned = {}
            end
            player_.blueprints_learned[bpId] = true
        end
        AddLog("【藏书阁】" .. msg, "good")
        AddLog("  可前往【修炼→炼器】锻造装备", "system")
    else
        AddLog("【藏书阁】" .. msg, "warning")
    end
    -- 刷新当前面板（购买后按钮变为"已购买"）
    if currentPanel_ == PANEL.JIANGHU then
        Client.SwitchPanel(currentPanel_)
    end
end

function Client_OnResForgeNew(eventType, eventData)
    local success = eventData:GetBool("Success")
    local msg     = eventData:GetString("Msg")
    if success then
        AddLog("【炼器】" .. msg, "good")
        -- 解析返回的装备列表（可选，主要用于日志展示）
        local itemsJson = eventData:GetString("Items")
        if itemsJson and itemsJson ~= "" then
            local ok, items = pcall(cjson.decode, itemsJson)
            if ok and items then
                for _, item in ipairs(items) do
                    local q = item.quality or 1
                    local qualityColor = "white"
                    if q >= 5 then qualityColor = "orange"
                    elseif q == 4 then qualityColor = "purple"
                    elseif q == 3 then qualityColor = "blue"
                    elseif q == 2 then qualityColor = "green"
                    end
                    local qDef = Settings.EQUIPMENT_QUALITY[q]
                    local qName = qDef and qDef.name or "普通"
                    AddLog(string.format("  <%s>获得: %s [%s]</%s>", qualityColor, item.name or "装备", qName, qualityColor), "system")
                end
            end
        end
    else
        AddLog("【炼器】" .. msg, "warning")
    end
    -- 刷新修炼面板（更新保底计数和材料）
    if currentPanel_ == PANEL.CULTIVATE then
        Client.SwitchPanel(currentPanel_)
    end
end

-- ============================================================================
-- 帮会事件响应
-- ============================================================================
function Client_OnResCreateGuild(eventType, eventData)
    local ok  = eventData:GetBool("Success")
    local msg = eventData:GetString("Msg")
    if ok then
        -- 立即更新本地玩家帮会状态（不等 PushPlayerData）
        local guildId   = eventData:GetString("GuildId")
        local guildName = eventData:GetString("GuildName")
        if player_ and guildId ~= "" then
            player_.guild_id   = guildId
            player_.guild_name = guildName
        end
        AddLog("【帮会】" .. msg, "good")
    else
        AddLog("【帮会】" .. msg, "warning")
    end
    if currentPanel_ == PANEL.JIANGHU then
        Client.SwitchPanel(currentPanel_)
    end
end

function Client_OnResGuildInfo(eventType, eventData)
    local ok  = eventData:GetBool("Success")
    local msg = eventData:GetString("Msg")
    if not ok then
        if msg == "LOADING" then
            -- 帮会数据还在加载，设置重试计时器
            ui_.guildRetryTimer = 1.5
            return
        end
        AddLog("【帮会】" .. (msg or "查询失败"), "warning")
        return
    end
    local json = eventData["InfoJson"]:GetString()
    local decOk, info = pcall(cjson.decode, json)
    if not decOk or type(info) ~= "table" then
        AddLog("【帮会】数据解析失败", "warning")
        return
    end
    cachedGuildInfo_ = info
    -- 如果当前在帮会面板，刷新显示
    if currentPanel_ == PANEL.JIANGHU then
        BuildNavSubPanel(PANEL.JIANGHU, "帮会")
    end
end

function Client_OnResJoinGuild(eventType, eventData)
    local ok  = eventData:GetBool("Success")
    local msg = eventData:GetString("Msg")
    if ok then
        AddLog("【帮会】" .. msg, "good")
    else
        AddLog("【帮会】" .. msg, "warning")
    end
    if currentPanel_ == PANEL.JIANGHU then
        Client.SwitchPanel(currentPanel_)
    end
end

function Client_OnResLeaveGuild(eventType, eventData)
    local ok  = eventData:GetBool("Success")
    local msg = eventData:GetString("Msg")
    if ok then
        AddLog("【帮会】已退出帮会", "good")
        cachedGuildInfo_ = nil
    else
        AddLog("【帮会】" .. (msg or "退出失败"), "warning")
    end
    if currentPanel_ == PANEL.JIANGHU then
        Client.SwitchPanel(currentPanel_)
    end
end

function Client_OnResSetGuildNotice(eventType, eventData)
    local ok = eventData:GetBool("Success")
    if ok then
        -- 刷新帮会信息
        SendToServer(EV.REQ_GUILD_INFO, {})
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- 帮会列表浏览
-- ═══════════════════════════════════════════════════════════════════

function Client_OnResGuildList(eventType, eventData)
    local ok = eventData:GetBool("Success")
    if not ok then return end
    local listJson = eventData:GetString("ListJson")
    local list = cjson.decode(listJson) or {}

    -- 弹出帮会列表面板（作为模态或替换当前面板）
    Client.ShowGuildListPanel(list)
end

function Client.ShowGuildListPanel(list)
    local container = UI.Panel {
        width = "100%",
        padding = 8,
        gap = 6,
    }

    container:AddChild(UI.Label {
        text = "── 帮会列表 ──",
        fontSize = 17,
        color = LOG_COLOR.title,
        marginBottom = 4,
        alignSelf = "center",
    })

    if #list == 0 then
        container:AddChild(UI.Label {
            text = "暂无帮会，成为第一个创建者吧！",
            fontSize = 14, color = TC.textSecondary,
            alignSelf = "center", marginTop = 20,
        })
    else
        for _, g in ipairs(list) do
            local isFull = g.member_count >= g.max_members
            container:AddChild(UI.Panel {
                width = "100%",
                backgroundColor = TC.bgPanel,
                padding = 8, borderRadius = 4, marginTop = 4, gap = 3,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = "【" .. g.name .. "】",
                                fontSize = 14, color = TC.info,
                            },
                            UI.Label {
                                text = string.format("%d/%d人", g.member_count, g.max_members),
                                fontSize = 12, color = isFull and { 200, 80, 80, 255 } or { 160, 220, 160, 255 },
                            },
                        },
                    },
                    UI.Label {
                        text = "帮主：" .. (g.leader_name or "?"),
                        fontSize = 12, color = LOG_COLOR.gold,
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Label {
                                text = g.notice ~= "" and ("公告：" .. g.notice) or "",
                                fontSize = 11, color = TC.textSecondary, flexShrink = 1,
                            },
                            UI.Button {
                                text = isFull and "已满员" or "申请加入",
                                fontSize = 11, paddingHorizontal = 10, paddingVertical = 4,
                                backgroundColor = isFull and { 80, 80, 80, 255 } or { 50, 100, 60, 255 },
                                borderRadius = 3,
                                disabled = isFull,
                                onClick = function()
                                    if not isFull then
                                        SendToServer(EV.REQ_JOIN_GUILD, { GuildId = g.id })
                                        AddLog(string.format(">> 申请加入帮会【%s】...", g.name), "system")
                                    end
                                end,
                            },
                        },
                    },
                },
            })
        end
    end

    -- 返回按钮
    container:AddChild(UI.Button {
        text = "返回",
        fontSize = 13, height = 30, width = "100%",
        backgroundColor = TC.btnSecondary, marginTop = 10,
        onClick = function()
            Client.SwitchPanel("帮会")
        end,
    })

    -- 替换当前面板内容
    if ui_ and ui_.bottomSection then
        ui_.bottomSection:ClearChildren()
        ui_.bottomSection:AddChild(container)
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- 踢人/转让帮主 结果处理
-- ═══════════════════════════════════════════════════════════════════

function Client_OnResKickMember(eventType, eventData)
    local ok = eventData:GetBool("Success")
    if ok then
        -- 刷新帮会面板
        SendToServer(EV.REQ_GUILD_INFO, {})
    end
end

function Client_OnResTransferLeader(eventType, eventData)
    local ok = eventData:GetBool("Success")
    if ok then
        -- 刷新帮会面板
        SendToServer(EV.REQ_GUILD_INFO, {})
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- 帮会成员上下线通知
-- ═══════════════════════════════════════════════════════════════════

function Client_OnNotifyGuildOnline(eventType, eventData)
    local playerName = eventData:GetString("PlayerName")
    local isOnline = eventData:GetBool("IsOnline")
    local status = isOnline and "上线" or "下线"
    AddLog(string.format("<帮会> %s已%s", playerName, status), "guild")
end

-- 帮会捐献响应
function Client_OnResGuildDonate(eventType, eventData)
    local ok = eventData:GetBool("Success")
    if ok then
        -- 服务端已通过 PushLog 发送成功消息，这里只刷新数据
        SendToServer(EV.REQ_GUILD_INFO, {})
        SendToServer(EV.REQ_GUILD_DAILY, {})
    end
end

-- 玩家改名响应
function Client_OnResRename(eventType, eventData)
    local ok = eventData:GetBool("Success")
    local msg = eventData:GetString("Msg")
    if ok then
        local newName = eventData:GetString("NewName")
        if player_ and newName ~= "" then
            player_.name = newName
        end
        AddLog("改名成功！新名字：" .. (newName or ""), "good")
    else
        AddLog("改名失败：" .. (msg ~= "" and msg or "未知原因"), "warning")
    end
end

-- 帮会改名响应
function Client_OnResGuildRename(eventType, eventData)
    local ok = eventData:GetBool("Success")
    local msg = eventData:GetString("Msg")
    if ok then
        local newName = eventData:GetString("NewName")
        AddLog("帮会改名成功！新名称：" .. (newName or ""), "good")
        SendToServer(EV.REQ_GUILD_INFO, {})
    else
        AddLog("帮会改名失败：" .. (msg ~= "" and msg or "未知原因"), "warning")
    end
end

-- 角色创建响应
function Client_OnResCreateCharacter(eventType, eventData)
    EntryFlow.OnCreateResult(eventType, eventData)
end

-- 帮会升级响应
function Client_OnResGuildUpgrade(eventType, eventData)
    local ok = eventData:GetBool("Success")
    if ok then
        SendToServer(EV.REQ_GUILD_INFO, {})
    end
end

-- 设置职位响应
function Client_OnResSetGuildRole(eventType, eventData)
    local ok = eventData:GetBool("Success")
    if ok then
        SendToServer(EV.REQ_GUILD_INFO, {})
    end
end

-- 日常任务列表响应
function Client_OnResGuildDaily(eventType, eventData)
    local ok = eventData:GetBool("Success")
    if not ok then return end
    local json = eventData:GetString("DataJson")
    local decOk, daily = pcall(cjson.decode, json)
    if decOk and type(daily) == "table" then
        -- 服务端返回数组 [{id, progress, claimed}...]，转为 map { [id]={count,claimed} }
        local map = {}
        for _, t in ipairs(daily) do
            map[t.id] = { count = t.progress or 0, claimed = t.claimed or false }
        end
        cachedGuildDaily_ = map
        if currentPanel_ == PANEL.JIANGHU then
            BuildNavSubPanel(PANEL.JIANGHU, "帮会")
        end
    end
end

-- 领取日常任务奖励响应
function Client_OnResClaimGuildTask(eventType, eventData)
    local ok  = eventData:GetBool("Success")
    local msg = eventData:GetString("Msg")
    if ok then
        AddLog("【帮会】" .. msg, "good")
        SendToServer(EV.REQ_GUILD_DAILY, {})
    else
        AddLog("【帮会】" .. (msg or "领取失败"), "warning")
    end
end


-- ═══════════════════════════════════════════════════════════════════
-- 领地战 客户端事件处理
-- ═══════════════════════════════════════════════════════════════════

--- 缓存据点列表数据
cachedStrongpoints_ = {}  -- layer -> { list of sp data }
cachedWarActive_ = false

function Client_OnResStrongpointList(eventType, eventData)
    local layer = eventData:GetInt("Layer")
    local data  = eventData:GetString("Data")
    local warActive = eventData:GetBool("WarActive")
    local list = {}
    -- 解析管道分隔格式：id|name|bonus_type|bonus_value|ownerName|desc
    for line in data:gmatch("[^\n]+") do
        local id, name, bonus, value, owner, desc = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(.*)$")
        if id then
            list[#list + 1] = {
                id    = id,
                name  = name,
                bonus = bonus,
                value = tonumber(value) or 0,
                owner = owner,
                desc  = desc or "",
            }
        end
    end
    cachedStrongpoints_[layer] = list
    cachedWarActive_ = warActive
    AddLog("【领地】已获取第" .. layer .. "层据点信息（" .. #list .. "个据点）", "info")
    -- 如果当前在据点面板则刷新
    if ui_.strongpointPanel then
        BuildStrongpointContent(layer)
    end
end

function Client_OnResAttackStrongpoint(eventType, eventData)
    local ok  = eventData:GetBool("Success")
    local msg = eventData:GetString("Msg")
    print("[Client] RES_ATTACK_STRONGPOINT ok=" .. tostring(ok) .. " msg=" .. tostring(msg))
    if ok then
        AddLog("【领地战】" .. msg, "good")
        BattlefieldMap.ShowToast(msg)
        StrongholdPanel.OnResponse(true, msg)
        -- 检查是否有防守者可选
        local noDefender = eventData:GetBool("NoDefender")
        if noDefender then
            -- 无人防守，启动客户端占领倒计时显示
            local spName = eventData:GetString("SpName")
            local capSec = eventData:GetInt("CaptureSec")
            if capSec <= 0 then capSec = 10 end
            BattlefieldMap.StartCaptureTimer(spName ~= "" and spName or "据点", capSec)
        else
            local defData = eventData:GetString("Defenders")
            if defData and defData ~= "" then
                ShowPvpTargetSelection(defData)
            end
        end
    else
        -- 检查是否是「帮会已有据点，需要确认更换」的情况
        local hasExisting = eventData:GetBool("HasExisting")
        if hasExisting then
            -- 如果地图已关闭，忽略（防止弹窗出现在主界面）
            if not BattlefieldMap.IsActive() then
                print("[Client] 地图已关闭，忽略据点更换确认")
                return
            end
            local existSpId   = eventData:GetString("ExistingSpId")
            local existSpName = eventData:GetString("ExistingSpName")
            -- 优先使用服务端传回的目标据点ID（面板可能已隐藏导致GetCurrentSpId为nil）
            local targetSpId  = eventData:GetString("TargetSpId")
            if not targetSpId or targetSpId == "" then
                targetSpId = StrongholdPanel.GetCurrentSpId() or ""
            end
            -- 显示确认更换弹窗
            Client.ShowSwitchConfirmDialog(targetSpId, existSpName)
        else
            AddLog("【领地战】" .. msg, "warning")
            BattlefieldMap.ShowToast(msg)
            StrongholdPanel.OnResponse(false, msg)
        end
    end
end

--- 显示更换据点确认弹窗
function Client.ShowSwitchConfirmDialog(targetSpId, existSpName)
    print("[Client] 确认更换弹窗: target=" .. tostring(targetSpId) .. " exist=" .. tostring(existSpName))

    -- 使用 BattlefieldMap 的 NanoVG 层渲染确认对话框（UI 库在地图模式下不可见）
    BattlefieldMap.ShowConfirmDialog({
        title = "更换据点确认",
        message = "已拥有「" .. (existSpName or "?") .. "」，确认更换？（24h限1次）",
        onConfirm = function()
            print("[Client] 确认更换据点: " .. tostring(targetSpId))
            SendToServer(EV.REQ_SWITCH_STRONGPOINT, { SpId = targetSpId })
            BattlefieldMap.ShowToast("正在更换据点...")
        end,
        onCancel = function()
            print("[Client] 取消更换据点")
        end,
    })
end
--- 更换据点响应处理
function Client_OnResSwitchStrongpoint(eventType, eventData)
    local ok  = eventData:GetBool("Success")
    local msg = eventData:GetString("Msg")
    print("[Client] RES_SWITCH_STRONGPOINT ok=" .. tostring(ok) .. " msg=" .. tostring(msg))
    if ok then
        AddLog("【领地战】" .. msg, "good")
        -- 不显示 Toast，避免遮挡进度条（进度环已充分表达状态）
        StrongholdPanel.OnResponse(true, msg)
        -- 启动占领倒计时（更换模式）
        local spName = eventData:GetString("SpName")
        local capSec = eventData:GetInt("CaptureSec")
        if capSec <= 0 then capSec = 10 end
        BattlefieldMap.StartCaptureTimer("更换→" .. (spName ~= "" and spName or "据点"), capSec)
    else
        AddLog("【领地战】" .. msg, "warning")
        BattlefieldMap.ShowToast(msg)
        StrongholdPanel.OnResponse(false, msg)
    end
end

function Client_OnResDefendStrongpoint(eventType, eventData)
    local ok  = eventData:GetBool("Success")
    local msg = eventData:GetString("Msg")
    if ok then
        AddLog("【领地战】" .. msg, "good")
        StrongholdPanel.OnResponse(true, msg)
    else
        AddLog("【领地战】" .. msg, "warning")
        StrongholdPanel.OnResponse(false, msg)
    end
end

function Client_OnResPvpChallenge(eventType, eventData)
    local ok  = eventData:GetBool("Success")
    local msg = eventData:GetString("Msg")
    if ok then
        AddLog("【领地战·PvP】" .. msg, "good")
    else
        AddLog("【领地战·PvP】" .. msg, "warning")
    end
end

function Client_OnNotifyWarStart(eventType, eventData)
    AddLog("【领地战】⚔ 领地争夺战已开始！（20:00-21:00）", "warning")
end

function Client_OnNotifyWarEnd(eventType, eventData)
    AddLog("【领地战】🏁 领地争夺战已结束", "info")
end

function Client_OnNotifyUnderAttack(eventType, eventData)
    local spName      = eventData:GetString("SpName")
    local attackGuild = eventData:GetString("AttackerGuild")
    AddLog("【领地战】⚠ 据点「" .. spName .. "」正在被「" .. attackGuild .. "」进攻！", "warning")
end

function Client_OnNotifySpCaptured(eventType, eventData)
    local spName   = eventData:GetString("SpName")
    local newOwner = eventData:GetString("NewOwner")
    local newOwnerId = eventData:GetString("NewOwnerId")
    local spId     = eventData:GetString("SpId")
    local oldSpId  = eventData:GetString("OldSpId")  -- 更换据点时释放的旧据点
    -- 停止占领倒计时
    BattlefieldMap.StopCaptureTimer()
    AddLog("【领地战】据点「" .. spName .. "」已被「" .. newOwner .. "」占领！", "info")
    BattlefieldMap.ShowToast("占领成功！「" .. spName .. "」归属「" .. newOwner .. "」")
    -- 刷新大地图据点归属
    if spId and spId ~= "" then
        BattlefieldMap.UpdateStrongpointOwner(spId, newOwner, newOwnerId)
    end
    -- 如果是更换据点，清除旧据点归属
    if oldSpId and oldSpId ~= "" then
        BattlefieldMap.UpdateStrongpointOwner(oldSpId, "", "")
        AddLog("【领地战】旧据点已释放", "info")
    end
    -- 刷新据点面板（如果正在查看该据点）
    if StrongholdPanel.IsVisible() and StrongholdPanel.GetCurrentSpId() == spId then
        StrongholdPanel.RefreshOwner(newOwner, newOwnerId)
    end
end

-- ═══════════════════════════════════════════════════════════════════
-- 据点交互面板（NanoVG 大地图中的浮层面板）
-- ═══════════════════════════════════════════════════════════════════

--- 初始化据点交互面板（进入战场层时调用一次）
function Client.InitStrongholdPanel()
    if StrongholdPanel.GetRoot() then return end  -- 已初始化

    local panelRoot = StrongholdPanel.Init({
        onAttack = function(spId)
            SendToServer(EV.REQ_ATTACK_STRONGPOINT, { SpId = spId })
        end,
        onSwitch = function(spId, existSpName)
            -- 更换据点：在本地立即弹出确认框（不走服务端异步）
            Client.ShowSwitchConfirmDialog(spId, existSpName)
        end,
        onDefend = function(spId)
            SendToServer(EV.REQ_DEFEND_STRONGPOINT, { SpId = spId })
        end,
        onClose = function()
            -- 关闭面板，恢复地图交互
        end,
    })

    -- 挂到 UI 顶层
    if panelRoot and ui_.root then
        ui_.root:AddChild(panelRoot)
    end
end

--- 显示据点交互面板
function Client.ShowStrongholdPanel(spId)
    print("[Client] ShowStrongholdPanel called, spId=" .. tostring(spId))
    if not spId then print("[Client] ⚠️ spId is nil, return"); return end
    local layer = BattlefieldMap.GetLayer()
    if not layer then print("[Client] ⚠️ layer is nil, return"); return end
    print("[Client] ShowStrongholdPanel layer=" .. tostring(layer))

    -- 查找据点当前归属
    local ownerGuild = ""
    local ownerGuildId = ""
    local owners = BattlefieldMap.GetStrongholdOwners and BattlefieldMap.GetStrongholdOwners()
    if owners and owners[spId] then
        ownerGuild = owners[spId].guild_name or ""
        ownerGuildId = owners[spId].guild_id or ""
    end

    -- 检查本帮会是否已拥有其他据点
    local myGuildId = player_ and player_.guild_id or ""
    local myGuildOwnedSpName = nil  -- 帮会已有据点的名称（nil=没有）
    if owners and myGuildId ~= "" then
        for sid, info in pairs(owners) do
            if info.guild_id == myGuildId and sid ~= spId then
                myGuildOwnedSpName = info.sp_name or info.guild_name or sid
                break
            end
        end
    end

    print("[Client] 调用 StrongholdPanel.Show, root=" .. tostring(StrongholdPanel.GetRoot()))
    StrongholdPanel.Show(spId, {
        layer = layer,
        ownerGuild = ownerGuild,
        ownerGuildId = ownerGuildId,
        myGuildId = myGuildId,
        myGuildName = player_ and player_.guild_name or "",
        myGuildOwnedSpName = myGuildOwnedSpName,  -- 帮会已有据点名（nil=无）
    })
end

-- ═══════════════════════════════════════════════════════════════════
-- 据点面板 UI（旧版列表面板，从层选择进入）
-- ═══════════════════════════════════════════════════════════════════

--- 构建据点面板（从层选择面板的"据点"按钮进入）
function BuildStrongpointPanel(layer)
    local container = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        children = {}
    }

    -- 标题行
    local header = UI.Panel {
        width = "100%", height = 36,
        flexDirection = "row", alignItems = "center",
        paddingLeft = 8, paddingRight = 8,
        children = {
            UI.Button {
                text = "← 返回", variant = "ghost", fontSize = 13,
                onClick = function()
                    -- 回到地图面板
                    Client.SwitchPanel(PANEL.MAP)
                end
            },
            UI.Label {
                text = "第" .. layer .. "层 · 据点一览",
                fontSize = 15, fontColor = "#FFD700",
                marginLeft = 8,
            },
        }
    }

    -- 据点内容区
    local content = UI.Panel {
        id = "sp_content",
        width = "100%", flex = 1,
        flexDirection = "column",
        overflow = "scroll",
        paddingLeft = 6, paddingRight = 6, paddingTop = 4,
        children = {}
    }

    container:AddChild(header)
    container:AddChild(content)

    -- 保存引用
    ui_.strongpointPanel = container
    ui_.strongpointLayer = layer

    -- 请求据点数据
    SendToServer(EV.REQ_STRONGPOINT_LIST, { Layer = layer })

    -- 如果有缓存则先显示
    if cachedStrongpoints_[layer] then
        BuildStrongpointContent(layer)
    end

    return container
end

--- 填充据点内容
function BuildStrongpointContent(layer)
    local panel = ui_.strongpointPanel
    if not panel then return end
    local content = panel:FindById("sp_content")
    if not content then return end
    content:RemoveAllChildren()

    local list = cachedStrongpoints_[layer] or {}
    local bonusLabels = {
        offline_potential = "离线灵力",
        cultivate_exp     = "修炼经验",
        silver_income     = "银两收入",
    }

    for i, sp in ipairs(list) do
        local hasOwner = sp.owner and sp.owner ~= "" and sp.owner ~= "无主"
        local ownerText = hasOwner and sp.owner or "无主"
        local ownerColor = hasOwner and "#90EE90" or "#888888"
        local valStr = (sp.value == math.floor(sp.value)) and tostring(math.floor(sp.value)) or string.format("%.1f", sp.value)
        local bonusText = (bonusLabels[sp.bonus] or sp.bonus) .. " +" .. valStr .. "%"

        local card = UI.Panel {
            width = "100%", height = 56,
            flexDirection = "row", alignItems = "center",
            marginBottom = 4, paddingLeft = 8, paddingRight = 8,
            backgroundColor = (i % 2 == 0) and "#1a1a2e" or "#16213e",
            borderRadius = 4,
            children = {
                -- 左侧：名称+加成
                UI.Panel {
                    flex = 1, flexDirection = "column",
                    children = {
                        UI.Label { text = sp.name, fontSize = 13, fontColor = "#FFFFFF" },
                        UI.Label { text = bonusText, fontSize = 11, fontColor = "#AAAAFF" },
                    }
                },
                -- 中间：归属
                UI.Label {
                    text = ownerText, fontSize = 12, fontColor = ownerColor,
                    width = 70, textAlign = "center",
                },
                -- 右侧：操作按钮
                UI.Panel {
                    width = 60, alignItems = "center", justifyContent = "center",
                    children = {
                        UI.Button {
                            text = "进攻", variant = "danger", fontSize = 11,
                            width = 52, height = 26,
                            onClick = function()
                                SendToServer(EV.REQ_ATTACK_STRONGPOINT, {
                                    SpId  = sp.id,
                                    Layer = layer,
                                })
                            end
                        }
                    }
                },
            }
        }
        content:AddChild(card)
    end

    -- 底部防守按钮
    local myGuild = player_ and player_.guild_name or ""
    if myGuild ~= "" then
        local defendBtn = UI.Button {
            text = "📛 防守本帮据点", variant = "primary", fontSize = 13,
            width = "90%", height = 34, marginTop = 8, alignSelf = "center",
            onClick = function()
                SendToServer(EV.REQ_DEFEND_STRONGPOINT, { Layer = layer })
            end
        }
        content:AddChild(defendBtn)
    end
end

--- PvP 目标选择弹窗（攻击据点后有防守者在线时弹出）
function ShowPvpTargetSelection(defData)
    -- 解析防守者数据：uid|name|level 每行一人
    local defenders = {}
    for line in defData:gmatch("[^\n]+") do
        local uid, name, realm, rlayer = line:match("^([^|]+)|([^|]+)|(%d+)|(%d+)$")
        if uid then
            defenders[#defenders + 1] = { uid = uid, name = name, realm = tonumber(realm) or 1, realm_layer = tonumber(rlayer) or 1 }
        end
    end
    if #defenders == 0 then return end

    -- 构建选择面板
    local overlay = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        backgroundColor = TC.shadow,
        justifyContent = "center", alignItems = "center",
        children = {}
    }

    local dialog = UI.Panel {
        width = "85%", maxWidth = 300,
        backgroundColor = "#1a1a2e",
        borderRadius = 8, borderWidth = 1, borderColor = "#FFD700",
        paddingTop = 12, paddingBottom = 12, paddingLeft = 10, paddingRight = 10,
        flexDirection = "column", alignItems = "center",
        children = {
            UI.Label {
                text = "选择挑战对手", fontSize = 15, fontColor = "#FFD700",
                marginBottom = 8,
            },
        }
    }

    for _, def in ipairs(defenders) do
        local row = UI.Button {
            text = string.format("%s（%s）", def.name, Settings.REALM.GetDisplayName(def.realm or 1, def.realm_layer or 1)),
            variant = "outline", fontSize = 13,
            width = "90%", height = 32, marginBottom = 6,
            onClick = function()
                -- 发起 1v1 挑战
                local spLayer = ui_.strongpointLayer or 3
                SendToServer(EV.REQ_PVP_CHALLENGE, {
                    SpId = "",  -- 服务端会从攻击者状态中获取
                    TargetUid = def.uid,
                })
                -- 关闭弹窗
                if overlay and overlay.Remove then
                    overlay:Remove()
                end
                AddLog("【领地战】向 " .. def.name .. " 发起1v1挑战！", "info")
            end
        }
        dialog:AddChild(row)
    end

    -- 取消按钮
    dialog:AddChild(UI.Button {
        text = "取消", variant = "ghost", fontSize = 12,
        marginTop = 4,
        onClick = function()
            if overlay and overlay.Remove then
                overlay:Remove()
            end
        end
    })

    overlay:AddChild(dialog)

    -- 添加到主区域上方
    local mainArea = ui_.mainArea
    if mainArea then
        mainArea:AddChild(overlay)
    end
end

-- ============================================================================
-- 任务系统：事件处理
-- ============================================================================

--- 收到任务进度更新（包括新任务解锁）
function Client_OnPushQuestUpdate(eventType, eventData)
    -- Boss 系统复用此事件做进度更新
    Client_OnResQuestInfo(eventType, eventData)
end

--- 收到 Boss 击败通知（弹出奖励提示）
function Client_OnPushQuestComplete(eventType, eventData)
    local title   = eventData["Title"]:GetString()
    local rewards = eventData["Rewards"]:GetString()
    questState_.completeMsg = string.format("【%s】已击败！\n奖励：%s", title, rewards)
    questState_.completeMsgTimer = 4.0
    Client.ShowQuestCompleteToast()
end

--- 收到任务系统完整状态（主线+日常+Boss进度）
function Client_OnResQuestInfo(eventType, eventData)
    -- 主线任务
    local mqId = eventData["MainQuestId"]:GetString()
    if mqId and mqId ~= "" then
        questState_.mainQuest = {
            id       = mqId,
            name     = eventData["MainQuestName"]:GetString(),
            desc     = eventData["MainQuestDesc"]:GetString(),
            chapter  = eventData["MainQuestChapter"]:GetInt(),
            progress = eventData["MainQuestProgress"]:GetInt(),
            goal     = eventData["MainQuestGoal"]:GetInt(),
        }
    else
        questState_.mainQuest = {
            id = "", name = "主线已通关", desc = "所有主线任务已完成！",
            chapter = 0, progress = 0, goal = 0,
        }
    end

    -- 日常任务（格式: "id|progress|goal|claimed;id|progress|goal|claimed;..."）
    local dailyStr = eventData["DailyQuests"]:GetString()
    questState_.dailyQuests = {}
    if dailyStr and dailyStr ~= "" then
        for entry in dailyStr:gmatch("[^;]+") do
            local id, prog, goal, claimed = entry:match("^(.-)|(%-?%d+)|(%d+)|(%d)$")
            if id then
                table.insert(questState_.dailyQuests, {
                    id = id,
                    progress = tonumber(prog) or 0,
                    goal = tonumber(goal) or 0,
                    claimed = claimed == "1",
                })
            end
        end
    end

    -- Boss 进度
    questState_.maxLayer = eventData["MaxLayer"]:GetInt()

    -- 门派试炼（格式: "sectId|questName|progress|goal;..."）
    local trialStr = eventData["SectTrials"]:GetString()
    questState_.sectTrials = {}
    if trialStr and trialStr ~= "" then
        for entry in trialStr:gmatch("[^;]+") do
            local sectId, name, prog, goal = entry:match("^(.-)|(.-)|(%d+)|(%d+)$")
            if sectId then
                table.insert(questState_.sectTrials, {
                    sectId   = sectId,
                    name     = name,
                    progress = tonumber(prog) or 0,
                    goal     = tonumber(goal) or 0,
                })
            end
        end
    end

    -- 如果任务面板正在显示，刷新它
    if ui_ and ui_.questPanel then
        Client.ShowQuestPanel(true)
    end
end

--- 显示完整任务面板（弹窗式覆盖）
---@param forceRefresh? boolean 如果为 true 则强制刷新而非关闭
function Client.ShowQuestPanel(forceRefresh)
    if not ui_ or not ui_.mainArea then return end

    -- 刷新时移除旧面板
    if ui_.questPanel and ui_.questPanel.Remove then
        ui_.questPanel:Remove()
        ui_.questPanel = nil
        if not forceRefresh and not mapNvgActive_ then return end  -- 非战场模式下 toggle 关闭
    end

    local mq = questState_.mainQuest
    local sections = {}

    -- ========== 主线任务区 ==========
    table.insert(sections, UI.Label {
        text = "【主线任务】",
        fontSize = 13,
        color = "#FFD700",
        fontWeight = "bold",
    })

    if mq and mq.id ~= "" then
        local chStr = mq.chapter > 0 and string.format("第%d章 · ", mq.chapter) or ""
        table.insert(sections, UI.Label {
            text = chStr .. (mq.name or ""),
            fontSize = 12,
            color = "#FFFFFF",
            marginTop = 4,
        })
        table.insert(sections, UI.Label {
            text = mq.desc or "",
            fontSize = 10,
            color = "#BBBBBB",
            marginTop = 2,
        })
        local progColor = (mq.progress >= mq.goal) and "#44FF44" or "#FFAA00"
        table.insert(sections, UI.Label {
            text = string.format("进度: %d / %d", mq.progress, mq.goal),
            fontSize = 11,
            color = progColor,
            marginTop = 3,
        })
    else
        table.insert(sections, UI.Label {
            text = "所有主线任务已完成！恭喜！",
            fontSize = 11,
            color = "#44FF44",
            marginTop = 4,
        })
    end

    -- 分隔
    table.insert(sections, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = "#FFFFFF22",
        marginTop = 8, marginBottom = 6,
    })

    -- ========== 日常任务区 ==========
    table.insert(sections, UI.Label {
        text = "【日常任务】",
        fontSize = 13,
        color = "#88CCFF",
        fontWeight = "bold",
    })

    -- 从 Settings 读取日常任务名称（客户端也 require 了 Settings）
    local dailyDefs = Settings.DAILY_QUESTS or {}
    for i, dq in ipairs(questState_.dailyQuests) do
        local def = dailyDefs[i]
        local dName = def and def.name or dq.id
        local dDesc = def and def.desc or ""
        local completed = dq.progress >= dq.goal
        local statusText
        local statusColor
        if dq.claimed then
            statusText = "✓ 已领取"
            statusColor = "#666666"
        elseif completed then
            statusText = "★ 可领取"
            statusColor = "#44FF44"
        else
            statusText = string.format("%d/%d", dq.progress, dq.goal)
            statusColor = "#FFAA00"
        end

        local row = UI.Panel {
            width = "100%", height = "auto",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            marginTop = 4,
            paddingTop = 4, paddingBottom = 4,
            paddingLeft = 6, paddingRight = 6,
            backgroundColor = dq.claimed and "#11111100" or "#FFFFFF08",
            borderRadius = 4,
        }

        row:AddChild(UI.Panel {
            flexDirection = "column",
            flexShrink = 1,
            children = {
                UI.Label { text = dName, fontSize = 11, color = dq.claimed and "#666666" or "#DDDDDD" },
                UI.Label { text = dDesc, fontSize = 9, color = "#888888", marginTop = 1 },
            }
        })

        if completed and not dq.claimed then
            local capturedId = dq.id
            row:AddChild(UI.Button {
                text = "领取",
                fontSize = 10,
                height = 22, minWidth = 50,
                paddingHorizontal = 8,
                variant = "primary",
                marginLeft = 4,
                onClick = function(self)
                    self:SetDisabled(true)
                    self:SetText("...")
                    SendToServer(EV.REQ_CLAIM_DAILY, { QuestId = capturedId })
                end,
            })
        else
            row:AddChild(UI.Label {
                text = statusText,
                fontSize = 10,
                color = statusColor,
                marginLeft = 4,
            })
        end

        table.insert(sections, row)
    end

    -- 全勤奖励提示
    local allClaimed = true
    for _, dq in ipairs(questState_.dailyQuests) do
        if not dq.claimed then allClaimed = false; break end
    end
    if allClaimed and #questState_.dailyQuests > 0 then
        table.insert(sections, UI.Label {
            text = "✓ 全勤奖励已发放！",
            fontSize = 10,
            color = "#FFD700",
            marginTop = 6,
        })
    end

    -- ========== 门派试炼区 ==========
    local sectTrials = questState_.sectTrials or {}
    if #sectTrials > 0 then
        -- 分隔
        table.insert(sections, UI.Panel {
            width = "100%", height = 1,
            backgroundColor = "#FFFFFF22",
            marginTop = 8, marginBottom = 6,
        })
        table.insert(sections, UI.Label {
            text = "【门派试炼】",
            fontSize = 13,
            color = "#FFAA44",
            fontWeight = "bold",
        })

        for _, trial in ipairs(sectTrials) do
            local completed = trial.progress >= trial.goal
            local progColor = completed and "#44FF44" or "#FFAA00"
            local row = UI.Panel {
                width = "100%", height = "auto",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                marginTop = 4,
                paddingTop = 4, paddingBottom = 4,
                paddingLeft = 6, paddingRight = 6,
                backgroundColor = "#FFFFFF08",
                borderRadius = 4,
            }
            row:AddChild(UI.Label {
                text = trial.name,
                fontSize = 11,
                color = "#DDDDDD",
                flexShrink = 1,
            })
            row:AddChild(UI.Label {
                text = completed
                    and "回去复命"
                    or string.format("%d/%d", trial.progress, trial.goal),
                fontSize = 10,
                color = progColor,
                marginLeft = 4,
            })
            table.insert(sections, row)
        end
    end

    -- 关闭按钮（域外战场常驻显示，不需要关闭按钮）
    if not mapNvgActive_ then
        table.insert(sections, UI.Button {
            text = "关闭",
            fontSize = 11,
            width = "100%",
            height = 28,
            marginTop = 10,
            variant = "outline",
            onClick = function()
                if ui_.questPanel and ui_.questPanel.Remove then
                    ui_.questPanel:Remove()
                    ui_.questPanel = nil
                end
            end,
        })
    end

    local panelBg = mapNvgActive_ and "#0a0a1a99" or "#0a0a1aF0"
    local panel = UI.Panel {
        position = "absolute",
        top = 40, right = 8,
        width = 220, height = "auto",
        maxHeight = "70%",
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 10, paddingRight = 10,
        backgroundColor = panelBg,
        borderRadius = 10,
        borderWidth = 1,
        borderColor = mapNvgActive_ and "#FFD70033" or "#FFD70066",
        overflow = "scroll",
        children = sections,
    }

    -- 域外战场时 mainArea 布局塌陷，挂到 root 顶层
    local parent = (mapNvgActive_ and ui_.root) or ui_.mainArea
    parent:AddChild(panel)
    ui_.questPanel = panel
end

--- 显示任务完成弹窗（居中 Toast）
function Client.ShowQuestCompleteToast()
    if not ui_ or not ui_.mainArea then return end
    if not questState_.completeMsg then return end

    -- 移除旧 toast
    if ui_.questToast and ui_.questToast.Remove then
        ui_.questToast:Remove()
        ui_.questToast = nil
    end

    local toast = UI.Panel {
        position = "absolute",
        top = "30%", left = "50%",
        width = 260, height = "auto",
        translateX = -130,
        paddingTop = 12, paddingBottom = 12,
        paddingLeft = 16, paddingRight = 16,
        backgroundColor = "#1a1a2eEE",
        borderRadius = 10,
        borderWidth = 1,
        borderColor = "#FFD700",
        alignItems = "center",
        children = {
            UI.Label {
                text = "首领击败！",
                fontSize = 16,
                color = "#FF4444",
                fontWeight = "bold",
            },
            UI.Label {
                text = questState_.completeMsg,
                fontSize = 12,
                color = "#FFFFFF",
                marginTop = 6,
                textAlign = "center",
            },
        },
    }

    ui_.mainArea:AddChild(toast)
    ui_.questToast = toast
end

return Client
