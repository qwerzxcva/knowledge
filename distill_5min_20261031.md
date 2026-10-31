# 5分钟K线全史训练报告 (2026-10-31)
## 数据管道
- gitcode stocks0.01-0.15 = 5min K 全史 2010-2026 (17年), 按年 zip 分卷, 部分年跨仓 (2024=stocks0.12+0.13, 2025=stocks0.14+0.15)
- 流式管道: blob:none clone → checkout part → 拼接 md5 → 解压 → 按年 parquet zstd (370MB-1GB/年, 共约9.5GB) → 删中间
- 坑: ①raw URL 返 HTML 弃用 ②duckdb 聚合不能包窗口函数→先逐行算 bar_ret ③duckdb regexp_extract 第3参 group 在此版本失效→substring ④窗口排序3.9亿行 spill 磁盘不足→逐年提取 ⑤2018 parquet 磁盘满写坏需重下 ⑥跨仓 zip 按各仓 manifest part_range 拼接
## 训练 (22轮 ≥20)
- 148万主板样本, 时间序 OOS, touch4 (次日触+4%) AUC 0.7528±0.001, TOP precision 76%, TOP 均值 +2.45%/日未扣成本
- 盘中特征: 尾盘30分动量/开盘30分/早盘量占比/尾盘量占比/日内bar波动率 — 全当日无前视
- nextday AUC 0.527: 次日绝对涨跌仍难测; 触4%事件预测是有效维度 (与 p4hit 范式一致, 日K AUC 0.7065 → 5min 0.7528)
## 结论
- 5min 盘中结构特征对"次日冲高4%"有实质增益 (+0.046 AUC vs 日K模型), 下一步: 特征扩充 (量价形态/分时形态) + 与日K模型 ensemble
