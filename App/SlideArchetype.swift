import Foundation

/// Stable public IDs mirror the pinned upstream catalog, independently of display names.
enum SlideArchetype: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
  case b01, b02, b03, b04, b05, b06, b07, b08, b09, b10
  case b11, b12, b13, b14, b15, b16, b17, b18, b19, b20
  case b21, b22, b23, b24, b25, b26, b27, b28, b29, b30
  case m01, m02, m03, m04, m05, m06, m07, m08, m09, m10
  case m11, m12, m13, m14, m15, m16, m17, m18, m19, m20
  case m21, m22, m23, m24, m25, m26, m27, m28, m29, m30
  case m31, m32, m33, m34, m35

  var id: String { rawValue }
  var title: String { specification.1 }
  var upstreamID: String { specification.0 }
  var input: Input { specification.2 }

  enum Input: String, Sendable {
    case title, items, table, metrics, chart, diagram, schedule
  }

  private var specification: (String, String, Input) {
    switch self {
    case .b01: ("title_page", "表紙", .title)
    case .b02: ("overview_map", "全体マップ", .items)
    case .b03: ("table_of_contents", "目次", .items)
    case .b04: ("section_divider", "章扉", .title)
    case .b05: ("chevron_steps", "矢羽・プロセス", .items)
    case .b06: ("premise_conclusion", "前提→帰結", .items)
    case .b07: ("stat_table_readout", "大型数値の表＋読み取り", .table)
    case .b08: ("card_grid_2x2", "2×2カード", .items)
    case .b09: ("axis_table", "軸のある表", .table)
    case .b10: ("back_cover", "裏表紙", .title)
    case .b11: ("claim_panel_figure", "主張パネル＋図", .chart)
    case .b12: ("lever_effect_table", "打ち手の効果表", .table)
    case .b13: ("status_heatmap_comment", "状態ヒートマップ＋コメント", .table)
    case .b14: ("harvey_ball_table", "ハーベイボール評価表", .table)
    case .b15: ("dot_matrix_share", "割合のドットマトリクス", .metrics)
    case .b16: ("progress_bubble_matrix", "進捗バブル行列", .table)
    case .b17: ("ranked_bar_annotated", "順位棒グラフ＋注記", .chart)
    case .b18: ("scatter_annotated", "散布図＋注記", .chart)
    case .b19: ("pillars_foundation", "柱＋土台", .items)
    case .b20: ("opposing_chevrons", "対向シェブロン", .items)
    case .b21: ("evidence_clip_grid", "外部動向の根拠グリッド", .items)
    case .b22: ("proportional_circles", "比例円の対比", .metrics)
    case .b23: ("delta_bars_totals", "増減の縦棒＋左右合計", .chart)
    case .b24: ("scenario_lines_cagr", "シナリオ線＋成長率", .chart)
    case .b25: ("research_basis", "調査の土台", .items)
    case .b26: ("issue_action_columns", "課題と打ち手", .items)
    case .b27: ("agenda_separator", "アジェンダ再掲型の章扉", .items)
    case .b28: ("swimlane_numbered_notes", "スイムレーン＋番号付き注記", .schedule)
    case .b29: ("front_back_two_tier", "表と裏の2段", .items)
    case .b30: ("qa_list", "一問一答", .items)
    case .m01: ("executive_summary", "エグゼクティブサマリー", .items)
    case .m02: ("evidence_basis", "調査根拠の整理", .items)
    case .m03: ("big_stat_pair", "大型数値2つの比較", .metrics)
    case .m04: ("kpi_dashboard", "KPIダッシュボード", .metrics)
    case .m05: ("chart_insight", "チャート＋示唆", .chart)
    case .m06: ("stacked_bar", "積み上げ棒グラフ", .chart)
    case .m07: ("waterfall", "寄与度ブリッジ", .chart)
    case .m08: ("true_waterfall", "厳密なウォーターフォール", .chart)
    case .m09: ("small_multiples", "小図の並列比較", .chart)
    case .m10: ("comparison_table", "選択肢の比較表", .table)
    case .m11: ("scenario_table", "シナリオ比較表", .table)
    case .m12: ("risk_table", "リスク一覧表", .table)
    case .m13: ("horizontal_axis_table", "横軸評価表", .table)
    case .m14: ("heatmap_table", "ヒートマップ表", .table)
    case .m15: ("matrix_2x2", "2×2マトリクス", .chart)
    case .m16: ("process_matrix", "プロセス×観点の行列", .table)
    case .m17: ("nested_row_matrix", "入れ子行の行列", .table)
    case .m18: ("timeline_matrix", "時系列マトリクス", .table)
    case .m19: ("theme_card_grid", "テーマカード", .items)
    case .m20: ("recommendation_pillars", "提言の柱", .items)
    case .m21: ("numbered_imperatives", "番号付き施策", .items)
    case .m22: ("scr", "状況・課題・対策", .items)
    case .m23: ("issue_to_solution_map", "課題と施策の対応", .items)
    case .m24: ("issue_cause_solution", "課題→原因→解決", .items)
    case .m25: ("issue_tree", "イシューツリー", .diagram)
    case .m26: ("current_target_state", "現状と目指す姿", .items)
    case .m27: ("calc_flow", "計算ロジックの流れ", .items)
    case .m28: ("process_flow", "プロセスフロー", .items)
    case .m29: ("cycle", "循環サイクル", .items)
    case .m30: ("chevron_rail", "段階を示す矢羽", .items)
    case .m31: ("chevron_value_chain", "バリューチェーン", .items)
    case .m32: ("decision_fork", "分岐と判断", .diagram)
    case .m33: ("roadmap", "ロードマップ", .schedule)
    case .m34: ("gantt", "ガントチャート", .schedule)
    case .m35: ("decision_page", "意思決定ページ", .items)
    }
  }

  static var modelCatalog: String {
    allCases.map { "\($0.rawValue):\($0.title)[\($0.input.rawValue)]" }.joined(separator: "、")
  }
}
