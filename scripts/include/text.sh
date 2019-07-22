#!/bin/sh
# shellcheck shell=ash
# shellcheck disable=SC2034

# Variable containing a new line as "$()" strips it
NL='
'

# Escape sequences
ESC="$(printf "\e")"
CSI="${ESC}["
SS2="${ESC}N"
SS3="${ESC}O"

# Terminal foreground colours (setaf 0-7)
TEXT_BLACK="${CSI}30m"
TEXT_RED="${CSI}31m"
TEXT_GREEN="${CSI}32m"
TEXT_BROWN="${CSI}33m"
TEXT_BLUE="${CSI}34m"
TEXT_MAGENTA="${CSI}35m"
TEXT_CYAN="${CSI}36m"
TEXT_WHITE="${CSI}37m"
# Terminal foreground colours (bold, setaf 0-7)
TEXT_GRAY="${CSI}1;30m"
TEXT_LIGHT_RED="${CSI}1;31m"
TEXT_LIGHT_GREEN="${CSI}1;32m"
TEXT_YELLOW="${CSI}1;33m"
TEXT_LIGHT_BLUE="${CSI}1;34m"
TEXT_LIGHT_MAGENTA="${CSI}1;35m"
TEXT_LIGHT_CYAN="${CSI}1;36m"
TEXT_LIGHT_GRAY="${CSI}1;37m"

# Terminal background colours (setab 0-7)
BACKGROUND_BLACK="${CSI}40m"
BACKGROUND_RED="${CSI}41m"
BACKGROUND_GREEN="${CSI}42m"
BACKGROUND_BROWN="${CSI}43m"
BACKGROUND_BLUE="${CSI}44m"
BACKGROUND_MAGENTA="${CSI}45m"
BACKGROUND_CYAN="${CSI}46m"
BACKGROUND_WHITE="${CSI}47m"
# Terminal background colours (bold, setab 0-7)
BACKGROUND_GRAY="${CSI}1;40m"
BACKGROUND_LIGHT_RED="${CSI}1;41m"
BACKGROUND_LIGHT_GREEN="${CSI}1;42m"
BACKGROUND_YELLOW="${CSI}1;43m"
BACKGROUND_LIGHT_BLUE="${CSI}1;44m"
BACKGROUND_LIGHT_MAGENTA="${CSI}1;45m"
BACKGROUND_LIGHT_CYAN="${CSI}1;46m"
BACKGROUND_LIGHT_GRAY="${CSI}1;47m"

# Set attribute (bold, dim, smso/sitm, smul, blink, rev, invis)
TEXT_BOLD="${CSI}1m"
TEXT_DIM="${CSI}2m"
TEXT_ITALIC="${CSI}3m"
TEXT_UNDERLINE="${CSI}4m"
TEXT_BLINK="${CSI}5m"
TEXT_INVERT="${CSI}7m"
TEXT_INVIS="${CSI}8m"
TEXT_STRIKE="${CSI}9m"
# Reset attribute (bold, dim, rmso/ritm, rmul, blink, rev, invis)
TEXT_BOLD_OFF="${CSI}21m"
TEXT_DIM_OFF="${CSI}22m"
TEXT_ITALIC_OFF="${CSI}23m"
TEXT_UNDERLINE_OFF="${CSI}24m"
TEXT_BLINK_OFF="${CSI}25m"
TEXT_INVERT_OFF="${CSI}27m"
TEXT_INVIS_OFF="${CSI}28m"
TEXT_STRIKE_OFF="${CSI}29m"

# Reset all attributes (sgr0)
TEXT_RESET="${CSI}m"

# Save/restore all text attributes, stack is limited to 10 levels
TEXT_ATTR_PUSH="${CSI}#{"
TEXT_ATTR_POP="${CSI}#}"

# Clear text relative to cursor (el, el1, el2)
TEXT_CLEARLEFT="${CSI}K"
TEXT_CLEARRIGHT="${CSI}1K"
TEXT_CLEAR="${CSI}2K"

# Cursor options
CURSOR_HIDE="${CSI}?25l"
CURSOR_SHOW="${CSI}?25h"
CURSOR_BLINK_OFF="${CSI}?12l"
CURSOR_BLINK_ON="${CSI}?12h"
CURSOR_VVIS_ON="${CSI}?34l"
CURSOR_VVIS_OFF="${CSI}?34h"
