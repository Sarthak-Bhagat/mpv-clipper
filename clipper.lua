-- clipper.lua — B marks the clip start, B again marks the end and encodes
-- an mp4 (with audio) and a gif of the range, current subtitle track burned in.
--
-- Output dir: script-opts/clipper.conf  ->  outdir=~/Videos/clips
-- Rebind in input.conf with:  KEY script-binding clipper/clip

local mp = require "mp"
local msg = require "mp.msg"
local utils = require "mp.utils"
local options = require "mp.options"

local opts = {
    outdir = "",   -- empty: ask xdg-user-dirs, see default_outdir()
    mp4 = true,
    gif = true,
}
options.read_options(opts, "clipper")

-- The XDG *Base Directory* spec covers config/data/cache/state -- application
-- files, not output someone will go looking for. Where user-facing media lands
-- is xdg-user-dirs' business, so ask it rather than hardcoding "~/Videos",
-- which is simply the wrong folder on a system whose is named "Vidéos".
-- Uses VIDEOS because the mp4 is the primary artifact; PICTURES would be the
-- better home if this ever goes gif-only.
local function default_outdir()
    local r = utils.subprocess({args = {"xdg-user-dir", "VIDEOS"},
                                cancellable = false})
    local dir = (r.status == 0 and r.stdout or ""):gsub("%s+$", "")
    if dir == "" then dir = "~/Videos" end
    return utils.join_path(dir, "clips")
end

local GIF_VF = "fps=15,scale=600:-1:flags=lanczos,split[a][b];" ..
    "[a]palettegen=stats_mode=diff[p];" ..
    "[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle"

local start_pos = nil

local function osd(text, secs)
    msg.info(text)
    mp.osd_message("clipper: " .. text, secs or 3)
end

local function hms(t)
    local h, m, s = math.floor(t / 3600), math.floor(t % 3600 / 60), t % 60
    if h > 0 then return string.format("%d:%02d:%04.1f", h, m, s) end
    return string.format("%d:%04.1f", m, s)
end

-- "Show Name (2026) [..] - S01E12 - ..." -> "showname-s01e12-10.32"
local function clip_name(t)
    local base = (mp.get_property("filename/no-ext") or "clip"):gsub("^%[.-%]%s*", "")
    -- title is everything before the first "(year)", "[tag]", " - " or SxxEyy
    local cut = #base + 1
    for _, pat in ipairs({"%s*[%(%[]", "%s+%-%s", "[Ss]%d+[Ee]%d+"}) do
        local i = base:find(pat)
        if i and i < cut then cut = i end
    end
    local title = base:sub(1, cut - 1):lower():gsub("[^%w]", "")
    if title == "" then title = "clip" end
    local se = base:match("[Ss]%d+[Ee]%d+")
    local h, m, s = math.floor(t / 3600), math.floor(t % 3600 / 60), math.floor(t % 60)
    local stamp = h > 0 and string.format("%d.%02d.%02d", h, m, s)
                         or string.format("%d.%02d", m, s)
    return title .. (se and ("-" .. se:lower()) or "") .. "-" .. stamp
end

-- a name is taken if any output this run would write already exists, so turning
-- mp4 off cannot start silently overwriting gifs
local function unused_path(dir, name)
    local path, n = utils.join_path(dir, name), 2
    local function taken(p)
        return (opts.mp4 and utils.file_info(p .. ".mp4"))
            or (opts.gif and utils.file_info(p .. ".gif"))
    end
    while taken(path) do
        path = utils.join_path(dir, name .. "-" .. n)
        n = n + 1
    end
    return path
end

-- run argv lists one after another; stop and report on the first failure
local function chain(steps, done)
    local i = 0
    local function nxt()
        i = i + 1
        local step = steps[i]
        if not step then return done() end
        mp.command_native_async({
            name = "subprocess", args = step.args, playback_only = false,
            capture_stdout = true, capture_stderr = true,
        }, function(ok, res)
            if step.may_fail or (ok and res.status == 0) then return nxt() end
            msg.error(step.what .. " failed: " .. tostring(res and res.stderr))
            osd(step.what .. " failed — see console (`)", 6)
        end)
    end
    nxt()
