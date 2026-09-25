"""Version 1 trace validators for the successor FFBD pipeline.

This is a development test helper, not a runtime dependency of tikzffbd.
Validators return a list of path-qualified errors; an empty list means valid.
"""

import json
import math
import re


USER_ID = re.compile(r"^[A-Za-z][A-Za-z0-9._-]*$")
INTERNAL_ID = re.compile(r"^@(flow|branch|join|port|continuation|region|text|constraint)/[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*$")
POSITIONS = {
    "top-left", "top-center", "top-right", "left", "right",
    "bottom-left", "bottom-center", "bottom-right",
}
KINDS = ("Spec", "Metrics", "Frame", "Constraint", "Diagnostic", "Regions",
         "Plan", "Geometry", "Routes", "Scene")


def _obj(value, path, errors, fields):
    if not isinstance(value, dict):
        errors.append(f"{path}: expected object")
        return False
    for field in fields:
        if field not in value:
            errors.append(f"{path}.{field}: required")
    return True


def _list(value, path, errors):
    if not isinstance(value, list):
        errors.append(f"{path}: expected array")
        return []
    return value


def _id(value, path, errors, internal=False):
    pattern = INTERNAL_ID if internal else USER_ID
    if not isinstance(value, str) or not pattern.fullmatch(value) or (isinstance(internal, str) and not value.startswith("@" + internal + "/")):
        errors.append(f"{path}: invalid {'internal' if internal else 'user'} ID")


def _node_id(value, path, errors):
    if isinstance(value, str) and (USER_ID.fullmatch(value) or (value.startswith(("@branch/", "@join/")) and INTERNAL_ID.fullmatch(value))):
        return
    errors.append(f"{path}: invalid node ID")


def _string(value, path, errors):
    if not isinstance(value, str) or not value:
        errors.append(f"{path}: expected nonempty string")


def _enum(value, choices, path, errors):
    if type(value) not in (str, int) or value not in choices:
        errors.append(f"{path}: expected one of {sorted(choices)}")


def _sp(value, path, errors, positive=False):
    if type(value) is not int or (positive and value <= 0):
        errors.append(f"{path}: expected {'positive ' if positive else ''}integer sp")


def _number(value, path, errors, positive=False):
    if type(value) not in (int, float) or not math.isfinite(value) or (positive and value <= 0):
        errors.append(f"{path}: expected finite {'positive ' if positive else ''}number")


def _rect(value, path, errors):
    if not _obj(value, path, errors, ("x_sp", "y_sp", "width_sp", "height_sp")):
        return
    for key in ("x_sp", "y_sp"):
        if key in value:
            _sp(value[key], f"{path}.{key}", errors)
    for key in ("width_sp", "height_sp"):
        if key in value:
            _sp(value[key], f"{path}.{key}", errors, positive=True)


def _point(value, path, errors):
    if _obj(value, path, errors, ("x_sp", "y_sp")):
        for key in ("x_sp", "y_sp"):
            if key in value:
                _sp(value[key], f"{path}.{key}", errors)


def _unique(records, key, path, errors, internal=False):
    seen = set()
    for i, record in enumerate(_list(records, path, errors)):
        if not isinstance(record, dict):
            errors.append(f"{path}[{i}]: expected object")
            continue
        value = record.get(key)
        if internal is not None:
            _id(value, f"{path}[{i}].{key}", errors, internal)
        if isinstance(value, str) and value in seen:
            errors.append(f"{path}[{i}].{key}: duplicate {value}")
        if isinstance(value, str):
            seen.add(value)


def _indices(records, path, errors, unique=True):
    seen = set()
    for i, record in enumerate(_list(records, path, errors)):
        if isinstance(record, dict):
            index = record.get("index")
            if type(index) is not int or index < 1:
                errors.append(f"{path}[{i}].index: expected positive declaration index")
            elif unique and index in seen:
                errors.append(f"{path}[{i}].index: duplicate declaration index")
            seen.add(index)


def _refs(values, allowed, path, errors):
    for i, value in enumerate(_list(values, path, errors)):
        if not isinstance(value, str) or value not in allowed:
            errors.append(f"{path}[{i}]: unknown ID {value}")


