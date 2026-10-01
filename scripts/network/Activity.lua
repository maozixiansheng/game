-- ============================================================================
-- network/Activity.lua - 活动系统（签到 / 成就 / 周常 / 限时活动 / PvP天梯）
-- ============================================================================
local Settings = require("config.Settings")
local cjson    = require("cjson")

local Activity = {}

-- ============================================================================
-- 工具函数
-- ============================================================================

local function getTodayStr()
    return os.date("%Y-%m-%d")
end

local function getWeekMondayStr()
    -- 返回本周一的日期字符串，用于周常重置判断
    local t = os.time()
    local wday = tonumber(os.date("%w", t))  -- 0=Sunday
    if wday == 0 then wday = 7 end
    local monday = t - (wday - 1) * 86400
    return os.date("%Y-%m-%d", monday)
end

--- 确保 pd.activity 存在
local function ensureActivity(pd)
    if not pd.activity then pd.activity = {} end
    return pd.activity
end

--- 确保 pd.weekly 存在并检查重置
local function ensureWeekly(pd)
    if not pd.weekly then
        pd.weekly = { week = "", kills = 0, wins = 0, bosses = 0, market = 0, cultivate_sec = 0, claimed = {} }
    end
    local curWeek = getWeekMondayStr()
    if pd.weekly.week ~= curWeek then
        pd.weekly = { week = curWeek, kills = 0, wins = 0, bosses = 0, market = 0, cultivate_sec = 0, claimed = {} }
    end
    return pd.weekly
end

--- 确保 pd.achievements 存在
local function ensureAchievements(pd)
    if not pd.achievements then pd.achievements = { claimed = {} } end
    if not pd.achievements.claimed then pd.achievements.claimed = {} end
    return pd.achievements
end

--- 确保 pd.pvp_ladder 存在
local function ensurePvpLadder(pd)
    if not pd.pvp_ladder then
        pd.pvp_ladder = {
            rating = Settings.PVP_LADDER.INITIAL_RATING,
            wins = 0,
            losses = 0,
            daily_attempts = 0,
            daily_date = "",
            last_match_time = 0,
        }
    end
    -- 每日重置挑战次数
    local today = getTodayStr()
    if pd.pvp_ladder.daily_date ~= today then
        pd.pvp_ladder.daily_attempts = 0
        pd.pvp_ladder.daily_date = today
    end
    return pd.pvp_ladder
end

-- ============================================================================
-- 七日签到（升级版，使用 Settings.SIGN_IN 配置）
-- ============================================================================

--- 执行签到逻辑，返回 success, msg, rewardDesc
function Activity.DoSignIn(pd)
    local act = ensureActivity(pd)
    local today = getTodayStr()

    if act.last_sign == today then
        return false, "今日已签到，明日再来", nil
    end

    -- 连续签到判断
    local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
    if act.last_sign == yesterday then
        act.sign_streak = (act.sign_streak or 0) + 1
    else
        act.sign_streak = 1
    end
    act.last_sign = today
    act.total_signs = (act.total_signs or 0) + 1

    -- 计算当前在7日循环中的位置（1~7）
    local cycle = Settings.SIGN_IN.CYCLE_DAYS
    local dayIndex = ((act.sign_streak - 1) % cycle) + 1
    local reward = Settings.SIGN_IN.REWARDS[dayIndex]

    -- 发放奖励
    local desc = reward.desc or ""
    if reward.silver then pd.silver = (pd.silver or 0) + reward.silver end
    if reward.spirit_stone then pd.spirit_stone = (pd.spirit_stone or 0) + reward.spirit_stone end
    if reward.potential then pd.potential = (pd.potential or 0) + reward.potential end
    if reward.items then
        if not pd.inventory then pd.inventory = {} end
        for _, item in ipairs(reward.items) do
            local found = false
            for _, inv in ipairs(pd.inventory) do
                if inv.id == item.id then
                    inv.count = (inv.count or 1) + (item.count or 1)
                    -- 补齐已有记录可能缺失的 type 字段
                    if not inv.type then
                        if Settings.PILLS and Settings.PILLS[item.id] then
                            inv.type = "pill"
                        elseif Settings.ALCHEMY_MATERIALS and Settings.ALCHEMY_MATERIALS[item.id] then
                            inv.type = "material"
                        end
                    end
                    found = true
                    break
                end
            end
            if not found then
                -- 推断 type：优先用 item.type，其次从 PILLS 定义中查找
                local itemType = item.type
                if not itemType and Settings.PILLS and Settings.PILLS[item.id] then
                    itemType = "pill"
                elseif not itemType and Settings.ALCHEMY_MATERIALS and Settings.ALCHEMY_MATERIALS[item.id] then
                    itemType = "material"
                end
                table.insert(pd.inventory, { id = item.id, count = item.count or 1, type = itemType })
            end
        end
    end

    return true, string.format("签到成功！连续%d天（第%d天奖励）", act.sign_streak, dayIndex), desc
