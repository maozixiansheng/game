-- ============================================================================
-- network/Quest.lua - 任务系统（主线 + 日常 + Boss进度）
-- ============================================================================
local Settings = require("config.Settings")
local Shared   = require("network.Shared")

local Quest = {}

-- ============================================================================
-- 初始化
-- ============================================================================

--- 初始化玩家任务数据
---@param pd table 玩家数据
function Quest.InitPlayer(pd)
    -- Boss 进度
    if not pd.boss_defeated then pd.boss_defeated = {} end
    if not pd.max_battlefield_layer then
        pd.max_battlefield_layer = Settings.BATTLEFIELD_INITIAL_LAYERS
    end
    -- 主线进度
    if not pd.main_quest_index then pd.main_quest_index = 1 end
    if not pd.main_quest_progress then pd.main_quest_progress = 0 end
    -- 累计统计（用于 kill_total 类主线）
    if not pd.total_kills then pd.total_kills = 0 end
    -- 日常任务
    if not pd.daily then
        pd.daily = { date = "", kills = 0, battles = 0, boss_challenges = 0, online_sec = 0, claimed = {} }
    end
end

-- ============================================================================
-- 日常任务：日期重置
-- ============================================================================

local function getTodayStr()
    return os.date("%Y-%m-%d")
end

--- 检查并重置日常（如果跨天了）
local function ensureDailyReset(pd)
    local today = getTodayStr()
    if pd.daily.date ~= today then
        pd.daily = { date = today, kills = 0, battles = 0, boss_challenges = 0, online_sec = 0, claimed = {} }
    end
end

-- ============================================================================
-- 主线任务：核心逻辑
-- ============================================================================

--- 获取当前主线任务定义
function Quest.GetCurrentMainQuest(pd)
    local idx = pd.main_quest_index or 1
    return Settings.MAIN_QUESTS[idx]
end

--- 检查当前主线任务是否完成
local function checkMainQuestComplete(pd)
    local qDef = Quest.GetCurrentMainQuest(pd)
    if not qDef then return false end
    return (pd.main_quest_progress or 0) >= qDef.goal
end

--- 完成当前主线任务，发放奖励，推进到下一个
function Quest.CompleteMainQuest(pd, conn)
    local qDef = Quest.GetCurrentMainQuest(pd)
    if not qDef then return end

    -- 发放奖励
    local r = qDef.rewards or {}
    if r.exp then pd.realm_exp = (pd.realm_exp or 0) + r.exp end
    if r.silver then pd.silver = (pd.silver or 0) + r.silver end
    if r.spirit_stone then pd.spirit_stone = (pd.spirit_stone or 0) + r.spirit_stone end
    if r.potential then pd.potential = (pd.potential or 0) + r.potential end

    -- 通知客户端
    if conn then
        local rewardStr = ""
        if r.exp then rewardStr = rewardStr .. string.format("经验+%d ", r.exp) end
        if r.silver then rewardStr = rewardStr .. string.format("银两+%d ", r.silver) end
        if r.spirit_stone then rewardStr = rewardStr .. string.format("灵石+%d ", r.spirit_stone) end
        if r.potential then rewardStr = rewardStr .. string.format("潜力+%d ", r.potential) end

        local Server = require("network.Server")
        Server.PushLog(conn, string.format("<绿>【主线完成】%s —— %s</绿>", qDef.name, rewardStr))
    end

    -- 经验升级检查（大量经验可能连升多层）
    if r.exp then
        local Server = require("network.Server")
        Server.CheckLevelUp(pd)
    end

    -- 推进到下一个任务
    pd.main_quest_index = (pd.main_quest_index or 1) + 1
    pd.main_quest_progress = 0

    -- 新任务可能已有累计进度（如 kill_total 类）
    Quest._syncMainQuestProgress(pd)

    -- 推送更新
    Quest.PushQuestState(pd, conn)
end

--- 同步主线累计类任务进度（登录时、切任务时调用）
function Quest._syncMainQuestProgress(pd)
    local qDef = Quest.GetCurrentMainQuest(pd)
    if not qDef then return end

    if qDef.trigger == "kill_total" then
        pd.main_quest_progress = math.min(pd.total_kills or 0, qDef.goal)
    elseif qDef.trigger == "join_guild" then
        if pd.guild_id and pd.guild_id ~= "" then
            pd.main_quest_progress = 1
        end
    end