def _constraint(value, path, errors):
    if not _obj(value, path, errors, ("id", "kind", "target_ids", "value", "strength", "source")):
        return
    _id(value.get("id"), f"{path}.id", errors, True)
    _string(value.get("kind"), f"{path}.kind", errors)
    _list(value.get("target_ids"), f"{path}.target_ids", errors)
    _enum(value.get("strength"), {"hard", "strong", "weak"}, f"{path}.strength", errors)
    source = value.get("source")
    if _obj(source, f"{path}.source", errors, ("command", "declaration_index")):
        _string(source.get("command"), f"{path}.source.command", errors)
        _sp(source.get("declaration_index"), f"{path}.source.declaration_index", errors, True)


def _diagnostic(value, path, errors):
    if not _obj(value, path, errors, ("code", "severity", "object_ids", "constraint_ids", "message", "suggested_actions")):
        return
    _string(value.get("code"), f"{path}.code", errors)
    _enum(value.get("severity"), {"error", "warning", "info"}, f"{path}.severity", errors)
    for key in ("object_ids", "constraint_ids", "suggested_actions"):
        for i, item in enumerate(_list(value.get(key), f"{path}.{key}", errors)):
            _string(item, f"{path}.{key}[{i}]", errors)
    _string(value.get("message"), f"{path}.message", errors)


def _spec(value, errors):
    keys = ("environment_id", "nodes", "flows", "branches", "joins", "structures", "annotations", "constraints", "options")
    if not _obj(value, "Spec", errors, keys):
        return
    _string(value.get("environment_id"), "Spec.environment_id", errors)
    nodes = _list(value.get("nodes"), "Spec.nodes", errors)
    flows = _list(value.get("flows"), "Spec.flows", errors)
    _unique(nodes, "id", "Spec.nodes", errors, None)
    _unique(flows, "id", "Spec.flows", errors, "flow")
    node_ids = {x.get("id") for x in nodes if isinstance(x, dict) and isinstance(x.get("id"), str)}
    flow_ids = {x.get("id") for x in flows if isinstance(x, dict) and isinstance(x.get("id"), str)}
    for key in ("nodes", "flows", "structures", "annotations"):
        records = _list(value.get(key), f"Spec.{key}", errors)
        _indices(records, f"Spec.{key}", errors, unique=key != "flows")
    for i, node in enumerate(nodes):
        p = f"Spec.nodes[{i}]"
        if not _obj(node, p, errors, ("id", "index", "kind")):
            continue
        _enum(node.get("kind"), {"function", "start", "finish", "split", "join"}, p + ".kind", errors)
        kind = node.get("kind")
        _id(node.get("id"), p + ".id", errors, "branch" if kind == "split" else "join" if kind == "join" else False)
        if node.get("kind") in ("split", "join"):
            _enum(node.get("logic"), {"and", "or"}, p + ".logic", errors)
        elif "logic" in node:
            errors.append(p + ".logic: only split/join nodes have logic")
        if "text_ref" in node:
            _id(node["text_ref"], p + ".text_ref", errors, True)
    for i, flow in enumerate(flows):
        p = f"Spec.flows[{i}]"
        if not _obj(flow, p, errors, ("id", "index", "source", "target", "kind")):
            continue
        _enum(flow.get("kind"), {"forward", "feedback"}, p + ".kind", errors)
        for endpoint in ("source", "target"):
            if not isinstance(flow.get(endpoint), str) or flow.get(endpoint) not in node_ids:
                errors.append(f"{p}.{endpoint}: unknown node")
        if "condition_ref" in flow:
            _id(flow["condition_ref"], p + ".condition_ref", errors, True)
    for key in ("branches", "joins"):
        records = _list(value.get(key), f"Spec.{key}", errors)
        _unique(records, "connector_id", f"Spec.{key}", errors, "branch" if key == "branches" else "join")
        for i, record in enumerate(records):
            p = f"Spec.{key}[{i}]"
            if not _obj(record, p, errors, ("connector_id", "arm_flow_ids_in_user_order", "source_id" if key == "branches" else "target_id")):
                continue
            expected_kind = "split" if key == "branches" else "join"
            matching_ids = {node.get("id") for node in nodes if isinstance(node, dict) and node.get("kind") == expected_kind and isinstance(node.get("id"), str)}
            if not isinstance(record.get("connector_id"), str) or record.get("connector_id") not in matching_ids:
                errors.append(p + ".connector_id: unknown node")
            endpoint = "source_id" if key == "branches" else "target_id"
            if not isinstance(record.get(endpoint), str) or record.get(endpoint) not in node_ids:
                errors.append(f"{p}.{endpoint}: unknown node")
            _refs(record.get("arm_flow_ids_in_user_order"), flow_ids, p + ".arm_flow_ids_in_user_order", errors)
    for key in ("structures", "annotations"):
        _unique(value.get(key), "id", f"Spec.{key}", errors)
    for i, structure in enumerate(_list(value.get("structures"), "Spec.structures", errors)):
        p = f"Spec.structures[{i}]"
        if not _obj(structure, p, errors, ("id", "index", "member_ids", "style", "input_member_ids", "output_member_ids")):
            continue
        members = structure.get("member_ids")
        _refs(members, node_ids, p + ".member_ids", errors)
        for key in ("input_member_ids", "output_member_ids"):
            member_ids = {member for member in members if isinstance(member, str)} if isinstance(members, list) else set()
            _refs(structure.get(key), member_ids, p + "." + key, errors)
    for i, note in enumerate(_list(value.get("annotations"), "Spec.annotations", errors)):
        p = f"Spec.annotations[{i}]"
        if not _obj(note, p, errors, ("id", "index", "owner_id", "type_ref", "body_ref")):
            continue
        if not isinstance(note.get("owner_id"), str) or note.get("owner_id") not in node_ids:
            errors.append(p + ".owner_id: unknown node")
        for key in ("type_ref", "body_ref"):
            _id(note.get(key), p + "." + key, errors, True)
        if "preferred_position" in note:
            _enum(note["preferred_position"], POSITIONS, p + ".preferred_position", errors)
        if "position_strength" in note:
            _enum(note["position_strength"], {"hard", "soft"}, p + ".position_strength", errors)
    for i, item in enumerate(_list(value.get("constraints"), "Spec.constraints", errors)):
        _constraint(item, f"Spec.constraints[{i}]", errors)
    options = value.get("options")
    if _obj(options, "Spec.options", errors, ("direction", "scale", "multipage")):
        _enum(options.get("direction"), {"right", "down"}, "Spec.options.direction", errors)
        _number(options.get("scale"), "Spec.options.scale", errors, True)
        if type(options.get("multipage")) is not bool:
            errors.append("Spec.options.multipage: expected boolean")


