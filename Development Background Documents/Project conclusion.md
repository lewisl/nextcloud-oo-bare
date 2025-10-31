
## Short answer

Given your hard requirements (team/shared folders, reliable undelete/restore, interest in a remote key server) and your experience, I’d pivot away from Nextcloud for the “secure team drive” use case. Keep it only if you’re willing to drop server‑side encryption and rely on robust snapshots/backups for undelete, or confine it to “low‑risk” collaboration. For truly sensitive shared content with dependable recovery and simpler ops, a mature E2EE platform (e.g., Sync.com/Tresorit) is the pragmatic choice. If you need your own keys or a remote KMS, evaluate self‑hosted alternatives designed for this from the start (e.g., Seafile Pro, Pydio Cells) before investing further in custom Nextcloud crypto plumbing.

## Why I think that

- Nextcloud + server‑side encryption (SSE) is a poor fit for shared/team libraries when you need dependable, user‑self‑service restore. The trashbin/version semantics under SSE have long‑standing edge cases, and you’ve hit a show‑stopper. You can engineer around it (snapshots + admin restores), but then you’re fighting the platform.
- “Real” E2EE and web editing only coexist by moving decryption and editing to the client (browser/desktop) and trusting vendor‑served JS/apps. Vendors that built for this from day 1 tend to be simpler and less brittle than bolting E2EE onto a general groupware stack.
- Customizing Nextcloud’s key retrieval or wiring a remote KMS is a maintenance treadmill: frequent upstream changes, complex share semantics, and limited test surface from the community for your exact scenario.

## Practical paths (ranked by operational sanity)

1) SaaS E2EE for the secure team drive
- What you gain: robust undelete/versioning designed around E2EE, minimal ops, predictable cost.
- What you give up: full control of the server; collaborative editing is typically client‑side and may be less “Google‑Docs‑like” for multi‑user concurrency.

2) Hybrid model
- Keep Nextcloud (no SSE) for general collaboration and OnlyOffice/Collabora.
- Put sensitive team folders in an E2EE service. Use DLP/process to keep them separate.
- Ops reality: this usually yields the best balance of features, simplicity, and risk.

3) Salvage Nextcloud with compensating controls (if you must)
- Turn off SSE; rely on:
  - Storage snapshots (ZFS/Btrfs/LVM/S3 versioning) + tested restore runbook
  - Strict delete permissions on Group Folders (deny delete for most users)
  - Retention policies and scheduled exports
- Trade‑off: data on the server is readable by admins/compromise at rest (mitigated by FDE/host controls), but you get reliable restores and keep web co‑editing.

4) Self‑hosted alternatives designed for this
- Seafile Pro or Pydio Cells are often cited for better large‑file performance/versioning and cleaner permission models; both integrate with OnlyOffice. Their encryption/restore stories and KMS options are worth a focused POC if you need remote keys and on‑prem control.
- Caveat: still more ops than SaaS, but typically less “bolt‑on” pain than customizing Nextcloud crypto.

## Reality check on “web editing under E2EE”

- True zero‑knowledge means the server can’t see plaintext; real‑time multi‑cursor collaboration is hard without exposing data to a server. Many E2EE vendors provide sequential or limited co‑editing through client apps or browser JS with local keys. That’s usually “good enough” for business editing but not Google‑Docs‑grade concurrency.

## My recommendation

- If the secure team drive is the priority and you’re done spending time on platform surgery: move it to a mature E2EE service (Sync.com/Tresorit). Keep Nextcloud as a general intranet/collab portal without SSE, or retire it entirely if redundancy isn’t valuable.
- If you require your own keys or a remote KMS: plan a short POC with Seafile Pro or Pydio Cells against your must‑haves (team shares, undelete, audit, editor integration), before attempting more Nextcloud crypto customization.

## If you want, I can help next with

- A 1‑page decision matrix (must‑haves vs nice‑to‑haves, costs, risks) across 2–3 candidates you name.
- A minimal “compensating controls” plan for your current Nextcloud to reduce risk while you evaluate alternatives (permissions, snapshots, restore drills).
- A scoped POC test plan (10–15 checks) to verify trash/versions, sharing, web editing, and key management on an alternative platform.
