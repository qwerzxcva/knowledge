# v5 特征扩充 — 负结果记录 (诚实)
- 13 特征 (新增量价背离 pv_div/尾段动量 tail5_mom/收盘位置 close_pos/影线 upper_shadow 等) × 6轮
- touch4 best 0.7502 未超 v4 基线 0.7519 → 新特征无显著增益
- 特征重要性 top: amt_(成交额)/tail5_mom(尾盘动量)/tail_ret/tail_v/bar_vol — 日内信息集中在成交额与尾盘结构
- 结论: 基础 8 特征已近饱和, 下一步增益方向是"价格水平×量能分层"交互而非更多分时形态
- 坑: SQL 字面量内正则少一个闭引号 (奇数引号检测法: count("'") 为奇数必断) + DESCRIBE 分派 sym/code_raw 两代格式
