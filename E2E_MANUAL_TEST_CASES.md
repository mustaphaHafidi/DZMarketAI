# DZMarket - E2E Manual Test Cases (Release Pro)

Last update: 2026-03-03
Version: 2.0

## 1) Objectif
Valider end-to-end les flux critiques DZMarket apres les derniers correctifs (auth callback, i18n, bordereaux, labels, reminders job-runner, retours vendeur).

## 2) Environnement et comptes
- Environnement cible: `https://app.dzmarket.pro` + `https://api.dzmarket.pro`
- Langues a rejouer: FR puis AR
- Comptes minimaux:
  - Buyer test
  - Seller test (transporteurs configures)
  - Superadmin test

## 3) Regles d'execution
- Pour chaque cas: noter `PASS`/`FAIL`, capture, heure, commit SHA.
- Si `FAIL`: joindre erreur exacte + ecran + action utilisateur.
- Priorite de sortie:
  - P0: 100% PASS
  - P1: >= 95% PASS

## 4) Matrice de test

### A. Auth et session
| ID | Priorite | Cas | Resultat attendu |
|---|---|---|---|
| AUTH-01 | P0 | Login credentials valides | Connexion reussie, redirection home |
| AUTH-02 | P0 | Login mauvais mot de passe | Message erreur propre |
| AUTH-03 | P0 | Logout profil | Session invalidee, retour sign-in |
| AUTH-04 | P0 | Mot de passe oublie + lien email | Ouverture ecran reset, MAJ mot de passe OK |
| AUTH-05 | P0 | Callback `/auth/callback` | Pas d'ecran blanc, redirection attendue |
| AUTH-06 | P1 | Session restauree apres reload app | Utilisateur reste connecte |
| AUTH-07 | P1 | Lien legal depuis auth | Page legale accessible |
| AUTH-08 | P1 | Retour navigateur Android/web | Pas de boucle, pas de blank page |

### B. i18n FR/AR et affichage
| ID | Priorite | Cas | Resultat attendu |
|---|---|---|---|
| I18N-01 | P0 | Switch FR -> AR (auth/home/profile) | Tous textes traduits |
| I18N-02 | P0 | Switch AR -> FR | Tous textes traduits |
| I18N-03 | P0 | Parcours vendeur (mes ventes/dashboard/annonces) | Aucune cle brute `*.title`, `listing.*`, etc. |
| I18N-04 | P1 | Notifications en AR | Labels/tabs/messages traduits |
| I18N-05 | P1 | RTL sur ecrans AR | Alignements et direction corrects |
| I18N-06 | P1 | Textes accents FR | Pas de caracteres corrompus |

### C. Creation annonce vendeur
| ID | Priorite | Cas | Resultat attendu |
|---|---|---|---|
| LIST-01 | P0 | Ouvrir wizard ajout annonce | Etape 1 visible |
| LIST-02 | P0 | Upload photos | Preview OK |
| LIST-03 | P0 | Choix categorie | Valeur appliquee |
| LIST-04 | P0 | Details (titre+description+etat) | Validation OK |
| LIST-05 | P0 | Prix/stock/cout | Validation OK |
| LIST-06 | P0 | Localisation wilaya/commune | Selecteurs charges |
| LIST-07 | P0 | Livraison + options colis | Regles appliquees |
| LIST-08 | P0 | Publication annonce | Retour `Mes annonces`, item visible |

### D. Achat buyer et commande
| ID | Priorite | Cas | Resultat attendu |
|---|---|---|---|
| BUY-01 | P0 | Ouvrir fiche produit active | Fiche chargee |
| BUY-02 | P0 | Contact vendeur via chat | Room ouverte |
| BUY-03 | P0 | Achat direct (stock dispo) | Commande creee |
| BUY-04 | P0 | Test anti-achat de son propre produit | Action bloquee |
| BUY-05 | P1 | Offre prix + reponse vendeur | Messages systeme coherents |
| BUY-06 | P1 | Anti-duplicate commande (double clic) | Seconde tentative bloquee |
| BUY-07 | P1 | Checkout livraison standard | Adresse + mode valides |
| BUY-08 | P1 | Checkout livraison a convenir | Pas de bordereau force |
| BUY-09 | P1 | Commande visible buyer et seller | Etat coherent des deux cotes |

