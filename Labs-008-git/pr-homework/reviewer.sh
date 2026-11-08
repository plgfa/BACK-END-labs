#!/usr/bin/env bash
# Імітація рев'ю pull request для домашнього завдання ASG.SH.GIT.06.
# «Рецензент» перевіряє гілку на навчальному «хостингу» за правилами CONTRIBUTING.md і текст pr-description.md,
# записує рев'ю на «хостингу» (hosting/rules.git/ed-reviews/) і друкує коментарі.
# Запуск у папці завдання: bash reviewer.sh [ПАПКА_ЗАВДАННЯ] [ГІЛКА]
# Код виходу: 0 - APPROVED; 1 - CHANGES_REQUESTED (є зауваження); 2 - не вдалося провести рев'ю.
# Це навчальний інструмент: справжнє рев'ю робить людина, яка читає зміну й ставить питання.
set -u   # без pipefail: «... | grep -q» інакше може хибно провалитися через SIGPIPE
dir="${1:-.}"
cd "$dir" || { echo "Не знайдено папку '$dir'"; exit 2; }
H="$PWD/hosting/rules.git"
[ -f "$H/ed-variant" ] || { echo "Не знайдено hosting/rules.git зі стартового скрипта. Запускайте в папці завдання."; exit 2; }
mode="$(cat "$H/ed-variant")"
hg() { git --git-dir="$H" "$@"; }
branches="$(hg for-each-ref --format='%(refname:short)' refs/heads | grep -vx main)"
branch="${2:-}"
if [ -z "$branch" ]; then
  n="$(printf '%s\n' "$branches" | grep -c .)"
  if [ "$n" = 0 ]; then echo "На «хостингу» немає гілки з вашою зміною. Підказка: git push -u origin <гілка>"; exit 2; fi
  if [ "$n" -gt 1 ]; then echo "На «хостингу» кілька гілок: $(echo $branches). Вкажіть гілку другим аргументом."; exit 2; fi
  branch="$branches"
fi
head="$(hg rev-parse -q --verify "refs/heads/$branch")" || { echo "Гілки '$branch' на «хостингу» немає."; exit 2; }
if [ "$(hg rev-parse main)" = "$head" ] || hg merge-base --is-ancestor "$head" main; then
  echo "Гілка '$branch' не містить нових комітів відносно main - нема чого рецензувати."; exit 2
fi

if [ "$mode" = "b" ]; then
  old_rule="5. Запізнення понад 10 хвилин - тренування не продовжується."
  new_rule="5. Запізнення понад 15 хвилин - тренування не продовжується."
  po="Замовник уточнив вимогу: межа запізнення - 15 хвилин, а не 10. Оновіть правило 5 у цьому ж pull request."
else
  old_rule="5. Скасування менше ніж за 24 години до початку - штраф 10% вартості квитка."
  new_rule="5. Скасування менше ніж за 24 години до початку - штраф 15% вартості квитка."
  po="Замовник уточнив вимогу: штраф - 15% вартості квитка, а не 10%. Оновіть правило 5 у цьому ж pull request."
fi
prev="$(ls "$H/ed-reviews" 2>/dev/null | grep -c '\.txt$')"
round=$((prev + 1))
if [ "$prev" -gt 0 ]; then
  last="$H/ed-reviews/$prev.txt"
  if grep -qx "commit: $head" "$last" && grep -qx "verdict: CHANGES_REQUESTED" "$last"; then
    echo "Після попереднього рев'ю (раунд $prev) у гілці '$branch' немає нових комітів. Виправте зауваження, закомітьте й відправте (git push)."
    exit 1
  fi
fi

comments=()
add() { comments+=("$1"); }

# Правила CONTRIBUTING.md
printf '%s' "$branch" | grep -qE '^(feature|fix)/[a-z0-9-]+$' || add "[CONTRIBUTING 1] Назва гілки '$branch' не відповідає правилу feature/<...> або fix/<...> (малі латинські літери, цифри, дефіси). Перейменувати гілку на «хостингу» на цьому рівні складно - для наступної задачі дотримуйтеся правила; цей pull request можна продовжити (зауваження не блокує, якщо інших немає)."
hg merge-base --is-ancestor main "$head" || add "[CONTRIBUTING 1] Гілка відстала від актуальної main. Злийте main у свою гілку (git switch <гілка>, git merge main), відправте."
desc_ok=1; desc=""
if [ -f pr-description.md ]; then desc="$(tr -d '\r' < pr-description.md)"; else desc_ok=0; fi
files="$(hg diff --name-only "main...$head")"
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    rules.md|CHANGELOG.md) ;;
    README.md) printf '%s' "$desc" | grep -q "README" || add "[CONTRIBUTING 2] Змінено README.md, але опис pull request цього не пояснює. Або приберіть зміну з цього pull request, або опишіть її в розділі «Ризики»." ;;
    *) add "[CONTRIBUTING 2] Файл '$f' не стосується задачі. Приберіть його з гілки новим комітом." ;;
  esac
