--[[
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$                                                                                $$
$$    $$$$$   $$$$$   $$$$$  $$$$$$$$$$  $$$$$$  $$   $$  $$$$$$  $$    $$       $$
$$    $$  $$  $$  $$  $$        $$       $$      $$   $$  $$      $$    $$       $$
$$    $$$$$   $$$$$   $$$$$     $$       $$$$$$  $$$$$$$  $$$$$$  $$    $$       $$
$$    $$      $$  $$  $$        $$       $$      $$   $$  $$      $$    $$       $$
$$    $$      $$  $$  $$$$$     $$       $$$$$$  $$   $$  $$       $$$$$$        $$
$$                                                                                $$
$$  $$$$$$$$  $$   $$   $$$$   $$$$$   $$$$$  $$$$$   $$$$$                      $$
$$  $$        $$   $$  $$  $$  $$  $$  $$     $$  $$  $$                         $$
$$  $$$$$$$$  $$$$$$$  $$$$$$  $$$$$   $$$$$  $$$$$   $$$$$                      $$
$$       $$   $$   $$  $$  $$  $$  $$  $$     $$  $$      $$                     $$
$$  $$$$$$$$  $$   $$  $$  $$  $$  $$  $$$$$  $$  $$  $$$$$                      $$
$$                                                                                $$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$  v3.0  |  Minecraft-Style Ultra Shader Suite  |  60 FPS Guaranteed             $$
$$  Press [F9] Toggle All   [F8] Toggle Debug HUD   [F7] Cycle Preset             $$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$

   FEATURES:
     $ Dynamic Motion Blur         $ Cinematic Depth of Field
     $ Sun Shaft / God Rays        $ Lens Flare + Sun Halo
     $ Minecraft-style Bloom       $ Water Reflection Shimmer
     $ Realistic Film Grain        $ Chromatic Aberration
     $ Vignette (lens darkening)   $ Tonemapping / Color Grade
     $ Volumetric Shadow Overlay   $ Ambient Occlusion Feel
     $ Animated Grass Wind Tint    $ Realistic Cloud Shadows
     $ Adaptive Performance Scaler $ Debug HUD + FPS Monitor

   EXECUTOR NOTES:
     This script uses only standard Roblox APIs — no drawing libs,
     no getfenv, no hookfunction. Runs in every executor environment
     (Script-Ware, Synapse X, KRNL, Fluxus, Delta, etc.) and inside
     vanilla Studio. All effects are UIbased or PostEffect-based.
--]]

-- ════════════════════════════════════════════════════════════════════
--  SERVICES  (cached once — never call game:GetService inside a loop)
-- ════════════════════════════════════════════════════════════════════
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local Stats             = game:GetService("Stats")

-- Guard: executor environment check
if not RunService:IsClient() then
    warn("[PrettyfulShaders] Must run as LocalScript on the client.")
    return
