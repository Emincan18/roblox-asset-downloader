"""Roblox-.mesh lesen und als OBJ und GLB schreiben.

.mesh ist Robloxs internes Format; weder Blender noch Studio können es öffnen. OBJ (nur Form, UVs, Normalen) und
GLB (zusätzlich Knochen und Gewichte) öffnen beide, Studio über Import 3D.

Unterstützt: 1.00/1.01 (Text), 2.00, 3.00/3.01, 4.00/4.01, 5.00, 6.00 (Chunks) und 7.00 (Draco, braucht DracoPy).
Nur die beste Detailstufe (LOD 0) wird exportiert. Nur Standardbibliothek, außer DracoPy für 7.00.
"""

import json
import re
import struct

ROOT = 0xFFFF


class MeshError(ValueError):
    pass


class Mesh:
    def __init__(self):
        self.positions = []  # (x, y, z)
        self.normals = []
        self.uvs = []  # (u, v) wie in Roblox: v = 0 oben im Bild
        self.faces = []  # (a, b, c)
        self.bones = []  # {"name", "parent", "matrix": [r00..r22, x, y, z]}
        self.joints = []  # pro Vertex 4 globale Knochen-Indizes
        self.weights = []  # pro Vertex 4 Gewichte, Summe 1
        self.version = ""


def _vertices(m, data, pos, count, size):
    for i in range(count):
        o = pos + i * size
        px, py, pz, nx, ny, nz, u, v = struct.unpack_from("<8f", data, o)
        m.positions.append((px, py, pz))
        m.normals.append((nx, ny, nz))
        m.uvs.append((u, v))
    return pos + count * size


def _faces(data, pos, count):
    return [struct.unpack_from("<3I", data, pos + i * 12) for i in range(count)], pos + count * 12


def _lod0(faces, lods):
    """Nur die Faces der besten Detailstufe; lods sind Face-Offsets."""
    if len(lods) >= 2 and 0 <= lods[0] < lods[1] <= len(faces):
        return faces[lods[0]:lods[1]]
    return faces


def _skinning(m, envelopes, bones_raw, names, subsets):
    """Knochen und pro Vertex globale Knochen-Indizes + Gewichte. Envelope-Indizes zeigen in die Knochenliste des Subsets."""
    for name_index, parent, _lod_parent, _culling, *matrix in bones_raw:
        end = names.find(b"\0", name_index)
        name = names[name_index:end if end >= 0 else len(names)].decode("utf-8", "replace") or f"Bone{len(m.bones)}"
        m.bones.append({"name": name, "parent": parent, "matrix": list(matrix)})
    owner = [None] * len(m.positions)
    for verts_begin, verts_length, bone_indices in subsets:
        for v in range(verts_begin, min(verts_begin + verts_length, len(owner))):
            owner[v] = bone_indices
    for v, (bones, weights) in enumerate(envelopes[:len(m.positions)]):
        table = owner[v] or list(range(len(m.bones)))
        joints, ws = [0, 0, 0, 0], [0.0, 0.0, 0.0, 0.0]
        for k in range(4):
            if weights[k] and bones[k] < len(table) and table[bones[k]] < len(m.bones):
                joints[k], ws[k] = table[bones[k]], weights[k] / 255
        total = sum(ws)
        m.joints.append(joints)
        m.weights.append([w / total for w in ws] if total else [1.0, 0.0, 0.0, 0.0])


def _read_bones(data, pos, count):
    return [struct.unpack_from("<IHHf12f", data, pos + i * 60) for i in range(count)], pos + count * 60


def _read_subsets(data, pos, count):
    out = []
    for i in range(count):
        _faces_begin, _faces_length, verts_begin, verts_length, n = struct.unpack_from("<5I", data, pos + i * 72)
        out.append((verts_begin, verts_length, list(struct.unpack_from("<26H", data, pos + i * 72 + 20))[:n]))
    return out, pos + count * 72


def _envelopes(data, pos, count):
    return [(data[pos + i * 8:pos + i * 8 + 4], data[pos + i * 8 + 4:pos + i * 8 + 8]) for i in range(count)], pos + count * 8