end

-- ============================================================================
-- 触发器：各系统调用
-- ============================================================================

--- 玩家击杀怪物时调用
---@param pd table 玩家数据
---@param conn userdata 连接
---@param layerNum number|nil 当前战场层
function Quest.OnKillMonster(pd, conn, layerNum)
    -- 累计统计
    pd.total_kills = (pd.total_kills or 0) + 1

    -- 日常
    ensureDailyReset(pd)
    pd.daily.kills = (pd.daily.kills or 0) + 1

    -- 主线检查
    local qDef = Quest.GetCurrentMainQuest(pd)
    if qDef then
        if qDef.trigger == "kill_total" then
            pd.main_quest_progress = math.min(pd.total_kills, qDef.goal)
        elseif qDef.trigger == "kill_in_layers" and layerNum then
            local validLayers = qDef.param or {}
            for _, l in ipairs(validLayers) do
                if l == layerNum then
                    pd.main_quest_progress = (pd.main_quest_progress or 0) + 1
                    break
                end
            end
        end
        if checkMainQuestComplete(pd) then
            Quest.CompleteMainQuest(pd, conn)
        else
            -- 进度变化但未完成，也推送给客户端刷新UI
            Quest.PushQuestState(pd, conn)
        end
    end
end

--- 玩家进入战场层时调用
function Quest.OnEnterLayer(pd, conn, layerNum)
    local qDef = Quest.GetCurrentMainQuest(pd)
    if qDef and qDef.trigger == "enter_layer" and layerNum == qDef.param then
        pd.main_quest_progress = 1
        if checkMainQuestComplete(pd) then
            Quest.CompleteMainQuest(pd, conn)
        end
    end
end

--- 玩家挑战Boss时调用（发起挑战即算，不论胜负）
function Quest.OnChallengeBoss(pd, conn, bossId)
    -- 日常
    ensureDailyReset(pd)
    pd.daily.boss_challenges = (pd.daily.boss_challenges or 0) + 1

    -- 主线
    local qDef = Quest.GetCurrentMainQuest(pd)
    if qDef and qDef.trigger == "challenge_boss" then
        -- 支持 param 为单个字符串或数组
        local matched = false
        if type(qDef.param) == "table" then
            for _, p in ipairs(qDef.param) do
                if p == bossId then matched = true; break end
            end
        else
            matched = (qDef.param == bossId)
        end
        if matched then
            pd.main_quest_progress = (pd.main_quest_progress or 0) + 1
            if checkMainQuestComplete(pd) then
                Quest.CompleteMainQuest(pd, conn)
            else
                Quest.PushQuestState(pd, conn)
            end
        else
            print(string.format("[Quest] challenge_boss 未匹配: bossId=%s, param=%s",
                tostring(bossId), tostring(qDef.param)))
        end
    end
end

--- Boss 被击败时调用
function Quest.OnBossDefeated(pd, conn, bossId)
    -- 主线
    local qDef = Quest.GetCurrentMainQuest(pd)
    if qDef and qDef.trigger == "defeat_boss" then
        local matched = false
        if type(qDef.param) == "table" then
            for _, p in ipairs(qDef.param) do
                if p == bossId then matched = true; break end
            end
        else
            matched = (qDef.param == bossId)
        end
        if matched then
            pd.main_quest_progress = 1
            if checkMainQuestComplete(pd) then
                Quest.CompleteMainQuest(pd, conn)
            end
        end
    end
    -- 推送 Boss 进度更新
    Quest.PushQuestState(pd, conn)
end

--- 战斗结束时调用（无论胜负，计入日常战斗次数）
function Quest.OnBattleFinished(pd, conn)
    ensureDailyReset(pd)
    pd.daily.battles = (pd.daily.battles or 0) + 1
end

--- 加入帮会时调用
function Quest.OnJoinGuild(pd, conn)
    local qDef = Quest.GetCurrentMainQuest(pd)
    if qDef and qDef.trigger == "join_guild" then
        pd.main_quest_progress = 1
        if checkMainQuestComplete(pd) then
            Quest.CompleteMainQuest(pd, conn)
        end
    end
end

