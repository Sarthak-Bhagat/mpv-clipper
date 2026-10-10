-- Lint config. Run: luacheck .
--
-- mpv embeds LuaJIT, so that is the standard library a script actually has.
-- `mp` is injected as a global by mpv's defaults.lua even though this script
-- takes it through require(), so it is declared read-only rather than left to
-- be reported as undefined in whatever gets added here next.
std = "luajit"
read_globals = {"mp"}

-- The source is wrapped at 88 columns by hand; holding the linter to the same
-- number is what stops that drifting one long line at a time.
max_line_length = 88
