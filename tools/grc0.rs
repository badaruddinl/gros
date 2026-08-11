//! Hosted bootstrap compiler for the Grown Alpha subset.
//!
//! The bootstrap compiler is intentionally a small, dependency-free Rust
//! program.  It lowers the frozen Grown Alpha grammar directly to the GWO2
//! bytecode contract; the compiler source that eventually runs in GrOS is
//! `examples/grown-alpha/grc1.grw`.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

const GWO2_VERSION: u16 = 2;
const GWO2_TARGET_GROGAN_X86_64: u16 = 1;
const GWO2_KIND_BYTECODE: u16 = 1;
const GWO2_HEADER_SIZE: usize = 32;
const GWO2_SECTION_SIZE: usize = 16;
const GWO2_MAX_BYTES: usize = 1024 * 1024;
const MAX_LOCALS: usize = 255;
const MAX_IDENTIFIER_BYTES: usize = 31;
const MAX_STRING_BYTES: usize = 255;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum TokenKind {
    Eof,
    Ident,
    Number,
    String,
    Lp,
    Rp,
    Lb,
    Rb,
    Colon,
    Semi,
    Comma,
    Eq,
    Assign,
    Plus,
    Minus,
    Star,
    Slash,
    Lt,
    Xor,
    Arrow,
}

#[derive(Clone, Debug)]
struct Token {
    kind: TokenKind,
    text: String,
    number: i64,
    line: usize,
    column: usize,
}

impl Token {
    fn empty(kind: TokenKind, line: usize, column: usize) -> Self {
        Self { kind, text: String::new(), number: 0, line, column }
    }
}

struct Lexer {
    path: String,
    source: Vec<u8>,
    length: usize,
    offset: usize,
    line: usize,
    column: usize,
    current: Token,
}

impl Lexer {
    fn new(path: &str, source: &[u8]) -> Self {
        let mut lexer = Self {
            path: path.to_owned(),
            source: source.to_vec(),
            length: source.len(),
            offset: 0,
            line: 1,
            column: 1,
            current: Token::empty(TokenKind::Eof, 1, 1),
        };
        lexer.next();
        lexer
    }

    fn is_ident_start(byte: u8) -> bool { byte.is_ascii_alphabetic() || byte == b'_' }
    fn is_ident_continue(byte: u8) -> bool { byte.is_ascii_alphanumeric() || byte == b'_' }

