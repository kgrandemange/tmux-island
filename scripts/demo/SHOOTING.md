# Plan de tournage — vidéo de présentation de TmuxIsland

Objectif : ~50 secondes, **sans voix**, qui montrent le clic qui t'amène sur le bon pane tmux. Les sous-titres et le
montage sont ajoutés après coup. Tout se passe avec des **projets fictifs** (shop-api, shop-web, shop-infra) : tes vraies
sessions sont masquées pendant la démo.

## 1. Préparer l'écran (5 min)

- Installe la dernière version : `./scripts/install.sh`
- Bureau propre : fond d'écran simple (idéalement sombre), icônes du bureau masquées, **Dock masqué** (`⌥⌘D`).
- Ferme toutes les applis inutiles, active un **Mode Concentration macOS** (pas de notification pendant le tournage).
- Réglages d'enregistrement : `⇧⌘5` › **Options** › micro « Aucun », **Afficher les clics de la souris** activé.
- Zone filmée : **tout l'écran** (la notch en haut, le terminal au centre). Si tu as un écran externe, filme celui du MacBook (avec la notch).
- Terminal : police **grande (16–18 pt)** pour que le texte soit lisible en vidéo, fenêtre centrée.

## 2. Lancer la démo

```bash
./scripts/demo/demo.sh start       # ouvre un terminal attaché à la démo + l'île en mode démo
```

Vérifie : l'île montre **3 points orange** et les sessions `api`, `infra`, `web`. Aucune de tes vraies sessions.

## 3. Déroulé (le décompte part du « GO »)

Depuis **un autre terminal que celui filmé**, lance :

```bash
./scripts/demo/demo.sh play 10     # décompte de 10 s : le temps de lancer l'enregistrement (⇧⌘5)
```

| Temps | Ce qui se passe seul | Ce que **tu** fais |
|---|---|---|
| 0:00 | 3 points orange, le terminal affiche `api › payments` qui travaille | Rien : laisse 5 s pour installer l'image |
| 0:09 | `infra` termine : **toast vert « shop-infra terminé »** + son | Laisse le toast 2 s à l'écran |
| 0:12 | | **Clique sur le toast** → le terminal passe sur `infra › terraform` (« Apply complete ! ») |
| 0:24 | `web` demande une permission : toast rouge « shop-web attend » | |
| 0:26 | | **Survole l'île** pour la déplier ; reste 2 s sur la ligne `web` (l'aperçu du pane s'ouvre) |
| 0:30 | | **Clique sur « 1 · Yes »** : l'agent reprend (visible dans l'île : « en cours ») |
| 0:38 | `web` termine (« 42 tests passed ») | **Clique sur la ligne `web`** → le terminal saute sur `web › checkout-ui` |
| 0:44 | | **Clique sur la puce `tests`** de la session `api` → le terminal change de session |
| 0:50 | | Sors la souris de l'île : elle se replie en 3 points. **Arrête l'enregistrement** |

Pas de panique si tu rates un clic ou si ça traîne : le montage coupe et accélère. Pour recommencer à zéro :

```bash
./scripts/demo/demo.sh stop && ./scripts/demo/demo.sh start
```

## 4. Terminer

```bash
./scripts/demo/demo.sh stop        # nettoie tout et relance ta vraie app
```

Envoie-moi le chemin du fichier `.mov` (par défaut sur le Bureau) : je fais le montage (découpe, accélérés,
zoom sur la notch, sous-titres, export mp4 + WebM + GIF) et je l'intègre à la page de présentation.
