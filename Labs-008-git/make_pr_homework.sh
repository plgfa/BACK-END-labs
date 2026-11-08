#!/usr/bin/env bash
# Стартовий скрипт домашнього завдання ASG.SH.GIT.06 «Pull request з виправленням за рев'ю».
# Створює папку завдання:
#   hosting/rules.git     - навчальний «хостинг» (голий репозиторій) з історією команди;
#   pr-description.md     - шаблон опису pull request (заповнюєте ви; файл НЕ комітиться);
#   task.txt              - умова.
# Рев'ю імітує скрипт reviewer.sh (той самий каталог, що й цей скрипт).
# Запуск: bash make_pr_homework.sh [--easy | --variant-b] [ЦІЛЬОВА_ПАПКА]   (типово ./pr-homework)
# Скрипт не змінює ваших глобальних налаштувань Git і не перезаписує наявну папку.
set -euo pipefail
mode="main"
case "${1:-}" in
  --easy) mode="easy"; shift ;;
  --variant-b) mode="b"; shift ;;
esac
target="${1:-pr-homework}"
if [ -e "$target" ]; then
  echo "Помилка: '$target' вже існує. Вкажіть іншу папку." >&2
  exit 1
fi
mkdir -p "$target/hosting"; cd "$target"
git init -q --bare -b main hosting/rules.git
git init -q -b main .seed; cd .seed
git config core.autocrlf false; git config commit.gpgsign false
export GIT_AUTHOR_NAME="Команда ED Mentorship" GIT_AUTHOR_EMAIL="team@example.invalid"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
t() { export GIT_AUTHOR_DATE="2026-05-0$1T$2:00:00+03:00" GIT_COMMITTER_DATE="2026-05-0$1T$2:00:00+03:00"; }
if [ "$mode" = "b" ]; then
  title="Правила спортивного клубу «Рух»"
  printf '# %s\n\n1. Запис на тренування відкривається за 7 днів.\n2. Скасувати запис можна не пізніше ніж за 2 години.\n3. В одному залі - не більше 12 людей.\n4. Повторний запис на те саме тренування не створює другого місця.\n' "$title" > rules.md
  printf '# Клуб «Рух»\n\nУ цьому репозиторіі зберігаються правила клубу. Зміни пропонуйте через pull request.\n' > README.md
else
  title="Правила сервісу бронювання"
  printf '# %s\n\n1. Місткість події: не більше 25 місць.\n2. Скасувати бронювання може лише його власник не пізніше ніж за 24 години до початку.\n3. Повторний запит з тим самим ключем не створює друге бронювання.\n4. Якщо місць немає, користувач потрапляє в лист очікування.\n' "$title" > rules.md
  printf '# Сервіс бронювання\n\nУ цьому репозиторіі зберігаються правила сервісу. Зміни пропонуйте через pull request.\n' > README.md
fi
cat > CONTRIBUTING.md <<'T'
# Як пропонувати зміни

1. Кожна задача - окрема гілка від актуальної main. Назва гілки: feature/<коротко-латиницею> або fix/<коротко-латиницею>, лише малі латинські літери, цифри й дефіси.
2. У pull request - лише зміни, потрібні для задачі. Помічене побіжно (друкарські помилки тощо) - окремою задачею або явно описаним у розділі «Ризики» опису.
3. Кожна зміна правил додає рядок на початок списку в CHANGELOG.md у форматі: - РРРР-ММ-ДД: що змінено.
4. Повідомлення комітів - у наказовій формі, від 10 символів, без «update», «fix», «зміни».
5. Опис pull request має три розділи: «Що змінено», «Як перевірити», «Ризики». Порожніх розділів не буває.
6. Після рев'ю зауваження виправляються новими комітами в тій самій гілці; гілку не перестворюють.
T
printf '# Історія змін\n\n- 2026-05-01: Початкові правила.\n' > CHANGELOG.md
git add rules.md; t 1 09; git commit -q -m "Додати початкові правила"
git add README.md CONTRIBUTING.md; t 1 10; git commit -q -m "Додати README і правила внеску"
git add CHANGELOG.md; t 2 11; git commit -q -m "Додати журнал змін"
git push -q ../hosting/rules.git main
tip="$(git rev-parse HEAD)"
cd ..; rm -rf .seed
printf '%s\n' "$mode" > hosting/rules.git/ed-variant
printf '%s\n' "$tip" > hosting/rules.git/ed-original-tip
mkdir -p hosting/rules.git/ed-reviews
cat > pr-description.md <<'T'
# <Назва pull request>

## Що змінено

(заповніть)

## Як перевірити

(заповніть)

## Ризики

(заповніть)
T
if [ "$mode" = "b" ]; then
  rule="5. Запізнення понад 10 хвилин - тренування не продовжується."
else
  rule="5. Скасування менше ніж за 24 години до початку - штраф 10% вартості квитка."
fi
case "$mode" in main) label="основний варіант";; easy) label="спрощений варіант";; b) label="варіант B";; esac
cat > task.txt <<T
Умова ($label). Повний контракт - урок SH.GIT.L05, розділ 10.
Задача від замовника: додати в rules.md правило
  $rule
1. git clone hosting/rules.git work ; прочитайте CONTRIBUTING.md.
2. Створіть гілку за правилами CONTRIBUTING.md, зробіть зміну, відправте гілку на «хостинг».
3. Заповніть pr-description.md (цей файл не комітиться - це текст pull request).
4. Попросіть рев'ю: bash <шлях>/reviewer.sh .   (у папці завдання). Виправте зауваження в тій самій гілці,
   відправте й попросіть рев'ю знову - доки не буде APPROVED.
5. Злийте гілку в main так, як це робить кнопка Merge pull request (git merge --no-ff), відправте main,
   видаліть гілку на «хостингу».
T
echo "Готово: папка завдання '$target'. Прочитайте task.txt."
