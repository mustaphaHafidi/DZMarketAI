# ZR Express — MCP Playwright Test Scenario (Web)

## 1) Objectif
Valider la création de commande ZR Express côté acheteur et la génération du bordereau côté vendeur, via l’UI web (MCP Playwright), sans erreur “Phone_Number1 must be a valid international phone number”.

## 2) Pré‑requis
- App web accessible sur `http://127.0.0.1:9105/` (web-server Flutter).
- ZR Express configuré côté vendeur dans “Paramètres transporteurs”.
- Produit test : **ID 26** (prix ~300 DA, stock disponible).
- Comptes de test :
  - Acheteur : `test1@gmail.com`
  - Vendeur : `test2@gmail.com`
  - **Mot de passe** : conserver hors repo (ne pas stocker ici).

## 3) Scénario MCP — Acheteur (test1)
1. Ouvrir l’app web (`http://127.0.0.1:9105/`).
2. Se connecter en **acheteur**.
3. Ouvrir le produit **ID 26** (ex. “chaussures”).
4. Cliquer **Acheter** → mode **Livraison COD** → **ZR Express**.
5. Remplir le formulaire ZR :
   - Nom / Prénom : `Test` / `Test`
   - Téléphone 1 : `0664589785` (local)
   - Daïra : `M'Sila`
   - Adresse : `2 cite silmane amirat`
   - Wilaya destinataire : **MSila**
   - Commune destinataire : **M'sila**
   - Produits : `Produit #26`
   - Prix : `300`
   - Poids : `2`
   - Dimensions : `30 × 30 × 30`
6. Choisir **Wilaya de départ (Expéditeur)** : **MSila**.
7. Accepter les CGU → **Confirmer** → **Valider et payer**.
8. Vérifier : redirection vers la **Conversation** (room commande).

## 4) Scénario MCP — Vendeur (test2)
1. Se déconnecter puis se reconnecter en **vendeur**.
2. Profil → **Mes ventes**.
3. Trouver la commande associée au produit **26** (ex. “Commande 63”).
4. Cliquer **Générer bordereau + expédier**.
5. Vérifier :
   - Toast / message “Expédition déclenchée avec bordereau”.
   - Statut commande bascule sur **Expédié**.
6. Ouvrir **Chat** de la commande : vérifier le message système “commande validée + bordereau généré”.

## 5) Résultat attendu
- Aucune erreur ZR Express sur le numéro (format international ok).
- Bordereau généré avec tracking + label.
- Message système disponible dans la room (ordre normal).

## 6) Observations (dernier run MCP)
- Le flux **ZR Express** a fonctionné côté web (achat → commande → bordereau).
- Les erreurs `rpc/post_order_event` / `rpc/send_message` apparaissaient avant la mise en place des grants.
- Après suppression des envois **client‑side** et ajout des **grants RPC** :
  - Moins de doublons.
  - Les messages système doivent désormais venir du **serveur** (create_order/create_shipment).

## 8) Dernier run MCP (2026‑02‑09)
- Connexion acheteur `test1@gmail.com`.
- Tentative de commande **Produit 26** → bloquée par la règle anti‑duplicat (commande déjà créée < 5 min).
- Côté vendeur `test2@gmail.com` : **Commande 64** → génération bordereau OK (toast “Expédition déclenchée…”).
- Statut commande passé en **Expédié**.
- Chat de la commande : messages système visibles (créée / validée).
- **Point à vérifier** : lien bordereau non affiché (payload `label_url` absent).
- **Logs navigateur** : encore un appel `rpc/send_message` en erreur (à corriger si persiste).

## 7) Notes techniques
- ZR Express accepte uniquement les numéros locaux **05/06** → normalisés en `+213…`.
- Si téléphone commence par **07**, l’API ZR Express retourne 400.
- Les wilayas/communes ZR proviennent de `courier-locations` (pas de fallback DB).

## 9) MCP run (2026-02-09 rebuild)
- Buyer: test@gmail.com
  - Product xbox (id 26) -> Acheter -> ZR Express.
  - Phone fixed to 0664589785, preview +213664589785.
  - Order confirmed -> Chat opened.
  - Result: no "commande enregistree" system message in the room.
- Seller: test2@gmail.com
  - Mes ventes -> Commande 75 -> Generer bordereau.
  - Toast OK, status Expedie.
  - Chat seller: "Commande expediee" message + "Ouvrir bordereau" visible.
  - Browser errors: rpc/post_order_event and rpc/send_message failed during shipment.
- Buyer chat:
  - "Commande expediee" visible.
  - Label link hidden for buyer (OK).
  - Creation message still missing (KO).
