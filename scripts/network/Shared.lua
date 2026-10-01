-- ============================================================================
-- network/Shared.lua - 双端共用代码
-- ============================================================================

local Shared = {}
local Settings = require("config.Settings")

Shared.Settings = Settings
Shared.EVENTS = Settings.EVENTS

-- ============================================================================
-- 事件注册
-- ============================================================================

-- 服务端需要接收的事件（来自客户端）
Shared.SERVER_EVENTS = {
    Settings.EVENTS.CLIENT_READY,
    Settings.EVENTS.REQ_MOVE_SCENE,
    Settings.EVENTS.REQ_INTERACT_NPC,
    Settings.EVENTS.REQ_START_BATTLE,
    Settings.EVENTS.REQ_FLEE_BATTLE,
    Settings.EVENTS.REQ_USE_ITEM,
    Settings.EVENTS.REQ_CULTIVATE,
    Settings.EVENTS.REQ_STOP_CULTIVATE,
    Settings.EVENTS.REQ_UNBIND_SKILL,
    Settings.EVENTS.REQ_EQUIP_ITEM,
    Settings.EVENTS.REQ_UNEQUIP_ITEM,
    Settings.EVENTS.REQ_DISCARD_ITEM,
    Settings.EVENTS.REQ_MARKET_LIST,
    Settings.EVENTS.REQ_MARKET_BUY,
    Settings.EVENTS.REQ_MARKET_SELL,
    Settings.EVENTS.REQ_MARKET_CANCEL,
    Settings.EVENTS.REQ_MARKET_HISTORY,
    Settings.EVENTS.REQ_MARKET_TRENDS,
    Settings.EVENTS.REQ_ADMIN_LOGIN,
    Settings.EVENTS.REQ_ADMIN_SELL,
    Settings.EVENTS.REQ_ADMIN_SET_NEWS,
    Settings.EVENTS.REQ_ADMIN_QUERY_PLAYER,
    Settings.EVENTS.REQ_ADMIN_ADD_CURRENCY,
    Settings.EVENTS.REQ_ADMIN_MODIFY_PLAYER,
    Settings.EVENTS.REQ_ADMIN_LIST_PLAYERS,
    Settings.EVENTS.REQ_SHOP_BUY,
    Settings.EVENTS.REQ_CHANGE_SPOT,
    Settings.EVENTS.REQ_USE_SKILL,
    Settings.EVENTS.REQ_TOGGLE_AUTO,
    Settings.EVENTS.REQ_SET_BATTLE_SLOTS,
    Settings.EVENTS.REQ_RANK,
    Settings.EVENTS.REQ_CHAT_SEND,
    Settings.EVENTS.REQ_ADMIN_RESET_SELF,
    Settings.EVENTS.REQ_ADMIN_RESET_PLAYER,
    Settings.EVENTS.REQ_ADMIN_SET_ACTIVITY,
    Settings.EVENTS.REQ_PICKUP_LOOT,
    Settings.EVENTS.REQ_RESET_TUTORIAL,
    Settings.EVENTS.REQ_NPC_OPTION,
    Settings.EVENTS.REQ_AD_REWARD,
    -- 境界突破 / 炼丹 / 买材料 / 修为丹
    Settings.EVENTS.REQ_BREAKTHROUGH,
    Settings.EVENTS.REQ_ALCHEMY_CRAFT,
    Settings.EVENTS.REQ_BUY_MATERIAL,
    Settings.EVENTS.REQ_BUY_REALM_PILL,
    Settings.EVENTS.REQ_USE_REALM_PILL,
    -- 域外战场
    Settings.EVENTS.REQ_ENTER_LAYER,
    Settings.EVENTS.REQ_MAP_MOVE,
    Settings.EVENTS.REQ_CHALLENGE_BOSS,
    Settings.EVENTS.REQ_CLAIM_DAILY,
    Settings.EVENTS.REQ_QUEST_INFO_REQ,
    -- 帮会
    Settings.EVENTS.REQ_CREATE_GUILD,
    Settings.EVENTS.REQ_GUILD_INFO,
    Settings.EVENTS.REQ_JOIN_GUILD,
    Settings.EVENTS.REQ_LEAVE_GUILD,
    Settings.EVENTS.REQ_SET_GUILD_NOTICE,
    Settings.EVENTS.REQ_GUILD_LIST,
    Settings.EVENTS.REQ_KICK_MEMBER,
    Settings.EVENTS.REQ_TRANSFER_LEADER,
    Settings.EVENTS.REQ_GUILD_DONATE,
    Settings.EVENTS.REQ_GUILD_UPGRADE,
    Settings.EVENTS.REQ_SET_GUILD_ROLE,
    Settings.EVENTS.REQ_GUILD_DAILY,
    Settings.EVENTS.REQ_CLAIM_GUILD_TASK,
    -- 炼器
    Settings.EVENTS.REQ_FORGE_CRAFT,
    Settings.EVENTS.REQ_BUY_BLUEPRINT,
    Settings.EVENTS.REQ_FORGE_NEW,
    Settings.EVENTS.REQ_BLUEPRINT_LIST,
    -- 领地战
    Settings.EVENTS.REQ_STRONGPOINT_LIST,
    Settings.EVENTS.REQ_ATTACK_STRONGPOINT,
    Settings.EVENTS.REQ_SWITCH_STRONGPOINT,
    Settings.EVENTS.REQ_DEFEND_STRONGPOINT,
    -- PVP
    Settings.EVENTS.REQ_PVP_CHALLENGE,
    -- 好友
    Settings.EVENTS.REQ_FRIEND_LIST,
    Settings.EVENTS.REQ_ADD_FRIEND,
    Settings.EVENTS.REQ_REMOVE_FRIEND,
    -- 活动
    Settings.EVENTS.REQ_DAILY_SIGN,
    -- 背包增强
    Settings.EVENTS.REQ_AUTO_EQUIP_BEST,
    Settings.EVENTS.REQ_SELL_ITEM,
    Settings.EVENTS.REQ_BATCH_SELL,
    -- 恢复
    Settings.EVENTS.REQ_RESTORE,
    -- 灵石功能
    Settings.EVENTS.REQ_CULTIVATE_BOOST,
    Settings.EVENTS.REQ_RENAME,
    Settings.EVENTS.REQ_GUILD_RENAME,
    Settings.EVENTS.REQ_TOGGLE_REVIVE,
    Settings.EVENTS.REQ_GUILD_BOOST,
    Settings.EVENTS.REQ_SKILL_TIER_UP,
    Settings.EVENTS.REQ_BUY_TITLE,
    Settings.EVENTS.REQ_EQUIP_TITLE,
    -- 角色创建
    Settings.EVENTS.REQ_CREATE_CHARACTER,
}

