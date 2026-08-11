#define _POSIX_C_SOURCE 200809L
#include "gwo2.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum token_kind { TOK_EOF, TOK_IDENT, TOK_NUMBER, TOK_STRING, TOK_LP, TOK_RP, TOK_LB, TOK_RB,
                  TOK_COLON, TOK_SEMI, TOK_COMMA, TOK_EQ, TOK_ASSIGN, TOK_PLUS, TOK_MINUS, TOK_STAR,
                  TOK_SLASH, TOK_LT, TOK_ARROW };

typedef struct { enum token_kind kind; char text[128]; int64_t number; unsigned line, column; } token_t;
typedef struct { const char *path; const char *source; size_t length, offset; unsigned line, column; token_t current; } lexer_t;
typedef struct { uint8_t *bytes; size_t size, capacity; } code_t;
typedef struct { char name[64]; unsigned slot; } local_t;
typedef struct { lexer_t lexer; code_t code; local_t locals[64]; unsigned local_count; int return_i32; int failed; } parser_t;

static void diagnostic(parser_t *p, const char *format, ...) {
    if (p->failed) return;
    va_list args;
    fprintf(stderr, "%s:%u:%u: error: ", p->lexer.path, p->lexer.current.line, p->lexer.current.column);
    va_start(args, format); vfprintf(stderr, format, args); va_end(args);
    fputc('\n', stderr);
    p->failed = 1;
}

static int code_emit(parser_t *p, uint8_t byte) {
    if (p->code.size == p->code.capacity) {
        size_t capacity = p->code.capacity ? p->code.capacity * 2 : 256;
        uint8_t *bytes = (uint8_t *)realloc(p->code.bytes, capacity);
        if (!bytes) { diagnostic(p, "out of memory while emitting bytecode"); return 0; }
        p->code.bytes = bytes; p->code.capacity = capacity;
    }
    p->code.bytes[p->code.size++] = byte;
    return 1;
}

static int code_u32(parser_t *p, uint32_t value) {
    return code_emit(p, (uint8_t)value) && code_emit(p, (uint8_t)(value >> 8)) &&
           code_emit(p, (uint8_t)(value >> 16)) && code_emit(p, (uint8_t)(value >> 24));
}

static size_t emit_jump(parser_t *p, uint8_t opcode) {
    size_t position = p->code.size;
    code_emit(p, opcode); code_emit(p, 0); code_emit(p, 0);
    return position;
}

static void patch_jump(parser_t *p, size_t position, size_t target) {
    int64_t delta = (int64_t)target - (int64_t)(position + 3);
    if (delta < -32768 || delta > 32767) { diagnostic(p, "jump exceeds Alpha range"); return; }
    p->code.bytes[position + 1] = (uint8_t)(uint16_t)(int16_t)delta;
    p->code.bytes[position + 2] = (uint8_t)((uint16_t)(int16_t)delta >> 8);
}

static int is_ident_start(int c) { return isalpha((unsigned char)c) || c == '_'; }
static int is_ident_continue(int c) { return isalnum((unsigned char)c) || c == '_'; }

