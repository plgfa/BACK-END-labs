#!/usr/bin/env bash
# Стартовий скрипт домашнього завдання ASG.SH.GIT.04 «Розслідування регресії в історії».
# Створює репозиторій з однаковою в усіх історією (7 комітів трьох авторів), яку вважаємо вже опублікованою.
# Запуск: bash make_regression_repo.sh [--easy | --variant-b] [ЦІЛЬОВА_ПАПКА]
#   без параметра  - основний варіант (зали для подій);
#   --easy         - спрощений варіант: лише знайти й скасувати помилковий коміт;
#   --variant-b    - еквівалентний варіант для повторної спроби (спортивний клуб).
# Скрипт не змінює ваших глобальних налаштувань Git і не перезаписує наявну папку.
set -euo pipefail
mode="main"
case "${1:-}" in
  --easy) mode="easy"; shift ;;
  --variant-b) mode="b"; shift ;;
esac
target="${1:-regression-hunt}"
if [ -e "$target" ]; then
  echo "Помилка: '$target' вже існує. Вкажіть іншу папку." >&2
  exit 1
fi
mkdir -p "$target"; cd "$target"
git init -q -b main
git config core.autocrlf false
git config commit.gpgsign false
repl() { sed "$2" "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
as() {
  export GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_NAME="$1" GIT_COMMITTER_EMAIL="$2"
  export GIT_AUTHOR_DATE="$3" GIT_COMMITTER_DATE="$3"
}
A=("Оксана Мельник" "oksana@example.invalid")
B=("Тарас Бондар" "taras@example.invalid")
C=("Ірина Ковальчук" "iryna@example.invalid")

if [ "$mode" = "b" ]; then
  # Варіант B: спортивний клуб. Помилка - у місткості басейну.
  as "${A[@]}" "2026-03-02T09:00:00+02:00"
  printf '# Місткість приміщень клубу\n\nТренажерний зал: 25\nБасейн: 18\nЗал для йоги: 14\n' > capacity.md
  printf '# Абонементи (навчальні числа)\n\nМісячний: 900 грн.\nСтудентський: 600 грн.\n' > prices.md
  printf '# Контакти приміщень\n\nТренажерний зал - gym@example.invalid\nБасейн - pool@example.invalid\nЗал для йоги - yoga@example.invalid\n' > rooms.md
  printf '# Клуб «Рух»\n\nУзгоджені дані про приміщення й абонементи клубу.\n' > README.md
  git add .; git commit -q -m "Додати початкові дані клубу"
  as "${B[@]}" "2026-03-03T10:00:00+02:00"
  printf 'Зал для боксу: 10\n' >> capacity.md
  printf 'Зал для боксу - box@example.invalid\n' >> rooms.md
  git commit -q -am "Додати зал для боксу"
  as "${C[@]}" "2026-03-04T11:00:00+02:00"
  printf 'Сімейний: 1500 грн.\n' >> prices.md
  git commit -q -am "Додати сімейний абонемент"
  as "${B[@]}" "2026-03-05T17:30:00+02:00"
  repl capacity.md 's/^Тренажерний зал: 25$/Тренажерний зал - 25 осіб./'
  repl capacity.md 's/^Басейн: 18$/Басейн - 8 осіб./'
  repl capacity.md 's/^Зал для йоги: 14$/Зал для йоги - 14 осіб./'
  repl capacity.md 's/^Зал для боксу: 10$/Зал для боксу - 10 осіб./'
  git commit -q -am "Привести записи місткості до одного формату"
  as "${A[@]}" "2026-03-06T09:15:00+02:00"
  printf 'Ранковий: 700 грн.\n' >> prices.md
  git commit -q -am "Додати ранковий абонемент"
  as "${C[@]}" "2026-03-09T12:40:00+02:00"
  printf '\nЯк перевірити зміну: загальна місткість має дорівнювати сумі за capacity.md.\n' >> README.md
  git rm -q rooms.md
  git commit -q -am "Додати в README правило перевірки"
  as "${B[@]}" "2026-03-10T15:05:00+02:00"
  printf '\nЗагальна місткість клубу: 57 осіб.\n' >> README.md
  git commit -q -am "Додати загальну місткість у README"
else
  # Основний і спрощений варіанти: зали для подій. Помилка - у місткості Хабу «Ринок».
  as "${A[@]}" "2026-03-02T09:00:00+02:00"
  printf '# Місткість залів\n\nЗал «Поділ»: 30\nХаб «Ринок»: 20\nПростір «Порт»: 15\n' > capacity.md
  printf '# Ціни (навчальні числа)\n\nБазова ціна: 400 грн.\nСтудентська знижка: 10%%.\n' > prices.md
  printf '# Контакти залів\n\nЗал «Поділ» - podil@example.invalid\nХаб «Ринок» - rynok@example.invalid\nПростір «Порт» - port@example.invalid\n' > venues.md
  printf '# Сервіс бронювання\n\nУзгоджені дані про зали й ціни для сервісу бронювання.\n' > README.md
  git add .; git commit -q -m "Додати початкові дані про зали й ціни"
  as "${B[@]}" "2026-03-03T10:00:00+02:00"
  printf 'Аудиторія «Сад»: 12\n' >> capacity.md
  printf 'Аудиторія «Сад» - sad@example.invalid\n' >> venues.md
  git commit -q -am "Додати аудиторію «Сад»"
  as "${C[@]}" "2026-03-04T11:00:00+02:00"
  printf 'Групова знижка (від 5 осіб): 15%%.\n' >> prices.md
  git commit -q -am "Додати групову знижку"
  as "${B[@]}" "2026-03-05T17:30:00+02:00"
  repl capacity.md 's/^Зал «Поділ»: 30$/Зал «Поділ» - 30 місць./'
  repl capacity.md 's/^Хаб «Ринок»: 20$/Хаб «Ринок» - 2 місця./'
  repl capacity.md 's/^Простір «Порт»: 15$/Простір «Порт» - 15 місць./'
  repl capacity.md 's/^Аудиторія «Сад»: 12$/Аудиторія «Сад» - 12 місць./'
  git commit -q -am "Привести записи місткості до одного формату"
  as "${A[@]}" "2026-03-06T09:15:00+02:00"
  printf 'Рання реєстрація: знижка 20%%.\n' >> prices.md
  git commit -q -am "Додати знижку за ранню реєстрацію"
  as "${C[@]}" "2026-03-09T12:40:00+02:00"
  printf '\nЯк перевірити зміну: загальна місткість має дорівнювати сумі за capacity.md.\n' >> README.md
  if [ "$mode" != "easy" ]; then git rm -q venues.md; fi
  git commit -q -am "Додати в README правило перевірки"
  as "${B[@]}" "2026-03-10T15:05:00+02:00"
  printf '\nЗагальна місткість залів: 59 місць.\n' >> README.md
  git commit -q -am "Додати загальну місткість у README"
fi
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_DATE
# Службові дані для самоперевірки (усередині .git, у коміти не потрапляють).
printf '%s\n' "$mode" > .git/ed-variant
git rev-parse HEAD > .git/ed-original-tip
echo "Готово: репозиторій '$target' створено. Історію вважайте вже опублікованою (її бачать колеги)."
