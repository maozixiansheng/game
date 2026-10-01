-- 称号面板模块
local TitlePanel = {}

function TitlePanel.Build(deps)
    local UI = deps.UI
    local player_ = deps.player
    local Settings = deps.Settings
    local SendToServer = deps.SendToServer
    local EV = deps.EV
    local AddLog = deps.AddLog
    local LOG_COLOR = deps.LOG_COLOR
    local bottomSection = deps.bottomSection

    local p = player_
    if not p then return end

    local container = UI.Panel {
        width = "100%", height = "100%", flexDirection = "column",
        paddingLeft = 8, paddingRight = 8, paddingTop = 6,
    }

    -- 当前佩戴称号
    local activeId = p.active_title or ""
    local activeName = "无"
    local activeColor = LOG_COLOR.white
    if activeId ~= "" then
        for _, t in ipairs(Settings.TITLES) do
            if t.id == activeId then
                activeName = t.name
                activeColor = t.color
                break
            end
        end
    end

    container:AddChild(UI.Panel {
        width = "100%", flexDirection = "row", alignItems = "center",
        marginBottom = 6, paddingBottom = 4,
        children = {
            UI.Label { text = "当前称号: ", fontSize = 13, color = LOG_COLOR.white },
            UI.Label { text = activeName, fontSize = 14, fontWeight = "bold",
                color = activeColor },
            activeId ~= "" and UI.Button {
                text = "卸下", fontSize = 11, variant = "outline",
                marginLeft = 8, height = 22,
                onClick = function()
                    SendToServer(EV.REQ_EQUIP_TITLE, { TitleId = "" })
                end,
            } or nil,
        },
    })

    -- 分割线
    container:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {60,60,60} })

    -- 称号列表
    local ownedSet = {}
    for _, tid in ipairs(p.titles_owned or {}) do
        ownedSet[tid] = true
    end

    -- 成就称号
    container:AddChild(UI.Label {
        text = "成就称号", fontSize = 13, fontWeight = "bold",
        color = LOG_COLOR.cyan, marginTop = 6, marginBottom = 4,
    })
    for _, t in ipairs(Settings.TITLES) do
        if t.source == "achievement" then
            local owned = ownedSet[t.id]
            local equipped = (activeId == t.id)
            local row = UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                marginBottom = 3, paddingLeft = 4,
            }
            row:AddChild(UI.Label {
                text = t.name, fontSize = 13, fontWeight = "bold",
                color = owned and t.color or {100,100,100},
            })
            if owned and not equipped then
                row:AddChild(UI.Button {
                    text = "佩戴", fontSize = 11, variant = "primary",
                    marginLeft = 8, height = 22,
                    onClick = function()
                        SendToServer(EV.REQ_EQUIP_TITLE, { TitleId = t.id })
                    end,
                })
            elseif equipped then
                row:AddChild(UI.Label {
                    text = " [佩戴中]", fontSize = 11, color = LOG_COLOR.green,
                })
            else
                row:AddChild(UI.Label {
                    text = " (未解锁)", fontSize = 11, color = {100,100,100},
                })
            end
            container:AddChild(row)
        end
    end

    -- 商店称号
    container:AddChild(UI.Label {
        text = "商店称号", fontSize = 13, fontWeight = "bold",
        color = LOG_COLOR.gold, marginTop = 8, marginBottom = 4,
    })
    for _, t in ipairs(Settings.TITLES) do
        if t.source == "shop" then
            local owned = ownedSet[t.id]
            local equipped = (activeId == t.id)
            local row = UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                marginBottom = 3, paddingLeft = 4,
            }
            row:AddChild(UI.Label {
                text = t.name, fontSize = 13, fontWeight = "bold",
                color = owned and t.color or {100,100,100},
            })
            if owned and not equipped then
                row:AddChild(UI.Button {
                    text = "佩戴", fontSize = 11, variant = "primary",
                    marginLeft = 8, height = 22,
                    onClick = function()
                        SendToServer(EV.REQ_EQUIP_TITLE, { TitleId = t.id })
                    end,
                })
            elseif equipped then
                row:AddChild(UI.Label {
                    text = " [佩戴中]", fontSize = 11, color = LOG_COLOR.green,
                })
            elseif not owned then
                row:AddChild(UI.Button {
                    text = string.format("购买(%d灵石)", t.cost or 0),
                    fontSize = 11, variant = "warning", marginLeft = 8, height = 22,
                    onClick = function()
                        if (p.spirit_stone or 0) < (t.cost or 0) then
                            AddLog("灵石不足！购买需要 " .. (t.cost or 0) .. " 灵石。", "warning")
                            return
                        end
                        SendToServer(EV.REQ_BUY_TITLE, { TitleId = t.id })
                    end,
                })
            end
            container:AddChild(row)
        end
    end

    -- 灵石余额
    container:AddChild(UI.Panel {
        width = "100%", marginTop = 8, paddingTop = 4,
        flexDirection = "row", justifyContent = "flex-end",
        children = {
            UI.Label {
                text = string.format("灵石余额: %d", math.floor(p.spirit_stone or 0)),
                fontSize = 12, color = LOG_COLOR.gold,
            },
        },
    })

    local scroll = UI.ScrollView { width = "100%", height = "100%", children = { container } }
    bottomSection:AddChild(scroll)
end

return TitlePanel