    fn next(&mut self) {
        while self.offset < self.length {
            let byte = self.source[self.offset];
            if byte == b' ' || byte == b'\t' || byte == b'\r' {
                self.offset += 1;
                self.column += 1;
                continue;
            }
            if byte == b'\n' {
                self.offset += 1;
                self.line += 1;
                self.column = 1;
                continue;
            }
            if byte == b'/' && self.offset + 1 < self.length && self.source[self.offset + 1] == b'/' {
                self.offset += 2;
                self.column += 2;
                while self.offset < self.length && self.source[self.offset] != b'\n' {
                    self.offset += 1;
                    self.column += 1;
                }
                continue;
            }
            break;
        }

        let line = self.line;
        let column = self.column;
        if self.offset >= self.length {
            self.current = Token::empty(TokenKind::Eof, line, column);
            return;
        }

        let byte = self.source[self.offset];
        self.offset += 1;
        self.column += 1;
        if Self::is_ident_start(byte) {
            let mut bytes = vec![byte];
            while self.offset < self.length && Self::is_ident_continue(self.source[self.offset]) {
                bytes.push(self.source[self.offset]);
                self.offset += 1;
                self.column += 1;
            }
            self.current = Token {
                kind: TokenKind::Ident,
                text: String::from_utf8(bytes).expect("Grown source is UTF-8"),
                number: 0,
                line,
                column,
            };
            return;
        }
        if byte.is_ascii_digit() {
            let mut bytes = vec![byte];
            while self.offset < self.length && self.source[self.offset].is_ascii_digit() {
                bytes.push(self.source[self.offset]);
                self.offset += 1;
                self.column += 1;
            }
            let text = String::from_utf8(bytes).expect("number is ASCII");
            let number = text.parse::<i64>().unwrap_or(i64::MAX);
            self.current = Token { kind: TokenKind::Number, text, number, line, column };
            return;
        }
        if byte == b'"' {
            let mut bytes = Vec::new();
            while self.offset < self.length && self.source[self.offset] != b'"' {
                if self.source[self.offset] == b'\\' && self.offset + 1 < self.length {
                    let escaped = self.source[self.offset + 1];
                    let value = match escaped {
                        b'n' => b'\n',
                        b'r' => b'\r',
                        b't' => b'\t',
                        other => other,
                    };
                    bytes.push(value);
                    self.offset += 2;
                    self.column += 2;
                    continue;
                }
                let value = self.source[self.offset];
                bytes.push(value);
                self.offset += 1;
                if value == b'\n' {
                    self.line += 1;
                    self.column = 1;
                } else {
                    self.column += 1;
                }
            }
            if self.offset < self.length {
                self.offset += 1;
                self.column += 1;
            }
            self.current = Token {
                kind: TokenKind::String,
                text: String::from_utf8(bytes).expect("Grown string is UTF-8"),
                number: 0,
                line,
                column,
            };
            return;
        }

        let (kind, consume_second) = match byte {
            b'(' => (TokenKind::Lp, false),
            b')' => (TokenKind::Rp, false),
            b'{' => (TokenKind::Lb, false),
            b'}' => (TokenKind::Rb, false),
            b':' => (TokenKind::Colon, false),
            b';' => (TokenKind::Semi, false),
            b',' => (TokenKind::Comma, false),
            b'+' => (TokenKind::Plus, false),
            b'*' => (TokenKind::Star, false),
            b'/' => (TokenKind::Slash, false),
            b'<' => (TokenKind::Lt, false),
            b'^' => (TokenKind::Xor, false),
            b'=' if self.offset < self.length && self.source[self.offset] == b'=' => (TokenKind::Eq, true),
            b'=' => (TokenKind::Assign, false),
            b'-' if self.offset < self.length && self.source[self.offset] == b'>' => (TokenKind::Arrow, true),
            b'-' => (TokenKind::Minus, false),
            _ => (TokenKind::Eof, false),
        };
        if consume_second {
            self.offset += 1;
            self.column += 1;
        }
        self.current = Token::empty(kind, line, column);
    }
}

#[derive(Clone)]
struct Local {
    name: String,
    slot: usize,
}

#[derive(Clone)]
struct Function {
    name: String,
    offset: usize,
    params: usize,
    return_i32: bool,
}

struct CallPatch {
    position: usize,
    name: String,
    argc: usize,
}

struct Parser {
    lexer: Lexer,
    code: Vec<u8>,
    locals: Vec<Option<Local>>,
    local_count: usize,
    next_slot: usize,
    functions: Vec<Function>,
    calls: Vec<CallPatch>,
    current_function: Option<usize>,
    return_i32: bool,
    failed: bool,
}

macro_rules! diagnostic {
    ($parser:expr, $($arg:tt)*) => {{
        $parser.diagnostic(format!($($arg)*));
    }};
}

impl Parser {
    fn new(path: &str, source: &[u8]) -> Self {
        Self {
            lexer: Lexer::new(path, source),
            code: Vec::new(),
            locals: vec![None; MAX_LOCALS],
            local_count: 0,
            next_slot: 0,
            functions: Vec::new(),
            calls: Vec::new(),
            current_function: None,
            return_i32: false,
            failed: false,
        }
    }

    fn diagnostic(&mut self, message: String) {
        if self.failed { return; }
        eprintln!("{}:{}:{}: error: {}", self.lexer.path, self.lexer.current.line,
                  self.lexer.current.column, message);
        self.failed = true;
    }

    fn emit(&mut self, byte: u8) { self.code.push(byte); }

    fn emit_u32(&mut self, value: u32) {
        self.emit(value as u8);
        self.emit((value >> 8) as u8);
        self.emit((value >> 16) as u8);
        self.emit((value >> 24) as u8);
    }

    fn accept(&mut self, kind: TokenKind) -> bool {
        if self.lexer.current.kind != kind { return false; }
        self.lexer.next();
        true
    }

    fn expect(&mut self, kind: TokenKind, what: &str) -> bool {
        if self.accept(kind) { return true; }
        diagnostic!(self, "expected {}", what);
        false
    }

