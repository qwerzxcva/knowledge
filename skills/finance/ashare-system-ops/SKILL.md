---
name: ashare-system-ops
description: "Use when operating the stockdb/t1 A-share system."
---

# A股云股票体系运维 (stockdb/t1)

## When to Use
- 用户要求看盘/推股/复盘/预测大盘、维护引擎或数据管道、同步 gitcode/GitHub 仓库时
- 关键词: 推股、复盘、引擎、优化、回测、盯盘、跟进上游、skapp

## 环境与路径
- 引擎代码: `/home/agentuser/stockdb/t1/alphas/` (算法库) + `engine_registry.py` (12 引擎注册表, 单一事实源)
- 主库: `t1/qfq_all.duckdb` (qfq_raw: sym,d,o,c,h,l, date 为 VARCHAR 需 try_cast); 因子矩阵: `stockdb/factor_matrix.duckdb` (factors_wide/px/mf_factors/fin_pit_up/zt_* 表)
- Python: 只用 `/tmp/senv/bin/python` (duckdb+baostock 装在里面); 系统 python3 无 duckdb
- 上游镜像: `stockdb/upstream/` (从 gitcode/GitHub 拉的外部数据)

## 数据层 (三源)
1. 实时: 腾讯 `qt.gtimg.cn/q=<sym>` (f[3]现价 f[4]昨收 f[32]涨跌% f[30]时间戳; 403/501=限流, 换接口或稍后重试; 东财 push2ex 涨停池需 date=YYYYMMDD 参数, 否则 data=None 不报错)
2. GitHub 爬虫源: db-fin-0 (1988-2026 PIT 财务 parquet, INDUSTRYCSRC1 行业在 f10), db-min-0 (5分钟线), analysis-hub ai_picks.json (另一 AI 每日推股)
3. EOD 回填: 收盘后用实时接口快照回填主库 (K线接口被限时); 高低价字段次日修复

### 数据源坑
- gitcode API: token 用 `?access_token=` query 参数 (Authorization header 报 400); 仓库列表 `size` 字段恒为 0, **判断空仓必须查 commits**, 不是 size
- gitcode clone 必须完整 (勿 --depth 1), push 才不报 unpack failed
- 东财 push2/clist 接口普遍 403 风控 (带 UA+Referer 也不稳); 优先腾讯源
- f-string 里带 `%3A` 的 URL 不能用 `%` 格式化, 用 f-string

## duckdb 坑 (每次都可能踩)
- **写连接持有期间任何只读连接都会锁冲突; 更隐蔽的是写入方的 insert 因锁竞争静默丢失** — 写库期间禁止开第二个连接检查, 等打点日志推进
- 大查询先 `SET memory_limit='4GB'; SET temp_directory='/tmp/ducktmp'`; window 函数不能嵌在 aggregate 里 (先 pr CTE 再 group)
- 磁盘报 no space 时先查 temp 目录与另一写进程, 主库 7.5GB 预留 2x 空间
- `d` 是 VARCHAR: 全部 `try_cast(d as date)`, 不能直接减 interval
- drop 表不回收空间, 缩文件只能导出重建

## 推送 GitHub
- 推送脚本**必须先写文件再执行** (heredoc 内 token 会被运行时替换成掩码); token 从 /tmp/tok3.txt /tmp/toka.txt 读, grep 用 `ghp_[A-Za-z0-9]{30,}` 30+ 长度排除掩码串
- contents API PUT: 先 GET 取 sha (新文件 404 跳过), 带 4-6 次重试 (SSL EOF/超时常见); 大批量推文件加 time.sleep(1)
- git clone 大包经常连不上: 用 tarball API (`/tarball` 端点) 代替; GitHub 公共仓也可用 codeload tarball (`codeload.github.com/<owner>/<repo>/tar.gz/refs/heads/main`) + curl 重试循环

## akshare (1.19+, 已装 /tmp/senv)
- 一次 `pip install akshare` 得数百接口; 本机 push2.eastmoney 域仍 403 (全A快照/东财板块名/个股资金流不可用), 其余逐个验证: hsgt北向 / stock_fund_flow_concept(同花顺387概念) / stock_comment_em千股千评 / stock_zh_a_gdhs股东户数 / stock_lhb_detail_em龙虎榜带解读 / stock_market_activity_legu情绪 / news_cctv / stock_financial_abstract / stock_gdfx_free_top_10_em 可用
- 封装层 alphas/ak_adapter.py: 统一 _cached 装饰器 (md5 key, TTL 分 realtime/daily) + 3次重试; 新接口先单测再用, 部分接口分页爬取耗时数十秒

## 回测纪律 (违反即结果作废)
1. 月频回测只用月末单一截面 (月内全日截面虚增 3-4 倍)
2. 因子注册需 ≥3 年分年审计; fwd_ret 标签必须 lead() 不是 lag()
3. 双源 union 会重复计数 — 一切取数走 px_view 口径
4. 长后台脚本加 flock, 杀进程要查孤儿 (父=init 的要 kill -9)
5. 新引擎上线前: 全史分年 OOS 验证 (参照 GBDT 四分片验证模式: IS70/OOS30, 各分片单调才算有效)