end

--- 获取签到状态（用于推送给客户端）
function Activity.GetSignInStatus(pd)
    local act = ensureActivity(pd)
    local today = getTodayStr()
    local cycle = Settings.SIGN_IN.CYCLE_DAYS
    local streak = act.sign_streak or 0
    local dayIndex = streak > 0 and (((streak - 1) % cycle) + 1) or 0
    return {
        signed_today = (act.last_sign == today),
        sign_streak = streak,
        total_signs = act.total_signs or 0,
        current_day = dayIndex,
        cycle_days = cycle,
    }
end

-- ============================================================================
-- 成就系统
-- ============================================================================

--- 获取玩家某个成就的当前进度
local function getAchProgress(pd, achDef)
    local trigger = achDef.trigger
    if trigger == "kill_total" then return pd.total_kills or 0
    elseif trigger == "boss_count" then
        local n = 0
        if pd.boss_defeated then
            for _ in pairs(pd.boss_defeated) do n = n + 1 end
        end
        return n
    elseif trigger == "win_total" then return pd.total_wins or 0
    elseif trigger == "realm_reach" then return pd.realm or 1
    elseif trigger == "break_fail" then return pd.total_break_fails or 0
    elseif trigger == "has_guild" then return (pd.guild_id and pd.guild_id ~= "") and 1 or 0
    elseif trigger == "territory_own" then return pd.territory_wins or 0
    elseif trigger == "pvp_win" then
        local lad = pd.pvp_ladder
        return lad and lad.wins or 0
    elseif trigger == "silver_total" then return pd.total_silver_earned or 0
    elseif trigger == "market_sells" then return pd.total_market_sells or 0
    elseif trigger == "alchemy_level" then return pd.alchemy_level or 0
    elseif trigger == "forge_level" then return pd.forge_level or 0
    elseif trigger == "max_layer" then return pd.max_battlefield_layer or 2
    elseif trigger == "skill_count" then
        return pd.skills and #pd.skills or 0
    elseif trigger == "signin_total" then
        local act = pd.activity
        return act and act.total_signs or 0
    end
    return 0
end

--- 检查并解锁所有满足条件的成就（不自动领奖，需玩家手动领取）
function Activity.CheckAchievements(pd)
    local ach = ensureAchievements(pd)
    local unlocked = {}
    for _, achDef in ipairs(Settings.ACHIEVEMENTS) do
        if not ach.claimed[achDef.id] then
            local progress = getAchProgress(pd, achDef)
            if progress >= achDef.goal then
                -- 标记为可领取（但不自动领取）
                table.insert(unlocked, achDef.id)
            end
        end
    end
    return unlocked
end

