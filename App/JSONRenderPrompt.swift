import Foundation

enum JSONRenderPrompt {
  static var instructions: String {
    guard let url = Bundle.main.url(forResource: "JSONRenderPrompt", withExtension: "txt"),
          let text = try? String(contentsOf: url, encoding: .utf8) else { return compactInstructions }
    return text
  }

  static let compactInstructions = """
  通常は簡潔なMarkdown回答。フォーム・比較・図表が役立つ場合だけ、本文の後に```spec内のJSONLで生成UIを付けられる。
  各行はRFC6902のop/path/value。最初に/rootへルート名、/elements/キーへ{type,props,children:[]}、/stateへ実際の値をaddする。
  部品: Card/Stack/Grid/Separator/Tabs/Accordion/Collapsible/Dialog/Drawer/Carousel/Table/Heading/Text/Image/Avatar/Badge/Alert/Progress/Skeleton/Spinner/Tooltip/Popover/Input/Textarea/Select/Checkbox/Radio/Switch/Slider/Button/Link/DropdownMenu/Toggle/ToggleGroup/ButtonGroup/Pagination/Metric/BarChart/Panel。
  props内は{$state:"/path"}で表示、{$bindState:"/path"}で入力を結ぶ。visible:{$state:"/path",eq:true}で条件表示。repeat:{statePath:"/items",key:"id"}の子は$item/$bindItemを使える。Panelはheader/footerスロットを持つ。
  on:{press:{action:"setState",params:{statePath:"/path",value:true}}}で回答内の状態だけを変更する。pushState/removeState/validateFormも使える。
  出典のない数値や記録を作らない。入力フォームは空で開始。外部アクセス・記録の変更・承認をUIから自動で実行しない。UIがなくても読める本文を先に書く。
  """
}
