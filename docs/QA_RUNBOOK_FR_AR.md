# QA Runbook — DZMarketProd (FR + AR)

## 1) Statuts QA

FR:
- Backlog = ticket non pret (description incomplete ou non priorise).
- Ready = pret a etre teste maintenant.
- In Progress = test en cours par un testeur.
- Blocked = test bloque (bug, acces, donnee manquante, dependance).
- Retest = correctif livre, test a rejouer.
- Done = test valide et termine.
- Note: Backlog != backend. Backlog = file d'attente de tickets.

AR:
- Backlog = تذكرة غير جاهزة (الوصف ناقص أو غير محددة الأولوية).
- Ready = جاهزة للاختبار الآن.
- In Progress = الاختبار قيد التنفيذ.
- Blocked = الاختبار متوقف (خلل، صلاحية، بيانات ناقصة، اعتماد خارجي).
- Retest = تم تسليم الإصلاح ويجب إعادة الاختبار.
- Done = تم التحقق من الاختبار وإغلاقه.
- ملاحظة: Backlog ليس Backend، بل قائمة انتظار التذاكر.

## 2) Regle en cas d'echec (KO)

FR:
1. Creer un ticket BUG-xxx.
2. Lier le BUG au ticket TC-xxx.
3. Ajouter preuve: capture/video/logs + version + device + compte.
4. Passer le TC en Blocked (ou Retest si fix deja deploye).

AR:
1. إنشاء تذكرة BUG-xxx.
2. ربط الخلل مع تذكرة TC-xxx.
3. إضافة الأدلة: صورة/فيديو/سجلات + النسخة + الجهاز + الحساب.
4. نقل TC إلى Blocked (أو Retest إذا الإصلاح منشور).

## 3) Regle en cas de succes (OK)

FR:
1. Verifier que le resultat attendu est totalement atteint.
2. Ajouter un commentaire court (plateforme, version, compte teste).
3. Joindre preuve legere si necessaire.
4. Passer le TC en Done.
5. Si un BUG lie existait, verifier qu'il est ferme ou marque pour retest.

AR:
1. التأكد أن النتيجة المتوقعة تحققت بالكامل.
2. إضافة تعليق قصير (المنصة، النسخة، الحساب المختبر).
3. إرفاق دليل بسيط عند الحاجة.
4. نقل TC إلى Done.
5. إذا كان هناك BUG مرتبط، التأكد أنه مغلق أو مضبوط لإعادة الاختبار.

## 4) Priorites

FR:
- P0 d'abord (bloquant metier, securite, paiement, checkout, auth, bordereau, label PDF).
- P1 ensuite.
- P2 en dernier.

AR:
- اختبار P0 أولاً (مشاكل حرجة: المصادقة، الدفع، الطلب، البورديرو، PDF).
- ثم P1.
- ثم P2.

## 5) Critere GO Release

FR:
- 0 ticket P0 ouvert.
- 0 Blocked critique.
- Tous les TC critiques en Done.
- Smoke final OK: auth, listing, checkout, shipping, notifications FR/AR.

AR:
- لا يوجد أي P0 مفتوح.
- لا يوجد Blocked حرج.
- كل الاختبارات الحرجة في Done.
- Smoke نهائي ناجح: المصادقة، الإعلانات، الشراء، الشحن، الإشعارات FR/AR.

## 6) Daily QA (15 min)

FR:
- Nombre Done / Total.
- Tickets Blocked.
- P0 restants.
- Decision du jour: Go partiel / No-Go.

AR:
- عدد Done من الإجمالي.
- التذاكر المتوقفة Blocked.
- عدد P0 المتبقي.
- قرار اليوم: Go جزئي أو No-Go.

