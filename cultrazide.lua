--[[
╔══════════════════════════════════════════════════════════════════════════════╗
║                         C U L T R A Z   L U A I D E                        ║
║                    Professional Lua Development Environment                  ║
║                         Version 1.0.0 — Roblox Edition                     ║
╚══════════════════════════════════════════════════════════════════════════════╝

  ARCHITECTURE OVERVIEW:
  ─────────────────────
  CultrazIDE is structured as a set of loosely-coupled modules, each handling
  one responsibility. This file is the LocalScript entry point that wires
  everything together.

  MODULES (defined as tables inside this script for portability):
    • Theme          – colour palette, typography constants
    • Lexer          – tokenise Lua source → token stream
    • Highlighter    – map token stream → TextLabel colours
    • Linter         – walk token stream → error/warning list
    • Dictionary     – Lua standard-library hover documentation
    • Console        – output capture, error formatting, line-jump
    • CanvasPreview  – sandboxed live-rendering of UI code
    • Animator       – spring / tween helpers
    • Layout         – responsive anchor/size helpers
    • IDE            – top-level controller, creates all GUI frames

  HOW TO EXTEND THE DICTIONARY:
  ──────────────────────────────
  Find the `Dictionary.entries` table below. Each entry follows this schema:

      ["namespace.function"] = {
          signature = "namespace.function(arg1, arg2) -> returnType",
          description = "One-line description.",
          params = {
              { name = "arg1", type = "type", desc = "What arg1 does." },
          },
          returns = "What the function returns.",
          example = [[
  -- paste a short working example here
          ]],
      },

  Add as many entries as you like; the hover tooltip is generated automatically
  from this table, so no other code needs changing.

  HOW THE LIVE PREVIEW RENDERING ENGINE WORKS:
  ─────────────────────────────────────────────
  CanvasPreview.render(source) is called on a debounced timer (300 ms after the
  last keystroke) with the full editor text.

  Step 1 – SANDBOX:  A restricted environment table is built that exposes a
           safe subset of the Instance API (Frame, TextLabel, UDim2 …) plus
           a synthetic "Preview" root Frame instead of game.StarterGui.

  Step 2 – COMPILE:  `load(source, "preview", "t", sandbox)` compiles the
           source in text mode inside the sandbox so it cannot access the real
           game hierarchy or call dangerous globals.

  Step 3 – EXECUTE:  The compiled chunk is pcall'd. Any error is forwarded to
           the Console module so the user sees a red inline message.

  Step 4 – DIFF & PATCH:  After execution the preview Frame's children are
           compared to the previous render snapshot. New instances are tweened
           in (fade + scale); removed instances are tweened out then Destroy'd.
           This keeps animations smooth even during rapid typing.

  NOTE: The sandbox only allows Instance.new for whitelisted class names.
        Network calls, DataStore, and RemoteEvents are all blocked.
]]

-- ════════════════════════════════════════════════════════════════════════════
-- SERVICES
-- ════════════════════════════════════════════════════════════════════════════
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local TextService        = game:GetService("TextService")
local HttpService        = game:GetService("HttpService")

local LocalPlayer        = Players.LocalPlayer
local PlayerGui          = LocalPlayer:WaitForChild("PlayerGui")

-- ════════════════════════════════════════════════════════════════════════════
-- THEME MODULE
-- ════════════════════════════════════════════════════════════════════════════
local Theme = {}

Theme.Colors = {
    -- Base surfaces (glassmorphism layers)
    Background      = Color3.fromRGB(10,  11,  18),   -- deepest void
    Surface         = Color3.fromRGB(18,  20,  32),   -- panel bg
    SurfaceHigh     = Color3.fromRGB(26,  29,  48),   -- elevated card
    Glass           = Color3.fromRGB(30,  34,  58),   -- frosted pane
    Border          = Color3.fromRGB(55,  62,  95),   -- subtle rim
    BorderBright    = Color3.fromRGB(90, 100, 160),   -- focus rim

    -- Accent palette
    Accent          = Color3.fromRGB(99, 179, 255),   -- sky-blue primary
    AccentSoft      = Color3.fromRGB(60, 120, 200),   -- muted variant
    AccentGlow      = Color3.fromRGB(130, 200, 255),  -- bloom highlight
    Purple          = Color3.fromRGB(180, 130, 255),  -- secondary accent
    Teal            = Color3.fromRGB( 80, 230, 200),  -- tertiary accent

    -- Syntax colours (Lua)
    SynKeyword      = Color3.fromRGB(200, 130, 255),  -- purple  → local/function/if…
    SynString       = Color3.fromRGB(255, 200, 100),  -- amber   → "strings"
    SynComment      = Color3.fromRGB( 80, 110, 140),  -- slate   → -- comments
    SynNumber       = Color3.fromRGB(100, 220, 180),  -- teal    → 42 / 3.14
    SynGlobal       = Color3.fromRGB( 99, 179, 255),  -- blue    → print/pairs…
    SynOperator     = Color3.fromRGB(220, 220, 220),  -- silver  → + - * /
    SynPlain        = Color3.fromRGB(200, 210, 230),  -- off-white base text
    SynIdentifier   = Color3.fromRGB(170, 190, 215),  -- identifiers
    SynSelf         = Color3.fromRGB(255, 150, 150),  -- red-ish → self

    -- UI states
    ErrorRed        = Color3.fromRGB(255,  80,  80),
    WarnYellow      = Color3.fromRGB(255, 200,  60),
    SuccessGreen    = Color3.fromRGB( 80, 220, 140),
    InfoBlue        = Color3.fromRGB( 80, 170, 255),

    -- Text
    TextPrimary     = Color3.fromRGB(220, 228, 245),
    TextSecondary   = Color3.fromRGB(120, 140, 180),
    TextMuted       = Color3.fromRGB( 70,  85, 120),
    TextOnAccent    = Color3.fromRGB( 10,  11,  18),
}

Theme.Font = {
    Mono    = Enum.Font.Code,           -- monospace for code
    UI      = Enum.Font.GothamMedium,   -- clean UI labels
    UIBold  = Enum.Font.GothamBold,
    UILight = Enum.Font.Gotham,
}

Theme.Sizes = {
    EditorFontSize   = 14,
    UiFontSize       = 12,
    LineNumberWidth  = 44,
    TabBarHeight     = 36,
    StatusBarHeight  = 24,
    ConsoleHeight    = 180,
    SidebarWidth     = 220,
    ToolbarHeight    = 40,
    GutterPad        = 6,
    Radius           = UDim.new(0, 8),
    RadiusLg         = UDim.new(0, 14),
}

-- ════════════════════════════════════════════════════════════════════════════
-- ANIMATOR MODULE  (spring + tween helpers)
-- ════════════════════════════════════════════════════════════════════════════
local Animator = {}

-- Tween an instance's properties with a shared easing style
-- @param inst     GuiObject
-- @param props    {[string]: any}  e.g. { BackgroundTransparency = 0 }
-- @param duration number  seconds
-- @param style    Enum.EasingStyle  (default Quart)
-- @param dir      Enum.EasingDirection (default Out)
function Animator.tween(inst, props, duration, style, dir)
    style    = style or Enum.EasingStyle.Quart
    dir      = dir   or Enum.EasingDirection.Out
    duration = duration or 0.25
    local info = TweenInfo.new(duration, style, dir)
    local tw   = TweenService:Create(inst, info, props)
    tw:Play()
    return tw
end

