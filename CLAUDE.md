# Aura PARTY — état du projet (v0.30)

Party game 2D façon Mario Party, Godot 4.3 (GL Compatibility), GDScript, 2 à 8 joueurs en ligne
(ENet UDP 7777, via Radmin VPN ou ZeroTier si Mac). Export Windows .exe + Mac .app universelle, jouable à la manette. L'utilisateur (Camille) ne code pas : réponses
en français, concises ; il préfère qu'on décide par défaut et qu'on montre des captures.

## Où sont les choses
- **Projet Godot de travail : `/home/claude/potes2`** (c'est là qu'on modifie).
- **Dépôt GitHub `artercamille/auraparty` : `/home/claude/auraparty`** = README.md, version.txt,
  `telecharger/AuraParty.zip` (exe + LISEZ-MOI), `telecharger/AuraParty-Mac.zip` (.app + « LISEZ-MOI (Mac).txt »), `docs/*.png` (captures du README), `jeu/` (copie du projet).
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
**Échelle** : `BoardMap.K = 1.25` multiplie toutes les positions (JUNCTIONS, SEGMENTS écrits en coordonnées « non agrandies ») ; dans `island.gd` les positions absolues sont `Vector2(...) * K` mais les tailles des bâtiments/décors et les décalages autour d'un sprite (château, volcan) ne sont PAS multipliés. `SIZE` = 5000x3375.
**Côte** : `BoardMap.COAST` est générée par `tools/gen_coast.py` (épouse chemins + lieux, criques BAYS, cap du phare, bruit) → relancer le script si on bouge un chemin ou un lieu.
Cases r=47 (espacement régulier ~175 px : si on allonge un chemin, rajouter des cases), chemins 150 px avec petites flèches de sens (`_chevron`), pions `TOKEN_SCALE` 0.42 ; carte (Tab) `MAP_ZOOM` 0.152 + `MAP_OFS` (île à droite de la légende, cartouches cachés).
Étoile gagnée (achat, bloc caché, fantôme) : grande animation plein écran `board.gd star_celebrate()` (rayons, confettis, étoile à yeux qui file vers le compteur du joueur).

