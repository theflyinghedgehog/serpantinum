#!/usr/bin/env bash
# Arch updates widget helper. Prints pending updates as JSON:
# {"helper":"yay|paru|","error":"","packages":[{"name","old","new","aur"}]}
# Repo updates come from checkupdates (pacman-contrib), which uses a temp copy of
# the sync DB, so it never touches the real pacman database.

esc() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '%s' "$s"; }

helper=""
for h in paru yay; do
    if command -v "$h" >/dev/null 2>&1; then helper=$h; break; fi
done

err=""
repo_out=""
if command -v checkupdates >/dev/null 2>&1; then
    repo_out=$(checkupdates 2>/dev/null)   # exit 2 just means "no updates"
else
    err="checkupdates missing: sudo pacman -S pacman-contrib"
fi

aur_out=""
if [ -n "$helper" ]; then
    aur_out=$("$helper" -Qua 2>/dev/null)
fi

first=1
emit() {
    if [ $first -eq 1 ]; then first=0; else printf ','; fi
    printf '{"name":"%s","old":"%s","new":"%s","aur":%s}' "$(esc "$1")" "$(esc "$2")" "$(esc "$3")" "$4"
}

printf '{"helper":"%s","error":"%s","packages":[' "$helper" "$(esc "$err")"
while read -r name old arrow new rest; do
    { [ -z "$name" ] || [ "$arrow" != "->" ]; } && continue
    emit "$name" "$old" "$new" false
done <<< "$repo_out"
while read -r name old arrow new rest; do
    { [ -z "$name" ] || [ "$arrow" != "->" ]; } && continue
    case "$rest" in *ignored*) continue ;; esac
    emit "$name" "$old" "$new" true
done <<< "$aur_out"
printf ']}\n'
