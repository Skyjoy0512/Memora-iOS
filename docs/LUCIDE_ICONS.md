# Lucideアイコン対応表

アプリ内の操作・ナビゲーション・状態表示は[Lucide](https://github.com/lucide-icons/lucide)に統一する。
アプリとウィジェットは既存のLucideSwift 0.9.11を使用し、238種類の`MemoraIcon`を
`Shared/MemoraIcon+Lucide.swift`の省略のないswitchで解決する。SF Symbolsへのフォールバックはない。
保存済みプロジェクト・設定との互換性のため、既存のraw valueは変更しない。
`.fill`付きの旧IDも同じアウトラインへ解決する。選択状態は既存の色・ラベル・選択トレイトで伝える。

## 描画とサイズ

- SwiftUI、UIKit本文編集ツールバー、ウィジェットは`MemoraIconRendering`を共有する。
- Lucideの24ptグリッドに対する2pt線幅、丸い線端と角を維持し、指定サイズの3倍解像度でテンプレート画像にする。
- `Image(icon:size:)`の標準サイズは20pt。`.font`は画像をリサイズしないため、必要なサイズを直接渡す。
- 設定・サイドメニューは20ptの図形を28pt枠へ配置する。補助矢印は12pt、操作領域は44pt以上。
- 再生の「15秒戻す／送る」は`rotateCcw`／`rotateCw`へ実際の秒数を重ねる。
- 本文編集の見出し、箇条書き、番号付きリストはそれぞれ`heading`、`list`、`listOrdered`で区別する。
- SF専用の`symbolEffect`は使わず、既存のReduce Motion設定に従うopacity遷移を使用する。
- 装飾画像は空の画像ラベルにし、ボタンやLabelが操作名を読み上げる。「Lucide Icon」という汎用ラベルは読み上げない。

mail／notebook／calendar／hardDrive／code／plugは一般操作の図形として使用する。
Lucideにブランドロゴは含まれない。外部サービス、Memora、AI提供元のロゴと利用者の写真は識別用の画像として扱う。
OSが描く標準ナビゲーション矢印やシステムシート内の記号はシステムに任せる。
ブランド画像の出典は[CONNECTOR_LOGOS.md](CONNECTOR_LOGOS.md)、ライセンスは[THIRD_PARTY.md](THIRD_PARTY.md)を参照。

## 検証

- `tools/checks/test_lucide_icons.py`：対応表の網羅性、旧ID、SF直接描画の混入、サイズ指定、本文編集のリスト識別を検査する。
- Debug起動時の`SelfChecks`：全238種類を12／20／48ptで描画し、画像が存在し透明画像ではないことを確認する。
- シミュレータでの確認範囲と結果は[ICON_REVIEW_2026_10.md](handoffs/ICON_REVIEW_2026_10.md)に記録する。

## 全対応表

| 保存ID | Lucide名 |
| --- | --- |
| `antenna.radiowaves.left.and.right` | `radio` |
| `antenna.radiowaves.left.and.right.slash` | `radioOff` |
| `apple.logo` | `cpu` |
| `arrow.clockwise` | `rotateCw` |
| `arrow.counterclockwise` | `rotateCcw` |
| `arrow.down` | `arrowDown` |
| `arrow.down.doc` | `fileDown` |
| `arrow.left.arrow.right` | `arrowLeftRight` |
| `arrow.right.circle` | `circleArrowRight` |
| `arrow.triangle.2.circlepath` | `refreshCw` |
| `arrow.triangle.merge` | `merge` |
| `arrow.turn.down.right` | `cornerDownRight` |
| `arrow.up` | `arrowUp` |
| `arrow.up.doc` | `fileUp` |
| `arrow.up.left` | `arrowUpLeft` |
| `arrow.up.right` | `arrowUpRight` |
| `arrow.up.right.square` | `externalLink` |
| `arrow.uturn.backward` | `undo2` |
| `bell` | `bell` |
| `bell.fill` | `bell` |
| `heading` | `heading` |
| `list.ordered` | `listOrdered` |
| `bold` | `bold` |
| `bolt.fill` | `zap` |
| `brain` | `brain` |
| `brain.fill` | `brain` |
| `brain.head.profile` | `brain` |
| `briefcase` | `briefcase` |
| `bubble.left.and.bubble.right` | `messagesSquare` |
| `building.2.fill` | `building` |
| `house` | `house` |
| `house.fill` | `house` |
| `calendar` | `calendar` |
| `calendar.badge.checkmark` | `calendarCheck` |
| `calendar.badge.checkmark.fill` | `calendarCheck` |
| `calendar.badge.plus` | `calendarPlus` |
| `calendar.fill` | `calendar` |
| `camera` | `camera` |
| `chart.bar` | `chartNoAxesColumn` |
| `chart.bar.fill` | `chartNoAxesColumn` |
| `chart.line.uptrend.xyaxis` | `chartLine` |
| `chat.bubble` | `messageCircle` |
| `chat.bubble.fill` | `messageCircle` |
| `character.book.closed` | `bookA` |
| `checklist` | `listChecks` |
| `checklist.fill` | `listChecks` |
| `checkmark` | `check` |
| `checkmark.circle` | `circleCheck` |
| `checkmark.circle.fill` | `circleCheck` |
| `checkmark.seal` | `badgeCheck` |
| `checkmark.seal.fill` | `badgeCheck` |
| `checkmark.square` | `squareCheck` |
| `chevron.up` | `chevronUp` |
| `circle.grid.3x3.fill` | `grid3X3` |
| `creditcard` | `creditCard` |
| `delete.left` | `delete` |
| `ear` | `ear` |
| `exclamationmark.bubble` | `messageCircleWarning` |
| `flag` | `flag` |
| `graduationcap` | `graduationCap` |
| `infinity` | `infinity` |
| `leaf.fill` | `leaf` |
| `lightbulb` | `lightbulb` |
| `minus.circle` | `circleMinus` |
| `newspaper` | `newspaper` |
| `paperplane` | `send` |
| `person.crop.circle.badge.plus` | `userRoundPlus` |
| `person.wave.2` | `contactRound` |
| `phone` | `phone` |
| `phone.down.fill` | `phoneOff` |
| `phone.fill` | `phone` |
| `plus.circle` | `circlePlus` |
| `sparkles.rectangle.stack` | `sparkles` |
| `speaker.wave.2.fill` | `volume2` |
| `square` | `square` |
| `chevron.down` | `chevronDown` |
| `chevron.left` | `chevronLeft` |
| `chevron.left.forwardslash.chevron.right` | `code` |
| `chevron.right` | `chevronRight` |
| `chevron.up.chevron.down` | `chevronsUpDown` |
| `circle` | `circle` |
| `circle.dotted` | `circleDashed` |
| `circle.lefthalf.filled` | `contrast` |
| `clock` | `clock` |
| `clock.arrow.circlepath` | `clockArrowRight` |
| `clock.fill` | `clock` |
| `cloud` | `cloud` |
| `cloud.fill` | `cloud` |
| `cpu` | `cpu` |
| `cpu.fill` | `cpu` |
| `crop` | `crop` |
| `crown` | `crown` |
| `crown.fill` | `crown` |
| `desktopcomputer` | `monitor` |
| `doc` | `file` |
| `doc.questionmark` | `fileQuestionMark` |
| `doc.on.doc` | `copy` |
| `doc.richtext` | `fileText` |
| `doc.text` | `fileText` |
| `doc.text.fill` | `fileText` |
| `dot.radiowaves.left.and.right` | `radio` |
| `dot.radiowaves.left.and.right.fill` | `radio` |
| `ellipsis` | `ellipsis` |
| `envelope` | `mail` |
| `envelope.open` | `mailOpen` |
| `exclamationmark.circle` | `circleAlert` |
| `exclamationmark.triangle` | `triangleAlert` |
| `exclamationmark.triangle.fill` | `triangleAlert` |
| `externaldrive` | `hardDrive` |
| `externaldrive.fill` | `hardDrive` |
| `face.smiling` | `faceSlightlySmiling` |
| `face.smiling.fill` | `faceSlightlySmiling` |
| `faceid` | `scanFace` |
| `faceid.fill` | `scanFace` |
| `folder` | `folder` |
| `folder.badge.plus` | `folderPlus` |
| `folder.badge.questionmark` | `folderSearch` |
| `folder.fill` | `folder` |
| `g.circle` | `globe` |
| `gearshape` | `settings` |
| `gearshape.fill` | `settings` |
| `gobackward.15` | `rotateCcw` |
| `goforward.15` | `rotateCw` |
| `hand.raised` | `hand` |
| `hand.raised.fill` | `hand` |
| `icloud.slash` | `cloudOff` |
| `info` | `info` |
| `info.circle` | `info` |
| `info.circle.fill` | `info` |
| `internaldrive` | `hardDrive` |
| `internaldrive.fill` | `hardDrive` |
| `iphone` | `smartphone` |
| `iphone.and.arrow.forward` | `smartphone` |
| `iphone.fill` | `smartphone` |
| `italic` | `italic` |
| `key` | `key` |
| `key.fill` | `key` |
| `line.3.horizontal` | `menu` |
| `line.3.horizontal.decrease` | `listFilter` |
| `line.3.horizontal.decrease.circle` | `listFilter` |
| `link` | `link` |
| `list.bullet.rectangle` | `list` |
| `location` | `navigation` |
| `location.fill` | `navigation` |
| `lock` | `lock` |
| `lock.shield` | `shieldCheck` |
| `lock.shield.fill` | `shieldCheck` |
| `magnifyingglass` | `search` |
| `mappin.slash` | `mapPinOff` |
| `mappin.slash.fill` | `mapPinOff` |
| `mic` | `mic` |
| `mic.fill` | `mic` |
| `mic.slash` | `micOff` |
| `moon` | `moon` |
| `moon.fill` | `moon` |
| `note.text` | `notebookText` |
| `notion.logo` | `notebook` |
| `paintpalette` | `palette` |
| `paperclip` | `paperclip` |
| `paragraph` | `pilcrow` |
| `pause.fill` | `pause` |
| `pencil` | `pencil` |
| `person` | `user` |
| `person.2` | `users` |
| `person.3` | `usersRound` |
| `person.3.fill` | `usersRound` |
| `person.badge.key` | `userRoundKey` |
| `person.badge.plus` | `userPlus` |
| `person.crop.circle` | `circleUserRound` |
| `person.crop.circle.badge.xmark` | `userRoundX` |
| `person.crop.circle.fill` | `circleUserRound` |
| `person.fill` | `user` |
| `photo` | `image` |
| `photo.badge.plus` | `imagePlus` |
| `photo.fill` | `image` |
| `photo.on.rectangle` | `images` |
| `pin` | `pin` |
| `puzzlepiece` | `puzzle` |
| `wrench.and.screwdriver` | `wrench` |
| `play` | `play` |
| `play.fill` | `play` |
| `plugs.connected` | `plug` |
| `plugs.connected.fill` | `plug` |
| `plus` | `plus` |
| `questionmark` | `circleQuestionMark` |
| `questionmark.bubble` | `messageCircleQuestionMark` |
| `questionmark.circle` | `circleQuestionMark` |
| `questionmark.circle.fill` | `circleQuestionMark` |
| `quote.bubble` | `messageSquareQuote` |
| `rectangle.grid.2x2` | `layoutGrid` |
| `rectangle.grid.2x2.fill` | `layoutGrid` |
| `rectangle.on.rectangle.angled` | `layers` |
| `rectangle.portrait.and.arrow.right` | `logOut` |
| `rectangle.stack` | `layers` |
| `rectangle.stack.badge.play` | `film` |
| `rectangle.stack.fill` | `layers` |
| `rotate.right` | `rotateCw` |
| `slider.horizontal.3` | `slidersHorizontal` |
| `sparkle` | `sparkle` |
| `sparkles` | `sparkles` |
| `sparkles.fill` | `sparkles` |
| `square.and.arrow.down` | `download` |
| `square.and.arrow.up` | `share` |
| `square.and.pencil` | `squarePen` |
| `square.grid.2x2` | `grid2X2` |
| `square.stack.3d.up` | `layers` |
| `star.bubble` | `messageCircleHeart` |
| `star.fill` | `star` |
| `stop.fill` | `square` |
| `stopwatch` | `timer` |
| `stopwatch.fill` | `timer` |
| `strikethrough` | `strikethrough` |
| `sun.max` | `sun` |
| `sunrise` | `sunrise` |
| `text.alignleft` | `textAlignStart` |
| `textformat` | `type` |
| `tablecells` | `table` |
| `text.badge.plus` | `listPlus` |
| `text.bubble` | `messageSquareText` |
| `text.document` | `fileText` |
| `trash` | `trash` |
| `tram.fill` | `tramFront` |
| `trash.fill` | `trash` |
| `trash.slash` | `shredder` |
| `tray` | `inbox` |
| `video` | `video` |
| `wand.and.stars` | `wandSparkles` |
| `waveform` | `audioLines` |
| `waveform.badge.mic` | `audioWaveform` |
| `waveform.badge.minus` | `audioWaveform` |
| `waveform.badge.plus` | `audioWaveform` |
| `waveform.fill` | `audioLines` |
| `waveform.path.ecg` | `activity` |
| `waveform.slash` | `audioLinesOff` |
| `wifi.slash` | `wifiOff` |
| `xmark` | `x` |
| `xmark.circle` | `circleX` |
| `xmark.circle.fill` | `circleX` |

## 公式ブランド画像の例外（2026-10-31）

操作・記録・スキルのアイコンは本表のLucideを維持する。Gmail/Drive/Notion/GitHub/MCPと
アカウントの識別は利用者の指示により公式画像を使う。出典と使い分けは[ブランド画像](CONNECTOR_LOGOS.md)。
Appleサインインに限りOSの`apple.logo`を使用し、一般の操作アイコンでは使用しない。
保存済みMemoraIconの名前と対応表は変更しない。
