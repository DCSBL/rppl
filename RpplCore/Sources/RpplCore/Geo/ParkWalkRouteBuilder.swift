import Foundation

/// One averaged walking route per park from the walk tracks of every session there.
///
/// Each session walks the same shore path back to the dock a few meters apart, and a map that
/// strokes every walk is a tangle. This bundles them: keep the points that several walks pass,
/// pull each point sideways onto the local centre line of its neighbours (a mean shift that only
/// moves across the walk, so points never pile up along it), thin them to a grid, join neighbours
/// into a minimum spanning tree and read the longest paths off it. Every section is one line; a
/// side path that runs along an existing section within the link distance is dropped.
public enum ParkWalkRouteBuilder {
    /// Neighbourhood for density and mean shift (m).
    public static let neighbourRadiusM = 10.0
    /// A point needs this many walk points around it to count.
    public static let minNeighbours = 3
    /// With this many sessions or more, a point must come from two sessions.
    public static let multiSessionMinimum = 4
    public static let meanShiftIterations = 5
    public static let gridCellM = 4.0
    /// Thinned points closer than this are linked.
    public static let linkDistanceM = 22.0
    public static let minSectionMeters = 30.0
    public static let maxSections = 4
    public static let minPoints = 10

    /// `tracks`: one entry per session, that session's walk polylines.
    public static func sections(sessionTracks: [[[MapCoordinate]]]) -> [[MapCoordinate]] {
        var points: [Point] = []
        for (session, tracks) in sessionTracks.enumerated() {
            for track in tracks {
                for coordinate in track {
                    points.append(Point(x: 0, y: 0, session: session, coordinate: coordinate))
                }
            }
        }
        guard points.count >= minPoints else { return [] }
        let origin = (
            latitude: points.map(\.coordinate.latitude).reduce(0, +) / Double(points.count),
            longitude: points.map(\.coordinate.longitude).reduce(0, +) / Double(points.count)
        )
        let metersPerLongitude = 111_320 * cos(origin.latitude * .pi / 180)
        for index in points.indices {
            points[index].x = (points[index].coordinate.longitude - origin.longitude) * metersPerLongitude
            points[index].y = (points[index].coordinate.latitude - origin.latitude) * 110_574
        }
        let sessionCount = Set(points.map(\.session)).count
        let requiredSessions = sessionCount >= multiSessionMinimum ? 2 : 1

        // Density: keep points that several walks pass.
        var grid = Grid(points: points.map { ($0.x, $0.y) }, cell: neighbourRadiusM)
        var kept: [(Double, Double)] = []
        for point in points {
            let neighbours = grid.neighbours(of: (point.x, point.y), within: neighbourRadiusM)
            guard neighbours.count >= minNeighbours else { continue }
            let sessions = Set(neighbours.map { points[$0].session })
            guard sessions.count >= requiredSessions else { continue }
            kept.append((point.x, point.y))
        }
        guard kept.count >= minPoints else { return [] }

        // Mean shift toward the ridge of the walk, across it only.
        for _ in 0..<meanShiftIterations {
            grid = Grid(points: kept, cell: neighbourRadiusM)
            kept = kept.map { point in
                shiftedAcross(point, neighbours: grid.neighbours(of: point, within: neighbourRadiusM).map { kept[$0] })
            }
        }

        // Thin to one point per grid cell.
        var seen = Set<GridKey>()
        var nodes: [(Double, Double)] = []
        for point in kept {
            let key = GridKey(x: Int((point.0 / gridCellM).rounded()), y: Int((point.1 / gridCellM).rounded()))
            if seen.insert(key).inserted { nodes.append(point) }
        }
        guard nodes.count >= 2 else { return [] }

        // Minimum spanning tree over nearby nodes.
        grid = Grid(points: nodes, cell: linkDistanceM)
        var edges: [Edge] = []
        for (index, node) in nodes.enumerated() {
            for other in grid.neighbours(of: node, within: linkDistanceM) where other > index {
                edges.append(Edge(a: index, b: other, weight: distance(node, nodes[other])))
            }
        }
        edges.sort { $0.weight < $1.weight }
        var union = UnionFind(count: nodes.count)
        var adjacency = Array(repeating: [(Int, Double)](), count: nodes.count)
        for edge in edges where union.join(edge.a, edge.b) {
            adjacency[edge.a].append((edge.b, edge.weight))
            adjacency[edge.b].append((edge.a, edge.weight))
        }

        // Longest paths, one component at a time.
        var alive = Array(repeating: true, count: nodes.count)
        var sections: [[(Double, Double)]] = []
        var visited = Array(repeating: false, count: nodes.count)
        for start in nodes.indices where !visited[start] {
            var component: [Int] = []
            var stack = [start]
            visited[start] = true
            while let node = stack.popLast() {
                component.append(node)
                for (next, _) in adjacency[node] where !visited[next] {
                    visited[next] = true
                    stack.append(next)
                }
            }
            guard component.count >= 4 else { continue }
            for _ in 0..<maxSections {
                guard let path = longestPath(in: component, adjacency: adjacency, alive: alive),
                      path.length >= minSectionMeters
                else { break }
                let line = path.nodes.map { nodes[$0] }
                sections.append(smoothed(line))
                for node in component where alive[node] {
                    if line.contains(where: { distance($0, nodes[node]) < linkDistanceM }) {
                        alive[node] = false
                    }
                }
            }
        }

        return sections.map { line in
            line.map { point in
                MapCoordinate(
                    latitude: origin.latitude + point.1 / 110_574,
                    longitude: origin.longitude + point.0 / metersPerLongitude
                )
            }
        }
    }