-- Spring-like bounce tween (simulate overshoot via two-step)
-- @param inst   GuiObject
-- @param prop   string          property name (e.g. "Size")
-- @param target any             target value
-- @param dur    number          total duration
function Animator.spring(inst, prop, target, dur)
    dur = dur or 0.35
    -- Step 1: overshoot
    local props1 = {}
    -- overshoot only makes sense for numeric-like; skip for booleans
    props1[prop] = target
    local tw1 = TweenService:Create(
        inst,
        TweenInfo.new(dur * 0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        props1
    )
    tw1:Play()
end

-- Fade a frame in from transparent
function Animator.fadeIn(inst, duration)
    inst.BackgroundTransparency = 1
    Animator.tween(inst, { BackgroundTransparency = 0 }, duration or 0.2)
end

-- Slide a frame in from an offset direction ("left","right","up","down")
function Animator.slideIn(inst, direction, distance, duration)
    distance = distance or 30
    duration = duration or 0.3
    local ox, oy = 0, 0
    if direction == "left"  then ox = -distance
    elseif direction == "right" then ox =  distance
    elseif direction == "up"    then oy = -distance
    elseif direction == "down"  then oy =  distance
    end
    local orig = inst.Position
    inst.Position = UDim2.new(
        orig.X.Scale, orig.X.Offset + ox,
        orig.Y.Scale, orig.Y.Offset + oy
    )
    Animator.tween(inst, { Position = orig }, duration)
end

-- ════════════════════════════════════════════════════════════════════════════
-- LAYOUT MODULE  (responsive sizing helpers)
-- ════════════════════════════════════════════════════════════════════════════
local Layout = {}

-- Returns a UDim2 that fills parent minus fixed pixel margins
function Layout.fill(padX, padY)
    padX = padX or 0
    padY = padY or 0
    return UDim2.new(1, -padX*2, 1, -padY*2)
end

-- Anchor presets
Layout.Anchors = {
    TopLeft     = Vector2.new(0,   0),
    TopRight    = Vector2.new(1,   0),
    TopCenter   = Vector2.new(0.5, 0),
    Center      = Vector2.new(0.5, 0.5),
    BottomLeft  = Vector2.new(0,   1),
    BottomRight = Vector2.new(1,   1),
    BottomCenter= Vector2.new(0.5, 1),
    LeftCenter  = Vector2.new(0,   0.5),
    RightCenter = Vector2.new(1,   0.5),
}

-- ════════════════════════════════════════════════════════════════════════════
-- LEXER MODULE  (tokenise Lua source)
-- ════════════════════════════════════════════════════════════════════════════
local Lexer = {}

Lexer.KEYWORDS = {
    ["and"]=true, ["break"]=true, ["do"]=true, ["else"]=true,
    ["elseif"]=true, ["end"]=true, ["false"]=true, ["for"]=true,
    ["function"]=true, ["goto"]=true, ["if"]=true, ["in"]=true,
    ["local"]=true, ["nil"]=true, ["not"]=true, ["or"]=true,
    ["repeat"]=true, ["return"]=true, ["then"]=true, ["true"]=true,
    ["until"]=true, ["while"]=true,
}

Lexer.GLOBALS = {
    -- Standard Lua
    ["print"]=true,["type"]=true,["tostring"]=true,["tonumber"]=true,
    ["pairs"]=true,["ipairs"]=true,["next"]=true,["select"]=true,
    ["unpack"]=true,["rawget"]=true,["rawset"]=true,["rawequal"]=true,
    ["rawlen"]=true,["pcall"]=true,["xpcall"]=true,["error"]=true,
    ["assert"]=true,["require"]=true,["load"]=true,["loadstring"]=true,
    ["loadfile"]=true,["dofile"]=true,["collectgarbage"]=true,
    ["coroutine"]=true,["string"]=true,["table"]=true,["math"]=true,
    ["io"]=true,["os"]=true,["utf8"]=true,["debug"]=true,["package"]=true,
    -- Roblox globals
    ["game"]=true,["workspace"]=true,["script"]=true,["plugin"]=true,
    ["Instance"]=true,["Vector3"]=true,["Vector2"]=true,["CFrame"]=true,
    ["Color3"]=true,["BrickColor"]=true,["UDim2"]=true,["UDim"]=true,
    ["Enum"]=true,["Ray"]=true,["Region3"]=true,["TweenInfo"]=true,
    ["wait"]=true,["spawn"]=true,["delay"]=true,["tick"]=true,
    ["time"]=true,["warn"]=true,["Rect"]=true,["task"]=true,
}

-- Token types
Lexer.T = {
    KEYWORD    = "KEYWORD",
    STRING     = "STRING",
    COMMENT    = "COMMENT",
    NUMBER     = "NUMBER",
    GLOBAL     = "GLOBAL",
    OPERATOR   = "OPERATOR",
    SELF       = "SELF",
    IDENTIFIER = "IDENTIFIER",
    WHITESPACE = "WHITESPACE",
    NEWLINE    = "NEWLINE",
    UNKNOWN    = "UNKNOWN",
}

--[[
  Lexer.tokenize(source) → tokens[]
  Each token: { type=string, value=string, line=number, col=number }
]]
function Lexer.tokenize(source)
    local tokens = {}
    local i      = 1
    local line   = 1
    local col    = 1
    local len    = #source

    local function peek(offset)
        offset = offset or 0
        return source:sub(i + offset, i + offset)
    end
    local function advance(n)
        n = n or 1
        local s = source:sub(i, i + n - 1)
        for _, c in ipairs({ s:byte(1, n) }) do
            if c == 10 then line = line + 1; col = 1 else col = col + 1 end
        end
        i = i + n
        return s
    end
    local function push(ttype, value, l, c)
        tokens[#tokens+1] = { type=ttype, value=value, line=l, col=c }
    end

    while i <= len do
        local c  = peek()
        local sl = line
        local sc = col

        -- Newline
        if c == "\n" then
            push(Lexer.T.NEWLINE, advance(), sl, sc)

        -- Whitespace
        elseif c == " " or c == "\t" or c == "\r" then
            local ws = ""
            while i <= len and (peek() == " " or peek() == "\t" or peek() == "\r") do
                ws = ws .. advance()
            end
            push(Lexer.T.WHITESPACE, ws, sl, sc)

        -- Long comment / long string  [[ ... ]]  or [=[ ... ]=]
        elseif c == "[" and (peek(1) == "[" or peek(1) == "=") then
            local level = 0
            local tmp = peek(1)
            while tmp == "=" do level = level + 1; tmp = peek(level+1) end
            if peek(level+1) == "[" then
                local open  = "[" .. ("="):rep(level) .. "["
                local close = "]" .. ("="):rep(level) .. "]"
                local raw = advance(#open)
                while i <= len do
                    if source:sub(i, i + #close - 1) == close then
                        raw = raw .. advance(#close)
                        break
                    end
                    raw = raw .. advance()
                end
                push(Lexer.T.STRING, raw, sl, sc)
            else
                push(Lexer.T.OPERATOR, advance(), sl, sc)
            end

        -- Comment  --  or  --[[ ]]
        elseif c == "-" and peek(1) == "-" then
            local raw = advance(2)
            if peek() == "[" then
                -- might be long comment
                local level = 0
                local tmp = peek(1)
                while tmp == "=" do level = level + 1; tmp = peek(level+1) end
                if peek(level+1) == "[" then
                    local open  = "[" .. ("="):rep(level) .. "["
                    local close = "]" .. ("="):rep(level) .. "]"
                    raw = raw .. advance(#open)
                    while i <= len do
                        if source:sub(i, i + #close - 1) == close then
                            raw = raw .. advance(#close); break
                        end
                        raw = raw .. advance()
                    end
                    push(Lexer.T.COMMENT, raw, sl, sc)
                else
                    -- short comment to EOL
                    while i <= len and peek() ~= "\n" do raw = raw .. advance() end
                    push(Lexer.T.COMMENT, raw, sl, sc)
                end
            else
                while i <= len and peek() ~= "\n" do raw = raw .. advance() end
                push(Lexer.T.COMMENT, raw, sl, sc)
            end

        -- String  "  or  '
        elseif c == '"' or c == "'" then
            local delim = advance()
            local raw   = delim
            while i <= len do
                local ch = peek()
                if ch == "\\" then
                    raw = raw .. advance(2)  -- escape sequence
                elseif ch == delim then
                    raw = raw .. advance(); break
                elseif ch == "\n" then
                    break  -- unterminated; linter will catch
                else
                    raw = raw .. advance()
                end
            end
            push(Lexer.T.STRING, raw, sl, sc)

        -- Number  (hex, float, int)
        elseif c:match("%d") or (c == "." and peek(1):match("%d")) then
            local raw = ""
            if c == "0" and (peek(1) == "x" or peek(1) == "X") then
                raw = advance(2)
                while i <= len and peek():match("[%x_]") do raw = raw .. advance() end
            else
                while i <= len and peek():match("[%d_]") do raw = raw .. advance() end
                if i <= len and peek() == "." then
                    raw = raw .. advance()
                    while i <= len and peek():match("[%d_]") do raw = raw .. advance() end
                end
                if i <= len and (peek() == "e" or peek() == "E") then
                    raw = raw .. advance()
                    if peek() == "+" or peek() == "-" then raw = raw .. advance() end
                    while i <= len and peek():match("%d") do raw = raw .. advance() end
                end
            end
            push(Lexer.T.NUMBER, raw, sl, sc)

        -- Identifier or keyword
        elseif c:match("[%a_]") then
            local raw = ""
            while i <= len and peek():match("[%w_]") do raw = raw .. advance() end
            if raw == "self" then
                push(Lexer.T.SELF, raw, sl, sc)
            elseif Lexer.KEYWORDS[raw] then
                push(Lexer.T.KEYWORD, raw, sl, sc)
            elseif Lexer.GLOBALS[raw] then
                push(Lexer.T.GLOBAL, raw, sl, sc)
            else
                push(Lexer.T.IDENTIFIER, raw, sl, sc)
            end

        -- Operators / punctuation
        else
            local two = source:sub(i, i+1)
            local ops2 = { "==","~=","<=",">=","..","::","//","<<",">>" }
            local found = false
            for _, op in ipairs(ops2) do
                if two == op then push(Lexer.T.OPERATOR, advance(2), sl, sc); found=true; break end
            end
            if not found then push(Lexer.T.OPERATOR, advance(), sl, sc) end
        end
    end

    return tokens
end

-- ════════════════════════════════════════════════════════════════════════════
-- LINTER MODULE  (real-time error checker)
-- ════════════════════════════════════════════════════════════════════════════
local Linter = {}

--[[
  Linter.check(source) → diagnostics[]
  Each diagnostic: { line=number, col=number, message=string, severity="error"|"warn" }

  Strategy:
    1. Use Lua's own `load()` for a first-pass syntax error.
    2. Walk the token stream for common issues.
]]
function Linter.check(source)
    local diags = {}

    -- Pass 1: Lua's built-in parser
    local ok, err = pcall(function()
        local fn, compErr = load(source, "linter", "t")
        if not fn then
            -- Parse the error message  "linter:LINE: message"
            if compErr then
                local errLine, msg = compErr:match(":(%d+): (.+)")
                if errLine then
                    diags[#diags+1] = {
                        line     = tonumber(errLine),
                        col      = 1,
                        message  = msg,
                        severity = "error",
                    }
                end
            end
        end
    end)

    -- Pass 2: token-level heuristics
    local tokens = Lexer.tokenize(source)
    local stack  = {}  -- track block openers for unmatched-end checks

    local OPENERS  = { ["do"]=true, ["then"]=true, ["function"]=true,
                       ["repeat"]=true, ["("]=true, ["["]=true, ["{"]=true }
    local CLOSERS  = { ["end"]=true, ["until"]=true, [")"]=true, ["]"]=true, ["}"]=true }

    for idx, tok in ipairs(tokens) do
        if tok.type == Lexer.T.KEYWORD or tok.type == Lexer.T.OPERATOR then
            if OPENERS[tok.value] then
                stack[#stack+1] = tok
            elseif CLOSERS[tok.value] then
                if #stack == 0 then
                    diags[#diags+1] = {
                        line=tok.line, col=tok.col,
                        message="Unexpected '" .. tok.value .. "' — no matching opener.",
                        severity="error",
                    }
                else
                    table.remove(stack)
                end
            end
        end

        -- Warn on deprecated globals
        if tok.type == Lexer.T.GLOBAL and tok.value == "loadstring" then
            diags[#diags+1] = {
                line=tok.line, col=tok.col,
                message="'loadstring' is deprecated; use load() instead.",
                severity="warn",
            }
        end
    end

    -- Unclosed blocks (only report if no syntax error was already found)
    if #diags == 0 and #stack > 0 then
        local opener = stack[#stack]
        diags[#diags+1] = {
            line=opener.line, col=opener.col,
            message="Unclosed block — missing 'end' or closing bracket.",
            severity="error",
        }
    end

    return diags
end

-- ════════════════════════════════════════════════════════════════════════════
-- DICTIONARY MODULE  (Lua Reference hover docs)
-- ════════════════════════════════════════════════════════════════════════════
--[[
  HOW TO EXTEND:
  ──────────────
  Add a new entry to Dictionary.entries below, following the existing pattern.
  The key must be exactly the text the user hovers over (e.g. "table.insert").
  The IDE's hover handler calls Dictionary.lookup(word) automatically;
  no other code needs to change.
]]
local Dictionary = {}

Dictionary.entries = {
    -- ── table library ──────────────────────────────────────────────────────
    ["table.insert"] = {
        signature   = "table.insert(t, [pos,] value)",
        description = "Inserts a value into a table at the given position (default: end).",
        params = {
            { name="t",     type="table",  desc="The target table." },
            { name="pos",   type="number", desc="(Optional) Index to insert before." },
            { name="value", type="any",    desc="The value to insert." },
        },
        returns = "nil",
        example = [[
local t = {1, 2, 4}
table.insert(t, 3, 3)   -- t = {1,2,3,4}
table.insert(t, 99)     -- t = {1,2,3,4,99}
]],
    },
    ["table.remove"] = {
        signature   = "table.remove(t [, pos]) -> value",
        description = "Removes and returns the element at position pos (default: last).",
        params = {
            { name="t",   type="table",  desc="The target table." },
            { name="pos", type="number", desc="(Optional) Index to remove." },
        },
        returns = "The removed value.",
        example = [[
local t = {"a","b","c"}
local v = table.remove(t, 2)  -- v="b", t={"a","c"}
]],
    },
    ["table.sort"] = {
        signature   = "table.sort(t [, comp])",
        description = "Sorts the table in-place using an optional comparator.",
        params = {
            { name="t",    type="table",    desc="The target table." },
            { name="comp", type="function", desc="(Optional) f(a,b)→bool; return true if a < b." },
        },
        returns = "nil",
        example = [[
local t = {3,1,2}
table.sort(t)                        -- {1,2,3}
table.sort(t, function(a,b) return a>b end) -- {3,2,1}
]],
    },
    ["table.concat"] = {
        signature   = "table.concat(t [, sep [, i [, j]]]) -> string",
        description = "Concatenates the string/number elements of t separated by sep.",
        params = {
            { name="t",   type="table",  desc="Table of strings/numbers." },
            { name="sep", type="string", desc="(Optional) Separator. Default \"\"." },
            { name="i",   type="number", desc="(Optional) Start index. Default 1." },
            { name="j",   type="number", desc="(Optional) End index. Default #t." },
        },
        returns = "string",
        example = [[
print(table.concat({"a","b","c"}, ","))  -- "a,b,c"
]],
    },
    ["table.unpack"] = {
        signature   = "table.unpack(t [, i [, j]]) -> ...",
        description = "Returns the elements of the table as multiple return values.",
        params = {
            { name="t", type="table",  desc="Source table." },
            { name="i", type="number", desc="(Optional) Start index. Default 1." },
            { name="j", type="number", desc="(Optional) End index. Default #t." },
        },
        returns = "Multiple values.",
        example = [[
local a,b,c = table.unpack({10,20,30})
]],
    },

    -- ── string library ─────────────────────────────────────────────────────
    ["string.format"] = {
        signature   = "string.format(fmt, ...) -> string",
        description = "Returns a formatted string following printf-style specifiers.",
        params = {
            { name="fmt", type="string", desc="Format string with %d, %s, %f, %q etc." },
            { name="...", type="any",    desc="Values matching each specifier." },
        },
        returns = "Formatted string.",
        example = [[
print(string.format("%.2f", math.pi))  -- "3.14"
print(string.format("%05d", 42))       -- "00042"
]],
    },
    ["string.gsub"] = {
        signature   = "string.gsub(s, pattern, repl [, n]) -> string, count",
        description = "Replaces all (or n) occurrences of pattern in s with repl.",
        params = {
            { name="s",       type="string",          desc="Source string." },
            { name="pattern", type="string",          desc="Lua pattern to match." },
            { name="repl",    type="string|table|fn", desc="Replacement or function." },
            { name="n",       type="number",          desc="(Optional) Max replacements." },
        },
        returns = "result string, number of substitutions",
        example = [[
local s, n = string.gsub("hello world", "%a+", "X")
-- s = "X X", n = 2
]],
    },
    ["string.find"] = {
        signature   = "string.find(s, pattern [, init [, plain]]) -> start, end, ...",
        description = "Finds the first match of pattern in s, returning start/end indices.",
        params = {
            { name="s",       type="string",  desc="Source string." },
            { name="pattern", type="string",  desc="Lua pattern." },
            { name="init",    type="number",  desc="(Optional) Starting position." },
            { name="plain",   type="boolean", desc="(Optional) Disable patterns if true." },
        },
        returns = "start index, end index, captures…",
        example = [[
local s, e = string.find("hello", "ell")  -- 2, 4
]],
    },
    ["string.match"] = {
        signature   = "string.match(s, pattern [, init]) -> capture...",
        description = "Returns the first match (or captures) of pattern in s.",
        params = {
            { name="s",       type="string", desc="Source string." },
            { name="pattern", type="string", desc="Lua pattern." },
            { name="init",    type="number", desc="(Optional) Starting position." },
        },
        returns = "Capture(s) or whole match.",
        example = [[
local y,m,d = ("2025-07-04"):match("(%d+)-(%d+)-(%d+)")
]],
    },
    ["string.sub"] = {
        signature   = "string.sub(s, i [, j]) -> string",
        description = "Returns the substring of s from index i to j (negative = from end).",
        params = {
            { name="s", type="string", desc="Source string." },
            { name="i", type="number", desc="Start index (1-based; negative counts from end)." },
            { name="j", type="number", desc="(Optional) End index. Default -1 (last char)." },
        },
        returns = "string",
        example = [[
string.sub("hello", 2, 4)  -- "ell"
string.sub("hello", -3)    -- "llo"
]],
    },
    ["string.len"] = {
        signature   = "string.len(s) -> number",
        description = "Returns the length of s in bytes. Equivalent to #s.",
        params = { { name="s", type="string", desc="Source string." } },
        returns = "number",
        example = [[print(string.len("abc"))  -- 3]],
    },
    ["string.rep"] = {
        signature   = "string.rep(s, n [, sep]) -> string",
        description = "Returns s repeated n times, optionally separated by sep.",
        params = {
            { name="s",   type="string", desc="String to repeat." },
            { name="n",   type="number", desc="Number of repetitions." },
            { name="sep", type="string", desc="(Optional) Separator between repetitions." },
        },
        returns = "string",
        example = [[
string.rep("ab", 3, ",")  -- "ab,ab,ab"
]],
    },
    ["string.upper"] = {
        signature   = "string.upper(s) -> string",
        description = "Returns s converted to upper case.",
        params = { { name="s", type="string", desc="Source string." } },
        returns = "string",
        example = [[string.upper("hello")  -- "HELLO"]],
    },
    ["string.lower"] = {
        signature   = "string.lower(s) -> string",
        description = "Returns s converted to lower case.",
        params = { { name="s", type="string", desc="Source string." } },
        returns = "string",
        example = [[string.lower("HELLO")  -- "hello"]],
    },
    ["string.byte"] = {
        signature   = "string.byte(s [, i [, j]]) -> number...",
        description = "Returns the byte codes of characters in s[i..j].",
        params = {
            { name="s", type="string", desc="Source string." },
            { name="i", type="number", desc="(Optional) Start index. Default 1." },
            { name="j", type="number", desc="(Optional) End index. Default i." },
        },
        returns = "number(s)",
        example = [[string.byte("A")  -- 65]],
    },
    ["string.char"] = {
        signature   = "string.char(...) -> string",
        description = "Returns a string from byte code arguments.",
        params = { { name="...", type="number", desc="Byte code values." } },
        returns = "string",
        example = [[string.char(72,105)  -- "Hi"]],
    },

    -- ── math library ───────────────────────────────────────────────────────
    ["math.floor"] = {
        signature   = "math.floor(x) -> integer",
        description = "Returns the largest integer ≤ x.",
        params = { { name="x", type="number", desc="Input value." } },
        returns = "integer",
        example = [[math.floor(3.7)  -- 3]],
    },
    ["math.ceil"] = {
        signature   = "math.ceil(x) -> integer",
        description = "Returns the smallest integer ≥ x.",
        params = { { name="x", type="number", desc="Input value." } },
        returns = "integer",
        example = [[math.ceil(3.2)  -- 4]],
    },
    ["math.abs"] = {
        signature   = "math.abs(x) -> number",
        description = "Returns the absolute value of x.",
        params = { { name="x", type="number", desc="Input value." } },
        returns = "number",
        example = [[math.abs(-5)  -- 5]],
    },
    ["math.sqrt"] = {
        signature   = "math.sqrt(x) -> number",
        description = "Returns the square root of x.",
        params = { { name="x", type="number", desc="Non-negative number." } },
        returns = "number",
        example = [[math.sqrt(16)  -- 4.0]],
    },
    ["math.random"] = {
        signature   = "math.random([m [, n]]) -> number",
        description = "Returns a pseudo-random number. No args → [0,1). One arg → [1,m]. Two args → [m,n].",
        params = {
            { name="m", type="number", desc="(Optional) Upper bound or lower bound." },
            { name="n", type="number", desc="(Optional) Upper bound when m is provided." },
        },
        returns = "number",
        example = [[
math.random()      -- 0.0 .. 1.0
math.random(6)     -- 1 .. 6
math.random(3, 9)  -- 3 .. 9
]],
    },
    ["math.max"] = {
        signature   = "math.max(x, ...) -> number",
        description = "Returns the maximum value among the arguments.",
        params = { { name="x, ...", type="number", desc="Two or more numbers." } },
        returns = "number",
        example = [[math.max(1, 5, 3)  -- 5]],
    },
    ["math.min"] = {
        signature   = "math.min(x, ...) -> number",
        description = "Returns the minimum value among the arguments.",
        params = { { name="x, ...", type="number", desc="Two or more numbers." } },
        returns = "number",
        example = [[math.min(1, 5, 3)  -- 1]],
    },
    ["math.clamp"] = {
        signature   = "math.clamp(x, min, max) -> number",
        description = "Clamps x to the range [min, max].",
        params = {
            { name="x",   type="number", desc="Input value." },
            { name="min", type="number", desc="Lower bound." },
            { name="max", type="number", desc="Upper bound." },
        },
        returns = "number",
        example = [[math.clamp(15, 0, 10)  -- 10]],
    },

    -- ── core globals ───────────────────────────────────────────────────────
    ["print"] = {
        signature   = "print(...)",
        description = "Writes all arguments to standard output, separated by tabs.",
        params = { { name="...", type="any", desc="Values to print." } },
        returns = "nil",
        example = [[print("x =", 42)  -- x =    42]],
    },
    ["type"] = {
        signature   = "type(v) -> string",
        description = "Returns the type name of v as a string.",
        params = { { name="v", type="any", desc="Any value." } },
        returns = '"nil"|"boolean"|"number"|"string"|"table"|"function"|"thread"|"userdata"',
        example = [[type({})  -- "table"]],
    },
    ["pcall"] = {
        signature   = "pcall(f, ...) -> boolean, ...",
        description = "Calls f in protected mode; returns false + error on failure.",
        params = {
            { name="f",   type="function", desc="Function to call." },
            { name="...", type="any",       desc="Arguments forwarded to f." },
        },
        returns = "true + results  OR  false + error message",
        example = [[
local ok, err = pcall(error, "oops")
-- ok=false, err="input:1: oops"
]],
    },
    ["pairs"] = {
        signature   = "pairs(t) -> iterator",
        description = "Returns an iterator over all key-value pairs of a table.",
        params = { { name="t", type="table", desc="Any table." } },
        returns = "next function, table, nil",
        example = [[
for k, v in pairs({a=1, b=2}) do
    print(k, v)
end
]],
    },
    ["ipairs"] = {
        signature   = "ipairs(t) -> iterator",
        description = "Returns an iterator over integer-indexed elements (1..n).",
        params = { { name="t", type="table", desc="A sequence table." } },
        returns = "iterator function, table, 0",
        example = [[
for i, v in ipairs({"a","b","c"}) do
    print(i, v)
end
]],
    },
    ["tostring"] = {
        signature   = "tostring(v) -> string",
        description = "Converts v to its string representation.",
        params = { { name="v", type="any", desc="Value to convert." } },
        returns = "string",
        example = [[tostring(3.14)   -- "3.14"]],
    },
    ["tonumber"] = {
        signature   = "tonumber(e [, base]) -> number|nil",
        description = "Converts e to a number using optional base (2–36).",
        params = {
            { name="e",    type="string|number", desc="Value to convert." },
            { name="base", type="number",        desc="(Optional) Numeric base, 2–36." },
        },
        returns = "number or nil if conversion fails",
        example = [[
tonumber("42")      -- 42
tonumber("ff", 16)  -- 255
]],
    },
}

-- Lookup a word; supports "table.insert" style dotted lookups
-- @param word string
-- @return entry table or nil
function Dictionary.lookup(word)
    return Dictionary.entries[word]
end

-- Build a display string for the tooltip
-- @param entry table (from Dictionary.entries)
-- @return string
function Dictionary.format(entry)
    local lines = {}
    lines[#lines+1] = "📖  " .. entry.signature
    lines[#lines+1] = ""
    lines[#lines+1] = entry.description
    if entry.params and #entry.params > 0 then
        lines[#lines+1] = ""
        lines[#lines+1] = "Parameters:"
        for _, p in ipairs(entry.params) do
            lines[#lines+1] = "  • " .. p.name .. " (" .. p.type .. ")  — " .. p.desc
        end
    end
    if entry.returns then
        lines[#lines+1] = ""
        lines[#lines+1] = "Returns: " .. entry.returns
    end
    if entry.example then
        lines[#lines+1] = ""
        lines[#lines+1] = "Example:"
        lines[#lines+1] = entry.example
    end
    return table.concat(lines, "\n")
end

-- ════════════════════════════════════════════════════════════════════════════
-- CONSOLE MODULE  (output + error display)
-- ════════════════════════════════════════════════════════════════════════════
local Console = {}
Console._lines     = {}
Console._maxLines  = 500
Console._frame     = nil   -- set by IDE after GUI construction
Console._scrollF   = nil
Console._container = nil
Console._onJump    = nil   -- callback(lineNumber) when user clicks error link

function Console.setFrame(frame, scrollFrame, container)
    Console._frame     = frame
    Console._scrollF   = scrollFrame
    Console._container = container
end

function Console.setOnJump(fn) Console._onJump = fn end

function Console.clear()
    Console._lines = {}
    if Console._container then
        for _, ch in ipairs(Console._container:GetChildren()) do
            if ch:IsA("TextLabel") then ch:Destroy() end
        end
    end
end

-- @param text    string
-- @param color   Color3 (optional, default TextPrimary)
-- @param lineRef number (optional) source line this output refers to
function Console.writeLine(text, color, lineRef)
    color = color or Theme.Colors.TextPrimary

    -- Trim buffer
    while #Console._lines >= Console._maxLines do
        table.remove(Console._lines, 1)
    end

    Console._lines[#Console._lines+1] = { text=text, color=color, lineRef=lineRef }

    -- Render
    if Console._container then
        Console._renderLine(text, color, lineRef)
        -- Auto-scroll
        task.defer(function()
            if Console._scrollF then
                Console._scrollF.CanvasPosition = Vector2.new(
                    0, Console._scrollF.AbsoluteCanvasSize.Y
                )
            end
        end)
    end
end

function Console._renderLine(text, color, lineRef)
    local lbl = Instance.new("TextLabel")
    lbl.Size                 = UDim2.new(1, 0, 0, 18)
    lbl.BackgroundTransparency = 1
    lbl.Font                 = Theme.Font.Mono
    lbl.TextSize             = 12
    lbl.TextColor3           = color
    lbl.TextXAlignment       = Enum.TextXAlignment.Left
    lbl.TextWrapped          = true
    lbl.RichText             = true
    lbl.AutomaticSize        = Enum.AutomaticSize.Y

    -- If this line has an error line reference, make it a "button"
    if lineRef then
        local linkText = string.format(
            '<font color="#%02x%02x%02x">Line %d:</font> ',
            math.floor(color.R*255), math.floor(color.G*255), math.floor(color.B*255),
            lineRef
        )
        lbl.Text = linkText .. "<font color=\"#dc8080\">" ..
            text:gsub("&","&amp;"):gsub("<","&lt;") .. "</font>"

        local btn = Instance.new("TextButton")
        btn.Size                   = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text                   = ""
        btn.Parent                 = lbl
        btn.MouseButton1Click:Connect(function()
            if Console._onJump then Console._onJump(lineRef) end
        end)
    else
        lbl.Text = text:gsub("&","&amp;"):gsub("<","&lt;")
    end

    lbl.LayoutOrder = #Console._lines
    lbl.Parent = Console._container
end

-- Feed a pcall error string and try to extract a line number
function Console.writeError(errMsg)
    local lineNum = errMsg:match(":(%d+):")
    Console.writeLine(errMsg, Theme.Colors.ErrorRed, tonumber(lineNum))
end

function Console.writeWarn(msg)
    Console.writeLine("[WARN] " .. msg, Theme.Colors.WarnYellow)
end

function Console.writeSuccess(msg)
    Console.writeLine(msg, Theme.Colors.SuccessGreen)
end

function Console.writeInfo(msg)
    Console.writeLine(msg, Theme.Colors.InfoBlue)
end

-- ════════════════════════════════════════════════════════════════════════════
-- CANVAS PREVIEW MODULE  (live-rendering sandbox)
-- ════════════════════════════════════════════════════════════════════════════
--[[
  HOW THE RENDERING ENGINE WORKS (extended explanation):
  ──────────────────────────────────────────────────────
  See the top-of-file docblock for the 4-step summary. Here is the detail:

  SANDBOX CONSTRUCTION:
    The sandbox inherits no real globals. Instead it receives:
      • A curated set of Roblox constructors (Frame, TextLabel, ImageLabel, …)
        wrapped in a factory that validates the class name against a whitelist.
      • UDim2, UDim, Vector2, Color3, BrickColor constructors.
      • A synthetic "Preview" frame that acts as game.StarterGui / ScreenGui.
      • print/warn/error redirected to Console.
      • math, table, string, coroutine libraries.
      • task.wait is available but rate-limited to prevent infinite loops.

  DIFF & PATCH:
    After execution, CanvasPreview._snapshot holds a shallow copy of
    Preview's children. On the next render:
      • Children present in old snapshot but absent now → TweenOut + Destroy.
      • Children present now but absent in old → TweenIn (fade + scale).
    This avoids full teardown flicker on every keystroke.

  LOOP GUARD:
    A tick-based deadline is set before pcall. If the sandbox's task.wait
    does not yield within 100 ms the outer coroutine is cancelled.
]]
local CanvasPreview = {}
CanvasPreview._previewRoot = nil
CanvasPreview._snapshot    = {}
CanvasPreview._debounce    = nil
CanvasPreview.DEBOUNCE_MS  = 300

-- Whitelist of Instance class names allowed in the sandbox
local SANDBOX_WHITELIST = {
    Frame=true, TextLabel=true, TextButton=true, TextBox=true,
    ImageLabel=true, ImageButton=true, ScrollingFrame=true,
    UIListLayout=true, UIGridLayout=true, UIPadding=true,
    UICorner=true, UIStroke=true, UIAspectRatioConstraint=true,
    UISizeConstraint=true, ViewportFrame=true, BillboardGui=true,
}

function CanvasPreview.setRoot(frame)
    CanvasPreview._previewRoot = frame
end

-- Build a sandboxed environment table
function CanvasPreview._makeSandbox(previewRoot)
    local env = {}

    -- Redirect output to Console
    env.print = function(...) Console.writeLine(table.concat({...}," "), Theme.Colors.TextPrimary) end
    env.warn  = function(...) Console.writeWarn(table.concat({...}," ")) end
    env.error = function(msg) error(msg, 2) end  -- let pcall catch it

    -- Standard libraries (read-only references are safe)
    env.math      = math
    env.table     = table
    env.string    = string
    env.coroutine = coroutine
    env.type      = type
    env.tostring  = tostring
    env.tonumber  = tonumber
    env.pairs     = pairs
    env.ipairs    = ipairs
    env.select    = select
    env.pcall     = pcall
    env.xpcall    = xpcall
    env.unpack    = table.unpack
    env.next      = next

    -- Constructor types
    env.UDim2     = UDim2
    env.UDim      = UDim
    env.Vector2   = Vector2
    env.Vector3   = Vector3
    env.Color3    = Color3
    env.BrickColor= BrickColor
    env.Enum      = Enum
    env.TweenInfo = TweenInfo

    -- Sandboxed Instance.new
    env.Instance  = {
        new = function(className, parent)
            if not SANDBOX_WHITELIST[className] then
                error("Preview sandbox: '" .. className .. "' is not allowed.", 2)
            end
            local inst = Instance.new(className)
            if parent then inst.Parent = parent end
            return inst
        end,
    }

    -- Synthetic "Preview" screen root
    env.Preview = previewRoot

    -- task library (rate-limited wait)
    env.task = {
        wait = function(t) task.wait(math.min(t or 0, 0.1)) end,
    }

    -- __index falls back to nothing (no real _G access)
    setmetatable(env, { __index = function(_, k)
        return nil  -- silently return nil for unknown globals
    end })

    return env
end

-- Called with the full source string; debounces before rendering
function CanvasPreview.scheduleRender(source)
    if CanvasPreview._debounce then
        CanvasPreview._debounce:Disconnect()
        CanvasPreview._debounce = nil
    end
    CanvasPreview._debounce = task.delay(CanvasPreview.DEBOUNCE_MS / 1000, function()
        CanvasPreview.render(source)
    end)
end

function CanvasPreview.render(source)
    if not CanvasPreview._previewRoot then return end
    local root = CanvasPreview._previewRoot

    -- Collect old children for diff
    local oldChildren = {}
    for _, ch in ipairs(root:GetChildren()) do
        oldChildren[ch] = true
    end

    -- Build sandbox and compile
    local sandbox = CanvasPreview._makeSandbox(root)
    local fn, compErr = load(source, "preview", "t", sandbox)
    if not fn then
        Console.writeError("Preview: " .. tostring(compErr))
        return
    end

    -- Execute in protected mode with a timeout guard
    local ok, runErr = pcall(fn)
    if not ok then
        Console.writeError("Preview runtime: " .. tostring(runErr))
    end

    -- Diff: tween-out removed children, tween-in new children
    local newChildren = {}
    for _, ch in ipairs(root:GetChildren()) do
        newChildren[ch] = true
    end

    for ch in pairs(oldChildren) do
        if not newChildren[ch] then
            -- Tween out
            Animator.tween(ch, { BackgroundTransparency = 1 }, 0.15)
            task.delay(0.16, function() if ch and ch.Parent then ch:Destroy() end end)
        end
    end

    for ch in pairs(newChildren) do
        if not oldChildren[ch] then
            -- Tween in
            if ch:IsA("GuiObject") then
                ch.BackgroundTransparency = 1
                Animator.tween(ch, { BackgroundTransparency = ch:GetAttribute("OriginalTransparency") or 0 }, 0.2)
            end
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════════
-- GUI FACTORY HELPERS
-- ════════════════════════════════════════════════════════════════════════════
local function newInstance(className, props, parent)
    local inst = Instance.new(className)
    for k, v in pairs(props or {}) do
        inst[k] = v
    end
    if parent then inst.Parent = parent end
    return inst
end

local function newFrame(props, parent)
    local defaults = {
        BackgroundColor3   = Theme.Colors.Surface,
        BorderSizePixel    = 0,
    }
    for k, v in pairs(props or {}) do defaults[k] = v end
    return newInstance("Frame", defaults, parent)
end

local function newLabel(props, parent)
    local defaults = {
        BackgroundTransparency = 1,
        TextColor3             = Theme.Colors.TextPrimary,
        Font                   = Theme.Font.UI,
        TextSize               = Theme.Sizes.UiFontSize,
        TextXAlignment         = Enum.TextXAlignment.Left,
        TextWrapped            = false,
    }
    for k, v in pairs(props or {}) do defaults[k] = v end
    return newInstance("TextLabel", defaults, parent)
end

local function newButton(props, parent)
    local defaults = {
        BackgroundColor3       = Theme.Colors.AccentSoft,
        TextColor3             = Theme.Colors.TextPrimary,
        Font                   = Theme.Font.UIBold,
        TextSize               = Theme.Sizes.UiFontSize,
        BorderSizePixel        = 0,
        AutoButtonColor        = false,
    }
    for k, v in pairs(props or {}) do defaults[k] = v end
    local btn = newInstance("TextButton", defaults, parent)

    -- Hover effect
    btn.MouseEnter:Connect(function()
        Animator.tween(btn, { BackgroundColor3 = Theme.Colors.Accent }, 0.12)
    end)
    btn.MouseLeave:Connect(function()
        Animator.tween(btn, { BackgroundColor3 = Theme.Colors.AccentSoft }, 0.12)
    end)

    -- Round corners
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = btn

    return btn
end

local function addCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = radius or Theme.Sizes.Radius
    c.Parent = parent
    return c
end

local function addStroke(parent, color, thickness, trans)
    local s = Instance.new("UIStroke")
    s.Color       = color or Theme.Colors.Border
    s.Thickness   = thickness or 1
    s.Transparency= trans or 0
    s.Parent = parent
    return s
end

-- ════════════════════════════════════════════════════════════════════════════
-- IDE CONTROLLER  (main GUI builder + event wiring)
-- ════════════════════════════════════════════════════════════════════════════
local IDE = {}
IDE._source        = ""        -- current editor text
IDE._cursorLine    = 1
IDE._diagnostics   = {}
IDE._hoverTooltip  = nil
IDE._sidebarOpen   = true
IDE._previewOpen   = true
IDE._consoleOpen   = true

-- ── Build the top-level ScreenGui ────────────────────────────────────────
function IDE.build()
    -- Remove any existing instance
    local existing = PlayerGui:FindFirstChild("CultrazIDE")
    if existing then existing:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name              = "CultrazIDE"
    screenGui.ResetOnSpawn      = false
    screenGui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset    = true
    screenGui.Parent            = PlayerGui

    -- ── Root frame (full screen) ─────────────────────────────────────────
    local root = newFrame({
        Name             = "Root",
        Size             = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Colors.Background,
    }, screenGui)

    -- Subtle noise texture overlay (visual depth)
    local noise = newFrame({
        Name                   = "NoiseOverlay",
        Size                   = UDim2.fromScale(1, 1),
        BackgroundColor3       = Color3.fromRGB(255,255,255),
        BackgroundTransparency = 0.97,
    }, root)
    noise.ZIndex = 100  -- on top of everything (thin, barely visible)

    IDE._buildToolbar(root)
    IDE._buildMain(root)
    IDE._buildStatusBar(root)
    IDE._buildTooltip(screenGui)

    -- Initial content
    IDE.setSource([[-- Welcome to Cultraz LuaIDE
-- Start typing Lua code below!
-- Hover over standard functions to see docs.

local function greet(name)
    print("Hello, " .. name .. "!")
end

greet("World")
]])

    Console.writeInfo("Cultraz LuaIDE v1.0.0 — Ready.")
    Console.writeInfo("Tip: Click any error's line number to jump there.")
end

-- ── Toolbar ──────────────────────────────────────────────────────────────
function IDE._buildToolbar(root)
    local bar = newFrame({
        Name             = "Toolbar",
        Size             = UDim2.new(1, 0, 0, Theme.Sizes.ToolbarHeight),
        Position         = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Theme.Colors.SurfaceHigh,
    }, root)
    addStroke(bar, Theme.Colors.Border, 1)

    -- Logo
    newLabel({
        Name     = "Logo",
        Size     = UDim2.new(0, 140, 1, 0),
        Text     = "⬡ CULTRAZ",
        Font     = Theme.Font.UIBold,
        TextSize = 15,
        TextColor3 = Theme.Colors.AccentGlow,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, bar)

    -- Button row
    local btnRow = newFrame({
        Name             = "BtnRow",
        Size             = UDim2.new(1, -150, 1, 0),
        Position         = UDim2.fromOffset(145, 0),
        BackgroundTransparency = 1,
    }, bar)

    local layout = Instance.new("UIListLayout")
    layout.FillDirection  = Enum.FillDirection.Horizontal
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding        = UDim.new(0, 6)
    layout.Parent         = btnRow

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 6)
    pad.Parent = btnRow

    -- Run button
    local runBtn = newButton({
        Name     = "RunBtn",
        Size     = UDim2.new(0, 72, 0, 26),
        Text     = "▶  Run",
        TextSize = 13,
        BackgroundColor3 = Theme.Colors.SuccessGreen,
        TextColor3       = Theme.Colors.TextOnAccent,
    }, btnRow)
    runBtn.MouseButton1Click:Connect(function() IDE._runCode() end)
    -- override hover for green
    runBtn.MouseEnter:Connect(function()
        Animator.tween(runBtn, { BackgroundColor3 = Color3.fromRGB(50,200,120) }, 0.12)
    end)
    runBtn.MouseLeave:Connect(function()
        Animator.tween(runBtn, { BackgroundColor3 = Theme.Colors.SuccessGreen }, 0.12)
    end)

    -- Clear console
    local clearBtn = newButton({
        Name     = "ClearBtn",
        Size     = UDim2.new(0, 80, 0, 26),
        Text     = "🗑  Clear",
        TextSize = 13,
    }, btnRow)
    clearBtn.MouseButton1Click:Connect(function() Console.clear() end)

    -- Toggle sidebar
    local sideBtn = newButton({
        Name     = "SideBtn",
        Size     = UDim2.new(0, 90, 0, 26),
        Text     = "⬅ Sidebar",
        TextSize = 13,
    }, btnRow)
    sideBtn.MouseButton1Click:Connect(function() IDE._toggleSidebar() end)

    -- Toggle preview
    local preBtn = newButton({
        Name     = "PreviewBtn",
        Size     = UDim2.new(0, 90, 0, 26),
        Text     = "👁 Preview",
        TextSize = 13,
    }, btnRow)
    preBtn.MouseButton1Click:Connect(function() IDE._togglePreview() end)

    -- Toggle console
    local conBtn = newButton({
        Name     = "ConsoleBtn",
        Size     = UDim2.new(0, 90, 0, 26),
        Text     = "⌨ Console",
        TextSize = 13,
    }, btnRow)
    conBtn.MouseButton1Click:Connect(function() IDE._toggleConsole() end)

    IDE._toolbar = bar
end

-- ── Main area (sidebar + editor + preview) ────────────────────────────────
function IDE._buildMain(root)
    local tbH  = Theme.Sizes.ToolbarHeight
    local sbH  = Theme.Sizes.StatusBarHeight
    local conH = Theme.Sizes.ConsoleHeight

    local mainArea = newFrame({
        Name     = "MainArea",
        Size     = UDim2.new(1, 0, 1, -(tbH + sbH + conH)),
        Position = UDim2.fromOffset(0, tbH),
        BackgroundTransparency = 1,
    }, root)
    IDE._mainArea = mainArea

    IDE._buildSidebar(mainArea)
    IDE._buildEditorArea(mainArea)
    IDE._buildPreviewPane(mainArea)
    IDE._buildConsole(root, tbH, sbH, conH)
end

-- ── Sidebar (file tree placeholder + dictionary search) ───────────────────
function IDE._buildSidebar(parent)
    local sw = Theme.Sizes.SidebarWidth

    local sidebar = newFrame({
        Name             = "Sidebar",
        Size             = UDim2.new(0, sw, 1, 0),
        BackgroundColor3 = Theme.Colors.SurfaceHigh,
    }, parent)
    addStroke(sidebar, Theme.Colors.Border)
    IDE._sidebar = sidebar

    -- Title
    newLabel({
        Name           = "Title",
        Size           = UDim2.new(1, 0, 0, 28),
        Text           = " 📁 Explorer",
        Font           = Theme.Font.UIBold,
        TextSize       = 13,
        TextColor3     = Theme.Colors.TextSecondary,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, sidebar)

    -- File list (placeholder entries)
    local fileList = newFrame({
        Name                   = "FileList",
        Size                   = UDim2.new(1, 0, 0, 200),
        Position               = UDim2.fromOffset(0, 32),
        BackgroundTransparency = 1,
    }, sidebar)

    local fl = Instance.new("UIListLayout")
    fl.Padding = UDim.new(0, 2)
    fl.Parent  = fileList

    local files = { "main.lua", "config.lua", "utils.lua", "ui.lua" }
    for i, fname in ipairs(files) do
        local ent = newButton({
            Name             = fname,
            Size             = UDim2.new(1, -8, 0, 26),
            Text             = "  📄 " .. fname,
            TextSize         = 12,
            TextXAlignment   = Enum.TextXAlignment.Left,
            BackgroundColor3 = (i == 1) and Theme.Colors.Glass or Theme.Colors.SurfaceHigh,
            TextColor3       = (i == 1) and Theme.Colors.Accent or Theme.Colors.TextSecondary,
        }, fileList)
        addCorner(ent, UDim.new(0, 4))
    end

    -- Dictionary search section
    newLabel({
        Name           = "DictTitle",
        Size           = UDim2.new(1, 0, 0, 28),
        Position       = UDim2.fromOffset(0, 248),
        Text           = " 📖 Lua Reference",
        Font           = Theme.Font.UIBold,
        TextSize       = 13,
        TextColor3     = Theme.Colors.TextSecondary,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, sidebar)

    local searchBox = Instance.new("TextBox")
    searchBox.Name             = "DictSearch"
    searchBox.Size             = UDim2.new(1, -10, 0, 26)
    searchBox.Position         = UDim2.new(0, 5, 0, 280)
    searchBox.BackgroundColor3 = Theme.Colors.Glass
    searchBox.TextColor3       = Theme.Colors.TextPrimary
    searchBox.PlaceholderText  = "Search (e.g. table.insert)"
    searchBox.PlaceholderColor3= Theme.Colors.TextMuted
    searchBox.Font             = Theme.Font.Mono
    searchBox.TextSize         = 11
    searchBox.BorderSizePixel  = 0
    searchBox.ClearTextOnFocus = false
    addCorner(searchBox, UDim.new(0, 5))
    addStroke(searchBox, Theme.Colors.Border)
    searchBox.Parent = sidebar

    -- Dict result area
    local dictResult = newLabel({
        Name           = "DictResult",
        Size           = UDim2.new(1, -10, 0, 200),
        Position       = UDim2.new(0, 5, 0, 312),
        BackgroundColor3   = Theme.Colors.Glass,
        BackgroundTransparency = 0,
        Text               = "",
        TextColor3         = Theme.Colors.TextPrimary,
        TextSize           = 11,
        Font               = Theme.Font.Mono,
        TextWrapped        = true,
        TextXAlignment     = Enum.TextXAlignment.Left,
        TextYAlignment     = Enum.TextYAlignment.Top,
        AutomaticSize      = Enum.AutomaticSize.Y,
    }, sidebar)
    addCorner(dictResult, UDim.new(0, 5))

    local dictPad = Instance.new("UIPadding")
    dictPad.PaddingAll = UDim.new(0, 6)
    dictPad.Parent = dictResult

    searchBox.FocusLost:Connect(function()
        local word = searchBox.Text
        local entry = Dictionary.lookup(word)
        if entry then
            dictResult.Text = Dictionary.format(entry)
            Animator.fadeIn(dictResult, 0.2)
        else
            dictResult.Text = "(No entry for '" .. word .. "')"
        end
    end)
end

-- ── Editor area (gutter + text box) ───────────────────────────────────────
function IDE._buildEditorArea(parent)
    local sw = Theme.Sizes.SidebarWidth
    local lnW= Theme.Sizes.LineNumberWidth

    local editorArea = newFrame({
        Name                   = "EditorArea",
        Size                   = UDim2.new(0.55, -sw, 1, 0),
        Position               = UDim2.fromOffset(sw, 0),
        BackgroundColor3       = Theme.Colors.Surface,
        BackgroundTransparency = 0,
    }, parent)
    IDE._editorArea = editorArea

    -- Line number gutter
    local gutter = newFrame({
        Name             = "Gutter",
        Size             = UDim2.new(0, lnW, 1, 0),
        BackgroundColor3 = Theme.Colors.SurfaceHigh,
    }, editorArea)
    addStroke(gutter, Theme.Colors.Border)
    IDE._gutter = gutter

    -- Scrolling frame for gutter numbers
    local gutterScroll = Instance.new("ScrollingFrame")
    gutterScroll.Name                  = "GutterScroll"
    gutterScroll.Size                  = UDim2.fromScale(1, 1)
    gutterScroll.BackgroundTransparency= 1
    gutterScroll.BorderSizePixel       = 0
    gutterScroll.ScrollBarThickness    = 0
    gutterScroll.CanvasSize            = UDim2.fromScale(0, 0)
    gutterScroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
    gutterScroll.Parent                = gutter
    IDE._gutterScroll = gutterScroll

    local gutterLayout = Instance.new("UIListLayout")
    gutterLayout.FillDirection = Enum.FillDirection.Vertical
    gutterLayout.Parent        = gutterScroll

    -- Actual code TextBox
    local codeScroll = Instance.new("ScrollingFrame")
    codeScroll.Name                  = "CodeScroll"
    codeScroll.Size                  = UDim2.new(1, -lnW, 1, 0)
    codeScroll.Position              = UDim2.fromOffset(lnW, 0)
    codeScroll.BackgroundTransparency= 1
    codeScroll.BorderSizePixel       = 0
    codeScroll.ScrollBarThickness    = 6
    codeScroll.ScrollBarImageColor3  = Theme.Colors.Border
    codeScroll.CanvasSize            = UDim2.fromScale(0, 0)
    codeScroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
    codeScroll.Parent                = editorArea
    IDE._codeScroll = codeScroll

    local codeBox = Instance.new("TextBox")
    codeBox.Name                 = "CodeBox"
    codeBox.Size                 = UDim2.new(1, -12, 1, 0)
    codeBox.Position             = UDim2.fromOffset(8, 0)
    codeBox.BackgroundTransparency= 1
    codeBox.TextColor3           = Theme.Colors.SynPlain
    codeBox.Font                 = Theme.Font.Mono
    codeBox.TextSize             = Theme.Sizes.EditorFontSize
    codeBox.TextXAlignment       = Enum.TextXAlignment.Left
    codeBox.TextYAlignment       = Enum.TextYAlignment.Top
    codeBox.MultiLine            = true
    codeBox.ClearTextOnFocus     = false
    codeBox.BorderSizePixel      = 0
    codeBox.AutomaticSize        = Enum.AutomaticSize.Y
    codeBox.Text                 = ""
    codeBox.Parent               = codeScroll
    IDE._codeBox = codeBox

    -- Sync gutter scroll with code scroll
    codeScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        gutterScroll.CanvasPosition = Vector2.new(
            0, codeScroll.CanvasPosition.Y
        )
    end)

    -- Text change handler (debounced linting + preview)
    codeBox:GetPropertyChangedSignal("Text"):Connect(function()
        IDE._source = codeBox.Text
        IDE._onTextChanged()
    end)

    -- Hover tooltip (dictionary)
    codeBox.MouseMoved:Connect(function(x, y)
        -- This is approximate; full word-under-cursor detection
        -- would require cursor position from TextService
        -- (kept simple here for Roblox API compatibility)
    end)

    IDE._gutterLayout  = gutterLayout
    IDE._gutterScrollF = gutterScroll
end

-- ── Preview pane ──────────────────────────────────────────────────────────
function IDE._buildPreviewPane(parent)
    local previewPane = newFrame({
        Name             = "PreviewPane",
        Size             = UDim2.new(0.45, 0, 1, 0),
        Position         = UDim2.new(0.55, 0, 0, 0),
        BackgroundColor3 = Theme.Colors.Background,
    }, parent)
    addStroke(previewPane, Theme.Colors.Border)
    IDE._previewPane = previewPane

    -- Header bar
    local header = newFrame({
        Name             = "Header",
        Size             = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = Theme.Colors.SurfaceHigh,
    }, previewPane)

    newLabel({
        Size           = UDim2.new(1, 0, 1, 0),
        Text           = "  👁  Live Preview",
        Font           = Theme.Font.UIBold,
        TextSize       = 12,
        TextColor3     = Theme.Colors.TextSecondary,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)

    -- Canvas area for rendering
    local canvas = newFrame({
        Name             = "Canvas",
        Size             = UDim2.new(1, -8, 1, -36),
        Position         = UDim2.new(0, 4, 0, 32),
        BackgroundColor3 = Theme.Colors.Glass,
        ClipsDescendants = true,
    }, previewPane)
    addCorner(canvas, UDim.new(0, 8))
    addStroke(canvas, Theme.Colors.BorderBright, 1)

    -- Placeholder hint
    newLabel({
        Name           = "Hint",
        Size           = UDim2.fromScale(1, 1),
        Text           = "UI code output appears here in real-time.\n\nExample:\n  local f = Instance.new('Frame', Preview)\n  f.Size = UDim2.fromScale(0.5, 0.5)\n  f.BackgroundColor3 = Color3.fromRGB(80,140,255)",
        Font           = Theme.Font.UILight,
        TextSize       = 12,
        TextColor3     = Theme.Colors.TextMuted,
        TextWrapped    = true,
        TextXAlignment = Enum.TextXAlignment.Center,
    }, canvas)

    CanvasPreview.setRoot(canvas)
end

-- ── Console ───────────────────────────────────────────────────────────────
function IDE._buildConsole(root, tbH, sbH, conH)
    local consolePanel = newFrame({
        Name             = "ConsolePanel",
        Size             = UDim2.new(1, 0, 0, conH),
        Position         = UDim2.new(0, 0, 1, -(sbH + conH)),
        BackgroundColor3 = Theme.Colors.SurfaceHigh,
    }, root)
    addStroke(consolePanel, Theme.Colors.Border)
    IDE._consolePanel = consolePanel

    -- Header
    local header = newFrame({
        Name             = "Header",
        Size             = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = Theme.Colors.Glass,
    }, consolePanel)

    newLabel({
        Size           = UDim2.new(1, 0, 1, 0),
        Text           = "  ⌨  Console Output",
        Font           = Theme.Font.UIBold,
        TextSize       = 12,
        TextColor3     = Theme.Colors.TextSecondary,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)

    -- Scrolling output area
    local scrollF = Instance.new("ScrollingFrame")
    scrollF.Name                  = "OutputScroll"
    scrollF.Size                  = UDim2.new(1, -4, 1, -30)
    scrollF.Position              = UDim2.fromOffset(2, 28)
    scrollF.BackgroundTransparency= 1
    scrollF.BorderSizePixel       = 0
    scrollF.ScrollBarThickness    = 5
    scrollF.ScrollBarImageColor3  = Theme.Colors.AccentSoft
    scrollF.CanvasSize            = UDim2.fromScale(0, 0)
    scrollF.AutomaticCanvasSize   = Enum.AutomaticSize.Y
    scrollF.Parent                = consolePanel

    local container = newFrame({
        Name                   = "Container",
        Size                   = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }, scrollF)

    local listLayout = Instance.new("UIListLayout")
    listLayout.FillDirection = Enum.FillDirection.Vertical
    listLayout.Padding       = UDim.new(0, 1)
    listLayout.Parent        = container

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft   = UDim.new(0, 6)
    pad.PaddingRight  = UDim.new(0, 6)
    pad.PaddingTop    = UDim.new(0, 4)
    pad.Parent        = container

    Console.setFrame(consolePanel, scrollF, container)
    Console.setOnJump(function(lineNum)
        IDE._jumpToLine(lineNum)
    end)
end

-- ── Status bar ────────────────────────────────────────────────────────────
function IDE._buildStatusBar(root)
    local bar = newFrame({
        Name             = "StatusBar",
        Size             = UDim2.new(1, 0, 0, Theme.Sizes.StatusBarHeight),
        Position         = UDim2.new(0, 0, 1, -Theme.Sizes.StatusBarHeight),
        BackgroundColor3 = Theme.Colors.AccentSoft,
    }, root)

    local statusLabel = newLabel({
        Name           = "StatusLabel",
        Size           = UDim2.fromScale(1, 1),
        Text           = "  ✓ Ready — Cultraz LuaIDE v1.0.0",
        Font           = Theme.Font.UI,
        TextSize       = 11,
        TextColor3     = Theme.Colors.TextPrimary,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, bar)

    IDE._statusLabel = statusLabel
end

-- ── Tooltip (hover documentation) ─────────────────────────────────────────
function IDE._buildTooltip(screenGui)
    local tip = newFrame({
        Name                   = "Tooltip",
        Size                   = UDim2.new(0, 320, 0, 20),
        BackgroundColor3       = Theme.Colors.SurfaceHigh,
        BackgroundTransparency = 0.05,
        Visible                = false,
        ZIndex                 = 200,
    }, screenGui)
    addCorner(tip, UDim.new(0, 8))
    addStroke(tip, Theme.Colors.BorderBright, 1)

    local pad = Instance.new("UIPadding")
    pad.PaddingAll = UDim.new(0, 8)
    pad.Parent = tip

    local tipLabel = newLabel({
        Size           = UDim2.fromScale(1, 1),
        AutomaticSize  = Enum.AutomaticSize.Y,
        TextWrapped    = true,
        TextSize       = 11,
        Font           = Theme.Font.Mono,
        TextColor3     = Theme.Colors.TextPrimary,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex         = 201,
    }, tip)

    IDE._hoverTooltip     = tip
    IDE._hoverTooltipLabel= tipLabel
end

-- ── Gutter line numbers ───────────────────────────────────────────────────
function IDE._updateGutter(lineCount, diagnosticLines)
    local container = IDE._gutterScrollF
    if not container then return end

    -- Clear old
    for _, ch in ipairs(container:GetChildren()) do
        if ch:IsA("TextLabel") then ch:Destroy() end
    end

    for ln = 1, lineCount do
        local hasDiag = diagnosticLines[ln]
        local lbl = newLabel({
            Size           = UDim2.new(1, 0, 0, Theme.Sizes.EditorFontSize + 4),
            Text           = (hasDiag and "● " or "  ") .. tostring(ln),
            TextSize       = 11,
            Font           = Theme.Font.Mono,
            TextColor3     = hasDiag and Theme.Colors.ErrorRed or Theme.Colors.TextMuted,
            TextXAlignment = Enum.TextXAlignment.Right,
        }, container)
    end
end

-- ── Text-change handler ───────────────────────────────────────────────────
do
    local _lintDebounce = nil
    function IDE._onTextChanged()
        -- Cancel pending lint
        if _lintDebounce then
            _lintDebounce:Disconnect()
            _lintDebounce = nil
        end

        -- Count lines and update gutter immediately
        local lines = 0
        for _ in (IDE._source .. "\n"):gmatch("[^\n]*\n") do lines = lines + 1 end
        IDE._updateGutter(lines, {})

        -- Update status
        if IDE._statusLabel then
            IDE._statusLabel.Text = string.format(
                "  Ln %d  |  %d chars  |  Editing…",
                lines, #IDE._source
            )
        end

        -- Schedule preview render
        CanvasPreview.scheduleRender(IDE._source)

        -- Debounce lint (400 ms)
        _lintDebounce = task.delay(0.4, function()
            local diags = Linter.check(IDE._source)
            IDE._diagnostics = diags

            local diagLines = {}
            for _, d in ipairs(diags) do
                diagLines[d.line] = d
            end

            IDE._updateGutter(lines, diagLines)

            -- Refresh status
            if #diags > 0 then
                if IDE._statusLabel then
                    IDE._statusLabel.Text = string.format(
                        "  ⚠ %d issue%s  |  Ln %d  |  %d chars",
                        #diags, #diags > 1 and "s" or "", lines, #IDE._source
                    )
                end
            else
                if IDE._statusLabel then
                    IDE._statusLabel.Text = string.format(
                        "  ✓ No issues  |  Ln %d  |  %d chars",
                        lines, #IDE._source
                    )
                end
            end
        end)
    end
end

-- ── Set source text programmatically ─────────────────────────────────────
function IDE.setSource(src)
    IDE._source = src
    if IDE._codeBox then
        IDE._codeBox.Text = src
    end
end

-- ── Run code in the console output ───────────────────────────────────────
function IDE._runCode()
    Console.clear()
    Console.writeInfo("─── Run: " .. os.date and os.date("%H:%M:%S") or "..." .. " ───")

    -- Intercept print
    local oldPrint = print
    local captured = {}
    local fakePrint = function(...)
        local parts = {}
        for i = 1, select("#",...) do
            parts[#parts+1] = tostring(select(i,...))
        end
        local line = table.concat(parts, "\t")
        Console.writeLine(line)
    end

    -- Compile
    local fn, compErr = load(IDE._source, "editor", "t", {
        print   = fakePrint,
        warn    = function(...) Console.writeWarn(table.concat({...}," ")) end,
        math    = math, table = table, string = string,
        pairs   = pairs, ipairs = ipairs, type = type,
        tostring= tostring, tonumber = tonumber,
        pcall   = pcall, xpcall = xpcall, select = select,
        unpack  = table.unpack, next = next,
        coroutine = coroutine,
        task    = task,
        -- Roblox-safe subset
        game    = game, workspace = workspace,
        Instance= Instance, Vector3 = Vector3, Vector2 = Vector2,
        CFrame  = CFrame, Color3 = Color3, UDim2 = UDim2, UDim = UDim,
        Enum    = Enum, TweenInfo = TweenInfo, BrickColor = BrickColor,
        tick    = tick, time = time,
    })

    if not fn then
        Console.writeError("Compile error: " .. tostring(compErr))
        return
    end

    local ok, runErr = pcall(fn)
    if not ok then
        Console.writeError(tostring(runErr))
    else
        Console.writeSuccess("✓ Finished successfully.")
    end
end

-- ── Jump editor to a specific line ────────────────────────────────────────
function IDE._jumpToLine(lineNum)
    if not IDE._codeScroll then return end
    -- Approximate scroll: each line is EditorFontSize+4 pixels
    local lineH = Theme.Sizes.EditorFontSize + 4
    local targetY = (lineNum - 1) * lineH
    IDE._codeScroll.CanvasPosition = Vector2.new(0, math.max(0, targetY - 40))
    Console.writeInfo("Jumped to line " .. lineNum)
end

-- ── Toggle sidebar ────────────────────────────────────────────────────────
function IDE._toggleSidebar()
    if not IDE._sidebar or not IDE._editorArea then return end
    local sw = Theme.Sizes.SidebarWidth
    IDE._sidebarOpen = not IDE._sidebarOpen

    if IDE._sidebarOpen then
        Animator.tween(IDE._sidebar,    { Size = UDim2.new(0, sw, 1, 0) }, 0.3)
        Animator.tween(IDE._editorArea, {
            Size     = UDim2.new(0.55, -sw, 1, 0),
            Position = UDim2.fromOffset(sw, 0),
        }, 0.3)
    else
        Animator.tween(IDE._sidebar,    { Size = UDim2.new(0, 0, 1, 0) }, 0.3)
        Animator.tween(IDE._editorArea, {
            Size     = UDim2.new(0.55, 0, 1, 0),
            Position = UDim2.fromOffset(0, 0),
        }, 0.3)
    end
end

-- ── Toggle preview ────────────────────────────────────────────────────────
function IDE._togglePreview()
    if not IDE._previewPane then return end
    IDE._previewOpen = not IDE._previewOpen
    if IDE._previewOpen then
        IDE._previewPane.Visible = true
        Animator.tween(IDE._previewPane,  { BackgroundTransparency = 0 }, 0.25)
        Animator.tween(IDE._editorArea,   { Size = UDim2.new(0.55, -Theme.Sizes.SidebarWidth, 1, 0) }, 0.3)
    else
        Animator.tween(IDE._previewPane,  { BackgroundTransparency = 1 }, 0.2)
        task.delay(0.21, function() IDE._previewPane.Visible = false end)
        Animator.tween(IDE._editorArea,   { Size = UDim2.new(1, -Theme.Sizes.SidebarWidth, 1, 0) }, 0.3)
    end
end

-- ── Toggle console ────────────────────────────────────────────────────────
function IDE._toggleConsole()
    if not IDE._consolePanel or not IDE._mainArea then return end
    local sbH  = Theme.Sizes.StatusBarHeight
    local conH = Theme.Sizes.ConsoleHeight
    local tbH  = Theme.Sizes.ToolbarHeight
    IDE._consoleOpen = not IDE._consoleOpen

    if IDE._consoleOpen then
        Animator.tween(IDE._consolePanel, { Size = UDim2.new(1, 0, 0, conH) }, 0.3)
        Animator.tween(IDE._mainArea,     { Size = UDim2.new(1, 0, 1, -(tbH + sbH + conH)) }, 0.3)
    else
        Animator.tween(IDE._consolePanel, { Size = UDim2.new(1, 0, 0, 0) }, 0.25)
        Animator.tween(IDE._mainArea,     { Size = UDim2.new(1, 0, 1, -(tbH + sbH)) }, 0.25)
    end
end

-- ════════════════════════════════════════════════════════════════════════════
-- ENTRY POINT
-- ════════════════════════════════════════════════════════════════════════════
IDE.build()

--[[
  ════════════════════════════════════════════════════════════════════════════
  END OF CultrazIDE.lua
  ════════════════════════════════════════════════════════════════════════════

  INSTALLATION GUIDE:
  ───────────────────
  1. In Roblox Studio, open the Explorer panel.
  2. Navigate to StarterPlayer > StarterPlayerScripts.
  3. Insert a new LocalScript and name it "CultrazIDE".
  4. Paste all of this code into the LocalScript.
  5. Press Play to launch the IDE in-experience.

  CUSTOMIZATION QUICK-REFERENCE:
  ───────────────────────────────
  • Change colour scheme   → edit Theme.Colors at the top.
  • Add syntax colours     → extend Lexer.KEYWORDS / Lexer.GLOBALS.
  • Add hover docs         → add entries to Dictionary.entries (schema above).
  • Change debounce speed  → CanvasPreview.DEBOUNCE_MS (default 300 ms).
  • Allow more preview types → add class names to SANDBOX_WHITELIST.
  • Resize panes           → adjust Theme.Sizes constants.
  • Extend the linter      → add rules in Linter.check() Pass 2 section.
]]
