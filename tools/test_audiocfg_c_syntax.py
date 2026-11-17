#!/usr/bin/env python3
"""Parse MCU C translation units and detect duplicate locals in one block.

Uses tree-sitter-c for syntax inspection. It is not a Bouffalo SDK build;
cross-compilation and physical boot testing remain required.
"""
from pathlib import Path
from tree_sitter import Language, Parser
import tree_sitter_c

root = Path(__file__).resolve().parents[1]
board = root / "boards" / "a2n20v2-Enhanced"
parser = Parser(Language(tree_sitter_c.language()))
files = [
    board / "src/a2n20_bl616/firmware_host/main.c",
    board / "src/a2n20_bl616/firmware_host/disk.c",
    board / "src/a2n20_bl616/firmware_host/menu.c",
    board / "src/a2n20_bl616/firmware/fpga_spi.c",
]

def ident_from_declarator(node):
    if node is None:
        return None
    if node.type == "identifier":
        return node
    inner = node.child_by_field_name("declarator")
    if inner is not None:
        return ident_from_declarator(inner)
    for child in node.named_children:
        if child.type in ("identifier", "pointer_declarator", "array_declarator",
                          "function_declarator", "parenthesized_declarator"):
            found = ident_from_declarator(child)
            if found is not None:
                return found
    return None

def check_blocks(node, source, filename):
    if node.type == "compound_statement":
        seen = {}
        for child in node.named_children:
            if child.type != "declaration":
                continue
            for part in child.named_children:
                candidate = (
                    part.child_by_field_name("declarator")
                    if part.type == "init_declarator" else
                    part if part.type in ("identifier", "pointer_declarator",
                                         "array_declarator") else None
                )
                ident = ident_from_declarator(candidate)
                if ident is None:
                    continue
                name = source[ident.start_byte:ident.end_byte].decode("utf-8")
                if name in seen:
                    line = ident.start_point.row + 1
                    raise AssertionError(
                        f"{filename}:{line}: duplicate local {name!r} "
                        f"(first at {seen[name]})")
                seen[name] = ident.start_point.row + 1
    for child in node.named_children:
        check_blocks(child, source, filename)

for path in files:
    source = path.read_bytes()
    parsed = parser.parse(source)
    assert not parsed.root_node.has_error, f"syntax parse errors in {path}"
    check_blocks(parsed.root_node, source, path)
    print(f"PASS {path.relative_to(root)}")
print("A3-R6 C parser/duplicate-local check: PASS (not cross-compiled)")