    // MARK: - Helpers

    struct Edge {
        var a: Int
        var b: Int
        var weight: Double
    }

    /// Where a tree walk from a node ends: the farthest node, how far, and each node's predecessor.
    struct Reach {
        var node: Int
        var distance: Double
        var predecessor: [Int: Int]
    }

    /// `point` moved onto the line its neighbours lie along, keeping its place along that line.
    ///
    /// A plain mean shift drags sparse points along the walk into clumps; moving only the component
    /// across the neighbourhood's principal direction straightens the walk without shortening it.
    static func shiftedAcross(_ point: (Double, Double), neighbours: [(Double, Double)]) -> (Double, Double) {
        guard !neighbours.isEmpty else { return point }
        let count = Double(neighbours.count)
        let centreX = neighbours.reduce(0.0) { $0 + $1.0 } / count
        let centreY = neighbours.reduce(0.0) { $0 + $1.1 } / count
        var sumXX = 0.0, sumYY = 0.0, sumXY = 0.0
        for neighbour in neighbours {
            let dx = neighbour.0 - centreX, dy = neighbour.1 - centreY
            sumXX += dx * dx
            sumYY += dy * dy
            sumXY += dx * dy
        }
        guard sumXX + sumYY > 1e-9 else { return (centreX, centreY) }
        let angle = 0.5 * atan2(2 * sumXY, sumXX - sumYY)
        let direction = (cos(angle), sin(angle))
        let offset = (centreX - point.0, centreY - point.1)
        let along = offset.0 * direction.0 + offset.1 * direction.1
        return (point.0 + offset.0 - along * direction.0, point.1 + offset.1 - along * direction.1)
    }

    struct Point {
        var x: Double
        var y: Double
        var session: Int
        var coordinate: MapCoordinate
    }

    struct GridKey: Hashable {
        var x: Int
        var y: Int
    }

    /// Hash grid for radius queries.
    struct Grid {
        let cell: Double
        var cells: [GridKey: [Int]] = [:]
        let points: [(Double, Double)]

        init(points: [(Double, Double)], cell: Double) {
            self.points = points
            self.cell = cell
            for (index, point) in points.enumerated() {
                cells[key(point), default: []].append(index)
            }
        }

        func key(_ point: (Double, Double)) -> GridKey {
            GridKey(x: Int((point.0 / cell).rounded(.down)), y: Int((point.1 / cell).rounded(.down)))
        }

        func neighbours(of point: (Double, Double), within radius: Double) -> [Int] {
            let centre = key(point)
            let reach = Int((radius / cell).rounded(.up))
            var result: [Int] = []
            for dx in -reach...reach {
                for dy in -reach...reach {
                    guard let bucket = cells[GridKey(x: centre.x + dx, y: centre.y + dy)] else { continue }
                    for index in bucket where ParkWalkRouteBuilder.distance(points[index], point) <= radius {
                        result.append(index)
                    }
                }
            }
            return result
        }
    }

    struct UnionFind {
        var parent: [Int]

        init(count: Int) { parent = Array(0..<count) }

        mutating func find(_ a: Int) -> Int {
            var root = a
            while parent[root] != root { root = parent[root] }
            var node = a
            while parent[node] != root {
                let next = parent[node]
                parent[node] = root
                node = next
            }
            return root
        }

        /// False when already connected.
        mutating func join(_ a: Int, _ b: Int) -> Bool {
            let rootA = find(a), rootB = find(b)
            guard rootA != rootB else { return false }
            parent[rootA] = rootB
            return true
        }
    }

    static func distance(_ a: (Double, Double), _ b: (Double, Double)) -> Double {
        ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1)).squareRoot()
    }

    /// Farthest node from `from` over alive tree nodes, with the path back.
    static func farthest(from: Int, adjacency: [[(Int, Double)]], alive: [Bool]) -> Reach {
        var reach = Reach(node: from, distance: 0, predecessor: [from: -1])
        var stack: [(Int, Double)] = [(from, 0)]
        while let item = stack.popLast() {
            let (node, total) = item
            if total > reach.distance {
                reach.node = node
                reach.distance = total
            }
            for (next, weight) in adjacency[node] where alive[next] && reach.predecessor[next] == nil {
                reach.predecessor[next] = node
                stack.append((next, total + weight))
            }
        }
        return reach
    }

    static func longestPath(
        in component: [Int], adjacency: [[(Int, Double)]], alive: [Bool]
    ) -> (nodes: [Int], length: Double)? {
        guard let seed = component.first(where: { alive[$0] }) else { return nil }
        let tail = farthest(from: seed, adjacency: adjacency, alive: alive)
        let head = farthest(from: tail.node, adjacency: adjacency, alive: alive)
        var path: [Int] = []
        var node = head.node
        while node != -1 {
            path.append(node)
            node = head.predecessor[node] ?? -1
        }
        return (nodes: path, length: head.distance)
    }

    /// Three-point moving average, endpoints kept.
    static func smoothed(_ line: [(Double, Double)]) -> [(Double, Double)] {
        guard line.count >= 3 else { return line }
        var out = line
        for index in 1..<(line.count - 1) {
            out[index] = (
                (line[index - 1].0 + line[index].0 + line[index + 1].0) / 3,
                (line[index - 1].1 + line[index].1 + line[index + 1].1) / 3
            )
        }
        return out
    }
}
