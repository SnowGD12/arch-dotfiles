# 1. Global settings
set fish_greeting
fish_add_path $HOME/.cargo/bin
set -gx QT_QPA_PLATFORMTHEME qt5ct
set -gx QT_QPA_PLATFORMTHEME qt6ct

# 2. Aliases & Abbreviations
alias ls="lsd"

# 3. Interactive shell setup
if status is-interactive
    starship init fish | source
    	fastfetch
end

