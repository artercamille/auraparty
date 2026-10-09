#!/bin/bash
# Partie de robots : 1 hôte (avec écran virtuel pour les captures) + N-1 clients sans écran.
# Usage : OUT=dossier N=4 [HL=1 (hôte sans écran) ROUNDS= MG= DUEL_MG= FORCE_SPACE= PRACTICE= SHOTS=1 SHOT_DELAYS= SPEED= NOREADY=1 TMAX=] tools/rungame.sh
N=${N:-4}
OUT=${OUT:-/tmp/auraparty_run}
TMAX=${TMAX:-240}
rm -rf "$OUT" && mkdir -p "$OUT"
cd /home/claude/potes2
export AUTOTEST_PLAYERS=$N ROUNDS=${ROUNDS:-1}
if [ -n "$SHOTS" ]; then export SHOTS="$OUT"; fi
if [ -n "$HL" ]; then timeout $TMAX godot --headless -- --autotest-host > "$OUT/host.log" 2>&1 & else timeout $TMAX xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 -- --autotest-host > "$OUT/host.log" 2>&1 & fi
sleep 4
unset SHOTS
for i in $(seq 2 $N); do
  timeout $TMAX godot --headless -- --autotest-join > "$OUT/c$i.log" 2>&1 &
  sleep 0.5
done
wait
grep -h "AUTOTEST_OK\|SCRIPT ERROR\|\[mg\]" "$OUT"/*.log | sort | uniq -c | head -20
grep -h -A3 "SCRIPT ERROR" "$OUT"/*.log | head -30
ls "$OUT" | grep png | head -40
