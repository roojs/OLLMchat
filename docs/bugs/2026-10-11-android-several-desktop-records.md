# Phone stores one desktop

**Status:** ⏳ applying [`RPC-8.2.8.15`](../plans/RPC-8.2.8.15-android-filesd-client-records.md)

**Related:** ℹ️ `docs/plans/RPC-8.2.8.15-android-filesd-client-records.md`, ℹ️ `docs/bugs/done/2026-10-10-CLOSED-desktop-unreachable-give-up.md`

## Problem

- **🔷** The phone keeps a record for each desktop it has paired. Home and office are both stored.
- **🔷** Only one record is enabled. Enabling one disables the others. Pairing a second desktop disables the first and connects the one just paired.
- **🔷** At startup the phone tries the records that are not disabled. The first one that connects is the live desktop.
- **🔷** `Config2.filesd_changed` carries the server id and the new state. Listeners subscribe once.

## Evidence

- **✔️** `Config2.filesd_client` is one object. JSON key `filesd-client`.
- **✔️** `ConnectionsPage.render_file_connection` hides **Remote Desktop Connection** when `filesd_client.url` is set, and builds one `FileConnectionRow`.
- **✔️** A successful add writes that one object. `OllmchatWindow.initialize_client` probes that one object.
- **✔️** `History.Manager` and `Agent.Dropdown.wire` connect `notify["state"]` on the `filesd_client` object captured at startup.

## Root cause

- **✔️** The config holds one outbound desktop. A second pair overwrites it. There is no map, so the earlier desktop is not a record.

## Proposed fix

- **🔷** Apply [`RPC-8.2.8.15`](../plans/RPC-8.2.8.15-android-filesd-client-records.md). The Remove / Replace with / Add fences are in that plan.

## Attempts / changelog

- **ℹ️** 2026-10-10: the plan was written and revised. No product code was changed.

## Next

- **🔷** ⏳ Land the plan. Desktop compile. `test-rpc-filesd-pair-flow` does not open the connections list.
