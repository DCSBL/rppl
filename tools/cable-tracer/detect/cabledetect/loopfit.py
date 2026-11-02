from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from scipy import ndimage
from scipy.spatial import ConvexHull, cKDTree
from shapely.geometry import LineString, Point, Polygon

from .features import Blob

# Priors from the 27 traced parks (2026-11): loop perimeter 480-1000 m, median ~700 m.
PERIMETER_MEDIAN_M = 700.0
PERIMETER_LOG_SIGMA = 0.28


@dataclass
class LoopCandidate:
    vertices_xy: np.ndarray  # metres, local frame, convex, travel order unknown
    score: float
    vertex_support: list[float]
    edge_support: float
    water_fraction: float
    perimeter_m: float
    notes: list[str] = field(default_factory=list)

    @property
    def polygon(self) -> Polygon:
        return Polygon(self.vertices_xy)


def cluster_points(points: np.ndarray, link_m: float) -> list[np.ndarray]:
    """Single-linkage clusters: indices of points chained by distances <= link_m."""
    if len(points) == 0:
        return []
    tree = cKDTree(points)
    pairs = tree.query_pairs(link_m)
    parent = list(range(len(points)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for a, b in pairs:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    groups: dict[int, list[int]] = {}
    for i in range(len(points)):
        groups.setdefault(find(i), []).append(i)
    return [np.array(g) for g in sorted(groups.values(), key=len, reverse=True)]


def merge_close(points: np.ndarray, weights: np.ndarray, radius_m: float) -> tuple[np.ndarray, np.ndarray]:
    """Mast platforms and their shadows split into 2-3 blobs; merge them into one weighted point."""
    merged_p, merged_w = [], []
    for group in cluster_points(points, radius_m):
        w = weights[group]
        merged_p.append((points[group] * w[:, None]).sum(axis=0) / w.sum())
        merged_w.append(w.sum())
    return np.array(merged_p), np.array(merged_w)


class LoopScorer:
    def __init__(self, blobs_xy: np.ndarray, blob_weights: np.ndarray, water_xy_test, vertex_radius_m=14.0, edge_radius_m=18.0):
        self.blobs_xy = blobs_xy
        self.blob_weights = blob_weights
        self.water_xy_test = water_xy_test  # callable: (N,2) metres -> bool array
        self.vertex_radius_m = vertex_radius_m
        self.edge_radius_m = edge_radius_m
        self.tree = cKDTree(blobs_xy) if len(blobs_xy) else None

    def score(self, vertices: np.ndarray) -> LoopCandidate:
        polygon = Polygon(vertices)
        notes = []
        if not polygon.is_valid or polygon.area < 1:
            return LoopCandidate(vertices, -1e9, [], 0, 0, 0, ["degenerate"])
        hull = ConvexHull(vertices)
        convex = len(hull.vertices) == len(vertices)
        perimeter = polygon.length
        ring = LineString(list(vertices) + [vertices[0]])

        # Vertex support: a blob (mast platform/shadow) close to each vertex, capped at 1 per vertex.
        support = []
        for v in vertices:
            if self.tree is None:
                support.append(0.0)
                continue
            d, i = self.tree.query(v)
            support.append(float(min(1.0, self.blob_weights[i] / 2)) * max(0.0, 1 - d / self.vertex_radius_m) if d < self.vertex_radius_m else 0.0)
        # Edge support: obstacles sit along the cable, inside or on the line.
        edge = 0.0
        outside_penalty = 0.0
        interior_penalty = 0.0
        for p, w in zip(self.blobs_xy, self.blob_weights):
            point = Point(p)
            d = ring.distance(point)
            if d <= self.edge_radius_m:
                edge += min(1.0, w / 2)
            elif polygon.contains(point):
                # Obstacles sit along the cable; the middle of a loop is empty water.
                interior_penalty += 1.0 * min(1.0, w / 2)
            elif d < 120:
                outside_penalty += 0.25 * min(1.0, w / 2)  # a floating thing just outside the loop is suspicious
        edge = min(edge, 10.0)

        # Edges must run over water; sample every ~5 m.
        samples = []
        for a, b in zip(vertices, np.roll(vertices, -1, axis=0)):
            n = max(2, int(np.linalg.norm(b - a) / 5))
            samples.append(a + (b - a) * np.linspace(0, 1, n, endpoint=False)[:, None])
        samples = np.concatenate(samples)
        water_fraction = float(np.mean(self.water_xy_test(samples)))

        prior = -((np.log(perimeter / PERIMETER_MEDIAN_M)) ** 2) / (2 * PERIMETER_LOG_SIGMA ** 2)
        # Shape prior: real loops are wide (axis ratio rarely over 3.5).
        rect = polygon.minimum_rotated_rectangle
        xs, ys = rect.exterior.coords.xy
        edges = [np.hypot(xs[i + 1] - xs[i], ys[i + 1] - ys[i]) for i in range(2)]
        ratio = max(edges) / max(1e-6, min(edges))
        shape = -max(0.0, ratio - 3.5)

        # Most full-size systems have 5 masts; 4 and 6 happen, more is a trace with extra points.
        complexity = {4: -0.5, 5: 0.0, 6: -2.0}.get(len(vertices), -4.0)
        total = 2.0 * sum(support) + 0.6 * edge - outside_penalty - interior_penalty + 4.0 * prior + shape + complexity
        if water_fraction < 0.97:
            total -= 40 * (0.97 - water_fraction) * 10
            notes.append(f"edges over land: {100 * (1 - water_fraction):.0f}%")
        if not convex:
            total -= 20
            notes.append("not convex")
        return LoopCandidate(vertices, total, support, edge, water_fraction, perimeter, notes)


def simplify_hull(points: np.ndarray, target: int) -> np.ndarray:
    """Convex hull reduced to `target` vertices by dropping the vertex that loses the least area."""
    hull = ConvexHull(points)
    verts = points[hull.vertices]
    while len(verts) > target:
        best, best_loss = None, None
        for i in range(len(verts)):
            trial = np.delete(verts, i, axis=0)
            loss = Polygon(verts).area - Polygon(trial).area
            if best_loss is None or loss < best_loss:
                best, best_loss = trial, loss
        verts = best
    return verts


def refine(scorer: LoopScorer, vertices: np.ndarray, step_m: float = 6.0, radius_m: float = 30.0, rounds: int = 4) -> LoopCandidate:
    """Coordinate descent: move one vertex at a time on a grid, keep improvements."""
    best = scorer.score(vertices)
    offsets = np.array([[dx, dy] for dx in np.arange(-radius_m, radius_m + 1e-6, step_m) for dy in np.arange(-radius_m, radius_m + 1e-6, step_m)])
    for _ in range(rounds):
        improved = False
        for i in range(len(best.vertices_xy)):
            base = best.vertices_xy.copy()
            for off in offsets:
                trial = base.copy()
                trial[i] = base[i] + off
                candidate = scorer.score(trial)
                if candidate.score > best.score + 1e-6:
                    best = candidate
                    improved = True
        if not improved:
            break
    return best


def propose_loops(blobs: list[Blob], blob_xy: np.ndarray, water_xy_test, vertex_counts=(4, 5, 6), max_distance_m: float = 520.0) -> list[LoopCandidate]:
    """Loop proposals from the floating objects: the convex hull of the main blob cluster,
    simplified to 4-6 vertices, then refined against the image evidence. Returns candidates
    sorted by score (best first)."""
    # The cable is never far from the park location (all 27 traced parks: centroid < 260 m).
    near = np.linalg.norm(blob_xy, axis=1) <= max_distance_m if len(blob_xy) else np.zeros(0, bool)
    blobs = [b for b, keep in zip(blobs, near) if keep]
    blob_xy = blob_xy[near]
    if len(blob_xy) < 4:
        return []
    weights = np.array([max(1.0, b.area_m2 / 4) for b in blobs])
    points, weights = merge_close(blob_xy, weights, radius_m=10.0)
    scorer = LoopScorer(points, weights, water_xy_test)
    candidates: list[LoopCandidate] = []
    for group in cluster_points(points, link_m=260.0)[:2]:
        if len(group) < 4:
            continue
        cluster = points[group]
        for k in vertex_counts:
            if len(cluster) < k:
                continue
            try:
                start = simplify_hull(cluster, k)
            except Exception:
                continue
            # Blobs sit inside the cable line; push the hull out a little before refining.
            centroid = cluster.mean(axis=0)
            start = centroid + (start - centroid) * 1.06
            candidates.append(refine(scorer, start))
    candidates.sort(key=lambda c: c.score, reverse=True)
    return candidates