def _parse_v1(m, text, version):
    lines = text.splitlines()
    numbers = [float(x) for x in re.findall(r"-?[\d.]+(?:[eE][-+]?\d+)?", " ".join(lines[2:]))]
    scale = 0.5 if version == "1.00" else 1.0
    for i in range(0, len(numbers) - 8, 9):
        p, n, t = numbers[i:i + 3], numbers[i + 3:i + 6], numbers[i + 6:i + 9]
        m.positions.append((p[0] * scale, p[1] * scale, p[2] * scale))
        m.normals.append(tuple(n))
        m.uvs.append((t[0], 1 - t[1]))  # 1.x speichert V umgekehrt zu den Binärformaten
    m.faces = [(i, i + 1, i + 2) for i in range(0, len(m.positions) - 2, 3)]


def parse(data):
    """bytes einer .mesh -> Mesh. Wirft MeshError, wenn das Format unbekannt ist."""
    newline = data.find(b"\n")
    head = data[:newline if newline >= 0 else 16].decode("ascii", "replace").strip()
    if not head.startswith("version "):
        raise MeshError("Keine Roblox-.mesh-Datei")
    version = head[8:].strip()
    m = Mesh()
    m.version = version
    pos = newline + 1
    if version.startswith("1."):
        _parse_v1(m, data.decode("ascii", "replace"), version)
    elif version == "2.00":
        header_size, vsize, _fsize, nv, nf = struct.unpack_from("<HBBII", data, pos)
        pos = _vertices(m, data, pos + header_size, nv, vsize)
        m.faces, pos = _faces(data, pos, nf)
    elif version in ("3.00", "3.01"):
        header_size, vsize, _fsize, lod_size, nlods, nv, nf = struct.unpack_from("<HBBHHII", data, pos)
        pos = _vertices(m, data, pos + header_size, nv, vsize)
        faces, pos = _faces(data, pos, nf)
        lods = list(struct.unpack_from(f"<{nlods}I", data, pos)) if lod_size == 4 else []
        m.faces = _lod0(faces, lods)
    elif version in ("4.00", "4.01", "5.00"):
        (header_size, _lod_type, nv, nf, nlods, nbones, names_size, nsubsets,
         _hq, _unused) = struct.unpack_from("<HHIIHHIHBB", data, pos)
        pos = _vertices(m, data, pos + header_size, nv, 40)
        envelopes = []
        if nbones:
            envelopes, pos = _envelopes(data, pos, nv)
        faces, pos = _faces(data, pos, nf)
        lods = list(struct.unpack_from(f"<{nlods}I", data, pos))
        pos += nlods * 4
        m.faces = _lod0(faces, lods)
        bones, pos = _read_bones(data, pos, nbones)
        names = data[pos:pos + names_size]
        pos += names_size
        subsets, pos = _read_subsets(data, pos, nsubsets)
        if nbones:
            _skinning(m, envelopes, bones, names, subsets)
    elif version in ("6.00", "7.00"):
        _parse_chunks(m, data, pos)
    else:
        raise MeshError(f"Mesh-Version {version} wird noch nicht unterstützt")
    if not m.positions or not m.faces:
        raise MeshError("Mesh ist leer")
    return m


