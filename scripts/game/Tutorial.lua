-- Tutorial.lua
-- 新手引导系统：mainArea 内嵌固定卡片方案
-- 教程卡片作为 mainArea 的第一个子节点置顶显示，不受日志刷新影响
--
-- 使用方式：
--   Tutorial.Init(cfg)            -- cfg = { mainArea }
--   Tutorial.UpdatePlayer(player)
--   Tutorial.Check()
--   Tutorial.Advance(eventName)
--   Tutorial.Dismiss()
--   Tutorial.RefreshUI(mainArea)  -- RebuildMainContent 后调用

local UI = require("urhox-libs/UI")

local Tutorial = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

---@type table|nil
local player_ = nil
---@type Widget|nil
local mainArea_ = nil

-- 当前教程卡片 widget（nil = 未显示）
---@type Widget|nil
local cardWidget_ = nil

-- 上一次显示的步骤索引（防止重复）
local lastShownStep_ = -1

-- 已达到过的最高步骤（用于 Advance 前置判断，不受 Dismiss 重置影响）
local highestStep_ = 0

-- 暂停标记：玩家正在执行当前步骤的操作，不要重复弹卡片
local paused_ = false

-- 上一次已知的服务端 tutorial_step（用于检测推进）
local lastKnownTutStep_ = -1

-- ============================================================================
-- 步骤定义
-- ============================================================================

local STEPS = {
    {
        title = "新手指引 · 步骤 1/14",
        text  = "欢迎来到侠客世界！\n👉 在下方「此处人物」区域，找到「老村长」并点击与他搭话。",
    },
    {
        title = "新手指引 · 步骤 2/14",
        text  = "老村长已将任务交付！\n👉 点击下方地图中的「竹林」按钮，前往竹林驱散迷失幼妖。",
    },
    {
        title = "新手指引 · 步骤 3/14",
        text  = "竹林深处妖气弥漫！\n👉 在下方人物区找到「迷失幼妖」，点击「驱散」按钮开始战斗！",
    },
    {
        title = "新手指引 · 步骤 4/14",
        text  = "战斗进行中…… 运用你的功法技能，击退妖兽！\n点击技能按钮释放招式。",
    },
    {
        title = "新手指引 · 步骤 5/14",
        text  = "战斗胜利！\n👉 日志中出现了黄色高亮的掉落物品，点击它将物品放入背包。",
    },
    {
        title = "新手指引 · 步骤 6/14",
        text  = "物品已收入囊中！\n👉 点击底部导航栏的「角色」按钮，查看你的装备和背包。",
    },
    {
        title = "新手指引 · 步骤 7/14",
        text  = "欢迎来到角色面板！\n👉 点击顶部的「背包」标签，查看你刚获得的物品。",
    },
    {
        title = "新手指引 · 步骤 8/14",
        text  = "这是你获得的装备！\n👉 点击物品旁的「装备」按钮，将它穿戴在身上提升实力。",
    },
    {
        title = "新手指引 · 步骤 9/14",
        text  = "装备完成，实力提升了！\n👉 点击底部导航栏的「修炼」按钮，学习打坐修炼。",
    },
    {
        title = "新手指引 · 步骤 10/14",
        text  = "这里是修炼界面。\n👉 点击「打坐」按钮，让你的内力随时间增长！",
    },
    {
        title = "新手指引 · 步骤 11/14",
        text  = "修炼已开始，内力正在积累。\n👉 点击底部的「角色」按钮，查看你的属性面板。",
    },
    {
        title = "新手指引 · 步骤 12/14",
        text  = "👉 点击顶部的「属性」标签，查看你的各项能力值。",
    },
    {
        title = "新手指引 · 步骤 13/14",
        text  = "你已掌握了基本玩法！\n👉 点击下方地图中的「村中心」按钮，回去找老村长复命。",
    },
    {
        title = "新手指引 · 步骤 14/14",
        text  = "老村长就在附近！\n👉 点击下方「老村长」，完成你的引导任务！",
    },
}

