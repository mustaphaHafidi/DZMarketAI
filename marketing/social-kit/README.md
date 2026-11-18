# social-kit — visuels réseaux DZMarket

Kit vectoriel (SVG) pour @dzmarketpro (TikTok / Instagram / Facebook / LinkedIn).
SVG = léger, éditable au texte, zéro cache. Exporter en PNG seulement au moment de poster.

## Charte (reprise du repo)

- Vert dégradé `#0E9F6E → #0A7D57` · titres `#0A7D57` · texte `#1B4332` · fond `#F1FDF3`
- Logo = rond vert + coche blanche (`assets/branding/dzmarket_logo.svg`)
- URL affichée : `www.dzmarket.pro` · mention `Android · iPhone · Web`
- Ton repris de la page IG : poster bilingue, gros titre, 1 bouton CTA

## Fichiers

| Fichier | Format | Usage | Message |
|---|---|---|---|
| `01_ig-post_90s_fr.svg` | 1080×1080 | post IG/FB | « Publie ton annonce en moins de 90 s » |
| `02_ig-post_90s_ar.svg` | 1080×1080 | post IG/FB | « انشر إعلانك في أقل من 90 ثانية » |
| `03_ig-story_100vendeurs_fr.svg` | 1080×1920 | story / Reel cover | « 100 premiers vendeurs = gratuit » |
| `04_ig-story_100vendeurs_ar.svg` | 1080×1920 | story / Reel cover | « أول 100 بائع دخول مجاني » |
| `05_fb-link_tout-en-un_fr.svg` | 1200×630 | image de lien FB / OG | « Vends et livres au même endroit » |
| `06_linkedin-banner_fr.svg` | 1128×191 | bannière page LinkedIn | tagline marketplace |
| `07_tiktok-cover_fr.svg` | 1080×1920 | cover / 1re frame TikTok | « Arrête de courir après les infos client dans les DM » |

## Légendes à coller (reprises de `marketing/social-assets/*.txt`)

- **FR court** : Publie en moins de 90 s. Commande, chat et livraison dans la même app.
  Accès gratuit pour les 100 premiers vendeurs sérieux 👉 www.dzmarket.pro
- **AR court** : انشر في أقل من 90 ثانية. الطلبات، الشات والتوصيل في تطبيق واحد.
  دخول مجاني لأول 100 بائع جاد 👉 www.dzmarket.pro
- Hashtags : `#DZMarket #Algerie #تجارة_إلكترونية #Ecommerce #Startup #livraison`

## Exporter en PNG (au besoin, ne pas versionner les PNG)

```bash
# via navigateur headless déjà présent (Playwright/Chromium)
npx --yes svgexport 01_ig-post_90s_fr.svg 01_ig-post_90s_fr.png 1080:1080
# ou Inkscape : inkscape 01_ig-post_90s_fr.svg -o 01.png -w 1080 -h 1080
```

## Éditer

Texte modifiable directement dans le `.svg` (balises `<text>`). Les polices arabes
s'appuient sur `Segoe UI / Tahoma` (présentes sous Windows). Garder les lignes AR courtes.
