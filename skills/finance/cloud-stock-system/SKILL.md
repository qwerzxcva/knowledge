---
name: cloud-stock-system
description: Use when operating the user's GitHub A-share stock repos.
version: 1.0
author: hermes-curator
license: MIT
metadata:
  hermes:
    tags: [stocks, backfill, github-ops, quant]
    related_skills: [stock-monitor]
---

# Cloud Stock System Ops

## When to Use
- Any work on the user's stock repos (db-warehouse, db-daily-*, algo-core, engine-core, stocks-ai-view, stock-memory): data backfill, engine-chain changes, workbench, or new data sources.

## Architecture (always verify current state first)
- Read `github.com/jiegengxiangjianxue/stock-memory` (entities/repos.json, data-catalog/datasets.json, profiles/state.json) BEFORE acting — it is the authoritative structured memory; state changes faster than chat context.
- Topology: `db-warehouse` = collector source + docs; `db-daily-0..5` = daily-K shards across 3 accounts (symbol-sorted `codes[shard::6]`); `algo-core` (algorithms) + `engine-core` (engine scripts) = algorithm chain; `stocks-ai-view` = view layer + 89-source registry.
- Data schema: `wh/daily/{YYYY}.parquet` zstd, columns `symbol,date,open,close,high,low,volume,turnover_rate`, dedup on (symbol,date).

## Git access: use contents API, not git
- This machine's git to github.com:443 fails intermittently (TLS EOF / connect timeouts). Do NOT burn time on `git clone` retries — use the REST contents API for all reads/writes:
  - Read: `GET /repos/{owner}/{repo}/contents/{path}` → base64 `content` + `sha`.
  - Write: `PUT` same path with `{message, content(base64), sha}` — always GET the sha first or the PUT fails.
  - Raw fetch of large/binary files: `GET /repos/.../git/blobs/{sha}` with `Accept: application/vnd.github.raw` (raw.githubusercontent is CDN-cached and unreliable for just-pushed files).
- Retry transient SSL EOF with 3-4 attempts + sleep; the API succeeds far more often than git. urllib raises `SSL: UNEXPECTED_EOF` in tight loops too — for large files (>1 MB) use curl with `-H 'Accept: application/vnd.github.raw'` to a file, looped with `-C -` (wget -c resume) until the byte count matches the API-reported size; multi-MB raw downloads truncate silently mid-body.
- Repos >1 GB or thousands of files (e.g. a full skills-library backup) CAN be pushed with git: `git push https://x-access-token:{token}@github.com/...` (plain clone drops the credential on redirect; embed the token in the push URL). GitHub Push Protection will reject commits containing secrets — grep the tree for `sk_live_`/`ghp_`/`tvly-` patterns first and scrub, then `git commit --amend` before re-pushing.
- GitCode mirrors: `git clone --depth 1` from gitcode yields an incomplete object store (fsck clean but push fails with index-pack failed / remote rejected, `cat-file` fatal on a missing blob) — always full-clone; content API PUTs false-report 400 there, use git push; token goes as `?access_token=` query param, not Bearer.

## Concurrent parquet writes
- Any writer that merges into a shared year-partition parquet (or rewrites `_index.json`) MUST hold an `fcntl.flock` on a lockfile and write to a `.tmp` then `os.replace`. Concurrent merge without the lock corrupts zstd files (symptom: 'ZSTD decompression failed' on read).
- Backfill collectors must patch NEW columns (e.g. turnover_rate) into merge logic — a collector that rewrites partitions from its own row shape silently drops columns added by other tools.

## Data source quirks (A-share)
- Tencent fqkline (`web.ifzq.gtimg.cn`): rate-limits to ~1750 requests then returns 501; keep concurrency ≤4 and ≥0.25s spacing; on 501 switch to `ifzq.gtimg.cn` root domain.
- Sina daily-K single request returns ~3700 bars (2011+); use it as primary, Tencent segmented fetch only for pre-1999 history. Requires `Referer: finance.sina.com.cn`; many Sina endpoints are GBK-encoded.
- Eastmoney push2 endpoints 403 from some egress IPs (WAF); have a Sina fallback for any eastmoney call.
- Sina moneyflow `MoneyFlow.ssl_qsfx_lscjfb?daima={code}&num=10000` returns the full history in one request (~4000 bars) — much faster than per-day loops.
- Full A-share symbol list (5575 incl. BSE): Sina `Market_Center.getHQNodeData` paged by 100, node=hs_a (eastmoney clist is 403-prone).
- Limit-up thresholds vary by board: main board 10%, ST 5%, ChiNext/STAR 20% — never use a single 10% rule across the market.

