#!/bin/sh

if [ $# -eq 0 ]; then
	echo "Usage: ${0##*/} [list|all|[LANGUAGE ...]]"
	echo ' Downloads nano syntax files.'
else
	LANGUAGES='asm autoconf awk c changelog cmake css debian default elisp fortran gentoo go groff guile html java javascript json lua makefile man mgp mutt nanohelp nanorc nftables objc ocaml patch perl php po postgresql pov python ruby rust sh spec tcl tex texinfo xml'
	if [ "$1" = 'list' ]; then
		echo "$LANGUAGES"
	else
		[ "$1" != 'all' ] && LANGUAGES="$*"
		echo 'Downloading...'
		curl -fs -w '\t%{filename_effective}\n' "https://git.savannah.gnu.org/cgit/nano.git/plain/syntax/{${LANGUAGES// /,}}.nanorc" --create-dirs -o '/jffs/configs/nano/#1.nanorc'
		if [ ! -f '/jffs/configs/nanorc' ] || ! grep -qF 'include "/jffs/configs/nano/*.nanorc"' /jffs/configs/nanorc; then
			echo 'include "/jffs/configs/nano/*.nanorc"' >>/jffs/configs/nanorc
		fi
		IFS=' .' read -r MAJOR MINOR _ <<-EOF
			$(nano -V | awk 'NR==1{print $NF}')
		EOF
		[ -f /jffs/configs/nano/sh.nanorc ] && ! grep -qF '/jffs/configs/profile.add' /jffs/configs/nano/sh.nanorc && sed -i 's/^\(syntax sh .*\))\$"$/\1|\/jffs\/configs\/profile\\\.add)\$"/' /jffs/configs/nano/sh.nanorc
		if [ $((${MAJOR:-0} * 100 + ${MINOR:-0})) -lt 406 ]; then
			sed -i 's/^formatter/#formatter/' /jffs/configs/nano/*
		fi
	fi
fi