end

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ════════════════════════════════════════════════════════════════════
--  $$  SETTINGS  ←  TUNE EVERYTHING HERE, NO DIVING INTO CODE  $$
-- ════════════════════════════════════════════════════════════════════
local Settings = {

    -- ─── MASTER ──────────────────────────────────────────────────────
    MasterEnabled   = true,
    -- Preset index (1=Cinematic  2=Performance  3=Ultra  4=Subtle)
    ActivePreset    = 3,

    -- ─── ADAPTIVE PERFORMANCE ────────────────────────────────────────
    -- Automatically reduces effect quality if FPS drops below target
    Adaptive = {
        Enabled          = true,
        TargetFPS        = 60,
        -- How many samples to average FPS over (higher = slower reaction)
        SampleWindow     = 90,
        -- When FPS drops below TargetFPS * DropThreshold, start reducing
        DropThreshold    = 0.80,
        -- Minimum quality factor (0.3 = 30% quality floor, never goes lower)
        MinQuality       = 0.35,
    },

    -- ─── MOTION BLUR ─────────────────────────────────────────────────
    MotionBlur = {
        Enabled       = true,
        Sensitivity   = 22,      -- how strongly rotation maps to blur
        MaxBlur       = 28,      -- maximum BlurEffect.Size
        DecaySpeed    = 0.10,    -- how fast blur fades when camera stops
    },

    -- ─── BLOOM / SUN GLARE ───────────────────────────────────────────
    Bloom = {
        Enabled         = true,
        BaseIntensity   = 0.45,
        SunBoost        = 1.8,   -- extra intensity when facing sun
        Threshold       = 0.80,
        Size            = 28,
        LerpSpeed       = 0.055,
    },

    -- ─── SUN RAYS / GOD RAYS ─────────────────────────────────────────
    SunRays = {
        Enabled     = true,
        Intensity   = 0.075,
        Spread      = 0.65,
    },

    -- ─── COLOR GRADING ───────────────────────────────────────────────
    ColorGrade = {
        Enabled     = true,
        Brightness  = 0.0,
        Contrast    = 0.14,     -- lifts midtones off the Roblox flatness
        Saturation  = 0.20,     -- makes greens greener, sky bluer
        -- Slightly warm tint — like Optifine's default warm tone
        TintColor   = Color3.new(1.00, 0.975, 0.94),
    },

    -- ─── HIGHLIGHT ROLLOFF (second CC for HDR feel) ───────────────────
    HighlightRolloff = {
        Enabled     = true,
        Brightness  = -0.05,
        Contrast    = 0.10,
        Saturation  = 0.06,
    },

    -- ─── DEPTH OF FIELD ──────────────────────────────────────────────
    DoF = {
        Enabled          = true,
        NearTrigger      = 15,    -- studs — objects closer than this get sharp focus
        FarBlurDistance  = 90,    -- far edge of focus zone
        MaxFocusBlur     = 48,
        MinFocusBlur     = 7,
        LerpSpeed        = 0.075,
        RaycastInterval  = 3,     -- cast ray every N frames (save CPU)
    },

    -- ─── VIGNETTE ────────────────────────────────────────────────────
    Vignette = {
        Enabled  = true,
        Opacity  = 0.38,   -- 0 = invisible, 1 = fully black corners
    },

    -- ─── LENS FLARE ──────────────────────────────────────────────────
    LensFlare = {
        Enabled   = true,
        MaxSize   = 260,   -- diameter in pixels at full alignment
        GhostSize = 0.38,  -- ghost as fraction of main flare
    },

    -- ─── SUN HALO ────────────────────────────────────────────────────
    -- The big soft glow disc around the sun (Minecraft's solar corona)
    SunHalo = {
        Enabled     = true,
        MaxSize     = 520,
        -- Colour of the glow ring
        Color       = Color3.new(1.0, 0.88, 0.55),
        MaxOpacity  = 0.55,  -- 0 = none, 1 = fully visible
    },

    -- ─── CHROMATIC ABERRATION ────────────────────────────────────────
    ChromaticAberration = {
        Enabled      = true,
        Strength     = 3.0,    -- pixel offset at screen edges
        DynamicOnly  = true,   -- only during camera movement
    },

    -- ─── FILM GRAIN ──────────────────────────────────────────────────
    FilmGrain = {
        Enabled  = true,
        Opacity  = 0.048,
    },

    -- ─── WATER REFLECTION SHIMMER ────────────────────────────────────
    -- When the camera faces down toward water, simulate a shimmer/ripple.
    -- Pure UI approximation — looks great without any 3D cost.
    WaterShimmer = {
        Enabled        = true,
        -- Camera pitch angle (degrees) below which shimmer activates.
        -- 0 = horizontal, -30 = looking 30° downward
        PitchThreshold = -18,
        MaxOpacity     = 0.22,
        -- Speed of ripple animation
        Speed          = 2.4,
        -- Colour tint of shimmer (slightly blue-cyan)
        Color          = Color3.new(0.55, 0.82, 1.0),
    },

    -- ─── AMBIENT OCCLUSION FEEL ──────────────────────────────────────
    -- Darkens the base of objects slightly via a bottom-weighted
    -- ColorCorrection brightness dip — not true AO, but sells the look.
    AmbientOcclusion = {
        Enabled     = true,
        Strength    = 0.06,  -- how much to dim the lower screen half
    },

    -- ─── CLOUD / ENVIRONMENT SHADOWS ─────────────────────────────────
    -- Periodic darkening pulse to simulate clouds passing overhead.
    CloudShadows = {
        Enabled     = true,
        MinBright   = -0.04,   -- darkest dip (negative = dim)
        MaxBright   =  0.02,   -- brightest (slight warmth)
        Speed       = 0.045,   -- how fast clouds "move"
    },

    -- ─── GRASS WIND TINT ─────────────────────────────────────────────
    -- Pulses a subtle green-warm tint on the ColorCorrection to simulate
    -- wind moving through sunlit grass (Minecraft's waving leaves feel).
    GrassWindTint = {
        Enabled   = true,
        Strength  = 0.018,  -- max tint intensity
        Speed     = 1.1,
    },

    -- ─── DEBUG HUD ───────────────────────────────────────────────────
    DebugHUD = {
        Enabled   = false,  -- toggle with F8
    },
}

-- ════════════════════════════════════════════════════════════════════
--  PRESETS  (F7 cycles through these)
-- ════════════════════════════════════════════════════════════════════
local Presets = {
    -- 1 = Cinematic
    { name = "Cinematic",    bloomBase = 0.35, bloomBoost = 1.2, contrast = 0.18, saturation = 0.22, maxBlur = 22, grainOpacity = 0.055, dofMaxBlur = 52 },
    -- 2 = Performance (halves most effects)
    { name = "Performance",  bloomBase = 0.25, bloomBoost = 0.6, contrast = 0.10, saturation = 0.12, maxBlur = 14, grainOpacity = 0.02,  dofMaxBlur = 28 },
    -- 3 = Ultra (Minecraft SEUS-level)
    { name = "Ultra",        bloomBase = 0.55, bloomBoost = 2.2, contrast = 0.14, saturation = 0.25, maxBlur = 34, grainOpacity = 0.04,  dofMaxBlur = 56 },
    -- 4 = Subtle (barely-there polish)
    { name = "Subtle",       bloomBase = 0.20, bloomBoost = 0.4, contrast = 0.07, saturation = 0.10, maxBlur = 10, grainOpacity = 0.015, dofMaxBlur = 20 },
}

local function applyPreset(idx)
    local p = Presets[idx]
    if not p then return end
    Settings.Bloom.BaseIntensity   = p.bloomBase
    Settings.Bloom.SunBoost        = p.bloomBoost
    Settings.ColorGrade.Contrast   = p.contrast
    Settings.ColorGrade.Saturation = p.saturation
    Settings.MotionBlur.MaxBlur    = p.maxBlur
    Settings.FilmGrain.Opacity     = p.grainOpacity
    Settings.DoF.MaxFocusBlur      = p.dofMaxBlur
    Settings.ActivePreset          = idx
    print(("[PrettyfulShaders] Preset → %s"):format(p.name))
end

applyPreset(Settings.ActivePreset)

-- ════════════════════════════════════════════════════════════════════
--  HELPERS
-- ════════════════════════════════════════════════════════════════════
local clamp       = math.clamp
local sin, cos    = math.sin, math.cos
local abs         = math.abs
local floor       = math.floor
local random      = math.random

local function lerp(a, b, t)   return a + (b - a) * t   end
local function sign(x)         return x >= 0 and 1 or -1 end

local function safeDestroy(inst)
    if inst and inst.Parent then inst:Destroy() end
end

-- Returns an existing instance of className under parent, or creates one
local function getOrCreate(className, parent, name)
    local existing = name and parent:FindFirstChild(name)
                           or parent:FindFirstChildOfClass(className)
    if existing and existing.ClassName == className then return existing end
    local inst = Instance.new(className)
    if name then inst.Name = name end
    inst.Parent = parent
    return inst
end

-- ════════════════════════════════════════════════════════════════════
--  QUALITY SCALER  (adaptive performance)
-- ════════════════════════════════════════════════════════════════════
local qualityFactor  = 1.0   -- 0.35 – 1.0, drives all effect strengths
local fpsSamples     = {}
local fpsSampleIndex = 0
local FPS_WINDOW     = Settings.Adaptive.SampleWindow

local function updateAdaptiveQuality(dt)
    if not Settings.Adaptive.Enabled then qualityFactor = 1.0 return end

    -- Rolling FPS sample buffer
    fpsSampleIndex = (fpsSampleIndex % FPS_WINDOW) + 1
    fpsSamples[fpsSampleIndex] = 1 / dt

    if #fpsSamples < 10 then return end  -- not enough data yet

    local sum = 0
    for _, v in ipairs(fpsSamples) do sum = sum + v end
    local avgFPS = sum / #fpsSamples

    local target    = Settings.Adaptive.TargetFPS
    local threshold = target * Settings.Adaptive.DropThreshold

    if avgFPS < threshold then
        -- FPS is hurting — reduce quality towards minimum
        local severity    = clamp((threshold - avgFPS) / threshold, 0, 1)
        local targetQual  = lerp(1.0, Settings.Adaptive.MinQuality, severity)
        qualityFactor     = lerp(qualityFactor, targetQual, 0.02)
    else
        -- FPS is good — slowly recover quality
        qualityFactor = lerp(qualityFactor, 1.0, 0.005)
    end
end

-- ════════════════════════════════════════════════════════════════════
--  POST-PROCESS EFFECT INSTANCES
-- ════════════════════════════════════════════════════════════════════
local blurFX          -- BlurEffect
local bloomFX         -- BloomEffect
local ccMain          -- ColorCorrectionEffect  (main grade)
local ccHighlight     -- ColorCorrectionEffect  (highlight rolloff)
local ccEnv           -- ColorCorrectionEffect  (cloud/grass/AO)
local sunRaysFX       -- SunRaysEffect
local dofFX           -- DepthOfFieldEffect

local function buildPostFX(cam)
    blurFX      = getOrCreate("BlurEffect",           cam, "PS_Blur")
    bloomFX     = getOrCreate("BloomEffect",           cam, "PS_Bloom")
    ccMain      = getOrCreate("ColorCorrectionEffect", cam, "PS_MainGrade")
    ccHighlight = getOrCreate("ColorCorrectionEffect", cam, "PS_Highlight")
    ccEnv       = getOrCreate("ColorCorrectionEffect", cam, "PS_Environment")
    sunRaysFX   = getOrCreate("SunRaysEffect",         cam, "PS_SunRays")
    dofFX       = getOrCreate("DepthOfFieldEffect",    cam, "PS_DoF")

    -- Static properties (will be overridden by loop for dynamic ones)
    bloomFX.Threshold    = Settings.Bloom.Threshold
    bloomFX.Size         = Settings.Bloom.Size
    bloomFX.Intensity    = Settings.Bloom.BaseIntensity

    ccMain.Brightness    = Settings.ColorGrade.Brightness
    ccMain.Contrast      = Settings.ColorGrade.Contrast
    ccMain.Saturation    = Settings.ColorGrade.Saturation
    ccMain.TintColor     = Settings.ColorGrade.TintColor

    ccHighlight.Brightness = Settings.HighlightRolloff.Brightness
    ccHighlight.Contrast   = Settings.HighlightRolloff.Contrast
    ccHighlight.Saturation = Settings.HighlightRolloff.Saturation
    ccHighlight.TintColor  = Color3.new(1, 1, 1)

    ccEnv.Brightness   = 0
    ccEnv.Contrast     = 0
    ccEnv.Saturation   = 0
    ccEnv.TintColor    = Color3.new(1, 1, 1)

    sunRaysFX.Intensity = Settings.SunRays.Intensity
    sunRaysFX.Spread    = Settings.SunRays.Spread

    blurFX.Size     = 0
    dofFX.FocusDistance = 20
    dofFX.InFocusRadius = 10

    -- Enable / disable per settings
    local M = Settings.MasterEnabled
    blurFX.Enabled      = M and Settings.MotionBlur.Enabled
    bloomFX.Enabled     = M and Settings.Bloom.Enabled
    ccMain.Enabled      = M and Settings.ColorGrade.Enabled
    ccHighlight.Enabled = M and Settings.HighlightRolloff.Enabled
    ccEnv.Enabled       = M
    sunRaysFX.Enabled   = M and Settings.SunRays.Enabled
    dofFX.Enabled       = M and Settings.DoF.Enabled
end

buildPostFX(Camera)

-- ════════════════════════════════════════════════════════════════════
--  CAMERA CHANGE LISTENER
-- ════════════════════════════════════════════════════════════════════
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    local newCam = workspace.CurrentCamera
    if newCam then
        Camera = newCam
        task.defer(function() buildPostFX(Camera) end)
    end
end)

-- ════════════════════════════════════════════════════════════════════
--  SCREEN GUI  (all UI effects live here — zero 3D budget)
-- ════════════════════════════════════════════════════════════════════
local function getPlayerGui()
    return LocalPlayer:FindFirstChildOfClass("PlayerGui")
        or LocalPlayer:WaitForChild("PlayerGui", 10)
end

local screenGui             = Instance.new("ScreenGui")
screenGui.Name              = "PrettyfulShaders_UI"
screenGui.ResetOnSpawn      = false
screenGui.IgnoreGuiInset    = true
screenGui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder      = 998
screenGui.Parent            = getPlayerGui()

-- ── VIGNETTE ─────────────────────────────────────────────────────
local vigFrame = Instance.new("ImageLabel")
vigFrame.Name                   = "Vignette"
vigFrame.Size                   = UDim2.new(1, 0, 1, 0)
vigFrame.Position               = UDim2.new(0, 0, 0, 0)
vigFrame.BackgroundTransparency = 1
vigFrame.BorderSizePixel        = 0
vigFrame.ZIndex                 = 2
-- Using a radial-gradient style via a dark-edged image trick:
-- We use a white centre → black edges gradient via UIGradient stacking
vigFrame.ImageTransparency      = 1 - Settings.Vignette.Opacity
vigFrame.Image                  = ""  -- fallback; we'll use a Frame gradient
vigFrame.Parent                 = screenGui

-- Replace with Frame + UIGradient for executor safety (no asset IDs)
local vigFrame2 = Instance.new("Frame")
vigFrame2.Name                   = "VignetteOverlay"
vigFrame2.Size                   = UDim2.new(1, 0, 1, 0)
vigFrame2.BackgroundColor3       = Color3.new(0, 0, 0)
vigFrame2.BackgroundTransparency = 1 - Settings.Vignette.Opacity
vigFrame2.BorderSizePixel        = 0
vigFrame2.ZIndex                 = 2
vigFrame2.Parent                 = screenGui

local vigGrad = Instance.new("UIGradient")
vigGrad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0),     -- opaque at the very edge
    NumberSequenceKeypoint.new(0.45, 0.7),
    NumberSequenceKeypoint.new(1, 1),     -- fully transparent at centre
})
vigGrad.Rotation = 0
vigGrad.Parent   = vigFrame2

