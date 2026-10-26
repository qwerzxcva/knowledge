# A股个股档案 (listing_dates_full.json)

5564只个股(5224在市+340退市), 字段:
- name: 证券简称
- ipo_date: 上市日(baostock query_stock_basic, 权威)
- out_date: 退市日(空=在市)
- status: listed/delisted
- first_trade_date: 本地qfq_all最早K线日(本地数据起点, 老票晚于ipo_date属正常)
- last_trade_date: 本地qfq_all最新K线日(=2026-10-23为active)
- bars: 本地K线条数

来源: baostock(2026-10-26拉取) + 本地qfq_all.duckdb推导合并。
差异说明: baostock的ipo_date为真实上市日; qfq首日为本地数据回补起点。