def _parse_chunks(m, data, pos):
    faces, lods, skin = [], [], None
    while pos + 16 <= len(data):
        kind = data[pos:pos + 8].rstrip(b"\0").decode("ascii", "replace")
        chunk_version, size = struct.unpack_from("<II", data, pos + 8)
        body, pos = data[pos + 16:pos + 16 + size], pos + 16 + size
        if kind == "COREMESH" and chunk_version == 1:
            nv = struct.unpack_from("<I", body, 0)[0]
            p = _vertices(m, body, 4, nv, 40)
            nf = struct.unpack_from("<I", body, p)[0]
            faces, _ = _faces(body, p + 4, nf)
        elif kind == "COREMESH" and chunk_version == 2:
            faces = _draco(m, body)
        elif kind == "LODS":
            n = struct.unpack_from("<I", body, 3)[0]
            lods = list(struct.unpack_from(f"<{n}I", body, 7))
        elif kind == "SKINNING":
            skin = body
    m.faces = _lod0(faces, lods)
    if skin:
        p = 0
        n_env = struct.unpack_from("<I", skin, p)[0]
        envelopes, p = _envelopes(skin, p + 4, n_env)
        n_bones = struct.unpack_from("<I", skin, p)[0]
        bones, p = _read_bones(skin, p + 4, n_bones)
        names_size = struct.unpack_from("<I", skin, p)[0]
        names = skin[p + 4:p + 4 + names_size]
        p += 4 + names_size
        n_subsets = struct.unpack_from("<I", skin, p)[0]
        subsets, p = _read_subsets(skin, p + 4, n_subsets)
        # Bei Draco kann sich die Vertex-Reihenfolge ändern; dann passen die Gewichte nicht mehr sicher.
        if n_bones and n_env == len(m.positions):
            _skinning(m, envelopes, bones, names, subsets)


def _draco(m, body):
    try:
        import DracoPy
    except ImportError as e:
        raise MeshError("Mesh-Version 7.00 ist Draco-komprimiert; dafür fehlt das Python-Paket DracoPy") from e
    start = body.find(b"DRACO")
    mesh = DracoPy.decode(body[start if start >= 0 else 0:])
    points = mesh.points.reshape(-1, 3).tolist()
    m.positions = [tuple(p) for p in points]
    normals = getattr(mesh, "normals", None)
    m.normals = [tuple(n) for n in normals.reshape(-1, 3).tolist()] if normals is not None and len(normals) else []
    uv = getattr(mesh, "tex_coord", None)
    m.uvs = [tuple(t) for t in uv.reshape(-1, 2).tolist()] if uv is not None and len(uv) else []
    return [tuple(f) for f in mesh.faces.reshape(-1, 3).tolist()]


def to_obj(m, name="mesh"):
    """OBJ-Text. OBJ zählt V von unten, Roblox von oben, deshalb 1 - v."""
    out = [f"# Aus Roblox-Mesh {m.version}", f"o {name}"]
    out += [f"v {x:.6f} {y:.6f} {z:.6f}" for x, y, z in m.positions]
    if m.uvs:
        out += [f"vt {u:.6f} {1 - v:.6f}" for u, v in m.uvs]
    if m.normals:
        out += [f"vn {x:.6f} {y:.6f} {z:.6f}" for x, y, z in m.normals]
    has_uv, has_n = bool(m.uvs), bool(m.normals)
    for face in m.faces:
        parts = []
        for i in face:
            k = i + 1
            parts.append(f"{k}/{k if has_uv else ''}/{k}" if has_n else (f"{k}/{k}" if has_uv else f"{k}"))
        out.append("f " + " ".join(parts))
    return "\n".join(out) + "\n"


def _matrix(r):
    """Roblox-CFrame (r00..r22, x, y, z) als 4x4-Zeilen."""
    return [[r[0], r[1], r[2], r[9]], [r[3], r[4], r[5], r[10]], [r[6], r[7], r[8], r[11]], [0.0, 0.0, 0.0, 1.0]]


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def _inverse(a):
    """Inverse einer 4x4-Matrix (Gauß-Jordan), auch wenn Knochen skaliert sind."""
    n = [row[:] + [1.0 if i == j else 0.0 for j in range(4)] for i, row in enumerate(a)]
    for c in range(4):
        p = max(range(c, 4), key=lambda r: abs(n[r][c]))
        n[c], n[p] = n[p], n[c]
        pivot = n[c][c] or 1e-12
        n[c] = [x / pivot for x in n[c]]
        for r in range(4):
            if r != c:
                f = n[r][c]
                n[r] = [x - f * y for x, y in zip(n[r], n[c])]
    return [row[4:] for row in n]


def _column_major(a):
    return [a[r][c] for c in range(4) for r in range(4)]