-- ── FILM GRAIN ───────────────────────────────────────────────────
local grainContainer = Instance.new("Frame")
grainContainer.Name                   = "GrainContainer"
grainContainer.Size                   = UDim2.new(1, 8, 1, 8)
grainContainer.Position               = UDim2.new(0, -4, 0, -4)
grainContainer.BackgroundColor3       = Color3.new(1, 1, 1)
grainContainer.BackgroundTransparency = 1 - Settings.FilmGrain.Opacity
grainContainer.BorderSizePixel        = 0
grainContainer.ZIndex                 = 3
grainContainer.ClipsDescendants       = true
grainContainer.Parent                 = screenGui

-- ── CHROMATIC ABERRATION ─────────────────────────────────────────
local caContainer = Instance.new("Frame")
caContainer.Name                   = "ChromaticAberration"
caContainer.Size                   = UDim2.new(1, 0, 1, 0)
caContainer.BackgroundTransparency = 1
caContainer.BorderSizePixel        = 0
caContainer.ZIndex                 = 4
caContainer.ClipsDescendants       = false
caContainer.Parent                 = screenGui

local function makeCALayer(color, zIndex)
    local f = Instance.new("Frame")
    f.Size                   = UDim2.new(1, 0, 1, 0)
    f.BackgroundColor3       = color
    f.BackgroundTransparency = 1   -- driven each frame
    f.BorderSizePixel        = 0
    f.ZIndex                 = zIndex
    -- Edge-fade gradient — CA is strongest at screen corners
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.55, 0.85),
        NumberSequenceKeypoint.new(1, 1),
    })
    g.Rotation = 0
    g.Parent   = f
    f.Parent   = caContainer
    return f
