# Aura PARTY — état du projet (v0.22)

Party game 2D façon Mario Party, Godot 4.3 (GL Compatibility), GDScript, 2 à 8 joueurs en ligne
(ENet UDP 7777, via Radmin VPN). Export Windows .exe. L'utilisateur (Camille) ne code pas : réponses
en français, concises ; il préfère qu'on décide par défaut et qu'on montre des captures.

## Où sont les choses
- **Projet Godot de travail : `/home/claude/potes2`** (c'est là qu'on modifie).
- **Dépôt GitHub `artercamille/auraparty` : `/home/claude/auraparty`** = README.md, version.txt,
  `telecharger/AuraParty.zip` (exe + LISEZ-MOI), `docs/*.png` (captures du README), `jeu/` (copie du projet).
- Si le conteneur a été réinitialisé, `potes2` n'existe plus : recopier `auraparty/jeu/` vers `potes2`
  puis `godot --headless --import`.

## Architecture
- Autoloads : **Net** (`net.gd` : réseau, phases, salon, lancement/fin des mini-jeux, scores),
  **Game** (`game.gd` : règles du plateau côté hôte), **Sfx** (`sfx.gd` : sons, musiques, bouton ♪, volumes).
- `main.gd` : change d'écran selon `Net.phase` (menu, lobby, board, minigame, mg_results, final),
  transition « rond noir » (shader), captures de test (`SHOTS`, `SHOT_DELAYS`).
- Écrans : `screens/menu.gd`, `lobby.gd` (+ Options : volumes, étoiles bonus, mini-jeux exclus,
  sauvés dans `user://settings.cfg`), `mg_results.gd`, `final.gd` (étoiles bonus, podium, stats), `backdrop.gd`.
- Plateau : `board/map.gd` (graphe : JUNCTIONS + SEGMENTS, types de cases par lettre),
  `board/island.gd` (décor dessiné une fois, cases `draw_space`, cabanes boutique),
  `board/board.gd` (UI événementielle : menus, panneaux, pions, caméra, émotes), `board/items.gd` (objets).
- `ui.gd` (class UI) : couleurs, `UI.panel`, `UI.ribbon`, `UI.text`, `UI.btn`, `char_tex`.

### Plateau ↔ mini-jeux
- Tout est **décidé par l'hôte**. `Game._send(d)` → rpc `_ev` → signal `Game.event` (board.gd l'affiche).
  Questions aux joueurs : `_ask_and_wait(id, what, payload, timeout, flow)` ; réponses client par
  `Game.send_request({...})`. `_flow` annule les attentes obsolètes.
- Fin d'un tour de table → `Net.start_round_minigame()` → `_start_minigame()` ; case duel → `Net.start_duel(a, b, mise)`
  (le kart est exclu des duels).
- **Pioche** : `_drop_recent()` retire les mini-jeux déjà joués (`_recent_mg`) et ceux exclus par l'hôte
  (`opt_excluded`) ; quand tout est passé, la pioche repart à zéro.
- `mg_data = {type, seed, players, practice, mode ("round"/"duel"), stake}`. Le mini-jeu
  utilise `seed` pour un tirage identique chez tout le monde.
- API mini-jeu (Net) : `mg_set_ready()` / signal `mg_go`, `mg_to_host(d)` (signal `mg_msg` chez l'hôte),
  `mg_broadcast(d)` (signal `mg_state`), `send_state(pos, vel, st)` (signal `remote_state`),
  `report_out(temps, comment)` (jeux à élimination), `report_time_up()`,
  `mg_end_with_scores({id: [score, texte]})` (plus haut = mieux ; égalité ⇒ même rang), signal `mg_ending`.
- Gains : REWARDS [8,5,3,2,1,1,0,0] ; dernier mini-jeu = +1 étoile au gagnant ; duel = le gagnant prend la mise.
- Écran d'intro commun : `stage.gd` → `draw_intro()` (aperçu `assets/previews/<type>.png`, explication,
  encart Commandes), `draw_ready_row()`, `draw_duel_banner()`, `draw_heads()`. Les jeux hors stage.gd
  les appellent via `preload("res://minigames/stage.gd")`.

