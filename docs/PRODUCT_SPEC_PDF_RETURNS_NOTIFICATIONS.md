# DZMarket Product Spec: PDF, Retours DZMarket, Notifications

Updated: 2026-04-19
Status: approved product direction
Scope: web + mobile

## 1) Objectif

Ce document fixe 3 decisions produit:

1. regle de retention du bordereau PDF
2. definition exacte de l'historique retours visible cote vendeur
3. version simplifiee de l'ecran notifications

Le but est d'aligner produit, UX et implementation sans ambiguity.

## 2) Hors scope

- aucun scoring acheteur externe
- aucun historique acheteur hors DZMarket
- aucun acces buyer au PDF complet par defaut
- aucune refonte backend complete dans ce document

## 3) Regle PDF bordereau

### 3.1 Regle metier

- Le bordereau PDF est conserve 6 mois a partir de sa date de generation.
- Le PDF reste consultable pendant ces 6 mois, quel que soit l'etat ulterieur de la commande.
- Le lien de consultation expose a l'utilisateur doit etre un lien signe temporaire regenere a la demande.
- Le fichier source doit rester prive dans le stockage DZMarket.

### 3.2 Roles autorises

- Vendeur: acces autorise pendant 6 mois
- Support/Admin: acces autorise pendant 6 mois minimum
- Acheteur: pas d'acces PDF complet par defaut

### 3.3 Etats ou le PDF doit rester visible

- label_ready / validated
- shipped
- out_for_delivery
- delivered
- returned_to_sender
- cancelled si le bordereau a deja ete genere

### 3.4 Expiration

- A J+6 mois apres generation:
  - le PDF peut etre supprime du stockage
  - les metadonnees de commande et d'expedition restent conservees
- Si une commande est en litige/support actif, la purge doit pouvoir etre retardee manuellement

### 3.5 Texte UI recommande

FR:
- `Le bordereau reste disponible pendant 6 mois apres sa generation.`

AR:
- `تبقى البوليصة متاحة لمدة 6 أشهر بعد إنشائها.`

### 3.6 Critères d'acceptation

- Un vendeur peut rouvrir un bordereau 1 jour, 30 jours et 5 mois apres sa generation.
- Un bordereau deja genere reste visible meme si la commande est livree ou retournee.
- Si un lien signe expire, l'application regenere un nouveau lien sans erreur visible pour le vendeur.
- Aucune URL publique permanente ne doit etre exposee a l'utilisateur.

## 4) Historique Retours DZMarket

### 4.1 Definition produit

L'historique retours visible cote vendeur concerne uniquement les commandes passees sur DZMarket.

Ce n'est pas:
- un historique global de l'acheteur
- un score externe
- une verite hors plateforme

C'est:
- un signal logistique interne DZMarket
- base sur les commandes creees sur DZMarket
- enrichi au fil du temps par les evenements transporteurs detectes sur DZMarket

### 4.2 Evenements sources autorises

Un retour DZMarket peut etre cree uniquement a partir d'une commande DZMarket lorsque le systeme detecte un statut comme:

- returned_to_sender
- not_claimed
- refused
- delivery_failed si confirme par le flux transporteur ou support

### 4.3 Donnees a conserver par retour

Minimum:

- order_id
- buyer_id
- seller_id
- courier_id
- tracking_number
- status
- returned_at

Enrichissements recommandes:

- shipped_at
- first_carrier_scan_at
- out_for_delivery_at
- last_known_status
- source
  - carrier_tracking
  - system_rule
  - support_manual
- return_reason_label si connue

### 4.4 Presentation produit

V1 vendeur:

- afficher un signal court dans `Mes ventes`
- afficher uniquement l'historique DZMarket
- ne pas utiliser de wording agressif

Wording recommande:

FR:
- `Retours DZMarket : {count} sur 12 mois`
- `Base uniquement sur les commandes passees sur DZMarket.`

AR:
- `مرتجعات DZMarket: {count} خلال 12 شهرًا`
- `يعتمد فقط على الطلبات التي تمت عبر DZMarket.`

### 4.5 Comportement attendu

- Le vendeur voit un compteur de retours DZMarket pour l'acheteur concerne.
- Ce compteur n'empeche pas automatiquement la vente.
- Ce compteur sert uniquement d'aide a la decision logistique.
- Le systeme ne doit pas laisser croire a un historique hors DZMarket.

### 4.6 Evolution recommandee

V2:

