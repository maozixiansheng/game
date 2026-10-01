-- ============================================================================
-- network/EntryFlow.lua - 游戏进入流程（欢迎页 → 故事滚动 → 角色创建）
-- ============================================================================

local EntryFlow = {}
local UI = require("urhox-libs/UI")
local Theme = require("config.Theme")
local TC = Theme.C
local Settings = require("config.Settings")
local EV = Settings.EVENTS

-- ============================================================================
-- 状态
-- ============================================================================
local entryRoot_    = nil   -- 整个流程的 UI 根节点
local onComplete_   = nil   -- 完成回调
local serverConn_   = nil   -- 服务端连接引用
local isNewPlayer_  = false -- 是否新玩家
local updateSub_    = nil   -- Update 事件订阅标记
local storyY_       = 0     -- 故事文字滚动偏移
local storyDone_    = false -- 故事是否播放完毕

-- 粒子系统状态
local particles_ = {}
local PARTICLE_COUNT = 30

-- 过渡动画状态
local transOverlay_   = nil    -- 过渡遮罩面板
local transTimer_     = 0      -- 过渡计时器
local transDuration_  = 1.2    -- 过渡时长（秒）
local transActive_    = false  -- 是否正在过渡
local transCallback_  = nil    -- 过渡完成后的回调

-- ============================================================================
-- 古风三字随机名生成
-- ============================================================================
local NAME_SURNAME = { "云", "月", "风", "星", "雪", "霜", "叶", "花", "柳", "苏",
    "慕", "楚", "沐", "凌", "白", "墨", "青", "寒", "萧", "夜",
    "紫", "玄", "尘", "影", "烟", "秋", "南", "北", "东", "西" }
local NAME_MIDDLE = { "无", "长", "玉", "灵", "清", "落", "千", "绝", "飞", "逸",
    "浮", "空", "天", "幻", "离", "孤", "若", "梦", "流", "隐",
    "凝", "素", "瑶", "幽", "仙", "轻", "冷", "远", "明", "澜" }
local NAME_LAST = { "尘", "歌", "殇", "弦", "心", "烟", "雨", "笙", "音", "漓",
    "羽", "枫", "墨", "雪", "鸢", "卿", "吟", "瑟", "澈", "霄",
    "辰", "夕", "容", "舞", "璃", "絮", "寂", "痕", "语", "归" }

