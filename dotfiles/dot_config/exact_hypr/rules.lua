hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

hl.window_rule({
    name     = "float-pavucontrol",
    match    = { class = "org.pulseaudio.pavucontrol" },

    float    = true,
    center   = true,
    size     = "(monitor_w*0.42) (monitor_h*0.46)",
    min_size = "1095 560",
    max_size = "800 500",
})

hl.window_rule({
    name     = "float-nmtui",
    match    = { class = "nmtui" },

    float    = true,
    center   = true,
    size     = "(monitor_w*0.31) (monitor_h*0.37)",
    min_size = "1095 560",
    max_size = "600 400",
})

hl.window_rule({
    name     = "float-calendar",
    match    = { class = "calendar" },

    float    = true,
    center   = true,
    size     = "(monitor_w*0.47) (monitor_h*0.46)",
    min_size = "1095 560",
    max_size = "900 500",
})

hl.window_rule({
    name     = "float-overskride",
    match    = { class = "io.github.kaii_lb.Overskride" },

    float    = true,
    center   = true,
    size     = "(monitor_w*0.31) (monitor_h*0.37)",
    min_size = "1095 560",
    max_size = "600 400",
})

hl.window_rule({
    name     = "float-imv",
    match    = { class = "imv" },

    float    = true,
    center   = true,
    size     = "(monitor_w*0.52) (monitor_h*0.56)",
    min_size = "1095 560",
    max_size = "1000 600",
})

hl.window_rule({
    name     = "float-eog",
    match    = { class = "org.gnome.eog" },

    float    = true,
    center   = true,
    size     = "(monitor_w*0.78) (monitor_h*0.79)",
    min_size = "1095 560",
    max_size = "1500 850",
})

hl.window_rule({
    name     = "float-localsend",
    match    = { class = "localsend" },

    float    = true,
    center   = true,
    size     = "(monitor_w*0.63) (monitor_h*0.74)",
    min_size = "1095 560",
    max_size = "1200 800",
})

hl.window_rule({
    name     = "float-bitwarden",
    match    = { class = "bitwarden" },

    float    = true,
    center   = true,
    size     = "(monitor_w*0.47) (monitor_h*0.56)",
    min_size = "1095 560",
    max_size = "900 600",
})

-- window rule
hl.window_rule({
  name     = "monkeytype-app",
  match    = { class = "brave-monkeytype.com__-Default" },
  float    = true,
  center   = true,
  size     = "(monitor_w*0.52) (monitor_h*0.60)",
  min_size = "1095 560",
  max_size = "1000 650",
})
