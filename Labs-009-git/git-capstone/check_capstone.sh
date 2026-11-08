#!/usr/bin/env bash
# Самоперевірка підсумкового завдання ASG.SH.GIT.01. Нічого не змінює в репозиторіях
# (для перевірки .gitignore створює й видаляє тимчасовий клон).
# Запуск: bash check_capstone.sh [ПАПКА_ЗАВДАННЯ]   (типово - поточна; у ній hosting/, work/, pr-description.md)
# Код виходу 0 - усі перевірки PASS; 1 - є FAIL.
set -u   # без pipefail: «... | grep -q» інакше може хибно провалитися через SIGPIPE
dir="${1:-.}"
cd "$dir" || { echo "FAIL: папку '$dir' не знайдено"; exit 1; }
root="$PWD"; H="$root/hosting/project.git"
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails+1)); }
info() { echo "INFO: $*"; }
finish() { echo; if [ "$fails" = 0 ]; then echo "РЕЗУЛЬТАТ: PASS"; exit 0; else echo "РЕЗУЛЬТАТ: FAIL ($fails)"; exit 1; fi; }
[ -f "$H/ed-variant" ] || { echo "FAIL: не знайдено hosting/project.git зі стартового скрипта"; fails=1; finish; }
mode="$(cat "$H/ed-variant")"; tip="$(cat "$H/ed-original-tip")"; col="$(cat "$H/ed-colleague-tip")"; bad="$(cat "$H/ed-bad")"
hg() { git --git-dir="$H" "$@"; }
if [ "$mode" = "b" ]; then
  canc_ok="Скасувати запис можна не пізніше ніж за 2 години до тренування."
  disc_re='^Студентський абонемент: знижка 20%.*ранков'; extra="Сімейний абонемент: знижка 15% від 3 осіб."
else
  canc_ok="Скасувати бронювання можна не пізніше ніж за 24 години до початку."
  disc_re='^Студентська знижка: 15%.*онлайн'; extra="Групова знижка: 10% від 5 осіб."
fi
show() { hg show "main:$1" 2>/dev/null | tr -d '\r'; }

# 1. Опублікована історія збережена.
if hg merge-base --is-ancestor "$tip" main 2>/dev/null; then pass "опублікована історія main збережена (${tip:0:7} - предок main)"
else fail "опубліковані коміти зникли з main (reset/push --force?)"; fi

# 2. Помилковий коміт скасовано.
if show rules/cancellation.md | grep -qxF "$canc_ok"; then pass "правило скасування в main відповідає requirement.md"
else fail "rules/cancellation.md у main не відповідає requirement.md. Підказка: git log -p -- rules/cancellation.md"; fi
if hg log --format=%B "$tip..main" | grep -q "This reverts commit $bad"; then info "помилковий коміт ${bad:0:7} скасовано командою git revert"
else info "коміту git revert для ${bad:0:7} не знайдено - якщо виправлено окремим комітом, поясніть у report.md"; fi

# 3. Гілку колеги злито, конфлікт розв'язано за вимогою.
if [ "$mode" != "easy" ]; then
  if hg merge-base --is-ancestor "$col" main 2>/dev/null; then pass "гілку колеги feature/discounts злито в main"
  else fail "гілку колеги не злито в main"; fi
  disc="$(show rules/discounts.md)"
  if printf '%s\n' "$disc" | grep -qE "$disc_re" && ! printf '%s\n' "$disc" | grep -E '^Студент' | grep -q '10%'; then
    pass "студентська знижка відповідає requirement.md"
  else fail "рядок студентської знижки в rules/discounts.md не відповідає requirement.md (розмір і умова)"; fi
  if printf '%s\n' "$disc" | grep -qxF "$extra"; then pass "нова знижка з гілки колеги збережена"
  else fail "у rules/discounts.md немає рядка «$extra» з гілки колеги"; fi
fi
if hg grep -q -E '^(<<<<<<<|>>>>>>>|=======$)' main -- . 2>/dev/null; then fail "у main лишилися маркери конфлікту (git grep -n '^<<<<<<<' main)"
else pass "у main немає маркерів конфлікту"; fi

