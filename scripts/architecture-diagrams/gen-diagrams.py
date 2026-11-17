#!/usr/bin/env python3
"""Generates the module diagrams of docs/ARCHITECTURE.md -> "Module Dependency Graph" from module-edges.json.

usage: gen-diagrams.py <module-edges.json> <out.md>

Per-area module diagrams: each area owns its member modules and draws every resolution its members
make (UnifiedLog and the clock left out); a target owned elsewhere gets a dashed border. A module may be
a member of two areas only when each of them names the targets it draws for it (`ONLY`), so that the
Interactors the frame path starts appear in both of its diagrams. An edge is red when it leaves its
lane (a per-key exception of the key-path lint) or resolves an Ambient key the lint's AMBIENT list pins
to its owners. The script exits non-zero unless every module is drawn, every area resolution is drawn
exactly once, the DI registrations cover every implementation module once, and the Layer Overview's
lanes cover every resolution and compile edge in the data.
"""
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
resolve, compile_deps, registers = data["resolve"], data["compile"], data["registers"]
modules, kinds, pinned = data["modules"], data["kinds"], {tuple(p) for p in data["pinned"]}
SKIPPED = {"UnifiedLog", "key:continuousClock"}
# A module with no layer suffix takes the column of the port kind its live values serve.
KIND_LAYER = {"Ambient": "amb", "Gateway": "gw"}
ENTRY = {"App", "ExtensionApp", "DevHarness", "LensTool", "ViewGallery"}


def layer(module):
    if module in ENTRY:
        return "entry"
    if module in {"AppRouter", "Views"}:
        return "view"
    if module == "Presenters":
        return "pres"
    if module.endswith("DependencyInjection"):
        return "di"
    for suffix, name in (("Interactor", "int"), ("UseCase", "uc"), ("Repository", "repo"),
                         ("DataSource", "ds"), ("DataStore", "ds"), ("Gateway", "gw")):
        if module.endswith(suffix):
            return name
    served = {KIND_LAYER.get(k) for k in kinds.get(module, [])}
    if len(served) == 1 and None not in served:
        return served.pop()
    if served:
        fail(f"{module} serves ports of more than one kind, or of a kind with no column: {kinds[module]}")
    return "core"


LAYER_TITLE = {"entry": "Entry", "view": "View / Router", "pres": "Presenter", "di": "Dependency injection",
               "int": "Interactor", "uc": "UseCase", "repo": "Repository", "ds": "DataSource / DataStore",
               "gw": "Gateway (OS boundary)", "amb": "Ambient"}
# lyra's palette: one saturated fill per layer under white text, and a gold border on the modules outside the
# implementation chain that other lanes compile against (Presenters, the DI targets, Domain, Entity).
GOLD = "stroke:#E9B84C,stroke-width:3px"
STYLE = {
    "entry": ("#4c78a8", ""), "view": ("#6a5", ""), "pres": ("#6a5", GOLD), "di": ("#c44", GOLD),
    "int": ("#7b5", ""), "uc": ("#59c", ""), "repo": ("#86c", ""), "ds": ("#c84", ""), "dstore": ("#a75", ""),
    "gw": ("#678", ""), "amb": ("#d57", ""),
}
ORDER = ["entry", "view", "pres", "int", "uc", "repo", "ds", "gw", "amb"]
# The kinds each lane may resolve; anything else is a per-key exception, drawn red. A copy of
# `allowed_kinds` in scripts/check-dependency-keypaths.sh (lane names as layer ids): change both together.
ALLOWED = {"entry": {"int", "amb"}, "view": {"pres", "amb"}, "pres": {"int", "amb"}, "int": {"uc", "amb"},
           "uc": {"repo", "amb"}, "repo": {"ds", "amb"}, "ds": {"gw", "amb"}}
EXCEPTION = "stroke:#d32f2f,stroke-width:2px"
# A label leaves out the layer suffix its column already names; the node id keeps the module name.
SUFFIX = {"int": "Interactor", "uc": "UseCase", "repo": "Repository", "ds": "DataSource", "gw": "Gateway"}


def label(module):
    suffix = SUFFIX.get(layer(module), "")
    return module.removesuffix(suffix) if suffix and module.endswith(suffix) else module