    fn expect_ident(&mut self, what: &str) -> Option<String> {
        if self.lexer.current.kind != TokenKind::Ident {
            diagnostic!(self, "expected {}", what);
            return None;
        }
        let name = self.lexer.current.text.clone();
        if name.len() > MAX_IDENTIFIER_BYTES {
            diagnostic!(self, "identifier is too long");
            return None;
        }
        self.lexer.next();
        Some(name)
    }

    fn local_find(&self, name: &str) -> Option<usize> {
        self.locals.iter().flatten().find(|local| local.name == name).map(|local| local.slot)
    }

    fn function_find(&self, name: &str) -> Option<usize> {
        self.functions.iter().position(|function| function.name == name)
    }

    fn add_function(&mut self, name: String, params: usize, return_i32: bool) -> bool {
        if self.function_find(&name).is_some() {
            diagnostic!(self, "duplicate function '{}'", name);
            return false;
        }
        if self.functions.len() >= 64 {
            diagnostic!(self, "too many functions");
            return false;
        }
        self.functions.push(Function { name, offset: 0, params, return_i32 });
        true
    }

    fn precedence(kind: TokenKind) -> usize {
        match kind {
            TokenKind::Eq | TokenKind::Lt | TokenKind::Xor => 1,
            TokenKind::Plus | TokenKind::Minus => 2,
            TokenKind::Star | TokenKind::Slash => 3,
            _ => 0,
        }
    }

    fn emit_jump(&mut self, opcode: u8) -> usize {
        let position = self.code.len();
        self.emit(opcode);
        self.emit(0);
        self.emit(0);
        position
    }

    fn patch_jump(&mut self, position: usize, target: usize) {
        let delta = target as i64 - (position as i64 + 3);
        if !(-32768..=32767).contains(&delta) {
            diagnostic!(self, "jump exceeds Alpha range");
            return;
        }
        let value = delta as i16 as u16;
        self.code[position + 1] = value as u8;
        self.code[position + 2] = (value >> 8) as u8;
    }

    fn parse_primary(&mut self) -> bool {
        match self.lexer.current.kind {
            TokenKind::Number => {
                let value = self.lexer.current.number as u32;
                self.lexer.next();
                self.emit(1);
                self.emit_u32(value);
                true
            }
            TokenKind::String => {
                let text = self.lexer.current.text.clone();
                if text.len() > MAX_STRING_BYTES {
                    diagnostic!(self, "byte string is too long");
                    return false;
                }
                self.emit(15);
                self.emit(text.len() as u8);
                self.code.extend_from_slice(text.as_bytes());
                self.lexer.next();
                !self.failed
            }
            TokenKind::Ident => {
                let name = self.lexer.current.text.clone();
                self.lexer.next();
                if name == "true" || name == "false" {
                    self.emit(1);
                    self.emit_u32(if name == "true" { 1 } else { 0 });
                    return true;
                }
                if self.lexer.current.kind == TokenKind::Lp {
                    return self.parse_call(&name);
                }
                let Some(slot) = self.local_find(&name) else {
                    diagnostic!(self, "unknown value '{}'", name);
                    return false;
                };
                self.emit(2);
                self.emit(slot as u8);
                true
            }
            TokenKind::Lp => {
                self.lexer.next();
                let ok = self.parse_expression(0);
                self.expect(TokenKind::Rp, "')'") && ok
            }
            _ => {
                diagnostic!(self, "expected integer expression");
                false
            }
        }
    }

    fn parse_call_argument(&mut self, argc: &mut usize) -> bool {
        if !self.parse_expression(0) { return false; }
        *argc += 1;
        true
    }

