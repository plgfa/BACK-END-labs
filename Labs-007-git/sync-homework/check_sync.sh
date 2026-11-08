#!/usr/bin/env bash
# Самоперевірка домашнього завдання ASG.SH.GIT.05. Нічого не змінює в репозиторіях.
# Запуск: bash check_sync.sh [ПАПКА_ЗАВДАННЯ]   (типово - поточна папка; у ній мають бути hosting/, laptop-a/, laptop-b/)
# Частину з реальним хостингом (GitHub тощо) перевіряє ментор за звітом; скрипт лише повідомляє INFO.
# Код виходу 0 - усі перевірки PASS; 1 - є FAIL.
set -u   # без pipefail: «... | grep -q» інакше може хибно провалитися через SIGPIPE
dir="${1:-.}"
cd "$dir" || { echo "FAIL: папку '$dir' не знайдено"; exit 1; }
root="$PWD"
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails+1)); }
info() { echo "INFO: $*"; }
finish() { echo; if [ "$fails" = 0 ]; then echo "РЕЗУЛЬТАТ: PASS"; exit 0; else echo "РЕЗУЛЬТАТ: FAIL ($fails)"; exit 1; fi; }
H="$root/hosting/team-plan.git"
if [ ! -f "$H/ed-original-tip" ]; then
  echo "FAIL: не знайдено hosting/team-plan.git зі стартового скрипта. Запускайте перевірку в папці завдання (там, де hosting/)."
  fails=1; finish
fi
mode="$(cat "$H/ed-variant")"; tip="$(cat "$H/ed-original-tip")"
hg() { git --git-dir="$H" "$@"; }
if [ "$mode" = "b" ]; then
  line_a="Фінал: неділя, 15:00."; line_b="Суддя турніру: judge@example.invalid"
else
  line_a="Перерва на каву: субота, 12:00."; line_b="Технічна підтримка залу: tech@example.invalid"
fi

# 1. Історія колеги збережена на «хостингу».
if hg merge-base --is-ancestor "$tip" main 2>/dev/null; then pass "на «хостингу» збережено історію колеги (${tip:0:7} - предок main)"
else fail "історію колеги на «хостингу» переписано або гілки main немає. Не використовуйте push --force"; fi

# 2. Обидві зміни є в main на «хостингу».
plan="$(hg show main:plan.md 2>/dev/null | tr -d '\r')"; contacts="$(hg show main:contacts.md 2>/dev/null | tr -d '\r')"
if printf '%s\n' "$plan" | grep -qxF "$line_a"; then pass "зміна з laptop-a (plan.md) є на «хостингу»"
else fail "на «хостингу» в plan.md немає рядка «$line_a». Підказка: коміт у laptop-a, потім git push"; fi
if printf '%s\n' "$contacts" | grep -qxF "$line_b"; then pass "зміна з laptop-b (contacts.md) є на «хостингу»"
else fail "на «хостингу» в contacts.md немає рядка «$line_b». Підказка: коміт у laptop-b, потім git push"; fi

# 3. Зміни зроблено паралельно (жоден коміт не є предком іншого) - так виникає відхилений push.
ca="$(hg log --format=%H -S "$line_a" main -- plan.md | tail -1)"
cb="$(hg log --format=%H -S "$line_b" main -- contacts.md | tail -1)"
if [ "$mode" != "easy" ] && [ -n "$ca" ] && [ -n "$cb" ]; then
  if ! hg merge-base --is-ancestor "$ca" "$cb" && ! hg merge-base --is-ancestor "$cb" "$ca"; then
    pass "коміти з двох папок зроблено паралельно, історії розійшлися й були об'єднані"
  else
    fail "коміт з однієї папки зроблено ПІСЛЯ отримання коміту з іншої - розбіжності не було. Умова: у laptop-b закомітьте зміну до git pull"
  fi
fi

# 4. Обидві робочі копії синхронізовані з «хостингом» і чисті.
hmain="$(hg rev-parse main 2>/dev/null)"
for c in laptop-a laptop-b; do
  if [ ! -d "$root/$c/.git" ]; then fail "немає робочої копії $c. Підказка: git clone hosting/team-plan.git $c"; continue; fi
  linked=0
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    case "$u" in /*|[A-Za-z]:*|.*) [ -d "$u" ] || u="$root/$c/$u" ;; esac
    # Той самий навчальний «хостинг»: збігаються службовий файл і вершина main.
    if [ -f "$u/ed-original-tip" ] && [ "$(cat "$u/ed-original-tip")" = "$tip" ] \
       && [ "$(git --git-dir="$u" rev-parse main 2>/dev/null)" = "$hmain" ]; then linked=1; fi
  done < <(git -C "$root/$c" config --get-regexp '^remote\..*\.url$' | cut -d' ' -f2-)
  if [ "$linked" = 1 ]; then pass "$c має віддалений репозиторій, що вказує на hosting/team-plan.git"
  else fail "$c не пов'язана з hosting/team-plan.git (git remote -v). Підказка: робочі копії створюються git clone"; fi
  if [ "$(git -C "$root/$c" rev-parse main 2>/dev/null)" = "$hmain" ]; then pass "$c: main збігається з «хостингом»"
  else fail "$c: main не збігається з «хостингом». Підказка: git pull (і git push, якщо є невідправлені коміти)"; fi
  if [ -z "$(git -C "$root/$c" status --porcelain)" ]; then pass "$c: робоча папка чиста"
  else fail "$c: є незакомічені зміни (git status)"; fi
done

# 5. Звіт.
if hg cat-file -e main:report.md 2>/dev/null; then
  rep="$(hg show main:report.md)"
  if [ "$(printf '%s\n' "$rep" | grep -c '[^[:space:]]')" -ge 4 ]; then pass "report.md на «хостингу» містить щонайменше 4 непорожні рядки"
  else fail "report.md закороткий (потрібно щонайменше 4 рядки)"; fi
  if printf '%s' "$rep" | grep -qiE "github\.com|gitlab\.com|bitbucket\.org"; then info "у звіті згадано адресу хостингу - частину 2 перевіряє ментор"
  else info "у звіті немає адреси хостингу (github.com, gitlab.com, bitbucket.org) - частина 2 не виконана або описана інакше; ментор перевірить"; fi
else
  fail "на «хостингу» немає закоміченого report.md"
fi
finish
