-- ============================================================================
-- game/Combat.lua - 战斗逻辑（服务端专用）
-- 版本2.0: agi闪避/先手、wis技能加成/控制抗性、heal/defend/dodge类型、
--           灼烧/毒伤DoT、眩晕递减、疾风连击
-- ============================================================================

local Combat = {}
local Shared  = require("network.Shared")
local Settings = Shared.Settings

-- 进行中的战斗 { [uid] = battleState }
local activeBattles = {}

-- ============================================================================
-- 内部工具
-- ============================================================================

-- 从玩家数据里取出战技能列表（根据 battle_slots 配置）
local function GetEquippedSkills(playerData)
    local slots = playerData.battle_slots or {}
    local result = {}
    for _, skillId in ipairs(slots) do
        local def = Shared.GetSkillDef(skillId)
        if def then
            -- 检查玩家确实学了该技能
            for _, sk in ipairs(playerData.skills or {}) do
                if sk.id == skillId or sk.skill_id == skillId then
                    result[#result + 1] = def
                    break
                end
            end
        end
    end
    return result
end

-- 自动战斗：选择最优技能（优先级最高 + 有内力 + 不在冷却）
local function PickBestSkill(battle)
    local p           = battle.player
    local cooldowns   = battle.skillCooldowns
    local equipped    = battle.equippedSkills
    local best        = nil

    for _, def in ipairs(equipped) do
        if def.battle_type ~= "normal" then
            local cd  = cooldowns[def.id] or 0
            local canUse = cd <= 0 and p.currentMp >= def.mp_cost
            if canUse then
                if not best or def.priority > best.priority then
                    best = def
                end
            end
        end
    end

    -- 有强力技能就用，否则普攻
    if best then return best end

    -- 从已装备技能中找普攻（battle_type == "normal"）
    for _, def in ipairs(equipped) do
        if def.battle_type == "normal" then
            return def
        end
    end

    -- 最终兜底：basic_fist（所有门派通用）
    return Shared.GetSkillDef("basic_fist") or Shared.GetSkillDef("basic_sword")
end

-- ============================================================================
-- agi闪避计算
-- 公式: dodge = defender_agi/(defender_agi+attacker_agi)*0.6 - 0.1, 上限45%
-- ============================================================================
local function CalcDodgeChance(defenderAgi, attackerAgi, hasDodgeBuff)
    local B = Settings.BATTLE
    local base = defenderAgi / (defenderAgi + attackerAgi + 1) * B.DODGE_FACTOR - B.DODGE_OFFSET
    -- 基础闪避上限45%，buff可突破至60%
    local cap = B.DODGE_CAP
    if hasDodgeBuff then
        base = base + B.DODGE_SKILL_BONUS
        cap = B.DODGE_CAP_WITH_BUFF or 0.60
    end
    return math.max(0, math.min(cap, base))
end

-- ============================================================================
-- wis技能伤害加成: bonus = wis/(wis+500)
-- ============================================================================
local function CalcWisDamageBonus(wis)
    local divisor = Settings.BATTLE.WIS_DAMAGE_DIVISOR
    return wis / (wis + divisor)
end

-- ============================================================================
-- wis控制抗性: resist = defender_wis/(defender_wis+attacker_wis+200)
-- ============================================================================
local function CalcStunResist(defenderWis, attackerWis)
    local offset = Settings.BATTLE.WIS_RESIST_OFFSET
    return defenderWis / (defenderWis + attackerWis + offset)
end

-- ============================================================================
-- 疾风连击（multi_hit）概率计算
-- ============================================================================
local function CalcMultiHitChance(attackerAgi, defenderAgi)
    local B = Settings.BATTLE
    local agiDiff = attackerAgi - defenderAgi - B.MULTI_HIT_AGI_THRESHOLD
    if agiDiff <= 0 then return 0 end
    local chance = agiDiff * B.MULTI_HIT_CHANCE_PER_AGI
    return math.min(chance, B.MULTI_HIT_CHANCE_CAP)
end

-- ============================================================================
-- DoT 处理：每回合开始时结算
-- ============================================================================
local function ProcessDoTs(battle, logs)
    local target = battle.monster
    local dots = battle.monsterDots or {}
    local totalDotDmg = 0

    -- 处理灼烧
    if dots.burn then
        local burn = dots.burn
        local round = burn.currentRound
        local dist = Settings.BATTLE.BURN_DISTRIBUTION
        if round <= #dist then
            local dmg = math.floor(burn.baseDamage * dist[round])
            target.currentHp = target.currentHp - dmg
            totalDotDmg = totalDotDmg + dmg
            logs[#logs + 1] = string.format(
                "<橙>  🔥 灼烧持续伤害：%d（第%d/%d回合）</橙>", dmg, round, #dist)
            burn.currentRound = round + 1
            if burn.currentRound > #dist then
                dots.burn = nil
            end
        else
            dots.burn = nil
        end
    end

    -- 处理毒伤（可叠加）
    if dots.poison and #dots.poison > 0 then
        local newPoisons = {}
        for i, poison in ipairs(dots.poison) do
            local round = poison.currentRound
            local dist = Settings.BATTLE.POISON_DISTRIBUTION
            if round <= #dist then
                local dmg = math.floor(poison.baseDamage * dist[round])
                target.currentHp = target.currentHp - dmg
                totalDotDmg = totalDotDmg + dmg
                poison.currentRound = round + 1
                if poison.currentRound <= #dist then
                    newPoisons[#newPoisons + 1] = poison
                end
            end
        end
        dots.poison = newPoisons
        if #dots.poison > 0 then
            local stacks = #dots.poison
            logs[#logs + 1] = string.format(
                "<绿>  ☠ 毒伤持续伤害：%d（%d层）</绿>", totalDotDmg - (dots.burn and 0 or 0), stacks)
        end
        -- 如果所有毒都结束了
        if #dots.poison == 0 then
            dots.poison = nil
        end
    end

    battle.monsterDots = dots
    return totalDotDmg
end

-- 应用DoT效果（攻击命中后）
local function ApplyDoT(battle, skillDef, logs)
    if not skillDef.dot_type then return end

    local p = battle.player
    local atkValue = p.stats.atk
    local dots = battle.monsterDots or {}

    if skillDef.dot_type == "burn" then
        -- 灼烧：不可叠加，刷新持续时间
        local baseDmg = math.floor(atkValue * (skillDef.dot_power or 0.2))
        dots.burn = {
            baseDamage = baseDmg,
            currentRound = 1,
        }
        logs[#logs + 1] = string.format("<橙>  🔥 附加灼烧！每回合造成持续火伤</橙>")

    elseif skillDef.dot_type == "poison" then
        -- 毒伤：可叠加，最多3层
        if not dots.poison then dots.poison = {} end
        local maxStacks = Settings.BATTLE.POISON_MAX_STACKS
        if #dots.poison < maxStacks then
            local baseDmg = math.floor(atkValue * (skillDef.dot_power or 0.15))
            dots.poison[#dots.poison + 1] = {
                baseDamage = baseDmg,
                currentRound = 1,
            }
            logs[#logs + 1] = string.format(
                "<绿>  ☠ 附加毒伤！（当前%d层）</绿>", #dots.poison)
        else
            logs[#logs + 1] = string.format("<绿>  ☠ 毒伤已满%d层！</绿>", maxStacks)
        end
    end

    battle.monsterDots = dots
end

-- 检查目标是否中毒（用于减疗判定）
local function IsPoisoned(battle)
    local dots = battle.monsterDots or {}
    return dots.poison and #dots.poison > 0
end

-- ============================================================================
-- defend型处理：获得减伤buff
-- ============================================================================
local function ApplyDefendBuff(battle, skillDef, logs)
    local B = Settings.BATTLE
    local buffs = battle.defendBuffs or {}

    -- 检查是否已满层
    if #buffs >= B.DEFEND_MAX_STACK then
        logs[#logs + 1] = "<蓝>  🛡 防御层数已满，无法继续叠加！</蓝>"
        return
    end

    -- 添加一层减伤buff
    buffs[#buffs + 1] = {
        remainRounds = B.DEFEND_DURATION,
    }
    battle.defendBuffs = buffs

    local totalReduction = math.min(#buffs * B.DEFEND_REDUCTION, B.DEFEND_MAX_STACK * B.DEFEND_REDUCTION)
    logs[#logs + 1] = string.format(
        "<蓝>  🛡 进入防御姿态！减伤%d%%，持续%d回合（当前%d层）</蓝>",
        math.floor(totalReduction * 100), B.DEFEND_DURATION, #buffs)
end

-- 计算当前减伤倍率（从defend buffs）
local function GetDefendReduction(battle)
    local buffs = battle.defendBuffs or {}
    if #buffs == 0 then return 0 end
    local B = Settings.BATTLE
    local totalReduction = #buffs * B.DEFEND_REDUCTION
    return math.min(totalReduction, B.DEFEND_MAX_STACK * B.DEFEND_REDUCTION)
end

-- 每回合减少defend buff持续时间
local function TickDefendBuffs(battle)
    local buffs = battle.defendBuffs or {}
    local newBuffs = {}
    for _, buff in ipairs(buffs) do
        buff.remainRounds = buff.remainRounds - 1
        if buff.remainRounds > 0 then
            newBuffs[#newBuffs + 1] = buff
        end
    end
    battle.defendBuffs = newBuffs
end

-- ============================================================================
-- heal型处理：回血 + 微伤害
-- ============================================================================
local function ExecuteHealSkill(battle, skillDef, logs)
    local p = battle.player
    local m = battle.monster
    local monDef = m.def
    local B = Settings.BATTLE

    -- 回血量 = 最大HP * heal_power
    local healAmount = math.floor(p.stats.hp * (skillDef.heal_power or 0.10))

    -- 中毒减疗
    -- 注意：这里判断的是玩家自身是否中毒（PvP场景），PvE怪物不会给玩家上毒
    -- 但保留机制以便将来PvP使用
    local poisonReduction = 1.0
    if battle.playerPoisoned then
        poisonReduction = 1.0 - B.POISON_HEAL_REDUCTION
    end
    healAmount = math.floor(healAmount * poisonReduction)

    local oldHp = p.currentHp
    p.currentHp = math.min(p.stats.hp, p.currentHp + healAmount)
    local actualHeal = math.floor(p.currentHp - oldHp)

    logs[#logs + 1] = string.format(
        "<绿>你运功疗伤，恢复 %d 点气血（%d/%d）</绿>",
        actualHeal, math.floor(p.currentHp), p.stats.hp)

    -- 微伤害（coeff 0.8 的低伤害）
    local wisBonus = 1.0 + CalcWisDamageBonus(p.stats.wis or 0)
    local coeff = math.min(skillDef.damage_coeff or 0.8, B.DAMAGE_COEFF_CAP)
    local dmg = Shared.CalcDamage(p.stats, { def = monDef.def }, coeff * p.skillCoeff * p.weaponCoeff * wisBonus, 1.0)
    m.currentHp = m.currentHp - dmg

    logs[#logs + 1] = string.format(
        "  同时以内劲震伤%s，造成 <红>%d</红> 点伤害", monDef.name, dmg)

    -- 消耗内力
    if (skillDef.mp_cost or 0) > 0 then
        p.currentMp = math.max(0, p.currentMp - skillDef.mp_cost)
    end
    -- 冷却
    if (skillDef.cooldown or 0) > 0 then
        battle.skillCooldowns[skillDef.id] = skillDef.cooldown
    end

    return dmg
end

-- ============================================================================
-- 执行技能攻击（主攻击逻辑）
-- 返回 (伤害量, 技能名, 连击层数, 是否触发眩晕)
-- ============================================================================
local function ExecuteSkillAttack(battle, skillDef)
    local p      = battle.player
    local m      = battle.monster
    local monDef = m.def
    local B      = Settings.BATTLE
    local logs   = {}

    -- wis技能伤害加成
    local wisBonus = 1.0 + CalcWisDamageBonus(p.stats.wis or 0)

    -- ── defend型：放弃攻击，获得减伤buff ─────────────────────────────
    if skillDef.battle_type == "defend" then
        ApplyDefendBuff(battle, skillDef, logs)
        -- 消耗内力
        if (skillDef.mp_cost or 0) > 0 then
            p.currentMp = math.max(0, p.currentMp - skillDef.mp_cost)
        end
        -- 冷却
        if (skillDef.cooldown or 0) > 0 then
            battle.skillCooldowns[skillDef.id] = skillDef.cooldown
        end
        battle.swiftComboStack = 0
        return 0, skillDef.name, 0, false, logs
    end

    -- ── heal型：回血+微伤 ────────────────────────────────────────────
    if skillDef.battle_type == "heal" then
        local dmg = ExecuteHealSkill(battle, skillDef, logs)
        battle.swiftComboStack = 0
        return dmg, skillDef.name, 0, false, logs
    end

    -- ── 疾风剑派：连击叠加 ──────────────────────────────────────────────
    local comboStack = 0
    local defIgnore = skillDef.ignore_def or 0.0
    local coeff = math.min(skillDef.damage_coeff or 1.0, B.DAMAGE_COEFF_CAP)

    if skillDef.branch == "swift" then
        -- 应用当前叠加层数的伤害加成
        local comboMult = 1.0 + battle.swiftComboStack * B.SWIFT_COMBO_BONUS
        local finalCoeff = coeff * p.skillCoeff * p.weaponCoeff * comboMult * wisBonus
        -- 命中后层数+1（上限 SWIFT_COMBO_MAX）
        battle.swiftComboStack = math.min(
            battle.swiftComboStack + 1,
            B.SWIFT_COMBO_MAX
        )
        comboStack = battle.swiftComboStack
        local dmg = Shared.CalcDamage(p.stats, { def = monDef.def }, finalCoeff, 1.0)
        -- 消耗内力
        if skillDef.battle_type ~= "normal" and skillDef.mp_cost > 0 then
            p.currentMp = math.max(0, p.currentMp - skillDef.mp_cost)
        end
        -- 冷却
        if (skillDef.cooldown or 0) > 0 then
            battle.skillCooldowns[skillDef.id] = skillDef.cooldown
        end
        m.currentHp = m.currentHp - dmg

        -- 疾风连击（multi_hit）：基于agi优势额外攻击一次
        local extraDmg = 0
        if skillDef.multi_hit then
            local multiChance = CalcMultiHitChance(p.stats.agi, monDef.agi)
            if multiChance > 0 and math.random() < multiChance then
                extraDmg = math.floor(dmg * B.MULTI_HIT_DAMAGE_MULT)
                m.currentHp = m.currentHp - extraDmg
                logs[#logs + 1] = string.format(
                    "<橙>  ⚡ 触发连击！额外造成 %d 点伤害</橙>", extraDmg)
            end
        end

        -- DoT
        ApplyDoT(battle, skillDef, logs)

        return dmg + extraDmg, skillDef.name, comboStack, false, logs

    -- ── 重剑门：无视防御 + 眩晕 ──────────────────────────────────────────
    elseif skillDef.branch == "heavy" then
        battle.swiftComboStack = 0
        local finalCoeff = coeff * p.skillCoeff * p.weaponCoeff * wisBonus
        local dmg = Shared.CalcDamage(p.stats, { def = monDef.def }, finalCoeff, 1.0, defIgnore)
        -- 消耗内力
        if skillDef.battle_type ~= "normal" and skillDef.mp_cost > 0 then
            p.currentMp = math.max(0, p.currentMp - skillDef.mp_cost)
        end
        -- 冷却
        if (skillDef.cooldown or 0) > 0 then
            battle.skillCooldowns[skillDef.id] = skillDef.cooldown
        end
        -- 眩晕判定（含wis抗性 + 递减）
        local stunApplied = false
        if (skillDef.stun_chance or 0) > 0 then
            local stunChance = skillDef.stun_chance
            -- wis控制抗性（怪物wis vs 玩家wis）
            local monWis = monDef.wis or 0
            local resist = CalcStunResist(monWis, p.stats.wis or 0)
            stunChance = stunChance * (1.0 - resist)
            -- 眩晕递减
            if battle.stunCount > 0 then
                ---@diagnostic disable-next-line: access-invisible
                stunChance = stunChance * math.pow(B.STUN_DIMINISH_MULT, battle.stunCount)
            end
            if math.random() < stunChance then
                battle.monsterStunRounds = battle.monsterStunRounds + 1
                battle.stunCount = battle.stunCount + 1
                stunApplied = true
            end
        end
        m.currentHp = m.currentHp - dmg

        -- DoT
        ApplyDoT(battle, skillDef, logs)

        return dmg, skillDef.name, 0, stunApplied, logs

    -- ── 通用技能（其他分支）──────────────────────────────────────────
    else
        battle.swiftComboStack = 0
        local finalCoeff = coeff * p.skillCoeff * p.weaponCoeff * wisBonus
        local dmg = Shared.CalcDamage(p.stats, { def = monDef.def }, finalCoeff, 1.0, defIgnore)
        -- 消耗内力
        if skillDef.battle_type ~= "normal" and skillDef.mp_cost > 0 then
            p.currentMp = math.max(0, p.currentMp - skillDef.mp_cost)
        end
        -- 冷却
        if (skillDef.cooldown or 0) > 0 then
            battle.skillCooldowns[skillDef.id] = skillDef.cooldown
        end
        -- 闪避型技能标记：本回合+15%闪避buff
        if skillDef.battle_type == "dodge" then
            battle.dodgeBuff = true
        end
        -- 眩晕（通用判定，含递减）
        local stunApplied = false
        if (skillDef.stun_chance or 0) > 0 then
            local stunChance = skillDef.stun_chance
            local monWis = monDef.wis or 0
            local resist = CalcStunResist(monWis, p.stats.wis or 0)
            stunChance = stunChance * (1.0 - resist)
            if battle.stunCount > 0 then
                ---@diagnostic disable-next-line: access-invisible
                stunChance = stunChance * math.pow(Settings.BATTLE.STUN_DIMINISH_MULT, battle.stunCount)
            end
            if math.random() < stunChance then
                battle.monsterStunRounds = battle.monsterStunRounds + 1
                battle.stunCount = battle.stunCount + 1
                stunApplied = true
            end
        end
        m.currentHp = m.currentHp - dmg

        -- 疾风连击（multi_hit 兼容非swift分支但有multi_hit标记的技能）
        local extraDmg = 0
        if skillDef.multi_hit then
            local multiChance = CalcMultiHitChance(p.stats.agi, monDef.agi)
            if multiChance > 0 and math.random() < multiChance then
                extraDmg = math.floor(dmg * B.MULTI_HIT_DAMAGE_MULT)
                m.currentHp = m.currentHp - extraDmg
                logs[#logs + 1] = string.format(
                    "<橙>  ⚡ 触发连击！额外造成 %d 点伤害</橙>", extraDmg)
            end
        end

        -- DoT
        ApplyDoT(battle, skillDef, logs)

        return dmg + extraDmg, skillDef.name, 0, stunApplied, logs
    end
end

-- 冷却倒计时（每回合结束后调用）
local function TickCooldowns(battle)
    for skillId, cd in pairs(battle.skillCooldowns) do
        if cd > 0 then
            battle.skillCooldowns[skillId] = cd - 1
        end
    end
end

-- 构建冷却 JSON 字符串，用于推送给客户端
local function CooldownJson(battle)
    local cjson = require("cjson")
    local t = {}
    for skillId, cd in pairs(battle.skillCooldowns) do
        if cd > 0 then
            t[skillId] = cd
        end
    end
    return cjson.encode(t)
end

-- ============================================================================
-- 公开 API
-- ============================================================================

-- 开始战斗
function Combat.StartBattle(uid, connection, playerData, monsterId)
    if activeBattles[uid] then
        return false, "已在战斗中"
    end

    local monsterDef = Shared.GetMonsterDef(monsterId)
    if not monsterDef then
        return false, "未知的对手"
    end

    local playerStats = Shared.CalcStats(playerData)
    -- 帮会战斗加成（combat_bonus 为固定攻击力加值）
    local guildCombatBonus = playerData.guild_combat_bonus or 0
    if guildCombatBonus > 0 then
        playerStats.atk = (playerStats.atk or 0) + guildCombatBonus
    end
    local skillCoeff  = Shared.CalcSkillCoeff(playerData)
    local weaponCoeff = Shared.CalcWeaponCoeff(playerData)

    -- 使用玩家当前HP（如果有），否则满血开始
    local startHp = playerData.hp or playerStats.hp
    if startHp > playerStats.hp then startHp = playerStats.hp end

    activeBattles[uid] = {
        uid             = uid,
        connection      = connection,
        player = {
            stats       = playerStats,
            currentHp   = startHp,
            currentMp   = playerStats.mp,
            skillCoeff  = skillCoeff,
            weaponCoeff = weaponCoeff,
        },
        monster = {
            def         = monsterDef,
            currentHp   = monsterDef.hp,
        },
        round               = 0,
        timer               = 0,
        medicineCooldown    = 0,
        monsterId           = monsterId,
        -- 技能系统
        autoFight           = (playerData.realm or 1) >= 2,
        pendingSkillId      = nil,
        pendingTimer        = 0,
        skillCooldowns      = {},
        equippedSkills      = GetEquippedSkills(playerData),
        -- 闪避系统
        dodgeBuff           = false,  -- dodge型技能当回合+15%闪避
        -- 疾风剑派连击系统
        swiftComboStack     = 0,
        -- 重剑门眩晕系统
        monsterStunRounds   = 0,
        stunCount           = 0,    -- 已成功眩晕次数（递减用）
        -- defend减伤buffs
        defendBuffs         = {},   -- { { remainRounds = N }, ... }
        -- DoT系统
        monsterDots         = {},   -- { burn = {...}, poison = {...} }
        -- 玩家中毒状态（PvP预留）
        playerPoisoned      = false,
    }

    local battle = activeBattles[uid]
    print(string.format("[Combat] uid=%s 开始战斗，对手：%s autoFight=%s",
        tostring(uid), monsterDef.name, tostring(battle.autoFight)))

    Combat.PushBattleState(activeBattles[uid], "战斗开始！", "none")
    return true, nil
end

-- ============================================================================
-- PvP 天梯战斗：将对手玩家数据构造为虚拟 monsterDef 进入回合制战斗
-- opponentData: 对手的 playerData（真实玩家或快照）
-- opponentName: 对手显示名
-- opponentRating: 对手天梯积分（战后结算用）
-- ============================================================================
function Combat.StartPvPBattle(uid, connection, playerData, opponentData, opponentName, opponentRating)
    if activeBattles[uid] then
        return false, "已在战斗中"
    end

    -- 计算对手属性，构造虚拟 monsterDef
    local opStats = Shared.CalcStats(opponentData)
    local opSkillCoeff = Shared.CalcSkillCoeff(opponentData)
    local opWeaponCoeff = Shared.CalcWeaponCoeff(opponentData)

    -- 虚拟 monster def（使用对手真实属性）
    local virtualMonster = {
        id       = "pvp_opponent",
        name     = opponentName or "天梯对手",
        hp       = opStats.hp,
        atk      = math.floor(opStats.atk * (1 + opSkillCoeff + opWeaponCoeff)),
        def      = opStats.def,
        agi      = opStats.agi,
        wis      = opStats.wis or 0,
        exp      = 0,
        silver   = 0,
        level    = opponentData.realm or 1,
        is_boss  = false,
        is_pvp   = true,  -- PvP 标记
    }

    -- 对手已装备技能（AI出招用）
    local opEquippedSkills = GetEquippedSkills(opponentData)
    if #opEquippedSkills == 0 then
        -- 兜底：至少有普攻
        local fallback = Shared.GetSkillDef("basic_fist") or Shared.GetSkillDef("basic_sword")
        if fallback then opEquippedSkills = { fallback } end
    end

    -- 玩家属性
    local playerStats = Shared.CalcStats(playerData)
    local guildCombatBonus = playerData.guild_combat_bonus or 0
    if guildCombatBonus > 0 then
        playerStats.atk = (playerStats.atk or 0) + guildCombatBonus
    end
    local skillCoeff  = Shared.CalcSkillCoeff(playerData)
    local weaponCoeff = Shared.CalcWeaponCoeff(playerData)

    -- PvP 满血开战
    local startHp = playerStats.hp

    activeBattles[uid] = {
        uid             = uid,
        connection      = connection,
        player = {
            stats       = playerStats,
            currentHp   = startHp,
            currentMp   = playerStats.mp,
            skillCoeff  = skillCoeff,
            weaponCoeff = weaponCoeff,
        },
        monster = {
            def         = virtualMonster,
            currentHp   = virtualMonster.hp,
        },
        round               = 0,
        timer               = 0,
        medicineCooldown    = 0,
        monsterId           = "pvp_opponent",
        -- PvP 标记与数据
        isPvP               = true,
        pvpOpponentUid      = opponentData.uid or nil,
        pvpOpponentRating   = opponentRating or Settings.PVP_LADDER.INITIAL_RATING,
        pvpOpponentSkills   = opEquippedSkills,
        pvpOpponentMp       = opStats.mp,
        pvpOpponentMpMax    = opStats.mp,
        pvpSkillCooldowns   = {},  -- 对手技能冷却
        -- 技能系统
        autoFight           = true,  -- PvP 默认自动战斗
        pendingSkillId      = nil,
        pendingTimer        = 0,
        skillCooldowns      = {},
        equippedSkills      = GetEquippedSkills(playerData),
        -- 闪避系统
        dodgeBuff           = false,
        -- 疾风剑派连击系统
        swiftComboStack     = 0,
        -- 重剑门眩晕系统
        monsterStunRounds   = 0,
        stunCount           = 0,
        -- defend减伤buffs
        defendBuffs         = {},
        -- DoT系统
        monsterDots         = {},
        -- 玩家中毒状态（PvP启用）
        playerPoisoned      = false,
    }

    local battle = activeBattles[uid]
    print(string.format("[Combat] PvP uid=%s vs %s (rating:%d) autoFight=%s",
        tostring(uid), opponentName, opponentRating or 0, tostring(battle.autoFight)))

    Combat.PushBattleState(battle, string.format("天梯对战开始！对手：%s", opponentName), "none")
    return true, nil
end

-- PvP 对手AI出招（从对手已装备技能中选择）
function Combat.PvPPickOpponentSkill(battle)
    if not battle.isPvP then return nil end
    local skills = battle.pvpOpponentSkills or {}
    local cds = battle.pvpSkillCooldowns or {}
    local mp = battle.pvpOpponentMp or 0

    -- 优先选高优先级技能
    local best = nil
    for _, def in ipairs(skills) do
        if def.battle_type ~= "normal" then
            local cd = cds[def.id] or 0
            if cd <= 0 and mp >= (def.mp_cost or 0) then
                if not best or (def.priority or 0) > (best.priority or 0) then
                    best = def
                end
            end
        end
    end

    if best then
        -- 消耗对手MP，设置冷却
        battle.pvpOpponentMp = mp - (best.mp_cost or 0)
        cds[best.id] = best.cooldown or 3
        return best
    end

    -- 兜底普攻
    for _, def in ipairs(skills) do
        if def.battle_type == "normal" then return def end
    end
    return nil
end

-- PvP 对手冷却递减（每回合开始调用）
function Combat.PvPTickOpponentCooldowns(battle)
    if not battle.isPvP then return end
    local cds = battle.pvpSkillCooldowns or {}
    for id, cd in pairs(cds) do
        if cd > 0 then cds[id] = cd - 1 end
    end
    -- 内力回复
    local maxMp = battle.pvpOpponentMpMax or 100
    local regen = math.floor(maxMp * (Settings.BATTLE.INNER_REGEN or 0.1))
    battle.pvpOpponentMp = math.min(maxMp, (battle.pvpOpponentMp or 0) + regen)
end

-- 每帧更新（在 Server Update 中调用）
function Combat.Update(dt)
    local toRemove = {}

    for uid, battle in pairs(activeBattles) do
        battle.timer = battle.timer + dt
        if battle.medicineCooldown > 0 then
            battle.medicineCooldown = battle.medicineCooldown - dt
        end

        local interval = Settings.BATTLE.ROUND_INTERVAL

        if battle.autoFight then
            if battle.timer >= interval then
                battle.timer = battle.timer - interval
                local finished, result = Combat.DoRound(battle, nil)
                if finished then
                    toRemove[#toRemove + 1] = { uid = uid, result = result }
                end
            end
        else
            if battle.pendingSkillId then
                battle.timer = 0
                battle.pendingTimer = 0
                local skillId = battle.pendingSkillId
                battle.pendingSkillId = nil
                local finished, result = Combat.DoRound(battle, skillId)
                if finished then
                    toRemove[#toRemove + 1] = { uid = uid, result = result }
                end
            end
        end
    end

    for _, item in ipairs(toRemove) do
        activeBattles[item.uid] = nil
    end

    return toRemove
end

-- 执行一个战斗回合（skillId=nil 则自动选择）
function Combat.DoRound(battle, skillId)
    battle.round = battle.round + 1
    local logs   = {}
    local p      = battle.player
    local m      = battle.monster
    local monDef = m.def

    -- ── 冷却 & buff 倒计时（回合开始时，对上一回合设置的冷却生效） ──
    if battle.round > 1 then
        TickCooldowns(battle)
        TickDefendBuffs(battle)
    end

    -- ── DoT结算（回合开始时） ────────────────────────────────────────
    if battle.round > 1 then
        local dotDmg = ProcessDoTs(battle, logs)
        if m.currentHp <= 0 then
            logs[#logs + 1] = string.format("<绿>%s被持续伤害击败！</绿>", monDef.name)
            Combat.PushBattleState(battle, table.concat(logs, "\n"), "player")
            return true, { win = true, uid = battle.uid, monsterDef = monDef, connection = battle.connection, playerHp = math.max(0, math.floor(p.currentHp)) }
        end
    end

    -- 内力自然回复
    p.currentMp = p.currentMp + p.stats.mp * Settings.BATTLE.INNER_REGEN
    if p.currentMp > p.stats.mp then p.currentMp = p.stats.mp end

    -- 选择本回合使用的技能
    local skillDef
    if skillId then
        skillDef = Shared.GetSkillDef(skillId)
        if skillDef then
            local cd  = battle.skillCooldowns[skillId] or 0
            local valid = (cd <= 0) and (p.currentMp >= (skillDef.mp_cost or 0))
            if not valid then skillDef = nil end
        end
    end
    if not skillDef then
        skillDef = PickBestSkill(battle)
    end

    -- 出手顺序：agi高者先手（改版：agi直接比较）
    local playerFirst = p.stats.agi >= (monDef.agi or 0)

    local function playerAttack()
        local dmg, skillName, comboStack, stunApplied, extraLogs = ExecuteSkillAttack(battle, skillDef)

        -- 合并额外日志
        if extraLogs then
            for _, l in ipairs(extraLogs) do
                logs[#logs + 1] = l
            end
        end

        -- 主日志
        local typeTag = ""
        if skillDef.battle_type == "normal" then typeTag = "普攻"
        elseif skillDef.battle_type == "damage" then typeTag = "伤害技"
        elseif skillDef.battle_type == "heal"   then typeTag = "治愈技"
        elseif skillDef.battle_type == "defend" then typeTag = "防御技"
        elseif skillDef.battle_type == "dodge"  then typeTag = "闪避技"
        end

        if skillDef.battle_type == "defend" then
            -- defend不造成伤害，日志已在ApplyDefendBuff中添加
            logs[#logs + 1] = string.format(
                "你施展「%s」[%s]，进入防御姿态",
                skillName, typeTag)
        elseif skillDef.battle_type == "heal" then
            -- heal日志已在ExecuteHealSkill中添加
            logs[#logs + 1] = string.format(
                "你施展「%s」[%s]", skillName, typeTag)
        else
            logs[#logs + 1] = string.format(
                "你施展「%s」[%s]，对%s造成 <红>%d</红> 点伤害",
                skillName, typeTag, monDef.name, dmg)
        end

        -- 疾风连击提示
        if comboStack >= 2 then
            local bonus = math.floor((comboStack - 1) * Settings.BATTLE.SWIFT_COMBO_BONUS * 100)
            logs[#logs + 1] = string.format(
                "<橙>  ↑ %d连击！伤害加成 +%d%%</橙>", comboStack, bonus)
        end
        -- 重剑眩晕提示
        if stunApplied then
            logs[#logs + 1] = string.format(
                "<黄>  ★ %s被震慑，下回合无法行动！</黄>", monDef.name)
        end
        -- 重剑无视防御提示
        if skillDef.branch == "heavy" and (skillDef.ignore_def or 0) > 0 then
            local ignorePct = math.floor((skillDef.ignore_def) * 100)
            logs[#logs + 1] = string.format(
                "<蓝>  ▶ 重剑破防！无视%d%%防御</蓝>", ignorePct)
        end
    end

    local function monsterAttack()
        -- 眩晕检查
        if battle.monsterStunRounds > 0 then
            battle.monsterStunRounds = battle.monsterStunRounds - 1
            logs[#logs + 1] = string.format(
                "<黄>%s处于眩晕状态，无法行动！</黄>", monDef.name)
            return
        end

        -- agi闪避判定
        local dodgeChance = CalcDodgeChance(p.stats.agi, monDef.agi or 10, battle.dodgeBuff)
        battle.dodgeBuff = false  -- 用完重置

        if math.random() < dodgeChance then
            logs[#logs + 1] = string.format(
                "你身法飘逸，巧妙躲开了%s的攻击！（闪避率%d%%）",
                monDef.name, math.floor(dodgeChance * 100))
            return
        end

        -- PvP 对手AI出招：使用技能增强伤害
        local pvpSkillBonus = 1.0
        local pvpSkillName = nil
        if battle.isPvP then
            Combat.PvPTickOpponentCooldowns(battle)
            local opSkill = Combat.PvPPickOpponentSkill(battle)
            if opSkill and opSkill.battle_type ~= "normal" then
                pvpSkillBonus = 1.0 + (opSkill.damage_mult or 0.3)
                pvpSkillName = opSkill.name
            end
        end

        -- 计算怪物伤害
        local monAtk = { atk = monDef.atk }
        local dmg    = Shared.CalcDamage(monAtk, { def = p.stats.def }, pvpSkillBonus)

        -- defend减伤
        local reduction = GetDefendReduction(battle)
        if reduction > 0 then
            local reduced = math.floor(dmg * reduction)
            dmg = dmg - reduced
            if dmg < 1 then dmg = 1 end
            logs[#logs + 1] = string.format(
                "<蓝>  🛡 防御减免 %d 点伤害（减伤%d%%）</蓝>",
                reduced, math.floor(reduction * 100))
        end

        p.currentHp  = p.currentHp - dmg
        if pvpSkillName then
            logs[#logs + 1] = string.format("%s施展【%s】，你受到 <红>%d</红> 点伤害（剩余气血：%d）",
                monDef.name, pvpSkillName, dmg, math.max(0, math.floor(p.currentHp)))
        else
            logs[#logs + 1] = string.format("%s反击，你受到 <红>%d</红> 点伤害（剩余气血：%d）",
                monDef.name, dmg, math.max(0, math.floor(p.currentHp)))
        end
    end

    if playerFirst then
        playerAttack()
        if m.currentHp > 0 then monsterAttack() end
    else
        monsterAttack()
        if p.currentHp > 0 then playerAttack() end
    end

    -- 检查战斗结束
    local firstAtk = playerFirst and "player" or "monster"
    if m.currentHp <= 0 then
        logs[#logs + 1] = string.format("<绿>你击败了%s！</绿>", monDef.name)
        Combat.PushBattleState(battle, table.concat(logs, "\n"), firstAtk)
        print(string.format("[Combat] DoRound 战斗结束 win=true uid=%s round=%d", tostring(battle.uid), battle.round))
        return true, { win = true, uid = battle.uid, monsterDef = monDef, connection = battle.connection, playerHp = math.max(0, math.floor(p.currentHp)) }
    end
    if p.currentHp <= 0 then
        logs[#logs + 1] = "<红>你的气血耗尽，战斗失败！</红>"
        Combat.PushBattleState(battle, table.concat(logs, "\n"), firstAtk)
        print(string.format("[Combat] DoRound 战斗结束 win=false uid=%s round=%d", tostring(battle.uid), battle.round))
        return true, { win = false, uid = battle.uid, connection = battle.connection, playerHp = 0 }
    end

    Combat.PushBattleState(battle, table.concat(logs, "\n"), firstAtk)
    return false, nil
end

-- 逃跑
function Combat.Flee(uid)
    local battle = activeBattles[uid]
    if not battle then return false, "你不在战斗中" end

    local monDef  = battle.monster.def
    local agiDiff = battle.player.stats.agi - monDef.agi
    local rate    = Settings.BATTLE.FLEE_BASE_RATE + agiDiff * Settings.BATTLE.FLEE_AGI_FACTOR
    rate = math.max(0.1, math.min(0.9, rate))

    if math.random() < rate then
        local playerHp = math.max(0, math.floor(battle.player.currentHp))
        activeBattles[uid] = nil
        return true, string.format("你趁机脱身，成功逃离了战斗！（逃跑成功率：%d%%）", math.floor(rate * 100)), playerHp
    else
        return false, string.format("逃跑失败！（成功率：%d%%）", math.floor(rate * 100))
    end
end

-- 使用药品
function Combat.UseItem(uid, itemData)
    local battle = activeBattles[uid]
    if not battle then return false, "你不在战斗中" end
    if battle.medicineCooldown > 0 then
        return false, string.format("药品冷却中，还需%.0f秒", battle.medicineCooldown)
    end
    local p = battle.player
    -- 兼容两种格式：heal_hp 或 effect.hp
    local healHp = itemData.heal_hp or (itemData.effect and itemData.effect.hp) or 0
    local healMp = itemData.heal_mp or (itemData.effect and itemData.effect.mp) or 0
    if healHp > 0 then
        p.currentHp = math.min(p.stats.hp, p.currentHp + healHp)
    end
    if healMp > 0 then
        p.currentMp = math.min(p.stats.mp, p.currentMp + healMp)
    end
    battle.medicineCooldown = Settings.BATTLE.MEDICINE_COOLDOWN
    return true, string.format("使用了%s，气血恢复%d点", itemData.name, healHp)
end

-- 手动选择技能（手动模式下调用）
function Combat.UseSkill(uid, skillId)
    local battle = activeBattles[uid]
    if not battle then return false, "你不在战斗中" end
    if battle.autoFight then return false, "当前为自动战斗模式" end
    if battle.pendingSkillId then return false, "已选择技能，等待回合结算" end
    battle.pendingSkillId = skillId
    battle.pendingTimer   = 0
    return true, nil
end

-- 切换自动/手动战斗
function Combat.SetAutoFight(uid, enabled)
    local battle = activeBattles[uid]
    if not battle then return false end
    battle.autoFight      = enabled
    battle.pendingSkillId = nil
    battle.pendingTimer   = 0
    return true
end

-- 检查玩家是否在战斗中
function Combat.IsInBattle(uid)
    return activeBattles[uid] ~= nil
end

-- 获取战斗信息
function Combat.GetBattleInfo(uid)
    return activeBattles[uid]
end

-- 推送战斗状态到客户端
function Combat.PushBattleState(battle, logText, firstAttacker)
    if not battle.connection then return end
    local p      = battle.player
    local m      = battle.monster
    local monDef = m.def

    local data = VariantMap()
    data["Log"]         = Variant(logText or "")
    data["PlayerHp"]    = Variant(math.max(0, math.floor(p.currentHp)))
    data["PlayerHpMax"] = Variant(p.stats.hp)
    data["PlayerMp"]    = Variant(math.max(0, math.floor(p.currentMp)))
    data["PlayerMpMax"] = Variant(p.stats.mp)
    data["MonsterName"] = Variant(monDef.name)
    data["MonsterHp"]   = Variant(math.max(0, math.floor(m.currentHp)))
    data["MonsterHpMax"]= Variant(monDef.hp)
    data["Round"]         = Variant(battle.round)
    data["AutoFight"]     = Variant(battle.autoFight)
    data["Cooldowns"]     = Variant(CooldownJson(battle))
    data["FirstAttacker"] = Variant(firstAttacker or "player")
    data["ComboStack"]    = Variant(battle.swiftComboStack or 0)
    data["MonsterStun"]   = Variant(battle.monsterStunRounds or 0)
    data["PendingSkill"]  = Variant(battle.pendingSkillId or "")
    -- 新增状态
    data["DefendStacks"]  = Variant(#(battle.defendBuffs or {}))
    data["DodgeBuff"]     = Variant(battle.dodgeBuff and 1 or 0)
    battle.connection:SendRemoteEvent(StringHash(Settings.EVENTS.PUSH_BATTLE_STATE), true, data)
end

return Combat
