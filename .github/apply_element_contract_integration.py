from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new)


program_path = Path("godot/ride_program.gd")
program = program_path.read_text()
program = replace_once(
    program,
    '\t\t"role_spans": role_spans.role_spans,\n\t\t"propulsion_by_span": propulsion,\n',
    '\t\t"role_spans": role_spans.role_spans,\n'
    '\t\t"element_intents": material_element_intents(story.sequence),\n'
    '\t\t"propulsion_by_span": propulsion,\n',
    "compiled element-intent publication",
)
program = replace_once(
    program,
    '\n\n## Reconstruct which material role owns each authored span. Ownership must be total, ordered\n',
    '''

## One explicit geometry-intent record per material role. No role is allowed to disappear from
## geometry review merely because its contract has not been researched yet: an unadopted record
## publishes that absence honestly, while an adopted record will later carry the executable
## `ElementContract` intent. The current slice adopts none; the camelback is the first planned
## promotion after its geometry is rewritten.
static func material_element_intents(sequence: Array = MATERIAL_ROLE_IDS) -> Dictionary:
\tvar role_ids: Array = sequence if not sequence.is_empty() else MATERIAL_ROLE_IDS
\tvar records := {}
\tfor role_value in role_ids:
\t\tvar role_id := str(role_value)
\t\trecords[role_id] = {
\t\t\t"status": "unadopted",
\t\t\t"reason": "no reviewed whole-element geometry intent has been adopted",
\t\t\t"intent": {},
\t\t}
\treturn records


## Reconstruct which material role owns each authored span. Ownership must be total, ordered
''',
    "material element-intent function",
)
program_path.write_text(program)


