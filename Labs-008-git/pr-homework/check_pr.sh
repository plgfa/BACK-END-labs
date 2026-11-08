  #!/usr/bin/env bash
# Самоперевірка домашнього завдання ASG.SH.GIT.06. Нічого не змінює.
# Запуск: bash check_pr.sh [ПАПКА_ЗАВДАННЯ]   (типово - поточна; у ній hosting/ і pr-description.md)
# Код виходу 0 - усі перевірки PASS; 1 - є FAIL.
set -u   # без pipefail: «... | grep -q» інакше може хибно провалитися через SIGPIPE
dir="${1:-.}"
cd "$dir" || { echo "FAIL: папку '$dir' не знайдено"; exit 1; }
H="$PWD/hosting/rules.git"
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails+1)); }
finish() { echo; if [ "$fails" = 0 ]; then echo "РЕЗУЛЬТАТ: PASS"; exit 0; else echo "РЕЗУЛЬТАТ: FAIL ($fails)"; exit 1; fi; }
[ -f "$H/ed-variant" ] || { echo "FAIL: не знайдено hosting/rules.git зі стартового скрипта"; fails=1; finish; }
mode="$(cat "$H/ed-variant")"; tip="$(cat "$H/ed-original-tip")"
hg() { git --git-dir="$H" "$@"; }
case "$mode" in
  b) final="5. Запізнення понад 15 хвилин - тренування не продовжується." ;;
  easy) final="5. Скасування менше ніж за 24 години до початку - штраф 10% вартості квитка." ;;
  *) final="5. Скасування менше ніж за 24 години до початку - штраф 15% вартості квитка." ;;
esac

# 1. Історія команди збережена.
if hg merge-base --is-ancestor "$tip" main 2>/dev/null; then pass "історія main на «хостингу» не переписана"
else fail "початкові коміти команди зникли з main на «хостингу» (push --force?)"; fi

# 2. Рев'ю: зауваження, виправлення в тій самій гілці, схвалення.
reviews="$(ls "$H/ed-reviews" 2>/dev/null | grep '\.txt$' | sort -n)"
cr=""; ap=""; apbranch=""
for r in $reviews; do
  f="$H/ed-reviews/$r"
  c="$(sed -n 's/^commit: //p' "$f")"; v="$(sed -n 's/^verdict: //p' "$f")"
  if [ "$v" = "CHANGES_REQUESTED" ] && [ -z "$cr" ]; then cr="$c"; fi
  if [ "$v" = "APPROVED" ]; then ap="$c"; apbranch="$(sed -n 's/^branch: //p' "$f")"; fi
done
if [ -z "$ap" ]; then
  fail "немає схваленого рев'ю (APPROVED). Підказка: bash reviewer.sh у папці завдання, виправлення, повторне рев'ю"
else
  pass "є схвалене рев'ю коміту ${ap:0:7} (гілка $apbranch)"
fi
if [ "$mode" != "easy" ]; then
  if [ -z "$cr" ]; then fail "немає рев'ю із зауваженнями (CHANGES_REQUESTED) - рев'ю не проводилося до схвалення"
  elif [ -n "$ap" ] && [ "$cr" != "$ap" ] && hg merge-base --is-ancestor "$cr" "$ap" 2>/dev/null; then
    pass "зауваження виправлено новими комітами в тій самій гілці (${cr:0:7} -> ${ap:0:7})"
  elif [ -n "$ap" ]; then
    fail "схвалений коміт не є продовженням коміту, на який надійшли зауваження. Умова: виправлення - нові коміти в тій самій гілці, без перестворення"
  fi
fi

# 3. Злиття схваленого коміту в main через коміт злиття (--no-ff), без змін після схвалення.
merge=""
if [ -n "$ap" ]; then
  for m in $(hg rev-list --first-parent --merges main); do
    if [ "$(hg rev-parse "$m^2")" = "$ap" ]; then merge="$m"; break; fi
  done
fi
if [ -n "$merge" ]; then pass "схвалений коміт злито в main комітом злиття ${merge:0:7} (як кнопка Merge pull request)"
elif [ -n "$ap" ] && hg merge-base --is-ancestor "$ap" main; then fail "схвалений коміт є в main, але без коміту злиття (fast-forward). Підказка: git merge --no-ff <гілка>"
else fail "схвалений коміт не злито в main на «хостингу». Підказка: git switch main, git pull, git merge --no-ff <гілка>, git push"; fi

# 4. Підсумковий зміст.
if hg show main:rules.md 2>/dev/null | tr -d '\r' | grep -qxF "$final"; then pass "main містить правило 5 у підсумковому формулюванні"
else fail "у main немає рядка «$final»"; fi

# 5. Гілку прибрано.
left="$(hg for-each-ref --format='%(refname:short)' refs/heads | grep -vx main)"
if [ -z "$left" ]; then pass "гілку задачі видалено на «хостингу»"
else fail "на «хостингу» лишилися гілки: $(echo $left). Підказка: git push origin --delete <гілка>"; fi

# 6. Опис pull request.
if [ -f pr-description.md ]; then
  d="$(tr -d '\r' < pr-description.md)"
  ok=1
  printf '%s' "$d" | grep -q "(заповніть)\|<Назва pull request>" && ok=0
  for s in "## Що змінено" "## Як перевірити" "## Ризики"; do
    n="$(printf '%s\n' "$d" | awk -v s="$s" '$0==s{f=1;next} /^## /{f=0} f' | grep -c '[^[:space:]]')"
    [ "$n" -ge 1 ] || ok=0
  done
  if [ "$ok" = 1 ]; then pass "опис pull request має назву й три заповнені розділи"
  else fail "опис pull request неповний (назва, «Що змінено», «Як перевірити», «Ризики»)"; fi
else
  fail "немає pr-description.md"
fi
finish
