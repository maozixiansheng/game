---============================================================
--- 精致古风主题 — 配色表 & 样式工厂
--- 用法: local Theme = require("config.Theme")
---============================================================

local Theme = {}

--------------------------------------------------------------
-- 资源路径
--------------------------------------------------------------
Theme.TEX_BG_MAIN  = "image/bg_ink_paper_20260605054113.png"   -- 深墨色主背景
Theme.TEX_BG_PANEL = "image/bg_scroll_panel_20260605054200.png" -- 竹简卡片底纹

--------------------------------------------------------------
-- 调色板
--------------------------------------------------------------
Theme.C = {
    -- 基础背景
    bgDeep       = { 26, 21, 16, 255 },      -- 最深底色（墨色）
    bgPanel      = { 40, 34, 26, 230 },      -- 卡片/面板底色
    bgPanelLight = { 55, 47, 36, 220 },      -- 浅一档面板底
    bgOverlay    = { 20, 17, 12, 180 },      -- 半透明遮罩

    -- 边框 & 装饰
    border       = { 107, 88, 53, 255 },     -- 古铜边框
    borderLight  = { 140, 115, 70, 180 },    -- 淡金分隔线
    borderGold   = { 200, 170, 90, 255 },    -- 鎏金高光边

    -- 文字
    textPrimary  = { 212, 196, 160, 255 },   -- 主文字（暖绢色）
    textSecondary= { 138, 122, 96, 255 },    -- 次要/说明文字
    textTitle    = { 240, 192, 80, 255 },    -- 标题/鎏金文字
    textAccent   = { 255, 220, 120, 255 },   -- 强调/金色高亮
    textMuted    = { 100, 90, 72, 255 },     -- 灰褪色

    -- 按钮 & 交互
    btnPrimary   = { 160, 50, 40, 255 },     -- 朱砂红按钮
    btnPrimaryHv = { 192, 64, 48, 255 },     -- 按钮 hover
    btnSecondary = { 70, 60, 45, 255 },      -- 次要按钮底色
    btnSecondaryHv = { 90, 78, 58, 255 },    -- 次要 hover
    btnDisabled  = { 60, 55, 48, 180 },      -- 禁用态

    -- 语义色
    success      = { 112, 176, 96, 255 },    -- 翠玉绿（收益/成功）
    warning      = { 224, 160, 48, 255 },    -- 琥珀黄（警告）
    danger       = { 224, 96, 48, 255 },     -- 火焰橙（伤害/危险）
    info         = { 130, 170, 210, 255 },   -- 青瓷蓝（信息）
    rare         = { 180, 130, 255, 255 },   -- 紫气（稀有品质）

    -- 进度条
    barFill      = { 180, 55, 40, 255 },     -- 朱砂填充
    barBg        = { 50, 42, 32, 255 },      -- 条底色
    barExp       = { 100, 180, 120, 255 },   -- 经验条绿

    -- 特殊
    gold         = { 240, 200, 80, 255 },    -- 灵石/金币色
    silver       = { 190, 200, 210, 255 },   -- 银色
    shadow       = { 0, 0, 0, 120 },         -- 投影
}

--------------------------------------------------------------
-- 字体
--------------------------------------------------------------
Theme.FONT = {
    regular = "Fonts/WenKai-Regular.ttf",
    light   = "Fonts/WenKai-Light.ttf",
}

--------------------------------------------------------------
-- 尺寸 & 间距
--------------------------------------------------------------
Theme.SIZE = {
    borderWidth    = 1,
    borderRadius   = 4,
    cardRadius     = 6,
    paddingSm      = 6,
    paddingMd      = 12,
    paddingLg      = 16,
    fontSize       = 14,
    fontSizeSm     = 12,
    fontSizeLg     = 18,
    fontSizeTitle  = 20,
    fontSizeH1     = 24,
}