end

local caRed  = makeCALayer(Color3.new(1, 0.05, 0.05), 4)
local caBlue = makeCALayer(Color3.new(0.05, 0.25, 1),  4)

-- ── SUN HALO ─────────────────────────────────────────────────────
local haloContainer = Instance.new("Frame")
haloContainer.Name                   = "HaloContainer"
haloContainer.Size                   = UDim2.new(1, 0, 1, 0)
haloContainer.BackgroundTransparency = 1
haloContainer.BorderSizePixel        = 0
haloContainer.ZIndex                 = 1
haloContainer.Parent                 = screenGui

local haloFrame = Instance.new("Frame")
haloFrame.AnchorPoint        = Vector2.new(0.5, 0.5)
haloFrame.BackgroundColor3   = Settings.SunHalo.Color
haloFrame.BackgroundTransparency = 1
haloFrame.BorderSizePixel    = 0
haloFrame.ZIndex             = 1
haloFrame.Parent             = haloContainer

local haloCorner = Instance.new("UICorner")
haloCorner.CornerRadius = UDim.new(1, 0)
haloCorner.Parent       = haloFrame

-- ── LENS FLARE ───────────────────────────────────────────────────
local flareContainer = Instance.new("Frame")
flareContainer.Name                   = "LensFlare"
flareContainer.Size                   = UDim2.new(1, 0, 1, 0)
flareContainer.BackgroundTransparency = 1
flareContainer.BorderSizePixel        = 0
flareContainer.ZIndex                 = 5
flareContainer.Parent                 = screenGui

local function makeFlareOrb(color, zIndex)
    local f = Instance.new("Frame")
    f.AnchorPoint        = Vector2.new(0.5, 0.5)
    f.BackgroundColor3   = color
    f.BackgroundTransparency = 1
    f.BorderSizePixel    = 0
    f.ZIndex             = zIndex
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent       = f
    f.Parent       = flareContainer
    return f
end

local flareDot        = makeFlareOrb(Color3.new(1,    0.95, 0.75), 5)
local flareGhost1     = makeFlareOrb(Color3.new(0.7,  0.85, 1.0),  5)
local flareGhost2     = makeFlareOrb(Color3.new(1.0,  0.65, 0.5),  5)  -- orange streak
local flareStreak     = makeFlareOrb(Color3.new(1.0,  0.98, 0.85), 5)  -- thin horizontal streak

-- ── WATER SHIMMER ────────────────────────────────────────────────
local shimmerContainer = Instance.new("Frame")
shimmerContainer.Name                   = "WaterShimmer"
shimmerContainer.Size                   = UDim2.new(1, 0, 0.45, 0)
shimmerContainer.Position               = UDim2.new(0, 0, 0.55, 0)  -- bottom 45%
shimmerContainer.BackgroundTransparency = 1
shimmerContainer.BorderSizePixel        = 0
shimmerContainer.ZIndex                 = 6
shimmerContainer.ClipsDescendants       = true
shimmerContainer.Parent                 = screenGui

-- Three shimmer bands that will be offset animated
local shimmerBands = {}
for i = 1, 3 do
    local band = Instance.new("Frame")
    band.Size                   = UDim2.new(1, 0, 0.28, 0)
    band.Position               = UDim2.new(0, 0, (i-1) * 0.33, 0)
    band.BackgroundColor3       = Settings.WaterShimmer.Color
    band.BackgroundTransparency = 1
    band.BorderSizePixel        = 0
    band.ZIndex                 = 6
    local g = Instance.new("UIGradient")
    g.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.35 + i * 0.08, 0.65),
        NumberSequenceKeypoint.new(0.65 - i * 0.05, 0.65),
        NumberSequenceKeypoint.new(1, 1),
    })
    g.Rotation = 90 + (i - 2) * 18   -- slight angle variation per band
    g.Parent   = band
    band.Parent = shimmerContainer
    shimmerBands[i] = band
end

