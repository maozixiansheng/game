-- ============================================================================
-- game/Cultivation.lua - 修炼逻辑（服务端专用）
-- ============================================================================

local Cultivation = {}
local Shared = require("network.Shared")
local Settings = Shared.Settings

-- ============================================================================
-- 修炼状态（内存中）
-- ============================================================================
-- 正在打坐的玩家 { [uid] = { skillId, startTime, costMult } }
local cultivatingPlayers = {}

-- 开始修炼
---@param playerData table
---@param skillId string
---@param costMultiplier? number 消耗倍率，默认1.2(自主修炼)
function Cultivation.StartCultivate(playerData, skillId, costMultiplier)
    costMultiplier = costMultiplier or Settings.CULTIVATE_COST_MULT.SELF

    -- 检查玩家是否拥有该功法
    local ownedSkill = Cultivation.GetOwnedSkill(playerData, skillId)
    if not ownedSkill then
        return false, "你没有学习这门功法"
    end

    local skillDef = Shared.GetSkillDef(skillId)
    if not skillDef then
        return false, "未知功法"
    end

    -- 检查是否已满级
    if ownedSkill.proficiency >= skillDef.max_proficiency then
        return false, string.format("《%s》已达满级，无法继续修炼", skillDef.name)
    end

    -- 检查潜能
    if (playerData.potential or 0) <= 0 then
        return false, "潜能不足，无法修炼（击杀妖兽可获得潜能）"
    end

    playerData.cultivating = skillId
    playerData.cultivate_cost_mult = costMultiplier
    cultivatingPlayers[playerData.uid] = {
        skillId = skillId,
        startTime = os.time(),
        costMult = costMultiplier,
    }

    local multLabel = costMultiplier <= 1.0 and "（师傅指导）" or ""
    return true, string.format("开始修炼%s%s，盘膝打坐，气运丹田……", skillDef.name, multLabel)
end

-- 停止修炼
function Cultivation.StopCultivate(playerData)
    local uid = playerData.uid
    if not playerData.cultivating or playerData.cultivating == "" then
        return false, "你当前没有在修炼"
    end

    local skillId = playerData.cultivating
    local skillDef = Shared.GetSkillDef(skillId)
    playerData.cultivating = ""
    playerData.cultivate_cost_mult = nil
    playerData.spirit_stone_boost = nil
    cultivatingPlayers[uid] = nil

    return true, string.format("停止修炼%s", skillDef and skillDef.name or skillId)
end