# (diagram id, title, summary, members); a member drawn in two areas has its targets split by ONLY.
AREAS = [
    ("Area0a", "Frame path: capture", "The host's camera ingestion path: device authorization, stream configuration, and camera frames feeding into the repository and surface pool.", [
        "CameraInteractor", "HarnessInteractor",
        "CameraControlUseCase",
        "CameraRepository",
        "CameraDataSource", "CameraPermissionDataSource",
        "AVFoundationGateway",
    ]),
    ("Area0b", "Frame path: pipeline, preview and transport", "The host's frame processing and delivery path: frames through the pipeline, rendered onto surfaces, and delivered to the preview window and the virtual camera transport. Red edges mark architectural keypath lint exceptions (`FramePipelineUseCase` on `DispatchExecutorGateway`, `PreviewDataSource` on `SurfacePoolDataSource`).", [
        "CameraInteractor", "HarnessInteractor",
        "FramePipelineUseCase",
        "PreviewRepository", "VirtualCameraRepository", "SurfaceRepository",
        "PreviewDataSource", "FrameTransportDataSource", "SurfacePoolDataSource",
        "MetalKitPreviewGateway", "IOSurfaceGateway", "MachGateway",
    ]),
    ("Area1", "Frame path: effect runtime", "The effect the pipeline runs on each frame: compiled shaders, per-effect state, and one command buffer per effect.", [
        "EffectRuntimeRepository",
        "GPURenderDataSource", "ShaderCompilationDataSource", "BundledEffectDataSource", "EffectRuntimeStateDataSource",
        "MetalGateway", "DispatchExecutorGateway", "RandomSource",
    ]),
    ("Area2", "Effects: catalog and authoring", "The effect catalog behind the Effects menu, `.lens` packages on disk, and the still-image render of the authoring tool.", [
        "EffectInteractor", "EffectAuthoringInteractor",
        "EffectCatalogUseCase", "EffectAuthoringUseCase",
        "EffectPackageRepository", "StillImageRepository",
        "EffectPackageDataSource", "EffectWatchDataSource", "StillImageDataSource",
        "FileSystemGateway", "FileWatchGateway", "WorkspaceGateway", "ImageIOGateway", "AppDirectories",
    ]),
    ("Area3", "App services: controls, settings, onboarding, support", "The controls, the settings, the onboarding flow with the extension install, and the support log.", [
        "ControlsInteractor", "SettingsInteractor", "OnboardingInteractor",
        "SettingsUseCase", "ExtensionInstallUseCase", "SupportLogUseCase",
        "SettingsRepository", "ExtensionInstallRepository", "SupportLogRepository",
        "HotkeyDataSource", "LoginItemDataSource", "PreferencesDataStore", "StoreMaintenanceDataStore",
        "ExtensionInstallDataSource", "SupportLogDataSource",
        "HotkeyGateway", "LoginItemGateway", "UserDefaultsGateway", "SystemExtensionGateway", "LogStoreGateway",
        "HostEnvironment",
    ]),
    ("Area4", "Extension process", "The Camera Extension: frames received over Mach and served as the CMIO stream.", [
        "ExtensionApp", "ExtensionRelayUseCase",
        "FrameReceiverRepository", "StreamOutputRepository",
        "FrameReceiverDataSource", "StreamOutputDataSource",
        "CMIOExtensionGateway", "HostTime",
    ]),
]
# Area id -> member -> the only targets that area draws for the member.
ONLY = {
    "Area0a": {"CameraInteractor": {"CameraControlUseCase", "ExtensionInstallUseCase"}, "HarnessInteractor": {"CameraControlUseCase"}},
    "Area0b": {"CameraInteractor": {"FramePipelineUseCase"}, "HarnessInteractor": {"FramePipelineUseCase"}},
}
ENTRY_MEMBERS = ["App", "DevHarness", "LensTool", "ViewGallery", "ExtensionApp", "AppRouter", "Views", "Presenters",
                 "StandardStreams"]
DI = ["HostDependencyInjection", "ExtensionDependencyInjection", "CommonDependencyInjection"]


def fail(message):
    raise SystemExit(message)


owner = {}
for area, _, _, members in AREAS:
    for m in members:
        if m in owner and not (m in ONLY.get(area, {}) and m in ONLY.get(owner[m], {})):
            fail(f"{m} is in two areas without ONLY in both")
        owner[m] = area