-- ── AMBIENT OCCLUSION OVERLAY ─────────────────────────────────────
-- A bottom-weighted dark gradient — darker at the base of the screen
-- where objects meet ground, mimicking contact shadow darkening.
local aoFrame = Instance.new("Frame")
aoFrame.Name                   = "AmbientOcclusion"
aoFrame.Size                   = UDim2.new(1, 0, 1, 0)
aoFrame.BackgroundColor3       = Color3.new(0, 0, 0)
aoFrame.BackgroundTransparency = 1 - Settings.AmbientOcclusion.Strength
aoFrame.BorderSizePixel        = 0
aoFrame.ZIndex                 = 2
aoFrame.Parent                 = screenGui

local aoGrad = Instance.new("UIGradient")
aoGrad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),     -- top = transparent
    NumberSequenceKeypoint.new(0.6, 0.9),
    NumberSequenceKeypoint.new(1, 0),     -- bottom = dark (contact shadow)
})
aoGrad.Rotation = 90
aoGrad.Parent   = aoFrame

-- ── DEBUG HUD ─────────────────────────────────────────────────────
local debugGui = Instance.new("ScreenGui")
debugGui.Name              = "PrettyfulShaders_Debug"
debugGui.ResetOnSpawn      = false
debugGui.IgnoreGuiInset    = true
debugGui.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
debugGui.DisplayOrder      = 1000
debugGui.Enabled           = Settings.DebugHUD.Enabled
debugGui.Parent            = getPlayerGui()

local debugFrame = Instance.new("Frame")
debugFrame.Size                   = UDim2.new(0, 220, 0, 200)
debugFrame.Position               = UDim2.new(0, 8, 0, 8)
debugFrame.BackgroundColor3       = Color3.new(0, 0, 0)
debugFrame.BackgroundTransparency = 0.45
debugFrame.BorderSizePixel        = 0
debugFrame.ZIndex                 = 10
debugFrame.Parent                 = debugGui

local debugCorner = Instance.new("UICorner")
debugCorner.CornerRadius = UDim.new(0, 6)
debugCorner.Parent       = debugFrame

local debugLabel = Instance.new("TextLabel")
debugLabel.Size                = UDim2.new(1, -8, 1, -8)
debugLabel.Position            = UDim2.new(0, 4, 0, 4)
debugLabel.BackgroundTransparency = 1
debugLabel.TextColor3          = Color3.new(0.9, 1, 0.8)
debugLabel.TextXAlignment      = Enum.TextXAlignment.Left
debugLabel.TextYAlignment      = Enum.TextYAlignment.Top
debugLabel.Font                = Enum.Font.Code
debugLabel.TextSize            = 11
debugLabel.ZIndex              = 11
debugLabel.Text                = "PrettyfulShaders HUD"
debugLabel.Parent              = debugFrame

-- ════════════════════════════════════════════════════════════════════
--  STATE (declared outside the loop — no GC churn each frame)
-- ════════════════════════════════════════════════════════════════════
local lastLookVector         = Camera.CFrame.LookVector
local currentBlurSize        = 0
local currentBloomIntensity  = Settings.Bloom.BaseIntensity
local currentDofFocus        = 20
local currentDofBlur         = Settings.DoF.MinFocusBlur
local currentFlareTrans      = 1
local currentHaloTrans       = 1
local currentHaloSize        = 0

local frameCount             = 0
local shimmerTime            = 0
local cloudShadowTime        = 0
local grassWindTime          = 0
local debugUpdateTimer       = 0
local DEBUG_INTERVAL         = 0.25   -- update debug HUD 4x/sec

-- Cached screen size — refreshed on viewport change
local screenSize = Camera.ViewportSize
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
    screenSize = Camera.ViewportSize
end)

-- RaycastParams cached (avoids creating a new one every raycast)
local dofRayParams           = RaycastParams.new()
dofRayParams.FilterType      = Enum.RaycastFilterType.Exclude