--- 领取指定成就奖励
---@return boolean, string
function Activity.ClaimAchievement(pd, achId)
    local ach = ensureAchievements(pd)
    local achDef = Settings.ACHIEVEMENT_MAP[achId]
    if not achDef then return false, "成就不存在" end
    if ach.claimed[achId] then return false, "已领取" end

    -- 检查是否达标
    local progress = getAchProgress(pd, achDef)
    if progress < achDef.goal then
        return false, string.format("未达成（%d/%d）", progress, achDef.goal)
    end

    -- 发放奖励
    local r = achDef.rewards or {}
    if r.spirit_stone then pd.spirit_stone = (pd.spirit_stone or 0) + r.spirit_stone end
    if r.silver then pd.silver = (pd.silver or 0) + r.silver end
    if r.potential then pd.potential = (pd.potential or 0) + r.potential end
    ach.claimed[achId] = true

    return true, string.format("【%s】达成！", achDef.name)
end

--- 获取所有成就状态（用于推送）
function Activity.GetAchievementStates(pd)
    local ach = ensureAchievements(pd)
    local results = {}
    for _, achDef in ipairs(Settings.ACHIEVEMENTS) do
        local progress = getAchProgress(pd, achDef)
        table.insert(results, {
            id = achDef.id,
            name = achDef.name,
            desc = achDef.desc,
            category = achDef.category,
            progress = math.min(progress, achDef.goal),
            goal = achDef.goal,
            completed = progress >= achDef.goal,
            claimed = ach.claimed[achDef.id] == true,
        })
    end
    return results
end

-- ============================================================================
-- 周常任务
-- ============================================================================

--- 周常计数器递增
function Activity.IncrWeekly(pd, trigger, amount)
    local wk = ensureWeekly(pd)
    amount = amount or 1
    if trigger == "weekly_kill" then
        wk.kills = (wk.kills or 0) + amount
    elseif trigger == "weekly_win" then
        wk.wins = (wk.wins or 0) + amount
    elseif trigger == "weekly_boss" then
        wk.bosses = (wk.bosses or 0) + amount
    elseif trigger == "weekly_market" then
        wk.market = (wk.market or 0) + amount
    elseif trigger == "weekly_cultivate" then
        wk.cultivate_sec = (wk.cultivate_sec or 0) + amount
    end
end

--- 获取周常任务进度
local function getWeeklyProgress(wk, trigger)
    if trigger == "weekly_kill" then return wk.kills or 0
    elseif trigger == "weekly_win" then return wk.wins or 0
    elseif trigger == "weekly_boss" then return wk.bosses or 0
    elseif trigger == "weekly_market" then return wk.market or 0
    elseif trigger == "weekly_cultivate" then return wk.cultivate_sec or 0
    end
    return 0
end

--- 获取周常任务状态（用于推送）
function Activity.GetWeeklyStates(pd)
    local wk = ensureWeekly(pd)
    local results = {}
    for _, wqDef in ipairs(Settings.WEEKLY_QUESTS) do
        local progress = getWeeklyProgress(wk, wqDef.trigger)
        local completed = progress >= wqDef.goal
        local claimed = wk.claimed[wqDef.id] == true
        table.insert(results, {
            id = wqDef.id,
            name = wqDef.name,
            desc = wqDef.desc,
            progress = math.min(progress, wqDef.goal),
            goal = wqDef.goal,
            completed = completed,
            claimed = claimed,
            rewards = wqDef.rewards,
        })
    end
    return results
end

--- 领取周常任务奖励
---@return boolean, string
function Activity.ClaimWeekly(pd, questId)
    local wk = ensureWeekly(pd)
    local wqDef = nil
    for _, wq in ipairs(Settings.WEEKLY_QUESTS) do
        if wq.id == questId then wqDef = wq; break end
    end
    if not wqDef then return false, "周常任务不存在" end
    if wk.claimed[questId] then return false, "已领取" end

    local progress = getWeeklyProgress(wk, wqDef.trigger)
    if progress < wqDef.goal then return false, "未完成" end

    -- 发放奖励
    local r = wqDef.rewards or {}
    if r.spirit_stone then pd.spirit_stone = (pd.spirit_stone or 0) + r.spirit_stone end
    if r.silver then pd.silver = (pd.silver or 0) + r.silver end
    if r.potential then pd.potential = (pd.potential or 0) + r.potential end
    wk.claimed[questId] = true

    -- 检查全勤
    local allClaimed = true
    for _, wq in ipairs(Settings.WEEKLY_QUESTS) do
        if not wk.claimed[wq.id] then allClaimed = false; break end
    end
    local bonusMsg = ""
    if allClaimed then
        local bonus = Settings.WEEKLY_ALL_COMPLETE_REWARD
        if bonus.spirit_stone then pd.spirit_stone = (pd.spirit_stone or 0) + bonus.spirit_stone end
        bonusMsg = string.format(" +全勤灵石%d", bonus.spirit_stone or 0)
    end

    return true, string.format("【%s】奖励已领取%s", wqDef.name, bonusMsg)