## 每日推股链路 (chain_v1.md)
数据层(3源并行) → 因子层 → 市况判定(串行: bull_bear_phase 250日均线 + rebound_regime 三剧本 + sentiment 温度计 + overseas 联动) → 6模块并行(消息/多池/情绪/异动/玄学/推股, 每模块主引擎最高权重+联动次要) → 中枢 fuse **≥4 票 high 才推, ≥2 mid 次之, 单引擎信号直达用户是违规** → pick_tracker 登记 T+1/T+5 回查, 命中率反馈权重

### 模块权重原则 (用户定调)
- 每模块: 本职引擎 1.0 主导, 联动引擎 0.3-0.5 次要
- 玄学类 (八字/星座/风水): 权重 0.2 参与计分, **不单独推票**, 输出必须带文化参考声明; 数据证伪的 (尾数8) 永不收录
- 推股模块独占: 全部引擎供结果, 中枢判断; 市况闸门 (恐慌→降仓, 冰点→只推防守)

## skapp 软件链路 (检查与修复)
- 仓库拓扑: 软件=jiegengxiangjianxue/skapp (不是 1 号账号); 数据三件套 qwerzxcva/stocks-ai-view data/data/{today_picks,decision,stock_names}.json; 搜索表 qwerzxcva/skapp-data search/symbols.json; 个股分片实际只有 db-stocks-a/b/c/d 四仓 (路径 <repo>/main/<前2位>/<code6>/stock.json, db-stocks-e 不存在 — RemoteSources.kt 分片映射里 8x/9x 前缀指向 e 是错的, 改指 d)
- 检查软件是否可用: 逐个 curl -o /dev/null -w "%{http_code}" 实测软件读的每个 raw URL (000=网络抖动重试 2-3 次再判定, 404 才是真缺); 东财 push2 403 但腾讯 qt.gtimg.cn + ifzq.gtimg.cn K线始终可用
- 推股生成链路: engine-chain.yml (CI) 跑 scripts/build_today_picks.py --force → 写 data/today_picks.json → skapp-app-data.yml 镜像到 data/data/ → 软件读; 名字/过滤类修复改完脚本必须重跑 engine-chain 再触发 skapp-app-data, 只改上游不重跑则软件端看不到
- CI 里路径与本地不同: build_today_picks 的 DATA_DIR 在 CI 是 data/ (本地是 data/data/), fallback 读数据文件要两个布局都试
- 本地 /tmp/skapp-app 不是 git 仓, 单文件修改用 contents API PUT (先 GET sha); Kotlin 无需本地编译, CI 会 build 验证

## 每日节奏
1. 盘前: 引擎链跑当日票单 (开盘剧本判定: A反弹/B震荡/C恐慌 三选一)
2. 盘中: 三层监控每20分钟轮 (sector_watch 49板块资金向 + news_pulse 快讯题材向 + live_monitor 个股); 异动告警 (板块|pct|>2%/涨停骤降/外围冲击/连板断层/分时脉冲)
3. 收盘: EOD 回填主库 (注意回补脚本覆盖盲区: 按日期缺口筛待补票, 勿用「已有近期数据即跳过」口径, 会漏当天) → 引擎重算 → structure_lens+emotion_gauge+游资榜 → 明日票+复盘推双仓
4. 模型闭环: 16:10 append_daily_sample (截面 parquet→data/samples/) + 16:15 append_factors_daily (ATTACH qfq_all 增量补 factor_matrix.factors_wide, qfq 日期列 VARCHAR 需 CAST; **factors_wide 停更会让 LGBM 推理吃旧截面**) + 周六 retrain_weekly 重训
5. 每日报告 16:20 推 stocks-algo/reports/ (大盘预测+结构+板块+消息+题材+游资); gitcode AI 无公开API (认证通但分析接口418), 报告镜像同步后供用户前端用 gitcode AI 分析
4. 上游跟踪: gitcode stock-system CI / stock-data 日更 / analysis-hub ai_picks — 合并前去重: 特征重叠的不重复计票, 独立维度才注册新引擎

## 诚实纪律 (用户红线)
- 只报告发生了什么, 预测必须给概率+置信+反面剧本; 推荐败了要复盘根因不找借口
- 组合必须多风格对冲 (防守/轮动/进攻各≥2票), 单风格全押是上次失败根因
- 删任何端数据前必须先确认用户
- 语言: 中文; 数字给具体价格区域, 不给空话
- **票单主板 only (用户硬约束)**: 只推 sh60x/sz00x (含原中小板002), 排除 300/301/688 前缀; 买入区间不是单点价 (用户买不到高开的票)
- 预测分歧不掩盖: 单点预测与相似路径置信带方向相反时双口径并列交中枢/LLM权衡
- 结构市教训: 用等权均值序列判断市况会被权重拉抬误导 (指数+2.29% vs 等权-2.64% 的二八日曾导致误判防御踏空大反弹) — 市况判定必须同时看指数与等权宽度 (structure_lens), 大盘预测已接结构修正第五法

详见: references/data-sources.md, references/engines.md
