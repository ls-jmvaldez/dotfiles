---
name: managing-databases
description: Guides database architecture decisions for PostgreSQL, DuckDB, Parquet, and PGVector. Use when designing schemas, choosing storage strategies, optimizing queries, tuning maintenance, configuring vector search, or diagnosing performance issues.
license: MIT
compatibility: opencode
---

# Database Management

Decision guidance for PostgreSQL, DuckDB, and Parquet in hybrid storage architectures.

## When to use which database

| Workload                              | Use                       | Why                                 |
| ------------------------------------- | ------------------------- | ----------------------------------- |
| Transactional (CRUD, users, sessions) | PostgreSQL                | ACID, row-level locking, indexes    |
| Analytical (aggregations, scans)      | DuckDB                    | Columnar, vectorized, parallel      |
| Data storage/interchange              | Parquet                   | Compressed, columnar, portable      |
| Metadata + relationships              | PostgreSQL                | Foreign keys, constraints           |
| Ad-hoc exploration                    | DuckDB                    | Fast on Parquet, no ETL needed      |
| Time-series with point lookups        | PostgreSQL + partitioning | Partition pruning + indexes         |
| Time-series analytics                 | DuckDB on Parquet         | Scan performance                    |
| Vector similarity search              | PostgreSQL + PGVector     | HNSW/IVFFlat indexes, hybrid search |
| RAG / semantic search                 | PostgreSQL + PGVector     | Embeddings + metadata in same DB    |

**Hybrid pattern example:**

- PostgreSQL: transactional data, relationships, users (metadata)
- DuckDB + Parquet: analytical content, aggregations, time-series

## PostgreSQL quick reference

**Use for:** Metadata, relationships, OLTP workloads, anything needing ACID.

**Key decisions:**

- Partition tables >100M rows or with retention requirements
- Index columns in WHERE/JOIN clauses, not everything
- Tune autovacuum for high-churn tables

## DuckDB quick reference

**Use for:** Analytics, aggregations, Parquet queries, data exploration.

**Key decisions:**

- Prefer Parquet files over CSV (10-100x faster)
- Let DuckDB auto-parallelize; don't micro-optimize
- For remote data, increase threads beyond CPU count

## Parquet quick reference

**Use for:** Storing analytical data, data interchange, columnar compression.

**Key decisions:**

- Target 128MB-1GB file sizes
- Partition by low-to-moderate cardinality columns (date, region)
- Sort by columns used in filters for better pruning

## PGVector quick reference

**Use for:** Similarity search, RAG applications, semantic search, recommendations.

**Key decisions:**

- HNSW for low-latency, high-recall (default choice)
- IVFFlat for memory-constrained or batch-updated data
- Use iterative scan for filtered queries
- Consider hybrid search (vector + keyword) for 8-15% accuracy boost

## Cross-database conventions

### Naming

| Convention             | Example                  | Applies to    |
| ---------------------- | ------------------------ | ------------- |
| snake_case tables      | `dataset_jobs`           | All           |
| snake_case columns     | `created_at`             | All           |
| Singular table names   | `dataset` not `datasets` | PostgreSQL    |
| Plural for collections | `datasets/` directory    | Parquet files |

### Timestamps

- Store as UTC always
- PostgreSQL: `TIMESTAMPTZ`
- Parquet: `TIMESTAMP` with `isAdjustedToUTC=true`
- DuckDB: reads both correctly

## Performance debugging checklist

### PostgreSQL slow query

1. Run `EXPLAIN (ANALYZE, BUFFERS)` on the query
2. Check for sequential scans on large tables
3. Verify indexes exist on filter/join columns
4. Check `pg_stat_user_tables` for bloat (dead tuples)
5. Review `work_mem` if seeing disk sorts

### DuckDB slow query

1. Check if reading CSV instead of Parquet
2. Verify not doing `SELECT *` on remote data
3. Check thread count matches workload
4. Look for unnecessary type conversions

### Parquet slow reads

1. Verify predicate pushdown is working (check query plan)
2. Check file sizes (too small = overhead, too large = no parallelism)
3. Confirm data is sorted by filter columns
4. Look for high-cardinality partition keys (too many small files)