def _metrics(value, errors):
    if not _obj(value, "Metrics", errors, ("environment_id", "by_text_ref", "by_node_id", "by_annotation_id", "by_structure_id", "style_clearances")):
        return
    _string(value.get("environment_id"), "Metrics.environment_id", errors)
    for key, required in (("by_text_ref", ("width_sp", "height_sp")),
                          ("by_node_id", ("width_sp", "height_sp")),
                          ("by_annotation_id", ("width_sp", "height_sp")),
                          ("by_structure_id", ("header_width_sp", "header_height_sp"))):
        records = value.get(key)
        if not isinstance(records, dict):
            errors.append(f"Metrics.{key}: expected object")
            continue
        for ident, dimensions in records.items():
            p = f"Metrics.{key}.{ident}"
            if key == "by_node_id":
                _node_id(ident, p, errors)
            else:
                _id(ident, p, errors, key == "by_text_ref")
            if _obj(dimensions, p, errors, required):
                for field, dimension in dimensions.items():
                    if field.endswith("_sp"):
                        _sp(dimension, f"{p}.{field}", errors, field != "depth_sp")
    clearances = value.get("style_clearances")
    if isinstance(clearances, dict):
        for key, dimension in clearances.items():
            _sp(dimension, f"Metrics.style_clearances.{key}", errors)
    else:
        errors.append("Metrics.style_clearances: expected object")


