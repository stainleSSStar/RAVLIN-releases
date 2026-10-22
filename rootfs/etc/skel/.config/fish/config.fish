# RAVLIN fish configuration
# Copied into every new user's home from /etc/skel by useradd -m.

if status is-interactive
    set -g fish_greeting "RAVLIN — minimal Void Linux remix"

    function fish_prompt
        # root gets a red user tag, everyone else magenta
        set -l user_color --bold magenta
        if test (id -u) -eq 0
            set user_color --bold red
        end

        set -l user (set_color $user_color)$USER(set_color normal)
        set -l host (set_color --bold cyan)(prompt_hostname)(set_color normal)
        set -l cwd (set_color --bold green)(prompt_pwd)(set_color normal)

        echo -n "$user@$host $cwd > "
    end
end