    fn parse_call(&mut self, name: &str) -> bool {
        if !self.expect(TokenKind::Lp, "'('") { return false; }
        let mut argc = 0usize;
        if name == "print_str" {
            if self.lexer.current.kind != TokenKind::String {
                diagnostic!(self, "print_str expects a string literal");
                return false;
            }
            let length = self.lexer.current.text.len();
            if length > MAX_STRING_BYTES {
                diagnostic!(self, "byte string is too long");
                return false;
            }
            if !self.parse_primary() { return false; }
            self.emit(1);
            self.emit_u32(length as u32);
            if !self.expect(TokenKind::Rp, "')'") { return false; }
            self.emit(12);
            self.emit(13);
            self.emit(2);
            return false;
        }
        if name == "load_byte" {
            if !self.parse_call_argument(&mut argc) || !self.expect(TokenKind::Comma, "','") ||
               !self.parse_call_argument(&mut argc) || !self.expect(TokenKind::Rp, "')'") { return false; }
            self.emit(16);
            return true;
        }
        if name == "store_byte" {
            if !self.parse_call_argument(&mut argc) || !self.expect(TokenKind::Comma, "','") ||
               !self.parse_call_argument(&mut argc) || !self.expect(TokenKind::Comma, "','") ||
               !self.parse_call_argument(&mut argc) || !self.expect(TokenKind::Rp, "')'") { return false; }
            self.emit(17);
            return false;
        }
        if name == "print_bytes" {
            if !self.parse_call_argument(&mut argc) || !self.expect(TokenKind::Comma, "','") ||
               !self.parse_call_argument(&mut argc) || !self.expect(TokenKind::Rp, "')'") { return false; }
            self.emit(12);
            self.emit(13);
            self.emit(2);
            return false;
        }

        if let Some(function_index) = self.function_find(name) {
            let expected = self.functions[function_index].params;
            let return_i32 = self.functions[function_index].return_i32;
            for index in 0..expected {
                if !self.parse_call_argument(&mut argc) { return false; }
                if index + 1 < expected && !self.expect(TokenKind::Comma, "','") { return false; }
            }
            if !self.expect(TokenKind::Rp, "')'") { return false; }
            if self.calls.len() >= 1024 {
                diagnostic!(self, "too many call sites");
                return false;
            }
            let position = self.code.len();
            self.emit(20);
            self.emit(0);
            self.emit(0);
            self.emit(expected as u8);
            self.emit(if return_i32 { 1 } else { 0 });
            self.calls.push(CallPatch { position, name: name.to_owned(), argc: expected });
            return return_i32;
        }

        let (expected, import_id) = match name {
            "file_open" => (2, 5),
            "file_read" => (3, 6),
            "file_write" => (3, 7),
            "file_close" => (1, 8),
            "file_stat" => (2, 9),
            "mem_grow" => (1, 10),
            "path_create" => (1, 11),
            "file_unlink" => (1, 12),
            "process_spawn" => (2, 15),
            "process_spawn_args" => (4, 17),
            "process_wait" => (1, 16),
            "process_args" => (2, 18),
            "file_list" => (2, 19),
            "console_read" => (2, 4),
            "task_yield" => {
                if !self.expect(TokenKind::Rp, "')'") { return false; }
                self.emit(12);
                self.emit(14);
                self.emit(0);
                // task_yield is a void scheduler boundary.  It must not
                // leave a synthetic value on the operand stack (otherwise an
                // idle console loop grows the stack on every poll), and the
                // statement parser must not emit a matching drop.
                return false;
            }
            "drop" => {
                if !self.parse_call_argument(&mut argc) || !self.expect(TokenKind::Rp, "')'") { return false; }
                self.emit(19);
                return false;
            }
            _ => {
                diagnostic!(self, "unknown call '{}'", name);
                return false;
            }
        };
        for index in 0..expected {
            if !self.parse_call_argument(&mut argc) { return false; }
            if index + 1 < expected && !self.expect(TokenKind::Comma, "','") { return false; }
        }
        if !self.expect(TokenKind::Rp, "')'") { return false; }
        self.emit(12);
        self.emit(import_id);
        self.emit(expected as u8);
        matches!(import_id, 4..=12 | 15..=19)
    }

    fn parse_expression(&mut self, minimum: usize) -> bool {
        if !self.parse_primary() { return false; }
        loop {
            let kind = self.lexer.current.kind;
            let level = Self::precedence(kind);
            if level < minimum || level == 0 { break; }
            self.lexer.next();
            if !self.parse_expression(level + 1) { return false; }
            let opcode = match kind {
                TokenKind::Plus => 4,
                TokenKind::Minus => 5,
                TokenKind::Star => 6,
                TokenKind::Slash => 7,
                TokenKind::Eq => 8,
                TokenKind::Lt => 9,
                TokenKind::Xor => 22,
                _ => unreachable!(),
            };
            self.emit(opcode);
        }
        !self.failed
    }

