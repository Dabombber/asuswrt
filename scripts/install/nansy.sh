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

		VERSION="$(nano -V | awk 'NR==1{print $NF}')"
		IFS=' .' read -r MAJOR MINOR PATCH <<-EOF
			$VERSION
		EOF
		PATCH="${PATCH%pre?}"
		if [ $((${MAJOR:-0} * 10000 + ${MINOR:-0} * 100 + ${PATCH:-0})) -lt 20704 ]; then
			URL='https://git.savannah.gnu.org/cgit/nano.git/plain/doc/syntax'
		else
			URL='https://git.savannah.gnu.org/cgit/nano.git/plain/syntax'
		fi

		echo 'Downloading...'
		curl -fs -w '\t%{filename_effective}\n' "$URL/{${LANGUAGES// /,}}.nanorc?h=v$VERSION" --create-dirs -o '/jffs/configs/nano/#1.nanorc'

		if [ -f /jffs/configs/nano/sh.nanorc ] && ! grep -qF '/jffs/configs/profile\.add' /jffs/configs/nano/sh.nanorc; then
			escape() { printf '%s\n' "$1" | sed 's/[]\/$*.^&[]/\\&/g'; }

			sed -i -e "s/^\(syntax \"\?sh\"\? \).*$/\1$(escape '"(\.sh|(\.|/)(a|ba|c|da|k|mk|pdk|tc|z)sh(rc|_profile)?|/(etc/|\.)profile|/jffs/configs/profile\.add)$"')/" \
				-e "s/^header .*$/$(escape 'header "^#!.*/(((a|ba|c|da|k|mk|pdk|tc|z)?sh)|(busybox|env) +sh|openrc-run|runscript)"')/" \
				-e "s/^magic .*$/$(escape 'magic "(POSIX|Bourne-Again) shell script.*text"')/" \
				/jffs/configs/nano/sh.nanorc
		fi
		if [ ! -f '/jffs/configs/nanorc' ] || ! grep -qF 'include "/jffs/configs/nano/*.nanorc"' /jffs/configs/nanorc; then
			echo 'include "/jffs/configs/nano/*.nanorc"' >> /jffs/configs/nanorc
		fi
	fi
fi
