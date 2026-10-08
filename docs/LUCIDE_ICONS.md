# Lucide icons

LucideSwift 0.9.11 is linked to the app and widget. `Image(icon:)`, `Label(_:icon:)`, and button/menu helpers resolve through `MemoraIcon.lucideName`. Stored SF names stay unchanged. Lucide uses template outline images; fill variants resolve to the same outline. Native SF fallback remains for unmatched symbols and UIKit symbol configuration.

`Image(icon:size:)` sets the raster image point size (default 20); `.font` does not resize a Lucide image. Use an explicit size for specialized controls. The tab bar keeps its native segmented control and 18-point icons. Glass morphing is unchanged; custom icon replacement uses an opacity transition.

| Stored icon | Lucide name / fallback |
| --- | --- |
| `antenna.radiowaves.left.and.right` | `radio` |
| `antenna.radiowaves.left.and.right.slash` | `radioOff` |
| `apple.logo` | SF Symbols fallback |
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
| `bold` | `bold` |
| `bolt.fill` | `zap` |
| `brain` | `brain` |
| `brain.fill` | `brain` |
| `brain.head.profile` | `brain` |
| `briefcase` | `briefcase` |
| `bubble.left.and.bubble.right` | `messagesSquare` |
| `building.2.fill` | SF Symbols fallback |
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
| `circle.grid.3x3.fill` | SF Symbols fallback |
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
| `sparkles.rectangle.stack` | SF Symbols fallback |
| `speaker.wave.2.fill` | `volume2` |
| `square` | `square` |
| `chevron.down` | `chevronDown` |
| `chevron.left` | `chevronLeft` |
| `chevron.left.forwardslash.chevron.right` | `code` |
| `chevron.right` | `chevronRight` |
| `chevron.up.chevron.down` | `chevronsUpDown` |
| `circle` | `circle` |
| `circle.dotted` | `circleDashed` |
| `circle.lefthalf.filled` | SF Symbols fallback |
| `clock` | `clock` |
| `clock.arrow.circlepath` | SF Symbols fallback |
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
| `face.smiling` | SF Symbols fallback |
| `face.smiling.fill` | SF Symbols fallback |
| `faceid` | SF Symbols fallback |
| `faceid.fill` | SF Symbols fallback |
| `folder` | `folder` |
| `folder.badge.plus` | `folderPlus` |
| `folder.badge.questionmark` | `folderSearch` |
| `folder.fill` | `folder` |
| `g.circle` | SF Symbols fallback |
| `gearshape` | `settings` |
| `gearshape.fill` | `settings` |
| `gobackward.15` | SF Symbols fallback |
| `goforward.15` | SF Symbols fallback |
| `hand.raised` | SF Symbols fallback |
| `hand.raised.fill` | SF Symbols fallback |
| `icloud.slash` | SF Symbols fallback |
| `info` | `info` |
| `info.circle` | SF Symbols fallback |
| `info.circle.fill` | SF Symbols fallback |
| `internaldrive` | SF Symbols fallback |
| `internaldrive.fill` | SF Symbols fallback |
| `iphone` | `smartphone` |
| `iphone.and.arrow.forward` | SF Symbols fallback |
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
| `notion.logo` | SF Symbols fallback |
| `paintpalette` | `palette` |
| `paperclip` | `paperclip` |
| `paragraph` | `pilcrow` |
| `pause.fill` | `pause` |
| `pencil` | `pencil` |
| `person` | `user` |
| `person.2` | `users` |
| `person.3` | `usersRound` |
| `person.3.fill` | `usersRound` |
| `person.badge.key` | SF Symbols fallback |
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
| `play` | `play` |
| `play.fill` | `play` |
| `plugs.connected` | `plug` |
| `plugs.connected.fill` | `plug` |
| `plus` | `plus` |
| `questionmark` | SF Symbols fallback |
| `questionmark.bubble` | SF Symbols fallback |
| `questionmark.circle` | SF Symbols fallback |
| `questionmark.circle.fill` | SF Symbols fallback |
| `quote.bubble` | `messageSquareQuote` |
| `rectangle.grid.2x2` | `layoutGrid` |
| `rectangle.grid.2x2.fill` | `layoutGrid` |
| `rectangle.on.rectangle.angled` | `layers` |
| `rectangle.portrait.and.arrow.right` | `logOut` |
| `rectangle.stack` | `layers` |
| `rectangle.stack.badge.play` | SF Symbols fallback |
| `rectangle.stack.fill` | `layers` |
| `rotate.right` | `rotateCw` |
| `slider.horizontal.3` | `slidersHorizontal` |
| `sparkle` | `sparkle` |
| `sparkles` | `sparkles` |
| `sparkles.fill` | `sparkles` |
| `square.and.arrow.down` | `download` |
| `square.and.arrow.up` | `share` |
| `square.and.pencil` | `squarePen` |
| `square.grid.2x2` | SF Symbols fallback |
| `square.stack.3d.up` | `layers` |
| `star.bubble` | SF Symbols fallback |
| `star.fill` | `star` |
| `stop.fill` | `square` |
| `stopwatch` | `timer` |
| `stopwatch.fill` | `timer` |
| `strikethrough` | `strikethrough` |
| `sun.max` | `sun` |
| `sunrise` | `sunrise` |
| `text.alignleft` | `textAlignStart` |
| `text.badge.plus` | SF Symbols fallback |
| `text.bubble` | `messageSquareText` |
| `text.document` | `fileText` |
| `trash` | `trash` |
| `trash.fill` | `trash` |
| `trash.slash` | SF Symbols fallback |
| `tray` | SF Symbols fallback |
| `video` | `video` |
| `wand.and.stars` | `wandSparkles` |
| `waveform` | `audioLines` |
| `waveform.badge.mic` | SF Symbols fallback |
| `waveform.badge.minus` | SF Symbols fallback |
| `waveform.badge.plus` | SF Symbols fallback |
| `waveform.fill` | `audioLines` |
| `waveform.path.ecg` | `activity` |
| `waveform.slash` | SF Symbols fallback |
| `wifi.slash` | `wifiOff` |
| `xmark` | `x` |
| `xmark.circle` | `circleX` |
| `xmark.circle.fill` | `circleX` |
