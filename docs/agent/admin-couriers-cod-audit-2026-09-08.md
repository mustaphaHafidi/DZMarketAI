# Audit admin, COD, transporteurs et conversations - 2026-09-08

## Perimetre

Audit en lecture seule du depot, des fonctions et de la production DZMarket.
Aucun secret, contenu JSONL ancien, ecriture SQL, creation d'expedition ou
deploiement n'a ete effectue. Les recommandations ci-dessous sont ordonnees
pour limiter les regressions.

## Verdict

- P0: limiter les profils publics. L'anonyme peut actuellement lire email,
  telephone, role, statut et coordonnees de profils.
- P1: corriger la configuration Ecotrack par societe/tenant; les endpoints
  actuellement configures repondent 404.
- P1: conserver l'acces complet des superadmins, mais fiabiliser la page
  admin, la pagination, les confirmations et l'audit des actions.
- P1: le parcours live est COD; aucun `payment_intents` n'est present. Le
  chemin de paiement mock reste toutefois dans le code et doit etre desactive
  avant toute livraison.
- P2: le bouton de contact vendeur peut persister un salon avant le premier
  message. L'annulation ou une offre vide ne cree pas ce salon dans le chemin
  actuel de l'offre.

## Donnees live, instantane

- 402 profils, 144 produits, 179 commandes et 122 conversations.
- 19 conversations sont sans message; 6 ont ete creees sur les 30 derniers
  jours. Elles ne doivent pas etre supprimees automatiquement sans politique.
- Les commandes sont COD et `payment_intents` est vide.
- 56 erreurs sur les 30 derniers jours, dont 37 temps reel/websocket; 23
  echecs de push, principalement sans token appareil.
- Le job runner serveur est actif chaque minute par cron. Ne pas ajouter un
  cron GitHub sans idempotence, sous peine de doublons.

## Profils et administration

La lecture anonyme des profils doit passer par une projection publique minimale
(nom public, avatar, zone utile), avec vue privee pour le proprietaire et vue
admin autorisee pour les superadmins. Les trois superadmins actifs conservent
leur acces metier complet; cela ne justifie pas d'exposer les donnees a tous.

La page admin charge jusqu'a 400 profils sans vraie pagination alors que le
live en contient 402. Les panneaux sont charges ensemble: une erreur peut
vider toute la page. Les actions de moderation n'ont pas de confirmation,
raison saisie ni journal d'audit complet. Le blocage archive le produit et la
reapprobation ne restaure pas forcement l'etat d'archive precedent.

Ameliorations recommandees: titre produit en premier, nom vendeur et miniature;
ID secondaire copiable; recherche/pagination cote serveur; etat de chargement
independant par panneau; confirmation avec raison; audit immuable avec acteur,
cible, ancienne/nouvelle valeur et horodatage; restauration explicite de
l'archive precedente.

## Paiement COD

Le bouton de paiement et l'appel applicatif a `createMockPaymentIntent` ont ete
retires du parcours commandes. Le service conserve une methode de compatibilite
qui refuse maintenant explicitement tout paiement mock; aucune commande ne
peut donc etre marquee payee par ce faux flux.

Ordre sur: masquer/desactiver le bouton de paiement en mode COD; faire evoluer
la commande par statuts serveur (confirmee, expediee, livree, encaissee,
remise); ne jamais accepter du client la preuve d'encaissement. Toute future
integration PSP doit avoir webhook signe, idempotence et separation du cash
livraison.

## Transporteurs

| Fournisseur | Test lecture seule | Conclusion |
| --- | --- | --- |
| Guepex | 2/2 HTTP 200 authentifies | OK |
| Yalidine | 2/2 HTTP 200 | OK; conserver la normalisation de paire inversee |
| ZR Express | 1/2 HTTP 200, 1/2 HTTP 401 | Un compte invalide a corriger |
| Ecotrack | 2/2 HTTP 404 sur l'hote/endpoints actuels | Configuration non validee |

Les deux comptes Ecotrack pointent vers `https://api.ecotrack.dz` et les
routes testees `/api/v1/validate/token` et `/api/v1/get/fees` repondent 404.
Cela ne prouve pas que les tokens sont invalides: l'URL de societe, le tenant
ou les routes peuvent etre mauvais. Il faut obtenir pour chaque societe l'hote
officiel et le tenant, puis propager la meme configuration verifiee dans
validation, frais, wilayas, creation, etiquette, suivi et cache.

Le modele actuel ne permet qu'un compte par vendeur et transporteur. Ajouter
un identifiant d'instance/tenant si plusieurs societes Ecotrack sont
necessaires. La validation doit etre faite cote serveur; le client ne doit
pas s'auto-marquer `valid`. Ne jamais renvoyer les tokens et n'autoriser que
des hotes HTTPS approuves, sans fallback silencieux.

## Conversations et offres

`_makeOffer` quitte proprement pour annulation, vide ou montant invalide. En
revanche `_contactSeller` appelle `ensureConversation` avant le premier
message. Cela explique les salons vides sans attribuer a tort leur creation a
l'annulation d'offre.

Le parcours contact envoie maintenant un premier message avant la navigation,
et le parcours offre valide demande le meme comportement. Une annulation, une
offre vide ou invalide sort toujours avant toute creation de salon.

Correction recommandee cote backend: creer le salon dans la meme operation que le premier
message valide ou l'offre valide, reutiliser un salon existant, et tester
annulation, tap hors modal, vide, montant invalide, double envoi, echec/retry
et conversation preexistante. Conserver les 19 salons actuels pour revue; ne
pas les supprimer automatiquement.

## Ordre de remediation sur staging

1. Projection publique/RLS des profils et verification des acces admin.
2. Pagination, isolation des erreurs, confirmation et audit des actions admin.
3. Instance/tenant Ecotrack avec URL fournie par la societe, puis tests
   validation/frais/locations/expedition/suivi.
4. Suppression du faux paiement du parcours COD et tests de statuts serveur.
5. Creation de conversation differee et tests d'offres.
6. Metriques d'erreurs, tokens push, alertes job runner et verification des
   doublons.

## Limites et sources

Les chiffres sont un instantane agrege et ne constituent pas une preuve de
blocage individuel. Aucun changelog officiel actuel de transporteur n'a ete
confirme. Les documents d'integration externes indiquent que des URLs/tenants
peuvent varier selon la societe, mais ne remplacent pas la confirmation du
fournisseur: https://feeef.dev/docs/api/delivery et
https://www.dzbuild.com/docs/couriers/overview.
