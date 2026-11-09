import Foundation

/// Binary raster with the few morphology operations the detector needs. Structuring element is
/// the 3x3 cross (4-connectivity), like scipy's defaults the Python prototype was tuned with.
struct Bitmap: Sendable {
    let width: Int
    let height: Int
    var bits: [Bool]

    init(width: Int, height: Int, fill: Bool = false) {
        self.width = width
        self.height = height
        bits = [Bool](repeating: fill, count: width * height)
    }

    init(width: Int, height: Int, bits: [Bool]) {
        precondition(bits.count == width * height)
        self.width = width
        self.height = height
        self.bits = bits
    }

    @inline(__always) subscript(x: Int, y: Int) -> Bool {
        get { bits[y * width + x] }
        set { bits[y * width + x] = newValue }
    }

    /// Value at a position that may be outside the raster (false there).
    @inline(__always) func value(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height && bits[y * width + x]
    }

    var count: Int { bits.reduce(0) { $0 + ($1 ? 1 : 0) } }
    var isEmpty: Bool { !bits.contains(true) }

    func eroded(iterations: Int = 1) -> Bitmap {
        var current = self
        for _ in 0..<iterations {
            var next = current
            for y in 0..<height {
                for x in 0..<width where current[x, y] {
                    // Border pixels erode (scipy pads with false).
                    if !(current.value(x: x - 1, y: y) && current.value(x: x + 1, y: y)
                        && current.value(x: x, y: y - 1) && current.value(x: x, y: y + 1)) {
                        next[x, y] = false
                    }
                }
            }
            current = next
        }
        return current
    }

    func dilated(iterations: Int = 1) -> Bitmap {
        var current = self
        for _ in 0..<iterations {
            var next = current
            for y in 0..<height {
                for x in 0..<width where !current[x, y] {
                    if current.value(x: x - 1, y: y) || current.value(x: x + 1, y: y)
                        || current.value(x: x, y: y - 1) || current.value(x: x, y: y + 1) {
                        next[x, y] = true
                    }
                }
            }
            current = next
        }
        return current
    }

    func opened(iterations: Int = 1) -> Bitmap { eroded(iterations: iterations).dilated(iterations: iterations) }
    func closed(iterations: Int = 1) -> Bitmap { dilated(iterations: iterations).eroded(iterations: iterations) }

    /// 4-connected components: label per pixel (0 = background, 1...count) and the size of each label.
    func components() -> (labels: [Int32], sizes: [Int]) {
        var labels = [Int32](repeating: 0, count: width * height)
        var sizes: [Int] = []
        var stack: [Int] = []
        stack.reserveCapacity(1024)
        for start in 0..<(width * height) where bits[start] && labels[start] == 0 {
            let label = Int32(sizes.count + 1)
            var size = 0
            labels[start] = label
            stack.append(start)
            while let index = stack.popLast() {
                size += 1
                let x = index % width, y = index / width
                if x > 0, bits[index - 1], labels[index - 1] == 0 { labels[index - 1] = label; stack.append(index - 1) }
                if x + 1 < width, bits[index + 1], labels[index + 1] == 0 { labels[index + 1] = label; stack.append(index + 1) }
                if y > 0, bits[index - width], labels[index - width] == 0 { labels[index - width] = label; stack.append(index - width) }
                if y + 1 < height, bits[index + width], labels[index + width] == 0 { labels[index + width] = label; stack.append(index + width) }
            }
            sizes.append(size)
        }
        return (labels, sizes)
    }

    /// Fills enclosed background regions of at most `maxArea` pixels (boats, obstacles, glint);
    /// larger holes are islands and stay.
    func fillingHoles(maxArea: Int) -> Bitmap {
        let background = Bitmap(width: width, height: height, bits: bits.map { !$0 })
        let (labels, sizes) = background.components()
        var touchesBorder = [Bool](repeating: false, count: sizes.count + 1)
        for x in 0..<width {
            touchesBorder[Int(labels[x])] = true
            touchesBorder[Int(labels[(height - 1) * width + x])] = true
        }
        for y in 0..<height {
            touchesBorder[Int(labels[y * width])] = true
            touchesBorder[Int(labels[y * width + width - 1])] = true
        }
        var result = self
        for index in 0..<(width * height) where !bits[index] {
            let label = Int(labels[index])
            if label > 0, !touchesBorder[label], sizes[label - 1] <= maxArea {
                result.bits[index] = true
            }
        }
        return result
    }

    /// Only the pixels carrying `label`.
    static func component(_ label: Int32, in labels: [Int32], width: Int, height: Int) -> Bitmap {
        Bitmap(width: width, height: height, bits: labels.map { $0 == label })
    }
}
