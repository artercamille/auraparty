<p align="center"><img src="docs/logo.png" width="520" alt="Aura PARTY"></p>

# Aura PARTY

Un party game 2D façon Mario Party, jusqu'à **8 joueurs en ligne**, chacun sur son PC Windows.
Une grande île volante avec des carrefours, des objets, une boutique, des duels, des étoiles à acheter, et 10 mini-jeux pour se trahir entre potes.

## ⬇️ Télécharger

### **[Télécharger Aura PARTY v0.16 pour Windows](https://github.com/artercamille/auraparty/raw/main/telecharger/AuraParty.zip)**

Dézippe le fichier, puis lance `AuraParty.exe`.
Si Windows affiche « Windows a protégé votre ordinateur » : *Informations complémentaires* → *Exécuter quand même*.

Tout le monde doit avoir **la même version**. Le jeu affiche un bouton sur l'écran d'accueil quand une nouvelle version sort ici.

## 🎮 Jouer ensemble

1. Celui qui héberge clique sur **Créer une partie** et donne son adresse IP aux autres.
2. Les autres collent cette IP et cliquent sur **Rejoindre**.

Pour se connecter, au choix :
- **Radmin VPN** (gratuit, le plus simple) : tout le monde rejoint le même réseau, l'IP commence par `26.`
- **Ouvrir le port** sur la box de l'hôte : **UDP 7777** vers son PC, puis donner son IP publique.

Dans le salon, l'hôte peut aussi lancer directement un mini-jeu pour le tester, sans passer par le plateau.

## ⭐ Règles

- Chacun commence avec 10 pièces au **village**. À ton tour : lancer le dé (1 à 10), utiliser un objet, ou regarder la carte (**Tab**).
- L'île a 6 zones (village, forêt, lac, château, volcan, plage) et des **carrefours** : à toi de choisir ta route (le pont du château coûte 5 pièces).
- En passant sur l'**étoile** avec 20 pièces, on l'achète. Elle s'envole ensuite ailleurs.
- Les cases : bleue **+3**, rouge **−3**, **?** événement de la zone, **!** carte chance, cadeau (objet gratuit), **VS** duel 1 contre 1, piège (−10 pièces dans la banque), banque, boutique, tuyau (téléportation).
- 8 objets (3 max dans le sac) : champignon, double dé, triple dé, dé pipé, champi poison, cloche fantôme, échangeur, tuyau doré.
- Après chaque tour de table : un mini-jeu au hasard. Les meilleurs gagnent des pièces, et le gagnant joue en premier au tour suivant.
- Le dernier mini-jeu rapporte une **étoile** au gagnant. À la fin, 3 **étoiles bonus** sont distribuées : Roi des mini-jeux, Pluie de pièces, Pas de chance.
- Le plus d'étoiles gagne, puis le plus de pièces.

## 🕹️ Les mini-jeux

| Mini-jeu | Principe |
|---|---|
| Gare aux blocs ! | Des blocs s'écrasent du ciel : regarde leur ombre. Dernier debout gagne. |
| Coup de tampon ! | Saute et retombe pour peindre le sol à ta couleur. |
| La bonne clé ! | 5 portes, 3 clés devant chacune, une seule ouvre (différente pour chacun). |
| Le grand parcours ! | Course de plateformes : pics, scies, plateformes mobiles. |
| Le rocher fou ! | Fuis le rocher géant qui accélère, sur une piste de plus en plus dure. |
| Défilé de bûches ! | Saute par-dessus les bûches sur un pont suspendu, gare aux piques. |
| Quiz sous le chapiteau ! | Retiens les ballons, puis saute sur l'estrade de la bonne réponse. |
| Grand Prix Aura ! | Course de karts vue de dessus, 3 tours, objets et turbos. |
| Mini-triathlon ! | Pagaie, vélo puis haies, chacun dans son couloir : alterne les touches le plus vite possible. |
| Fusées en folie ! | Course de fusées jusqu'à la Lune en slalomant entre astéroïdes et soucoupes. |

**Commandes** : plateau : Espace pour valider, ← → pour choisir, Tab pour la carte, 1 à 6 pour les émotes · M pour couper la musique · mini-jeux : bouger Q/D ou flèches · sauter Espace (double saut) · pousser Maj/X/E/clic · plein écran F11.
Kart : Z/↑/Espace pour accélérer, S/↓ pour freiner, Q/D pour tourner, Maj/X/clic pour l'objet.
Triathlon : Q/D en alternance (pagaie), Z/S en alternance (vélo), Espace (haies). Fusées : Q/D pour slalomer, Z pour accélérer, S pour freiner.

## 📸 Captures

<p align="center">
<img src="docs/plateau.png" width="48%"> <img src="docs/village.png" width="48%">
<img src="docs/chateau.png" width="48%"> <img src="docs/kart.png" width="48%">
<img src="docs/triathlon.png" width="48%"> <img src="docs/fusees.png" width="48%">
<img src="docs/buches.png" width="48%"> <img src="docs/quiz.png" width="48%">
</p>

## 🛠️ Le code

Le jeu est fait avec [Godot 4.3](https://godotengine.org/). Le projet complet est dans le dossier [`jeu/`](jeu/) :
ouvre `jeu/project.godot` dans Godot 4.3 pour le modifier ou l'exporter.

## Crédits

- Graphismes et sons : [Kenney](https://kenney.nl) (licence CC0)
- Musiques : [FreePD](https://freepd.com) (domaine public)
- Police : Fredoka (SIL Open Font License)