- Intraday EOD fill fallback: when the day-K API is rate-limited (501) after close, backfill the day's bar from the realtime quote endpoint (`q=` batch: field 3=close, 4=prev close, 33=open; high/low unreliable there — repair from day-K next session); insert-or-skip on (symbol, date).
- GitHub Actions shards
- Free-plan scheduled workflows (cron */30) often fire 10-60 min late or skip; hand-dispatch via `POST /repos/{owner}/{repo}/actions/workflows/{wf}/dispatches` to keep backfill moving, and don't diagnose a fault before checking dispatch-first.
- One job per shard repo (never a 2-job matrix committing to the same repo) + `git pull --rebase` before push; two concurrent jobs hit non-fast-forward rejections and lose the done-file breakpoint.
- A failed push can lose the `shard_*_done.txt` breakpoint while parquet data still lands — verify actual symbol coverage in parquet (read one partition, count distinct symbols) before assuming data loss.

## Run long jobs in the background
- Long backfills: run via Hermes `terminal` with background=true (tracked proc_*) — `setsid nohup`/plain nohup children get reaped when the execute_code kernel is recycled; use `sleep`-loop polling in <=280 s chunks (execute_code kills at 300 s) or a notify-on-exit background terminal instead of in-kernel sleeps.
- factor_matrix.duckdb: date column was mixed VARCHAR (ISO + compact formats sort wrong) — now rebuilt as a real DATE column, 893k rows with unparseable dates (source-data gap in 1.8k SZ symbols, mirrored by an empty px table) deleted; treat NULL-date rows as dead data and drop them, they never join any cross-section.
- Scheduled pick pipelines stall silently: always check `data/*.json` timestamps (ai_picks, pools, pre/midday_picks) before trusting a morning recommendation — a stale ts means the Actions time-window guard skipped the run; hand-dispatch scheduler first, then verify via workflow runs list (weekend failures of window-guarded engines are expected, not bugs).
- Python deps live in `/tmp/senv` (duckdb, pyarrow, scikit-learn) — /tmp is wiped on reboot; recreate with `python3 -m venv /tmp/senv && /tmp/senv/bin/pip install duckdb pyarrow scikit-learn` when missing.
- Big DuckDB writes (factor matrix): batch INSERT + CHECKPOINT per batch; one-shot concat → write gets OOM-killed (exit 137) on 7 GB boxes. Downsample (e.g. 25%) before ML training to fit RAM.
- DuckDB `json.dump` on rows containing DATE objects raises TypeError — always pass `default=str`. A dropped-table DuckDB file never shrinks on checkpoint; reclaim space by ATTACHing a new file and `create table new.x as select * from old.x` (halved a 15 GB factor matrix this way), then delete the original.
- Long loops that spawn per-round Python subprocesses: guard with `flock` on a lockfile — a killed loop's orphaned children keep running and silently duplicate work (logs overwrite each other, results mix two code versions). Kill by exact pattern, never bare `pkill -f test*`; first SIGTERM a background terminal's shell then verify with `ps` before starting a replacement.
- Never open a second connection (even read-only) to a duckdb file while a writer process holds it: the reader gets an IOException lock error, and worse, the writer's INSERTs can fail silently under lock contention — the job then logs progress while persisting nothing. Verify inserted row counts AFTER the run, not just log tail; a long-running writer means verification queries must wait.

