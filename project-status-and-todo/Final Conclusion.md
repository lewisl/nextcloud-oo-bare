

## Project conclusion (final)

### Decision
Adopt Sync.com for secure team file sync/sharing and retire the Nextcloud + OnlyOffice stack for production use.

### Why this path
- Reliability and recovery: Trash/version restore functions correctly in shared spaces without cryptic edge cases.
- Security posture: E2EE by default; risk from web editing can be eliminated by using client‑side editing.
- Cost and simplicity: Lower TCO than Pydio Enterprise or Tresorit; minimal ops burden.
- Data residency and performance: Hosted in Canada; consistently fast and responsive.

### Alternatives considered
- Nextcloud + OnlyOffice: Rejected due to show‑stopping trashbin/version issues under server‑side encryption for shared/team folders.
- Sync.com:  adopted for cost, valid EE2E implementation, Office Online editing or local syncing with Office apps editing.
- Tresorit: Solid E2EE, not‑for‑profit discount available; ultimately pricier and less convenient than Sync.com for our use.
- Proton Drive: Mac desktop sync client does not support shared folders (admitted limitation) — deal‑breaker.

### Risk and policy posture
- Default to client‑side editing for sensitive content to preserve strict zero‑knowledge guarantees.
- If enabling Office Online for convenience, request Sync’s written statement on WOPI cache/retention and purge SLA, and apply it only to low‑risk workspaces.

### Migration and decommission (high‑level)
- Freeze writes on the old stack; take final snapshot.
- Migrate shared folders and permissions into Sync.com; validate restore/version behavior with test cases.
- Communicate cutover (install client, editing policy, support contact).
- Decommission Nextcloud/OnlyOffice/nginx in stages; revoke tokens/keys, remove DNS, archive configs (with secrets redacted) for 90–180 days.

### Operational checklist in Sync.com
- Enforce MFA; review device approvals if available in plan.
- Set version history and trash retention to meet RPO/RTO; run quarterly restore drills.
- Apply least‑privilege sharing; restrict delete and resharing rights.
- Confirm Canadian data residency and finalize DPA/SCCs as applicable.
- Enable audit/event logs if available; consider scheduled exports.
- Standardize client versions and document conflict resolution.

### Hetzner note
Hetzner was an excellent learning experience: outstanding performance and value, even with extra latency to Germany — clearly ahead of DigitalOcean in our testing. We’re nonetheless prioritizing operational simplicity and recovery guarantees with Sync.com.

### Closeout
This project achieved its primary goal: selecting a dependable, secure, and maintainable team file platform. Sync.com meets the requirements at lower cost and complexity. The open‑source path provided valuable lessons, especially around encryption + shared folders + recovery, but SaaS is the right fit here.
