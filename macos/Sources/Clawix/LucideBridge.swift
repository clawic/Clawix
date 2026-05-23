import SwiftUI

/// Lucide icon registry. Renders glyphs from a static table of SVG
/// primitives (`LucideIconRegistry`) parsed at runtime by
/// `SVGPathBuilder`. The 79 Kind cases below cover every icon the app
/// references plus the SF Symbol → Lucide mappings used by
/// `LucideIcon.auto(_:)`.
///
/// Why this shape (vs. the previous Text + Font.custom("lucide", ...)
/// path): bundling the Lucide TTF carried a custom font everywhere the
/// app shipped, and the codepoint indirection made every site read the
/// font even when only a handful of glyphs were used. Going through
/// SwiftUI Path lets the icons inherit `.foregroundStyle` /
/// `.foregroundColor` like SF Symbols, and the rendered geometry is the
/// official Lucide vector data (translated by `SVGPathBuilder`), not a
/// hand-eyeballed approximation.
///
/// Usage is unchanged from the font-based version:
///
///     LucideIcon(.chevronDown, size: 13)
///         .foregroundColor(Color.gray(light: 0.19, dark: 0.86))
///
/// `.font(.system(...))` set on the call site is IGNORED — pass the
/// size explicitly via the `size:` parameter so the stroke weight scales
/// correctly.
struct LucideIcon: View {
    enum Kind {
        case chevronDown
        case chevronUp
        case chevronLeft
        case chevronRight
        case x
        case plus
        case minus
        case check
        case ellipsis
        case arrowUp
        case arrowDown
        case arrowLeft
        case arrowRight
        case arrowUpRight
        case squareArrowOutUpRight
        case arrowRightToLine
        case arrowDownToLine
        case undo2
        case rotateCw
        case rotateCcw
        case refreshCw
        case maximize2
        case minimize2
        case trash
        case search
        case folder
        case archive
        case messageCircle
        case globe
        case paperclip
        case camera
        case image
        case images
        case imageOff
        case send
        case zap
        case zapOff
        case star
        case clock
        case list
        case listChecks
        case textAlignStart
        case key
        case link
        case laptop
        case scan
        case tornado
        case drama
        case fileQuestionMark
        case squareDashed
        case appWindow
        case workflow
        case download
        case share2
        case inbox
        case play
        case pause
        case square
        case circleStop
        case moon
        case audioWaveform
        case triangleAlert
        case circleAlert
        case shieldAlert
        case info
        case circleCheck
        case circleX
        case circleDot
        case eye
        case eyeOff
        case glasses
        case lock
        case terminal
        case database
        case braces
        case idCard
        case badgeCheck
        case webhook
        case fileText
        // Ported from Lucide so former SF Symbols / the circleDot fallback
        // resolve to real custom glyphs instead of Apple's library.
        case house
        case calendar
        case library
        case network
        case megaphone
        case layers
        case handshake
        case wandSparkles
        case sparkles
        case paintbrush
        case palette
        case scroll
        case circleUser
        case user
        case layoutGrid
        case grid2x2
        case clipboardList
        case radioTower
        case rss
        case circleHelp
        case brain
        case smartphone
        case code
        case heart
        case bookmark
        case shield
        case lightbulb
        case flame
        case pencil
        case wrench
        case gitBranch
        case sun
        case keyboard
        case fingerprint
        case slidersHorizontal
        case package
        case monitor
        case server
        case smile
        case layoutDashboard
        case puzzle
        case plug
        case blocks
        case panelTop
        case listTodo
        case squareMousePointer
        case keyRound
    }

    let kind: Kind
    var size: CGFloat