-- ============================================================================
-- 卡片构建
-- ============================================================================

local function BuildCard(stepIndex)
    local step = STEPS[stepIndex]
    if not step then return nil end

    local card = UI.Panel {
        width = "100%",
        flexDirection = "column",
        paddingVertical = 8,
        paddingHorizontal = 12,
        backgroundColor = { 15, 25, 55, 245 },
        borderWidth = 1,
        borderColor = { 60, 120, 220, 220 },
        borderRadius = 6,
        gap = 4,
        flexShrink = 0,
    }

    -- 顶部行：标题
    card:AddChild(UI.Label {
        text = step.title,
        fontSize = 11,
        color = { 90, 150, 240, 200 },
    })

    -- 正文
    card:AddChild(UI.Label {
        text = step.text,
        fontSize = 14,
        color = { 240, 230, 170, 255 },
        width = "100%",
        flexWrap = "wrap",
        lineHeight = 1.3,
    })

    -- 自动推进提示（完成操作后自动切换下一步，无需手动关闭）

    return card
end

-- ============================================================================
-- 步骤展示（置顶插入 mainArea）
-- ============================================================================

local function ShowStep(stepIndex)
    if stepIndex < 1 or stepIndex > #STEPS then
        Tutorial.Dismiss()
        return
    end
    if stepIndex == lastShownStep_ and cardWidget_ then
        return  -- 已经在显示了
    end

    -- 关闭旧卡片
    if cardWidget_ then
        cardWidget_:Remove()
        cardWidget_ = nil
    end

    if not mainArea_ then return end

    local card = BuildCard(stepIndex)
    if not card then return end

    -- 插入 mainArea 的第一个位置（置顶，1-based 索引）
    mainArea_:InsertChild(card, 1)
    cardWidget_ = card
    lastShownStep_ = stepIndex
    if stepIndex > highestStep_ then
        highestStep_ = stepIndex
    end
end

-- ============================================================================
-- 公共 API
-- ============================================================================

--- 初始化教程系统
---@param cfg table { mainArea }
function Tutorial.Init(cfg)
    mainArea_ = cfg.mainArea or nil
    -- 不在 Init 时无条件显示步骤1，等 player data 到达后由 Check() 决定
end

--- UI 重建后刷新引用
function Tutorial.RefreshUI(mainArea)
    mainArea_ = mainArea
    -- 旧 cardWidget_ 已随 mainArea:ClearChildren 被销毁
    cardWidget_ = nil
    -- 重新显示当前步骤（仅在教程仍活跃时）
    if lastShownStep_ > 0 then
        -- 如果玩家数据已到达且教程已完成，不重新显示
        if player_ then
            local tutStep = player_.tutorial_step or 0
            if tutStep >= 3 and lastShownStep_ < 4 then
                lastShownStep_ = -1
                return
            end
        end
        local step = lastShownStep_
        lastShownStep_ = -1  -- 重置让 ShowStep 能执行
        ShowStep(step)
    end
end

--- 更新玩家数据引用
function Tutorial.UpdatePlayer(player)
    player_ = player
end

--- 注册目标（保留接口兼容性）
function Tutorial.RegisterTarget(name, widget) end

--- 注销目标（保留接口兼容性）
function Tutorial.UnregisterTarget(name) end

--- 关闭当前卡片
function Tutorial.Dismiss()
    if cardWidget_ then
        cardWidget_:Remove()
        cardWidget_ = nil
    end
    lastShownStep_ = -1
end

--- 重置教程内部状态（服务端重置教程后调用）
function Tutorial.Reset()
    Tutorial.Dismiss()
    lastShownStep_ = -1
    highestStep_ = 0
    paused_ = false
    lastKnownTutStep_ = -1
end