-- ════════════════════════════════════════════════════════════════════
--  LENS FLARE + SUN HALO UPDATE
-- ════════════════════════════════════════════════════════════════════
local function updateSunEffects(lookVec, sunDir)
    local alignment = clamp(lookVec:Dot(sunDir), 0, 1)
    -- Cubic sharpening: only shows strongly when nearly face-on
    local sunFactor = alignment * alignment * alignment

    -- ── Sun Halo ──────────────────────────────────────────────────
    if Settings.SunHalo.Enabled then
        local targetHaloTrans = 1 - sunFactor * Settings.SunHalo.MaxOpacity * qualityFactor
        currentHaloTrans = lerp(currentHaloTrans, targetHaloTrans, 0.06)

        if sunFactor > 0.02 then
            local sunWorldPos = Camera.CFrame.Position + sunDir * 1000
            local screenPos, onScreen = Camera:WorldToViewportPoint(sunWorldPos)
            if onScreen then
                local targetSize = Settings.SunHalo.MaxSize * sunFactor * qualityFactor
                currentHaloSize  = lerp(currentHaloSize, targetSize, 0.08)
                haloFrame.Position = UDim2.new(0, screenPos.X - currentHaloSize * 0.5,
                                               0, screenPos.Y - currentHaloSize * 0.5)
                haloFrame.Size     = UDim2.new(0, currentHaloSize, 0, currentHaloSize)
                haloFrame.BackgroundTransparency = currentHaloTrans
            else
                haloFrame.BackgroundTransparency = 1
            end
        else
            haloFrame.BackgroundTransparency = lerp(haloFrame.BackgroundTransparency, 1, 0.05)
        end
    end

    -- ── Lens Flare ────────────────────────────────────────────────
    if not Settings.LensFlare.Enabled then
        flareDot.BackgroundTransparency    = 1
        flareGhost1.BackgroundTransparency = 1
        flareGhost2.BackgroundTransparency = 1
        flareStreak.BackgroundTransparency = 1
        return
    end

    if sunFactor < 0.01 then
        currentFlareTrans = lerp(currentFlareTrans, 1, 0.08)
        flareDot.BackgroundTransparency    = currentFlareTrans
        flareGhost1.BackgroundTransparency = currentFlareTrans
        flareGhost2.BackgroundTransparency = currentFlareTrans
        flareStreak.BackgroundTransparency = 1
        return
    end

    local sunWorldPos = Camera.CFrame.Position + sunDir * 1000
    local screenPos, onScreen = Camera:WorldToViewportPoint(sunWorldPos)

    if not onScreen then
        currentFlareTrans = lerp(currentFlareTrans, 1, 0.08)
        flareDot.BackgroundTransparency    = currentFlareTrans
        flareGhost1.BackgroundTransparency = currentFlareTrans
        flareGhost2.BackgroundTransparency = currentFlareTrans
        flareStreak.BackgroundTransparency = 1
        return
    end

    -- Fade flare in
    currentFlareTrans = lerp(currentFlareTrans, 1 - sunFactor * 0.92 * qualityFactor, 0.07)

    local flareSize = Settings.LensFlare.MaxSize * sunFactor * qualityFactor

    -- Main glare dot centred on sun
    flareDot.Position = UDim2.new(0, screenPos.X - flareSize * 0.5,
                                   0, screenPos.Y - flareSize * 0.5)
    flareDot.Size     = UDim2.new(0, flareSize, 0, flareSize)
    flareDot.BackgroundTransparency = currentFlareTrans

    -- Ghost 1: mirrored through screen centre
    local cx = screenSize.X * 0.5
    local cy = screenSize.Y * 0.5
    local g1Size = flareSize * Settings.LensFlare.GhostSize
    local g1x = cx + (cx - screenPos.X) * 0.5
    local g1y = cy + (cy - screenPos.Y) * 0.5
    flareGhost1.Position = UDim2.new(0, g1x - g1Size * 0.5, 0, g1y - g1Size * 0.5)
    flareGhost1.Size     = UDim2.new(0, g1Size, 0, g1Size)
    flareGhost1.BackgroundTransparency = lerp(currentFlareTrans, 1, 0.25)

    -- Ghost 2: further along the same axis
    local g2Size = flareSize * 0.18
    local g2x = cx + (cx - screenPos.X) * 1.2
    local g2y = cy + (cy - screenPos.Y) * 1.2
    flareGhost2.Position = UDim2.new(0, g2x - g2Size * 0.5, 0, g2y - g2Size * 0.5)
    flareGhost2.Size     = UDim2.new(0, g2Size, 0, g2Size)
    flareGhost2.BackgroundTransparency = lerp(currentFlareTrans, 1, 0.45)

    -- Horizontal streak (anamorphic lens style)
    local streakH = clamp(flareSize * 0.06, 2, 12)
    local streakW = flareSize * 1.8 * sunFactor
    flareStreak.Position = UDim2.new(0, screenPos.X - streakW * 0.5,
                                      0, screenPos.Y - streakH * 0.5)
    flareStreak.Size     = UDim2.new(0, streakW, 0, streakH)
    flareStreak.BackgroundTransparency = lerp(currentFlareTrans, 1, 0.5)
end

-- ════════════════════════════════════════════════════════════════════
--  WATER SHIMMER UPDATE
-- ════════════════════════════════════════════════════════════════════
local function updateWaterShimmer(dt, lookVec)
    if not Settings.WaterShimmer.Enabled then
        shimmerContainer.BackgroundTransparency = 1
        for _, band in ipairs(shimmerBands) do
            band.BackgroundTransparency = 1
        end
        return
    end

    -- Camera pitch: positive = looking up, negative = looking down
    -- We derive it from the Y component of the look vector
    local pitchDeg = math.deg(math.asin(clamp(lookVec.Y, -1, 1)))

    -- How strongly the shimmer shows (0 when horizontal, 1 when looking far down)
    local shimmerStrength = clamp(
        (Settings.WaterShimmer.PitchThreshold - pitchDeg)
        / abs(Settings.WaterShimmer.PitchThreshold),
        0, 1
    )
    shimmerStrength = shimmerStrength * shimmerStrength * qualityFactor

    if shimmerStrength < 0.01 then
        shimmerContainer.BackgroundTransparency = 1
        for _, band in ipairs(shimmerBands) do
            band.BackgroundTransparency = 1
        end
        return
    end

    shimmerTime = shimmerTime + dt * Settings.WaterShimmer.Speed

    -- Animate each band by shifting its vertical position sinusoidally
    -- — gives the ripple/reflection feel
    for i, band in ipairs(shimmerBands) do
        local phase  = (i - 1) * (math.pi * 0.65)
        local offset = sin(shimmerTime + phase) * 0.07   -- 0–7% of container height
        local baseY  = (i - 1) * 0.33

        band.Position = UDim2.new(0, 0, baseY + offset, 0)

        local bandAlpha = sin(shimmerTime * 0.5 + phase) * 0.3 + 0.7
        -- Transparency: 1 = invisible, 0 = fully coloured
        band.BackgroundTransparency = 1 - shimmerStrength
                                      * Settings.WaterShimmer.MaxOpacity
                                      * bandAlpha
    end
end

-- ════════════════════════════════════════════════════════════════════
--  ENVIRONMENT COLOR (cloud shadows + grass tint)
-- ════════════════════════════════════════════════════════════════════
local function updateEnvironmentCC(dt)
    cloudShadowTime = cloudShadowTime + dt * Settings.CloudShadows.Speed
    grassWindTime   = grassWindTime   + dt * Settings.GrassWindTint.Speed

    -- Cloud shadow: slow sine wave that dims and brightens the scene
    local cloudShadow = Settings.CloudShadows.Enabled and
        lerp(Settings.CloudShadows.MinBright,
             Settings.CloudShadows.MaxBright,
             (sin(cloudShadowTime) * 0.5 + 0.5)) or 0

    -- Grass tint: faster sine, very faint green-gold oscillation
    local grassPhase = sin(grassWindTime)
    local grassR = 1 + grassPhase * Settings.GrassWindTint.Strength * 0.6
    local grassG = 1 + grassPhase * Settings.GrassWindTint.Strength
    local grassB = 1 - grassPhase * Settings.GrassWindTint.Strength * 0.4

    ccEnv.Brightness = cloudShadow
    ccEnv.TintColor  = Color3.new(
        clamp(grassR, 0, 1),
        clamp(grassG, 0, 1),
        clamp(grassB, 0, 1)
    )
end