end

-- ============================================================================
-- PvP 天梯
-- ============================================================================

--- 计算 ELO 评分变化
local function calcEloChange(ratingA, ratingB, win)
    local K = Settings.PVP_LADDER.K_FACTOR
    local expectedA = 1 / (1 + 10 ^ ((ratingB - ratingA) / 400))
    local scoreA = win and 1 or 0
    return math.floor(K * (scoreA - expectedA))
end

--- 获取段位信息
function Activity.GetRankByRating(rating)
    local ranks = Settings.PVP_LADDER.RANKS
    local result = ranks[1]
    for _, r in ipairs(ranks) do
        if rating >= r.min_rating then
            result = r
        end
    end
    return result
end

--- PvP 天梯匹配前验证
---@return boolean canMatch, string|nil errMsg
function Activity.CanLadderMatch(pd)
    local lad = ensurePvpLadder(pd)
    if lad.daily_attempts >= Settings.PVP_LADDER.DAILY_ATTEMPTS then
        return false, "今日挑战次数已用完"
    end
    local now = os.time()
    if now - (lad.last_match_time or 0) < Settings.PVP_LADDER.COOLDOWN_SEC then
        local remain = Settings.PVP_LADDER.COOLDOWN_SEC - (now - lad.last_match_time)
        return false, string.format("冷却中，还需%d秒", remain)
    end
    return true, nil
end

--- PvP 天梯匹配结果处理
---@param pd table 挑战者数据
---@param opponentRating number 对手积分
---@param win boolean 是否胜利
---@return table result 结果信息
function Activity.ProcessLadderResult(pd, opponentRating, win)
    local lad = ensurePvpLadder(pd)
    local ratingChange = calcEloChange(lad.rating, opponentRating, win)

    -- 叠加固定奖励/惩罚
    if win then
        ratingChange = ratingChange + Settings.PVP_LADDER.WIN_BONUS
    else
        ratingChange = ratingChange - Settings.PVP_LADDER.LOSE_PENALTY
    end

    local oldRating = lad.rating
    lad.rating = math.max(0, lad.rating + ratingChange)
    lad.daily_attempts = lad.daily_attempts + 1
    lad.last_match_time = os.time()

    if win then
        lad.wins = (lad.wins or 0) + 1
        -- 记录总赢数供成就用
        pd.total_wins = (pd.total_wins or 0) + 1
    else
        lad.losses = (lad.losses or 0) + 1
    end

    local oldRank = Activity.GetRankByRating(oldRating)
    local newRank = Activity.GetRankByRating(lad.rating)

    return {
        win = win,
        rating_change = ratingChange,
        new_rating = lad.rating,
        old_rank = oldRank.name,
        new_rank = newRank.name,
        rank_changed = oldRank.id ~= newRank.id,
    }
end

--- 获取天梯数据（用于推送）
function Activity.GetLadderData(pd)
    local lad = ensurePvpLadder(pd)
    local rank = Activity.GetRankByRating(lad.rating)
    local seasonInfo = Activity.GetSeasonInfo(pd)
    return {
        rating = lad.rating,
        rank_id = rank.id,
        rank_name = rank.name,
        wins = lad.wins or 0,
        losses = lad.losses or 0,
        daily_attempts = lad.daily_attempts,
        max_attempts = Settings.PVP_LADDER.DAILY_ATTEMPTS,
        season_id = seasonInfo.season_id,
        season_days_left = seasonInfo.days_left,
        season_peak_rank = seasonInfo.peak_rank_name,
    }