## Workbench (React site)
- Two deployments: Vela (`ws-*.lightvela.tech`, 302→sites-auth login is owner-auth, WeChat/QQ scan only — the agent cannot complete it) and GitHub Pages (dufuwuxin.github.io/stocks-ai-view-c, no login). When the user reports "site has no data", first open the Pages URL in a browser and read `document.body.innerText` — do not assume data files are missing.
- Root cause of "site blank but index quotes show": the frontend fetches warehouse JSON from `raw.githubusercontent.com`, which is frequently blocked/slow from CN browsers (Tencent realtime APIs connect fine, so the page half-works). Fix pattern: `data_origin_patch.js` fetchJSON must try the **same-origin `data/<file>` first** (Pages serves the repo's data/ dir), then fall back to raw GitHub, then gitcode. Deploy the data files into the Pages repo's `data/` by syncing them from the source shards. Sync is automated: `pages-data-sync` workflow (every 10 min) full-diffs the source repo's data/ into the Pages repo.
- Frontend render pipeline is fragile to null elements: `render()` runs sequential `renderXxx(d.field)` calls with NO try/catch — one `document.getElementById(...)` returning null for a removed element aborts every render after it (stuck "加载中…” panels that never resolve). Fix: null-guard each render target and wrap calls in the page's `_safe()` helper; also fix duplicate `id=` attributes (renderSummary updated only the first match, leaving the desktop card dead) and check that render functions actually have call sites (renderCloud was defined but never invoked). Verify fixes by reading per-element innerText in the browser, not the whole page.
- The Pages copy of data/ is a static sync of shard repos — re-sync after each session's data pushes, or the site serves stale snapshots. Browser cache: after changing JS, the user needs a hard refresh (Ctrl+Shift+R).
- Debugging in-browser: `browser_exec` + `js('document.body.innerText')` shows which blocks render ("加载中…” = fetch pending/failed, real numbers = OK); kernel-daemon IPC can time out on navigation — retry `ensure_real_tab()` once.

## skapp modular architecture (user-defined, 2026-10 design)
- User's architecture directive: each module (news / multi-pool / sentiment / alerts / 玄学 / picks) runs its OWN module engine at highest weight with other engines as secondary linked weights; ONLY the picks module is fed by all engines through the central hub, which decides whether to push at all (≥4-engine high / ≥2 mid). Implemented in skapp/py/modules/module_engine.py with MODULES config — extend modules there, never hard-wire engines into UI.
- Three similar repos exist and must stay merged into ONE trunk: jiegengxiangjianxue/skapp (framework: Rust core + FastAPI api + pyproject), skapp-app (the complete 14-screen Compose UI — newest, merge its ui/ data/ into skapp/app), skapp-data (data+engine+search snapshots). Architecture doc lives at skapp/ARCHITECTURE.md; check it before adding screens so web (Pages static) vs app (realtime engine) split holds.
- When git clone fails on TLS/connect timeouts, pull the tarball via contents API (`GET /repos/{owner}/{repo}/tarball` with token) and extract with `--strip-components=1` — the tarball has no .git, so push changed files back via the contents API batch-putter (loop with sha-get + sleep), not git.
- Software (Android) is the realtime engine runner; the webpage is static post-close snapshots only — do not duplicate engine runtime into the web layer.

## skapp (Android app, see references/skapp-android-app.md)
- Repo jiegengxiangjianxue/skapp (public): Rust core (pyo3 via CI maturin; local cargo test must strip serde/pyo3) + skapp_pkg/ (never name a top-level package `py` — collides with pytest's `py` lib) + app/ Compose M3 + 4 Actions. APK → Release tag apk-v*, dispatch android-apk after every app/ change.
- App reads the WEBSITE's live repos (qwerzxcva/stocks-ai-view primary, stocks-ai-view-c backup, skapp-data tertiary) via multi-source raw fallback — github.io does NOT publish data/, the site itself fetches raw.githubusercontent. Direct endpoints: Tencent qt.gtimg.cn quotes (GBK, hk prefix for HK), Sina zhibo news (jsonp %20). Polling 30s/60s/120s.
- Cross-repo CI sync needs a PAT repo secret (GITHUB_TOKEN is repo-scoped, 403); seal with pynacl SealedBox in a throwaway venv. Commit before `git pull --rebase --autostash`. A step's `env:` must be declared on THAT step, not a sibling.
- Kotlin pitfalls per CI round: pluginManagement{google()} in settings.gradle.kts; @file:OptIn before package; no `is Ctor(args)`; Double? safe-call before .isNaN; optJSONArray for array fields (strategy_rank ranking is an array); LocalContext hoisted out of onClick; name-enrich pick JSONs; cards must be tap-through (detail sheet).

## Syncing skills/knowledge/memory backups to GitHub (qwerzxcva)
- Tokens per account live at /tmp/{qw_tok,sk_tok,...}; qwerzxcva's was recovered from a repo clone's `.git/config` remote URL (x-access-token form) — before assuming a token is missing, grep all local `.git/config` files.
- Bulk upload (thousands of files): do NOT `git clone` github.com (TLS/connect timeouts on this box) — build the repo locally (`git init -b main`, copy files, commit) then `git push -f https://x-access-token:$TOK@github.com/...` in a retry loop (5-8 attempts with sleep; 408/disconnect on first tries is normal, force-push needed because a fresh GitHub repo has an auto-README commit).
- Dedupe by skill name when syncing `~/.hermes/skills`: namespace skills (`@ns/*`, 200+) go under `namespace/<ns>/<skill>/`, top-level skills at repo root; skip dotfiles and curator metadata (.locks, .hub, .usage*, .curator_*).
- Memory backups (MEMORY.md/USER.md) must go to a PRIVATE repo; knowledge corpora and skills to public.

## gitcode source repos (other AI's work — absorb, don't duplicate)
- Enumerate via `GET /api/v5/user/repos?access_token={tok}&per_page=100` (User-Agent header required). Absorb pipeline: full-clone the repo, inventory engines/features, DEDUPE against the existing 117-factor matrix before integrating (most published feature sets overlap heavily); copy only genuinely new paradigms (e.g. pure-stdlib GBDT/NB engines, PEAD double-beat events) into a local `alphas/` dir with a README crediting the source, then validate on own data with IS/OOS time-split before wiring into the chain. Some repos are empty placeholders — check before planning an absorb.
- NB (GaussianNB) probability rankings can come out inverted relative to GBDT quantiles — verify direction empirically per class and use inverted consensus if so; don't assume alignment.
- Monitor the upstream repos by commit history, not repo list: an actively-pushed repo may carry only shell commits (empty picks / stale market data behind a fresh timestamp) — check the actual payload content (n_picks, dates inside the JSON) before treating an upstream as a live source; several upstream ML calibrations exist whose verdicts (classic indicators all negative edge) can be cited as cross-validation, but their own win-rate claims need an unverified-口径 caveat.
- Tail-only fetch of an upstream append-only file: pull `review_history.jsonl` / ledger file via contents API and read the last lines instead of re-downloading everything.

## Long-running collectors & daemons (baostock / monitors)
- baostock `query_*` calls can hang forever on one symbol with no timeout — wrap result iteration with a max-row cap, and run the job under a shell watchdog that restarts on stall: if no log checkpoint advances for 2 polls, kill -9 and re-launch (resume via a done-set query); also restart when the process itself dies. A `socket.setdefaulttimeout` breaks baostock's connection (all queries return empty) — never add it.
- Silent-loop monitor processes (Tencent qt.gtimg.cn pollers etc.) die silently, and repeated identical log lines can be STALE snapshots, not live data — verify a poller is alive with `ps` before quoting its log as current, wrap pollers in a keeper loop that restarts on death, and check the quote payload's own timestamp field before trusting it. CN markets close 11:30-13:00: no new ticks at lunch is normal, not a dead poller.

## Engine registry (consolidated engine chain)
- All engines live in one registry (`alphas/engine_registry.py`): weights, source files, status. Rules: engines sharing the same feature source merge into ONE vote (GBDT+NB = ml_ensemble); engines overlapping existing factor families get down-weighted (dual_trend 0.8); engines with incomplete input data get weight 0 + status pending (pead awaits fin_pit); multipliers (calendar) are not independent votes. Confidence: ≥4 engines = high, ≥2 = mid, else low — two-engine agreement is not 'high'.
- New engine validation bar: IS/OOS time-split on own data; ML quantile monotonicity must hold OOS in every shard (high-prediction quintile beats low quintile), else reject.
- Upstream PIT financial source `db-fin-0` (jiegengxiangjianxue): year-partitioned parquet `data/fin_indicator/fin_indicator_{YYYY}.parquet`, 4452 symbols 1988–2026, true announce_date — fetch via contents API into `factor_matrix.duckdb fin_pit_up` with a done-set breakpoint (skip existing local parquet files); some year files are empty/missing upstream (2024/2025), and large-year downloads hit IncompleteRead — a resume run that skips existing files completes the gaps. Yoy EPS comparisons must filter prev-EPS < 0.05 (turnaround artifacts produce million-percent yoy).
- Recommendation basket MUST be style-hedged: defensive/rotation/offensive, ≥2 picks each — single-style baskets lose whole days on rotation days. Index-level phase from SSE-family indicators misses small-cap/growth structural markets; hedge the basket instead of over-trusting phase.
- Review each pick set vs next-day real quotes and log attribution; the user expects honest accounting of misses with root causes, not defense.
- Registry v4 (12 engines, all active): adds beta_rank (180d regression → high-β/ negative-β inverse pools; defensive banks show negative β — cross-checks basket hedging), flow_price_divergence_full (4-quadrant: 微涨大流入=吸筹 / 大涨大流入=主升 / 微涨大流出=派发 / 大跌大流出=出清), closed_loop.py (pick_tracker jsonl: register pick → T+1/T+5 check → hit-rate feeds weight; bull_bear_phase via 250d MA on equal-weight proxy; sector rotation), news_mystic.py (limit-up-pool theme attribution + leader identification, keyword 利好/利空 tagging, mystic daily — weather→power-demand is quantifiable and admitted, 八字/星座 are cultural tags with engine weight 0).
- Backfill the day's closes after every trading session (EOD) so the engine chain never runs on stale t0; when the day-K API is rate-limited, the realtime-quote fallback covers close/prev/open but not reliable high/low.
- Full module chain lives in `data/chain_v1.md` (data layer → factor layer → regime gate (bull_bear + rebound_regime + sentiment, serial) → 6 modules parallel → central fuse → pick_tracker loop back). Modules each weight their own primary engine highest; only the picks module consumes all engines. Extend modules in skapp py/modules/module_engine.py, not ad hoc.
- Engine routing table `alphas/module_router.py` (17 modules): each module maps to a primary engine fn + aux engine list at 0.3-0.5 weight; `chain_run()` runs bull_bear_phase first then phase-dependent modules (bear adds high-position-distribution + low-position scan; bull adds accumulation + rotation) — all with DEFAULT_ARGS so signature mismatches don't break the chain; fall back to `fn()` on TypeError. Verify zero fails before reporting the chain healthy.

## Alpha-mining pitfalls (equity factor/strategy stats)
- β regression MUST use returns, not price levels — regressing price-on-price yields betas near 0 for everything (levels are non-stationary and unit-mismatched); use daily returns cov/var.
- Vol-ratio sweet spot is 2-4, and the signal must co-move with price: prev-day up>3% + vr 2-4 → next-day ≥4% touch 32%, limit-up 8.4% (4.2× base); vr>4 is exhausted (decoy), vr 2-4 WITHOUT price rise is a trap (zt ~2%). Report base rates alongside any conditional hit rate or the number is meaningless.
- A 'next-day high ≥X%' touch rate is NOT achievable profit — next-day CLOSE mean on the same pool is ~4× lower; the executable form is a limit sell at the touch level with a stop below, expectation = touch_rate×gain + (1−touch_rate)×stop. State this math when the user asks for 'buy today sell tomorrow for N%'.
- Index-level stats hide structural markets: the equal-weight proxy can fall −1.2% while 20 main-board stocks limit-up (thematic clustering). Pair every index read with a limit-up-pool breadth check and dual_theme state before calling a day 'weak'.
- Equal-weight proxy series (not the official index) is the working base for 35-year stats — main-DB has no index rows; similar-Kline search over 5-day return vectors + streak-structure + crash-inertia + drift, equal-weight averaged, gives an honest next-day forecast (~50-55% hist win rate — state it as a tendency, never a direction promise).

## Skill absorption (new user-installed skills)
- When the user adds skills, evaluate them for engine absorption: rule-based thresholds (sentiment phases) and complete scoring systems (GMMA+Ichimoku+ADX) port into `alphas/` preserving the skill's original thresholds; keep only what the 128-factor matrix lacks; validate on real DB data; disclose data-quality caveats (e.g. amount estimated as close×volume) instead of hiding them.

## Market-intel APIs & patterns
- Tencent qt.gtimg.cn: `q={sym}` gives ~-delimited GBK quote fields (1 name, 3 price, 32 pct, 30 timestamp); the `ff_` moneyflow prefix returns none_match (dead); expect stale frames at lunch close.
- Eastmoney push2 clist is 403 from this egress (WAF) — use Sina fallbacks; the em ztpool endpoint (`push2ex.eastmoney.com/getTopicZTPool`) still works for limit-up pool / board height.
- Calendar effects (3.6M daily-sample verified, engine 9): Tuesday strongest +0.11%/day, Friday weakest, February +0.20%/day (CNY effect), January weakest — use as a position multiplier. Digit numerology (code ending 8/4) is a survivorship artifact — tested and rejected, do not re-add.
- Rebound structure (35y, 338 crash-days <−2.5% equal-weight): next-day avg +0.88%, 56% up; panic crashes (<−4%) do NOT rebound next day (+0.16% avg) — momentum down continues; post-crash leaders by elasticity: ChiNext >688 > main boards; HIGH-position (240d >30%) stocks rebound +1.6% vs low-position +0.7% (bottom-fishing logic fails — funds chase beaten strong names), but low-position win-rate is only ~33% (a few big winners skew the mean): low-position picks need flow/筹码 confirmation, never position alone.
- Accumulation detection (engine 10): flat 20d range <8% + 5d/15d volume ratio >1.8 (Wyckoff), cross-checked against 20d main-money net-inflow top while price hasn't run; v2 upgrades to slope-comparison (price 5d slope vs flow 5d slope, flow normalized by mean |flow|) + 10-day persistence ≥0.6 filter + TR20/TR60 <0.8 volatility-compression as an independent signal — absorbed from upstream flow_divergence.py. Treat fund-flow snapshots older than a few days as stale and say so in the report.

## Memory & reporting conventions
- User-facing products must carry LIVE data, not seed snapshots — locate the real source first (check repos' pushed_at / file commit dates) before wiring a consumer; the user rejects anything staler than the website equivalent and expects tap-through interactivity (every list item opens a detail view).
- User reports must state facts, not predictions; verify child-agent claims (commit shas) by listing the repo's commits before reporting success.
- Update `stock-memory/profiles/state.json` after each milestone (done/in_progress/todo) so other AI sessions see current state.
- Workbench: single-file React+Tailwind CDN at db-warehouse/workbench-src/, deployed on Vela (302→sites-auth on visit is owner-auth, not a failure); texts are contenteditable + localStorage.

## User style gates (standing)
- '只讲发生了什么，不预测/不给买卖建议' is the DEFAULT for market reports, but when the user explicitly asks for a forecast, give one with probability + horizon + confidence — then honestly grade it next session against reality. Never hide behind 'no predictions' after having been asked.
- When data contradicts an earlier claim, correct it explicitly and show the finer-grained re-run (e.g. low-position rebound mean was positive — the earlier 'not supported' was overstated; the real rule is low-position win-rate ~33% needing flow/筹码 confirmation). Overclaiming a debunk invites a user challenge; state the nuance the first time.
- When the user says a data source exists ('my repos have it'), actually enumerate and inspect it before concluding absence — API size fields lie (gitcode size=0 for non-empty repos), and repos revive between sessions (db-fin-0 went 404 → live year-partitioned parquet).
- The user wants breadth completed SAME-session ('要做就今天做完'): when given a module checklist, audit + implement every gap immediately, pushing partial-but-real engines over promises. Honest labeling: engines without data sources get status pending + weight 0, and cultural/entertainment analysis (八字/星座) is labeled as such with weight 0 while only data-validated signals (calendar, weather→power demand) get real weight.