# 4. На «хостингу» лише main.
left="$(hg for-each-ref --format='%(refname:short)' refs/heads | grep -vx main)"
if [ -z "$left" ]; then pass "на «хостингу» лишилася тільки main (гілки задач прибрано)"
else fail "на «хостингу» лишилися гілки: $(echo $left). Підказка: git push origin --delete <гілка>"; fi

# 5. .gitignore діє, .env ніколи не потрапляв в історію.
tmp="$(mktemp -d)"; git clone -q "$H" "$tmp/c" 2>/dev/null
if [ -f "$tmp/c/.gitignore" ]; then
  ok=1
  for pth in .env logs/app.log notes.tmp; do git -C "$tmp/c" check-ignore -q --no-index "$pth" || ok=0; done
  if git -C "$tmp/c" check-ignore -q --no-index .env.example || ! git -C "$tmp/c" ls-files --error-unmatch .env.example >/dev/null 2>&1; then ok=0; fi
  if [ "$ok" = 1 ]; then pass ".gitignore у main ігнорує .env, logs/, *.tmp і не зачіпає .env.example"
  else fail ".gitignore у main не ігнорує .env, logs/ або *.tmp, або зачіпає .env.example. Підказка: git check-ignore -v <шлях>"; fi
else
  fail "у main немає .gitignore"
fi
rm -rf "$tmp"
if hg log --all --format= --name-only | grep -qx ".env"; then fail ".env потрапив у коміт (навіть якщо потім видалений - він в історії). Ключ з нього вважайте скомпрометованим"
else pass ".env не потрапив у жоден коміт"; fi

# 6. Ваш pull request: злиття --no-ff гілки, що додала .gitignore.
prm=""
for m in $(hg rev-list --first-parent --merges "$tip..main"); do
  p2="$(hg rev-parse "$m^2")"; mb="$(hg merge-base "$m^1" "$p2")"
  if hg diff --name-only "$mb" "$p2" | grep -qx ".gitignore"; then prm="$m"; break; fi
done
if [ -n "$prm" ]; then pass ".gitignore додано через гілку й злиття --no-ff (${prm:0:7})"
else fail "не знайдено коміту злиття гілки, що додає .gitignore. Підказка: окрема гілка, потім git merge --no-ff"; fi
if [ -f pr-description.md ]; then
  d="$(tr -d '\r' < pr-description.md)"; ok=1
  printf '%s' "$d" | grep -q "(заповніть\|<Назва pull request>" && ok=0
  for s in "## Що змінено" "## Як перевірити" "## Ризики" "## Самоперевірка перед запитом рев'ю"; do
    n="$(printf '%s\n' "$d" | awk -v s="$s" '$0==s{f=1;next} /^## /{f=0} f' | grep -c '[^[:space:]]')"
    [ "$n" -ge 1 ] || ok=0
  done
  if [ "$ok" = 1 ]; then pass "опис pull request має назву й чотири заповнені розділи"
  else fail "опис pull request неповний (назва і розділи «Що змінено», «Як перевірити», «Ризики», «Самоперевірка...»)"; fi
else fail "немає pr-description.md"; fi

# 7. Звіт і синхронізація робочої копії.
if hg cat-file -e main:report.md 2>/dev/null; then
  rep="$(show report.md)"
  if printf '%s' "$rep" | grep -q "${bad:0:7}"; then pass "report.md називає помилковий коміт"
  else fail "report.md не містить хеша помилкового коміту (7+ символів)"; fi
  if [ "$(printf '%s\n' "$rep" | grep -c '[^[:space:]]')" -ge 5 ]; then pass "report.md містить щонайменше 5 непорожніх рядків"
  else fail "report.md закороткий (щонайменше 5 рядків, зокрема вивід git log --oneline --graph)"; fi
else fail "у main немає report.md"; fi
if [ -d work/.git ]; then
  if [ "$(git -C work rev-parse main 2>/dev/null)" = "$(hg rev-parse main)" ] && [ -z "$(git -C work status --porcelain)" ]; then
    pass "робоча копія work синхронізована й чиста"
  else fail "робоча копія work не збігається з «хостингом» або має незакомічені зміни"; fi
else info "папки work не знайдено - перевірку робочої копії пропущено"; fi
finish