done <<< "$files"
cl="$(hg show "$head:CHANGELOG.md" 2>/dev/null | tr -d '\r')"
first="$(printf '%s\n' "$cl" | grep -m1 '^- ')"
if [ "$first" = "- 2026-05-01: Початкові правила." ] || ! printf '%s' "$first" | grep -qE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}: .{5,}$'; then
  add "[CONTRIBUTING 3] У CHANGELOG.md немає нового рядка на початку списку у форматі «- РРРР-ММ-ДД: що змінено»."
fi
bad=0
while IFS= read -r m; do
  low="$(printf '%s' "$m" | tr '[:upper:]' '[:lower:]')"
  if [ "${#m}" -lt 10 ]; then bad=1; fi
  case "$low" in update|fix|changes|зміни|правки|wip|test) bad=1;; esac
done < <(hg log --format=%s "main..$head")
[ "$bad" = 0 ] || add "[CONTRIBUTING 4] Є повідомлення комітів коротші за 10 символів або неінформативні. Нові коміти пишіть за правилом; наявні в опублікованій гілці не переписуйте."
if [ "$desc_ok" = 0 ]; then
  add "[CONTRIBUTING 5] Не знайдено pr-description.md у папці завдання."
else
  printf '%s' "$desc" | grep -q "(заповніть)" && add "[CONTRIBUTING 5] В описі pull request лишилися незаповнені розділи «(заповніть)»."
  printf '%s' "$desc" | grep -q "<Назва pull request>" && add "[CONTRIBUTING 5] Опис pull request без назви: замініть рядок «<Назва pull request>»."
  for s in "## Що змінено" "## Як перевірити" "## Ризики"; do
    body="$(printf '%s\n' "$desc" | awk -v s="$s" '$0==s{f=1;next} /^## /{f=0} f' | grep -c '[^[:space:]]')"
    [ "$body" -ge 1 ] || add "[CONTRIBUTING 5] Розділ «${s#\#\# }» в описі порожній або відсутній."
  done
fi

# Зміст задачі
rules="$(hg show "$head:rules.md" 2>/dev/null | tr -d '\r')"
if [ "$mode" != "easy" ] && [ "$round" -ge 2 ]; then
  printf '%s\n' "$rules" | grep -qxF "$new_rule" || add "[Замовник] Правило 5 має бути: «$new_rule» (вимогу уточнено в першому рев'ю)."
else
  printf '%s\n' "$rules" | grep -qxF "$old_rule" || printf '%s\n' "$rules" | grep -qxF "$new_rule" || add "[Задача] У rules.md немає правила 5 у формулюванні задачі: «$old_rule»."
fi
[ "$mode" != "easy" ] && [ "$round" = 1 ] && add "[Замовник] $po"

if [ "${#comments[@]}" = 0 ]; then verdict="APPROVED"; else verdict="CHANGES_REQUESTED"; fi
# Зауваження лише про назву гілки не блокує схвалення.
if [ "$verdict" = "CHANGES_REQUESTED" ] && [ "${#comments[@]}" = 1 ] && [[ "${comments[0]}" == "[CONTRIBUTING 1] Назва гілки"* ]]; then verdict="APPROVED"; fi
{
  echo "round: $round"; echo "branch: $branch"; echo "commit: $head"; echo "verdict: $verdict"
  for c in "${comments[@]}"; do echo "comment: $c"; done
} > "$H/ed-reviews/$round.txt"
echo "Рев'ю, раунд $round, гілка $branch, коміт ${head:0:7}: $verdict"
for c in "${comments[@]}"; do echo " - $c"; done
[ "$verdict" = "APPROVED" ] && { echo "Можна зливати (git merge --no-ff) і видаляти гілку."; exit 0; }
exit 1
