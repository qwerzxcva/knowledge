# skapp — Android app (Kotlin Compose M3) + public data repo

## Architecture (current)
- Repo: `jiegengxiangjianxue/skapp` (PUBLIC). Rust core (`core/`, sma/cross_rank/composite/limit-up thresholds; pyo3 build via CI maturin — crates.io unreachable from the workstation, so local Rust tests must strip serde/pyo3 deps), Python pipeline `skapp_pkg/` (NEVER name a top-level package `py` — collides with pytest's `py` lib: CI fails `AttributeError: module 'py' has no attribute 'path'`; string paths like `os.path.join(HERE,"py",...)` must be renamed too), `api/` FastAPI, `app/` Compose M3, Actions: rust-core / py-tests / eod-snapshot (cron UTC 7:35 = 15:35 CST + dispatch) / android-apk.
- APK distribution: `android-apk` workflow → Release tag `apk-v*` (dispatch after every `app/` change). Version string lives in `app/build.gradle.kts` (`versionName`), not in Kotlin.
- Live data source (v0.4+): the app reads the SAME repos the website does — `qwerzxcva/stocks-ai-view` (primary, Actions push at minute frequency; ~1030 data files: today_picks.json = signals/values/limit_up + market pulse, decision.json = position_advice + ten-dim cards + avoid list, stock_names.json = 5278-name search index) with `dufuwuxin/stocks-ai-view-c` as backup and `skapp-data` as tertiary. The site's `gh_sources.js` picks the freshest ts across repos; replicate with multi-source fallback. github.io does NOT publish data/ (404) — the frontend always went through raw.githubusercontent.
- `dufuwuxin/skapp-data`? No — `jiegengxiangjianxue/skapp-data` (public) holds: search index, engine JSONs (name-enriched from symbols.json), daily snapshots. eod-snapshot generates the daily snapshot + T+1 pick review settlement, commits to skapp, then syncs 8 files to skapp-data.
- Realtime endpoints (direct, no backend): quotes Tencent `qt.gtimg.cn/q=...` (GBK; A-share + HK with `hk` prefix); news Sina `zhibo.sina.com.cn/api/zhibo/feed?...zhibo_id=152` (jsonp callback name must be URL-encoded, spaces → %20). App polls: quotes 30s, news 60s, engine JSONs 120s (ViewModel init + while(true)+delay loops).

## Credentials model (user requirement: multi-account)
- App needs NO token for the main path (public raw reads with `?t=` cache-buster). Settings accepts multi-line tokens (one per account: jiegengxiangjianxue / jiegengxiangjianxue1 / qwerzxcva / dufuwuxin); take the first non-blank line; on 401/403 fall back to anonymous raw — never let a bad token make the app fail harder than no token (fine-grained tokens default to zero repo access → private-repo reads 404 even with a "valid" token).
- Tokens typed by the user into Settings, persisted in SharedPreferences.

## CI cross-repo sync
- `secrets.GITHUB_TOKEN` can only write the repo it runs in — syncing to another repo needs a PAT stored as a repo secret (name it GH_PAT). Sealing without pynacl installed: create a throwaway venv, `pip install pynacl`, `public.SealedBox(publickey).encrypt(secret)` → base64 → `PUT /repos/{o}/{r}/actions/secrets/{NAME}` with `{encrypted_value, key_id}` from the public-key endpoint.
- Commit-then-rebase: run `git add`/`commit` BEFORE `git pull --rebase --autostash` (eod_sync dirties the tree → plain rebase fails with "unstaged changes").
- A step's `env:` must be declared on THAT step, not a sibling — cross-repo sync steps fail with `KeyError: 'GH_TOKEN'` otherwise.

## Kotlin/Compose pitfalls (each cost a CI round)
- `settings.gradle.kts` needs `pluginManagement { google() }` or AGP plugin resolution fails.
- M3 `TopAppBar` is experimental: `@file:OptIn(ExperimentalMaterial3Api::class)` and the file annotation MUST precede the `package` line.
- `is Constructor(args)` is illegal in conditionals — compare fields: `(x as? T)?.field == v`.
- `optDouble` returns a primitive but a data-class property declared `Double?` still needs safe calls (`p.price?.let { ... }`) before `.isNaN()`/format.
- JSON shape mismatches: `strategy_rank.json`'s `ranking` is an ARRAY of objects — `getJSONObject("ranking")` throws at runtime; always `optJSONArray` first and handle null.
- `LocalContext.current` must be hoisted to composable scope, not called inside onClick lambdas.
- Enrich engine JSONs with display names (join symbols.json by code) before pushing — code-only pick lists are unreadable to the user.
- Pick/quote cards are clickable → `ModalBottomSheet` detail (live quote, add-to-watchlist, K-line link `gu.qq.com/{code}/gp`); user reads tap-through as a baseline feature, not polish.

## Modular engine architecture (v2, user-defined)
- The app hosts six linked-engine modules (news / pools / sentiment / alerts / mystic / picks) driven by `py/modules/module_engine.py`: each module weights its OWN primary engine highest and other engines secondarily; picks is special — all engines feed the central hub which only pushes picks with ≥4-engine (high) or ≥2-engine (mid) confidence. New screens must render module output, not raw engine output.
- Module results are computed Python-side; the app renders via a module-result JSON (one per module) added to the repo data/ — add the module JSON to the eod-snapshot sync list when a module ships.
- The three repos (skapp framework / skapp-app UI / skapp-data) must stay ONE trunk: skapp-app has the newest 14-screen UI — its `ui/` screens and `data/` classes merge into skapp/app; architecture doc at skapp/ARCHITECTURE.md. Tarball route (contents API tarball + --strip-components=1) has NO .git — push merged files back via the contents-API batch putter (loop sha-get + PUT + sleep), one file at a time with retries; batch-put ~19 Kotlin files survives transient SSL EOF, a git clone may not even connect.
- User's style gate on skapp work: breadth items on a requested checklist are completed SAME-session ('要做就今天做完') — implement every module immediately even if thin, with honest status labels (pending/weight-0 for engines lacking data sources; cultural/entertainment features like 八字/星座 get weight 0 and are labeled as such, only data-validated signals get real weight).

## Adding a new engine data feed to the app
1. Check the file exists in qwerzxcva/stocks-ai-view data/ (contents API tree) and note its JSON shape from a raw fetch.
2. Add a data class + `suspend fun` in Repository.kt using `liveFile(RAW_A/..., RAW_B/...)` multi-source fallback; parse with opt* accessors only.
3. Add a StateFlow + polling loop slot in the ViewModel; render in a Tab with ResView; make rows clickable.
4. Dispatch android-apk workflow, poll `/actions/runs?per_page=1` until complete, verify Release asset timestamp moved.
