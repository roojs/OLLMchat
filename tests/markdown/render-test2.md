`information_schema.TABLES` does not store a **live** row‑count.  
What you see in the `TABLE_ROWS` column is only a *statistics* value that MySQL updates
periodically (or when you run `ANALYZE TABLE`).  

When you connect through **MySQL Router** you are usually hitting a **read‑only
replica** (or a pool of replicas). Those replicas apply the binary log asynchronously,
so their statistics can be behind the primary server.  
Even on the primary, the value is only an estimate for InnoDB tables – it can be
off by a large factor if the table has been heavily updated since the last
statistics refresh.

### Why the numbers differ

| Situation | What `TABLE_ROWS` shows | Why it can differ from the “real” count |
|-----------|------------------------|----------------------------------------|
| **InnoDB table on the primary** | Approximate value based on the InnoDB “persistent statistics” (or on the last `ANALYZE TABLE`) | InnoDB does not maintain an exact row count; it estimates from page density. |
| **Read‑only replica behind the primary** | Same approximate value, but **stale** because the replica may not have applied recent changes yet | Replication lag → statistics are older than the primary’s current state. |
| **MyISAM table** | Exact count (MyISAM stores the row count in the .MYD file) | Usually accurate, but still may be out‑of‑date on a replica. |
| **`SELECT COUNT(*) FROM …`** | Exact count (full table scan or index scan) | Guarantees correctness but can be expensive on large tables. |

### What you can do

1. **If you need an exact number**  
   ```sql
   SELECT COUNT(*) AS exact_rows FROM your_table;
   ```
   *Beware*: on a large table this can be slow because it must read all rows (or at
   least all index entries).

2. **Refresh the statistics** (helps the estimate become more accurate)  
   ```sql
   ANALYZE TABLE your_table;
   ```
   After `ANALYZE`, the `TABLE_ROWS` value will be recomputed from the current
   page statistics.

3. **Connect directly to the primary** (if you are allowed) to avoid replication lag:  
   Use the endpoint that points to the primary rather than the Router’s read‑only
   pool.

4. **Check replication delay** if you suspect the replica is lagging:  
   ```sql
   SHOW SLAVE STATUS\G   -- (or SHOW REPLICA STATUS\G on MySQL 8.0+)
   ```
   Look at `Seconds_Behind_Master`. A non‑zero value indicates that the replica
   is not fully up‑to‑date.

5. **Use `SHOW TABLE STATUS`** for a quick estimate that also includes the
   `Rows` column (same kind of estimate as `information_schema`). Example:  
   ```sql
   SHOW TABLE STATUS LIKE 'your_table';
   ```

6. **If you need a reliable “live” count for monitoring**, consider:
   * Maintaining a **counter column** that you increment/decrement in your
     application logic (e.g., via triggers or the app itself).  
   * Using **pt‑table‑summary** from Percona Toolkit, which can give a fast,
     approximate row count with configurable sampling.

### TL;DR

- `information_schema.TABLES.TABLE_ROWS` is **only an estimate** (for InnoDB) and can be stale on replicas.
- MySQL Router may be sending you to a replica that is behind the primary, causing the discrepancy.
- For exact numbers run `SELECT COUNT(*)` (or maintain a separate counter).  
- Run `ANALYZE TABLE` or connect to the primary if you need a more accurate estimate quickly.

Feel free to share the exact environment (MySQL version, Router configuration, whether you’re using read‑write splitting, etc.) if you’d like a more tailored set‑up or a script to automate the refresh/verification process.