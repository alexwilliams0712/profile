#!/usr/bin/env python3
"""In-place JSON/JSON5 reformatter.

Sorts object keys, aligns colons, packs scalar arrays wide, and PRESERVES
comments. Parses json and json5 natively (no json5->json pre-pass), so //
and /* */ comments survive on both.

Usage: json_formatter.py <file> [line_width]
"""

import json
import sys

LINE_WIDTH = int(sys.argv[2]) if len(sys.argv) > 2 else 80


class Tok:
    __slots__ = ("kind", "value", "line")

    def __init__(self, kind, value, line):
        self.kind = kind
        self.value = value
        self.line = line


def tokenize(s):
    tokens = []
    i = 0
    n = len(s)
    line = 0
    while i < n:
        c = s[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r":
            i += 1
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "/":
            j = i + 2
            while j < n and s[j] != "\n":
                j += 1
            tokens.append(Tok("comment", s[i:j].rstrip(), line))
            i = j
            continue
        if c == "/" and i + 1 < n and s[i + 1] == "*":
            j = i + 2
            while j < n and not (s[j] == "*" and j + 1 < n and s[j + 1] == "/"):
                j += 1
            j = min(j + 2, n)
            text = s[i:j]
            tokens.append(Tok("comment", text, line))
            line += text.count("\n")
            i = j
            continue
        if c == '"' or c == "'":
            quote = c
            j = i + 1
            buf = []
            while j < n:
                if s[j] == "\\":
                    buf.append(s[j : j + 2])
                    j += 2
                    continue
                if s[j] == quote:
                    break
                buf.append(s[j])
                j += 1
            tokens.append(Tok("string", (quote, "".join(buf)), line))
            i = j + 1
            continue
        if c in "{}[]:,":
            tokens.append(Tok("punct", c, line))
            i += 1
            continue
        j = i
        while j < n and s[j] not in " \t\r\n" and s[j] not in "{}[]:,/\"'":
            j += 1
        tokens.append(Tok("word", s[i:j], line))
        i = j
    return tokens


def decode_string(quote, raw):
    out = []
    i = 0
    n = len(raw)
    while i < n:
        ch = raw[i]
        if ch == "\\" and i + 1 < n:
            nxt = raw[i + 1]
            simple = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}
            if nxt in simple:
                out.append(simple[nxt])
                i += 2
            elif nxt == "u":
                out.append(chr(int(raw[i + 2 : i + 6], 16)))
                i += 6
            elif nxt == "x":
                out.append(chr(int(raw[i + 2 : i + 4], 16)))
                i += 4
            elif nxt == "\n":
                i += 2
            else:
                out.append(nxt)
                i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def normalize_word(word):
    if word in ("true", "false", "null"):
        return word
    stripped = word.lstrip("+")
    if stripped.lstrip("-") in ("Infinity", "NaN"):
        return stripped
    low = stripped.lower()
    if low.startswith("0x") or low.startswith("-0x"):
        return str(int(stripped, 16))
    try:
        return str(int(stripped))
    except ValueError:
        pass
    try:
        float(stripped)
        return stripped
    except ValueError:
        return json.dumps(word)


class Parser:
    def __init__(self, tokens):
        self.toks = tokens
        self.pos = 0

    def at(self):
        return self.toks[self.pos] if self.pos < len(self.toks) else None

    def comments(self):
        out = []
        while self.pos < len(self.toks) and self.toks[self.pos].kind == "comment":
            out.append(self.toks[self.pos].value)
            self.pos += 1
        return out

    def parse_value(self):
        tok = self.toks[self.pos]
        if tok.kind == "punct" and tok.value == "{":
            return self.parse_object()
        if tok.kind == "punct" and tok.value == "[":
            return self.parse_array()
        if tok.kind == "string":
            self.pos += 1
            q, raw = tok.value
            return ("scalar", json.dumps(decode_string(q, raw)))
        if tok.kind == "word":
            self.pos += 1
            return ("scalar", normalize_word(tok.value))
        raise ValueError("unexpected token: %r" % (tok.value,))

    def consume_tail(self, value_line):
        # optional trailing comment + comma in either order
        trailing = None
        if (
            self.pos < len(self.toks)
            and self.toks[self.pos].kind == "comment"
            and self.toks[self.pos].line == value_line
        ):
            trailing = self.toks[self.pos].value
            self.pos += 1
        if self.pos < len(self.toks) and self.toks[self.pos].kind == "punct" and self.toks[self.pos].value == ",":
            comma_line = self.toks[self.pos].line
            self.pos += 1
            if (
                trailing is None
                and self.pos < len(self.toks)
                and self.toks[self.pos].kind == "comment"
                and self.toks[self.pos].line == comma_line
            ):
                trailing = self.toks[self.pos].value
                self.pos += 1
        return trailing

    def parse_object(self):
        self.pos += 1  # '{'
        members = []
        while True:
            leading = self.comments()
            tok = self.toks[self.pos]
            if tok.kind == "punct" and tok.value == "}":
                self.pos += 1
                return ("object", members, leading)
            if tok.kind == "string":
                q, raw = tok.value
                key = decode_string(q, raw)
            elif tok.kind == "word":
                key = tok.value
            else:
                raise ValueError("expected key, got %r" % (tok.value,))
            self.pos += 1
            leading += self.comments()
            assert self.toks[self.pos].value == ":", "expected colon"
            self.pos += 1
            leading += self.comments()
            value = self.parse_value()
            value_line = self.toks[self.pos - 1].line
            trailing = self.consume_tail(value_line)
            members.append({"leading": leading, "key": key, "value": value, "trailing": trailing})

    def parse_array(self):
        self.pos += 1  # '['
        elems = []
        while True:
            leading = self.comments()
            tok = self.toks[self.pos]
            if tok.kind == "punct" and tok.value == "]":
                self.pos += 1
                return ("array", elems, leading)
            value = self.parse_value()
            value_line = self.toks[self.pos - 1].line
            trailing = self.consume_tail(value_line)
            elems.append({"leading": leading, "value": value, "trailing": trailing})