def to_glb(m, name="mesh"):
    """Binäres glTF 2.0. glTF zählt V wie Roblox von oben, also unverändert. Knochen als Node-Baum mit Skin."""
    blob = bytearray()
    views, accessors = [], []

    def add(raw, target=None):
        while len(blob) % 4:
            blob.append(0)
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw)}
        if target:
            view["target"] = target
        blob.extend(raw)
        views.append(view)
        return len(views) - 1

    def accessor(values, fmt, ctype, kind, target=None, minmax=False):
        flat = [x for v in values for x in (v if isinstance(v, (list, tuple)) else (v,))]
        acc = {"bufferView": add(struct.pack(f"<{len(flat)}{fmt}", *flat), target), "componentType": ctype,
               "count": len(values), "type": kind}
        if minmax:
            acc["min"] = [min(v[i] for v in values) for i in range(3)]
            acc["max"] = [max(v[i] for v in values) for i in range(3)]
        accessors.append(acc)
        return len(accessors) - 1

    attributes = {"POSITION": accessor(m.positions, "f", 5126, "VEC3", 34962, minmax=True)}
    if len(m.normals) == len(m.positions):
        attributes["NORMAL"] = accessor(m.normals, "f", 5126, "VEC3", 34962)
    if len(m.uvs) == len(m.positions):
        attributes["TEXCOORD_0"] = accessor(m.uvs, "f", 5126, "VEC2", 34962)
    skinned = bool(m.bones) and len(m.joints) == len(m.positions)
    if skinned:
        attributes["JOINTS_0"] = accessor(m.joints, "H", 5123, "VEC4", 34962)
        attributes["WEIGHTS_0"] = accessor(m.weights, "f", 5126, "VEC4", 34962)
    indices = accessor([i for f in m.faces for i in f], "I", 5125, "SCALAR", 34963)

    nodes = [{"name": name, "mesh": 0}]
    gltf = {"asset": {"version": "2.0", "generator": "roblox-asset-downloader"},
            "meshes": [{"name": name, "primitives": [{"attributes": attributes, "indices": indices}]}]}
    roots = [0]
    if skinned:
        world = [_matrix(b["matrix"]) for b in m.bones]
        first = len(nodes)
        for i, b in enumerate(m.bones):
            parent = b["parent"]
            local = world[i] if parent == ROOT or parent >= len(m.bones) else _mul(_inverse(world[parent]), world[i])
            nodes.append({"name": b["name"], "matrix": _column_major(local)})
        for i, b in enumerate(m.bones):
            parent = b["parent"]
            if parent == ROOT or parent >= len(m.bones):
                roots.append(first + i)
            else:
                nodes[first + parent].setdefault("children", []).append(first + i)
        ibm = accessor([_column_major(_inverse(w)) for w in world], "f", 5126, "MAT4")
        gltf["skins"] = [{"joints": list(range(first, first + len(m.bones))), "inverseBindMatrices": ibm}]
        nodes[0]["skin"] = 0
    gltf.update({"scene": 0, "scenes": [{"nodes": roots}], "nodes": nodes, "accessors": accessors,
                 "bufferViews": views, "buffers": [{"byteLength": len(blob)}]})
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    blob += b"\0" * (-len(blob) % 4)
    total = 12 + 8 + len(js) + 8 + len(blob)
    return (struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js
            + struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


def convert(data, name="mesh"):
    """bytes einer .mesh -> (obj_text, glb_bytes)."""
    m = parse(data)
    return to_obj(m, name), to_glb(m, name)


def extra_files(data, file_name):
    """Zu einer heruntergeladenen .mesh die Dateien für Blender und Studio: [(name.obj, bytes), (name.glb, bytes)].
    Leer, wenn es kein Mesh ist oder die Umwandlung nicht klappt; dann bleibt einfach nur die .mesh."""
    if not data.startswith(b"version "):
        return []
    stem = file_name.rsplit(".", 1)[0]
    try:
        obj, glb = convert(data, stem)
    except Exception:  # unbekannte Version oder fehlendes DracoPy: die .mesh reicht dann
        return []
    return [(stem + ".obj", obj.encode()), (stem + ".glb", glb)]
