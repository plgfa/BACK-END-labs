#!/usr/bin/env bash
# Самоперевірка домашнього завдання ASG.SH.GIT.04. Нічого не змінює в репозиторії.
# Запуск у папці репозиторію: bash check_regression.sh [ПАПКА]
# Варіант (основний, --easy, --variant-b) визначається автоматично за даними стартового скрипта.
# Код виходу 0 - усі перевірки PASS; 1 - є FAIL.
set -u   # без pipefail: «... | grep -q» інакше може хибно провалитися через SIGPIPE
dir="${1:-.}"
cd "$dir" || { echo "FAIL: папку '$dir' не знайдено"; exit 1; }
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails+1)); }
info() { echo "INFO: $*"; }
finish() { echo; if [ "$fails" = 0 ]; then echo "РЕЗУЛЬТАТ: PASS"; exit 0; else echo "РЕЗУЛЬТАТ: FAIL ($fails)"; exit 1; fi; }

if [ ! -f .git/ed-original-tip ]; then
  echo "FAIL: це не репозиторій зі стартового скрипта ASG.SH.GIT.04 (немає службових даних у .git)."
  echo "Підказка: запускайте перевірку в папці, створеній make_regression_repo.sh."
  fails=1; finish
fi
mode="$(cat .git/ed-variant)"; tip="$(cat .git/ed-original-tip)"
if [ "$mode" = "b" ]; then
  bad="Басейн - 8 осіб."; good_re='^Басейн(: 18| - 18 осіб\.)$'
  others_re=('^Тренажерний зал(: 25| - 25 осіб\.)$' '^Зал для йоги(: 14| - 14 осіб\.)$' '^Зал для боксу(: 10| - 10 осіб\.)$')
  total="Загальна місткість клубу: 67 осіб."; lost="rooms.md"
else
  bad="Хаб «Ринок» - 2 місця."; good_re='^Хаб «Ринок»(: 20| - 20 місць\.)$'
  others_re=('^Зал «Поділ»(: 30| - 30 місць\.)$' '^Простір «Порт»(: 15| - 15 місць\.)$' '^Аудиторія «Сад»(: 12| - 12 місць\.)$')
  total="Загальна місткість залів: 77 місць."; lost="venues.md"
fi

# 1. Історія не переписана: усі опубліковані коміти досі в main.
branch="$(git symbolic-ref --short HEAD 2>/dev/null)"
if [ "$branch" = "main" ] && git merge-base --is-ancestor "$tip" HEAD 2>/dev/null; then
  pass "опублікована історія збережена: коміт ${tip:0:7} досі в main, нові коміти - поверх"
else
  fail "опублікований коміт ${tip:0:7} більше не в історії main (або ви не на main). Схоже на reset/amend опублікованих комітів. Підказка: git reflog покаже, куди повернутися"
fi

# 2. Помилкове значення виправлено, інші не зачеплено.
cap="$(git show HEAD:capacity.md 2>/dev/null | tr -d '\r')"
if printf '%s\n' "$cap" | grep -qE "$good_re" && ! printf '%s\n' "$cap" | grep -qF "$bad"; then
  pass "місткість виправлено в capacity.md"
else
  fail "у capacity.md останнього коміту досі немає правильного значення (або лишився рядок «$bad»). Підказка: git log -S і git show"
fi
ok=1; for re in "${others_re[@]}"; do printf '%s\n' "$cap" | grep -qE "$re" || ok=0; done
if [ "$ok" = 1 ]; then pass "інші записи capacity.md не пошкоджено"
else fail "інші записи capacity.md змінилися або зникли. Підказка: git diff ${tip:0:7} HEAD -- capacity.md"; fi

# 3. Звіт називає коміт, що вніс помилку.
culprit="$(git log -S "$bad" --format=%H "$tip" -- capacity.md | tail -1)"
if git cat-file -e HEAD:report.md 2>/dev/null; then
  rep="$(git show HEAD:report.md)"
  if printf '%s' "$rep" | grep -q "${culprit:0:7}"; then pass "report.md називає коміт, що вніс помилку"
  else fail "report.md не містить хеша коміту, що вніс помилку (щонайменше 7 перших символів). Підказка: git log -S"; fi
  if [ "$(printf '%s\n' "$rep" | grep -c '[^[:space:]]')" -ge 4 ]; then pass "report.md містить щонайменше 4 непорожні рядки"
  else fail "report.md закороткий: потрібні хеш, автор і дата, як знайшли, як виправили (щонайменше 4 рядки)"; fi
else
  fail "немає закоміченого report.md"
fi
if git log --format=%B "$tip..HEAD" | grep -q "This reverts commit $culprit"; then
  info "помилковий коміт скасовано командою git revert"
else
  info "коміту git revert для помилкового коміту не знайдено - виправлення зроблено окремим комітом (поясніть вибір у report.md)"
fi

if [ "$mode" != "easy" ]; then
  # 4. Загальна місткість у README відповідає сумі.
  if git show HEAD:README.md 2>/dev/null | tr -d '\r' | grep -qxF "$total"; then pass "README містить правильну загальну місткість"
  else fail "у README немає рядка «$total». Підказка: після скасування помилки перерахуйте суму - revert не виправляє рядки, додані пізніше"; fi
  # 5. Випадково видалений файл відновлено з історії без змін.
  del="$(git log --diff-filter=D --format=%H "$tip" -- "$lost" | head -1)"
  want="$(git rev-parse --verify -q "$del^:$lost")"
  have="$(git rev-parse --verify -q "HEAD:$lost")"
  if [ -n "$have" ] && [ "$have" = "$want" ]; then pass "$lost відновлено у версії, що була перед видаленням"
  elif [ -n "$have" ]; then fail "$lost є, але відрізняється від версії перед видаленням. Підказка: git restore --source=<коміт>^ $lost (символ ^ - батько коміту)"
  else fail "$lost не відновлено. Підказка: git log --diff-filter=D -- $lost знайде коміт, що його видалив"; fi
fi

# 6. Робоча папка чиста.
dirty="$(git status --porcelain)"
if [ -z "$dirty" ]; then pass "робоча папка чиста"
else fail "є незакомічені зміни: $(echo "$dirty" | tr '\n' ';')"; fi
finish