-- 客户端需要接收的事件（来自服务端）
Shared.CLIENT_EVENTS = {
    Settings.EVENTS.INIT_PLAYER,
    Settings.EVENTS.NPC_DIALOG,
    Settings.EVENTS.NPC_SKILL_GRANT,
    Settings.EVENTS.PUSH_GAME_LOG,
    Settings.EVENTS.PUSH_PLAYER_DATA,
    Settings.EVENTS.PUSH_INVENTORY,
    Settings.EVENTS.PUSH_MARKET_DATA,
    Settings.EVENTS.PUSH_MARKET_HISTORY,
    Settings.EVENTS.PUSH_MARKET_TRENDS,
    Settings.EVENTS.PUSH_BATTLE_STATE,
    Settings.EVENTS.PUSH_BATTLE_END,
    Settings.EVENTS.ADMIN_LOGIN_RESULT,
    Settings.EVENTS.PUSH_NEWS_UPDATE,
    Settings.EVENTS.PUSH_ADMIN_PLAYER_INFO,
    Settings.EVENTS.PUSH_ADMIN_RESULT,
    Settings.EVENTS.PUSH_ADMIN_PLAYER_LIST,
    Settings.EVENTS.PUSH_SHOP_DATA,
    Settings.EVENTS.PUSH_SPOT_PLAYERS,
    Settings.EVENTS.PUSH_RANK,
    Settings.EVENTS.PUSH_CHAT_MSG,
    Settings.EVENTS.PUSH_CHAT_HISTORY,
    Settings.EVENTS.PUSH_LOOT_RESULT,  -- 拾取结果
    Settings.EVENTS.PUSH_AD_REWARD,
    -- 境界突破 / 炼丹 / 修为丹商铺
    Settings.EVENTS.PUSH_BREAKTHROUGH,
    Settings.EVENTS.PUSH_ALCHEMY_RESULT,
    Settings.EVENTS.PUSH_REALM_PILL_SHOP,
    Settings.EVENTS.PUSH_REALM_PILL_RESULT,
    -- 域外战场
    Settings.EVENTS.RES_ENTER_LAYER,
    Settings.EVENTS.RES_LAYER_SNAPSHOT,
    Settings.EVENTS.NOTIFY_PLAYER_POS,
    Settings.EVENTS.NOTIFY_PLAYER_ENTER,
    Settings.EVENTS.NOTIFY_PLAYER_LEAVE,
    Settings.EVENTS.NOTIFY_MONSTER_DEAD,
    Settings.EVENTS.NOTIFY_MONSTER_SYNC,
    Settings.EVENTS.NOTIFY_MONSTER_SPAWN,
    Settings.EVENTS.NOTIFY_BATTLE_TRIGGER,
    -- 任务系统
    Settings.EVENTS.RES_QUEST_INFO,
    -- 领地战通知
    Settings.EVENTS.NOTIFY_WAR_START,
    Settings.EVENTS.NOTIFY_WAR_END,
    Settings.EVENTS.NOTIFY_UNDER_ATTACK,
    Settings.EVENTS.NOTIFY_SP_CAPTURED,
    -- 帮会
    Settings.EVENTS.RES_CREATE_GUILD,
    Settings.EVENTS.RES_GUILD_INFO,
    Settings.EVENTS.RES_JOIN_GUILD,
    Settings.EVENTS.RES_LEAVE_GUILD,
    Settings.EVENTS.RES_SET_GUILD_NOTICE,
    Settings.EVENTS.RES_GUILD_LIST,
    Settings.EVENTS.RES_KICK_MEMBER,
    Settings.EVENTS.RES_TRANSFER_LEADER,
    Settings.EVENTS.NOTIFY_GUILD_ONLINE,
    Settings.EVENTS.RES_GUILD_DONATE,
    Settings.EVENTS.RES_GUILD_UPGRADE,
    Settings.EVENTS.RES_SET_GUILD_ROLE,
    Settings.EVENTS.RES_GUILD_DAILY,
    Settings.EVENTS.RES_CLAIM_GUILD_TASK,
    -- 炼器
    Settings.EVENTS.RES_FORGE_CRAFT,
    Settings.EVENTS.RES_BUY_BLUEPRINT,
    Settings.EVENTS.RES_FORGE_NEW,
    Settings.EVENTS.RES_BLUEPRINT_LIST,
    -- 领地战
    Settings.EVENTS.RES_STRONGPOINT_LIST,
    Settings.EVENTS.RES_ATTACK_STRONGPOINT,
    Settings.EVENTS.RES_SWITCH_STRONGPOINT,
    Settings.EVENTS.RES_DEFEND_STRONGPOINT,
    Settings.EVENTS.NOTIFY_WAR_START,
    Settings.EVENTS.NOTIFY_WAR_END,
    Settings.EVENTS.NOTIFY_UNDER_ATTACK,
    Settings.EVENTS.NOTIFY_SP_CAPTURED,
    -- PVP
    Settings.EVENTS.RES_PVP_CHALLENGE,
    -- 好友
    Settings.EVENTS.PUSH_FRIEND_LIST,
    -- 活动
    Settings.EVENTS.PUSH_ACTIVITY_DATA,
    -- 灵石功能
    Settings.EVENTS.RES_RENAME,
    Settings.EVENTS.RES_GUILD_RENAME,
    Settings.EVENTS.RES_SKILL_TIER_UP,
    Settings.EVENTS.RES_TITLE_UPDATE,
    -- 角色创建
    Settings.EVENTS.RES_CREATE_CHARACTER,
}