    fn parse_statement(&mut self) -> bool {
        let Some(keyword) = self.expect_ident("statement") else { return false; };
        if keyword == "let" {
            let Some(name) = self.expect_ident("local identifier") else { return false; };
            if !self.expect(TokenKind::Colon, "':'") { return false; }
            let Some(type_name) = self.expect_ident("local type") else { return false; };
            if !matches!(type_name.as_str(), "i32" | "bool" | "ptr" | "bytes") {
                diagnostic!(self, "unsupported local type '{}'", type_name);
                return false;
            }
            if !self.expect(TokenKind::Assign, "'='") { return false; }
            if self.local_find(&name).is_some() || self.local_count >= MAX_LOCALS || self.next_slot >= MAX_LOCALS {
                diagnostic!(self, "duplicate or excessive local '{}'", name);
                return false;
            }
            let slot = self.next_slot;
            self.next_slot += 1;
            self.local_count += 1;
            self.locals[slot] = Some(Local { name, slot });
            if !self.parse_expression(0) || !self.expect(TokenKind::Semi, "';'") { return false; }
            self.emit(3);
            self.emit(slot as u8);
            return true;
        }
        if keyword == "return" {
            if self.accept(TokenKind::Semi) {
                if self.return_i32 {
                    diagnostic!(self, "i32 function must return a value");
                    return false;
                }
                let is_main = self.current_function.map(|index| self.functions[index].name == "main").unwrap_or(false);
                self.emit(if is_main { 14 } else { 21 });
                return true;
            }
            if !self.parse_expression(0) || !self.expect(TokenKind::Semi, "';'") { return false; }
            if !self.return_i32 {
                diagnostic!(self, "void function cannot return a value");
                return false;
            }
            self.emit(13);
            return true;
        }
        if keyword == "if" {
            if !self.expect(TokenKind::Lp, "'('") || !self.parse_expression(0) ||
               !self.expect(TokenKind::Rp, "')'") || !self.expect(TokenKind::Lb, "'{'") { return false; }
            let false_jump = self.emit_jump(11);
            if !self.parse_block() { return false; }
            if self.lexer.current.kind == TokenKind::Ident && self.lexer.current.text == "else" {
                self.lexer.next();
                let end_jump = self.emit_jump(10);
                self.patch_jump(false_jump, self.code.len());
                if self.lexer.current.kind == TokenKind::Ident && self.lexer.current.text == "if" {
                    if !self.parse_statement() { return false; }
                } else {
                    if !self.expect(TokenKind::Lb, "'{'") || !self.parse_block() { return false; }
                }
                self.patch_jump(end_jump, self.code.len());
            } else {
                self.patch_jump(false_jump, self.code.len());
            }
            return true;
        }
        if keyword == "while" {
            let loop_start = self.code.len();
            if !self.expect(TokenKind::Lp, "'('") || !self.parse_expression(0) ||
               !self.expect(TokenKind::Rp, "')'") || !self.expect(TokenKind::Lb, "'{'") { return false; }
            let end_jump = self.emit_jump(11);
            if !self.parse_block() { return false; }
            let back_jump = self.emit_jump(10);
            self.patch_jump(back_jump, loop_start);
            self.patch_jump(end_jump, self.code.len());
            return true;
        }
        if matches!(keyword.as_str(), "print_i32" | "exit" | "newline") {
            let import_id = match keyword.as_str() { "print_i32" => 1, "exit" => 2, _ => 3 };
            if !self.expect(TokenKind::Lp, "'('") { return false; }
            let mut argc = 0;
            if import_id != 3 {
                if !self.parse_expression(0) { return false; }
                argc = 1;
            }
            if !self.expect(TokenKind::Rp, "')'") || !self.expect(TokenKind::Semi, "';'") { return false; }
            self.emit(12);
            self.emit(import_id);
            self.emit(argc);
            return true;
        }
        if self.lexer.current.kind == TokenKind::Lp {
            let result = self.parse_call(&keyword);
            if self.failed || !self.expect(TokenKind::Semi, "';'") { return false; }
            if result { self.emit(19); }
            return true;
        }
        if self.lexer.current.kind == TokenKind::Assign {
            let Some(slot) = self.local_find(&keyword) else {
                diagnostic!(self, "assignment to unknown local '{}'", keyword);
                return false;
            };
            self.lexer.next();
            if !self.parse_expression(0) || !self.expect(TokenKind::Semi, "';'") { return false; }
            self.emit(3);
            self.emit(slot as u8);
            return true;
        }
        diagnostic!(self, "unknown statement or function '{}'", keyword);
        false
    }

