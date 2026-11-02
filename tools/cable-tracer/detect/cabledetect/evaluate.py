from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from shapely.geometry import LineString, Polygon


@dataclass
class LoopMatch:
    iou: float
    mean_vertex_error_m: float   # each traced bend -> nearest proposed vertex
    max_vertex_error_m: float
    mean_line_error_m: float     # proposed vertices -> traced cable line
    perimeter_error_m: float


def compare(proposed_xy: np.ndarray, traced_xy: np.ndarray) -> LoopMatch:
    p = Polygon(proposed_xy)
    t = Polygon(traced_xy)
    iou = p.intersection(t).area / max(1e-6, p.union(t).area)
    vertex_errors = [float(np.min(np.linalg.norm(proposed_xy - v, axis=1))) for v in traced_xy]
    ring = LineString(list(traced_xy) + [traced_xy[0]])
    from shapely.geometry import Point
    line_errors = [ring.distance(Point(v)) for v in proposed_xy]
    return LoopMatch(
        iou=float(iou),
        mean_vertex_error_m=float(np.mean(vertex_errors)),
        max_vertex_error_m=float(np.max(vertex_errors)),
        mean_line_error_m=float(np.mean(line_errors)),
        perimeter_error_m=float(p.length - t.length),
    )