end

local function clip(a, b)
    if not (opts.mp4 or opts.gif) then
        return osd("mp4 and gif are both off — nothing to encode", 4)
    end
    local src = mp.get_property("path")
    if not src or src:match("^%a[%w+.-]*://") then
        return osd("not a local file")
    end
    src = utils.join_path(mp.get_property("working-directory", ""), src)
    local dur = string.format("%.3f", b - a)
    local ss = string.format("%.3f", a)

    local outdir = mp.command_native({"expand-path",
        opts.outdir ~= "" and opts.outdir or default_outdir()})
    utils.subprocess({args = {"mkdir", "-p", outdir}, cancellable = false})
    local out = unused_path(outdir, clip_name(a))

    local tmp = utils.subprocess({args = {"mktemp", "-d", "/tmp/mpv-clipper.XXXXXX"},
                                  cancellable = false}).stdout:gsub("%s+$", "")
    local steps, subs = {}, nil

    -- the subtitles filter can only draw text subs; image subs (PGS) are skipped
    local track = mp.get_property_native("current-tracks/sub")
    local visible = mp.get_property_bool("sub-visibility")
    if track and visible and not track["image"] then
        local sub_src = track["external-filename"] or src
        local ext = track["codec"] == "ass" and "ass" or "srt"
        local subfile = tmp .. "/subs." .. ext
        local map = track["external"] and "0:s:0" or ("0:" .. track["ff-index"])
        steps[#steps + 1] = {what = "subtitle extract", args = {"ffmpeg",
            "-hide_banner", "-loglevel", "error", "-i", sub_src, "-map", map,
            "-c:s", ext == "ass" and "copy" or "srt", "-y", subfile}}
        -- ffmpeg exits non-zero after dumping ("no output file"), hence may_fail
        steps[#steps + 1] = {what = "font dump", may_fail = true, args = {"sh", "-c",
            'mkdir -p "$1/fonts" && cd "$1/fonts" && ' ..
            'ffmpeg -hide_banner -loglevel quiet -dump_attachment:t "" -i "$2"',
            "sh", tmp, src}}
        subs = "subtitles=" .. subfile .. ":fontsdir=" .. tmp .. "/fonts,"
    elseif track and track["image"] then
        osd("image subtitles can't be burned — clipping without", 4)
    end
    subs = subs or ""

    -- -copyts/-start_at_zero keep the file's own clock so the burned subs
    -- stay in sync; -ss and -t both before -i, or palettegen reads to EOF
    local function cut(extra)
        local args = {"ffmpeg", "-hide_banner", "-loglevel", "error", "-copyts",
            "-ss", ss, "-t", dur, "-i", src, "-start_at_zero"}
        for _, v in ipairs(extra) do args[#args + 1] = v end
        return args
    end
    local made = {}
    if opts.mp4 then
        made[#made + 1] = ".mp4"
        steps[#steps + 1] = {what = "mp4 encode", args = cut({
            "-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libx264", "-preset", "slow",
            "-crf", "18", "-pix_fmt", "yuv420p", "-vf", subs .. "scale=1280:-2",
            "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-y", out .. ".mp4"})}
    end
    if opts.gif then
        made[#made + 1] = ".gif"
        steps[#steps + 1] = {what = "gif encode", args = cut({
            "-map", "0:v:0", "-an", "-vf", subs .. GIF_VF, "-loop", "0", "-y", out .. ".gif"})}
    end

    osd(string.format("encoding %s → %s (%ss)…", hms(a), hms(b), dur), 30)
    chain(steps, function()
        utils.subprocess({args = {"rm", "-rf", tmp}, cancellable = false})
        osd("saved " .. out .. " " .. table.concat(made, " / "), 5)
    end)
end

mp.add_key_binding("B", "clip", function()
    local now = mp.get_property_number("time-pos")
    if not now then return end
    if not start_pos then
        start_pos = now
        return osd("start " .. hms(now) .. " — B again to end", 3)
    end
    local a, b = math.min(start_pos, now), math.max(start_pos, now)
    start_pos = nil
    if b - a < 0.1 then return osd("too short, mark cleared") end
    clip(a, b)
end)
