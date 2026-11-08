#!/usr/bin/env bash
# Стартовий скрипт підсумкового завдання модуля ASG.SH.GIT.01 «Історія змін з гілкою, конфліктом і pull request».
# Створює папку завдання:
#   hosting/project.git   - навчальний «хостинг» з опублікованою історією команди (є помилковий коміт)
#                           і гілкою колеги feature/discounts (конфліктує з main);
#   requirement.md        - вимоги замовника (джерело правди для розв'язання конфлікту й пошуку помилки);
#   pr-description.md     - шаблон опису вашого pull request (не комітиться);
#   task.txt              - умова.
# Запуск: bash make_capstone.sh [--easy | --variant-b] [ЦІЛЬОВА_ПАПКА]   (типово ./git-capstone)
# Скрипт не змінює ваших глобальних налаштувань Git і не перезаписує наявну папку.
set -euo pipefail
mode="main"
case "${1:-}" in
  --easy) mode="easy"; shift ;;
  --variant-b) mode="b"; shift ;;
esac
target="${1:-git-capstone}"
if [ -e "$target" ]; then
  echo "Помилка: '$target' вже існує. Вкажіть іншу папку." >&2
  exit 1
fi
mkdir -p "$target/hosting"; cd "$target"
git init -q --bare -b main hosting/project.git
git init -q -b main .seed; cd .seed
git config core.autocrlf false; git config commit.gpgsign false
who() { export GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_NAME="$1" GIT_COMMITTER_EMAIL="$2"; }
t() { export GIT_AUTHOR_DATE="2026-06-0$1T$2:00:00+03:00" GIT_COMMITTER_DATE="2026-06-0$1T$2:00:00+03:00"; }
# Замінити рядок, що точно дорівнює OLD, на NEW (без регулярних виразів; awk є всюди, де є bash).
setline() { awk -v o="$2" -v n="$3" '{ if ($0 == o) print n; else print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }

if [ "$mode" = "b" ]; then
  cap="Одночасно в залі - не більше 12 людей."; canc_ok="Скасувати запис можна не пізніше ніж за 2 години до тренування."
  canc_bad="Скасувати запис можна не пізніше ніж за 20 хвилин до тренування."
  disc0="Студентський абонемент: знижка 10%."; disc_main="Студентський абонемент: знижка 10% (лише ранкові тренування)."
  disc_col="Студентський абонемент: знижка 20% (за студентським квитком)."; extra_col="Сімейний абонемент: знижка 15% від 3 осіб."
  title="Правила спортивного клубу «Рух»"; msg_disc="Обмежити студентський абонемент ранковими тренуваннями"
else
  cap="Місткість події: не більше 25 місць."; canc_ok="Скасувати бронювання можна не пізніше ніж за 24 години до початку."
  canc_bad="Скасувати бронювання можна не пізніше ніж за 2 години до початку."
  disc0="Студентська знижка: 10%."; disc_main="Студентська знижка: 10% (лише при онлайн-оплаті)."
  disc_col="Студентська знижка: 15% (за студентським квитком)."; extra_col="Групова знижка: 10% від 5 осіб."
  title="Правила сервісу бронювання"; msg_disc="Обмежити студентську знижку онлайн-оплатою"
fi
mkdir -p rules
printf '# %s\n\nПравила розкладено по файлах у папці rules/.\nЛокальні налаштування сервісу - у файлі .env за зразком .env.example (файл .env не комітиться).\n' "$title" > README.md
printf '# Місткість\n\n%s\n' "$cap" > rules/capacity.md
printf '# Скасування\n\n%s\n' "$canc_ok" > rules/cancellation.md
printf '# Знижки\n\n%s\n' "$disc0" > rules/discounts.md
printf 'SERVICE_URL=https://service.example.invalid\nSERVICE_API_KEY=<ваш ключ>\n' > .env.example
who "Оксана Мельник" "oksana@example.invalid"; t 1 09
git add .; git commit -q -m "Додати початкові правила й опис"
who "Тарас Бондар" "taras@example.invalid"; t 1 11
printf '\nКонтакт команди: team@example.invalid\n' >> README.md
git commit -q -am "Додати контакт команди в README"
base="$(git rev-parse HEAD)"
who "Тарас Бондар" "taras@example.invalid"; t 2 10
setline rules/cancellation.md "$canc_ok" "$canc_bad"
git commit -q -am "Уточнити формулювання правила скасування"
bad="$(git rev-parse HEAD)"
who "Оксана Мельник" "oksana@example.invalid"; t 2 14
if [ "$mode" != "easy" ]; then
  setline rules/discounts.md "$disc0" "$disc_main"
  git commit -q -am "$msg_disc"
fi
who "Оксана Мельник" "oksana@example.invalid"; t 3 09
printf '\nЯкщо місць немає, людина потрапляє в лист очікування.\n' >> rules/capacity.md
git commit -q -am "Додати правило листа очікування"
git push -q ../hosting/project.git main
tip="$(git rev-parse HEAD)"
if [ "$mode" != "easy" ]; then
  git switch -q -c feature/discounts "$base"
  who "Ірина Ковальчук" "iryna@example.invalid"; t 2 16
  setline rules/discounts.md "$disc0" "$disc_col"
  printf '%s\n' "$extra_col" >> rules/discounts.md
  git commit -q -am "Оновити студентську знижку й додати нову"
  git push -q ../hosting/project.git feature/discounts
  col="$(git rev-parse HEAD)"
else
  col=""
fi
cd ..; rm -rf .seed
H=hosting/project.git
printf '%s\n' "$mode" > $H/ed-variant
printf '%s\n' "$tip" > $H/ed-original-tip
printf '%s\n' "$col" > $H/ed-colleague-tip
printf '%s\n' "$bad" > $H/ed-bad

if [ "$mode" = "b" ]; then
  cat > requirement.md <<'T'
# Вимоги власника клубу (діють з 1 червня)

1. Скасувати запис можна не пізніше ніж за 2 години до тренування.
2. Студентський абонемент: знижка 20%, лише на ранкові тренування.
3. Сімейний абонемент: знижка 15% від 3 осіб.
T
else
  cat > requirement.md <<'T'
# Вимоги замовника (діють з 1 червня)

1. Скасувати бронювання можна не пізніше ніж за 24 години до початку.
2. Знижка для студентів - 15% при онлайн-оплаті.
3. Групова знижка: 10% від 5 осіб.
T
fi
cat > pr-description.md <<'T'
# <Назва pull request>

## Що змінено

(заповніть)

## Як перевірити

(заповніть)

## Ризики

(заповніть)

## Самоперевірка перед запитом рев'ю

(заповніть: що саме ви перевірили і якими командами)
T
case "$mode" in main) label="основний варіант";; easy) label="спрощений варіант";; b) label="варіант B";; esac
cat > task.txt <<T
Умова ($label). Повний контракт - урок SH.GIT.L06, розділ 10 (ASG.SH.GIT.01).
Історію на «хостингу» вже бачать колеги - не переписуйте її.
1. git clone hosting/project.git work. Створіть у work файл .env за зразком .env.example з будь-яким НЕСПРАВЖНІМ ключем.
2. Через окрему гілку й pull request (опис - pr-description.md, злиття --no-ff) додайте .gitignore,
   щоб .env, папка logs/ і файли *.tmp не потрапляли в репозиторій, а .env.example лишався відстежуваним.
3. Одне з правил у main суперечить requirement.md. Знайдіть коміт, що вніс помилку, і скасуйте його без переписування історії.
T
if [ "$mode" != "easy" ]; then
  cat >> task.txt <<'T'
4. Злийте гілку колеги feature/discounts у main. Конфлікт розв'яжіть за requirement.md. Потім видаліть гілку колеги на «хостингу».
T
fi
cat >> task.txt <<'T'
Наприкінці закомітьте report.md (що й чому зроблено, хеш помилкового коміту, вивід git log --oneline --graph), відправте main.
T
echo "Готово: папка завдання '$target'. Прочитайте task.txt і requirement.md."