-- 每帧更新修炼（在Server Update中调用，dt为秒）
-- 新逻辑：持续消耗潜能，按 grade 对应的总消耗比例转换为熟练度
function Cultivation.Update(playerData, dt)
    if not playerData.cultivating or playerData.cultivating == "" then return end

    local skillId = playerData.cultivating
    local skillDef = Shared.GetSkillDef(skillId)
    if not skillDef then return end

    local ownedSkill = Cultivation.GetOwnedSkill(playerData, skillId)
    if not ownedSkill then return end

    -- 已满级则停止
    if ownedSkill.proficiency >= skillDef.max_proficiency then
        playerData.cultivating = ""
        playerData.cultivate_cost_mult = nil
    playerData.spirit_stone_boost = nil
        return
    end

    -- 获取消耗倍率
    local costMult = playerData.cultivate_cost_mult or Settings.CULTIVATE_COST_MULT.SELF
    local info = cultivatingPlayers[playerData.uid]
    if info then costMult = info.costMult or costMult end

    -- 计算速率
    local profPerSec, drainPerSec = Shared.CalcCultivateRate(
        skillDef.grade, skillDef.max_proficiency, costMult
    )

    -- 本帧潜能消耗和熟练度获得
    local potentialCost = drainPerSec * dt
    local profGain = profPerSec * dt

    -- 帮会修炼加成（由 Server 游戏循环注入）
    local cultBonus = playerData.guild_cult_bonus or 1.0
    if cultBonus > 1.0 then
        profGain = profGain * cultBonus
    end

    -- 灵石加速倍率
    local stoneBoost = playerData.spirit_stone_boost or 1.0
    if stoneBoost > 1.0 then
        profGain = profGain * stoneBoost
    end

    if (playerData.potential or 0) < potentialCost then
        -- 潜能不足，按剩余潜能等比缩放
        local ratio = (playerData.potential or 0) / potentialCost
        profGain = profGain * ratio
        playerData.potential = 0
        -- 潜能耗尽，自动停止
        playerData.cultivating = ""
        playerData.cultivate_cost_mult = nil
    playerData.spirit_stone_boost = nil
        cultivatingPlayers[playerData.uid] = nil
    else
        playerData.potential = (playerData.potential or 0) - potentialCost
    end

    -- 检查是否会超过阶段边界或上限
    local oldTier = Shared.GetProficiencyTier(ownedSkill.proficiency, skillDef.max_proficiency)
    local newProf = math.min(skillDef.max_proficiency, ownedSkill.proficiency + profGain)
    local newTier = Shared.GetProficiencyTier(newProf, skillDef.max_proficiency)

    -- 计算阶段上界（累加 ratio 再一次性乘法，与 GetProficiencyTier 完全一致）
    local function getTierCeiling(tier, maxProf)
        ---@type table[]
        local tiers = Settings.PROFICIENCY_TIERS
        local totalRatio = 0
        for _, t in ipairs(tiers) do totalRatio = totalRatio + t.ratio end
        local ratioAcc = 0
        for i = 1, math.min(tier, #tiers) do
            ratioAcc = ratioAcc + tiers[i].ratio
        end
        return maxProf * (ratioAcc / totalRatio)
    end

    local shouldStop = false
    if newProf >= skillDef.max_proficiency then
        -- 满级停止
        newProf = skillDef.max_proficiency
        shouldStop = true
    elseif newTier > oldTier then
        -- 跨阶段：卡在当前阶段的上界
        local ceiling = getTierCeiling(oldTier, skillDef.max_proficiency)
        -- 浮点保护：如果当前已在边界，直接进入下一阶而非卡住
        if ownedSkill.proficiency >= ceiling - 1e-9 then
            newProf = ceiling
            -- 不停止，允许继续进入下一阶
        else
            newProf = ceiling
            shouldStop = true
        end
    end

    -- 按实际使用量退还多扣的潜能
    local actualGain = newProf - ownedSkill.proficiency
    if actualGain < profGain and profGain > 0 then
        local usedRatio = actualGain / profGain
        local refund = potentialCost * (1 - usedRatio)
        playerData.potential = (playerData.potential or 0) + refund
    end

    if shouldStop then
        playerData.cultivating = ""
        playerData.cultivate_cost_mult = nil
    playerData.spirit_stone_boost = nil
        cultivatingPlayers[playerData.uid] = nil
    end

    -- 增加熟练度
    ownedSkill.proficiency = newProf
end

-- 即时修炼：一次性消耗指定潜能，立刻获得熟练度（不跨阶）
---@param playerData table
---@param skillId string
---@param budget number 本次投入的潜能量
---@param costMultiplier? number 消耗倍率
---@return boolean ok
---@return string msg
---@return number? profGain 实际获得的熟练度
function Cultivation.InstantCultivate(playerData, skillId, budget, costMultiplier)
    costMultiplier = costMultiplier or Settings.CULTIVATE_COST_MULT.SELF

    local ownedSkill = Cultivation.GetOwnedSkill(playerData, skillId)
    if not ownedSkill then
        return false, "你没有学习这门功法", 0
    end

    local skillDef = Shared.GetSkillDef(skillId)
    if not skillDef then
        return false, "未知功法", 0
    end

    if ownedSkill.proficiency >= skillDef.max_proficiency then
        return false, string.format("《%s》已达满级", skillDef.name), 0
    end

    local potential = playerData.potential or 0
    if potential <= 0 then
        return false, "潜能不足", 0
    end

    -- 限制 budget 不超过实际潜能
    budget = math.min(budget, potential)
    if budget <= 0 then
        return false, "投入潜能不能为 0", 0
    end

    -- 计算速率比（每点潜能获得多少熟练度）
    local profPerSec, drainPerSec = Shared.CalcCultivateRate(skillDef.grade, skillDef.max_proficiency, costMultiplier)
    local profPerPotential = profPerSec / drainPerSec  -- 每消耗1点潜能获得的熟练度

    -- 帮会修炼加成
    local cultBonus = playerData.guild_cult_bonus or 1.0
    if cultBonus > 1.0 then
        profPerPotential = profPerPotential * cultBonus
    end

    -- 灵石加速倍率
    local stoneBoost = playerData.spirit_stone_boost or 1.0
    if stoneBoost > 1.0 then
        profPerPotential = profPerPotential * stoneBoost
    end

    -- 计算熟练度增量
    local profGain = budget * profPerPotential

    -- 阶段边界限制：不跨阶
    local oldTier = Shared.GetProficiencyTier(ownedSkill.proficiency, skillDef.max_proficiency)
    local newProf = math.min(skillDef.max_proficiency, ownedSkill.proficiency + profGain)
    local newTier = Shared.GetProficiencyTier(newProf, skillDef.max_proficiency)

    if newTier > oldTier and newProf < skillDef.max_proficiency then
        -- 卡在当前阶段上界
        local tiers = Settings.PROFICIENCY_TIERS
        local totalRatio = 0
        for _, t in ipairs(tiers) do totalRatio = totalRatio + t.ratio end
        local ratioAcc = 0
        for i = 1, oldTier do ratioAcc = ratioAcc + tiers[i].ratio end
        local ceiling = skillDef.max_proficiency * (ratioAcc / totalRatio)
        -- 浮点保护：如果当前已在边界（差值极小），不再卡住，允许进入下一阶
        if ownedSkill.proficiency >= ceiling - 1e-9 then
            -- 已在边界，不需要 clamp，保持 newProf 进入下一阶
        else
            newProf = ceiling
        end
    end

    -- 实际熟练度增量
    local actualGain = newProf - ownedSkill.proficiency
    -- 按实际使用量计算实际消耗的潜能
    local actualBudget = budget
    if actualGain < profGain and profGain > 0 then
        actualBudget = math.ceil(budget * (actualGain / profGain))
    end

    -- 扣潜能、加熟练度
    playerData.potential = potential - actualBudget
    ownedSkill.proficiency = newProf

    return true, string.format("修炼《%s》完成，熟练度 +%.2f", skillDef.name, actualGain), actualGain
end

-- 离线修炼结算
function Cultivation.CalcOffline(playerData, offlineSeconds)
    if not playerData.cultivating or playerData.cultivating == "" then return 0, 0 end

    local skillId = playerData.cultivating
    local skillDef = Shared.GetSkillDef(skillId)
    if not skillDef then return 0, 0 end

    local ownedSkill = Cultivation.GetOwnedSkill(playerData, skillId)
    if not ownedSkill then return 0, 0 end

    -- 获取消耗倍率（离线修炼沿用下线时的倍率）
    local costMult = playerData.cultivate_cost_mult or Settings.CULTIVATE_COST_MULT.SELF

    -- 计算速率
    local profPerSec, drainPerSec = Shared.CalcCultivateRate(
        skillDef.grade, skillDef.max_proficiency, costMult
    )

    -- 离线期间总消耗和总获得
    local totalDrain = drainPerSec * offlineSeconds
    local totalGain = profPerSec * offlineSeconds

    -- 受潜能限制
    if (playerData.potential or 0) < totalDrain then
        local ratio = (playerData.potential or 0) / totalDrain
        totalGain = totalGain * ratio
        totalDrain = playerData.potential or 0
    end

    -- 受熟练度上限限制
    local remaining = skillDef.max_proficiency - ownedSkill.proficiency
    if totalGain > remaining then
        local usedRatio = remaining / totalGain
        totalDrain = totalDrain * usedRatio
        totalGain = remaining
    end

    playerData.potential = (playerData.potential or 0) - totalDrain
    ownedSkill.proficiency = math.min(skillDef.max_proficiency, ownedSkill.proficiency + totalGain)

    -- 如果潜能耗尽或已满，停止修炼
    if (playerData.potential or 0) <= 0 or ownedSkill.proficiency >= skillDef.max_proficiency then
        playerData.cultivating = ""
        playerData.cultivate_cost_mult = nil
    playerData.spirit_stone_boost = nil
    end

    return totalGain, totalDrain
end

-- 学习新功法（获得功法时调用）
function Cultivation.LearnSkill(playerData, skillId, bound)
    -- 检查是否已有
    if Cultivation.GetOwnedSkill(playerData, skillId) then
        return false, "你已经拥有这门功法"
    end
    playerData.skills = playerData.skills or {}
    table.insert(playerData.skills, {
        id          = skillId,
        proficiency = 0,
        bound       = bound,
    })
    return true, nil
end

-- 解绑功法
function Cultivation.UnbindSkill(playerData, skillId)
    local ownedSkill = Cultivation.GetOwnedSkill(playerData, skillId)
    if not ownedSkill then
        return false, nil, "你没有这门功法"
    end
    if not ownedSkill.bound then
        return false, nil, "这门功法已经是非绑定状态"
    end

    local skillDef = Shared.GetSkillDef(skillId)

    -- 解绑：从玩家背包移除，返回功法数据（用于放入市场或背包）
    local removedSkill = nil
    for i, sk in ipairs(playerData.skills) do
        if sk.id == skillId then
            removedSkill = table.remove(playerData.skills, i)
            break
        end
    end

    -- 如果正在修炼，停止
    if playerData.cultivating == skillId then
        playerData.cultivating = ""
        playerData.cultivate_cost_mult = nil
    playerData.spirit_stone_boost = nil
    end

    local item = {
        type        = "skill",
        id          = Shared.GenId(),
        skill_id    = skillId,
        name        = skillDef and skillDef.name or skillId,
        grade       = skillDef and skillDef.grade or 1,
        proficiency = removedSkill and removedSkill.proficiency or 0,
        bound       = false,
    }

    return true, item, string.format("已解除%s的绑定，功法进入背包，可在交易阁出售", item.name)
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

-- 获取玩家已学功法
function Cultivation.GetOwnedSkill(playerData, skillId)
    if not playerData.skills then return nil end
    for _, sk in ipairs(playerData.skills) do
        if sk.id == skillId then return sk end
    end
    return nil
end

-- 检查是否可以升级功法链（拿下一级功法）
-- 新逻辑：达到"融会贯通"(tier>=3，约27%)即可解锁下一等级
function Cultivation.CanAdvance(playerData, skillId)
    local ownedSkill = Cultivation.GetOwnedSkill(playerData, skillId)
    if not ownedSkill then return false end
    local skillDef = Shared.GetSkillDef(skillId)
    if not skillDef then return false end
    return Shared.HasReachedMastery(ownedSkill.proficiency, skillDef.max_proficiency)
end

-- 获取下一阶功法ID
function Cultivation.GetNextSkill(skillId)
    for _, sk in ipairs(Settings.SKILLS) do
        if sk.require_skill == skillId then
            return sk.id
        end
    end
    return nil
end

return Cultivation