--------------------------------------------------------------
-- 纹饰符号（用于标题和分割线）
--------------------------------------------------------------
Theme.ORNAMENT = {
    divider      = "————————————————————————",
    dividerShort = "————————————",
    titleLeft    = "══ ",
    titleRight   = " ══",
    sectionLeft  = "——— ",
    sectionRight = " ———",
    bullet       = "",
    diamond      = "*",
    dot          = "-",
    bambooLeft   = "| ",
}

--------------------------------------------------------------
-- 样式工厂函数
--------------------------------------------------------------

--- 主背景面板（全屏根容器）
function Theme.RootPanel(props)
    local p = props or {}
    return {
        width = p.width or "100%",
        height = p.height or "100%",
        backgroundColor = Theme.C.bgDeep,
        backgroundImage = Theme.TEX_BG_MAIN,
        imageTint = { 255, 255, 255, 60 },  -- 底纹若隐若现
    }
end

--- 卡片面板（内容容器）
function Theme.Card(props)
    local p = props or {}
    return {
        backgroundColor = p.backgroundColor or Theme.C.bgPanel,
        backgroundImage = p.showTexture ~= false and Theme.TEX_BG_PANEL or nil,
        imageTint = p.imageTint or { 255, 255, 255, 25 },
        borderColor = p.borderColor or Theme.C.border,
        borderWidth = p.borderWidth or Theme.SIZE.borderWidth,
        borderRadius = p.borderRadius or Theme.SIZE.cardRadius,
        padding = p.padding or Theme.SIZE.paddingMd,
    }
end

--- 标题文字样式
function Theme.TitleStyle(props)
    local p = props or {}
    return {
        fontSize = p.fontSize or Theme.SIZE.fontSizeTitle,
        color = p.color or Theme.C.textTitle,
        textAlign = p.textAlign or "center",
    }
end

--- 正文文字样式
function Theme.TextStyle(props)
    local p = props or {}
    return {
        fontSize = p.fontSize or Theme.SIZE.fontSize,
        color = p.color or Theme.C.textPrimary,
    }
end

--- 朱砂色主按钮样式
function Theme.BtnPrimary(props)
    local p = props or {}
    return {
        backgroundColor = Theme.C.btnPrimary,
        borderRadius = p.borderRadius or Theme.SIZE.borderRadius,
        paddingHorizontal = p.paddingH or 14,
        paddingVertical = p.paddingV or 8,
        color = { 255, 240, 220, 255 },
        fontSize = p.fontSize or Theme.SIZE.fontSize,
    }
end

--- 次要按钮样式（古铜底）
function Theme.BtnSecondary(props)
    local p = props or {}
    return {
        backgroundColor = Theme.C.btnSecondary,
        borderColor = Theme.C.border,
        borderWidth = 1,
        borderRadius = p.borderRadius or Theme.SIZE.borderRadius,
        paddingHorizontal = p.paddingH or 12,
        paddingVertical = p.paddingV or 6,
        color = Theme.C.textPrimary,
        fontSize = p.fontSize or Theme.SIZE.fontSize,
    }
end

--- 分割线标签
function Theme.Divider(short)
    return {
        text = short and Theme.ORNAMENT.dividerShort or Theme.ORNAMENT.divider,
        color = Theme.C.borderLight,
        fontSize = Theme.SIZE.fontSizeSm,
        textAlign = "center",
        marginVertical = 4,
    }
end

--- 带纹饰的段落标题
function Theme.SectionTitle(text)
    return {
        text = Theme.ORNAMENT.sectionLeft .. text .. Theme.ORNAMENT.sectionRight,
        color = Theme.C.textTitle,
        fontSize = Theme.SIZE.fontSizeLg,
        textAlign = "center",
        marginVertical = 6,
    }
end

--- 带纹饰的大标题
function Theme.MainTitle(text)
    return {
        text = Theme.ORNAMENT.titleLeft .. text .. Theme.ORNAMENT.titleRight,
        color = Theme.C.textTitle,
        fontSize = Theme.SIZE.fontSizeH1,
        textAlign = "center",
        marginVertical = 8,
    }
end

return Theme