local function RandomName()
    local s = NAME_SURNAME[math.random(#NAME_SURNAME)]
    local m = NAME_MIDDLE[math.random(#NAME_MIDDLE)]
    local l = NAME_LAST[math.random(#NAME_LAST)]
    return s .. m .. l
end

-- ============================================================================
-- 粒子效果（青白色仙气雾粒）
-- ============================================================================
local function InitParticles(w, h)
    particles_ = {}
    for i = 1, PARTICLE_COUNT do
        particles_[i] = {
            x = math.random() * w,
            y = math.random() * h,
            vx = (math.random() - 0.5) * 20,
            vy = -math.random() * 15 - 5,
            size = math.random() * 3 + 1.5,
            alpha = math.random() * 0.4 + 0.1,
            life = math.random() * 6 + 2,
            maxLife = 8,
        }
    end
end

local function UpdateParticles(dt, w, h)
    for i = 1, #particles_ do
        local p = particles_[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.life = p.life - dt
        p.alpha = p.alpha - dt * 0.02
        if p.life <= 0 or p.y < -20 or p.alpha <= 0 then
            p.x = math.random() * w
            p.y = h + math.random() * 20
            p.vx = (math.random() - 0.5) * 20
            p.vy = -math.random() * 15 - 5
            p.size = math.random() * 3 + 1.5
            p.alpha = math.random() * 0.4 + 0.1
            p.life = math.random() * 6 + 2
        end
    end
end

-- ============================================================================
-- 故事文案
-- ============================================================================
local STORY_TEXT = [[


天地初开，灵气充盈，万物皆可修行。

千年之前，修真界百家争鸣，
丹药、灵材、法宝流通四方，
造就了一个繁荣昌盛的修仙盛世。

然而盛极必衰——
一场浩劫席卷三界，宗门覆灭，传承断绝，
灵脉枯竭，天材地宝散落荒野。

如今，修真界百废待兴。

你，一个偶得灵根的凡人，
于古村废墟中苏醒，
身无长物，却怀揣一颗不屈之心。

以「倒爷」之名行走天下——
低买高卖，积累灵石；
结交各路散修，打探秘境消息；
以商道养修道，以财力撬动天机。

你的目标：
修至大乘圆满，开宗立派，一统修真界！



]]

-- ============================================================================
-- 页面1：欢迎页（精致古风 + 服务器展示）
-- ============================================================================
local function BuildWelcomePage()
    -- 获取推荐服务器
    local curServer = Settings.SERVERS[1]
    for _, s in ipairs(Settings.SERVERS) do
        if s.recommend then curServer = s; break end
    end

    local page = UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundImage = "image/welcome_bg_20260605173711.png",
        backgroundFit = "cover",
    }

    -- 标题图片（金石篆刻风）
    page:AddChild(UI.Panel {
        width = 560, height = 240,
        backgroundImage = "image/title_seal_style_20260605174951.png",
        backgroundFit = "contain",
        marginBottom = 8,
    })

    -- 副标题
    page:AddChild(UI.Label {
        text = "—— 以商入道，一统修真 ——",
        fontSize = 13,
        color = { 200, 184, 150, 255 },
        marginBottom = 28,
    })

    -- 服务器选择面板
    local serverPanel = UI.Panel {
        width = 220,
        borderRadius = 6,
        borderWidth = 1,
        borderColor = TC.border,
        backgroundColor = TC.bgPanel,
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 14, paddingRight = 14,
        alignItems = "center",
        marginBottom = 28,
    }

    -- 服务器名 + 状态指示灯
    local serverRow = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        marginBottom = 4,
    }
    -- 绿点指示灯
    serverRow:AddChild(UI.Panel {
        width = 8, height = 8,
        borderRadius = 4,
        backgroundColor = TC.success,
        marginRight = 8,
    })
    serverRow:AddChild(UI.Label {
        text = curServer.name .. " - " .. curServer.id .. "服",
        fontSize = 15,
        color = TC.textPrimary,
    })
    serverPanel:AddChild(serverRow)

    -- 状态说明
    serverPanel:AddChild(UI.Label {
        text = curServer.status == "open" and "畅通" or "繁忙",
        fontSize = 11,
        color = TC.textSecondary,
    })

    page:AddChild(serverPanel)

    -- 进入按钮（朱砂红主色调）
    page:AddChild(UI.Button {
        text = "踏 入 仙 途",
        variant = "primary",
        width = 200, height = 46,
        fontSize = 17,
        borderRadius = 6,
        onClick = function(self)
            self:SetDisabled(true)
            self:SetText("正在进入…")
            EntryFlow._StartTransition(function()
                if isNewPlayer_ then
                    EntryFlow._ShowStory()
                else
                    EntryFlow._Finish()
                end
            end)
        end,
    })

    -- 版本号
    page:AddChild(UI.Label {
        text = "v1.0.0",
        fontSize = 10,
        color = TC.textMuted,
        marginTop = 24,
    })

    return page
end

-- ============================================================================
-- 页面2：故事滚动（电影开场式）
-- ============================================================================
local storyLabel_ = nil
local storyContainer_ = nil
local skipBtn_ = nil

local function BuildStoryPage()
    storyY_ = 0
    storyDone_ = false

    local page = UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = { 10, 8, 6, 255 },
        overflow = "hidden",
    }

    -- 故事文字容器（会被 Update 动态移动）
    storyContainer_ = UI.Panel {
        width = "80%",
        alignSelf = "center",
        position = "absolute",
        top = "100%",  -- 从底部开始
    }

    storyLabel_ = UI.Label {
        text = STORY_TEXT,
        fontSize = 15,
        color = { 200, 210, 200, 255 },
        textAlign = "center",
        lineHeight = 1.8,
    }
    storyContainer_:AddChild(storyLabel_)
    page:AddChild(storyContainer_)

    -- 跳过按钮
    skipBtn_ = UI.Button {
        text = "跳过 ▶",
        variant = "text",
        position = "absolute",
        bottom = 20, right = 20,
        fontSize = 12,
        color = TC.textSecondary,
        onClick = function()
            EntryFlow._ShowCreate()
        end,
    }
    page:AddChild(skipBtn_)

    return page
end

-- ============================================================================
-- 页面3：角色创建（性别 + 名字 + 邀请码）
-- ============================================================================
local nameInput_   = nil
local genderMale_  = nil
local genderFemale_ = nil
local selectedGender_ = "male"
local inviteInput_ = nil
local createBtn_   = nil
local errorLabel_  = nil

local function BuildCreatePage()
    selectedGender_ = "male"

    local page = UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        backgroundColor = TC.bgDeep,
    }

    page:AddChild(UI.Label {
        text = "创建角色",
        fontSize = 22,
        color = TC.textTitle,
        marginBottom = 24,
    })

    -- 性别选择
    local genderRow = UI.Panel {
        flexDirection = "row",
        justifyContent = "center", alignItems = "center",
        marginBottom = 16,
    }

    genderMale_ = UI.Button {
        text = "♂ 男",
        width = 80, height = 36,
        fontSize = 14,
        backgroundColor = TC.btnPrimary,
        color = { 255, 255, 255, 255 },
        marginRight = 12,
        onClick = function()
            selectedGender_ = "male"
            genderMale_:SetStyle({ backgroundColor = TC.btnPrimary })
            genderFemale_:SetStyle({ backgroundColor = TC.btnSecondary })
        end,
    }
    genderFemale_ = UI.Button {
        text = "♀ 女",
        width = 80, height = 36,
        fontSize = 14,
        backgroundColor = TC.btnSecondary,
        color = { 255, 255, 255, 255 },
        onClick = function()
            selectedGender_ = "female"
            genderFemale_:SetStyle({ backgroundColor = TC.btnPrimary })
            genderMale_:SetStyle({ backgroundColor = TC.btnSecondary })
        end,
    }
    genderRow:AddChild(genderMale_)
    genderRow:AddChild(genderFemale_)
    page:AddChild(genderRow)

    -- 名字输入
    page:AddChild(UI.Label {
        text = "道号（1-6字）",
        fontSize = 12,
        color = TC.textSecondary,
        marginBottom = 4,
    })

    local nameRow = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        marginBottom = 12,
    }
    nameInput_ = UI.TextField {
        placeholder = "请输入道号",
        width = 160, height = 36,
        fontSize = 14,
        maxLength = 6,
    }
    nameRow:AddChild(nameInput_)
    nameRow:AddChild(UI.Button {
        text = "随机",
        width = 56, height = 36,
        fontSize = 12,
        marginLeft = 8,
        variant = "secondary",
        onClick = function()
            nameInput_:SetText(RandomName())
        end,
    })
    page:AddChild(nameRow)

    -- 邀请码输入
    page:AddChild(UI.Label {
        text = "邀请码（可选，填写双方各得100灵石）",
        fontSize = 11,
        color = TC.textSecondary,
        marginBottom = 4,
    })
    inviteInput_ = UI.TextField {
        placeholder = "6位邀请码",
        width = 160, height = 36,
        fontSize = 14,
        maxLength = 6,
    }
    page:AddChild(inviteInput_)

    -- 错误提示
    errorLabel_ = UI.Label {
        text = "",
        fontSize = 11,
        color = TC.danger,
        marginTop = 8,
        height = 16,
    }
    page:AddChild(errorLabel_)

    -- 确认按钮
    createBtn_ = UI.Button {
        text = "开始修仙",
        variant = "primary",
        width = 180, height = 44,
        fontSize = 16,
        marginTop = 16,
        onClick = function()
            EntryFlow._SubmitCreate()
        end,
    }
    page:AddChild(createBtn_)

    return page
end

-- ============================================================================
-- 流程控制
-- ============================================================================

function EntryFlow._ShowStory()
    if not entryRoot_ then return end
    entryRoot_:RemoveAllChildren()
    local storyPage = BuildStoryPage()
    entryRoot_:AddChild(storyPage)
end

function EntryFlow._ShowCreate()
    if not entryRoot_ then return end
    storyContainer_ = nil
    storyLabel_ = nil
    entryRoot_:RemoveAllChildren()
    local createPage = BuildCreatePage()
    entryRoot_:AddChild(createPage)
end

-- ============================================================================
-- 过渡动画
-- ============================================================================

--- 启动过渡动画（黑幕渐入 + 提示文字 → 完成后执行回调）
function EntryFlow._StartTransition(callback)
    transActive_ = true
    transTimer_ = 0
    transCallback_ = callback

    -- 创建全屏遮罩（初始透明）
    transOverlay_ = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        top = 0, left = 0,
        backgroundColor = { 0, 0, 0, 0 },
        justifyContent = "center",
        alignItems = "center",
    }
    -- 加载提示文字
    transOverlay_:AddChild(UI.Label {
        id = "trans_text",
        text = "仙途开启中…",
        fontSize = 18,
        color = { 200, 184, 150, 0 },
    })
    -- 底部小字
    transOverlay_:AddChild(UI.Label {
        id = "trans_hint",
        text = "灵气汇聚，道心凝结",
        fontSize = 12,
        color = { 150, 140, 120, 0 },
        marginTop = 12,
    })

    if entryRoot_ then
        entryRoot_:AddChild(transOverlay_)
    end
end

--- 更新过渡动画（在 _HandleUpdate 中调用）
function EntryFlow._UpdateTransition(dt)
    if not transActive_ then return end
    transTimer_ = transTimer_ + dt

    local progress = math.min(transTimer_ / transDuration_, 1.0)
    -- ease-in: 先慢后快
    local alpha = progress * progress
    local bgAlpha = math.floor(alpha * 255)
    local textAlpha = math.floor(math.min(progress * 1.5, 1.0) * 255)

    if transOverlay_ then
        transOverlay_:SetBackgroundColor({ 0, 0, 0, bgAlpha })
        local txt = transOverlay_:FindById("trans_text")
        if txt then txt:SetStyle({ color = { 200, 184, 150, textAlpha } }) end
        local hint = transOverlay_:FindById("trans_hint")
        if hint then hint:SetStyle({ color = { 150, 140, 120, math.floor(textAlpha * 0.7) } }) end
    end

    -- 过渡完成
    if progress >= 1.0 then
        transActive_ = false
        if transCallback_ then
            transCallback_()
        end
    end
end

function EntryFlow._Finish()
    -- 移除 Update 订阅
    if updateSub_ then
        UnsubscribeFromEvent("Update")
        updateSub_ = nil
    end
    -- 清除 UI
    if entryRoot_ then
        UI.SetRoot(nil)
        entryRoot_ = nil
    end
    -- 清理过渡状态
    transOverlay_ = nil
    transActive_ = false
    -- 回调主流程
    if onComplete_ then
        onComplete_()
    end
end

function EntryFlow._SubmitCreate()
    local name = nameInput_ and nameInput_:GetText() or ""
    local invite = inviteInput_ and inviteInput_:GetText() or ""

    -- 本地校验
    local nameLen = utf8.len(name) or 0
    if nameLen < Settings.SPIRIT_STONE.CREATE_NAME_MIN_LEN or nameLen > Settings.SPIRIT_STONE.CREATE_NAME_MAX_LEN then
        if errorLabel_ then
            errorLabel_:SetText("道号需要1-6个字")
        end
        return
    end

    -- 邀请码格式校验（可选，6位大写字母+数字）
    if invite ~= "" then
        if #invite ~= 6 or not invite:match("^[A-Z0-9]+$") then
            if errorLabel_ then
                errorLabel_:SetText("邀请码格式错误（6位大写字母+数字）")
            end
            return
        end
    end

    -- 禁用按钮防重复点击
    if createBtn_ then
        createBtn_:SetDisabled(true)
        createBtn_:SetText("创建中...")
    end
    if errorLabel_ then
        errorLabel_:SetText("")
    end

    -- 发送到服务端
    if serverConn_ then
        local vm = VariantMap()
        vm["Name"] = Variant(name)
        vm["Gender"] = Variant(selectedGender_)
        vm["InviteCode"] = Variant(invite)
        serverConn_:SendRemoteEvent(EV.REQ_CREATE_CHARACTER, true, vm)
    end
end

-- 收到服务端创建结果
function EntryFlow.OnCreateResult(eventType, eventData)
    local success = eventData["Success"]:GetBool()
    local msg = eventData["Msg"]:GetString()

    if success then
        -- 创建成功，进入游戏
        EntryFlow._Finish()
    else
        -- 失败，显示错误
        if errorLabel_ then
            errorLabel_:SetText(msg or "创建失败")
        end
        if createBtn_ then
            createBtn_:SetDisabled(false)
            createBtn_:SetText("开始修仙")
        end
    end
end

-- ============================================================================
-- Update 驱动故事滚动
-- ============================================================================
local STORY_SCROLL_SPEED = 40  -- 像素/秒

function EntryFlow._HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 过渡动画更新
    EntryFlow._UpdateTransition(dt)

    -- 故事页面滚动
    if storyContainer_ and not storyDone_ then
        storyY_ = storyY_ + STORY_SCROLL_SPEED * dt
        storyContainer_:SetStyle({ top = -storyY_ })

        -- 当滚动到一定距离后自动切页
        local screenH = graphics:GetHeight() / graphics:GetDPR()
        if storyY_ > screenH + 600 then
            storyDone_ = true
            EntryFlow._ShowCreate()
        end
    end
end

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 启动进入流程
---@param opts { conn: any, isNew: boolean, onComplete: function }
function EntryFlow.Show(opts)
    serverConn_ = opts.conn
    isNewPlayer_ = opts.isNew or false
    onComplete_ = opts.onComplete

    -- 构建欢迎页
    entryRoot_ = UI.Panel {
        width = "100%", height = "100%",
    }
    local welcomePage = BuildWelcomePage()
    entryRoot_:AddChild(welcomePage)
    UI.SetRoot(entryRoot_)

    -- 订阅 Update 驱动动画
    SubscribeToEvent("Update", "EntryFlow_HandleUpdate")
    updateSub_ = true
end

--- 更新服务器连接引用（连接建立后调用）
function EntryFlow.SetConn(conn)
    serverConn_ = conn
end

--- 标记为新玩家（收到 INIT_PLAYER._needCreate 时调用）
--- 这样欢迎页"进入"按钮将走 故事→创建 流程
function EntryFlow.MarkNewPlayer()
    isNewPlayer_ = true
end

-- 全局回调（供 SubscribeToEvent 使用）
function EntryFlow_HandleUpdate(eventType, eventData)
    EntryFlow._HandleUpdate(eventType, eventData)
end

return EntryFlow
