# 语言工程知识库 v1 — gitcode 开源 Kotlin/Rust 大项目蒸馏 + 我方代码资产格局

> 2026-10-31 · 审计 7 个开源项目（3 Kotlin / 4 Rust）+ 我方 gitcode 103 仓盘点

## 一、我方 gitcode 代码/数据资产格局
| 类别 | 仓 | 说明 |
|---|---|---|
| Python 算法 | stocks-ops / stock-pead-engine / stock-quant-engines / stocks-holo / engine-core / stock-system / stock-data / jx1 | 引擎蜂巢+engine-chain, 已蒸馏入 code_kb |
| 数据仓 | stocks0.38~0.87（50 个版本快照, Markdown 索引）/ stock-market-data / stock-feature-samples×6 / stock-altdata-sec | 数据分散防封, 边跑边传边删 |
| Shell | stocks0.25/0.13 | 采集脚本 |

## 二、Kotlin 大项目蒸馏（3 个, 480 kt 文件）

### Eyepetizer（123 kt, MVVM+Jetpack）
- 架构: MVVM 40 票 / ViewModel 29 / 协程 22 / 委托属性 14（`by viewModels`）/ Flow 8
- 可学模板: 单 Activity + Navigation + Fragment 导航; `by lazy`/`by viewModels` 委托消除样板

### PlayAndroid（138 kt, MVVM+Hilt+Room, 多模块 core/app）
- 架构: MVVM 52 / **Hilt 47** / ViewModel 35 / LiveData 32 / 协程 28 / Room 11
- **核心模板（可直接复用）**: `BaseAndroidViewModel<BaseData, Data, Key>` 抽象分页基类——
  `pageLiveData.switchMap { getData(it) }` 把分页状态装进 LiveData 流, 子类只实现 `getData(page)`;
  Repository 层统一 Room 缓存 + Retrofit 网络 + DataStore 配置三通道
- 泛型基类 + switchMap 是本项目最值得抄的"减少复杂代码"样板

### WanAndroid（219 kt, MVP 单Activity）
- 架构: MVP Presenter 97 / 委托 26 / Retrofit 25 / 单 Activity Navigation 13
- 对照价值: 与 PlayAndroid 形成 MVP vs MVVM 同域对照——MVP 契约类(contract)多、样板重, MVVM+Flow 更精简; 新项目选 MVVM+Flow+Hilt

### Kotlin 蒸馏结论（质量优化准则）
1. 用 `sealed class/interface` 封装 UI 状态（Loading/Success/Error），消灭布尔旗标
2. 泛型基类 + `switchMap`/`flatMapLatest` 收敛分页/刷新逻辑
3. 协程异常统一: `viewModelScope + SupervisorJob + CoroutineExceptionHandler`
4. Hilt 注入 Repository, 不在 ViewModel 里 new 依赖
5. `data class` + `copy()` 做不可变状态更新

## 三、Rust 大项目蒸馏（4 个, 1008 rs 文件）

### atomMqtt（107★, MQTT broker, workspace 三 crate 分层）
- 分层: mqtt-core（v3/v5 codec 各自独立模块, 协议编解码零耦合）/ mqtt-broker（server 66KB 单文件消息路由）/ mqtt-web（API）
- **核心模式**: `mpsc::unbounded_channel` + `tokio::spawn` 后台消息路由器; BrokerHandle 克隆 sender 给所有连接任务; 原子计数器（`AtomicU64 fetch_add Relaxed`）做 metrics 无锁统计
- 订阅树 lookup + 状态锁最小化（只锁 subscriptions 查找, IO 全在任务内）

### rust-postgres（132 rs, 异步 PG 驱动）
- **核心模板**: `pub async fn query<P: BorrowToSql, I: IntoIterator<Item=P> + ExactSizeIterator>` —— 参数泛型不 collect 零拷贝编码; RowStream 惰性行流
- 错误处理: Result 贯穿 79 文件, 无 panic 路径; trait `BorrowToSql` 抽象参数类型（避免 String clone）

### rhai（328 rs, 嵌入式脚本引擎）
- Iterator 链 103 处 = 函数式数据管道替换手写循环; 枚举状态机 42 个; 宏 25 处（DSL 内建）
- 错误枚举带结构化字段（`OutOfOrder { at: u32 }`），错误即诊断信息

### uniffi-rs（520 rs, FFI 绑定生成器）
- trait 抽象 96 + Arc 并发 70 + 宏生成 56: 用 `proc-macro` 从 UDL 生成多语言绑定, 消灭手写 FFI 样板

### Rust 蒸馏结论（质量+效率准则）
1. **枚举状态机 > 布尔旗标组合**：协议/连接/订单状态全用 `enum` + `match` 穷尽检查
2. **零拷贝**: API 接口收 `impl IntoIterator`/`AsRef<[u8]>`/trait 抽象, 不在边界 collect
3. **无锁指标**: `AtomicU64 + Relaxed` 替代 Mutex 计数
4. **channel 路由**: mpsc + spawn 后台任务, handle 克隆分发, 代替共享锁全局状态
5. **错误即数据**: thiserror 枚举带字段, 上层可 match 恢复
6. **workspace crate 分层**: core(协议/纯逻辑) / server(运行时) / api(边界) 零交叉
7. `unsafe` 最小化（rhai 7/328, postgres 1/132）——需要时集中封装并注释不变量

## 四、对我方 Python 算法链的迁移映射
| 大项目模式 | 迁移到我方链路 |
|---|---|
| atomMqtt 消息路由(channel+后台任务) | 蜂巢中枢调度可改为消息驱动(引擎结果→路由器→融合), 当前为同步顺序调用 |
| rust-postgres 泛型零拷贝 | fetchers 模块统一 `Iterable` 输入, 消除中间 list 复制(大DataFrame分批) |
| rhai 错误枚举带字段 | hive 引擎 meta.err 从字符串改结构化 {stage, sym, reason} |
| PlayAndroid 泛型分页基类 | 数据回补脚本统一 BaseBackfill(分页/断点/幂等)基类 |
| MVP vs MVVM 对照 | 引擎保持"正交域+薄中枢"路线正确, 中枢不得长成 MVP 式胖协调者 |
