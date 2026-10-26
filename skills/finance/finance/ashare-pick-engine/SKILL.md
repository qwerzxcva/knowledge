---
name: ashare-pick-engine
description: Use when 推股、大盘预测、题材发现或三角洲/时间窗类请求时。主板-only T+1 六层报告与触发式日历工作流。
---

# A 股推股与预测引擎工作流（投研小行家专属）

## 用户硬性约束（always-on）

- **主板 only**：排除 300xxx/301xxx/688xxx，只推 sh60x/sz00x（用户原话：「不要创业板/科创板，我买不了」）。
- **T+1 目标**：今天买明天卖赚 4%+；最低要求今天亏 1-2 个点明天赚回。输出必含 4% 限价与止损。
- **报告完整度**：每只票必须达到六层完整度（见 references/report-template.md），每层具体数字，不许定性空话——引擎已固化为 stock_report.py，先跑引擎。
- **时间预测只做触发式**：用户曾要求提升三角洲理论正确率；三角洲已用 35 年数据三层检验终审无效（农历日/相位/MLD 全灭），永久标注「不作独立信号」。时间窗需求一律走触发式日历（streak_calendar、冰点反弹日历），每个数字可复验。
- **只讲发生了什么，不给买卖建议**（事实与建议分离；决策量化字段照给，方向判断不包装）。
- 拿不到数据时明确说明，不用记忆旧价格充数；标注数据时间。

## 核心已验证规则（数字即结论）

- 涨停前兆 A 组：昨涨>3% + 量比 2-4 → 次日≥4% 触发 32%、涨停 8.4%（基准 2%）。陷阱：量比>4（爆量已晚）、光放量不涨。
- 板块级前兆：同板块多票同时放量（不管涨跌）→ sector_burst 引擎。
- 买入区间：昨收×(0.985~1.00)；高开>2% 不追等回踩（89% 会来）；全天不回踩放弃。
- 结构分化：指数 vs 等权 gap>+4 且上涨家数<15% = 二八拉抬，禁止据此推防守。
- streak 日历：连跌 3 日后次日胜率 70%（n=46）；连涨 3 日后次日胜率 37%（追高风险）。
- 状态日历（market_regime.py，取代裸连跌）：五维状态=连跌天数×5日跌幅深度×量比×MA20位置×距250日高回撤，36年8748日上证全史切片。分界结论：MA20上+连跌2-3+浅跌=反弹区（76-83%）；MA20下+一日急杀3-7%=接刀区（18-29%，禁接）；MA20下+回撤>35%=熊市延续区（10日中位-2.2%）。当前状态由引擎自动匹配历史同状态并输出次日/5日/10日统计。指数全史数据：akshare stock_zh_index_daily('sh000001') 一次拉36年，存 /tmp/sh000001_full.json；腾讯 ifzq 日期段参数报 param error、新浪 datalen>1023 返回 null、东财 push2his 403——都别再试。
- LGBM 双模型：v1 明日涨 AUC 0.585；v2 强涨专项（fwd>3%）AUC 0.682、TOP1% 命中 37.3%=3.3× 基准。
- 金格子（经三重验证，直接引用数字，勿重算）：①连板次日+平开~5%高开：+1.59%/笔、胜率61.6%、四年逐年全正；执行口径=限价回踩买+双边0.2%成本，「盘中触4%≠能赚4%」（先触止损概率55%+）。②G5=52W真突破（收盘>昨日250日max，列名 dist_52w_prev）+低波（amp_pct_250<0.55）：次日+3.25%、胜率68%（n=2026），前/后半分裂65%/70%稳定；甜区=突破日涨幅5-7%档（次日+2.93%/5日+7.43%）——≥7%次日追高买不进，<5%弱突破次日仅+0.85%。③缩量涨停封板（量比<2）次日+2.33%/5日+2.56% vs 放量封板5日-0.1%（n=33k）。④节前窗口（春节/国庆前5日）：+0.24%/日、62%胜率（36年全史）；月初效应2020s已退化勿用。负向警报（强制入avoid）：一字板开板10日-3.8%、涨停次日巨阴5日-2.9%、巨量上影次日-0.43%、强游资净买入5/10日后-1.6%/-4.0%（只可T+1）。聚合器 positive_signal_scan.py 输出 S1-S5+A1-A3，build_today_picks 已接入（engine=gold_scan）。
- 学术因子IC（主板2021+实测，供权重参考）：Amihud非流动性IC+0.044连续4年正；低波位置amp_pct_250 IC-0.041三年稳；52W锚定+0.5-0.7%事件效应；alpha158纯技术因子全部|IC|<0.04无信号，勿再单建日线技术因子引擎。三因子等权融合LS+0.15%/22日不稳已否决。quality_factors（ROE×2+净利增速+毛利率-负债×0.3，PIT生效日：年报5/1、中报9/1）单调有效Q5-Q1=+0.67%/10日，抗跌型相对alpha，防御性加权用。
- 前瞻标签基建：fwd_horizon表（factor_matrix.duckdb，全史216万行1/5/10日LEAD标签）已物化，新因子回测直接JOIN它，勿再用相关子查询（慢到超时）。

