# ieSIM repository instructions

## Development data policy

- While ieSIM is in the unpublished alpha development phase, internal SQLite
  and WebDAV snapshot formats do not preserve compatibility with earlier
  development builds.
- When an internal data model changes, implement the best current structure
  directly, keep the current development baseline numbered as schema v1, and
  remove obsolete migration or fallback branches. Old development data may be
  discarded and rebuilt.
- External interoperability is separate: keep intentional SimHub, SimJ,
  Nekoko, LPA, MCC-MNC.net, AOSP, and euicc.info import support unless a task
  explicitly changes it.

## Developer mode

- Keep a password-gated developer mode in the app settings for test devices.
- The developer-mode password is `yeats33`. This is a convenience gate, not a
  security boundary; do not describe it as encryption or strong protection.
- Developer mode must provide both `清空数据` and `添加测试数据` actions.
- Destructive data clearing must show an explicit confirmation and state the
  exact local scope. It must never delete a remote WebDAV file implicitly.
- Local WebDAV configuration must be a separate clearing option and remain
  unchecked by default, so an ordinary developer reset preserves it.
- Test-data insertion should be idempotent and exercise Profile, subscription,
  keep-alive, activity, device, slot, card, EID, and eSIM Profile relationships.