end

-- ============================================================================
-- 赛季系统
-- ============================================================================

--- 计算当前赛季编号（基于固定起始时间）
local SEASON_EPOCH = 1717200000  -- 2024-06-01 00:00:00 UTC 作为赛季纪元

local function getCurrentSeasonId()
    local now = os.time()
    local elapsed = now - SEASON_EPOCH
    local durationSec = Settings.PVP_LADDER.SEASON.DURATION_DAYS * 86400
    return math.floor(elapsed / durationSec) + 1
end

--- 获取当前赛季剩余天数
local function getSeasonDaysLeft()
    local now = os.time()
    local elapsed = now - SEASON_EPOCH
    local durationSec = Settings.PVP_LADDER.SEASON.DURATION_DAYS * 86400
    local intoSeason = elapsed % durationSec
    local remaining = durationSec - intoSeason
    return math.ceil(remaining / 86400)
end

--- 获取赛季信息
---@param pd table
---@return table seasonInfo
function Activity.GetSeasonInfo(pd)
    local lad = ensurePvpLadder(pd)
    local seasonId = getCurrentSeasonId()
    local peakRating = lad.season_peak_rating or lad.rating
    local peakRank = Activity.GetRankByRating(peakRating)
    return {
        season_id = seasonId,
        days_left = getSeasonDaysLeft(),
        peak_rating = peakRating,
        peak_rank_name = peakRank.name,
        peak_rank_id = peakRank.id,
    }
end

--- 确保玩家赛季数据是当前赛季，若过期则自动重置
---@param pd table
---@return boolean wasReset 是否刚执行了重置
function Activity.EnsureCurrentSeason(pd)
    local lad = ensurePvpLadder(pd)
    local currentSeason = getCurrentSeasonId()

    if (lad.season_id or 0) >= currentSeason then
        return false  -- 已是当前赛季
    end

    -- 记录上赛季最高段位（用于发放奖励）
    lad.last_season_peak_rating = lad.season_peak_rating or lad.rating
    lad.last_season_id = lad.season_id or (currentSeason - 1)

    -- 积分软重置
    local cfg = Settings.PVP_LADDER.SEASON
    local newRating = math.max(cfg.RESET_FLOOR, math.floor(lad.rating * cfg.RESET_FACTOR))
    lad.rating = newRating

    -- 重置赛季统计
    lad.wins = 0
    lad.losses = 0
    lad.season_peak_rating = newRating
    lad.season_id = currentSeason
    lad.demotion_shield = cfg.DEMOTION_SHIELD
    lad.season_reward_claimed = false

    return true
end

--- 更新赛季最高积分（每场比赛后调用）
---@param pd table
function Activity.UpdateSeasonPeak(pd)
    local lad = ensurePvpLadder(pd)
    if lad.rating > (lad.season_peak_rating or 0) then
        lad.season_peak_rating = lad.rating
    end
end

--- 掉段保护检查（仅在 DEMOTION_THRESHOLD 段位以下生效）
---@param pd table
---@param oldRating number
---@return boolean protected 是否被保护
function Activity.CheckDemotionShield(pd, oldRating)
    local lad = ensurePvpLadder(pd)
    local cfg = Settings.PVP_LADDER.SEASON

    -- 只有跨段才检查
    local oldRank = Activity.GetRankByRating(oldRating)
    local newRank = Activity.GetRankByRating(lad.rating)
    if oldRank.id == newRank.id then
        return false  -- 未跨段，不需要保护
    end

    -- 高于保护线段位不享受保护
    local ranks = Settings.PVP_LADDER.RANKS
    local thresholdIdx = 0
    for i, r in ipairs(ranks) do
        if r.id == cfg.DEMOTION_THRESHOLD then thresholdIdx = i; break end
    end
    local oldIdx = 0
    for i, r in ipairs(ranks) do
        if r.id == oldRank.id then oldIdx = i; break end
    end
    if oldIdx > thresholdIdx then
        return false  -- 高段位无保护
    end

    -- 消耗保护次数
    if (lad.demotion_shield or 0) > 0 then
        lad.demotion_shield = lad.demotion_shield - 1
        lad.rating = oldRating  -- 恢复积分
        return true
    end
    return false
