#!/usr/bin/env bash
# Перевірка робочого місця (SH.START.L03, ASG.SH.START.01).
# Запуск у Git Bash (Windows) або Terminal (macOS/Linux):
#   bash check_workstation.sh <шлях-до-робочої-папки>                 - перевірки уроку (W1-W5)
#   bash check_workstation.sh <шлях> --assignment                     - плюс файли домашнього завдання (W6-W7)
#   bash check_workstation.sh <шлях> --assignment --variant-b         - еквівалентний варіант B (плюс B1-B2)
# Скрипт нічого не змінює: лише читає й друкує PASS/FAIL. Код виходу 0 - усе PASS, 1 - є FAIL.

DIR="${1:-}"
MODE_ASG=0
VARIANT_B=0
for a in "$@"; do
  [ "$a" = "--assignment" ] && MODE_ASG=1
  [ "$a" = "--variant-b" ] && VARIANT_B=1
done
FAILS=0
pass() { echo "PASS $1: $2"; }
fail() { echo "FAIL $1: $2"; FAILS=$((FAILS + 1)); }
info() { echo "INFO $1"; }

if [ -z "$DIR" ] || [ "${DIR#--}" != "$DIR" ]; then
  echo "Вкажіть шлях до робочої папки, наприклад: bash check_workstation.sh ~/ed-learning"
  exit 2
fi

info "Дата перевірки: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
info "Система: $(uname -s) $(uname -r)"
info "Оболонка: bash ${BASH_VERSION}"

# W1: назва робочої папки - лише латинські літери, цифри, «-» і «_»
NAME="$(basename "$DIR")"
if [ ! -d "$DIR" ]; then
  fail W1 "папки «$DIR» не існує. Підказка: створіть її або перевірте шлях (урок, крок 5 демонстрації)."
elif printf '%s' "$NAME" | grep -Eq '^[A-Za-z0-9_-]+$'; then
  pass W1 "робоча папка «$NAME» існує, назва без пробілів і без літер поза латиницею"
else
  fail W1 "назва «$NAME» містить пробіли або інші символи. Підказка: лише латинські літери, цифри, «-» і «_», наприклад ed-learning."
fi

# W2: обов'язкові підпапки
MISSING=""
for sub in notes practice projects; do
  [ -d "$DIR/$sub" ] || MISSING="$MISSING $sub"
done
if [ -d "$DIR" ] && [ -z "$MISSING" ]; then
  pass W2 "є підпапки notes, practice, projects"
else
  fail W2 "немає підпапок:${MISSING:- (немає самої робочої папки)}"
fi

# W3: README.md щонайменше з трьома непорожніми рядками
if [ -f "$DIR/README.md" ]; then
  N=$(grep -c '[^[:space:]]' "$DIR/README.md")
  if [ "$N" -ge 3 ]; then pass W3 "README.md: непорожніх рядків - $N"; else fail W3 "README.md: непорожніх рядків - $N, потрібно щонайменше 3"; fi
else
  fail W3 "немає файла README.md у робочій папці"
fi

# W4: Git встановлено, версія не нижча за 2.30
if command -v git >/dev/null 2>&1; then
  GV="$(git --version)"
  NUM="$(printf '%s' "$GV" | sed -E 's/^git version ([0-9]+)\.([0-9]+).*/\1 \2/')"
  OK=$(printf '%s' "$NUM" | awk '{ if ($1 > 2 || ($1 == 2 && $2 >= 30)) print 1; else print 0 }')
  if [ "$OK" = "1" ]; then pass W4 "$GV (потрібно 2.30 або новіший)"; else fail W4 "$GV - застаріла версія, потрібно 2.30 або новіший"; fi
  ED="$(git config --get core.editor)"
  if [ -n "$ED" ]; then info "Git core.editor: $ED"; else info "Git core.editor не задано - Git візьме редактор зі змінних VISUAL/EDITOR або типовий (зазвичай vi/Vim), див. урок, розділ 12"; fi
else
  GV=""
  fail W4 "команду git не знайдено. Підказка: встановіть Git (розділ 5.4) і відкрийте НОВЕ вікно терміналу."
fi

# W5: редактор VS Code доступний з терміналу
if command -v code >/dev/null 2>&1; then
  CV="$(code --version 2>/dev/null | head -n 1)"
  pass W5 "VS Code $CV, команда code доступна в терміналі"
else
  CV=""
  fail W5 "команду code не знайдено. Підказка: на Windows відкрийте нове вікно терміналу після встановлення; на macOS у VS Code відкрийте палітру команд і виконайте «Shell Command: Install 'code' and optionally 'copilot' commands in PATH» (copilot не встановлюйте)."
fi

if [ "$MODE_ASG" = "1" ]; then
  # W6: план і розклад з уроків SH.START.L01-L02
  if [ -f "$DIR/notes/plan.md" ] && [ -f "$DIR/notes/schedule.md" ]; then
    pass W6 "notes/plan.md і notes/schedule.md на місці"
  else
    fail W6 "потрібні notes/plan.md і notes/schedule.md (домашні завдання ASG.SH.START.02 і ASG.SH.START.03)"
  fi
  # W7: опис перешкоди
  F="$DIR/notes/obstacle.md"
  if [ -f "$F" ] && grep -q '^Перешкода: ..........' "$F" && grep -q '^Як усунуто: ..........' "$F"; then
    pass W7 "notes/obstacle.md описує перешкоду і спосіб її усунення"
  else
    fail W7 "потрібен notes/obstacle.md з рядками «Перешкода: ...» і «Як усунуто: ...» (щонайменше 10 символів кожен)"
  fi
fi

if [ "$VARIANT_B" = "1" ]; then
  # B1: додаткова підпапка tools
  if [ -d "$DIR/tools" ]; then pass B1 "є підпапка tools"; else fail B1 "у варіанті B потрібна ще підпапка tools"; fi
  # B2: README.md містить точні рядки версій, отримані командами
  if [ -n "$GV" ] && [ -n "$CV" ] && [ -f "$DIR/README.md" ] && grep -qxF "$GV" "$DIR/README.md" && grep -qxF "$CV" "$DIR/README.md"; then
    pass B2 "README.md містить фактичні рядки версій: «$GV» і «$CV»"
  else
    fail B2 "README.md має містити окремими рядками точний вивід «git --version» і перший рядок «code --version» з цього комп'ютера"
  fi
fi

if [ "$FAILS" -eq 0 ]; then echo "Результат: PASS"; exit 0; else echo "Результат: FAIL ($FAILS)"; exit 1; fi
