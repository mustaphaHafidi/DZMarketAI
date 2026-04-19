# SUPPORT_EMAIL_TEMPLATES_FR_AR

## Regles d'usage

- `no-reply@dzmarket.pro`: emails systeme only (confirmation, reset, notifications).
- `support@dzmarket.pro`: support client et reponses ticket.
- `contact@dzmarket.pro`: legal, business, partenariat.
- Ne pas utiliser les filtres Gmail avec reponse automatique "modele" pour le support.

## Sujet standard

- FR: `[DZMarket][Ticket <TICKET_ID>] <SUJET>`
- AR: `[DZMarket][Ticket <TICKET_ID>] <الموضوع>`

`<TICKET_ID>` doit etre une vraie valeur, jamais `{{ticket_id}}`.

## 1) Accuse de reception (FR)

Objet: `[DZMarket][Ticket <TICKET_ID>] Demande recue - <SUJET_CLIENT>`

Bonjour <PRENOM>,

Nous avons bien recu votre demande.
Notre equipe support vous repondra sous 24h ouvrables.

Numero de ticket: <TICKET_ID>

Pour accelerer le traitement, merci d'envoyer:
- capture d'ecran
- version de l'application
- type d'appareil
- heure approximative du probleme

Cordialement,
Support DZMarket
support@dzmarket.pro

## 2) Demande d'informations (FR)

Objet: `[DZMarket][Ticket <TICKET_ID>] Informations complementaires requises - <SUJET_CLIENT>`

Bonjour <PRENOM>,

Pour finaliser votre demande, merci de nous envoyer:
- <INFO_1>
- <INFO_2>
- <INFO_3>

Des reception des elements, nous poursuivons le traitement.

Cordialement,
Support DZMarket
support@dzmarket.pro

## 3) Resolution (FR)

Objet: `[DZMarket][Ticket <TICKET_ID>] Resolution de votre demande - <SUJET_CLIENT>`

Bonjour <PRENOM>,

Votre demande a ete traitee.
Action appliquee: <ACTION>.
Resultat: <RESULTAT>.

Si besoin, repondez simplement a cet email et nous reprenons le ticket.

Cordialement,
Support DZMarket
support@dzmarket.pro

## 4) تاكيد الاستلام (AR)

الموضوع: `[DZMarket][Ticket <TICKET_ID>] تم استلام طلبك - <موضوع العميل>`

مرحباً <الاسم>،

تم استلام طلبك.
سيقوم فريق الدعم بالرد خلال 24 ساعة عمل.

رقم التذكرة: <TICKET_ID>

لتسريع المعالجة، يرجى ارسال:
- لقطة شاشة
- نسخة التطبيق
- نوع الجهاز
- وقت حدوث المشكلة

مع التحية،
دعم DZMarket
support@dzmarket.pro

## 5) طلب معلومات اضافية (AR)

الموضوع: `[DZMarket][Ticket <TICKET_ID>] نحتاج معلومات اضافية - <موضوع العميل>`

مرحباً <الاسم>،

لاستكمال معالجة طلبك، نرجو تزويدنا بـ:
- <INFO_1>
- <INFO_2>
- <INFO_3>

بعد استلام المعلومات، نتابع المعالجة مباشرة.

مع التحية،
دعم DZMarket
support@dzmarket.pro

## 6) حل الطلب (AR)

الموضوع: `[DZMarket][Ticket <TICKET_ID>] تم حل الطلب - <موضوع العميل>`

مرحباً <الاسم>،

تمت معالجة طلبك.
الاجراء المنفذ: <ACTION>.
النتيجة: <RESULTAT>.

اذا احتجت مساعدة اضافية، فقط قم بالرد على هذا البريد.

مع التحية،
دعم DZMarket
support@dzmarket.pro

## Automatisation recommandee

Use `automation/gmail/support_autoreply.gs` to:

- injecter un vrai ticket id
- cibler le vrai expéditeur
- garder un style FR/AR homogène DZMarket
- eviter `+canned.response` et les alias de redirection
