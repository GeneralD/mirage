#!/usr/bin/env python3
"""usage: splice.py <ARCHITECTURE.md> <section-head.md> <area-diagrams.md>

Replaces the "## Module Dependency Graph" section (up to "## Frame Path") with the head and the diagrams.
"""
import sys

doc_path, head_path, body_path = sys.argv[1:4]
doc = open(doc_path, encoding="utf-8").read()
start = doc.index("## Module Dependency Graph\n")
end = doc.index("## Frame Path\n")
new = open(head_path, encoding="utf-8").read().rstrip("\n") + "\n\n" + open(body_path, encoding="utf-8").read()
open(doc_path, "w", encoding="utf-8").write(doc[:start] + new + doc[end:])
print(f"replaced {doc[start:end].count(chr(10))} lines with {new.count(chr(10))}")