    init(_ kind: Kind, size: CGFloat = 16) {
        self.kind = kind
        self.size = size
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch kind {
            // Cases that already have a hand-crafted custom struct in the
            // project — dispatch to the existing one so its design DNA
            // (squircle elbows, custom proportions) wins over the
            // SVG-derived render.
            case .search:    SearchIcon(size: size)
            case .globe:     GlobeIcon(size: size)
            case .check:     CheckIcon(size: size)
            case .arrowUp:   ArrowUpIcon(size: size)
            case .terminal:  TerminalIcon(size: size)
            case .archive:   ArchiveIcon(size: size)

            // SVG-derived custom icons (one file per kind in LucideIcons/).
            case .chevronDown:            ChevronDownIcon(size: size)
            case .chevronUp:              ChevronUpIcon(size: size)
            case .chevronLeft:            ChevronLeftIcon(size: size)
            case .chevronRight:           ChevronRightIcon(size: size)
            case .x:                      XIcon(size: size)
            case .plus:                   PlusIcon(size: size)
            case .minus:                  MinusIcon(size: size)
            case .ellipsis:               EllipsisIcon(size: size)
            case .arrowDown:              ArrowDownIcon(size: size)
            case .arrowLeft:              ArrowLeftIcon(size: size)
            case .arrowRight:             ArrowRightIcon(size: size)
            case .arrowUpRight:           ArrowUpRightIcon(size: size)
            case .squareArrowOutUpRight:  SquareArrowOutUpRightIcon(size: size)
            case .arrowRightToLine:       ArrowRightToLineIcon(size: size)
            case .arrowDownToLine:        ArrowDownToLineIcon(size: size)
            case .undo2:                  Undo2Icon(size: size)
            case .rotateCw:               RotateCwIcon(size: size)
            case .rotateCcw:              RotateCcwIcon(size: size)
            case .refreshCw:              RefreshCwIcon(size: size)
            case .maximize2:              Maximize2Icon(size: size)
            case .minimize2:              Minimize2Icon(size: size)
            case .trash:                  TrashIcon(size: size)
            case .folder:                 FolderIcon(size: size)
            case .messageCircle:          MessageCircleIcon(size: size)
            case .paperclip:              PaperclipIcon(size: size)
            case .camera:                 CameraIcon(size: size)
            case .image:                  ImageIcon(size: size)
            case .images:                 ImagesIcon(size: size)
            case .imageOff:               ImageOffIcon(size: size)
            case .send:                   SendIcon(size: size)
            case .zap:                    ZapIcon(size: size)
            case .zapOff:                 ZapOffIcon(size: size)
            case .star:                   StarIcon(size: size)
            case .clock:                  ClockIcon(size: size)
            case .list:                   ListIcon(size: size)
            case .listChecks:             ListChecksIcon(size: size)
            case .textAlignStart:         TextAlignStartIcon(size: size)
            case .key:                    KeyIcon(size: size)
            case .link:                   LinkIcon(size: size)
            case .laptop:                 LaptopIcon(size: size)
            case .scan:                   ScanIcon(size: size)
            case .tornado:                TornadoIcon(size: size)
            case .drama:                  DramaIcon(size: size)
            case .fileQuestionMark:       FileQuestionMarkIcon(size: size)
            case .squareDashed:           SquareDashedIcon(size: size)
            case .appWindow:              AppWindowIcon(size: size)
            case .workflow:               WorkflowIcon(size: size)
            case .download:               DownloadIcon(size: size)
            case .share2:                 Share2Icon(size: size)
            case .inbox:                  InboxIcon(size: size)
            case .play:                   PlayIcon(size: size)
            case .pause:                  PauseIcon(size: size)
            case .square:                 SquareIcon(size: size)
            case .circleStop:             CircleStopIcon(size: size)
            case .moon:                   MoonIcon(size: size)
            case .audioWaveform:          AudioWaveformIcon(size: size)
            case .triangleAlert:          TriangleAlertIcon(size: size)
            case .circleAlert:            CircleAlertIcon(size: size)
            case .shieldAlert:            ShieldAlertIcon(size: size)
            case .info:                   InfoIcon(size: size)
            case .circleCheck:            CircleCheckIcon(size: size)
            case .circleX:                CircleXIcon(size: size)
            case .circleDot:              CircleDotIcon(size: size)
            case .eye:                    EyeIcon(size: size)
            case .eyeOff:                 EyeOffIcon(size: size)
            case .glasses:                GlassesIcon(size: size)
            case .lock:                   LockIcon(size: size)
            case .database:               DatabaseIcon(size: size)
            case .braces:                 BracesIcon(size: size)
            case .idCard:                 IdCardIcon(size: size)
            case .badgeCheck:             BadgeCheckIcon(size: size)
            case .webhook:                WebhookIcon(size: size)
            case .fileText:               FileTextIcon(size: size)
            case .house:                  HouseIcon(size: size)
            case .calendar:               CalendarIcon(size: size)
            case .library:                LibraryIcon(size: size)
            case .network:                NetworkIcon(size: size)
            case .megaphone:              MegaphoneIcon(size: size)
            case .layers:                 LayersIcon(size: size)
            case .handshake:              HandshakeIcon(size: size)
            case .wandSparkles:           WandSparklesIcon(size: size)
            case .sparkles:               SparklesIcon(size: size)
            case .paintbrush:             PaintbrushIcon(size: size)
            case .palette:                PaletteIcon(size: size)
            case .scroll:                 ScrollIcon(size: size)
            case .circleUser:             CircleUserIcon(size: size)
            case .user:                   UserIcon(size: size)
            case .layoutGrid:             LayoutGridIcon(size: size)
            case .grid2x2:                Grid2x2Icon(size: size)
            case .clipboardList:          ClipboardListIcon(size: size)
            case .radioTower:             RadioTowerIcon(size: size)
            case .rss:                    RssIcon(size: size)
            case .circleHelp:             CircleHelpIcon(size: size)
            case .brain:                  BrainIcon(size: size)
            case .smartphone:             SmartphoneIcon(size: size)
            case .code:                   CodeIcon(size: size)
            case .heart:                  HeartIcon(size: size)
            case .bookmark:               BookmarkIcon(size: size)
            case .shield:                 ShieldIcon(size: size)
            case .lightbulb:              LightbulbIcon(size: size)
            case .flame:                  FlameIcon(size: size)
            case .pencil:                 PencilIcon(size: size)
            case .wrench:                 WrenchLineIcon(size: size)
            case .gitBranch:              GitBranchLineIcon(size: size)
            case .sun:                    SunIcon(size: size)
            case .keyboard:               KeyboardIcon(size: size)
            case .fingerprint:            FingerprintIcon(size: size)
            case .slidersHorizontal:      SlidersHorizontalIcon(size: size)
            case .package:                PackageIcon(size: size)
            case .monitor:                MonitorIcon(size: size)
            case .server:                 ServerIcon(size: size)
            case .smile:                  SmileIcon(size: size)
            case .layoutDashboard:        LayoutDashboardIcon(size: size)
            case .puzzle:                 PuzzleIcon(size: size)
            case .plug:                   PlugIcon(size: size)
            case .blocks:                 BlocksIcon(size: size)
            case .panelTop:               PanelTopIcon(size: size)
            case .listTodo:               ListTodoIcon(size: size)
            case .squareMousePointer:     SquareMousePointerIcon(size: size)
            case .keyRound:               KeyRoundIcon(size: size)
            }
        }
        .accessibilityHidden(true)
    }

    /// Maps an SF Symbol-style name to a Lucide kind. Used by the
    /// `auto(_:)` helper at sites where the icon name is computed at
    /// runtime (settings categories, plugin metadata, permission modes).
    static func sfMapped(_ symbol: String) -> Kind? {
        switch symbol {
        case "chevron.down":  return .chevronDown
        case "chevron.up":    return .chevronUp
        case "chevron.left":  return .chevronLeft
        case "chevron.right": return .chevronRight
        case "xmark":         return .x
        case "plus":          return .plus
        case "minus":         return .minus
        case "checkmark":     return .check
        case "ellipsis":      return .ellipsis

        case "arrow.up":      return .arrowUp
        case "arrow.down":    return .arrowDown
        case "arrow.left":    return .arrowLeft
        case "arrow.right":   return .arrowRight
        case "arrow.up.right": return .arrowUpRight
        case "arrow.up.right.square": return .squareArrowOutUpRight
        case "arrow.right.to.line": return .arrowRightToLine
        case "arrow.down.to.line":  return .arrowDownToLine
        case "arrow.down.circle":   return .arrowDown
        case "arrow.uturn.backward": return .undo2
        case "arrow.clockwise":      return .rotateCw
        case "arrow.counterclockwise": return .rotateCcw
        case "arrow.triangle.2.circlepath": return .refreshCw
        case "arrow.up.left.and.arrow.down.right": return .maximize2
        case "arrow.down.right.and.arrow.up.left": return .minimize2

        case "trash":            return .trash
        case "magnifyingglass":  return .search
        case "folder", "folder.fill": return .folder
        case "archivebox":       return .archive
        case "bubble.left":      return .messageCircle
        case "globe", "globe.americas.fill": return .globe
        case "paperclip":        return .paperclip
        case "camera", "camera.fill", "camera.viewfinder": return .camera
        case "photo":            return .image
        case "photo.on.rectangle.angled": return .images
        case "photo.badge.exclamationmark": return .imageOff
        case "paperplane", "paperplane.fill": return .send
        case "bolt", "bolt.fill": return .zap
        case "bolt.slash", "bolt.slash.fill": return .zapOff
        case "star", "star.fill": return .star
        case "clock", "timer":   return .clock
        case "list.bullet":      return .list
        case "checklist":        return .listChecks
        case "text.alignleft":   return .textAlignStart
        case "flag":             return .listChecks
        case "note.text", "doc.text": return .fileText
        case "square.stack.3d.up", "square.stack", "square.stack.fill",
             "square.3.layers.3d", "square.3.stack.3d": return .layers
        case "brain", "brain.head.profile": return .brain
        case "cylinder.split.1x2", "internaldrive": return .database
        case "clock.arrow.circlepath": return .clock
        case "key.viewfinder":   return .key
        case "link", "link.circle": return .link
        case "laptopcomputer":   return .laptop
        case "viewfinder", "crop", "rectangle.inset.filled": return .scan
        case "tornado":          return .tornado
        case "theatermasks":     return .drama
        case "doc.questionmark": return .fileQuestionMark
        case "questionmark.square.dashed", "app.dashed": return .squareDashed
        case "app", "macwindow": return .appWindow
        case "point.3.connected.trianglepath.dotted": return .workflow
        case "square.and.arrow.down": return .download
        case "square.and.arrow.up":   return .share2
        case "tray.and.arrow.down":   return .inbox
        case "play", "play.fill":     return .play
        case "pause", "pause.fill":   return .pause
        case "stop.fill":             return .square
        case "stop.circle", "stop.circle.fill": return .circleStop
        case "record.circle":        return .circleDot
        case "moon", "moon.zzz":      return .moon
        case "waveform":              return .audioWaveform
        case "exclamationmark.triangle",
             "exclamationmark.triangle.fill": return .triangleAlert
        case "exclamationmark.circle",
             "exclamationmark.circle.fill": return .circleAlert
        case "exclamationmark.shield",
             "exclamationmark.shield.fill": return .shieldAlert
        case "exclamationmark.applewatch": return .circleAlert
        case "info.circle", "info.circle.fill": return .info
        case "text.viewfinder":      return .textAlignStart
        case "checkmark.circle", "checkmark.circle.fill": return .circleCheck
        case "xmark.circle", "xmark.circle.fill": return .circleX
        case "circle":            return .circleDot
        case "badge.check":       return .badgeCheck
        // Former catch-all that collapsed a dozen concepts into one
        // circle+dot placeholder. Each now resolves to a real glyph.
        case "bookmark", "bookmark.fill":  return .bookmark
        case "cloud.moon", "moon.stars":   return .moon
        case "shield", "shield.fill", "checkmark.shield": return .shield
        case "pencil", "pencil.line", "square.and.pencil", "pencil.circle": return .pencil
        case "lightbulb", "lightbulb.fill": return .lightbulb
        case "person.crop.circle", "person", "person.fill", "person.circle": return .circleUser
        case "bubble.middle.bottom", "quote.bubble", "bubble.right": return .messageCircle
        case "safari":            return .globe
        case "flame", "flame.fill": return .flame
        case "arrow.triangle.branch": return .gitBranch
        // Former SF passthroughs in the sidebar / tools catalog.
        case "house", "house.fill": return .house
        case "calendar", "calendar.badge.clock": return .calendar
        case "books.vertical", "books.vertical.fill", "book", "book.closed": return .library
        case "network":           return .globe
        case "layers", "square.3.stack.3d.top.filled": return .layers
        case "puzzle", "puzzlepiece", "puzzlepiece.extension", "puzzlepiece.fill": return .puzzle
        case "plug", "powerplug", "powerplug.fill", "poweroutlet.type.b": return .plug
        case "blocks", "building.columns", "shippingbox.and.arrow.backward": return .blocks
        case "list.todo", "checklist.checked", "checkmark.rectangle": return .listTodo
        case "square.mouse.pointer", "rectangle.and.hand.point.up.left", "cursorarrow.rays": return .squareMousePointer
        case "key.round", "key.horizontal": return .keyRound
        case "panel.top", "menubar.rectangle": return .panelTop
        case "megaphone", "megaphone.fill": return .megaphone
        case "handshake", "hands.sparkles": return .handshake
        case "wand.and.stars", "wand.and.rays", "wand.and.stars.inverse": return .wandSparkles
        case "sparkles":          return .sparkles
        case "paintbrush", "paintbrush.fill", "paintbrush.pointed": return .paintbrush
        case "paintpalette", "paintpalette.fill", "swatchpalette": return .palette
        case "scroll", "scroll.fill", "doc.plaintext": return .scroll
        case "rectangle.3.group", "rectangle.grid.2x2", "rectangle.grid.2x2.fill",
             "rectangle.3.offgrid": return .layoutGrid
        case "square.grid.2x2", "square.grid.2x2.fill",
             "circle.grid.2x2", "circle.grid.2x2.fill", "square.grid.3x3": return .grid2x2
        case "list.bullet.rectangle", "list.bullet.rectangle.portrait",
             "list.bullet.clipboard", "list.clipboard": return .clipboardList
        case "antenna.radiowaves.left.and.right",
             "antenna.radiowaves.left.and.right.circle": return .radioTower
        case "dot.radiowaves.left.and.right", "dot.radiowaves.right",
             "dot.radiowaves.up.forward": return .rss
        case "questionmark.circle", "questionmark.circle.fill", "questionmark": return .circleHelp
        case "smartphone", "iphone", "ipad", "ipad.landscape": return .smartphone
        case "heart", "heart.fill": return .heart
        case "chevron.left.slash.chevron.right", "curlybraces", "curlybraces.square": return .code
        case "wrench.and.screwdriver", "wrench.and.screwdriver.fill",
             "wrench", "wrench.fill", "wrench.adjustable": return .wrench
        case "keyboard", "keyboard.fill": return .keyboard
        case "fingerprint", "touchid": return .fingerprint
        case "slider.horizontal.3", "slider.horizontal.2.square", "slider.vertical.3": return .slidersHorizontal
        case "shippingbox", "shippingbox.fill", "cube", "cube.box": return .package
        case "macwindow.on.rectangle", "display", "display.2", "tv": return .monitor
        case "server.rack", "xserve": return .server
        case "sun.max", "sun.min", "sun.max.fill": return .sun
        case "face.smiling", "face.smiling.fill", "smiley": return .smile
        case "square.grid.3x1.below.line.grid.1x2", "rectangle.grid.1x2": return .layoutDashboard
        case "eye":               return .eye
        case "eye.slash":         return .eyeOff
        case "eyeglasses", "eyeglasses.slash": return .glasses
        default: return nil
        }
    }

    /// Resolves an SF Symbol-style name at runtime: renders a Lucide
    /// glyph for known mappings, falls back to `Image(systemName:)` for
    /// genuinely OS-level chrome (`command`, `return` for keyboard
    /// shortcut hints) or any name we have not mapped yet.
    @ViewBuilder
    static func auto(_ systemName: String, size: CGFloat = 16) -> some View {
        if let kind = LucideIcon.sfMapped(systemName) {
            LucideIcon(kind, size: size)
        } else {
            Image(systemName: systemName)
                .font(.system(size: size))
        }
    }
}
