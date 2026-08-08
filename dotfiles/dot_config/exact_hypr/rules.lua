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
    name   = "float-pavucontrol",
    match  = { class = "org.pulseaudio.pavucontrol" },

    float  = true,
    center = true,
    size   = "800 500",
})

hl.window_rule({
    name   = "float-nmtui",
    match  = { class = "nmtui" },

    float  = true,
    center = true,
    size   = "600 400",
})

hl.window_rule({
    name   = "float-calendar",
    match  = { class = "calendar" },

    float  = true,
    center = true,
    size   = "900 500",
})

hl.window_rule({
    name   = "float-overskride",
    match  = { class = "io.github.kaii_lb.Overskride" },

    float  = true,
    center = true,
    size   = "600 400",
})

hl.window_rule({
    name   = "float-imv",
    match  = { class = "imv" },

    float  = true,
    center = true,
    size   = "1000 600",
})

hl.window_rule({
    name   = "float-eog",
    match  = { class = "org.gnome.eog" },

    float  = true,
    center = true,
    size   = "1500 850",
})

hl.window_rule({
    name   = "float-localsend",
    match  = { class = "localsend" },

    float  = true,
    center = true,
    size   = "1200 800",
})

-- window rule
hl.window_rule({
  name = "monkeytype-app",
  match = { class = "brave-monkeytype.com__-Default" },
  float = true,
  size = { 1000, 650 },
  center = true,
})