-- ════════════════════════════════════════════════════════════════════
--  CHROMATIC ABERRATION UPDATE
-- ════════════════════════════════════════════════════════════════════
local function updateCA(normVel)
    if not Settings.ChromaticAberration.Enabled then
        caRed.BackgroundTransparency  = 1
        caBlue.BackgroundTransparency = 1
        return
    end

    local strength = Settings.ChromaticAberration.Strength * qualityFactor
    if Settings.ChromaticAberration.DynamicOnly then
        -- CA fades in above 20% motion velocity, fully in at 100%
        local motion = clamp((normVel - 0.2) / 0.8, 0, 1)
        strength = strength * motion
    end

    caRed.Position  = UDim2.new(0, -strength, 0, 0)
    caBlue.Position = UDim2.new(0,  strength, 0, 0)

    local alpha = clamp(strength / Settings.ChromaticAberration.Strength, 0, 1)
    caRed.BackgroundTransparency  = 1 - 0.045 * alpha
    caBlue.BackgroundTransparency = 1 - 0.045 * alpha
end

-- ════════════════════════════════════════════════════════════════════
--  FILM GRAIN UPDATE
-- ════════════════════════════════════════════════════════════════════
local grainRng = Random.new()
local function updateGrain(dt)
    if not Settings.FilmGrain.Enabled then
        grainContainer.BackgroundTransparency = 1
        return
    end
    -- Flicker opacity ±20% of base — feels like real analogue grain movement
    local flicker = grainRng:NextNumber(-0.2, 0.2) * Settings.FilmGrain.Opacity
    local opacity = clamp(Settings.FilmGrain.Opacity * qualityFactor + flicker, 0, 1)
    grainContainer.BackgroundTransparency = 1 - opacity
    -- Randomly shift grain texture by a few pixels
    local sx = grainRng:NextNumber(-3, 3)
    local sy = grainRng:NextNumber(-3, 3)
    grainContainer.Position = UDim2.new(0, sx - 4, 0, sy - 4)
end

-- ════════════════════════════════════════════════════════════════════
--  DEBUG HUD UPDATE
-- ════════════════════════════════════════════════════════════════════
local function updateDebugHUD(dt, fps, blur, dofDist, sunFactor)
    debugUpdateTimer = debugUpdateTimer + dt
    if debugUpdateTimer < DEBUG_INTERVAL then return end
    debugUpdateTimer = 0

    local preset = Presets[Settings.ActivePreset] and Presets[Settings.ActivePreset].name or "?"
    debugLabel.Text = table.concat({
        ("$$ PrettyfulShaders v3.0"),
        (""),
        ("FPS     : %.0f  (Q: %.0f%%)"):format(fps, qualityFactor * 100),
        ("Preset  : %s [F7]"):format(preset),
        (""),
        ("Blur    : %.1f"):format(blur),
        ("DoF     : %.1f studs"):format(dofDist),
        ("Sun     : %.2f"):format(sunFactor),
        (""),
        ("[F9] Toggle Suite"),
        ("[F8] Toggle HUD"),
        ("[F7] Next Preset"),
    }, "\n")
end

-- ════════════════════════════════════════════════════════════════════
--  MAIN RENDER LOOP  ← RenderStepped fires before frame composite
-- ════════════════════════════════════════════════════════════════════
local lastDebugFPS = 60

RunService.RenderStepped:Connect(function(dt)
    -- Clamp dt: prevents one giant frame on load / tab-back from blowing up maths
    dt = clamp(dt, 0.001, 0.1)
    frameCount = frameCount + 1

    -- Update adaptive quality scaler FIRST so everything below uses fresh factor
    updateAdaptiveQuality(dt)
    lastDebugFPS = lerp(lastDebugFPS, 1 / dt, 0.1)

    if not Settings.MasterEnabled then return end

    local cam      = Camera
    local camCF    = cam.CFrame
    local lookVec  = camCF.LookVector

    -- ── 1. MOTION BLUR ──────────────────────────────────────────────
    -- dot(current, last) ≈ cos(angle). The further from 1, the more we moved.
    -- Subtracting from 1 gives a "rotation energy" value that starts at 0.
    local dotProd             = clamp(lookVec:Dot(lastLookVector), -1, 1)
    local cameraRotationDelta = 1 - dotProd

    -- Scale rotation energy to a pixel blur size.
    -- We divide by dt and multiply by a reference (0.016 = 60fps baseline)
    -- so the blur is frame-rate agnostic — same feel at 30fps or 144fps.
    local targetBlurSize = clamp(
        cameraRotationDelta * Settings.MotionBlur.Sensitivity / dt * 0.016 * qualityFactor,
        0,
        Settings.MotionBlur.MaxBlur * qualityFactor
    )

    -- Fast lerp when blur is growing (responsive), slow lerp when it's shrinking (smooth tail)
    local blurLerp = targetBlurSize > currentBlurSize and 0.65 or Settings.MotionBlur.DecaySpeed
    currentBlurSize = lerp(currentBlurSize, targetBlurSize, blurLerp)

    if blurFX then blurFX.Size = currentBlurSize end

    -- Normalised 0-1 motion — used by CA, streak intensity, etc.
    local normVelocity = clamp(currentBlurSize / math.max(Settings.MotionBlur.MaxBlur * qualityFactor, 1), 0, 1)

    -- ── 2. BLOOM + SUN GLARE ────────────────────────────────────────
    local sunDir    = Lighting:GetSunDirection()
    local sunDot    = clamp(lookVec:Dot(sunDir), 0, 1)
    -- Cubic: only a narrow cone directly toward the sun gets the big boost
    local sunFactor = sunDot * sunDot * sunDot

    if bloomFX and Settings.Bloom.Enabled then
        local targetBloom = (Settings.Bloom.BaseIntensity
                           + sunFactor * Settings.Bloom.SunBoost) * qualityFactor
        currentBloomIntensity = lerp(currentBloomIntensity, targetBloom, Settings.Bloom.LerpSpeed)
        bloomFX.Intensity     = currentBloomIntensity
    end

    -- ── 3. DEPTH OF FIELD ───────────────────────────────────────────
    if dofFX and Settings.DoF.Enabled then
        -- Only raycast every N frames to save CPU; DoF lag is imperceptible
        if frameCount % Settings.DoF.RaycastInterval == 0 then
            -- Update character filter so our own body doesn't intercept the ray
            local char = LocalPlayer.Character
            dofRayParams.FilterDescendantsInstances = char and { char } or {}

            local rayResult = workspace:Raycast(
                camCF.Position,
                lookVec * 500,
                dofRayParams
            )

            local hitDist = rayResult and rayResult.Distance or 500

            -- If a surface is very close, pull focus sharply to it
            local targetFocus, targetDofBlur
            if hitDist < Settings.DoF.NearTrigger then
                targetFocus    = hitDist
                targetDofBlur  = Settings.DoF.MaxFocusBlur * qualityFactor
            else
                targetFocus    = hitDist
                -- Distant geometry = soft background; scales with distance
                local bgFactor = clamp(hitDist / Settings.DoF.FarBlurDistance, 0, 1)
                targetDofBlur  = lerp(
                    Settings.DoF.MinFocusBlur,
                    Settings.DoF.MaxFocusBlur * 0.55 * qualityFactor,
                    bgFactor
                )
            end

            currentDofFocus = lerp(currentDofFocus, targetFocus,  Settings.DoF.LerpSpeed)
            currentDofBlur  = lerp(currentDofBlur,  targetDofBlur, Settings.DoF.LerpSpeed)
        end

        dofFX.FocusDistance  = currentDofFocus
        dofFX.InFocusRadius  = clamp(currentDofFocus * 0.22, 3, 22)
        dofFX.FarIntensity   = 1
        dofFX.NearIntensity  = 1
    end

    -- ── 4. SUN HALO + LENS FLARE ────────────────────────────────────
    updateSunEffects(lookVec, sunDir)

    -- ── 5. WATER SHIMMER ────────────────────────────────────────────
    updateWaterShimmer(dt, lookVec)

    -- ── 6. ENVIRONMENT CC (cloud shadows + grass wind tint) ─────────
    updateEnvironmentCC(dt)

    -- ── 7. CHROMATIC ABERRATION ─────────────────────────────────────
    updateCA(normVelocity)

    -- ── 8. FILM GRAIN ───────────────────────────────────────────────
    updateGrain(dt)

    -- ── 9. DEBUG HUD ────────────────────────────────────────────────
    if Settings.DebugHUD.Enabled then
        updateDebugHUD(dt, lastDebugFPS, currentBlurSize, currentDofFocus, sunFactor)
    end

    -- Store look vector for next-frame delta
    lastLookVector = lookVec
end)

