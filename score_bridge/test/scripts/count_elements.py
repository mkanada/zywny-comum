#!/usr/bin/env python3
"""Conta nós/formas/usos-de-glifo/runs-de-texto de um scene.json.

Usado pelo teste de ida-e-volta de R01 (score_bridge/test/roundtrip_count_test.dart)
para comparar, sobre o mesmo `scene.json`, a contagem obtida por este script
(implementação de referência, independente do parser Dart) contra a contagem
obtida pelo parser Dart (`VsbDocument`/`ScenePage`).

Uso: count_elements.py <arquivo.vsb ou scene.json ou single.json>
Saída: um objeto JSON de uma linha em stdout com as contagens.
"""
import json
import sys
import zipfile


def load_scene_document(path):
    if path.endswith(".vsb"):
        with zipfile.ZipFile(path) as zf:
            with zf.open("scene.json") as f:
                return json.load(f)
    with open(path, "r", encoding="utf-8") as f:
        doc = json.load(f)
    # Aceita tanto scene.json isolado ({"pages": [...]})
    # quanto o JSON único (-t vsb-json, {"scene": {"pages": [...]}, ...}).
    if "pages" in doc:
        return doc
    return doc["scene"]


def count(scene_document):
    counts = {
        "nodes": 0,
        "paths": 0,
        "rects": 0,
        "ellipses": 0,
        "glyphUses": 0,
        "textRuns": 0,
    }

    def walk(node):
        counts["nodes"] += 1
        for child in node.get("children", []):
            t = child.get("t")
            if t == "g":
                walk(child)
            elif t == "p":
                counts["paths"] += 1
            elif t == "r":
                counts["rects"] += 1
            elif t == "e":
                counts["ellipses"] += 1
            elif t == "u":
                counts["glyphUses"] += 1
            elif t == "t":
                counts["textRuns"] += 1
            else:
                raise ValueError("tipo de elemento desconhecido: %r" % (t,))

    for page in scene_document["pages"]:
        walk(page["root"])

    return counts


def main():
    if len(sys.argv) != 2:
        print("uso: count_elements.py <arquivo>", file=sys.stderr)
        sys.exit(2)
    scene_document = load_scene_document(sys.argv[1])
    print(json.dumps(count(scene_document)))


if __name__ == "__main__":
    main()
