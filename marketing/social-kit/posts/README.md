# posts — visuels à publier (feed DZMarket)

Posts prêts à publier pour @dzmarketpro (Instagram / Facebook / TikTok photo / LinkedIn).
Pas de couverture ni photo de profil ici — que du contenu de publication.
SVG = léger, éditable au texte. Les PNG prêts à publier sont dans `png/`
(1080×1080, ~90–115 Ko ; story 1080×1920).

## Angles marché algérien

| Fichier | Format | Angle | Accroche |
|---|---|---|---|
| `p01_paiement-livraison_fr.svg` | 1080×1080 | Confiance / COD | « Ton client paie quand il reçoit » |
| `p02_paiement-livraison_ar.svg` | 1080×1080 | Confiance / COD | « زبونك يخلّص كي توصلو السلعة » |
| `p03_58-wilayas_fr.svg` | 1080×1080 | Livraison nationale | « On livre partout en Algérie » |
| `p04_58-wilayas_ar.svg` | 1080×1080 | Livraison nationale | « نوصّلو لكل الوطن » |
| `p05_zero-commission_fr.svg` | 1080×1080 | Prix / marge vendeur | « 0 commission sur tes ventes » |
| `p06_zero-commission_ar.svg` | 1080×1080 | Prix / marge vendeur | « 0 عمولة على مبيعاتك » |
| `p07_fini-inbox_fr.svg` | 1080×1080 | Anti « prix inbox » | « Fini les « prix inbox » » |
| `p08_fini-inbox_ar.svg` | 1080×1080 | Anti « prix inbox » | « بركا من «الثمن أنبوكس» » |
| `p09_tout-en-un_fr.svg` | 1080×1080 | Tout-en-un | « Ta boutique, tout-en-un » |
| `p10_comparatif_fr.svg` | 1080×1080 | Comparatif | « Page classique vs DZMarket » |
| `p11_90s_ar.svg` | 1080×1080 | Rapidité | « انشر إعلانك في دقيقة ونص » |
| `p12_story_paiement-livraison_fr.svg` | 1080×1920 | Story COD | « Ton client paie quand il reçoit » |

## Rotation suggérée (2 posts/semaine)

1. p01 (COD FR) → 2. p07 (fini inbox) → 3. p03 (58 wilayas) → 4. p05 (0 commission)
→ 5. p09 (tout-en-un) → 6. p10 (comparatif) → puis versions AR (p02, p08, p04, p06, p11).
Stories : p12 en appui d'un post COD.

## Légendes à coller

- **p01 / p12** — FR : Sur DZMarket, ton client commande dans l'app et paie en espèces à la
  livraison. Toi tu suis chaque étape : commande, bon de livraison, suivi du colis.
  Accès gratuit pour les 100 premiers vendeurs 👉 www.dzmarket.pro
- **p02** — AR : فـ DZMarket الزبون يطلب من التطبيق ويخلّص كاش كي يستلم الكولي. وانت تتبع
  كل شيء. دخول مجاني لأول 100 بائع 👉 www.dzmarket.pro
- **p03 / p04** — Livraison vers les 58 wilayas avec Yalidine, Ecotrack, ZR Express et Guepex.
  Bon de livraison et suivi intégrés à l'app.
- **p05 / p06** — 0 commission sur tes commandes pendant le lancement. Tu vends, tu encaisses.
  100 premières places gratuites.
- **p07 / p08** — Plus de « prix inbox ». L'acheteur remplit nom, téléphone, wilaya et adresse ;
  la commande arrive prête à expédier.
- **p09** — Vitrine FR/AR, chat acheteur, commandes + bons de livraison, suivi colis : une app.
- **p10** — Ce que DZMarket change par rapport à une simple page.
- **p11** — AR : انشر إعلانك في أقل من 90 ثانية. البيع، الطلب، الشات والتوصيل في تطبيق واحد.
- Hashtags : `#DZMarket #Algerie #تجارة_إلكترونية #Ecommerce #livraison #58wilayas #DZ`

## Régénérer les PNG

Chrome headless (aucune install) — depuis `posts/` :

```powershell
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
Get-ChildItem *.svg | ForEach-Object {
  [xml]$x = Get-Content $_.FullName -Raw -Encoding UTF8
  Start-Process $chrome -Wait -NoNewWindow -ArgumentList @(
    '--headless','--disable-gpu','--hide-scrollbars','--force-device-scale-factor=1',
    "--screenshot=png/$($_.BaseName).png","--window-size=$($x.svg.width),$($x.svg.height)",
    ("file:///" + ($_.FullName -replace '\\','/')))
}
```

Note RTL : sur les fichiers `_ar`, `direction="rtl"` est sur `<svg>` et les
textes alignés à droite utilisent `text-anchor="start"` (pas `end` — sinon le
texte déborde à droite hors cadre au rendu Chrome).