    fn parse_block(&mut self) -> bool {
        while !self.failed && self.lexer.current.kind != TokenKind::Rb && self.lexer.current.kind != TokenKind::Eof {
            if !self.parse_statement() { return false; }
        }
        self.expect(TokenKind::Rb, "'}'")
    }

    fn skip_function_body(&mut self) -> bool {
        if !self.expect(TokenKind::Lb, "'{'") { return false; }
        let mut depth = 1usize;
        while !self.failed && self.lexer.current.kind != TokenKind::Eof && depth != 0 {
            if self.accept(TokenKind::Lb) {
                depth += 1;
            } else if self.accept(TokenKind::Rb) {
                depth -= 1;
            } else {
                self.lexer.next();
            }
        }
        if depth != 0 {
            diagnostic!(self, "unterminated function body");
            return false;
        }
        true
    }
}

fn scan_declarations(path: &str, source: &[u8]) -> Option<Vec<Function>> {
    let mut scan = Parser::new(path, source);
    let keyword = scan.expect_ident("target declaration")?;
    if keyword != "target" {
        diagnostic!(scan, "expected target declaration");
        return None;
    }
    if scan.lexer.current.kind != TokenKind::String || scan.lexer.current.text != "gros.x86.bios.longmode.grogan.v1" {
        diagnostic!(scan, "unsupported target");
        return None;
    }
    scan.lexer.next();
    while !scan.failed && scan.lexer.current.kind != TokenKind::Eof {
        let declaration = scan.expect_ident("fn declaration")?;
        if declaration != "fn" {
            diagnostic!(scan, "expected fn declaration");
            return None;
        }
        let name = scan.expect_ident("function name")?;
        if !scan.expect(TokenKind::Lp, "'('") { return None; }
        let mut params = 0usize;
        if scan.lexer.current.kind != TokenKind::Rp {
            loop {
                scan.expect_ident("parameter name")?;
                if !scan.expect(TokenKind::Colon, "':'") { return None; }
                let type_name = scan.expect_ident("parameter type")?;
                if !matches!(type_name.as_str(), "i32" | "bool" | "ptr" | "bytes") {
                    diagnostic!(scan, "unsupported parameter type '{}'", type_name);
                    return None;
                }
                params += 1;
                if !scan.accept(TokenKind::Comma) { break; }
            }
        }
        if !scan.expect(TokenKind::Rp, "')'") || !scan.expect(TokenKind::Arrow, "'->'") { return None; }
        let return_type = scan.expect_ident("return type")?;
        let return_i32 = return_type == "i32";
        if !return_i32 && return_type != "void" {
            diagnostic!(scan, "unsupported return type '{}'", return_type);
            return None;
        }
        if !scan.add_function(name, params, return_i32) || !scan.skip_function_body() { return None; }
    }
    if scan.failed { None } else { Some(scan.functions) }
}

fn is_terminal(code: &[u8]) -> bool {
    matches!(code.last(), Some(13 | 14 | 21))
}

fn fnv1a(bytes: &[u8]) -> u32 {
    let mut hash = 2_166_136_261u32;
    for byte in bytes {
        hash = (hash ^ u32::from(*byte)).wrapping_mul(16_777_619);
    }
    hash
}

fn put16(bytes: &mut [u8], offset: usize, value: u16) {
    bytes[offset] = value as u8;
    bytes[offset + 1] = (value >> 8) as u8;
}

fn put32(bytes: &mut [u8], offset: usize, value: u32) {
    for index in 0..4 { bytes[offset + index] = (value >> (8 * index)) as u8; }
}

