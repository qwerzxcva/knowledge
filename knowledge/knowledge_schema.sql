CREATE TABLE calendar_findings (
  win_name VARCHAR,
  n INTEGER,
  mean_ret DOUBLE,
  win_rate DOUBLE,
  edge DOUBLE,
  decade_stability VARCHAR,
  ts DATE
);

CREATE TABLE event_findings (
  event VARCHAR,
  n INTEGER,
  fwd1 DOUBLE,
  fwd5 DOUBLE,
  fwd10 DOUBLE,
  verdict VARCHAR,
  ts DATE
);

CREATE TABLE factor_ic_findings (
  factor VARCHAR,
  horizon VARCHAR,
  ic_mean DOUBLE,
  years_stable INTEGER,
  detail VARCHAR,
  ts DATE
);

CREATE TABLE gold_cells (
  cell VARCHAR,
  cond VARCHAR,
  bias VARCHAR,
  wr_full DOUBLE,
  wr_10y DOUBLE,
  wr_5y DOUBLE,
  verified DATE
);

CREATE TABLE idx_cyb (
  date DATE,
  open DOUBLE,
  high DOUBLE,
  low DOUBLE,
  close DOUBLE,
  volume DOUBLE
);

CREATE TABLE idx_sh000001 (
  date DATE,
  open DOUBLE,
  high DOUBLE,
  low DOUBLE,
  close DOUBLE,
  volume DOUBLE
);

CREATE TABLE idx_sz399001 (
  date DATE,
  open DOUBLE,
  high DOUBLE,
  low DOUBLE,
  close DOUBLE,
  volume DOUBLE
);

CREATE TABLE intraday (
  sym VARCHAR,
  d DATE,
  minute VARCHAR,
  price DOUBLE,
  vol DOUBLE
);

CREATE TABLE lhb_detail (
  code VARCHAR,
  name VARCHAR,
  lhb_date DATE,
  pct_chg DOUBLE,
  net_buy DOUBLE,
  buy DOUBLE,
  sell DOUBLE,
  note VARCHAR
);

CREATE TABLE lhb_seat (
  code VARCHAR,
  name VARCHAR,
  lhb_date DATE,
  dept VARCHAR,
  buy DOUBLE,
  sell DOUBLE,
  net DOUBLE,
  type VARCHAR
);

CREATE TABLE market_regimes (
  cond VARCHAR,
  n INTEGER,
  next_med DOUBLE,
  next_win DOUBLE,
  d5_med DOUBLE,
  d10_med DOUBLE,
  verdict VARCHAR
);

CREATE TABLE predictions (
  p_date DATE,
  horizon VARCHAR,
  predicted DOUBLE,
  direction VARCHAR,
  method VARCHAR,
  actual DOUBLE,
  eval_date DATE
);

CREATE TABLE sw_daily (
  code VARCHAR,
  name VARCHAR,
  date DATE,
  open DOUBLE,
  high DOUBLE,
  low DOUBLE,
  close DOUBLE,
  volume DOUBLE
);

CREATE TABLE verified_strategies (
  id VARCHAR,
  name VARCHAR,
  descr VARCHAR,
  entry_rule VARCHAR,
  ev_pct DOUBLE,
  win_pct DOUBLE,
  sample_n INTEGER,
  years_json VARCHAR,
  verified DATE
);

CREATE TABLE youzi_profile (
  dept VARCHAR,
  n_days BIGINT,
  total_buy_stocks HUGEINT,
  total_sell_stocks HUGEINT,
  buy_yi DOUBLE,
  sell_yi DOUBLE,
  net_yi DOUBLE,
  win_like DOUBLE
);

CREATE TABLE yyyb (
  dept VARCHAR,
  yb_date DATE,
  n_buy INTEGER,
  n_sell INTEGER,
  buy_amt DOUBLE,
  sell_amt DOUBLE,
  net DOUBLE
);

CREATE TABLE zt_pool (
  code VARCHAR,
  name VARCHAR,
  zt_date DATE,
  pct_chg DOUBLE,
  price DOUBLE,
  seal_fund DOUBLE,
  first_seal VARCHAR,
  last_seal VARCHAR,
  breaks INTEGER,
  streak INTEGER,
  industry VARCHAR
);

