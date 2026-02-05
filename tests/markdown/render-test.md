The two tables are almost the same, but **pressrelease_notify_archive** is missing a few columns (and a few indexes) that exist in **pressrelease_notify**.  
The quickest way to bring the archive table up‑to‑date is to issue a series of `ALTER TABLE … ADD COLUMN` (and `ADD KEY`) statements that match the definition in the main table.

Below is a ready‑to‑run script that adds every column that is present in **pressrelease_notify** but absent in **pressrelease_notify_archive**, and then adds the indexes that are also missing.

> **Important** – run the script on a test copy first, or inside a transaction, so you can roll back if anything looks wrong.

```sql
/* ----------------------------------------------------------------------
   1) Add the missing columns
   ---------------------------------------------------------------------- */
ALTER TABLE pressrelease_notify_archive
  /* column that is nullable in the live table */
  ADD COLUMN `field`            varchar(16)          DEFAULT 'email' AFTER `evtype`,
  /* column that is NOT NULL in the live table – keep the same definition */
  ADD COLUMN `evtype`          varchar(16) NOT NULL DEFAULT ''       AFTER `event_id`,
  /* column that is NOT NULL in the live table – keep the same definition */
  ADD COLUMN `domain_id`       int          NOT NULL DEFAULT 0    AFTER `contact_language`,
  /* columns that exist only in the live table */
  ADD COLUMN `ipv6_id`         int          NOT NULL DEFAULT 0    AFTER `email_id`,
  ADD COLUMN `email_id`        int          NOT NULL DEFAULT 0    AFTER `ipv6_id`;

-- If you prefer the exact same nullability as the live table (i.e. `field` and `evtype` are nullable there),
-- you can change the definitions to match:
--   MODIFY COLUMN `field`   varchar(16) DEFAULT 'email',
--   MODIFY COLUMN `evtype` varchar(16) DEFAULT '',
--   MODIFY COLUMN `domain_id` int DEFAULT 0;

/* ----------------------------------------------------------------------
   2) Add the missing indexes
   ---------------------------------------------------------------------- */
ALTER TABLE pressrelease_notify_archive
  /* indexes that exist in pressrelease_notify but not in the archive table */
  ADD KEY `is_open_idx` (`is_open`),
  ADD KEY `lookup_c` (`onid`,`ontable`,`person_id`,`act_when`,`msgid`,`to_email`,`evtype`,`fail_reviewed`,`event_id`),
  ADD KEY `lookup_h` (`act_when`,`evtype`,`sent`),
  ADD KEY `lookup_g` (`onid`,`ontable`,`person_id`,`act_start`,`act_when`,`to_email`,`evtype`,`sent`,`msgid`,`fail_reviewed`,`event_id`),
  ADD KEY `lookup_x` (`ontable`,`domain_id`,`person_id`,`sent`,`event_id`),
  ADD KEY `lookup_j` (`onid`,`ontable`,`person_id`,`act_when`,`to_email`,`evtype`,`sent`,`msgid`,`fail_reviewed`,`event_id`,`opened_dt`),
  ADD KEY `lookup_k` (`onid`,`ontable`,`person_id`,`act_when`,`to_email`,`evtype`,`sent`,`msgid`,`fail_reviewed`,`event_id`,`opened_dt`,`server_id`),
  ADD KEY `ix_match` (`ontable`,`evtype`,`fail_reviewed`,`reject_match_id`),
  ADD KEY `lookup_to_email` (`to_email`,`ontable`,`evtype`,`fail_reviewed`,`person_id`,`msgid`,`event_id`),
  ADD KEY `lookup_reject` (`person_id`,`reject_match_id`,`event_id`),
  ADD KEY `lookup_em` (`person_id`,`field`),
  ADD KEY `lookup_q` (`id`,`onid`,`ontable`,`sent`);

-- The archive table already has a few indexes (is_open_idx, lookup_p, lookup_j). 
-- Adding the ones above will make its index set identical to the live table.

/* ----------------------------------------------------------------------
   3) Verify the result
   ---------------------------------------------------------------------- */
SHOW CREATE TABLE pressrelease_notify;
SHOW CREATE TABLE pressrelease_notify_archive;
```

### What the script does

| Step | What is added | Why it matters |
|------|---------------|----------------|
| **Columns** | `field`, `evtype`, `domain_id`, `ipv6_id`, `email_id` | These columns exist in `pressrelease_notify` but are absent from the archive table. |
| **Indexes** | All keys that are present in the live table but missing from the archive (`is_open_idx`, `lookup_c`, `lookup_h`, `lookup_g`, `lookup_x`, `lookup_j`, `lookup_k`, `ix_match`, `lookup_to_email`, `lookup_reject`, `lookup_em`, `lookup_q`) | Indexes dramatically affect query performance and are part of the “identical schema” requirement. |
| **Verification** | `SHOW CREATE TABLE` for both tables | Lets you double‑check that the definitions now match. |

### Optional tweaks

* If you want the archive table **exactly** like the live one (including column order), you can add `AFTER <column>` clauses to place each column where it belongs.
* If the live table’s columns `field`, `evtype`, and `domain_id` are **nullable** (the `CREATE TABLE` you posted shows them as nullable), you may want to `MODIFY` those columns after adding them to match the nullability:

```sql
ALTER TABLE pressrelease_notify_archive
  MODIFY COLUMN `field`    varchar(16) DEFAULT 'email',
  MODIFY COLUMN `evtype`  varchar(16) DEFAULT '',
  MODIFY COLUMN `domain_id` int DEFAULT 0;
```

### Running it safely

1. **Backup** the archive table (or the whole DB) first.  
   ```sql
   CREATE TABLE pressrelease_notify_archive_backup LIKE pressrelease_notify_archive;
   INSERT INTO pressrelease_notify_archive_backup SELECT * FROM pressrelease_notify_archive;
   ```

2. **Wrap in a transaction** (if your storage engine supports it) so you can roll back on error:

```sql
START TRANSACTION;
-- run the ALTER statements above
COMMIT;   -- or ROLLBACK; on error
```

After the transaction commits, `pressrelease_notify_archive` will have the same column list and index set as `pressrelease_notify`. You can now treat the two tables as structural mirrors.