- bouton `Voir le detail`
- liste des retours DZMarket de cet acheteur
- pour chaque ligne:
  - commande
  - date
  - transporteur
  - statut retour
  - tracking

### 4.7 Critères d'acceptation

- Un retour detecte sur une commande DZMarket alimente bien l'historique du buyer concerne.
- Le vendeur ne voit jamais un libelle pouvant etre interprete comme un score acheteur global.
- Le texte d'aide mentionne explicitement que la source est limitee a DZMarket.
- Le compteur 6 mois et 12 mois est coherent avec les evenements internes stockes.

## 5) Notifications simplifiees

### 5.1 Problematique

L'ecran notifications actuel melange:

- liste inbox
- filtres unread
- filtres categories
- preferences
- mute temporaire

Cela fonctionne, mais l'UX est plus complexe que necessaire pour un usage marketplace grand public.

### 5.2 Decision UX

L'ecran principal `Notifications` doit devenir une inbox simple.

L'ecran secondaire `Parametres notifications` doit contenir les preferences et le mute.

### 5.3 Ecran principal: contenu autorise

- titre `Notifications`
- action `Tout marquer comme lu`
- filtre `Toutes`
- filtre `Non lues`
- liste chronologique des notifications

Ne pas afficher en permanence sur l'ecran principal:

- categories chat/offres/commandes/systeme
- switches de preferences
- mute 8h

### 5.4 Ecran secondaire: Parametres notifications

Contenu:

- Messages
- Offres
- Commandes
- Systeme
- Mettre en pause 8h
- Reactiver

### 5.5 Textes UI recommandes

Main screen FR:

- `Notifications`
- `Toutes`
- `Non lues`
- `Tout marquer comme lu`

Main screen AR:

- `الإشعارات`
- `الكل`
- `غير المقروءة`
- `تحديد الكل كمقروء`

Settings screen FR:

- `Parametres notifications`
- `Messages`
- `Offres`
- `Commandes`
- `Systeme`
- `Mettre en pause 8h`
- `Reactiver`

Settings screen AR:

- `إعدادات الإشعارات`
- `الرسائل`
- `العروض`
- `الطلبات`
- `النظام`
- `إيقاف لمدة 8 ساعات`
- `إعادة التفعيل`

### 5.6 Regles de navigation

- Depuis le profil ou la barre principale, l'utilisateur ouvre directement l'inbox simple.
- Depuis l'inbox, un bouton ou icone `Parametres` ouvre les preferences.
- Le mute temporaire ne doit pas encombrer l'inbox principale.

### 5.7 Critères d'acceptation

- L'utilisateur peut lire ses notifications sans passer devant des reglages.
- L'utilisateur peut filtrer rapidement entre `Toutes` et `Non lues`.
- Les preferences restent accessibles en un clic depuis l'inbox.
- Les categories ne sont plus exposees en permanence sur l'ecran principal.
- Les textes FR/AR ne montrent aucune cle technique.

## 6) References implementation actuelles

Historique retours:

- [lib/src/features/orders/seller_orders_page.dart](/C:/src/dzmarket/lib/src/features/orders/seller_orders_page.dart:273)
- [lib/src/services/buyer_return_service.dart](/C:/src/dzmarket/lib/src/services/buyer_return_service.dart:5)
- [supabase.sql](/C:/src/dzmarket/supabase.sql:2802)
- [supabase/functions/job-runner/index.ts](/C:/src/dzmarket/supabase/functions/job-runner/index.ts:580)

Notifications:

- [lib/src/features/notifications/notifications_page.dart](/C:/src/dzmarket/lib/src/features/notifications/notifications_page.dart:207)
- [lib/src/services/notification_inbox_service.dart](/C:/src/dzmarket/lib/src/services/notification_inbox_service.dart:11)
- [lib/src/services/i18n.dart](/C:/src/dzmarket/lib/src/services/i18n.dart:623)

PDF bordereau:

- [lib/src/services/label_url_service.dart](/C:/src/dzmarket/lib/src/services/label_url_service.dart:15)
- [lib/src/services/shipping_service.dart](/C:/src/dzmarket/lib/src/services/shipping_service.dart:2679)
- [lib/src/features/chat/chat_room_page.dart](/C:/src/dzmarket/lib/src/features/chat/chat_room_page.dart:132)

## 7) Decision resume

- Bordereau PDF: retention 6 mois
- Historique retours: DZMarket uniquement, jamais hors plateforme
- Notifications: inbox simple + reglages separes