fn emit_gwo2(path: &Path, code: &[u8], entry: usize) -> Result<(), String> {
    if code.is_empty() || code.len() > GWO2_MAX_BYTES - GWO2_HEADER_SIZE - GWO2_SECTION_SIZE {
        return Err("bytecode size outside GWO2 limit".to_owned());
    }
    if entry >= code.len() { return Err("GWO2 entry is outside bytecode".to_owned()); }
    let size = GWO2_HEADER_SIZE + GWO2_SECTION_SIZE + code.len();
    let mut bytes = vec![0u8; size];
    bytes[0..4].copy_from_slice(b"GWO2");
    put16(&mut bytes, 4, GWO2_VERSION);
    put16(&mut bytes, 6, GWO2_TARGET_GROGAN_X86_64);
    put16(&mut bytes, 8, GWO2_KIND_BYTECODE);
    put32(&mut bytes, 12, GWO2_HEADER_SIZE as u32);
    put32(&mut bytes, 16, 1);
    put32(&mut bytes, 20, entry as u32);
    put32(&mut bytes, 24, code.len() as u32);
    let code_offset = GWO2_HEADER_SIZE + GWO2_SECTION_SIZE;
    bytes[code_offset..].copy_from_slice(code);
    put32(&mut bytes, GWO2_HEADER_SIZE, 1);
    put32(&mut bytes, GWO2_HEADER_SIZE + 4, code_offset as u32);
    put32(&mut bytes, GWO2_HEADER_SIZE + 8, code.len() as u32);
    put32(&mut bytes, GWO2_HEADER_SIZE + 12, fnv1a(code));
    let image_checksum = fnv1a(&bytes[GWO2_HEADER_SIZE..]);
    put32(&mut bytes, 28, image_checksum);
    fs::write(path, bytes).map_err(|error| format!("cannot write GWO2 image: {}", error))
}

fn parse_import_line(line: &[u8]) -> Result<Option<String>, String> {
    let mut start = 0usize;
    while start < line.len() && matches!(line[start], b' ' | b'\t' | b'\r') { start += 1; }
    if !line[start..].starts_with(b"import") { return Ok(None); }
    let mut position = start + 6;
    if position >= line.len() || !matches!(line[position], b' ' | b'\t') {
        return Err("import must be followed by whitespace".to_owned());
    }
    while position < line.len() && matches!(line[position], b' ' | b'\t') { position += 1; }
    if position >= line.len() || line[position] != b'"' {
        return Err("import expects a quoted module path".to_owned());
    }
    position += 1;
    let path_start = position;
    while position < line.len() && line[position] != b'"' { position += 1; }
    if position >= line.len() { return Err("unterminated import path".to_owned()); }
    let name = String::from_utf8(line[path_start..position].to_vec())
        .map_err(|_| "import path is not UTF-8".to_owned())?;
    if name.is_empty() || name.len() > 31 || name.contains('/') || name.contains('\\') || name.contains("..") {
        return Err("import path must be one bounded root filename".to_owned());
    }
    position += 1;
    while position < line.len() && matches!(line[position], b' ' | b'\t' | b'\r') { position += 1; }
    if position >= line.len() || line[position] != b';' {
        return Err("import must end with ';'".to_owned());
    }
    Ok(Some(name))
}

fn expand_source_file(path: &Path, depth: usize, root: bool) -> Result<Vec<u8>, String> {
    if depth > 8 { return Err("import nesting exceeds Alpha limit".to_owned()); }
    let source = fs::read(path).map_err(|error| format!("cannot read source {}: {}", path.display(), error))?;
    let mut output = Vec::with_capacity(source.len());
    for line in source.split_inclusive(|byte| *byte == b'\n') {
        match parse_import_line(line)? {
            Some(name) => {
                let parent = path.parent().unwrap_or_else(|| Path::new("."));
                let module_path = parent.join(PathBuf::from(name));
                let module = expand_source_file(&module_path, depth + 1, false)?;
                output.extend_from_slice(&module);
                if !module.ends_with(b"\n") { output.push(b'\n'); }
            }
            None => output.extend_from_slice(line),
        }
    }
    if !root {
        let trimmed = output.iter().copied().skip_while(|byte| matches!(byte, b' ' | b'\t' | b'\r' | b'\n'));
        let prefix: Vec<u8> = trimmed.take(6).collect();
        if prefix == b"target" { return Err(format!("module {} must contain functions, not a target declaration", path.display())); }
    }
    Ok(output)
}