## 工作流程

1. **数据**：行情唯一入口 px_view / qfq_all.duckdb（sym 无点、d 列 VARCHAR 需 CAST AS DATE、列名 o/c/h/l/v）；指数不在 qfq_all → 用腾讯 ifzq fqkline 或 /tmp/mkt_series.json（35 年等权）。duckdb 大查询先 SET memory_limit='3GB'+temp_directory='/tmp/ducktmp'，逐批 INSERT+CHECKPOINT 防 OOM。
2. **推理**：lgb_infer.py 双模型走 factors_wide 最新截面（特征必须 115/115 全匹配——部分匹配会中位数填充输出常数 p≈0.32）。
3. **报告**：stock_report.py <sym...> 逐票出六层 JSON；资金连续性走新浪 MoneyFlow（带 Referer）。
4. **预测**：daily_market_pred.py 五法等权（相似K线/连跌结构/漂移/惯性/指数状态日历——market_regime.py 匹配 n≥40 时优先级最高，覆盖 streak_calendar 的粗口径）+ structure_lens 结构修正 + P10-P90 置信带。大盘预测必须给「什么状态下才反弹/才熊」的条件判定，不准只报裸连跌天数——用户明确批评过裸连跌太粗糙，要记录超跌反弹/熊市开启的完整条件组合。
5. **诚实检验门**：任何新因子/新理论上线前跑 data/ls_test_22d_correction.md 流程；fwd_ret 标签必须 lead() 非 lag()；因子分年审计≥3 年；月频回测用月末单一截面。
6. **推送**：GitHub contents API，脚本先写文件再执行（heredoc 内 token 会被运行时掩码替换）；20MB 是分片上限（90/40MB 均 422）；CI 判定用 check-runs；PUT 前先 GET 拿 sha（竞态 422 时重取 sha 再试一次）。

新因子/格子/事件的全部验证数字、负向警报与验证纪律集中在 `references/validated-factors.md`——上线新信号前先查该文件避免重复劳动。

## 引擎地图

`/home/agentuser/stockdb/t1/alphas/`：stock_report / lgb_infer / streak_calendar / market_regime / daily_market_pred / structure_lens / sector_burst / zt_predict / next_day_4pct / sector_rotation / theme_lane / emotion_gauge / youzi_engine / ak_adapter（akshare 1.19.1，push2 域 403）/ positive_signal_scan / event_pattern_engine / academic_factors / vol_structure / strength_decay / calendar_rules / rs_engine / youzi_follow / prediction_loop（预测→次日实际→胜率闭环，cron 8:05/16:05）。engine_registry v7=17 引擎（含已激活的 pead/quality_factors）。cron：盘中 20 分钟轮、16:15 因子增量、16:20 报告推送、18:00 LHB席位明细、周六重训。