static void lexer_next(lexer_t *lexer) {
    while (lexer->offset < lexer->length) {
        char c = lexer->source[lexer->offset];
        if (c == ' ' || c == '\t' || c == '\r') { ++lexer->offset; ++lexer->column; continue; }
        if (c == '\n') { ++lexer->offset; ++lexer->line; lexer->column = 1; continue; }
        if (c == '/' && lexer->offset + 1 < lexer->length && lexer->source[lexer->offset + 1] == '/') {
            lexer->offset += 2; lexer->column += 2;
            while (lexer->offset < lexer->length && lexer->source[lexer->offset] != '\n') { ++lexer->offset; ++lexer->column; }
            continue;
        }
        break;
    }
    token_t token = {0}; token.line = lexer->line; token.column = lexer->column;
    if (lexer->offset >= lexer->length) { token.kind = TOK_EOF; lexer->current = token; return; }
    char c = lexer->source[lexer->offset++]; ++lexer->column;
    if (is_ident_start(c)) {
        size_t n = 0; token.text[n++] = c;
        while (lexer->offset < lexer->length && is_ident_continue(lexer->source[lexer->offset])) {
            if (n + 1 < sizeof(token.text)) token.text[n++] = lexer->source[lexer->offset];
            ++lexer->offset; ++lexer->column;
        }
        token.text[n] = '\0'; token.kind = TOK_IDENT; lexer->current = token; return;
    }
    if (isdigit((unsigned char)c)) {
        size_t n = 0; token.text[n++] = c;
        while (lexer->offset < lexer->length && isdigit((unsigned char)lexer->source[lexer->offset])) {
            if (n + 1 < sizeof(token.text)) token.text[n++] = lexer->source[lexer->offset];
            ++lexer->offset; ++lexer->column;
        }
        token.text[n] = '\0'; token.number = strtoll(token.text, NULL, 10); token.kind = TOK_NUMBER; lexer->current = token; return;
    }
    if (c == '"') {
        size_t n = 0;
        while (lexer->offset < lexer->length && lexer->source[lexer->offset] != '"') {
            if (lexer->source[lexer->offset] == '\\' && lexer->offset + 1 < lexer->length) {
                char escaped = lexer->source[lexer->offset + 1];
                if (escaped == 'n') escaped = '\n';
                else if (escaped == 'r') escaped = '\r';
                else if (escaped == 't') escaped = '\t';
                if (n + 1 < sizeof(token.text)) token.text[n++] = escaped;
                lexer->offset += 2;
                lexer->column += 2;
                continue;
            }
            if (lexer->source[lexer->offset] == '\n') { ++lexer->line; lexer->column = 1; }
            else ++lexer->column;
            if (n + 1 < sizeof(token.text)) token.text[n++] = lexer->source[lexer->offset];
            ++lexer->offset;
        }
        if (lexer->offset < lexer->length) { ++lexer->offset; ++lexer->column; }
        token.text[n] = '\0'; token.kind = TOK_STRING; lexer->current = token; return;
    }
    token.kind = TOK_EOF;
    switch (c) {
    case '(': token.kind = TOK_LP; break; case ')': token.kind = TOK_RP; break;
    case '{': token.kind = TOK_LB; break; case '}': token.kind = TOK_RB; break;
    case ':': token.kind = TOK_COLON; break; case ';': token.kind = TOK_SEMI; break;
    case ',': token.kind = TOK_COMMA; break;
    case '+': token.kind = TOK_PLUS; break; case '*': token.kind = TOK_STAR; break;
    case '/': token.kind = TOK_SLASH; break; case '<': token.kind = TOK_LT; break;
    case '=': token.kind = TOK_ASSIGN; if (lexer->offset < lexer->length && lexer->source[lexer->offset] == '=') { ++lexer->offset; ++lexer->column; token.kind = TOK_EQ; } break;
    case '-': token.kind = TOK_MINUS; if (lexer->offset < lexer->length && lexer->source[lexer->offset] == '>') { ++lexer->offset; ++lexer->column; token.kind = TOK_ARROW; } break;
    default: token.kind = TOK_EOF; break;
    }
    lexer->current = token;
}

static int accept(parser_t *p, enum token_kind kind) { if (p->lexer.current.kind != kind) return 0; lexer_next(&p->lexer); return 1; }
static int expect(parser_t *p, enum token_kind kind, const char *what) {
    if (accept(p, kind)) return 1;
    diagnostic(p, "expected %s", what);
    return 0;
}
static int expect_ident(parser_t *p, char *name, size_t size) {
    if (p->lexer.current.kind != TOK_IDENT) { diagnostic(p, "expected identifier"); return 0; }
    size_t length = strlen(p->lexer.current.text);
    if (length >= size) { diagnostic(p, "identifier is too long"); return 0; }
    memcpy(name, p->lexer.current.text, length + 1);
    lexer_next(&p->lexer);
    return 1;
}
static int local_find(parser_t *p, const char *name) {
    for (unsigned i = 0; i < p->local_count; ++i) if (strcmp(p->locals[i].name, name) == 0) return (int)p->locals[i].slot;
    return -1;
}

