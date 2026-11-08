#!/usr/bin/env bash
# Стартовий скрипт домашнього завдання ASG.SH.GIT.05 «Дві робочі копії й один віддалений репозиторій».
# Створює папку завдання з навчальним «хостингом» - голим репозиторієм hosting/team-plan.git
# з історією колеги (3 коміти). Робочі копії laptop-a і laptop-b ви створюєте самі командою git clone.
# Запуск: bash make_sync_homework.sh [--easy | --variant-b] [ЦІЛЬОВА_ПАПКА]   (типово ./sync-homework)
#   --easy       - спрощений варіант: без одночасних змін (див. урок SH.GIT.L04, розділ 10);
#   --variant-b  - еквівалентний варіант для повторної спроби (інший домен, та сама структура).
# Скрипт не змінює ваших глобальних налаштувань Git і не перезаписує наявну папку.
set -euo pipefail
mode="main"
case "${1:-}" in
  --easy) mode="easy"; shift ;;
  --variant-b) mode="b"; shift ;;
esac
target="${1:-sync-homework}"
if [ -e "$target" ]; then
  echo "Помилка: '$target' вже існує. Вкажіть іншу папку." >&2
  exit 1
fi
mkdir -p "$target/hosting"; cd "$target"
git init -q --bare -b main hosting/team-plan.git
git init -q -b main .seed
cd .seed
git config core.autocrlf false
git config commit.gpgsign false
export GIT_AUTHOR_NAME="Колега ED Mentorship" GIT_AUTHOR_EMAIL="colleague@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
t() { export GIT_AUTHOR_DATE="2026-04-0$1T$2:00:00+03:00" GIT_COMMITTER_DATE="2026-04-0$1T$2:00:00+03:00"; }
if [ "$mode" = "b" ]; then
  printf '# План турніру з настільного тенісу\n\n## Розклад\n\nРеєстрація учасників: субота, 09:00.\nПерше коло: субота, 10:00.\n' > plan.md
  printf '# Контакти\n\nОрганізатор: org@example.invalid\n' > contacts.md
  printf '# Турнір\n\nСпільні документи команди організаторів.\n' > README.md
else
  printf '# План конференції «Дані без болю»\n\n## Розклад\n\nВідкриття: субота, 10:00.\nПерша доповідь: субота, 10:30.\n' > plan.md
  printf '# Контакти\n\nОрганізаторка: org@example.invalid\n' > contacts.md
  printf '# Конференція\n\nСпільні документи команди організаторів.\n' > README.md
fi
git add README.md; t 1 09; git commit -q -m "Додати README"
git add plan.md; t 1 10; git commit -q -m "Додати план заходу"
git add contacts.md; t 2 11; git commit -q -m "Додати контакти"
git push -q ../hosting/team-plan.git main
tip="$(git rev-parse HEAD)"
cd ..
rm -rf .seed
# Службові дані для самоперевірки (усередині голого репозиторію, у коміти не потрапляють).
printf '%s\n' "$mode" > hosting/team-plan.git/ed-variant
printf '%s\n' "$tip" > hosting/team-plan.git/ed-original-tip
echo "Готово: навчальний «хостинг» створено: $target/hosting/team-plan.git"
echo "Далі: cd \"$target\" і git clone hosting/team-plan.git laptop-a (див. умову завдання)."