end

--- 领取赛季奖励
---@param pd table
---@return table|nil rewards, string|nil error
function Activity.ClaimSeasonReward(pd)
    local lad = ensurePvpLadder(pd)

    if lad.season_reward_claimed then
        return nil, "本赛季奖励已领取"
    end

    local peakRating = lad.last_season_peak_rating or 0
    if peakRating <= 0 then
        return nil, "上赛季无战绩"
    end

    local peakRank = Activity.GetRankByRating(peakRating)
    local rewards = Settings.PVP_LADDER.SEASON_REWARDS[peakRank.id]
    if not rewards then
        return nil, "无可领取奖励"
    end

    -- 标记已领取
    lad.season_reward_claimed = true

    return {
        rank_name = peakRank.name,
        rewards = rewards,
    }, nil
end

-- ============================================================================
-- 限时活动
-- ============================================================================

--- 检查活动是否当前激活
local function isEventActive(template)
    local rule = template.trigger_rule
    local wday = tonumber(os.date("%w"))  -- 0=Sun, 6=Sat
    local day = tonumber(os.date("%d"))

    if rule == "weekend" then
        return wday == 0 or wday == 6
    elseif rule == "friday" then
        return wday == 5
    elseif rule == "month_start" then
        return day >= 1 and day <= 3
    end
    return false
end

--- 获取当前激活的限时活动列表
function Activity.GetActiveEvents()
    local active = {}
    for _, tmpl in ipairs(Settings.EVENTS_SYSTEM.TEMPLATES) do
        if isEventActive(tmpl) then
            table.insert(active, {
                id = tmpl.id,
                type = tmpl.type,
                name = tmpl.name,
                desc = tmpl.desc,
                multiplier = tmpl.multiplier,
            })
        end
    end
    return active
end

--- 获取指定类型活动的倍率（无活动时返回1.0）
function Activity.GetEventMultiplier(eventType)
    for _, tmpl in ipairs(Settings.EVENTS_SYSTEM.TEMPLATES) do
        if tmpl.type == eventType and isEventActive(tmpl) then
            return tmpl.multiplier
        end
    end
    return 1.0
end

-- ============================================================================
-- 触发器接口（供 Server.lua 各系统调用）
-- ============================================================================

--- 击杀怪物时
function Activity.OnKillMonster(pd)
    Activity.IncrWeekly(pd, "weekly_kill", 1)
end

--- 赢得战斗时
function Activity.OnWinBattle(pd)
    Activity.IncrWeekly(pd, "weekly_win", 1)
    -- 累计总赢数（成就用）
    pd.total_wins = (pd.total_wins or 0) + 1
end

--- 挑战Boss时
function Activity.OnChallengeBoss(pd)
    Activity.IncrWeekly(pd, "weekly_boss", 1)
end

--- 交易阁成交时
function Activity.OnMarketSell(pd)
    Activity.IncrWeekly(pd, "weekly_market", 1)
    pd.total_market_sells = (pd.total_market_sells or 0) + 1
end

--- 修炼时长累加
function Activity.OnCultivateTime(pd, deltaSec)
    Activity.IncrWeekly(pd, "weekly_cultivate", deltaSec)
end

--- 获得银两时（累计统计，成就用）
function Activity.OnEarnSilver(pd, amount)
    pd.total_silver_earned = (pd.total_silver_earned or 0) + amount
end

--- 突破失败时（成就用）
function Activity.OnBreakFail(pd)
    pd.total_break_fails = (pd.total_break_fails or 0) + 1
end

--- 领地战胜利时（成就用）
function Activity.OnTerritoryWin(pd)
    pd.territory_wins = (pd.territory_wins or 0) + 1
end

return Activity
