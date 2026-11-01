# factor_matrix 重建事故复盘 (2026-11-01)
## 事故链
1. 磁盘100% → DROP 21中间表 + 删 factor_matrix.duckdb (factors_wide 导出 parquet)
2. 导出 parquet 在磁盘满时被截断损坏 (未验证完整性!) — 双重丢失
3. 重建过程中两次磁盘100% (duckdb 5.7G→10G 增长超预期) → 删早年 5min parquet 腾挪
4. 第一轮重建 3 小时白算: 建表语句只有 (symbol,date) 2列, 114因子列靠 res[tw_cols] 对齐被静默丢弃
5. date 格式 '20240102' vs TIMESTAMP 混型 INSERT 失败 (两次修 CAST)
## 修复沉淀
- ALTER TABLE ADD COLUMN IF NOT EXISTS 逐因子补列 (factor_matrix.py main 头部)
- INSERT 统一 date: CASE WHEN length=8 THEN strptime('%Y%m%d') ELSE CAST(VARCHAR AS TIMESTAMP)
- 导出文件必须立即 read_parquet 验证 (footer magic bytes)
- 磁盘水位: duckdb 增长不可预测, 预留 2×预估空间
## 最终状态
factors_wide: 5577票 × 1361万行 × 118列, lgb_infer 三头+touch4_5min 第4头全部恢复在线