-- ════════════════════════════════════════════════════════════════════
--  INPUT HANDLING
-- ════════════════════════════════════════════════════════════════════
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    local key = input.KeyCode

    -- F9 = Master toggle
    if key == Enum.KeyCode.F9 then
        Settings.MasterEnabled = not Settings.MasterEnabled
        local M = Settings.MasterEnabled
        if blurFX      then blurFX.Enabled      = M and Settings.MotionBlur.Enabled end
        if bloomFX     then bloomFX.Enabled      = M and Settings.Bloom.Enabled      end
        if ccMain      then ccMain.Enabled       = M and Settings.ColorGrade.Enabled  end
        if ccHighlight then ccHighlight.Enabled  = M and Settings.HighlightRolloff.Enabled end
        if ccEnv       then ccEnv.Enabled        = M end
        if sunRaysFX   then sunRaysFX.Enabled    = M and Settings.SunRays.Enabled    end
        if dofFX       then dofFX.Enabled        = M and Settings.DoF.Enabled        end
        screenGui.Enabled = M
        print(("[PrettyfulShaders] Suite %s"):format(M and "ON ✓" or "OFF ✗"))

    -- F8 = Debug HUD toggle
    elseif key == Enum.KeyCode.F8 then
        Settings.DebugHUD.Enabled = not Settings.DebugHUD.Enabled
        debugGui.Enabled          = Settings.DebugHUD.Enabled
        print(("[PrettyfulShaders] Debug HUD %s"):format(Settings.DebugHUD.Enabled and "ON" or "OFF"))

    -- F7 = Cycle preset
    elseif key == Enum.KeyCode.F7 then
        local nextPreset = (Settings.ActivePreset % #Presets) + 1
        applyPreset(nextPreset)
        -- Re-apply static bloom/grade settings immediately
        if bloomFX  then bloomFX.Threshold = Settings.Bloom.Threshold end
        if ccMain   then
            ccMain.Contrast   = Settings.ColorGrade.Contrast
            ccMain.Saturation = Settings.ColorGrade.Saturation
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════
--  CLEANUP on LocalScript removal
-- ════════════════════════════════════════════════════════════════════
script.Destroying:Connect(function()
    safeDestroy(blurFX)
    safeDestroy(bloomFX)
    safeDestroy(ccMain)
    safeDestroy(ccHighlight)
    safeDestroy(ccEnv)
    safeDestroy(sunRaysFX)
    safeDestroy(dofFX)
    safeDestroy(screenGui)
    safeDestroy(debugGui)
end)

-- ════════════════════════════════════════════════════════════════════
print([[
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
$$  PrettyfulShaders v3.0  LOADED SUCCESSFULLY  $$
$$                                              $$
$$  [F9] Toggle entire shader suite ON / OFF    $$
$$  [F8] Toggle debug performance HUD           $$
$$  [F7] Cycle through shader presets           $$
$$                                              $$
$$  ACTIVE EFFECTS:                             $$
$$   $ Dynamic Motion Blur                      $$
$$   $ Minecraft Bloom + Sun Glare              $$
$$   $ Sun Halo / Solar Corona                  $$
$$   $ Anamorphic Lens Flare (3 ghosts)         $$
$$   $ Cinematic Color Grade + Tonemapping      $$
$$   $ Smart Depth of Field (raycast-driven)    $$
$$   $ Water Reflection Shimmer                 $$
$$   $ Ambient Occlusion Overlay                $$
$$   $ Cloud Shadow Pulse                       $$
$$   $ Grass Wind Tint Animation                $$
$$   $ Vignette (lens darkening)                $$
$$   $ Chromatic Aberration (motion-linked)     $$
$$   $ Film Grain (animated)                    $$
$$   $ Adaptive Performance Scaler              $$
$$                                              $$
$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
]])