static int precedence(enum token_kind kind) {
    if (kind == TOK_EQ || kind == TOK_LT) return 1;
    if (kind == TOK_PLUS || kind == TOK_MINUS) return 2;
    if (kind == TOK_STAR || kind == TOK_SLASH) return 3;
    return 0;
}

static int parse_expression(parser_t *p, int minimum);
static int parse_call(parser_t *p, const char *name);
static int parse_primary(parser_t *p) {
    if (p->lexer.current.kind == TOK_NUMBER) {
        int64_t value = p->lexer.current.number; lexer_next(&p->lexer);
        code_emit(p, 1); code_u32(p, (uint32_t)value); return !p->failed;
    }
    if (p->lexer.current.kind == TOK_STRING) {
        size_t length = strlen(p->lexer.current.text);
        if (length > 255) { diagnostic(p, "byte string is too long"); return 0; }
        code_emit(p, 15); code_emit(p, (uint8_t)length);
        for (size_t i = 0; i < length; ++i) code_emit(p, (uint8_t)p->lexer.current.text[i]);
        lexer_next(&p->lexer);
        return !p->failed;
    }
    if (p->lexer.current.kind == TOK_IDENT) {
        char name[64];
        size_t length = strlen(p->lexer.current.text);
        if (length >= sizeof(name)) { diagnostic(p, "identifier is too long"); return 0; }
        memcpy(name, p->lexer.current.text, length + 1);
        lexer_next(&p->lexer);
        if (p->lexer.current.kind == TOK_LP) return parse_call(p, name);
        int slot = local_find(p, name);
        if (slot < 0) { diagnostic(p, "unknown value '%s'", name); return 0; }
        code_emit(p, 2); code_emit(p, (uint8_t)slot); return !p->failed;
    }
    if (accept(p, TOK_LP)) { int ok = parse_expression(p, 0); expect(p, TOK_RP, "')'"); return ok; }
    diagnostic(p, "expected integer expression"); return 0;
}

static int parse_call_argument(parser_t *p, unsigned *argc) {
    if (!parse_expression(p, 0)) return 0;
    ++*argc;
    return 1;
}