contract_path = Path("godot/route_contract.gd")
contract = contract_path.read_text()
contract = replace_once(
    contract,
    'const Terrain := preload("res://terrain.gd")\n',
    'const Terrain := preload("res://terrain.gd")\n'
    'const ElementContract := preload("res://element_contract.gd")\n',
    "element-contract preload",
)
contract = replace_once(
    contract,
    '''\tfor index in count:
\t\tvar tangent: Vector3 = trajectory.tangent[index]
\t\tvar up: Vector3 = trajectory.rider_up[index]
\t\tvar right := tangent.cross(up).normalized()
\t\trights[index] = right
\t\tbanks[index] = _bank_degrees(tangent, up, banks[index - 1] if index > 0 else 0.0)

\tvar propulsion_ids := PackedInt32Array()
''',
    '''\tfor index in count:
\t\tvar tangent: Vector3 = trajectory.tangent[index]
\t\tvar up: Vector3 = trajectory.rider_up[index]
\t\tvar right := tangent.cross(up).normalized()
\t\trights[index] = right
\t\tbanks[index] = _bank_degrees(tangent, up, banks[index - 1] if index > 0 else 0.0)

\tvar element_contracts := _element_contract_records(plan, compiled, trajectory, banks)
\tif not element_contracts.ok:
\t\treturn {"ok": false, "errors": element_contracts.errors}

\tvar propulsion_ids := PackedInt32Array()
''',
    "production element-contract evaluation",
)
contract = replace_once(
    contract,
    '\t\t"dense_output": trajectory.dense_output,\n'
    '\t\t"generation_stats": compiled.generation_stats.duplicate(true),\n',
    '\t\t"dense_output": trajectory.dense_output,\n'
    '\t\t"element_contracts": element_contracts.records,\n'
    '\t\t"generation_stats": compiled.generation_stats.duplicate(true),\n',
    "route element-contract publication",
)
helper = r'''


## Measure every whole material role on the one accepted production trajectory. Unadopted roles
## are not judged, but they still publish their geometry so absence of a reviewed threshold cannot
## become absence of evidence. Adopted roles fail route construction on any contract violation.
static func _element_contract_records(
\tplan: Dictionary, compiled: Dictionary, trajectory: Dictionary,
\tbanks: PackedFloat32Array
) -> Dictionary:
\tvar errors := PackedStringArray()
\tvar intents_value: Variant = compiled.get("element_intents")
\tvar role_spans_value: Variant = compiled.get("role_spans")
\tif not intents_value is Dictionary:
\t\terrors.append("compiled program is missing element_intents")
\tif not role_spans_value is Dictionary:
\t\terrors.append("compiled program is missing role_spans for element contracts")
\tif not errors.is_empty():
\t\treturn {"ok": false, "records": {}, "errors": errors}
\tvar intents: Dictionary = intents_value
\tvar role_spans: Dictionary = role_spans_value
\tvar expected_ids := []
\tfor role_value in plan.get("roles", []):
\t\tif not role_value is Dictionary or str(role_value.get("id", "")).is_empty():
\t\t\terrors.append("plan contains a material role without an id")
\t\t\tcontinue
\t\texpected_ids.append(str(role_value.id))
\tvar actual_ids: Array = intents.keys()
\tactual_ids.sort()
\tvar sorted_expected := expected_ids.duplicate()
\tsorted_expected.sort()
\tif actual_ids != sorted_expected:
\t\terrors.append("element_intents must exactly cover the plan's material roles")
\tif not errors.is_empty():
\t\treturn {"ok": false, "records": {}, "errors": errors}

\tvar measured_route := {
\t\t"positions": trajectory.position_m,
\t\t"tangents": trajectory.tangent,
\t\t"banks": banks,
\t}
\tvar records := {}
\tfor role_id_value in expected_ids:
\t\tvar role_id := str(role_id_value)
\t\tvar intent_record_value: Variant = intents.get(role_id)
\t\tif not intent_record_value is Dictionary:
\t\t\terrors.append("element intent '%s' is not a Dictionary" % role_id)
\t\t\tcontinue
\t\tvar intent_record: Dictionary = intent_record_value
\t\tvar sample_bounds := _role_sample_bounds(role_spans, role_id, trajectory)
\t\tif sample_bounds.x < 0 or sample_bounds.y < sample_bounds.x:
\t\t\terrors.append("element '%s' has no whole-role sample bounds" % role_id)
\t\t\tcontinue
\t\tvar measurement := ElementContract.measure(
\t\t\tmeasured_route, sample_bounds.x, sample_bounds.y)
\t\tif measurement.get("status") != "measured":
\t\t\terrors.append("element '%s' could not be measured: %s" % [
\t\t\t\trole_id, str(measurement.get("reason", "unknown"))])
\t\t\tcontinue
\t\tvar status := str(intent_record.get("status", ""))
\t\tvar intent_value: Variant = intent_record.get("intent")
\t\tif status == "unadopted":
\t\t\tif not intent_value is Dictionary or not intent_value.is_empty():
\t\t\t\terrors.append("unadopted element '%s' carries a hidden intent" % role_id)
\t\t\t\tcontinue
\t\t\tvar reason := str(intent_record.get("reason", ""))
\t\t\tif reason.is_empty():
\t\t\t\terrors.append("unadopted element '%s' has no reason" % role_id)
\t\t\t\tcontinue
\t\t\trecords[role_id] = {
\t\t\t\t"status": "unadopted",
\t\t\t\t"reason": reason,
\t\t\t\t"intent": {},
\t\t\t\t"measurement": measurement,
\t\t\t\t"violations": PackedStringArray(),
\t\t\t}
\t\telif status == "adopted":
\t\t\tif not intent_value is Dictionary or intent_value.is_empty():
\t\t\t\terrors.append("adopted element '%s' has no executable intent" % role_id)
\t\t\t\tcontinue
\t\t\tvar violations := ElementContract.validate(intent_value, measurement)
\t\t\trecords[role_id] = {
\t\t\t\t"status": "adopted",
\t\t\t\t"reason": str(intent_record.get("reason", "")),
\t\t\t\t"intent": intent_value.duplicate(true),
\t\t\t\t"measurement": measurement,
\t\t\t\t"violations": violations,
\t\t\t}
\t\t\tfor violation in violations:
\t\t\t\terrors.append("element '%s' geometry contract: %s" % [role_id, violation])
\t\telse:
\t\t\terrors.append("element '%s' has invalid intent status '%s'" % [role_id, status])
\treturn {"ok": errors.is_empty(), "records": records, "errors": errors}
'''
contract = replace_once(
    contract,
    '\n\nstatic func _terrain_proofs(\n',
    helper + '\n\nstatic func _terrain_proofs(\n',
    "element-contract record helper",
)
contract_path.write_text(contract)
