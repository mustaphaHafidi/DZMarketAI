1. Objectif
   - Valider l'integration Ecotrack de bout en bout (commande, validation, bordereau, suivi).
   - Verifier la synchro UI: Mes ventes, Chat, statuts.

2. Pre-requis
   - Compte vendeur Ecotrack avec token valide.
   - Produit actif (stock > 0).
   - Acheteur different du vendeur.
   - Vendeur a configure ses credentials Ecotrack dans l'app.

3. Donnees de test (exemple)
   - Buyer: test@gmail.com
   - Seller: test2@gmail.com
   - Product: id 21 (owner = seller)
   - Wilaya: M'Sila (code_wilaya=28)
   - Commune: M'Sila (doit exister via /get/communes)
   - Montant: 300 DZD
   - Poids: 2 kg
   - Dimensions: 30 x 30 x 30
   - Stop desk: false (domicile)

4. Cas de test (UI)
   4.1 Buyer cree une commande
   - Action: Acheter -> valider la commande.
   - Attendu:
     - Commande creee (pas d'erreur 403).
     - Redirection vers chat room de la commande.
     - Message systeme: "Commande enregistree, en attente de validation vendeur".

   4.2 Seller genere le bordereau
   - Action: Mes ventes -> ouvrir commande -> Generer bordereau.
   - Attendu:
     - Creation expedition OK.
     - Message systeme "validation + bordereau genere" dans le chat.
     - Label visible cote vendeur uniquement.

   4.3 Buyer ne voit pas le label
   - Action: ouvrir le chat cote buyer.
   - Attendu:
     - Message systeme visible.
     - Pas de bouton/section label.

5. Cas de test (API directe)
   5.1 Validation token
   - GET {{url}}/api/v1/validate/token?api_token={{api_token}} -> VALID_TOKEN

   5.2 Wilayas & Communes
   - GET {{url}}/api/v1/get/wilayas
   - GET {{url}}/api/v1/get/communes?wilaya_id=28

   5.3 Create order
   - POST {{url}}/api/v1/create/order?... (voir ecotrack.md)

   5.4 Label
   - GET {{url}}/api/v1/get/order/label?tracking=...

6. Debug
   - 403 create_shipment: verifier appel cote vendeur + service role.
   - Doublon messages: verifier dedupe_key.
