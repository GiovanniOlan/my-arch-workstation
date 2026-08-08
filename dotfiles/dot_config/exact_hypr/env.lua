hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- start-hyprland doesn't inherit .bashrc's PATH, so exec_cmd binds pointing
-- at ~/.local/bin scripts silently fail. Guarded against reload duplicates.
local local_bin = os.getenv("HOME") .. "/.local/bin"
local current_path = os.getenv("PATH") or ""
if not current_path:find(local_bin, 1, true) then
    hl.env("PATH", local_bin .. ":" .. current_path)
end

-- hl.config({
--     ecosystem = {
--         enforce_permissions = true,
--     },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")
