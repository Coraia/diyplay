import Foundation

@main
struct Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args.first == "app" {
            MenuBarApp.run()
            return
        }
        CLI.run(args)
    }
}

enum CLI {
    static func run(_ args: [String]) {
        let cmd = args[0]
        switch cmd {
        case "status", "doctor":
            doctor(strict: cmd == "doctor")
        case "displays":
            for d in DisplayControl.listDisplays() {
                print("\(d.name)  vendor=\(d.vendor) product=\(d.product)  \(d.sizeText)")
            }
        case "apply":
            guard let d = DisplayControl.activeDisplay() else { fail("没有显示器") }
            apply(DisplayControl.preferredUI(d))
        case "native":
            guard args.count >= 2, let parsed = parseRes(args[1]),
                  let d = DisplayControl.activeDisplay()
            else {
                fputs("usage: diyplay native 2824x2160\n", stderr)
                exit(2)
            }
            do {
                try DisplayControl.setNative(d, width: parsed.w, height: parsed.h, presetId: nil)
                doctor(strict: false)
            } catch {
                fail(error.localizedDescription)
            }
        case "preset":
            guard args.count >= 2, let d = DisplayControl.activeDisplay(),
                  let preset = PresetBank.presets(vendor: d.vendor, product: d.product).first(where: { $0.id == args[1] })
            else {
                fputs("usage: diyplay preset phone|half|full\n", stderr)
                exit(2)
            }
            do {
                try DisplayControl.setNative(d, width: preset.width, height: preset.height, presetId: preset.id)
                doctor(strict: false)
            } catch {
                fail(error.localizedDescription)
            }
        case "res":
            guard args.count >= 2, let parsed = parseRes(args[1]) else {
                fputs("usage: diyplay res WxH\n", stderr)
                exit(2)
            }
            apply(parsed)
        case "help", "-h", "--help":
            help()
        default:
            fputs("unknown command: \(cmd)\n", stderr)
            help()
            exit(2)
        }
    }

    static func help() {
        print("""
        diyplay — 菜单栏显示工具（识别显示器 + 物理分辨率 + HiDPI）

        不带参数：菜单栏。Omarchy 无关。

        displays
        status / doctor
        native WxH          设定物理分辨率
        preset phone|half|full   32C1U 预设
        res WxH             HiDPI 看起来的大小
        apply
        """)
    }

    static func parseRes(_ s: String) -> (w: Int, h: Int)? {
        let p = s.lowercased().replacingOccurrences(of: "×", with: "x").split(separator: "x")
        guard p.count == 2, let w = Int(p[0]), let h = Int(p[1]) else { return nil }
        return (w, h)
    }

    static func doctor(strict: Bool) {
        guard let snap = DisplayControl.snapshot() else {
            print("display:     (none)")
            if strict { exit(1) }
            return
        }
        print("display:     \(snap.display.name)  vendor=\(snap.display.vendor) product=\(snap.display.product)")
        print("identified:  \(snap.display.sizeText)  timingId=\(snap.display.timingId.map(String.init) ?? "?")")
        print("physical:    \(snap.native.w)x\(snap.native.h)  preset=\(snap.presetId ?? "-")")
        if let ui = snap.ui {
            print("ui:          \(ui.pointsW)x\(ui.pointsH)  pixels \(ui.pixelsW)x\(ui.pixelsH)  \(String(format: "%.0f", ui.hz))Hz  hidpi=\(ui.hidpi)")
        } else {
            print("ui:          (unavailable)")
        }
        print("override:    \(OverrideFile.path(vendor: snap.display.vendor, product: snap.display.product))")
        if snap.problems.isEmpty {
            print("doctor:      ok")
        } else {
            for b in snap.problems { print("doctor:      FAIL \(b)") }
            if strict { exit(1) }
        }
    }

    static func apply(_ looksLike: (w: Int, h: Int)) {
        do {
            try DisplayControl.apply(looksLike: looksLike)
            doctor(strict: false)
        } catch {
            fail(error.localizedDescription)
        }
    }

    static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}