def compact_json(node):
    kind = node[0]
    if kind == "scalar":
        return node[1]
    if kind == "object":
        members, dangling = node[1], node[2]
        if dangling:
            return None
        items = []
        for m in members:
            if m["leading"] or m["trailing"]:
                return None
            v = compact_json(m["value"])
            if v is None:
                return None
            items.append((m["key"], v))
        if not items:
            return "{}"
        items.sort(key=lambda x: x[0])
        return "{" + ", ".join(json.dumps(k) + ": " + v for k, v in items) + "}"
    members, dangling = node[1], node[2]
    if dangling:
        return None
    parts = []
    for e in members:
        if e["leading"] or e["trailing"]:
            return None
        v = compact_json(e["value"])
        if v is None:
            return None
        parts.append(v)
    if not parts:
        return "[]"
    return "[" + ", ".join(parts) + "]"


def align_json(node, indent=0):
    ind = "  " * indent
    current_col = len(ind)
    kind = node[0]
    if kind == "scalar":
        return node[1]

    if kind == "object":
        members, dangling = node[1], node[2]
        if not members and not dangling:
            return "{}"
        compact = compact_json(node)
        if compact is not None and "\n" not in compact and current_col + len(compact) < LINE_WIDTH:
            return compact
        sm = sorted(members, key=lambda m: m["key"])
        max_len = max(len(json.dumps(m["key"])) for m in sm) if sm else 0
        lines = ["{"]
        for i, m in enumerate(sm):
            for c in m["leading"]:
                lines.append(f"{ind}  {c}")
            key_str = json.dumps(m["key"])
            value_str = align_json(m["value"], indent + 1)
            padding = " " * (max_len - len(key_str))
            comma = "," if i < len(sm) - 1 else ""
            trail = f"  {m['trailing']}" if m["trailing"] else ""
            lines.append(f"{ind}  {key_str}{padding}: {value_str}{comma}{trail}")
        for c in dangling:
            lines.append(f"{ind}  {c}")
        lines.append(f"{ind}}}")
        return "\n".join(lines)

    elems, dangling = node[1], node[2]
    if not elems and not dangling:
        return "[]"
    compact = compact_json(node)
    if compact is not None and "\n" not in compact and current_col + len(compact) < LINE_WIDTH:
        return compact
    has_comments = bool(dangling) or any(e["leading"] or e["trailing"] for e in elems)
    all_scalar = all(e["value"][0] == "scalar" for e in elems)
    if all_scalar and not has_comments:
        inner_ind = ind + "  "
        lines = ["["]
        current_line = inner_ind
        for i, e in enumerate(elems):
            entry = e["value"][1] + (", " if i < len(elems) - 1 else "")
            if current_line == inner_ind:
                current_line += entry
            elif len(current_line) + len(entry) <= LINE_WIDTH:
                current_line += entry
            else:
                lines.append(current_line.rstrip())
                current_line = inner_ind + entry
        if current_line.strip():
            lines.append(current_line.rstrip())
        lines.append(f"{ind}]")
        return "\n".join(lines)
    lines = ["["]
    for i, e in enumerate(elems):
        for c in e["leading"]:
            lines.append(f"{ind}  {c}")
        value_str = align_json(e["value"], indent + 1)
        comma = "," if i < len(elems) - 1 else ""
        trail = f"  {e['trailing']}" if e["trailing"] else ""
        lines.append(f"{ind}  {value_str}{comma}{trail}")
    for c in dangling:
        lines.append(f"{ind}  {c}")
    lines.append(f"{ind}]")
    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: json_formatter.py <file> [line_width]", file=sys.stderr)
        return 1

    with open(sys.argv[1], "r") as f:
        text = f.read()

    parser = Parser(tokenize(text))
    header = parser.comments()
    root = parser.parse_value()
    footer = parser.comments()

    out = list(header)
    out.append(align_json(root, 0))
    out.extend(footer)

    with open(sys.argv[1], "w") as f:
        f.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
