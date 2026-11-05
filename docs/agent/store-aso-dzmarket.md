# DZMarket - ASO arabe et francais

Mise a jour : 2026-11-05. Cette fiche prepare les champs de recherche. Elle
ne vaut pas publication : verifier chaque fiche publique apres validation.

## Google Play

Ajouter ou verifier les deux localisations dans `Store listings` puis publier
les changements de fiche seulement.

| Locale | Titre (30) | Description courte (80) |
| --- | --- | --- |
| Arabe | `DZMarket | سوق الجزائر` | `سوق جزائري للبيع والشراء مع دردشة وتوصيل وتتبع الطلبات.` |
| Francais | `DZMarket | Annonces Algérie` | `Achetez, vendez, discutez et suivez vos livraisons en Algérie.` |

Ne pas promettre une position sur des recherches generiques. Verifier, hors
console, la page `hl=ar` et `hl=fr` apres publication.

## App Store

Les champs de recherche d'une version deja publiee exigent une nouvelle
version et un nouveau build. Associer les textes ci-dessous a la prochaine
release mobile contenant le correctif de selection d'images; ne pas tenter de
reutiliser le build 43 deja distribue.

| Locale | Nom (30) | Sous-titre (30) | Mots-cles (100) |
| --- | --- | --- | --- |
| Arabe | `DZMarket | سوق الجزائر` | `بيع وشراء مع دردشة وتوصيل` | `إعلانات,متجر,سوق إلكتروني,تسوق,بيع مستعمل,شراء منتجات,طلبات,شحن,الجزائر,DZ Market` |
| Francais | `DZMarket | Annonces Algérie` | `Vendre, acheter, livrer` | `annonces,vente,achat,occasion,produits,livraison,chat,Algerie,marketplace` |

Verifier aussi une URL de confidentialite pour chaque locale, enregistrer un
champ a la fois, puis soumettre la nouvelle version avec un build frais.

## Web

- `web/robots.txt` et `web/sitemap.xml` sont versionnes et doivent repondre
  HTTP 200 apres tout deploiement web.
- Le sitemap ne doit contenir que les pages publiques utiles; ne pas ajouter
  les parcours d'authentification.
- Dans Search Console, soumettre `https://www.dzmarket.pro/sitemap.xml` une
  fois apres le prochain deploiement. Attendre l'indexation avant de refaire
  une demande identique.
