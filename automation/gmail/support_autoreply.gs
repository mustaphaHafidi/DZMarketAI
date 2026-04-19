/**
 * DZMarket Gmail support automation
 *
 * What this script does:
 * - Reads new support emails from Gmail label DZMarket/Support/Inbox
 * - Sends a branded acknowledgement from support@dzmarket.pro
 * - Generates a real ticket id per thread (no {{ticket_id}} placeholders)
 * - Detects FR/AR and uses matching template
 * - Marks thread as processed to prevent duplicate auto-replies
 *
 * Optional helper functions:
 * - dzmarketReplyNeedInfo(threadId, details)
 * - dzmarketReplyResolved(threadId, details)
 */

var DZMARKET_SUPPORT = {
  supportAlias: 'support@dzmarket.pro',
  supportName: 'Support DZMarket',
  supportMailbox: 'dzmarketsoft@gmail.com',
  appUrl: 'https://app.dzmarket.pro',
  logoUrl: 'https://app.dzmarket.pro/assets/logos/logo4_icon_square.png',
  timezone: 'Africa/Algiers',
  triggerEveryMinutes: 5,
  maxThreadsPerRun: 25,
  labels: {
    inbox: 'DZMarket/Support/Inbox',
    ackSent: 'DZMarket/Support/AckSent',
    needInfo: 'DZMarket/Support/NeedInfo',
    resolved: 'DZMarket/Support/Resolved',
    error: 'DZMarket/Support/Error'
  }
};

/**
 * Run once after pasting the script:
 * - creates required Gmail labels
 * - installs a single time-driven trigger every X minutes
 */
function dzmarketSetupSupportBot() {
  var cfg = DZMARKET_SUPPORT;
  getOrCreateLabel_(cfg.labels.inbox);
  getOrCreateLabel_(cfg.labels.ackSent);
  getOrCreateLabel_(cfg.labels.needInfo);
  getOrCreateLabel_(cfg.labels.resolved);
  getOrCreateLabel_(cfg.labels.error);
  ensureSingleTimeTrigger_('dzmarketProcessSupportInbox', cfg.triggerEveryMinutes || 5);
}

function dzmarketProcessSupportInbox() {
  var cfg = DZMARKET_SUPPORT;
  var inboxLabel = getOrCreateLabel_(cfg.labels.inbox);
  var ackLabel = getOrCreateLabel_(cfg.labels.ackSent);
  var errorLabel = getOrCreateLabel_(cfg.labels.error);

  var query =
    'label:"' +
    inboxLabel.getName() +
    '" -label:"' +
    ackLabel.getName() +
    '" newer_than:21d';
  var threads = GmailApp.search(query, 0, cfg.maxThreadsPerRun);

  for (var i = 0; i < threads.length; i++) {
    var thread = threads[i];
    try {
      var sourceMsg = findLatestExternalMessage_(thread);
      if (!sourceMsg) {
        thread.addLabel(ackLabel);
        continue;
      }

      var senderEmail = extractSenderEmail_(sourceMsg.getFrom());
      if (!senderEmail || shouldSkipSender_(senderEmail, cfg)) {
        thread.addLabel(ackLabel);
        continue;
      }

      var senderName = extractSenderName_(sourceMsg.getFrom());
      var firstName = extractFirstName_(senderName);
      var language = detectLanguage_(sourceMsg.getSubject() + '\n' + sourceMsg.getPlainBody());
      var ticketId = getOrCreateTicketId_(thread, cfg);

      var subject = buildSubject_(language, ticketId, sourceMsg.getSubject(), 'ack');
      var html = buildSupportHtml_(language, 'ack', firstName, ticketId, '');
      var text = buildSupportText_(language, 'ack', firstName, ticketId, '');

      GmailApp.sendEmail(senderEmail, subject, text, {
        from: cfg.supportAlias,
        name: cfg.supportName,
        replyTo: cfg.supportAlias,
        htmlBody: html
      });

      thread.addLabel(ackLabel);
      thread.removeLabel(inboxLabel);
    } catch (err) {
      thread.addLabel(errorLabel);
      Logger.log('dzmarketProcessSupportInbox failed for thread ' + thread.getId() + ': ' + err);
    }
  }
}

function dzmarketReplyNeedInfo(threadId, details) {
  sendManualReply_(threadId, 'need_info', details || '');
}

function dzmarketReplyResolved(threadId, details) {
  sendManualReply_(threadId, 'resolved', details || '');
}

