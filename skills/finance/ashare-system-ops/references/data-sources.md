# 数据源速查

## 腾讯实时 (qt.gtimg.cn/q=)
- 逗号分隔多标的; 返回 GBK, `~` 分隔
- 字段: 1名称 2代码 3现价 4昨收 5今开 30时间戳 32涨跌% 33开盘 34低 36量 38换手
- 指数: sh000001 上证 sz399006 创业板 sh000688 科创50 sh000905 中证500 sh000016 上证50
- 外盘: usDJI usIXIC hkHSI hkHSTECH (恒生科技与 A 股科创联动最强)
- 资金流 ff_ 接口已失效 (none_match)

## 东财
- 涨停池: `push2ex.eastmoney.com/getTopicZTPool?ut=7eea3edcaed734bea9cbfc24409ed989&dpt=wz.ztzt&pagesize=320&date=YYYYMMDD` — **必须带 date**, 字段 n=名 c=代码 lbc=连板; 跌停用 getTopicDTPool
- clist/push2 行情列表: 403 风控常态, 别依赖
- f10 公司概况: `emweb.securities.eastmoney.com/PC_HSF10/CompanySurvey/PageAjax?code=SH6009xx` 返回 gzip, jbzl[0].INDUSTRYCSRC1 = 证监会行业 (行业映射源, 按需+缓存)

## baostock
- 代码格式 `sh.600000` 9位; query_profit_data/query_growth_data (PIT: pubDate+statDate)
- 会话易静默卡死: 单票查询无超时会无限挂 — 外层 watchdog (日志打点停滞 8 分钟杀重启+断点续跑) 或 RS_MAX 限制; 不要用 socket.setdefaulttimeout 修 (长连接会直接死, 命中率归零)
- 科创 688/次新覆盖差 (命中率骤降不是 bug 是覆盖极限)
- 写 factor_matrix 期间禁止只读连接 (锁冲突静默丢 insert)

## gitcode (dufuwuxin)
- API: `gitcode.com/api/v5/...?access_token=<tok>` (query 参数), UA=curl/8; tarball 端点拉大包
- commits 判断活跃度; 活跃仓: stock-system (scripts/ 200+, data/ths/f10), stock-data (日更), engine-core; 空占位仓: stock-market-data / stock-altdata-sec / stock-feature-samples*
- 可复用脚本: ban_prob.py (涨停连板实证表), flow_divergence.py (资金流背离斜率法), cycle_algo.py (季节性), weight_calibrator_v2

## GitHub 上游
- db-fin-0: data/fin_indicator/fin_indicator_YYYY.parquet, 14 字段含 announce_date (真 PIT), symbol 格式 shXXXXXX; 2024/2025 上游为空, 2026 含 Q3
- analysis-hub: data/ai_picks.json (ts/date/anchor/规则/picks/observe_only)
- db-market: market/ 内容常滞后, 只 review_history.jsonl 在追加 (且常为空壳 n_picks=0 = 上游引擎停摆)

## 指数全史 K 线 (大盘统计必备)
- 腾讯 ifzq 只给近 800 日且指数日期范围参数会报 param error; 新浪 datalen 上限 1023 且 5000 返回 var(null); 东财 push2his 403 — **唯一稳定全史源: akshare `stock_zh_index_daily(symbol="sh000001")`** (8700+ 日自 1990), 存 /tmp/sh000001_full.json 供 gold_cells/market_regime/streak_calendar 共用, 建议每周刷新
- 大盘条件化统计(状态→次日分布)必须拿全史: 800 日样本连跌3日组只有 46 个, 36 年才够分桶

## 软件端数据源 (skapp 消费)
- stock_names.json 格式 {"sz000001": "sz000001 平安银行"} (code 前缀+名字在同串); universe.json 是 {ts,n,codes} 列表结构, 不含名字 — 从 codes 字段取不到 name, 取名字走 stock_names.json
- llm-models 仓 MANIFEST.json 是端侧 LLM 分片下载入口 (raw 200, API 也 200; raw 偶发 000 重试即可)
