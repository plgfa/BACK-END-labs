#!/usr/bin/env bash
# Самоперевірка домашнього завдання ASG.LANG.CS.SETUP.02 «Паспорт середовища .NET».
# Запуск із папки, де лежить ваш passport.md:   bash check_passport.sh [passport.md]
# Перевірка нічого не змінює. Правильні прогнози зберігаються як хеші: скрипт каже,
# скільки відповідей хибні в кожній машині, але не каже, які саме.
set -u
F="${1:-passport.md}"
if [ ! -f "$F" ]; then echo "Немає файла $F. Скопіюйте passport_template.md у passport.md і заповніть."; exit 2; fi
FAILS=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; echo "      Підказка: $2"; FAILS=$((FAILS+1)); }
text=$(tr -d '\r' < "$F")

# C1. Структура
missing=""
for h in "## 1. Моя машина" "## 2. Прогноз сумісності" "## 3. Пояснення" "## 4. Шлях від .cs до виконання"; do
  printf '%s\n' "$text" | grep -qF "$h" || missing="$missing «$h»"
done
if [ -z "$missing" ]; then pass "C1 структура: усі чотири розділи на місці"; else fail "C1 структура: немає розділів$missing" "не змінюйте заголовки з passport_template.md"; fi

V=$(printf '%s\n' "$text" | sed -n 's/^Варіант:[[:space:]]*\([A-Za-z]*\).*/\1/p' | head -1 | tr 'a-z' 'A-Z')
case "$V" in A|B|EASY) ;; *) fail "C0 варіант не вказано" "у першому розділі має бути рядок «Варіант: A» (або B, EASY)"; echo; echo "РЕЗУЛЬТАТ: FAIL ($FAILS)"; exit 1;; esac

# C2. Власна машина: фактичний вивід команд
sec1=$(printf '%s\n' "$text" | sed -n '/^## 1\. Моя машина/,/^## 2\./p')
if printf '%s\n' "$sec1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+ \[' && printf '%s\n' "$sec1" | grep -Eq '^Microsoft\.NETCore\.App [0-9]+\.[0-9]+\.[0-9]+ \['; then
  pass "C2 власна машина: є рядок SDK і рядок Microsoft.NETCore.App"
else
  fail "C2 власна машина: немає виводу dotnet --list-sdks або dotnet --list-runtimes" "вставте вивід команд без змін, кожен запис з нового рядка, без відступів"
fi

# C3-C4. Прогнози
if [ "$V" = "EASY" ]; then KEYS="m1.build m1.run.Report10 m2.build m2.run.Report10"; PV=A; else
  KEYS="m1.build m1.run.Report8 m1.run.Report9 m1.run.Report10 m2.build m2.run.Report8 m2.run.Report9 m2.run.Report10 m3.build m3.run.Report8 m3.run.Report9 m3.run.Report10"; PV=$V; fi
truth_hashes="1057c5ff59d77853 27260ff25eef405a 8ff89d1abbb8dfeb ff046217df1a7db0 a400f7857d7f432d 3185095b1143e20b 86f5b67cbe1309bc 9479d365f5748cd9 b48b81e65112fb72 70f747651f62f44a d8c763738e0f6aa2 c0b948c57354a4c6 a4893d6f1e3a4ffd d7018bec899e4cc4 b25b7a6952d77975 870db13694105f44 04b173cb04a23486 7b7f569f57a85fe5 b6395c7b572d3910 e681d23196e04e79 20d33a246016ab87 b45a2cd93c84a0cd 35aaa0d7da0cce77 fcfb1fbf17d5a96f"
sec2=$(printf '%s\n' "$text" | sed -n '/^## 2\. Прогноз/,/^## 3\./p')
absent=""; wrong1=0; wrong2=0; wrong3=0; total=0; ok=0; NOS=""
for k in $KEYS; do
  val=$(printf '%s\n' "$sec2" | sed -n "s/^${k//./\\.}[[:space:]]*=[[:space:]]*\([a-z]*\).*/\1/p" | head -1)
  if [ "$val" != "yes" ] && [ "$val" != "no" ]; then absent="$absent $k"; continue; fi
  total=$((total+1))
  [ "$val" = "no" ] && NOS="$NOS $k"
  h=$(printf '%s' "$PV.$k=$val" | sha256sum | cut -c1-16)
  if printf '%s\n' $truth_hashes | grep -qx "$h"; then ok=$((ok+1)); else
    case "$k" in m1.*) wrong1=$((wrong1+1));; m2.*) wrong2=$((wrong2+1));; m3.*) wrong3=$((wrong3+1));; esac
  fi
done
if [ -z "$absent" ]; then pass "C3 прогнози: усі $total рядків мають значення yes або no"; else fail "C3 прогнози: немає або хибний формат:$absent" "рядок має вигляд «m1.build = yes», значення лише yes або no"; fi
if [ "$ok" -eq "$total" ] && [ -z "$absent" ]; then pass "C4 прогнози збігаються з фактичними запусками ($ok з $total)"; else
  fail "C4 прогнози: правильно $ok з $total (хибних: machine-1 - $wrong1, machine-2 - $wrong2, machine-3 - $wrong3)" "для збірки потрібен SDK; для запуску - runtime Microsoft.NETCore.App тієї самої мажорної версії, що в apps/<застосунок>.runtimeconfig.json (новіша мажорна версія сама не підходить)"
fi

# C5. Пояснення для кожного «no»
sec3=$(printf '%s\n' "$text" | sed -n '/^## 3\. Пояснення/,/^## 4\./p')
unexpl=""
for k in $NOS; do printf '%s\n' "$sec3" | grep -Eq "^- ${k//./\\.}:[[:space:]]*[^[:space:]].{10,}" || unexpl="$unexpl $k"; done
if [ -z "$unexpl" ]; then pass "C5 пояснення: кожне «no» має причину"; else fail "C5 пояснення: немає причини для:$unexpl" "для кожного «no» додайте рядок «- <ключ>: чого саме бракує (SDK / runtime якої версії)»"; fi

# C6. Шлях від .cs до виконання
sec4=$(printf '%s\n' "$text" | sed -n '/^## 4\. Шлях від \.cs до виконання/,$p' | sed '1d' | grep -v '^<!--' | grep -v '^[[:space:]]*$')
n=$(printf '%s\n' "$sec4" | grep -o '[.!?]\( \|$\)' | wc -l | tr -d ' ')
kw=0; for re in 'IL|CIL' 'JIT' 'CLR|runtime|середовищ'; do printf '%s\n' "$sec4" | grep -Eqi "$re" && kw=$((kw+1)); done
if [ "$n" -ge 3 ] && [ "$n" -le 6 ] && [ "$kw" -eq 3 ]; then pass "C6 пояснення шляху: $n речень, згадано IL, JIT і runtime"; else
  fail "C6 пояснення шляху: речень $n (потрібно 3-5), ключових понять $kw з 3" "своїми словами: що робить компілятор, що лежить у .dll, хто і коли перетворює IL на машинний код"
fi

echo
if [ "$FAILS" -eq 0 ]; then echo "РЕЗУЛЬТАТ: PASS"; exit 0; else echo "РЕЗУЛЬТАТ: FAIL ($FAILS)"; exit 1; fi
