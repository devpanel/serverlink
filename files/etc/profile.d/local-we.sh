if [ -n "$USER" -a -z "${USER##w_*}" ]; then
        umask 022
        alias vi=vim
fi