def _frame(value, errors):
    if not _obj(value, "Frame", errors, ("environment_id", "page_width_sp", "page_height_sp", "content_width_sp", "content_height_sp", "direction", "scale")):
        return
    _string(value.get("environment_id"), "Frame.environment_id", errors)
    for key in ("page_width_sp", "page_height_sp", "content_width_sp", "content_height_sp"):
        _sp(value.get(key), f"Frame.{key}", errors, True)
    _enum(value.get("direction"), {"right", "down"}, "Frame.direction", errors)
    _number(value.get("scale"), "Frame.scale", errors, True)
    for axis in ("width", "height"):
        page, content = value.get(f"page_{axis}_sp"), value.get(f"content_{axis}_sp")
        if type(page) is int and type(content) is int and content > page:
            errors.append(f"Frame.content_{axis}_sp: exceeds page")


def _regions(value, errors):
    if not _obj(value, "Regions", errors, ("environment_id", "root", "regions_by_id", "fallback_subgraphs", "ambiguities")):
        return
    _string(value.get("environment_id"), "Regions.environment_id", errors)
    regions = value.get("regions_by_id")
    if not isinstance(regions, dict):
        errors.append("Regions.regions_by_id: expected object")
        return
    if not isinstance(value.get("root"), str) or value.get("root") not in regions:
        errors.append("Regions.root: unknown region")
    for ident, region in regions.items():
        p = f"Regions.regions_by_id.{ident}"
        _id(ident, p, errors, True)
        if _obj(region, p, errors, ("id", "kind", "ordered_children", "member_ids", "can_keep_together")):
            if region.get("id") != ident:
                errors.append(p + ".id: map key mismatch")
            _enum(region.get("kind"), {"sequence", "parallel", "group", "generic"}, p + ".kind", errors)
            _list(region.get("ordered_children"), p + ".ordered_children", errors)
            _list(region.get("member_ids"), p + ".member_ids", errors)
            if type(region.get("can_keep_together")) is not bool:
                errors.append(p + ".can_keep_together: expected boolean")
    for key in ("fallback_subgraphs", "ambiguities"):
        _list(value.get(key), f"Regions.{key}", errors)


def _plan(value, errors):
    if not _obj(value, "Plan", errors, ("environment_id", "pages", "estimated_costs")):
        return
    _string(value.get("environment_id"), "Plan.environment_id", errors)
    for i, page in enumerate(_list(value.get("pages"), "Plan.pages", errors)):
        p = f"Plan.pages[{i}]"
        if not _obj(page, p, errors, ("rows", "continuation_ids")):
            continue
        _list(page.get("continuation_ids"), p + ".continuation_ids", errors)
        for j, row in enumerate(_list(page.get("rows"), p + ".rows", errors)):
            q = f"{p}.rows[{j}]"
            if _obj(row, q, errors, ("index", "direction_sign", "ordered_region_ids", "ordered_node_ids", "forced_break_ids")):
                _sp(row.get("index"), q + ".index", errors)
                _enum(row.get("direction_sign"), {-1, 1}, q + ".direction_sign", errors)
                for key in ("ordered_region_ids", "ordered_node_ids", "forced_break_ids"):
                    _list(row.get(key), q + "." + key, errors)
    if not isinstance(value.get("estimated_costs"), dict):
        errors.append("Plan.estimated_costs: expected object")


def _geometry(value, errors):
    if not _obj(value, "Geometry", errors, ("environment_id", "node_rects_by_id", "group_rects_by_id", "row_axes", "reserved_channels", "provisional_ports", "spacing_stats")):
        return
    _string(value.get("environment_id"), "Geometry.environment_id", errors)
    for key in ("node_rects_by_id", "group_rects_by_id"):
        records = value.get(key)
        if not isinstance(records, dict):
            errors.append(f"Geometry.{key}: expected object")
            continue
        for ident, rect in records.items():
            (_node_id if key == "node_rects_by_id" else _id)(ident, f"Geometry.{key}.{ident}", errors)
            _rect(rect, f"Geometry.{key}.{ident}", errors)
    for key in ("row_axes", "reserved_channels", "provisional_ports"):
        _list(value.get(key), f"Geometry.{key}", errors)
    if not isinstance(value.get("spacing_stats"), dict):
        errors.append("Geometry.spacing_stats: expected object")