static int parse_call(parser_t *p, const char *name) {
    if (!expect(p, TOK_LP, "'('")) return 0;
    unsigned argc = 0;
    if (strcmp(name, "print_str") == 0) {
        if (p->lexer.current.kind != TOK_STRING) { diagnostic(p, "print_str expects a string literal"); return 0; }
        size_t length = strlen(p->lexer.current.text);
        if (length > 255) { diagnostic(p, "byte string is too long"); return 0; }
        if (!parse_primary(p)) return 0;
        code_emit(p, 1); code_u32(p, (uint32_t)length);
        if (!expect(p, TOK_RP, "')'")) return 0;
        code_emit(p, 12); code_emit(p, 13); code_emit(p, 2);
        return 0;
    }
    if (strcmp(name, "load_byte") == 0) {
        if (!parse_call_argument(p, &argc) || !expect(p, TOK_COMMA, "','") || !parse_call_argument(p, &argc) || !expect(p, TOK_RP, "')'")) return 0;
        code_emit(p, 16); return 1;
    }
    if (strcmp(name, "store_byte") == 0) {
        if (!parse_call_argument(p, &argc) || !expect(p, TOK_COMMA, "','") || !parse_call_argument(p, &argc) || !expect(p, TOK_COMMA, "','") || !parse_call_argument(p, &argc) || !expect(p, TOK_RP, "')'")) return 0;
        code_emit(p, 17); return 0;
    }
    if (strcmp(name, "print_bytes") == 0) {
        if (!parse_call_argument(p, &argc) || !expect(p, TOK_COMMA, "','") || !parse_call_argument(p, &argc) || !expect(p, TOK_RP, "')'")) return 0;
        code_emit(p, 12); code_emit(p, 13); code_emit(p, 2); return 0;
    }
    unsigned expected = 0;
    uint8_t import_id = 0;
    if (strcmp(name, "file_open") == 0) { expected = 2; import_id = 5; }
    else if (strcmp(name, "file_read") == 0) { expected = 3; import_id = 6; }
    else if (strcmp(name, "file_write") == 0) { expected = 3; import_id = 7; }
    else if (strcmp(name, "file_close") == 0) { expected = 1; import_id = 8; }
    else if (strcmp(name, "file_stat") == 0) { expected = 2; import_id = 9; }
    else if (strcmp(name, "mem_grow") == 0) { expected = 1; import_id = 10; }
    else if (strcmp(name, "path_create") == 0) { expected = 1; import_id = 11; }
    else if (strcmp(name, "file_unlink") == 0) { expected = 1; import_id = 12; }
    else if (strcmp(name, "console_read") == 0) { expected = 2; import_id = 4; }
    else if (strcmp(name, "task_yield") == 0) {
        if (!expect(p, TOK_RP, "')'")) return 0;
        code_emit(p, 12); code_emit(p, 14); code_emit(p, 0);
        return 1;
    }
    else if (strcmp(name, "drop") == 0) {
        if (!parse_call_argument(p, &argc) || !expect(p, TOK_RP, "')'")) return 0;
        code_emit(p, 19);
        return 0;
    }
    else { diagnostic(p, "unknown call '%s'", name); return 0; }
    if (expected == 0) {
        if (!expect(p, TOK_RP, "')'")) return 0;
        code_emit(p, 19);
        return 0;
    }
    for (unsigned i = 0; i < expected; ++i) {
        if (!parse_call_argument(p, &argc)) return 0;
        if (i + 1 < expected && !expect(p, TOK_COMMA, "','")) return 0;
    }
    if (!expect(p, TOK_RP, "')'")) return 0;
    code_emit(p, 12); code_emit(p, import_id); code_emit(p, (uint8_t)expected);
    return import_id == 4 || import_id == 5 || import_id == 6 || import_id == 7 ||
           import_id == 8 || import_id == 9 || import_id == 10 || import_id == 11 || import_id == 12;
}

static int parse_expression(parser_t *p, int minimum) {
    if (!parse_primary(p)) return 0;
    while (1) {
        enum token_kind kind = p->lexer.current.kind; int level = precedence(kind);
        if (level < minimum || level == 0) break;
        lexer_next(&p->lexer);
        if (!parse_expression(p, level + 1)) return 0;
        uint8_t op = kind == TOK_PLUS ? 4 : kind == TOK_MINUS ? 5 : kind == TOK_STAR ? 6 :
                     kind == TOK_SLASH ? 7 : kind == TOK_EQ ? 8 : 9;
        code_emit(p, op);
    }
    return !p->failed;
}