### E. Mes ventes, bordereaux, labels
| ID | Priorite | Cas | Resultat attendu |
|---|---|---|---|
| SHIP-01 | P0 | Mes ventes charge | Liste commandes visible |
| SHIP-02 | P0 | Generer bordereau Yalidine | Succès + tracking/label |
| SHIP-03 | P0 | Generer bordereau Ecotrack | Succès + tracking/label |
| SHIP-04 | P0 | Generer bordereau ZR Express | Succès + tracking/label |
| SHIP-05 | P0 | Generer bordereau Guepex | Succès + tracking/label |
| SHIP-06 | P0 | Ouvrir label commande 111/123 | PDF s'ouvre (pas page noire) |
| SHIP-07 | P0 | URL label | Domaine public `api.dzmarket.pro` |
| SHIP-08 | P1 | Message systeme label genere | Visible chat/notifications |
| SHIP-09 | P1 | Reminder label > 3 jours (test DB) | Message `order.system.label_reminder` |
| SHIP-10 | P1 | Reminder scan transporteur > 96h | Message `order.system.carrier_scan_reminder` |
| SHIP-11 | P1 | Annulation stale auto | Statut `cancelled` + message systeme |
| SHIP-12 | P1 | Actions seller apres refresh | Etat persistant |

### F. Notifications / chat
| ID | Priorite | Cas | Resultat attendu |
|---|---|---|---|
| NOTIF-01 | P0 | Ouvrir notifications FR | Liste lisible, pas de cles brutes |
| NOTIF-02 | P0 | Ouvrir notifications AR | Traduction complete |
| NOTIF-03 | P1 | Filtre tabs (systeme/commandes/offres/messages) | Filtrage correct |
| NOTIF-04 | P1 | Badge unread | Compteurs coherents |
| NOTIF-05 | P1 | Message order status dans chat | Evenement systeme present |
| NOTIF-06 | P1 | Conversation unique buyer/seller/product | Pas de doublon de room |

### G. Retours et dashboards vendeur
| ID | Priorite | Cas | Resultat attendu |
|---|---|---|---|
| RET-01 | P0 | Historique retours charge | Ecran sans erreur |
| RET-02 | P1 | Retour detecte via sync | Event retour visible |
| RET-03 | P1 | Dashboard vendeur | KPIs affiches sans cles i18n |
| RET-04 | P1 | Tableau livraisons | Statuts coherents |
| RET-05 | P1 | Parametres transporteur | Chargement + edition OK |

### H. Superadmin et securite
| ID | Priorite | Cas | Resultat attendu |
|---|---|---|---|
| ADM-01 | P0 | Acces moderation superadmin | Ecran accessible |
| ADM-02 | P0 | User standard vers moderation | Acces refuse |
| ADM-03 | P1 | Suspendre/reactiver utilisateur | Statut mis a jour |
| ADM-04 | P1 | Moderation annonce (approve/mask/block) | Etat persiste |
| ADM-05 | P1 | Ecran erreurs app | Liste chargee |

### I. Web responsive
| ID | Priorite | Cas | Resultat attendu |
|---|---|---|---|
| WEB-01 | P0 | Home web desktop | Layout propre, pas d'overlap |
| WEB-02 | P0 | Profil/notifications web | Pas de bandes blanches anormales |
| WEB-03 | P1 | Back navigateur web | Navigation stable |
| WEB-04 | P1 | Reload direct URL (path strategy) | Route charge sans `#` |

## 5) Suite de regression minimale (avant release)
Executer au minimum:
- AUTH-01, AUTH-04, AUTH-05
- I18N-01, I18N-03
- LIST-08
- BUY-03
- SHIP-02, SHIP-06, SHIP-07
- NOTIF-01, NOTIF-02
- RET-01
- WEB-01

## 6) Resultat final de campagne
Template de synthese:
- Date:
- Build/version:
- Testeur:
- P0 PASS/FAIL:
- P1 PASS rate:
- Bloquants:
- Decision release: GO / NO-GO

## 7) Rappel qualité
Toute regression sur auth, checkout, bordereau, label ou i18n est `NO-GO`.