--- 境界突破时调用
function Quest.OnBreakthrough(pd, conn)
    local qDef = Quest.GetCurrentMainQuest(pd)
    if qDef and qDef.trigger == "breakthrough" then
        pd.main_quest_progress = (pd.main_quest_progress or 0) + 1
        if checkMainQuestComplete(pd) then
            Quest.CompleteMainQuest(pd, conn)
        end
    end
end

--- 在线时长更新（由服务端定时调用，每60秒一次）
function Quest.OnOnlineTime(pd, conn, deltaSec)
    ensureDailyReset(pd)
    pd.daily.online_sec = (pd.daily.online_sec or 0) + deltaSec
end

-- ============================================================================
-- 日常任务：查询
-- ============================================================================

--- 获取日常任务状态列表
function Quest.GetDailyQuestStates(pd)
    ensureDailyReset(pd)
    local results = {}
    for _, dq in ipairs(Settings.DAILY_QUESTS) do
        local progress = 0
        if dq.trigger == "online_time" then
            progress = pd.daily.online_sec or 0
        elseif dq.trigger == "daily_kill" then
            progress = pd.daily.kills or 0
        elseif dq.trigger == "daily_battle" then
            progress = pd.daily.battles or 0
        elseif dq.trigger == "daily_win" then
            progress = pd.daily.wins or 0
        elseif dq.trigger == "daily_boss_challenge" then
            progress = pd.daily.boss_challenges or 0
        end
        progress = math.floor(progress)
        local completed = progress >= dq.goal
        local claimed = pd.daily.claimed[dq.id] == true
        table.insert(results, {
            id = dq.id,
            name = dq.name,
            desc = dq.desc,
            progress = math.min(progress, dq.goal),
            goal = dq.goal,
            completed = completed,
            claimed = claimed,
            rewards = dq.rewards,
        })
    end
    return results
end

--- 检查是否全勤（所有日常都已领取）
function Quest.IsDailyAllClaimed(pd)
    ensureDailyReset(pd)
    for _, dq in ipairs(Settings.DAILY_QUESTS) do
        if not pd.daily.claimed[dq.id] then return false end
    end
    return true
end

-- ============================================================================
-- 日常任务：领取奖励
-- ============================================================================

