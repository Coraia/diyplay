import Foundation

enum OverrideFile {
    static let root = "/Library/Displays/Contents/Resources/Overrides"

    static func directory(vendor: Int) -> String {
        String(format: "%@/DisplayVendorID-%04x", root, vendor)
    }

    static func path(vendor: Int, product: Int) -> String {
        String(format: "%@/DisplayProductID-%04x", directory(vendor: vendor), product)
    }

    static func hidpi(_ w: Int, _ h: Int) -> Data {
        be32(w) + be32(h) + be32(0x0000_0009) + be32(0x0020_0000)
    }

    static func payload(
        vendor: Int,
        product: Int,
        native: (Int, Int),
        slider: [(Int, Int)],
        defaultUI: (Int, Int)
    ) throws -> Data {
        let plist: [String: Any] = [
            "DisplayVendorID": vendor,
            "DisplayProductID": product,
            "DisplayIsTV": false,
            "DisplayPixelDimensions": be32(native.0) + be32(native.1),
            "default-resolution": be32(defaultUI.0) + be32(defaultUI.1) + be32(0x3C),
            "scale-resolutions": slider.map { hidpi($0.0, $0.1) },
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    static func write(
        vendor: Int,
        product: Int,
        native: (Int, Int),
        slider: [(Int, Int)],
        defaultUI: (Int, Int)
    ) throws {
        let dir = directory(vendor: vendor)
        let dest = path(vendor: vendor, product: product)
        let data = try payload(
            vendor: vendor,
            product: product,
            native: native,
            slider: slider,
            defaultUI: defaultUI
        )
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: dest), options: .atomic)
        } catch {
            throw DisplayError.overrideNotWritable
        }
    }

    private static func be32(_ n: Int) -> Data {
        var v = UInt32(n).bigEndian
        return withUnsafeBytes(of: &v) { Data($0) }
    }
}

enum Ladder {
    static func hidpi(nativeW: Int, nativeH: Int) -> [(w: Int, h: Int, label: String)] {
        let steps: [(Double, String)] = [
            (2.0, "更锐"),
            (1.5, "偏锐"),
            (1.25, "日常"),
            (1.0, "最大"),
        ]
        var seen = Set<String>()
        var out: [(w: Int, h: Int, label: String)] = []
        for (scale, label) in steps {
            var w = Int((Double(nativeW) / scale).rounded())
            var h = Int((Double(nativeH) / scale).rounded())
            w -= w % 2
            h -= h % 2
            guard w >= 640, h >= 480 else { continue }
            let key = "\(w)x\(h)"
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append((w, h, label))
        }
        return out
    }
}

struct NativePreset: Equatable {
    var id: String
    var title: String
    var width: Int
    var height: Int
    var slider: [(w: Int, h: Int, label: String)]?

    var size: (w: Int, h: Int) { (width, height) }

    var resolvedSlider: [(w: Int, h: Int, label: String)] {
        slider ?? Ladder.hidpi(nativeW: width, nativeH: height)
    }

    static func == (lhs: NativePreset, rhs: NativePreset) -> Bool {
        lhs.id == rhs.id
    }
}

enum PresetBank {
    static func presets(vendor: Int, product: Int) -> [NativePreset] {
        if vendor == 9699, product == 65535 {
            return [
                NativePreset(
                    id: "phone",
                    title: "Phone 右窗",
                    width: 2824,
                    height: 2160,
                    slider: [
                        (1412, 1080, "更锐"),
                        (1920, 1469, "日常"),
                        (2259, 1728, "更大"),
                        (2824, 2160, "最大"),
                    ]
                ),
                NativePreset(
                    id: "half",
                    title: "对半 1:1",
                    width: 1920,
                    height: 2160,
                    slider: [
                        (960, 1080, "更锐"),
                        (1536, 1728, "日常"),
                        (1920, 2160, "最大"),
                    ]
                ),
                NativePreset(
                    id: "full",
                    title: "整屏 4K",
                    width: 3840,
                    height: 2160,
                    slider: nil
                ),
            ]
        }
        return []
    }
}
