import ast
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
NONTRADING_ROOT = PROJECT_ROOT / "src" / "break100" / "nontrading"
SOURCE_ROOT = PROJECT_ROOT / "src" / "break100"
FORBIDDEN_IMPORT_PREFIXES = (
    "break100.execution",
    "MetaTrader5",
)
FORBIDDEN_ORDER_SYMBOLS = {
    "CTrade",
    "MqlTradeRequest",
    "OrderSend",
    "OrderSendAsync",
    "order_send",
}


def imported_modules(path: Path) -> set[str]:
    """Return absolute import names from a Python module."""
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    imports: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.add(node.module)
    return imports


def test_nontrading_package_exists_and_has_no_execution_imports() -> None:
    assert NONTRADING_ROOT.is_dir(), "non-trading boundary must be explicit"
    modules = sorted(NONTRADING_ROOT.rglob("*.py"))
    assert modules, "non-trading boundary must contain executable contracts"

    violations: list[str] = []
    for module in modules:
        for imported in imported_modules(module):
            if imported.startswith(FORBIDDEN_IMPORT_PREFIXES):
                violations.append(f"{module.relative_to(PROJECT_ROOT)} -> {imported}")

    assert violations == []


def test_order_submission_symbols_are_confined_to_execution_package() -> None:
    assert SOURCE_ROOT.is_dir(), "source package must exist"
    violations: list[str] = []
    for module in sorted(SOURCE_ROOT.rglob("*.py")):
        relative = module.relative_to(SOURCE_ROOT)
        if relative.parts and relative.parts[0] == "execution":
            continue
        tree = ast.parse(module.read_text(encoding="utf-8"), filename=str(module))
        symbols = {
            node.id
            for node in ast.walk(tree)
            if isinstance(node, ast.Name) and node.id in FORBIDDEN_ORDER_SYMBOLS
        }
        attributes = {
            node.attr
            for node in ast.walk(tree)
            if isinstance(node, ast.Attribute) and node.attr in FORBIDDEN_ORDER_SYMBOLS
        }
        if symbols or attributes:
            found = ",".join(sorted(symbols | attributes))
            violations.append(f"{module.relative_to(PROJECT_ROOT)} -> {found}")

    assert violations == []
