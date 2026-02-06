1. Objectif
   - Valider l’intégration Ecotrack de bout en bout (création commande, validation, bordereau, suivi).
   - Vérifier la synchro UI: Mes ventes, Chat, suivi des statuts.

2. Pré-requis
   - Un compte vendeur Ecotrack avec token API valide.
   - Un produit actif dans DZMarket (stock > 0).
   - Un acheteur différent du vendeur.
   - Vendeur a configuré ses credentials Ecotrack dans l’app (API ID / token / nom expéditeur).

3. Données de test (exemple)
   - Buyer: test@gmail.com
   - Seller: test2@gmail.com
   - Product: id 21 (owner = seller)
   - Order: crée via l’app (id généré)
   - Wilaya: M’Sila (code_wilaya=28)
   - Commune: M’Sila (doit exister via /get/communes)
   - Montant: 300 DZD
   - Poids: 2 kg
   - Dimensions: 30 x 30 x 30
   - Stop desk: false (domicile)

4. Cas de test (UI)
   4.1 Buyer crée une commande
   - Action: Acheter → valider la commande.
   - Attendu:
     - La commande est créée (pas d’erreur 403).
     - Redirection vers chat room de la commande.
     - Message système: “Commande enregistrée, en attente de validation vendeur”.

   4.2 Seller génère le bordereau
   - Action: Mes ventes → ouvrir commande → Générer bordereau.
   - Attendu:
     - Création expédition OK.
     - Message système “validation + bordereau généré” dans le chat.
     - Label visible côté vendeur uniquement.

   4.3 Buyer ne voit pas le label
   - Action: ouvrir le chat côté buyer.
   - Attendu:
     - Message système visible.
     - Aucune section “label/bordereau” affichée.

   4.4 Mes ventes auto-refresh
   - Action: après génération, rester sur Mes ventes.
   - Attendu:
     - Statut et boutons mis à jour sans sortir de l’écran.

5. Cas de test (API directe)
   5.1 Validation token
   - GET {{url}}/api/v1/validate/token?api_token={{api_token}}
   - Attendu: VALID_TOKEN

   5.2 Wilayas & Communes
   - GET {{url}}/api/v1/get/wilayas
   - GET {{url}}/api/v1/get/communes?wilaya_id=28
   - Attendu: commune M’Sila présente, has_stop_desk conforme.

   5.3 Create order (Ecotrack)
   - POST {{url}}/api/v1/create/order?... (voir ecotrack.md)
   - Attendu: tracking renvoyé, status initial.

   5.4 Label
   - GET {{url}}/api/v1/get/order/label?tracking=...
   - Attendu: PDF renvoyé.

6. Points de contrôle / Debug
   - Si erreur “Unknown from_wilaya_name” → corriger mapping (wilaya_id obligatoire).
   - Si 403 dans create_shipment → vérifier que l’appel est côté vendeur + service role.
   - Si doublon messages → vérifier dedupe_key.

7. Nettoyage
   - Ne pas supprimer une commande validée.
   - Utiliser DELETE order uniquement si non validée (avant expédition).