undrawn = [m for m in modules if m not in owner and m not in ENTRY_MEMBERS and m not in DI
           and m not in {"UnifiedLog", "Domain", "Entity"}]
if undrawn:
    fail(f"modules in no diagram: {undrawn}")
# The other direction: a member that is no module any more (deleted or renamed) would be drawn as a phantom node.
gone = sorted(m for m in [*owner, *ENTRY_MEMBERS, *DI, *(m for area in ONLY.values() for m in area)] if m not in modules)
if gone:
    fail(f"diagram members that are no module under Sources/: {gone}")


def kind(module):
    """The colour a module is drawn in: its layer's, except that a DataStore shares the DataSource column in a nearby hue."""
    return "dstore" if module.endswith("DataStore") else layer(module)


def class_defs(classes):
    lines = []
    for cls in sorted(classes):
        key, dashed = (cls[:-1], True) if cls.endswith("x") and cls[:-1] in STYLE else (cls, False)
        fill, border = STYLE[key]
        # #333 vanishes against GitHub's dark theme; a light grey dash reads on both themes.
        border = "stroke:#bbb,stroke-width:2px,stroke-dasharray:5 3" if dashed else (border or "stroke:#333")
        lines.append(f"  classDef {cls} fill:{fill},{border},color:#fff")
    return lines


def module_diagram(prefix, members, edges):
    """edges: (source, target, solid). Columns are layers; targets outside `members` get a dashed border."""
    member_set = set(members)
    externals = sorted({t for _, t, _ in edges if t not in member_set}, key=lambda m: (ORDER.index(layer(m)), m))
    lines, classes = ["```mermaid", "graph LR"], set()
    for lay in ORDER:
        group = [m for m in members if layer(m) == lay] + [m for m in externals if layer(m) == lay]
        if not group:
            continue
        lines.append(f'  subgraph {prefix}_{lay}["{LAYER_TITLE[lay]}"]')
        for m in group:
            cls = kind(m) + ("" if m in member_set else "x")
            classes.add(cls)
            lines.append(f"    {m}:::{cls}" if label(m) == m else f'    {m}["{label(m)}"]:::{cls}')
        lines.append("  end")
    red = []
    for i, (s, t, solid) in enumerate(edges):
        lines.append(f"  {s} {'-->' if solid else '-.->'} {t}")
        if not solid and (layer(t) not in ALLOWED.get(layer(s), set()) or (s, t) in pinned):
            red.append(i)
    lines += class_defs(classes)
    if red:
        lines.append(f"  linkStyle {','.join(map(str, red))} {EXCEPTION}")
    lines.append("```")
    return "\n".join(lines), len(members) + len(externals), len(red)


def resolutions(members, only=None):
    only = only or {}
    return [(s, t, False) for s in members for t in resolve.get(s, []) if t not in SKIPPED and t in only.get(s, {t})]


report, sections = [], []

# Entry points and the view lane: compile edges among them, then every resolution they make.
entry_compile = [(s, t, True) for s in ENTRY_MEMBERS for t in compile_deps[s] if t in ENTRY_MEMBERS]
block, nodes, red = module_diagram("Entry", ENTRY_MEMBERS, entry_compile + resolutions(ENTRY_MEMBERS))
sections.append(("Entry points and the view lane",
                 "Solid edges are compile-time dependencies: the entry points' on the view lane, and the view lane's own. Which DI target each entry point links is in the next diagram.",
                 block))
report.append(("entry", nodes, red))

# Dependency injection: which target links which, and what each registers.
di_lines = ["```mermaid", "graph LR"]
di_lines.append('  subgraph DI_entry["Entry"]')
for m in ["App", "DevHarness", "LensTool", "ExtensionApp"]:
    di_lines.append(f"    {m}:::entry")
di_lines.append("  end")
di_lines.append('  subgraph DI_di["Dependency injection"]')
for m in DI:
    di_lines.append(f"    {m}:::di")
di_lines.append("  end")
host_only = len(registers["HostDependencyInjection"])
groups = [("DI_common", "Registered by CommonDependencyInjection: both processes", "CommonDependencyInjection"),
          ("DI_ext", "Registered by ExtensionDependencyInjection", "ExtensionDependencyInjection")]
