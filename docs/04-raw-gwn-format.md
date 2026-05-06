# Raw .gwn Format

`scripts/gwnraw.sh` builds the early raw-byte `.gwn` format into a `.gwo` image.

Supported directives:

- `origin <hex>` sets the base load address used by label references.
- `label <name>` records the current output address.
- `bytes <hex...>` emits one or more raw bytes.
- `byte <hex>` emits one raw byte.
- `ascii "<text>"` emits ASCII text with shell-style escapes such as `\r\n`.
- `addr16 <label>` emits a little-endian absolute 16-bit address.
- `rel8 <label>` emits an 8-bit relative displacement from the next byte.
- `rel16 <label>` emits a 16-bit relative displacement from the next word.
- `pad_to <size> with <hex>` pads the image to an output offset.
- `signature <hex...>` emits final signature bytes.

Rules:

- `origin` is optional, defaults to `0`, and must appear before labels or emitted bytes.
- Label names must match `[A-Za-z_][A-Za-z0-9_]*`.
- `addr16` emits an absolute 16-bit address and fails if the label is out of range.
- `rel8` and `rel16` are calculated from the next emitted byte or word.
- Use `byte 00` for NUL terminators.

Example:

```txt
origin 7C00

bytes BE
addr16 banner
bytes E8
rel16 print_string

label banner
ascii "GrOS\r\n"
byte 00
```
