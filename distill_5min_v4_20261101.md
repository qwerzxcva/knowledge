# 5min 全史重训 + 按月复核 (v4)
## 修正记录 (诚实)
- 初版训练标签依赖 qfq 日K表, 审计发现其 1991-2022 残缺 (每年数百~数千行, 2023 起才完整) → 148万样本名不符实
- 修复: 从 5min parquet 自建全史日频标签 (1400万 sym-day, labels_5min.duckdb), 除权异常过滤 (|ret|超界剔除, 未复权口径已标注)
- 62 轮总训练: 22+22+18, v4 全史 1026万主板样本 (train 821万 / OOS 205万)
## v4 结果
- touch4 (次日触+4%): OOS AUC 0.7513±0.0004 (18轮 std 极小), TOP组 precision 77.7%, TOP均值 +2.39%/日未扣成本
- nextday: 0.5349 (绝对涨跌仍难测)
- 严格时间外按月复核 (train 2024-25 → va 2026 全段): 01月 0.744 / 02月 0.761 / 03月 0.760 / 04月 0.680 (至4/10样本短), TOP precision 73.7%, TOP均值 +2.51%
- 复核通过: 无崩塌月, 模型非靠单一时段
## 教训沉淀
- 标签表必须先审计覆盖度再合并 (min/max/count per year)
- duckdb: 聚合不能包窗口→先逐行算; regexp_extract group 参数此版本失效→substring; 大窗口 spill→逐年提取
- 早期 parquet 列名 sym vs 后期 code_raw → 提取前 DESCRIBE 分派