di_classes = {"entry", "di"}
for gid, gtitle, di in groups:
    di_lines.append(f'  subgraph {gid}["{gtitle}"]')
    for m in sorted(registers[di], key=lambda m: (ORDER.index(layer(m)), m)):
        di_classes.add(kind(m))
        di_lines.append(f"    {m}:::{kind(m)}")
    di_lines.append("  end")
di_lines.append(f'  HostRegistered["the other {host_only} implementation modules<br/>(every Interactor; the host\'s UseCases, Repositories,<br/>DataSources, DataStores, Gateways and Ambient lives)"]:::di')
di_edges = [(s, t) for s in ["App", "DevHarness", "LensTool", "ExtensionApp"] for t in compile_deps[s] if t in DI]
di_edges += [(s, t) for s in DI for t in compile_deps[s] if t in DI]
di_edges += [("CommonDependencyInjection", "DI_common"), ("ExtensionDependencyInjection", "DI_ext"),
             ("HostDependencyInjection", "HostRegistered")]
di_lines += [f"  {s} --> {t}" for s, t in di_edges]
di_lines += class_defs(di_classes)
di_lines.append("```")
sections.append(("Dependency injection",
                 "This one is grouped by registration rather than by layer, and every module in it also appears in a layered diagram. The host's entry points link `HostDependencyInjection`, the extension links `ExtensionDependencyInjection`, and both link `CommonDependencyInjection`; `ViewGallery` links none, so no live value reaches it. Every implementation module is registered by exactly one of the three.",
                 "\n".join(di_lines)))
if sorted(registers["CommonDependencyInjection"] + registers["ExtensionDependencyInjection"] + registers["HostDependencyInjection"]) != sorted(
        m for m in modules if layer(m) in ("int", "uc", "repo", "ds", "gw", "amb")):
    fail("the DI registrations do not cover every implementation module exactly once")

drawn = set()
for area, title, summary, members in AREAS:
    edges = resolutions(members, ONLY.get(area))
    for s, t, _ in edges:
        if (s, t) in drawn:
            fail(f"drawn twice: {s} -> {t}")
        drawn.add((s, t))
    block, nodes, red = module_diagram(area, members, edges)
    sections.append((title, summary, block))
    report.append((title, nodes, red))
expected = {(s, t) for s, ts in resolve.items() for t in ts if t not in SKIPPED and s in owner}
if drawn != expected:
    fail(f"undrawn: {sorted(expected - drawn)}; extra: {sorted(drawn - expected)}")

# The overview's lanes must cover every resolution and every compile edge between layers.
OVERVIEW_RESOLVE = {("entry", "int"), ("pres", "int"), ("int", "uc"), ("uc", "repo"), ("repo", "ds"), ("ds", "gw"),
                    ("entry", "amb"), ("pres", "amb"), ("int", "amb"), ("uc", "amb"), ("repo", "amb"), ("ds", "amb"),
                    ("entry", "uc"), ("uc", "gw"), ("repo", "gw"), ("ds", "ds")}
used = {(layer(s), layer(t)) for s, ts in resolve.items() for t in ts if not t.startswith("key:")}
if used - OVERVIEW_RESOLVE:
    fail(f"resolutions the overview does not draw: {sorted(used - OVERVIEW_RESOLVE)}")
IMPL = {"int", "uc", "repo", "ds", "gw", "amb"}
OVERVIEW_COMPILE = {("entry", "view"), ("entry", "pres"), ("entry", "di"), ("view", "view"), ("view", "pres"),
                    ("di", "di"), ("di", "impl"), ("entry", "core"), ("view", "core"), ("pres", "core"),
                    ("di", "core"), ("impl", "core"), ("core", "core")}
compiled = {("impl" if layer(s) in IMPL else layer(s), "impl" if layer(t) in IMPL else layer(t))
            for s, ts in compile_deps.items() if s in modules for t in ts if t in modules}
if compiled - OVERVIEW_COMPILE:
    fail(f"compile edges the overview does not draw: {sorted(compiled - OVERVIEW_COMPILE)}")

with open(sys.argv[2], "w", encoding="utf-8") as out:
    for title, summary, block in sections:
        out.write(f"#### {title}\n\n{summary}\n\n{block}\n\n")
for name, nodes, red in report:
    print(f"{name}: nodes={nodes} red={red}")
print("overview resolve lanes used:", sorted(used))
print("overview compile lanes used:", sorted(compiled))