### Règles du plateau (game.gd)
Cases : B +3 / R −3 (+6/−6 pendant les 5 derniers tours), E événement de zone, C carte chance, I objet,
D duel, T piège (−10 vers la banque), K banque, H boutique (4 sur l'île), P tuyau, S départ (+5 en passant),
**W Roi Grognon** (malus au hasard), **G fantôme** (5 p. = vole 5-15 p. ; 30 p. = vole une étoile).
Bloc caché : 6 % sur B/R (pièces / objet / étoile). Rochers-péages à l'entrée des raccourcis
(segments 2 et 9) : prix 5, +5 par passage (max 30), `Game.rocks`. Étoile 20 pièces.
Début de partie : « Qui commence ? » (blocs). Parties de 10 tours ou plus : « Plus que 5 tours ! » (+10 pièces au dernier).
Stats suivies dans `players[id]` : coins_won, mg_wins, reds, steps, used.
Étoile gagnée (achat, bloc caché, fantôme) : grande animation plein écran `board.gd star_celebrate()` (rayons, confettis, étoile à yeux qui file vers le compteur du joueur).

## Les 16 mini-jeux (`Net.MINIGAMES`, fichiers dans `minigames/`)
| clé | nom | type |
|---|---|---|
| blocks | Gare aux blocs ! | élimination (stage.gd) |
| paint | Coup de tampon ! | territoire (stage.gd) |
| keys | La bonne clé ! | course (stage.gd) |
| parcours | Le grand parcours ! | course plateformes (stage.gd) |
| rock | Le rocher fou ! | élimination, scrolling |
| logs | Défilé de bûches ! | élimination |
| quiz | Quiz sous le chapiteau ! | points |
| kart | Grand Prix Aura ! | course 3 tours, objets (pas en duel) |
| triathlon | Mini-triathlon ! | couloirs : pagaie/vélo/haies |
| rocket | Fusées en folie ! | course verticale, astéroïdes |
| mushroom | Champi-couleurs ! | Mushroom Mix-Up, élimination |
| bumper | Boules-tamponneuses ! | Bumper Balls, élimination |
| bomb | Bombe chaude ! | Hot Bob-omb, hôte = état de la bombe |
| tug | Tir à la corde ! | Tug o' War, équipes jusqu'à 4v4, impair ⇒ 1 arbitre gagnant d'office |
| slots | Jackpot Aura ! | Lucky Lineup : machine à sous locale par joueur, 3 tirages, résultat envoyé à l'hôte (`assets/slots/`) |
| memory | Mémo-boum ! | Memory Mash (MP DS) fidèle : vue de dessus, 18 cartes 6x3, 2 équipes (impair ⇒ arbitre), saut + frappe au sol, 1re équipe à 4 paires, hôte arbitre (`assets/cards/`) |

Ajouter un mini-jeu : créer le .gd, l'ajouter à `Net.MINIGAMES` + à la liste `--checkall` dans net.gd,
gérer les robots (`Net.autotest != ""`), spectateurs/duel, puis faire son aperçu HD dans `assets/previews/`.

## Dépendances / pièges importants
- Si le conteneur est neuf : installer Godot 4.3 (zip GitHub godotengine), les modèles d'export Windows
  (`Godot_v4.3-stable_export_templates.tpz` → `~/.local/share/godot/export_templates/4.3.stable/`),
  `apt-get install wine64 p7zip-full`, rcedit-x64.exe (GitHub electron/rcedit) déclaré dans
  `~/.config/godot/editor_settings-4.3.tres` (`export/windows/rcedit`, `export/windows/wine = /usr/lib/wine/wine64`).
- Godot 4.3 en local (`godot`), export : `godot --headless --export-release "Windows Desktop" build/AuraParty.exe`
  (rcedit via wine), vérif : `WINEDEBUG=-all /usr/lib/wine/wine64 build/AuraParty.exe --headless -- --checkall`
  (31 OK attendus), zip : `7z a -tzip -mx=9 -mm=Deflate`.
- **Toujours `godot --headless --import` après avoir ajouté des images**, sinon elles sont nulles (`null`).
- **Textures : les charger AVANT de dessiner** (dans `_ready`), sinon blanches dans les couches dessinées une seule fois.
- Imports par défaut en compression lossy 0.9 ; les aperçus (`assets/previews/*.import`) sont en
  `compress/mode=0` + mipmaps (qualité HD) : refaire ce réglage pour tout nouvel aperçu.
- Le typage GDScript échoue sur `var x := expression non typée` → typer explicitement.
- Assets : Kenney (CC0, style pastel « Platformer Remastered », sans contours), packs dans
  `/home/claude/kenney2` et `/home/claude/kmirror` (peuvent disparaître). Musiques FreePD (domaine public).
  Persos = aliens Kenney recolorés (8 couleurs dans `assets/chars/<couleur>/`).
- Pas de personnages Nintendo dessinés : noms français neutres (Roi Grognon, fantôme générique, etc.).
- **Logo `assets/ui/logo.png` = logo d'origine : NE PAS le modifier** (Camille a détesté la version retouchée).
- Version : `Net.VERSION` (doit être identique chez tous les joueurs) + `version.txt` + LISEZ-MOI + README.
- Commits : `git -c user.name=artercamille -c user.email=artercamille@users.noreply.github.com`.

## Tests automatiques (`tools/rungame.sh` dans le projet)
- Partie de robots : hôte `godot -- --autotest-host` + clients `godot --headless -- --autotest-join`,
  variables : `AUTOTEST_PLAYERS`, `ROUNDS`, `SPEED`, `MG`, `DUEL_MG`, `FORCE_SPACE=B,D,W,G`, `HIDDEN=1`,
  `PRACTICE=<type>` (mini-jeu seul), `NOREADY=1` (reste sur l'écran d'intro), `SHOTS`/`SHOT_DELAYS`
  (captures, avec `xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3`).
  Succès = ligne `AUTOTEST_OK` dans les logs ; chercher `SCRIPT ERROR`. Logs `[mg]` = mini-jeux tirés.
- Captures du plateau : `godot -- --debug-screen=board` avec `BOARD_CAM="x,y,zoom"`, `BOARD_SHOT`,
  `BOARD_SHOT_T`, `BOARD_EVENT='{json}|{json}'`, `BOARD_MENU`, `BOARD_MAP=1`.
  Autres écrans : `--debug-screen=final` (`SHOW_STATS=1`), `--debug-screen=lobby` (`SHOW_OPTIONS=1`).
- Lancer les commandes depuis `/home/claude/potes2` (sinon pas de captures).
- `HL=1` = hôte sans écran : à utiliser pour tester la logique, car l'hôte sous xvfb tourne à ~10 i/s
  dans les arènes (le chrono avance au ralenti, les captures sont décalées).
- Robots dans les jeux de plateforme : métas `goal_x`, `goal_jump`, `jump_now`, `goal_down` (piqué) sur le Player.

## Interface (GUI) à refaire
- Camille fait générer un kit d'interface par ChatGPT (style validé : cartoon arrondi pastel, boutons ronds,
  barres de menu penchées, grand cadre à étoile, ruban, cartouche joueur, icônes, touches, badges 1-8).