static int parse_block(parser_t *p);
static int parse_statement(parser_t *p) {
    if (p->lexer.current.kind != TOK_IDENT) { diagnostic(p, "expected statement"); return 0; }
    char keyword[64];
    size_t keyword_length = strlen(p->lexer.current.text);
    if (keyword_length >= sizeof(keyword)) { diagnostic(p, "statement name is too long"); return 0; }
    memcpy(keyword, p->lexer.current.text, keyword_length + 1);
    lexer_next(&p->lexer);
    if (strcmp(keyword, "let") == 0) {
        char name[64], type[32];
        if (!expect_ident(p, name, sizeof(name)) || !expect(p, TOK_COLON, "':'") || !expect_ident(p, type, sizeof(type)) || strcmp(type, "i32") != 0 || !expect(p, TOK_ASSIGN, "'='")) {
            if (!p->failed) diagnostic(p, "only i32 locals are supported");
            return 0;
        }
        if (local_find(p, name) >= 0 || p->local_count >= 64) { diagnostic(p, "duplicate or excessive local '%s'", name); return 0; }
        unsigned slot = p->local_count++;
        memcpy(p->locals[slot].name, name, strlen(name) + 1);
        p->locals[slot].slot = slot;
        if (!parse_expression(p, 0) || !expect(p, TOK_SEMI, "';'")) return 0;
        code_emit(p, 3); code_emit(p, (uint8_t)slot); return 1;
    }
    if (strcmp(keyword, "return") == 0) {
        if (accept(p, TOK_SEMI)) {
            if (p->return_i32) diagnostic(p, "i32 function must return a value");
            code_emit(p, 14); return !p->failed;
        }
        if (!parse_expression(p, 0) || !expect(p, TOK_SEMI, "';'")) return 0;
        if (!p->return_i32) { diagnostic(p, "void function cannot return a value"); return 0; }
        code_emit(p, 13); return 1;
    }
    if (strcmp(keyword, "if") == 0) {
        if (!expect(p, TOK_LP, "'('") || !parse_expression(p, 0) || !expect(p, TOK_RP, "')'") || !expect(p, TOK_LB, "'{'")) return 0;
        size_t false_jump = emit_jump(p, 11);
        if (!parse_block(p)) return 0;
        if (p->lexer.current.kind == TOK_IDENT && strcmp(p->lexer.current.text, "else") == 0) {
            lexer_next(&p->lexer);
            size_t end_jump = emit_jump(p, 10); patch_jump(p, false_jump, p->code.size);
            if (p->lexer.current.kind == TOK_IDENT && strcmp(p->lexer.current.text, "if") == 0) {
                if (!parse_statement(p)) return 0;
            } else {
                if (!expect(p, TOK_LB, "'{'")) return 0;
                if (!parse_block(p)) return 0;
            }
            patch_jump(p, end_jump, p->code.size);
        } else patch_jump(p, false_jump, p->code.size);
        return 1;
    }
    if (strcmp(keyword, "while") == 0) {
        size_t loop = p->code.size;
        if (!expect(p, TOK_LP, "'('") || !parse_expression(p, 0) || !expect(p, TOK_RP, "')'") || !expect(p, TOK_LB, "'{'")) return 0;
        size_t end_jump = emit_jump(p, 11);
        if (!parse_block(p)) return 0;
        size_t back_jump = emit_jump(p, 10);
        patch_jump(p, back_jump, loop);
        patch_jump(p, end_jump, p->code.size);
        return 1;
    }
    if (strcmp(keyword, "print_i32") == 0 || strcmp(keyword, "exit") == 0 || strcmp(keyword, "newline") == 0) {
        int id = strcmp(keyword, "print_i32") == 0 ? 1 : strcmp(keyword, "exit") == 0 ? 2 : 3;
        if (!expect(p, TOK_LP, "'('") ) return 0;
        unsigned argc = 0;
        if (id != 3) { if (!parse_expression(p, 0)) return 0; argc = 1; }
        if (!expect(p, TOK_RP, "')'") || !expect(p, TOK_SEMI, "';'")) return 0;
        code_emit(p, 12); code_emit(p, (uint8_t)id); code_emit(p, (uint8_t)argc); return 1;
    }
    if (p->lexer.current.kind == TOK_LP) {
        int result = parse_call(p, keyword);
        if (!result && p->failed) return 0;
        if (!expect(p, TOK_SEMI, "';'")) return 0;
        if (result) code_emit(p, 19);
        return 1;
    }
    if (p->lexer.current.kind == TOK_ASSIGN) {
        int slot = local_find(p, keyword); lexer_next(&p->lexer);
        if (slot < 0) { diagnostic(p, "assignment to unknown local '%s'", keyword); return 0; }
        if (!parse_expression(p, 0) || !expect(p, TOK_SEMI, "';'")) return 0;
        code_emit(p, 3); code_emit(p, (uint8_t)slot); return 1;
    }
    diagnostic(p, "unknown statement or function '%s'", keyword); return 0;
}

