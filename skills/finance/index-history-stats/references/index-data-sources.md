# 指数历史数据源选型

| 源 | 用法 | 限制 |
|---|---|---|
| akshare `stock_zh_index_daily` | `sys.path.insert(0,'/tmp/senv/lib/python3.12/site-packages')` 后 import；返回全史 date/close/volume | 首选；需 /tmp/senv |
| 腾讯 ifzq fqkline | `param=sh000001,day,,,800,qfq`（无日期版）| 上限 ~800 日；带起止日期报 param error |
| 新浪 CN_MarketDataService | datalen≤1023；jsonp `var([...])` 解析 | datalen 大返回 var(null)；量纲老数据不齐 |
| 东财 push2his kline | — | IP 级 403，别试 |
| /tmp/mkt_series.json | 35 年等权序列（dates/rets dict）| 无价格点位；有历史坏点需结构透镜校验 |

缓存落盘 `/tmp/sh000001_full.json`（[date, close, volume] 数组），引擎读缓存+定期刷新。

## 上线过的引擎（stocks-algo alphas/）

- `gold_cells.py`：金格子 check()（G1 MA20上×昨日大跌；G2 MA20上×大涨×量平；G3 回踩1日×放量；G4 连跌4日）
- `market_regime.py`：五维状态日历 + fetch_sh_index_full()（可在此复用刷新逻辑）
- `streak_calendar.py`：裸连跌/连涨反转窗（最弱，仅兜底）
- `delta_windows.py`：三角洲（检验未通过，永久标注仅供观察，勿删标注）
