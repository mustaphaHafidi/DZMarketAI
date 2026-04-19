# DZMarket Gmail Support Autoreply

This folder contains a Google Apps Script to replace Gmail canned-response auto-replies for support inbox.

## Why this exists

It fixes the issues you saw:

- no more sender like `+canned.response@gmail.com`
- no more wrong recipient `support+_redir+...`
- no more unresolved placeholders like `{{ticket_id}}` or `{{prenom}}`
- consistent branded HTML style close to DZMarket auth emails

## File

- `automation/gmail/support_autoreply.gs`

## Setup (10 minutes)

1. In Gmail (`dzmarketsoft@gmail.com`), verify alias `support@dzmarket.pro` in **Settings > Accounts and Import > Send mail as**.
2. Create a Gmail filter:
   - query: `to:support@dzmarket.pro`
   - action: apply label `DZMarket/Support/Inbox`
   - **do not** send canned response from this filter.
3. Open [script.google.com](https://script.google.com), create a new project.
4. Paste content of `support_autoreply.gs` into `Code.gs`, save.
5. In Apps Script:
   - run `dzmarketSetupSupportBot` once and accept permissions,
   - this creates labels + installs a single trigger automatically.
   - optional: run `dzmarketProcessSupportInbox` manually once for immediate test.
6. Disable old Gmail canned-response auto-reply/filter to avoid duplicate responses.

## Daily operations

- Automatic acknowledgement is sent by trigger.
- For manual follow-up from Apps Script:
  - `dzmarketReplyNeedInfo("<THREAD_ID>", "line1\nline2\nline3")`
  - `dzmarketReplyResolved("<THREAD_ID>", "Action appliquee ...")`

You can get a thread id from Gmail URL while opening a conversation.

## Labels used by the script

- `DZMarket/Support/Inbox` (input queue)
- `DZMarket/Support/AckSent` (ack sent)
- `DZMarket/Support/NeedInfo` (manual follow-up sent)
- `DZMarket/Support/Resolved` (manual resolution sent)
- `DZMarket/Support/Error` (script failures)

## Notes

- Script generates one stable ticket id per conversation: `DZM-YYYYMMDD-XXXXXX`.
- Replies are sent to the real original sender extracted from message headers.
- It skips internal senders (`@dzmarket.pro`, support mailbox, postmaster, mailer-daemon).