function sendManualReply_(threadId, mode, details) {
  var cfg = DZMARKET_SUPPORT;
  var thread = GmailApp.getThreadById(threadId);
  if (!thread) {
    throw new Error('Thread not found: ' + threadId);
  }

  var sourceMsg = findLatestExternalMessage_(thread);
  if (!sourceMsg) {
    throw new Error('No external sender found in thread: ' + threadId);
  }

  var to = extractSenderEmail_(sourceMsg.getFrom());
  if (!to) {
    throw new Error('Cannot resolve sender email for thread: ' + threadId);
  }

  var senderName = extractSenderName_(sourceMsg.getFrom());
  var firstName = extractFirstName_(senderName);
  var language = detectLanguage_(sourceMsg.getSubject() + '\n' + sourceMsg.getPlainBody());
  var ticketId = getOrCreateTicketId_(thread, cfg);

  var subject = buildSubject_(language, ticketId, sourceMsg.getSubject(), mode);
  var html = buildSupportHtml_(language, mode, firstName, ticketId, details);
  var text = buildSupportText_(language, mode, firstName, ticketId, details);

  GmailApp.sendEmail(to, subject, text, {
    from: cfg.supportAlias,
    name: cfg.supportName,
    replyTo: cfg.supportAlias,
    htmlBody: html
  });

  if (mode === 'need_info') {
    thread.addLabel(getOrCreateLabel_(cfg.labels.needInfo));
  }
  if (mode === 'resolved') {
    thread.addLabel(getOrCreateLabel_(cfg.labels.resolved));
  }
}

function findLatestExternalMessage_(thread) {
  var messages = thread.getMessages();
  for (var i = messages.length - 1; i >= 0; i--) {
    var from = extractSenderEmail_(messages[i].getFrom());
    if (!from) continue;
    if (shouldSkipSender_(from, DZMARKET_SUPPORT)) continue;
    return messages[i];
  }
  return null;
}

function shouldSkipSender_(senderEmail, cfg) {
  var email = (senderEmail || '').toLowerCase();
  if (!email) return true;
  if (email.indexOf('mailer-daemon') !== -1) return true;
  if (email.indexOf('postmaster') !== -1) return true;
  if (email === cfg.supportAlias.toLowerCase()) return true;
  if (email === cfg.supportMailbox.toLowerCase()) return true;
  if (email.indexOf('@dzmarket.pro') !== -1) return true;
  return false;
}

function extractSenderEmail_(fromHeader) {
  if (!fromHeader) return '';
  var match = fromHeader.match(/<([^>]+)>/);
  if (match && match[1]) return String(match[1]).trim().toLowerCase();
  return String(fromHeader).trim().toLowerCase();
}