static int parse_block(parser_t *p) {
    while (!p->failed && p->lexer.current.kind != TOK_RB && p->lexer.current.kind != TOK_EOF)
        if (!parse_statement(p)) return 0;
    return expect(p, TOK_RB, "'}'");
}

static char *read_source(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb"); if (!file) return NULL;
    if (fseeko(file, 0, SEEK_END) != 0) { fclose(file); return NULL; }
    off_t size = ftello(file); if (size < 0 || size > 1 << 20) { fclose(file); return NULL; }
    if (fseeko(file, 0, SEEK_SET) != 0) { fclose(file); return NULL; }
    char *source = (char *)malloc((size_t)size + 1); if (!source) { fclose(file); return NULL; }
    if (fread(source, 1, (size_t)size, file) != (size_t)size) { free(source); fclose(file); return NULL; }
    fclose(file); source[size] = '\0'; *length = (size_t)size; return source;
}

static int compile(const char *source_path, const char *output_path) {
    size_t length = 0; char *source = read_source(source_path, &length);
    if (!source) { fprintf(stderr, "error: cannot read source %s\n", source_path); return 1; }
    parser_t parser = {0}; parser.lexer.path = source_path; parser.lexer.source = source; parser.lexer.length = length; parser.lexer.line = 1; parser.lexer.column = 1; lexer_next(&parser.lexer);
    if (parser.lexer.current.kind != TOK_IDENT || strcmp(parser.lexer.current.text, "target") != 0) diagnostic(&parser, "expected target declaration");
    else {
        lexer_next(&parser.lexer);
        if (parser.lexer.current.kind != TOK_STRING) {
            diagnostic(&parser, "expected target string");
        } else {
            if (strcmp(parser.lexer.current.text, "gros.x86.bios.longmode.grogan.v1") != 0)
                diagnostic(&parser, "unsupported target '%s'", parser.lexer.current.text);
            lexer_next(&parser.lexer);
        }
    }
    char function[64], type[32];
    if (!parser.failed && (!expect_ident(&parser, function, sizeof(function)) || strcmp(function, "fn") != 0)) diagnostic(&parser, "expected fn declaration");
    if (!parser.failed && (!expect_ident(&parser, function, sizeof(function)) || strcmp(function, "main") != 0)) diagnostic(&parser, "only fn main is currently self-hosting");
    if (!parser.failed && (!expect(&parser, TOK_LP, "'('") || !expect(&parser, TOK_RP, "')'") || !expect(&parser, TOK_ARROW, "'->'") || !expect_ident(&parser, type, sizeof(type)))) parser.failed = 1;
    if (!parser.failed) { parser.return_i32 = strcmp(type, "i32") == 0; if (!parser.return_i32 && strcmp(type, "void") != 0) diagnostic(&parser, "unsupported return type '%s'", type); }
    if (!parser.failed && expect(&parser, TOK_LB, "'{'") && parse_block(&parser)) {
        if (parser.lexer.current.kind != TOK_EOF) diagnostic(&parser, "trailing tokens after main");
        if (!parser.failed && (parser.code.size == 0 || (parser.code.bytes[parser.code.size - 1] != 13 && parser.code.bytes[parser.code.size - 1] != 14))) {
            if (parser.return_i32) { code_emit(&parser, 1); code_u32(&parser, 0); code_emit(&parser, 13); }
            else code_emit(&parser, 14);
        }
    }
    int result = 1;
    if (!parser.failed) { char error[160]; result = gwo2_emit_bytecode(output_path, parser.code.bytes, (uint32_t)parser.code.size, 0, error, sizeof(error)) ? 0 : (fprintf(stderr, "error: %s\n", error), 1); }
    free(parser.code.bytes); free(source); return result;
}

int main(int argc, char **argv) {
    if (argc != 3) { fprintf(stderr, "usage: grc0 <source.grw> <output.gwo>\n"); return 2; }
    return compile(argv[1], argv[2]);
}