def _path(value, path, errors):
    if not _obj(value, path, errors, ("source_port_id", "target_port_id", "points")):
        return
    for key in ("source_port_id", "target_port_id"):
        _id(value.get(key), path + "." + key, errors, True)
    points = _list(value.get("points"), path + ".points", errors)
    if len(points) < 2:
        errors.append(path + ".points: at least two points required")
    for i, point in enumerate(points):
        _point(point, f"{path}.points[{i}]", errors)
    for i, (a, b) in enumerate(zip(points, points[1:])):
        if all(isinstance(p, dict) and type(p.get(k)) is int for p in (a, b) for k in ("x_sp", "y_sp")):
            if (a["x_sp"] == b["x_sp"]) == (a["y_sp"] == b["y_sp"]):
                errors.append(f"{path}.points[{i + 1}]: segment must be nonzero and orthogonal")


def _routes(value, errors):
    if not _obj(value, "Routes", errors, ("environment_id", "paths_by_flow_id", "ports_by_id", "shared_trunks", "crossings", "congestion", "costs", "conflicts")):
        return
    _string(value.get("environment_id"), "Routes.environment_id", errors)
    paths = value.get("paths_by_flow_id")
    if isinstance(paths, dict):
        for ident, path in paths.items():
            _id(ident, f"Routes.paths_by_flow_id.{ident}", errors, True)
            _path(path, f"Routes.paths_by_flow_id.{ident}", errors)
    else:
        errors.append("Routes.paths_by_flow_id: expected object")
    ports = value.get("ports_by_id")
    if isinstance(ports, dict):
        for ident, port in ports.items():
            _id(ident, f"Routes.ports_by_id.{ident}", errors, True)
            _point(port, f"Routes.ports_by_id.{ident}", errors)
    else:
        errors.append("Routes.ports_by_id: expected object")
    for key in ("shared_trunks", "crossings", "congestion", "conflicts"):
        _list(value.get(key), f"Routes.{key}", errors)
    if not isinstance(value.get("costs"), dict):
        errors.append("Routes.costs: expected object")