- `tools/decoupe_gui.py planche.png dossier` : retire le fond (vrai alpha, faux damier ou vert #00FF00)
  et découpe chaque élément en PNG + `_sommaire.png` numéroté. Testé sur la 1re planche (44 éléments).
- Attendu : images séparées en grand, sans texte. Puis remplacer `UI.panel`/`UI.btn`/`UI.ribbon` par des
  StyleBoxTexture (9-slice) et des icônes.

## À faire / à ne pas oublier
- Camille veut des mini-jeux **copiés fidèlement** sur les vrais Mario Party (règles, vue, déroulé) : vérifier le vrai jeu avant de l'adapter.
- Le zip fait ~54 Mo : GitHub refuse au-delà de 100 Mo → prévoir GitHub Releases si ça grossit.
- Pas encore fait : mini-jeux 2v2 / 1v3 selon la couleur des cases (proposé, pas choisi) ;
  menus en barres penchées style Mario Party (capture de Camille) ; alliés (Jamboree).
- Idées de mini-jeux en attente : Shy Guy Says, Bowser's Big Blast, Spin and Bear It (roulette), « jeu des marches 10 8 5 3 »,
  « poupées russes », Le bon cliché, Carrousel hanté, Course aux drapeaux, Abris-sandwichs.
- Jamais testé avec de vrais joueurs depuis v0.15 : équilibrage du triathlon, de la corde (TAP_CAP 11),
  de la mèche de la bombe, des rochers et du fantôme à vérifier.
- Petit défaut : en mode test (bots qui rejoignent), les messages « X a rejoint » recouvrent l'encart Commandes.
- Si on change un mini-jeu, refaire son aperçu (`assets/previews/<type>.png`, 1280×720).