## Les 23 mini-jeux (`Net.MINIGAMES`, fichiers dans `minigames/`)
Documentation joueurs (règles, commandes, gains, aperçus) : **`docs/MINI-JEUX.md`** à la racine du dépôt (liée depuis le README) : la tenir à jour.
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
| flags | Le Capitaine a dit ! | Shy Guy Says (Superstars) : l'hôte envoie les ordres (feintes), chacun juge sa réponse et `report_out(at de l'ordre)` ; minuteur 30 s à 45 s ⇒ survivants gagnent |
| roulette | Roulette-marteau ! | Spin and Bear It : phases hôte choose/arrow/spin_wait/spin/smash, l'hôte élimine via `Net._on_out(victime, manche)` |
| penguins | Pingouins perdus ! | **COOP** Penguin Pushers : l'hôte simule les pingouins (fuite), rang S/A/B selon le temps |
| chrono | Stop chrono ! | idée de Camille : 3 manches, temps à viser (5-11,5 s), chrono visible 3/2/1,2 s puis caché par un volet ; chacun envoie son temps (`mg_to_host`), l'hôte révèle (`ph` target/run/stopped/reveal) ; score = −total des écarts |
| kitchen | Cuisine en folie ! | **COOP** façon Overcooked (choix de Camille, pas un vrai MP) : grille 14x8, l'hôte gère objets/planches/feux/commandes ; robots = burgers en boucle |
| doodle | Toujours plus haut ! | v0.30, demande de Camille « comme Doodle Jump » : colonne de 720 px (papier quadrillé), rebond auto, écran qui boucle, plateformes vertes/bleues (bougent)/marron (cassent)/blanches (disparaissent), ressort, hélice, monstres ; chacun grimpe chez lui (mêmes plateformes, autres en transparence) ; tomber = fini ; 60 s, score = hauteur (m) envoyée à l'hôte. Tests : `DOODLE_ALT=altitude` (départ plus haut), `DOODLE_POSE=1` (image figée pour l'aperçu) |
| maze | Sors du labyrinthe ! | v0.30, demande de Camille : labyrinthe de haies 19x11 (graine, quelques boucles, salle 3x3 au centre), une sortie loin du centre, caméra qui suit, flèche = direction de la sortie, champignons (vitesse) dans les culs-de-sac, on passe à travers les autres ; fin 15 s après le 1er sorti (90 s max), non sortis classés par cases restantes |

**Jeux coop** : `"coop": true` dans `Net.MINIGAMES` ; jamais en duel ; fin avec `Net.mg_end_coop(pièces, texte)` → tout le monde gagne les mêmes pièces (S 10 / A 7 / B 4 / raté 0), pas d'étoile du dernier mini-jeu. Écran de rang commun : `penguins.gd _draw_result()`.

Ajouter un mini-jeu : créer le .gd, l'ajouter à `Net.MINIGAMES` + à la liste `--checkall` dans net.gd,
gérer les robots (`Net.autotest != ""`), spectateurs/duel, puis faire son aperçu HD dans `assets/previews/`,
et l'ajouter à `docs/MINI-JEUX.md` + au tableau du README + au LISEZ-MOI.

## Performance (v0.28) — IMPORTANT
- Le décor fixe de l'île (couches `back`, `ground` + `props`) est **cuit en images** au chargement (`island.gd _bake_all/_bake` :
  SubViewport, tuiles 1024 px avec 16 px de recouvrement, échelle 0.9 pour l'île / 0.4 pour le ciel, mipmaps, matériau
  PREMULT_ALPHA). Sans ça : ~15 600 appels de dessin et 840 000 triangles par image (lag). Avec : ~520 appels.
- Cuisson une seule fois par session (`static var _baked_cache`), lancée en arrière-plan dès le salon (`Island.prebake()` dans
  `lobby.gd`) ; écran « Préparation de l'île... » sur le plateau si pas encore fini (`board.gd _draw_loading`). Ignorée en headless.
- `NO_BAKE=1` = dessin direct (utile pour les captures sous xvfb : sans carte graphique la cuisson prend ~17 s ;
  sur un vrai PC ~1-2 s). `PERF=1` affiche fps / appels de dessin ; `HIDE_LAYERS=ground,props` pour mesurer.
- Tout décor ajouté dans `_draw_ground/_draw_props/_draw_back` est automatiquement cuit. Ce qui bouge va dans
  `water`, `clouds` ou `top` (redessinés à chaque image : y rester léger).

## Manette (v0.28)
- Actions dans `net.gd _setup_inputs` (clavier + manette) : left/right/up/down (croix + stick), jump (A), push (X, B), menu (Start),
  map (Y, Select), back (B). Plateau : B = retour, LB/RB/clics de stick = émotes (`EMOTE_PAD`).
- `UI.pad_mode` passe à true dès qu'on touche la manette (`Net._input`) : `UI.padify()` remplace ESPACE→A, Échap→B dans `UI.text` ;
  encart Commandes converti (`stage.gd _pad_tokens`, puces `UI.pad_chip`) ; touches du HUD (`UI.key_chip(..., pad)`).
- Menus Godot (menu, salon, fin) : anneau jaune `UI.FocusRing` visible seulement en mode manette ; focus auto sur le bouton
  principal (`UI.first_button`, évite « Exclure ») ; fenêtres par-dessus via `UI.open_modal(over, fermer)` (focus piégé, B ferme).
- `FORCE_PAD=1` = captures en mode manette (simule 2 appuis sur la croix au bout de 2,5 s). `LOBBY_DELAYS` = moments des captures du salon.

## Mac (v0.28)
- Preset « macOS » (universel x86_64+arm64, signature ad-hoc intégrée, pas de notarisation) ; il faut
  `textures/vram_compression/import_etc2_astc=true` (fait) et le modèle `macos.zip` dans les export templates
  (extrait du .tpz 4.3 : le .tpz fait 1 Go, n'extraire que `templates/macos.zip`).
- Export : `godot --headless --export-release "macOS" build/mac/AuraParty-Mac.zip`, puis rezipper avec `zip -9 -r -y` (garde le
  bit exécutable ; PAS 7z) en ajoutant « LISEZ-MOI (Mac).txt ». Jamais testé sur un vrai Mac (pas de Mac ici).
- Radmin VPN n'existe pas sur Mac → ZeroTier conseillé ; `Net.local_ips()` reconnaît Radmin (26.), Hamachi (25.),
  Tailscale (100.64-127.) et ZeroTier (nom de la carte réseau).
- `gh` n'est pas authentifié ici (pas de GitHub Releases) : les zips sont dans le dépôt (Mac ~82 Mo, Windows ~59 Mo,
  limite GitHub 100 Mo par fichier ; l'historique git grossit à chaque version).

## Dépendances / pièges importants
- Si le conteneur est neuf : installer Godot 4.3 (zip GitHub godotengine), les modèles d'export Windows
  (`Godot_v4.3-stable_export_templates.tpz` → `~/.local/share/godot/export_templates/4.3.stable/` : n'extraire que
  `version.txt`, `windows_release_x86_64.exe`, `windows_release_x86_64_console.exe`, `macos.zip` avec
  `python3 -I tools/zip_distant.py URL_du_tpz templates/version.txt,... DOSSIER` (~190 Mo au lieu d'1 Go)),
  `apt-get install wine64 p7zip-full`, rcedit-x64.exe (GitHub electron/rcedit) déclaré dans
  `~/.config/godot/editor_settings-4.3.tres` (`export/windows/rcedit`, `export/windows/wine = /usr/lib/wine/wine64`).
- Godot 4.3 en local (`godot`), export : `godot --headless --export-release "Windows Desktop" build/AuraParty.exe`
  (rcedit via wine), vérif : `WINEDEBUG=-all /usr/lib/wine/wine64 build/AuraParty.exe --headless -- --checkall`
  (38 OK attendus), zip : `7z a -tzip -mx=9 -mm=Deflate`.
- `build/` n'est PAS dans .gitignore : exporter dans le scratchpad (ou supprimer `jeu/build` avant de committer).
- Si le dépôt est cloné ailleurs que `/home/claude/potes2` : `ln -s <dépôt>/jeu /home/claude/potes2` (rungame.sh s'y place).
- **Toujours `godot --headless --import` après avoir ajouté des images**, sinon elles sont nulles (`null`).
- **Textures : les charger AVANT de dessiner** (dans `_ready`), sinon blanches dans les couches dessinées une seule fois.
- Imports par défaut en compression lossy 0.9 ; les aperçus (`assets/previews/*.import`) sont en
  `compress/mode=0` + mipmaps (qualité HD) : refaire ce réglage pour tout nouvel aperçu.
- Le typage GDScript échoue sur `var x := expression non typée` → typer explicitement.
- Assets : Kenney (CC0, style pastel « Platformer Remastered », sans contours), packs dans
  `/home/claude/kenney2` et `/home/claude/kmirror` (peuvent disparaître). Musiques FreePD (domaine public).
  Persos = aliens Kenney recolorés (8 couleurs dans `assets/chars/<couleur>/`), avec un contour sombre de 5 px
  ajouté (v0.26) ; originaux sans contour dans `tools/chars_sans_contour/`.
  Packs reçus en v0.26 (`/home/claude/kpacks`) : game-icons, board-game-icons (déjà ceux de `assets/icons`),
  board-game-info, input-prompts-pixel (pixel art : Camille n'aime pas, non utilisé).
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
  Autres écrans : `--debug-screen=final` (`SHOW_STATS=1`), `--debug-screen=lobby` (`SHOW_OPTIONS=1`, `SHOW_PICKER=1` = choix
  du mini-jeu ; ajouter `NO_BAKE=1`, sinon la cuisson de l'île bloque l'écran sous xvfb).
- Lancer les commandes depuis `/home/claude/potes2` (sinon pas de captures).
- `HL=1` = hôte sans écran : à utiliser pour tester la logique, car l'hôte sous xvfb tourne à ~10 i/s
  dans les arènes (le chrono avance au ralenti, les captures sont décalées).
- Robots dans les jeux de plateforme : métas `goal_x`, `goal_jump`, `jump_now`, `goal_down` (piqué) sur le Player.

## Interface (kit ChatGPT, v0.25)
- Planche d'origine : `tools/kit_gui_chatgpt.png` ; éléments découpés dans `assets/gui/` (boutons, `bar_*` barres
  penchées, `frame`/`frame_plain`, `ribbon`/`ribbon_n` (version neutre recolorable), `cartouche`, `box_*`, `ic_*`,
  `key_*`, `rank1..8`). `UI.gui("nom")` charge une texture.
- `UI.KitBox` (StyleBox dessiné en code dans le style du kit : contour sombre, bas foncé, reflet, point brillant) est
  utilisé par `UI.panel()` et `UI.button_box()` → tous les boutons et panneaux du jeu. Fenêtres (PanelContainer) =
  `frame_plain` en 9-slice. `UI.ribbon()` = ruban du kit étiré et recoloré.
- Plateau : menu d'action en barres penchées (↑ ↓), icônes étoile/pièce du kit, badges de rang 1-8.
- `tools/decoupe_gui.py planche.png dossier` : découpe une planche (vrai alpha, faux damier ou vert #00FF00).
- v0.27 : encre commune `UI.INK` (contour des textes = contour des panneaux), `UI.text_left`, `UI.key_chip` (touche + légende),
  `UI.portrait` (visage en rond sur fond clair, utilisé par les cartes joueurs, `stage.gd` et `mg_results`),
  HUD plateau : `_info_panel` (étoile/banque même taille), touches Tab / 1-6 ; encart Commandes = vraies touches (`stage.gd _keys`).
- Décor v0.27 : `_grass_patches`, `_ground_details` (touffes, fleurs en prairies), falaises facettées (`_sky_island`),
  volcan (`_lava_rock`, `_lava_cracks`, fumée/braises), rives (`_shore` : galets, nénuphars), reflets d'eau.

## Textes et alignement (v0.29) — à respecter pour tout nouveau texte
- `UI.text` centre les MAJUSCULES sur le point donné (base = y + 0,36·taille, mesuré juste pour Fredoka).
- Dans un panneau `UI.panel`/KitBox, centrer sur **`UI.face_center(rect)`** (pas `rect.get_center()`) : le bas du
  panneau est une bande foncée, la face claire est plus haut.
- Plusieurs lignes : **`UI.text_block(ci, centre, texte, taille, largeur, couleur)`** (coupe et centre le bloc), `UI.wrap_lines`,
  `UI.block_height`. Aligné à gauche : `UI.text_left` (renvoie la largeur → coller une icône après).
- Boutons Godot : `UI.btn(texte, cb, couleur, taille)` remonte le texte selon la taille (`button_box(col, pressed, fsize)`).
- Rubans : texte sur la bande avant (−0,21·h). Contour des textes transparent avec le texte (fondus propres).
- Lignes d'aide du plateau : `board.gd _hint(centre, texte)` (pastille sombre) ; pièces d'un joueur : `_coin_tag`.
- Cadres (PanelContainer) : marges 64/40/64/48. Bouton ♪ caché pendant les mini-jeux (touche M toujours active).
- Audit complet fait en v0.29 (tous les écrans) ; outils de captures dans le scratchpad : `bshot.sh` (plateau + événements JSON).
- **Script Python d'édition : toujours vérifier `s.count(old) == 1` avant `replace`** (un `replace("", …)` a déjà corrompu board.gd).

## À faire / à ne pas oublier
- Camille veut des mini-jeux **copiés fidèlement** sur les vrais Mario Party (règles, vue, déroulé) : vérifier le vrai jeu avant de l'adapter.
- Zips : Mac ~82 Mo, Windows ~59 Mo ; GitHub refuse au-delà de 100 Mo → passer à GitHub Releases si ça grossit.
- Pas encore fait : mini-jeux 2v2 / 1v3 selon la couleur des cases (proposé, pas choisi) ;
  alliés (Jamboree) ; mode « mini-jeux seulement » ; 2e plateau.
- Idées de mini-jeux en attente : Bowser's Big Blast, Hot Rope Jump, « jeu des marches 10 8 5 3 »,
  « poupées russes », Le bon cliché, Carrousel hanté, Course aux drapeaux, Abris-sandwichs.
- Jamais testé avec de vrais joueurs depuis v0.15 : équilibrage du triathlon, de la corde (TAP_CAP 11),
  de la mèche de la bombe, des rochers et du fantôme à vérifier.
- Messages « X a rejoint » : à droite (y=400), ou sur l'aperçu pendant un mini-jeu.
- Si on change un mini-jeu, refaire son aperçu (`assets/previews/<type>.png`, 1280×720).
