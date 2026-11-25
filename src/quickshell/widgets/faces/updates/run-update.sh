#!/usr/bin/env bash
# Runs the update for the Arch updates widget, without a terminal.
#   run-update.sh all
#   run-update.sh some <repo pkgs...> -- <aur pkgs...>
# The sudo password comes in on the first line of stdin. It is checked once with
# sudo -S, then handed to pacman/yay through a SUDO_ASKPASS helper that reads it
# from this process's environment, so it never touches the disk.
# Output is plain pacman/yay text plus a few "@@" marker lines for the widget.

exec 2>&1
export LC_ALL=C   # the widget parses pacman's English output

IFS= read -r SERP_UPD_PW
export SERP_UPD_PW

askpass=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/serp-askpass.XXXXXX") || { echo "@@ERR mktemp"; exit 4; }
trap 'rm -f "$askpass"' EXIT
chmod 700 "$askpass"
printf '#!/bin/sh\nprintf "%%s\\n" "$SERP_UPD_PW"\n' > "$askpass"
export SUDO_ASKPASS="$askpass"

# One attempt only, so a typo doesn't count as three failures for faillock.
if ! printf '%s\n' "$SERP_UPD_PW" | sudo -S -p '' -v >/dev/null 2>&1; then
    echo "@@ERR badpass"
    exit 3
fi
echo "@@AUTH ok"

helper=""
for h in paru yay; do
    if command -v "$h" >/dev/null 2>&1; then helper=$h; break; fi
done

aur_flags=(--noconfirm --answerclean None --answerdiff None --answeredit None --removemake)
case "$helper" in
    yay)  aur_flags+=(--sudoflags -A) ;;
    paru) aur_flags=(--noconfirm --skipreview --removemake --sudoflags -A) ;;
esac

mode=$1; shift
rc=0
if [ "$mode" = "all" ]; then
    if [ -n "$helper" ]; then
        "$helper" -Syu "${aur_flags[@]}"; rc=$?
    else
        sudo -A pacman -Syu --noconfirm; rc=$?
    fi
else
    repo=(); aur=(); side=repo
    for a in "$@"; do
        if [ "$a" = "--" ]; then side=aur; continue; fi
        if [ $side = repo ]; then repo+=("$a"); else aur+=("$a"); fi
    done
    if [ ${#repo[@]} -gt 0 ]; then
        sudo -A pacman -Sy --needed --noconfirm "${repo[@]}"; rc=$?
    fi
    if [ $rc -eq 0 ] && [ ${#aur[@]} -gt 0 ]; then
        "${helper:-yay}" -S --needed "${aur_flags[@]}" "${aur[@]}"; rc=$?
    fi
fi

echo "@@DONE $rc"
exit $rc