def _scene(value, errors):
    if not _obj(value, "Scene", errors, ("environment_id", "pages", "quality", "diagnostics", "scale")):
        return
    _string(value.get("environment_id"), "Scene.environment_id", errors)
    _number(value.get("scale"), "Scene.scale", errors, True)
    quality = value.get("quality")
    if _obj(quality, "Scene.quality", errors, ("vector", "search_budget", "candidates_evaluated", "budget_exhausted")):
        vector = _list(quality.get("vector"), "Scene.quality.vector", errors)
        if len(vector) != 7:
            errors.append("Scene.quality.vector: expected seven ordered components")
        for i, component in enumerate(vector):
            _number(component, f"Scene.quality.vector[{i}]", errors)
            if type(component) in (int, float) and component < 0:
                errors.append(f"Scene.quality.vector[{i}]: expected nonnegative")
        if vector and vector[0] != 0:
            errors.append("Scene.quality.vector[0]: valid Scene must have zero hard violations")
        for key in ("search_budget", "candidates_evaluated"):
            _sp(quality.get(key), "Scene.quality." + key, errors, key == "search_budget")
        if type(quality.get("budget_exhausted")) is not bool:
            errors.append("Scene.quality.budget_exhausted: expected boolean")
    for i, diagnostic in enumerate(_list(value.get("diagnostics"), "Scene.diagnostics", errors)):
        _diagnostic(diagnostic, f"Scene.diagnostics[{i}]", errors)
    pages = _list(value.get("pages"), "Scene.pages", errors)
    if not pages:
        errors.append("Scene.pages: at least one page required")
    markers = {}
    for i, page in enumerate(pages):
        p = f"Scene.pages[{i}]"
        keys = ("node_rects", "structure_rects", "annotations", "flow_paths", "edge_labels", "continuation_markers", "bounding_rect")
        if not _obj(page, p, errors, keys):
            continue
        _rect(page.get("bounding_rect"), p + ".bounding_rect", errors)
        for key in ("node_rects", "structure_rects"):
            records = page.get(key)
            if not isinstance(records, dict):
                errors.append(f"{p}.{key}: expected object")
                continue
            for ident, rect in records.items():
                (_node_id if key == "node_rects" else _id)(ident, f"{p}.{key}.{ident}", errors)
                _rect(rect, f"{p}.{key}.{ident}", errors)
        for j, note in enumerate(_list(page.get("annotations"), p + ".annotations", errors)):
            q = f"{p}.annotations[{j}]"
            if _obj(note, q, errors, ("id", "owner_id", "position", "rect", "type_ref", "body_ref")):
                _id(note.get("id"), q + ".id", errors)
                _id(note.get("owner_id"), q + ".owner_id", errors)
                _enum(note.get("position"), POSITIONS, q + ".position", errors)
                _rect(note.get("rect"), q + ".rect", errors)
                for key in ("type_ref", "body_ref"):
                    _id(note.get(key), q + "." + key, errors, True)
        paths = page.get("flow_paths")
        if isinstance(paths, dict):
            for ident, path in paths.items():
                _id(ident, f"{p}.flow_paths.{ident}", errors, True)
                _path(path, f"{p}.flow_paths.{ident}", errors)
        else:
            errors.append(p + ".flow_paths: expected object")
        for j, label in enumerate(_list(page.get("edge_labels"), p + ".edge_labels", errors)):
            q = f"{p}.edge_labels[{j}]"
            if _obj(label, q, errors, ("flow_id", "text_ref", "rect")):
                _id(label.get("flow_id"), q + ".flow_id", errors, True)
                _id(label.get("text_ref"), q + ".text_ref", errors, True)
                _rect(label.get("rect"), q + ".rect", errors)
        for j, marker in enumerate(_list(page.get("continuation_markers"), p + ".continuation_markers", errors)):
            q = f"{p}.continuation_markers[{j}]"
            if _obj(marker, q, errors, ("id", "counterpart_id", "semantic_flow_id", "rect", "text_ref")):
                for key in ("id", "counterpart_id", "semantic_flow_id", "text_ref"):
                    _id(marker.get(key), q + "." + key, errors, True)
                _rect(marker.get("rect"), q + ".rect", errors)
                ident = marker.get("id")
                if isinstance(ident, str):
                    if ident in markers:
                        errors.append(f"{q}.id: duplicate continuation marker")
                    markers[ident] = (marker.get("counterpart_id"), i, marker.get("semantic_flow_id"))
    for ident, (other, page_index, flow_id) in markers.items():
        if not isinstance(other, str) or other not in markers or markers[other][0] != ident or markers[other][1] == page_index or markers[other][2] != flow_id:
            errors.append(f"Scene.continuation_markers.{ident}: missing reciprocal counterpart on another page")


VALIDATORS = {"Spec": _spec, "Metrics": _metrics, "Frame": _frame,
              "Constraint": lambda x, e: _constraint(x, "Constraint", e),
              "Diagnostic": lambda x, e: _diagnostic(x, "Diagnostic", e),
              "Regions": _regions, "Plan": _plan, "Geometry": _geometry,
              "Routes": _routes, "Scene": _scene}


def validate(kind, value):
    """Return path-qualified schema errors for a contract object."""
    if kind not in VALIDATORS:
        raise ValueError(f"unknown contract kind: {kind}")
    errors = []
    VALIDATORS[kind](value, errors)
    return errors


def validate_trace(trace):
    """Validate a trace envelope and reject environment mixing."""
    errors = []
    if not _obj(trace, "trace", errors, ("contract_version", "environment_id", "objects")):
        return errors
    if trace.get("contract_version") != 1:
        errors.append("trace.contract_version: expected 1")
    _string(trace.get("environment_id"), "trace.environment_id", errors)
    objects = trace.get("objects")
    if not isinstance(objects, dict):
        return errors + ["trace.objects: expected object"]
    for kind, value in objects.items():
        if kind not in VALIDATORS:
            errors.append(f"trace.objects.{kind}: unknown contract kind")
            continue
        errors.extend(validate(kind, value))
        if kind not in ("Constraint", "Diagnostic") and isinstance(value, dict):
            if value.get("environment_id") != trace.get("environment_id"):
                errors.append(f"trace.objects.{kind}.environment_id: environment mismatch")
    return errors


def canonical_trace(trace):
    """Serialize valid trace JSON deterministically, with no lossy floats."""
    errors = validate_trace(trace)
    if errors:
        raise ValueError("; ".join(errors))
    return json.dumps(trace, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False) + "\n"