function extractSenderName_(fromHeader) {
  if (!fromHeader) return '';
  var match = fromHeader.match(/^(.*)<[^>]+>/);
  if (!match || !match[1]) return '';
  return String(match[1]).replace(/["']/g, '').trim();
}

function extractFirstName_(name) {
  if (!name) return '';
  var cleaned = String(name)
    .replace(/\s+/g, ' ')
    .replace(/[0-9]/g, '')
    .trim();
  if (!cleaned) return '';
  var parts = cleaned.split(' ');
  if (!parts.length) return '';
  return parts[0];
}

function detectLanguage_(text) {
  if (!text) return 'fr';
  return /[\u0600-\u06FF]/.test(text) ? 'ar' : 'fr';
}

function getOrCreateTicketId_(thread, cfg) {
  var props = PropertiesService.getScriptProperties();
  var key = 'ticket.thread.' + thread.getId();
  var existing = props.getProperty(key);
  if (existing) return existing;

  var datePart = Utilities.formatDate(new Date(), cfg.timezone, 'yyyyMMdd');
  var raw = thread.getId() || Utilities.getUuid();
  var shortId = String(raw).slice(-6).toUpperCase();
  if (shortId.length < 6) {
    shortId = Utilities.getUuid().replace(/-/g, '').slice(0, 6).toUpperCase();
  }
  var ticketId = 'DZM-' + datePart + '-' + shortId;
  props.setProperty(key, ticketId);
  return ticketId;
}

function normalizeSubject_(subject) {
  if (!subject) return 'Support';
  return String(subject)
    .replace(/^\s*(re|fwd|fw)\s*:\s*/gi, '')
    .trim();
}

function buildSubject_(lang, ticketId, sourceSubject, mode) {
  var base = normalizeSubject_(sourceSubject);
  if (lang === 'ar') {
    if (mode === 'need_info') return '[DZMarket][Ticket ' + ticketId + '] نحتاج معلومات إضافية - ' + base;
    if (mode === 'resolved') return '[DZMarket][Ticket ' + ticketId + '] تم حل الطلب - ' + base;
    return '[DZMarket][Ticket ' + ticketId + '] تم استلام طلبك - ' + base;
  }

  if (mode === 'need_info') return '[DZMarket][Ticket ' + ticketId + '] Informations complémentaires requises - ' + base;
  if (mode === 'resolved') return '[DZMarket][Ticket ' + ticketId + '] Résolution de votre demande - ' + base;
  return '[DZMarket][Ticket ' + ticketId + '] Demande reçue - ' + base;
}

function buildSupportHtml_(lang, mode, firstName, ticketId, details) {
  var cfg = DZMARKET_SUPPORT;
  var safeName = escapeHtml_(firstName || '');
  var safeTicket = escapeHtml_(ticketId || '');
  var safeDetails = escapeHtml_(details || '').replace(/\n/g, '<br>');

  var greetingFr = safeName ? 'Bonjour ' + safeName + ',' : 'Bonjour,';
  var greetingAr = safeName ? 'مرحباً ' + safeName + '،' : 'مرحباً،';

  var title = '';
  var intro = '';
  var actionLine = '';
  var footerLine = '';

  if (lang === 'ar') {
    if (mode === 'need_info') {
      title = 'نحتاج معلومات إضافية';
      intro = 'لمتابعة طلبك بسرعة، نحتاج المعلومات التالية:';
      actionLine = safeDetails || '• لقطات شاشة واضحة\n• نسخة التطبيق\n• نوع الجهاز';
      footerLine = 'بعد استلام المعلومات، نتابع المعالجة مباشرة.';
    } else if (mode === 'resolved') {
      title = 'تم حل الطلب';
      intro = 'تمت معالجة طلبك.';
      actionLine = safeDetails || 'تم تنفيذ الإجراء المطلوب بنجاح.';
      footerLine = 'إذا احتجت أي مساعدة إضافية، فقط قم بالرد على هذا البريد.';
    } else {
      title = 'تم استلام طلبك';
      intro = 'استلمنا رسالتك. سيقوم فريق الدعم بالرد خلال 24 ساعة عمل.';
      actionLine = 'رقم التذكرة: ' + safeTicket;
      footerLine = 'لتسريع المعالجة، يرجى إرسال: لقطة شاشة + نسخة التطبيق + نوع الجهاز + وقت المشكلة.';
    }
  } else {
    if (mode === 'need_info') {
      title = 'Informations complémentaires requises';
      intro = 'Pour accélérer le traitement de votre demande, merci de nous envoyer:';
      actionLine = safeDetails || '- captures d écran\n- version de l application\n- type d appareil';
      footerLine = 'Dès réception de ces éléments, nous poursuivons le traitement.';
    } else if (mode === 'resolved') {
      title = 'Résolution de votre demande';
      intro = 'Votre demande a bien été traitée.';
      actionLine = safeDetails || 'Action effectuée avec succès.';
      footerLine = 'Si besoin, repondez simplement a cet email et nous reprenons le ticket.';
    } else {
      title = 'Demande reçue';
      intro = 'Nous avons bien reçu votre demande. Notre équipe support vous répondra sous 24h ouvrables.';
      actionLine = 'Numéro de ticket: ' + safeTicket;
      footerLine = 'Pour accélérer le traitement, merci d envoyer: capture écran + version app + appareil + heure du problème.';
    }
  }

  var greeting = lang === 'ar' ? greetingAr : greetingFr;
  var direction = lang === 'ar' ? 'rtl' : 'ltr';
  var align = lang === 'ar' ? 'right' : 'left';

  var html = '';
  html += '<!doctype html><html lang="' + (lang === 'ar' ? 'ar' : 'fr') + '" dir="' + direction + '">';
  html += '<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">';
  html += '<title>DZMarket Support</title></head>';
  html += '<body style="margin:0;padding:0;background:#eef5ef;">';
  html += '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#eef5ef;border-collapse:collapse;"><tr><td align="center" style="padding:24px 12px;">';
  html += '<table role="presentation" width="620" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:620px;background:#ffffff;border:1px solid #dfe9e1;border-radius:14px;border-collapse:separate;">';
  html += '<tr><td style="padding:28px 24px;font-family:Arial,Helvetica,sans-serif;color:#16322a;text-align:' + align + ';">';
  html += '<table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>';
  html += '<td style="vertical-align:middle;padding-right:10px;"><img src="' + cfg.logoUrl + '" alt="DZMarket" width="40" height="40" style="display:block;border:0;border-radius:8px;"></td>';
  html += '<td style="vertical-align:middle;font-size:32px;line-height:32px;font-weight:700;color:#08372a;">DZMarket</td>';
  html += '</tr></table>';
  html += '<h1 style="margin:24px 0 12px;font-size:30px;line-height:1.25;color:#0a3d2f;">' + escapeHtml_(title) + '</h1>';
  html += '<p style="margin:0 0 12px;font-size:18px;line-height:1.6;color:#2e4a3f;">' + escapeHtml_(greeting) + '</p>';
  html += '<p style="margin:0 0 12px;font-size:18px;line-height:1.6;color:#2e4a3f;">' + escapeHtml_(intro) + '</p>';
  html += '<p style="margin:0 0 12px;font-size:16px;line-height:1.6;color:#2e4a3f;white-space:pre-line;">' + actionLine + '</p>';
  html += '<p style="margin:0 0 20px;font-size:16px;line-height:1.6;color:#2e4a3f;">' + escapeHtml_(footerLine) + '</p>';
  html += '<p style="margin:0 0 8px;font-size:14px;line-height:1.5;color:#5f746b;">Support DZMarket</p>';
  html += '<p style="margin:0 0 8px;font-size:14px;line-height:1.5;"><a href="mailto:' + cfg.supportAlias + '?subject=' + encodeURIComponent('[DZMarket][Ticket ' + ticketId + '] ') + '" style="color:#0a6c53;text-decoration:none;">' + cfg.supportAlias + '</a></p>';
  html += '<p style="margin:0;font-size:13px;line-height:1.5;color:#8aa095;">' + cfg.appUrl + '</p>';
  html += '</td></tr></table></td></tr></table></body></html>';
  return html;
}

function buildSupportText_(lang, mode, firstName, ticketId, details) {
  var nameLineFr = firstName ? 'Bonjour ' + firstName + ',' : 'Bonjour,';
  var nameLineAr = firstName ? 'مرحباً ' + firstName + '،' : 'مرحباً،';

  if (lang === 'ar') {
    if (mode === 'need_info') {
      return (
        nameLineAr +
        '\n\nنحتاج معلومات إضافية لمتابعة طلبك:\n' +
        (details || '- لقطات شاشة\n- نسخة التطبيق\n- نوع الجهاز') +
        '\n\nرقم التذكرة: ' +
        ticketId +
        '\n\nSupport DZMarket\nsupport@dzmarket.pro'
      );
    }
    if (mode === 'resolved') {
      return (
        nameLineAr +
        '\n\nتمت معالجة طلبك.\n' +
        (details || 'تم تنفيذ الإجراء المطلوب بنجاح.') +
        '\n\nرقم التذكرة: ' +
        ticketId +
        '\nإذا احتجت أي مساعدة إضافية، قم بالرد على هذا البريد.\n\nSupport DZMarket\nsupport@dzmarket.pro'
      );
    }
    return (
      nameLineAr +
      '\n\nتم استلام طلبك. سنرد خلال 24 ساعة عمل.\n' +
      'رقم التذكرة: ' +
      ticketId +
      '\nلتسريع المعالجة، أرسل: لقطة شاشة + نسخة التطبيق + نوع الجهاز + وقت المشكلة.\n\nSupport DZMarket\nsupport@dzmarket.pro'
    );
  }

  if (mode === 'need_info') {
    return (
      nameLineFr +
      '\n\nPour traiter votre demande, merci de nous envoyer:\n' +
      (details || '- captures d écran\n- version de l application\n- type d appareil') +
      '\n\nNuméro de ticket: ' +
      ticketId +
      '\n\nSupport DZMarket\nsupport@dzmarket.pro'
    );
  }
  if (mode === 'resolved') {
    return (
      nameLineFr +
      '\n\nVotre demande est traitée.\n' +
      (details || 'Action effectuée avec succès.') +
      '\n\nNuméro de ticket: ' +
      ticketId +
      '\nSi besoin, repondez a cet email.\n\nSupport DZMarket\nsupport@dzmarket.pro'
    );
  }
  return (
    nameLineFr +
    '\n\nNous avons bien reçu votre demande. Réponse sous 24h ouvrables.\n' +
    'Numéro de ticket: ' +
    ticketId +
    '\nPour accélérer le traitement: capture écran + version app + appareil + heure du problème.\n\nSupport DZMarket\nsupport@dzmarket.pro'
  );
}

function getOrCreateLabel_(labelName) {
  var label = GmailApp.getUserLabelByName(labelName);
  if (!label) {
    label = GmailApp.createLabel(labelName);
  }
  return label;
}

function ensureSingleTimeTrigger_(handlerName, everyMinutes) {
  var triggers = ScriptApp.getProjectTriggers();
  for (var i = 0; i < triggers.length; i++) {
    var t = triggers[i];
    if (t.getHandlerFunction() === handlerName) {
      ScriptApp.deleteTrigger(t);
    }
  }
  ScriptApp.newTrigger(handlerName).timeBased().everyMinutes(everyMinutes).create();
}

function escapeHtml_(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