--- 领取指定日常任务奖励
---@return boolean success
---@return string|nil errMsg
function Quest.ClaimDailyReward(pd, conn, questId)
    ensureDailyReset(pd)
    -- 查找任务
    local dqDef = nil
    for _, dq in ipairs(Settings.DAILY_QUESTS) do
        if dq.id == questId then dqDef = dq; break end
    end
    if not dqDef then return false, "任务不存在" end
    if pd.daily.claimed[questId] then return false, "已领取" end

    -- 检查完成
    local progress = 0
    if dqDef.trigger == "online_time" then progress = pd.daily.online_sec or 0
    elseif dqDef.trigger == "daily_kill" then progress = pd.daily.kills or 0
    elseif dqDef.trigger == "daily_battle" then progress = pd.daily.battles or 0
    elseif dqDef.trigger == "daily_boss_challenge" then progress = pd.daily.boss_challenges or 0
    end
    if progress < dqDef.goal then return false, "未完成" end

    -- 发放奖励
    local r = dqDef.rewards or {}
    if r.exp then pd.realm_exp = (pd.realm_exp or 0) + r.exp end
    if r.silver then pd.silver = (pd.silver or 0) + r.silver end
    if r.spirit_stone then pd.spirit_stone = (pd.spirit_stone or 0) + r.spirit_stone end
    if r.potential then pd.potential = (pd.potential or 0) + r.potential end
    pd.daily.claimed[questId] = true

    -- 经验升级检查
    if r.exp then
        local Server = require("network.Server")
        Server.CheckLevelUp(pd)
    end

    if conn then
        local Server = require("network.Server")
        -- 构造奖励描述
        local parts = {}
        if r.exp then parts[#parts+1] = string.format("经验+%d", r.exp) end
        if r.silver then parts[#parts+1] = string.format("银两+%d", r.silver) end
        if r.spirit_stone then parts[#parts+1] = string.format("灵石+%d", r.spirit_stone) end
        if r.potential then parts[#parts+1] = string.format("潜力+%d", r.potential) end
        local rewardStr = #parts > 0 and table.concat(parts, " ") or ""
        Server.PushLog(conn, string.format("<绿>【日常完成】%s %s</绿>", dqDef.name, rewardStr))
    end

    -- 检查全勤
    if Quest.IsDailyAllClaimed(pd) then
        local bonus = Settings.DAILY_ALL_COMPLETE_REWARD
        if bonus.spirit_stone then pd.spirit_stone = (pd.spirit_stone or 0) + bonus.spirit_stone end
        if conn then
            local Server = require("network.Server")
            Server.PushLog(conn, string.format("<金>【全勤奖励】额外灵石+%d</金>", bonus.spirit_stone or 0))
        end
    end

    Quest.PushQuestState(pd, conn)
    return true
end

-- ============================================================================
-- 网络推送
-- ============================================================================

--- 推送完整任务状态给客户端
function Quest.PushQuestState(pd, conn)
    if not conn then return end

    -- 主线
    local qDef = Quest.GetCurrentMainQuest(pd)
    local data = VariantMap()
    if qDef then
        data["MainQuestId"]       = Variant(qDef.id)
        data["MainQuestName"]     = Variant(qDef.name)
        data["MainQuestDesc"]     = Variant(qDef.desc)
        data["MainQuestChapter"]  = Variant(qDef.chapter)
        data["MainQuestProgress"] = Variant(pd.main_quest_progress or 0)
        data["MainQuestGoal"]     = Variant(qDef.goal)
    else
        data["MainQuestId"]       = Variant("")
        data["MainQuestName"]     = Variant("主线已通关")
        data["MainQuestDesc"]     = Variant("所有主线任务已完成！")
        data["MainQuestChapter"]  = Variant(0)
        data["MainQuestProgress"] = Variant(0)
        data["MainQuestGoal"]     = Variant(0)
    end

    -- 日常（用分号分隔格式序列化）
    local dailyStates = Quest.GetDailyQuestStates(pd)
    local dailyParts = {}
    for _, ds in ipairs(dailyStates) do
        -- 格式: id|progress|goal|claimed
        table.insert(dailyParts, string.format("%s|%d|%d|%s",
            ds.id, math.floor(ds.progress), math.floor(ds.goal), ds.claimed and "1" or "0"))
    end
    data["DailyQuests"] = Variant(table.concat(dailyParts, ";"))

    -- Boss 进度
    data["MaxLayer"] = Variant(pd.max_battlefield_layer or Settings.BATTLEFIELD_INITIAL_LAYERS)

    -- 门派试炼进行中的任务（格式: "sectId|questName|progress|goal;..."）
    local trialParts = {}
    if pd.sect_trials then
        for sectId, trial in pairs(pd.sect_trials) do
            if trial.status == "accepted" then
                local quest = Settings.SECT_TRIAL and Settings.SECT_TRIAL.QUESTS[sectId]
                if quest then
                    local progress = trial.progress or 0
                    local total = quest.count or 1
                    table.insert(trialParts, string.format("%s|%s|%d|%d",
                        sectId, quest.name, progress, total))
                end
            end
        end
    end
    data["SectTrials"] = Variant(table.concat(trialParts, ";"))

    conn:SendRemoteEvent(Settings.EVENTS.RES_QUEST_INFO, true, data)
end

-- 兼容旧接口
Quest.PushActiveQuest = Quest.PushQuestState

--- 战斗胜利时调用（仅胜利才计入）
function Quest.OnWinBattle(pd, conn)
    ensureDailyReset(pd)
    pd.daily.wins = (pd.daily.wins or 0) + 1

    -- 主线检查：win_battle 触发器
    local qDef = Quest.GetCurrentMainQuest(pd)
    if qDef and qDef.trigger == "win_battle" then
        pd.main_quest_progress = (pd.main_quest_progress or 0) + 1
        if checkMainQuestComplete(pd) then
            Quest.CompleteMainQuest(pd, conn)
        end
    end
end
function Quest.OnJoinSect(pd, conn) end
function Quest.OnStartCultivate(pd, conn) end
function Quest.OnEnterScene(pd, conn, sceneName) end
function Quest.OnRealmUp(pd, conn, realm, layer) end
function Quest.OnEquipItem(pd, conn) end
function Quest.OnLearnSkill(pd, conn) end

return Quest
