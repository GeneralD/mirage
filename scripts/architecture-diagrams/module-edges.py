#!/usr/bin/env python3
"""Inventory of mirage's module edges for the architecture diagrams.

usage: module-edges.py <repo root> <dump-package.json> <out.json>

- compile: target -> its target dependencies (Package.swift, via `swift package dump-package`)
- resolve: module -> the modules whose live values its `@Dependency(\\.key)` resolutions reach
  (key -> Key type in Domain -> liveValue in a DI target -> the module that defines that type);
  a key with no live registration of ours (swift-dependencies' `continuousClock`) stays a key
- registers: DI target -> the modules whose types it registers as live values
- kinds: module -> the port kinds (the `Sources/Domain/<Kind>/` directory of the key) its live values serve,
  which places a module with no layer suffix (an Ambient live, `AppDirectories`, `RandomSource`) in its column
- pinned: [module, target] for each resolution of a key the AMBIENT list of
  `scripts/check-dependency-keypaths.sh` gives to named owners only; the diagrams draw those red
"""
import json
import pathlib
import re
import sys

root, dump_path, out_path = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
sources = root / "Sources"
modules = sorted(p.name for p in sources.iterdir() if p.is_dir())


def swift_files(module):
    return sorted((sources / module).rglob("*.swift"))


def code_lines(path):
    """The file's lines with `//` comments dropped (good enough for an inventory: no key is spelled in a string)."""
    return [re.sub(r"//.*$", "", line) for line in path.read_text(encoding="utf-8").splitlines()]


# key -> Key type: `public var key: any P { get { self[PKey.self] } ... }`, across Sources/Domain; and the
# Key type -> the kind its file sits under (a file at the root of Domain declares no port).
key_type = {}
ktype_kind = {}
for path in (sources / "Domain").rglob("*.swift"):
    text = "\n".join(code_lines(path))
    parts = path.relative_to(sources / "Domain").parts
    for key, ktype in re.findall(r"var\s+(\w+)\s*:[^{]*\{\s*get\s*\{\s*self\[(\w+)\.self\]", text):
        key_type[key] = ktype
        if len(parts) > 1:
            ktype_kind[ktype] = parts[0]

# AMBIENT: `<key> <owners>` lines; `*` is every module, anything else pins the key to its owners.
lint = (root / "scripts" / "check-dependency-keypaths.sh").read_text(encoding="utf-8")
ambient_block = re.search(r"^AMBIENT='\n(.*?)^'", lint, re.S | re.M)
if not ambient_block:
    raise SystemExit("no AMBIENT list in scripts/check-dependency-keypaths.sh")
pinned_keys = {line.split()[0] for line in ambient_block.group(1).splitlines() if line.split() and line.split()[1] != "*"}

# type -> defining module.
type_module = {}
for module in modules:
    for path in swift_files(module):
        for name in re.findall(r"\b(?:final\s+class|class|struct|actor|enum)\s+(\w+)", "\n".join(code_lines(path))):
            type_module.setdefault(name, module)

# Key type -> live implementation type, and DI target -> registered modules.
di_targets = [m for m in modules if m.endswith("DependencyInjection")]
key_impl = {}
registers = {}
kinds = {}
for di in di_targets:
    regs = set()
    for path in swift_files(di):
        text = "\n".join(code_lines(path))
        # A live value held in a shared constant (`private let liveFrameExecutor = FrameExecutorImpl()`).
        constants = dict(re.findall(r"\blet\s+(\w+)\s*=\s*(\w+)\s*\(", text))
        for ktype, body in re.findall(r"extension\s+(\w+)\s*:\s*DependencyKey\s*\{(.*?)\n\}", text, re.S):
            impl = (
                re.search(r"liveValue[^=]*=\s*(\w+)\s*[\(.]", body)
                or re.search(r"liveValue[^{]*\{\s*(\w+)\s*\(", body)
                or re.search(r"liveValue[^=]*=\s*(\w+)\s*$", body, re.M)
            )
            if impl:
                name = constants.get(impl.group(1), impl.group(1))
                key_impl.setdefault(ktype, (name, di))
                regs.add(type_module.get(name, "?" + name))
                if name in type_module and ktype in ktype_kind:
                    kinds.setdefault(type_module[name], set()).add(ktype_kind[ktype])
    registers[di] = sorted(regs)

# module -> resolved keys -> target modules.
pattern = re.compile(r"\bDependency(?:<[^>]*>)?(?:\.init)?\(\s*\\\.(\w+)\s*\)")
resolve = {}
unresolved = {}
pinned = set()
for module in modules:
    targets = set()
    for path in swift_files(module):
        for key in pattern.findall("\n".join(code_lines(path))):
            ktype = key_type.get(key)
            impl = key_impl.get(ktype) if ktype else None
            if impl and impl[0] in type_module:
                targets.add(type_module[impl[0]])
                if key in pinned_keys:
                    pinned.add((module, type_module[impl[0]]))
            else:
                targets.add("key:" + key)
                unresolved.setdefault(key, ktype)
    if targets:
        resolve[module] = sorted(targets)

dump = json.load(open(dump_path, encoding="utf-8"))
compile_deps = {}
for target in dump["targets"]:
    if target["type"] == "test":
        continue
    deps = []
    for dep in target.get("dependencies", []):
        if "byName" in dep:
            deps.append(dep["byName"][0])
        elif "target" in dep:
            deps.append(dep["target"][0])
        elif "product" in dep:
            deps.append("product:" + dep["product"][0])
    compile_deps[target["name"]] = sorted(deps)

json.dump(
    {"modules": modules, "compile": compile_deps, "resolve": resolve, "registers": registers, "unresolvedKeys": unresolved,
     "kinds": {m: sorted(k) for m, k in kinds.items()}, "pinned": sorted(list(p) for p in pinned)},
    open(out_path, "w", encoding="utf-8"),
    indent=1,
    sort_keys=True,
)
print(f"modules={len(modules)} compile={len(compile_deps)} resolving={len(resolve)} unresolved keys={sorted(unresolved)}")