function Shared.RegisterServerEvents()
    for _, name in ipairs(Shared.SERVER_EVENTS) do
        network:RegisterRemoteEvent(name)
    end
    print("[Shared] 注册服务端事件完成，共" .. #Shared.SERVER_EVENTS .. "个")
end

function Shared.RegisterClientEvents()
    for _, name in ipairs(Shared.CLIENT_EVENTS) do
        network:RegisterRemoteEvent(name)
    end
    print("[Shared] 注册客户端事件完成，共" .. #Shared.CLIENT_EVENTS .. "个")
end

-- ============================================================================
-- 工具函数
-- ============================================================================

-- 查找功法定义
function Shared.GetSkillDef(skillId)
    for _, sk in ipairs(Settings.SKILLS) do
        if sk.id == skillId then
            return sk
        end
    end
    return nil
end

-- 查找怪物定义
function Shared.GetMonsterDef(monsterId)
    for _, m in ipairs(Settings.MONSTERS) do
        if m.id == monsterId then
            return m
        end
    end
    -- fallback: Boss 也可作为战斗对手
    if Settings.BOSS_MAP and Settings.BOSS_MAP[monsterId] then
        return Settings.BOSS_MAP[monsterId]
    end
    return nil
end

-- 查找装备模板
function Shared.GetEquipTemplate(templateId)
    for _, t in ipairs(Settings.EQUIPMENT_TEMPLATES) do
        if t.id == templateId then
            return t
        end
    end
    return nil
end

-- 生成唯一ID（基于时间+随机数）
function Shared.GenId()
    return tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

-- 计算玩家当前等级所需经验
function Shared.ExpRequired(level)
    return Settings.LEVEL.EXP_PER_LEVEL(level)
end

-- 计算玩家实际属性（基础+功法加成+装备加成）
function Shared.CalcStats(playerData)
    -- 获取境界倍率（层内线性插值）
    local realmIndex = playerData.realm or 1
    local layerIndex = playerData.realm_layer or 1
    local stat_mult = Settings.REALM.GetStatMult(realmIndex, layerIndex)

    -- 境界阶梯加成：用 (realmIndex-1) 替代旧的 (level-1)
    -- 旧系统 level 最高~25，新系统累计层数最高93，直接用 level 会导致属性爆炸
    -- stat_mult 已通过层内插值处理细粒度增长，这里只提供境界阶梯基础值
    local realmBonus = (realmIndex - 1)  -- 0~6

    local s = {
        hp  = math.floor((playerData.hp_base  + realmBonus * 40) * stat_mult),
        mp  = math.floor((playerData.mp_base  + realmBonus * 20) * stat_mult),
        atk = math.floor((playerData.atk_base + realmBonus * 8)  * stat_mult),
        def = math.floor((playerData.def_base + realmBonus * 4)  * stat_mult),
        agi = math.floor((playerData.agi_base + realmBonus * 4)  * stat_mult),
        wis = playerData.wis_base,
    }
    -- 功法加成（含分阶加成乘数）
    if playerData.skills then
        for _, sk in ipairs(playerData.skills) do
            local def = Shared.GetSkillDef(sk.id)
            if def and sk.proficiency and sk.proficiency > 0 then
                local prof = sk.proficiency
                -- 获取分阶加成乘数
                local tier = Shared.GetProficiencyTier(prof, def.max_proficiency)
                local bonus = Shared.GetProficiencyBonus(tier)
                -- 升阶倍率（灵石升阶：基础1.0/精通1.3/圆满1.6/大成2.0）
                local tierUp = sk.tier or 0
                local tierBonus = 1.0
                if tierUp > 0 and Settings.SKILL_TIER_UP then
                    local tierInfo = Settings.SKILL_TIER_UP.TIERS[tierUp + 1]
                    if tierInfo then tierBonus = tierInfo.bonus end
                end
                if def.stat_bonus.atk then s.atk = s.atk + def.stat_bonus.atk * prof * bonus * tierBonus end
                if def.stat_bonus.def then s.def = s.def + def.stat_bonus.def * prof * bonus * tierBonus end
                if def.stat_bonus.agi then s.agi = s.agi + def.stat_bonus.agi * prof * bonus * tierBonus end
                if def.stat_bonus.hp  then s.hp  = s.hp  + def.stat_bonus.hp  * prof * bonus * tierBonus end
                if def.stat_bonus.wis then s.wis = s.wis + def.stat_bonus.wis * prof * bonus * tierBonus end
            end
        end
    end
    -- 装备加成
    if playerData.equipment then
        for _, item in pairs(playerData.equipment) do
            if item and item.stats then
                if item.stats.atk then s.atk = s.atk + item.stats.atk end
                if item.stats.def then s.def = s.def + item.stats.def end
                if item.stats.agi then s.agi = s.agi + item.stats.agi end
                if item.stats.hp  then s.hp  = s.hp  + item.stats.hp  end
            end
        end
    end
    return s
end

-- 功法系数表（grade 1~5 → 系数）
local SKILL_GRADE_COEFF = { 1.0, 1.3, 1.6, 2.0, 2.5 }

-- 计算玩家当前最高功法等级系数（取已装备功法中grade最高者）
-- 如同时修炼两本功法，GDD规定取其中较高等级计算
function Shared.CalcSkillCoeff(playerData)
    local maxGrade = 0
    if playerData.skills then
        for _, sk in ipairs(playerData.skills) do
            local def = Shared.GetSkillDef(sk.id)
            if def and def.grade and def.grade > maxGrade then
                maxGrade = def.grade
            end
        end
    end
    if maxGrade < 1 then return 1.0 end
    return SKILL_GRADE_COEFF[maxGrade] or 1.0
end

-- 计算武器系数（当前装备武器的atk相对基准的倍率）
-- 基准：无武器时系数为1.0；装备武器后 weaponCoeff = 1 + weapon.stats.atk / 100
-- 这使铁剑(atk=8)系数≈1.08，钢剑(atk=15)系数≈1.15，与GDD"武器系数"语义对应
function Shared.CalcWeaponCoeff(playerData)
    if playerData.equipment and playerData.equipment.weapon then
        local w = playerData.equipment.weapon
        local wAtk = (w.stats and w.stats.atk) or 0
        return 1.0 + wAtk / 100.0
    end
    return 1.0
end

-- 战斗伤害计算：最终伤害 = (攻击力 × 功法系数 × 武器系数) - 防御力×0.5 ± DAMAGE_RANDOM
-- defIgnore: 0.0=正常，0.3=无视30%防御，1.0=完全无视防御
function Shared.CalcDamage(atkStats, defStats, skillBonus, weaponBonus, defIgnore)
    skillBonus  = skillBonus  or 1.0
    weaponBonus = weaponBonus or 1.0
    defIgnore   = defIgnore   or 0.0
    local effectiveDef = defStats.def * 0.5 * (1.0 - defIgnore)
    local base = atkStats.atk * skillBonus * weaponBonus - effectiveDef
    if base < 1 then base = 1 end
    local rand = 1.0 + (math.random() * 2 - 1) * Settings.BATTLE.DAMAGE_RANDOM
    return math.floor(base * rand)
end

-- 格式化银两显示
function Shared.FormatSilver(amount)
    if amount >= 10000 then
        return string.format("%.1f万两", amount / 10000)
    end
    return amount .. "两"
end

-- ============================================================================
-- 熟练度分阶系统
-- ============================================================================

--- 计算指定熟练度所处的阶位（1~6）及在当前阶的进度百分比
---@param proficiency number 当前熟练度值
---@param maxProficiency number 该功法最大熟练度
---@return integer tier 当前阶位(1~6)
---@return string tierName 阶位名称
---@return number tierProgress 当前阶内进度(0~1)
---@return number overallProgress 总进度(0~1)
function Shared.GetProficiencyTier(proficiency, maxProficiency)
    local tiers = Settings.PROFICIENCY_TIERS
    -- 计算总 ratio
    local totalRatio = 0
    for _, t in ipairs(tiers) do totalRatio = totalRatio + t.ratio end

    -- 使用累加 ratio 再一次性乘法，避免逐步乘法累加的浮点误差
    -- 必须与 GetTierCeiling 计算方式完全一致
    local ratioAcc = 0
    for i, t in ipairs(tiers) do
        local prevCeiling = maxProficiency * (ratioAcc / totalRatio)
        ratioAcc = ratioAcc + t.ratio
        local ceiling = maxProficiency * (ratioAcc / totalRatio)
        if proficiency < ceiling then
            local inTier = proficiency - prevCeiling
            local tierSize = ceiling - prevCeiling
            return i, t.name, inTier / tierSize, proficiency / maxProficiency
        end
    end
    -- 已满
    return #tiers, tiers[#tiers].name, 1.0, 1.0
end

--- 获取熟练度对应的 stat_bonus 额外乘数
--- 未达融会贯通(tier<3)返回1.0，达到后按 PROFICIENCY_BONUS 表返回
---@param tier integer 当前阶位
---@return number multiplier
function Shared.GetProficiencyBonus(tier)
    if tier < 3 then return 1.0 end
    return Settings.PROFICIENCY_BONUS[tier] or 1.0
end

--- 判断功法是否达到"融会贯通"(tier>=3)，可以学习下一等级功法
---@param proficiency number
---@param maxProficiency number
---@return boolean
function Shared.HasReachedMastery(proficiency, maxProficiency)
    local tier = Shared.GetProficiencyTier(proficiency, maxProficiency)
    return tier >= 3
end

--- 计算修炼每秒获得的熟练度（基于潜能消耗速率和总消耗）
--- profGainPerSec = drainPerSec / (totalCost / maxProficiency)
---@param grade integer 功法等级
---@param maxProficiency number 最大熟练度
---@param costMultiplier number 消耗倍率(1.0或1.2)
---@return number profPerSec 每秒熟练度增长
---@return number drainPerSec 每秒潜能消耗
function Shared.CalcCultivateRate(grade, maxProficiency, costMultiplier)
    local totalCost = Settings.CULTIVATE_COST_BY_GRADE[grade] or Settings.CULTIVATE_COST_BY_GRADE[1]
    local baseDrain = Settings.CULTIVATE_DRAIN_PER_SEC
    local drainPerSec = baseDrain * (costMultiplier or 1.0)
    -- 熟练度增长速率与 costMultiplier 无关（时间固定，花费不同）
    -- 自主(1.2x)：同样时间多花20%潜能；师傅(1.0x)：基准消耗
    local profPerSec = baseDrain * (maxProficiency / totalCost)
    return profPerSec, drainPerSec
end

--- 计算投入指定潜能到阶段边界所需的最大潜能量
--- 返回：maxBudget（滑条上限）、预估熟练度增量
---@param proficiency number 当前熟练度
---@param maxProficiency number 最大熟练度
---@param grade integer 功法等级
---@param potential number 当前潜能
---@param costMultiplier number 消耗倍率
---@return integer maxBudget 滑条上限（不超过潜能，不超过阶段满所需）
---@return number estProfGain 预估熟练度增量
function Shared.CalcCultivateBudgetCap(proficiency, maxProficiency, grade, potential, costMultiplier)
    local profPerSec, drainPerSec = Shared.CalcCultivateRate(grade, maxProficiency, costMultiplier)
    local profPerPotential = profPerSec / drainPerSec  -- 每消耗1点潜能获得的熟练度

    -- 计算当前阶段剩余空间（使用累加ratio再一次性乘法，与 GetProficiencyTier/getTierCeiling 一致）
    local tiers = Settings.PROFICIENCY_TIERS
    local totalRatio = 0
    for _, t in ipairs(tiers) do totalRatio = totalRatio + t.ratio end

    local ratioAcc = 0
    local tierCeiling = maxProficiency  -- 当前阶段的上界
    for i, t in ipairs(tiers) do
        ratioAcc = ratioAcc + t.ratio
        local ceiling = maxProficiency * (ratioAcc / totalRatio)
        if proficiency < ceiling then
            tierCeiling = ceiling
            break
        end
    end

    local remainingProf = tierCeiling - proficiency
    -- 到阶段满所需潜能
    local potentialForTier = math.ceil(remainingProf / profPerPotential)
    -- 滑条上限 = min(当前潜能, 到阶段满所需)
    local maxBudget = math.min(math.floor(potential), potentialForTier)
    maxBudget = math.max(1, maxBudget)

    -- 预估增量（用整个 maxBudget 计算）
    local estGain = maxBudget * profPerPotential

    return maxBudget, estGain
end

return Shared