--- 检查当前 tutorial_step，决定是否显示引导
function Tutorial.Check()
    if not player_ then return end
    local step = player_.tutorial_step or 0

    -- 检测服务端 tutorial_step 是否推进了
    if step ~= lastKnownTutStep_ then
        lastKnownTutStep_ = step
    end

    -- 服务端推进了 step → 解除暂停，显示下一步
    if paused_ then
        if step == 0 then
            return  -- 还没推进，保持暂停不重复弹
        end
        -- step 已推进（>=1），解除暂停继续
        paused_ = false
    end

    -- ★ 核心原则：只能前进，不能后退
    -- 事件驱动的 Advance 可能已将教程推进到步骤 3+，
    -- Check() 不能因为 tutorial_step 仍在旧值就把卡片打回去。
    if step == 0 then
        if highestStep_ < 1 then  -- 尚未显示过步骤1，才展示
            ShowStep(1)
        end
        return
    end
    if step == 1 then
        if highestStep_ < 2 then  -- 尚未前进到步骤2+，才展示
            ShowStep(2)
        end
        return
    end
    if step == 2 then
        -- 击败幼妖后，步骤 3-5 由事件驱动显示，不干涉
        return
    end
    if step >= 3 then
        -- 教程大阶段已完成，但客户端步骤 4-14 仍可能由事件驱动显示中
        if highestStep_ >= 4 then
            return  -- 事件驱动的引导正在进行，不干涉
        end
        -- 没有活跃的事件驱动步骤 → 教程真正结束
        Tutorial.Dismiss()
        return
    end
end

--- 推进步骤
---@param eventName string
function Tutorial.Advance(eventName)
    if not player_ then return end
    local tutStep = player_.tutorial_step or 0

    if eventName == "npc_elder_talked" and tutStep == 0 then
        paused_ = true  -- 暂停，等玩家接受任务
        Tutorial.Dismiss()
        return
    end

    if eventName == "tutorial_accepted" then
        paused_ = false
        ShowStep(2)
        return
    end

    if eventName == "spot_bamboo_grove_arrived" and tutStep == 1 then
        ShowStep(3)
        return
    end

    if eventName == "battle_start" and tutStep == 1 then
        ShowStep(4)
        return
    end

    if eventName == "battle_end" and highestStep_ >= 4 then
        Tutorial.Dismiss()
        return
    end

    if eventName == "loot_appeared" then
        ShowStep(5)
        return
    end

    if eventName == "loot_picked" then
        ShowStep(6)
        return
    end

    if eventName == "nav_skills_click" and highestStep_ >= 6 and highestStep_ < 7 then
        ShowStep(7)
        return
    end

    if eventName == "subtab_背包_click" and highestStep_ >= 7 and highestStep_ < 8 then
        ShowStep(8)
        return
    end

    if eventName == "item_equipped" and highestStep_ >= 8 and highestStep_ < 9 then
        ShowStep(9)
        return
    end

    if eventName == "nav_cultivate_click" and highestStep_ >= 9 and highestStep_ < 10 then
        ShowStep(10)
        return
    end

    if eventName == "cultivate_started" and highestStep_ >= 10 and highestStep_ < 11 then
        ShowStep(11)
        return
    end

    if eventName == "nav_skills_click" and highestStep_ >= 11 and highestStep_ < 12 then
        ShowStep(12)
        return
    end

    if eventName == "subtab_属性_click" and highestStep_ >= 12 and highestStep_ < 13 then
        ShowStep(13)
        return
    end

    if eventName == "spot_village_center_arrived" and highestStep_ >= 13 and highestStep_ < 14 then
        ShowStep(14)
        return
    end

    if eventName == "elder_dialog_complete" then
        Tutorial.Dismiss()
        return
    end
end

--- 跳过教程（发送请求到服务端）
function Tutorial.Skip()
    Tutorial.Dismiss()
    lastShownStep_ = -1
    highestStep_ = 99
    -- 立即更新本地状态，避免地图等 UI 仍显示"引导未完成"
    if player_ then
        player_.tutorial_step = 3
    end
    -- 发送跳过请求到服务端
    local data = VariantMap()
    data["Action"] = Variant("skip_tutorial")
    network:GetServerConnection():SendRemoteEvent(StringHash("ReqSkipTutorial"), true, data)
end

return Tutorial