fn compile(source_path: &Path, output_path: &Path) -> Result<(), String> {
    let source = expand_source_file(source_path, 0, true)?;
    if source.len() > 1 << 20 { return Err("source exceeds Alpha limit".to_owned()); }
    let declarations = scan_declarations(&source_path.display().to_string(), &source)
        .ok_or_else(|| "source declaration scan failed".to_owned())?;
    let mut parser = Parser::new(&source_path.display().to_string(), &source);
    parser.functions = declarations;
    let target = parser.expect_ident("target declaration");
    if target.as_deref() != Some("target") {
        if !parser.failed { diagnostic!(parser, "expected target declaration"); }
    } else if parser.lexer.current.kind != TokenKind::String {
        diagnostic!(parser, "expected target string");
    } else {
        parser.lexer.next();
    }

    while !parser.failed && parser.lexer.current.kind != TokenKind::Eof {
        let declaration = match parser.expect_ident("fn declaration") { Some(value) => value, None => break };
        if declaration != "fn" {
            diagnostic!(parser, "expected fn declaration");
            break;
        }
        let name = match parser.expect_ident("function name") { Some(value) => value, None => break };
        if !parser.expect(TokenKind::Lp, "'('") { break; }
        let Some(function_index) = parser.function_find(&name) else {
            diagnostic!(parser, "unknown function declaration '{}'", name);
            break;
        };
        parser.current_function = Some(function_index);
        parser.return_i32 = parser.functions[function_index].return_i32;
        parser.local_count = 0;
        parser.next_slot = 0;
        parser.locals.fill(None);
        let mut parameters = Vec::new();
        if parser.lexer.current.kind != TokenKind::Rp {
            loop {
                let Some(parameter) = parser.expect_ident("parameter name") else { break; };
                if !parser.expect(TokenKind::Colon, "':'") { break; }
                if parser.expect_ident("parameter type").is_none() { break; }
                parameters.push(parameter);
                if !parser.accept(TokenKind::Comma) { break; }
            }
        }
        if parser.failed || !parser.expect(TokenKind::Rp, "')'") || !parser.expect(TokenKind::Arrow, "'->'") ||
           parser.expect_ident("return type").is_none() || !parser.expect(TokenKind::Lb, "'{'") { break; }
        if parameters.len() != parser.functions[function_index].params {
            diagnostic!(parser, "function parameter count changed during parse");
            break;
        }
        parser.functions[function_index].offset = parser.code.len();
        for parameter in parameters.iter().rev() {
            if parser.local_find(parameter).is_some() || parser.local_count >= MAX_LOCALS || parser.next_slot >= MAX_LOCALS {
                diagnostic!(parser, "duplicate or excessive parameter '{}'", parameter);
                break;
            }
            let slot = parser.next_slot;
            parser.next_slot += 1;
            parser.local_count += 1;
            parser.locals[slot] = Some(Local { name: parameter.clone(), slot });
            parser.emit(3);
            parser.emit(slot as u8);
        }
        if parser.failed || !parser.parse_block() { break; }
        if !is_terminal(&parser.code) {
            if parser.return_i32 {
                parser.emit(1);
                parser.emit_u32(0);
                parser.emit(13);
            } else {
                parser.emit(21);
            }
        }
    }

    let main_index = parser.function_find("main").ok_or_else(|| "missing fn main".to_owned())?;
    if parser.failed { return Err("source parse failed".to_owned()); }
    for patch in &parser.calls {
        let Some(function_index) = parser.function_find(&patch.name) else {
            return Err(format!("call target '{}' is unknown", patch.name));
        };
        let function = &parser.functions[function_index];
        if function.offset > u16::MAX as usize { return Err(format!("call target '{}' is outside Alpha range", patch.name)); }
        if function.params != patch.argc { return Err(format!("wrong argument count for '{}'", patch.name)); }
        parser.code[patch.position + 1] = function.offset as u8;
        parser.code[patch.position + 2] = (function.offset >> 8) as u8;
    }
    emit_gwo2(output_path, &parser.code, parser.functions[main_index].offset)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        eprintln!("usage: grc0 <source.grw> <output.gwo>");
        std::process::exit(2);
    }
    if let Err(error) = compile(Path::new(&args[1]), Path::new(&args[2])) {
        eprintln!("error: {}", error);
        std::process::exit(1);
    }
}
