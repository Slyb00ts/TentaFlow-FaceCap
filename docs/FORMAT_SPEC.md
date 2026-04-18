# FORMAT_SPEC — `.face v3`

**Kanoniczna specyfikacja formatu binarnego `.face v3`.**

Ten dokument jest **jedynym źródłem prawdy** w razie konfliktu między kodem Swift
(writer) i Rust (reader). Jeśli kod się różni od specyfikacji, **kod ma zostać
dopasowany do tego dokumentu**, nie odwrotnie.

---

## 1. Konwencje globalne

| Konwencja | Wartość |
|---|---|
| Endianness | **little-endian** dla wszystkich pól `u16`, `u32`, `u64`, `f16`, `f32` |
| Wyrównanie sekcji (offset w pliku) | **32 bajty** — każda sekcja zaczyna się na wielokrotności 32 |
| Padding między sekcjami | `0x00` do najbliższej granicy 32 |
| Rozmiar nagłówka pliku | **48 bajtów** |
| Rozmiar wpisu katalogu sekcji | **32 bajty** |
| Magic pliku | ASCII `"FACE"` = `0x46 0x41 0x43 0x45` |
| Wersja major | `3` |
| Wersja minor | `0` (stan bieżący; rośnie przy kompatybilnych zmianach) |
| CRC32 | IEEE 802.3 polynomial `0xEDB88320`, init `0xFFFFFFFF`, final XOR `0xFFFFFFFF` |
| CRC32 — liczone z | **całym plikiem** od offsetu 0 do `total_size - 1`, **pole `crc32` (bajty 24..28) wyzerowane** na czas liczenia |
| Tekst ASCII (nazwy) | null-padded, bez terminatora gdy pełny |
| Konwencja współrzędnych | prawoskrętny układ, Y w górę, Z w kierunku kamery (jak ARKit) |
| Jednostki | metry |

---

## 2. Layout pliku — ogólny

```
┌─────────────────────────────────────────┐  offset 0
│              FILE HEADER                │  48 B
├─────────────────────────────────────────┤  offset 48
│              SECTION DIRECTORY          │  N × 32 B (N = section_count)
├─────────────────────────────────────────┤  offset = 48 + N*32
│              (padding do 32 B)          │  0..31 B
├─────────────────────────────────────────┤  offset = aligned do 32
│              SECTION BODIES             │
│                                         │
│   każda sekcja: (nagłówek + dane),      │
│   padded do 32 B granicy                │
│                                         │
└─────────────────────────────────────────┘  offset = total_size
```

Wszystkie offsety w `SECTION DIRECTORY` są **absolutne** (liczone od początku pliku).

---

## 3. File Header (48 bajtów, offset 0)

| Offset | Typ | Nazwa | Wartość | Opis |
|---|---|---|---|---|
| 0 | `u8[4]` | `magic` | `"FACE"` | `0x46 0x41 0x43 0x45` |
| 4 | `u16` | `version_major` | `3` | |
| 6 | `u16` | `version_minor` | `0` | |
| 8 | `u32` | `flags` | — | bitmaska `FaceFlags` (patrz §4) |
| 12 | `u16` | `section_count` | 1..255 | liczba wpisów w directory |
| 14 | `u16` | `_pad0` | `0` | rezerwa |
| 16 | `u64` | `total_size` | — | rozmiar pliku w bajtach |
| 24 | `u32` | `crc32` | — | CRC32 z całego pliku (tu wyzerowane przy liczeniu) |
| 28 | `u32` | `_pad1` | `0` | rezerwa |
| 32 | `u64` | `created_unix` | — | UNIX epoch (sekundy UTC) |
| 40 | `u8[8]` | `producer` | `"iOSv1.00"` albo `"TESTGEN\0"` | ASCII, null-padded |

**Razem:** 48 B.

---

## 4. Flagi globalne (`FileHeader.flags`)

| Bit | Nazwa | Znaczenie |
|---|---|---|
| 0 | `HAS_PERFORMANCE` | Sekcja `0x0030` obecna |
| 1 | `HAS_LIDAR` | Skan użył LiDAR (informacyjnie, nie zmienia layoutu) |
| 2 | `HAS_TEX` | Sekcja `0x0010` obecna |
| 3 | `HAS_EYES` | Sekcja `0x0041` obecna |
| 4 | `HAS_TEETH` | Sekcja `0x0042` obecna |
| 5 | `HAS_TONGUE` | Sekcja `0x0043` obecna |
| 6 | `HAS_MOUTH_CAV` | Sekcja `0x0044` obecna |
| 7..31 | — | rezerwa (= 0) |

Flagi **muszą** być spójne z obecnością sekcji w katalogu (reader może asertować).

---

## 5. Section Directory (N × 32 B)

Bezpośrednio po headerze (offset 48). Każdy wpis:

| Offset w wpisie | Typ | Nazwa | Opis |
|---|---|---|---|
| 0 | `u32` | `section_id` | id z tabeli §6 |
| 4 | `u32` | `flags` | rezerwa (obecnie `0`) |
| 8 | `u64` | `offset` | offset **w pliku** do bajtu 0 ciała sekcji |
| 16 | `u64` | `size` | rozmiar **użyteczny** (bez paddingu końcowego) |
| 24 | `u64` | `uncompressed_size` | obecnie = `size` (kompresja nie wdrożona) |

**Razem:** 32 B / wpis.

Reguły:
- `offset % 32 == 0` — wymuszone, reader zwraca `AlignmentViolation`,
- `offset + size ≤ total_size` — wymuszone, reader zwraca `OutOfBoundsSection`,
- wpisy w directory **nie muszą** być posortowane po `section_id`.

Po directory następuje padding zer do najbliższej wielokrotności 32 B.

---

## 6. Tabela ID sekcji

| ID | Nazwa | Obowiązkowa | Flaga |
|---|---|---|---|
| `0x0001` | `MESH_GEOMETRY` | TAK | — |
| `0x0002` | `MESH_NORMALS` | nie | — |
| `0x0003` | `MESH_UVS` | gdy jest tekstura | — |
| `0x0004` | `MESH_TRIANGLES` | TAK | — |
| `0x0005` | `VERTEX_GROUPS` | nie | — |
| `0x0010` | `TEXTURE_RGB565` | nie | `HAS_TEX` |
| `0x0020` | `BLENDSHAPE_TABLE` | TAK | — |
| `0x0021` | `BLENDSHAPE_DELTAS` | TAK | — |
| `0x0022` | `MASKS` | nie | — |
| `0x0030` | `PERFORMANCE_CLIPS` | nie | `HAS_PERFORMANCE` |
| `0x0041` | `EYE_SPHERES` | nie | `HAS_EYES` |
| `0x0042` | `TEETH_ROW` | nie | `HAS_TEETH` |
| `0x0043` | `TONGUE` | nie | `HAS_TONGUE` |
| `0x0044` | `MOUTH_CAVITY` | nie | `HAS_MOUTH_CAV` |

Zakresy zarezerwowane:
- `0x0006..0x000F` — przyszłe mesh properties (kolory wierzchołków, tangents),
- `0x0011..0x001F` — alternatywne formaty textury (mip, RGBA, ETC2),
- `0x0023..0x002F` — dodatkowe dane blendshape (np. normal deltas),
- `0x0031..0x0040` — przyszłe animacje (skeletal, BVH),
- `0x0045..0x00FF` — dodatkowe rigid pieces.

---

## 7. Sekcja `0x0001` MESH_GEOMETRY

Pozycje wierzchołków.

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u32` | `vertex_count` |
| 4 | `u8[12]` | `_pad` (zera do 16 B nagłówka) |
| 16 | `[f32;3]` × `vertex_count` | `positions` |

Rozmiar użyteczny: `16 + 12 * vertex_count` bajtów. Po tym padding do 32 B.

---

## 8. Sekcja `0x0002` MESH_NORMALS

Identyczna struktura jak `MESH_GEOMETRY`. `count` musi być równe `vertex_count`
z `MESH_GEOMETRY`.

---

## 9. Sekcja `0x0003` MESH_UVS

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u32` | `uv_count` |
| 4 | `u8[12]` | `_pad` |
| 16 | `[f32;2]` × `uv_count` | `uvs` |

`uv_count` **NIE musi** być równe `vertex_count` (UV mogą być per-corner).

---

## 10. Sekcja `0x0004` MESH_TRIANGLES

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u32` | `triangle_count` |
| 4 | `u8` | `has_uv_indices` (`0` albo `1`) |
| 5 | `u8[11]` | `_pad` |
| 16 | `[u16;3]` × `triangle_count` | `triangles` (indeksy do `positions`) |
| 16 + 6*triangle_count | padding do 32 | |
| po paddingu | `[u16;3]` × `triangle_count` | `uv_triangles` (jeśli `has_uv_indices`) |

Każdy trójkąt to 3 indeksy u16 → 6 B. Jeśli `has_uv_indices = 1`, blok UV-triangles
następuje po pierwszym bloku **po paddingu do 32 B**.

---

## 11. Sekcja `0x0005` VERTEX_GROUPS

Opcjonalna. Per-vertex grupa mimiczna (1 bajt).

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u32` | `count` (musi = `vertex_count`) |
| 4 | `u8[12]` | `_pad` |
| 16 | `u8` × `count` | `group_id[]` |

Konwencja grup (zarezerwowane id, reszta = implementation-defined):
| id | Grupa |
|---|---|
| 0 | neutral / skin |
| 1 | left eye area |
| 2 | right eye area |
| 3 | mouth area |
| 4 | jaw |
| 5 | forehead |
| 6 | nose |
| 7 | chin |

---

## 12. Sekcja `0x0010` TEXTURE_RGB565

Baza koloru twarzy 512×512 RGB565 LE (standardowo).

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u16` | `width` |
| 2 | `u16` | `height` |
| 4 | `u8` | `format` (`0` = RGB565 LE) |
| 5 | `u8` | `mip_count` (`1` = tylko base) |
| 6 | `u8[10]` | `_pad` |
| 16 | `u8` × `width * height * 2` | `pixels` |

Standardowe wymiary: 512×512 (rekomendowane dla Tab5 PSRAM). Inne rozmiary
dopuszczalne (reader sprawdza `width * height * 2 ≤ section_size - 16`).

---

## 13. Sekcja `0x0020` BLENDSHAPE_TABLE

**KANONICZNA DEFINICJA:** wpis blendshape ma **36 bajtów** z jawnym polem
`delta_count: u32`.

> **Status wdrożenia:** obecny kod Swift (`SectionBuilder.swift:118-128`) i Rust
> (`face_v3_types.rs:100` + `face_v3_loader.rs:429-483`) używają **32 B** bez pola
> `delta_count` (wyprowadzane z różnicy offsetów). Do migracji na 36 B — patrz
> [`HANDOFF.md §3.1`](HANDOFF.md#31-krytyczne-rozmiar-wpisu-blendshape_table--36-b-vs-32-b).

### 13.1. Nagłówek sekcji

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u32` | `entry_count` (typowo `52`) |
| 4 | `u8[12]` | `_pad` |
| 16 | BlendshapeEntry × `entry_count` | patrz §13.2 |

### 13.2. Kanoniczny wpis blendshape (36 B)

| Offset w wpisie | Typ | Nazwa | Opis |
|---|---|---|---|
| 0 | `u8` | `au_arkit_id` | 0..51, indeks ARKit blendShapeLocation |
| 1 | `u8` | `flags` | bit 0 = `SPARSE`, bit 1 = `HAS_MASK_L`, bit 2 = `HAS_MASK_R` |
| 2 | `u8` | `name_len` | 0..24 |
| 3 | `u8` | `_pad` | 0 |
| 4 | `u8[24]` | `name` | ASCII, null-padded (np. `"browInnerUp"`) |
| 28 | `u32` | `delta_offset` | offset w blobie `BLENDSHAPE_DELTAS` (od początku blobu) |
| 32 | `u32` | `delta_count` | liczba delt (verteksów zmienionych) |

**Razem:** 36 B.

### 13.3. Alternatywny wpis (32 B, obecnie wdrożony)

Dla kompatybilności wstecznej:

| Offset | Typ | Nazwa |
|---|---|---|
| 0..28 | jak wyżej | |
| 28 | `u32` | `delta_offset` |
| — | — | brak `delta_count`; reader wyprowadza z `(next_offset - this_offset) / stride` |

**Reguła:** stride = 6 B (dense) albo 10 B (sparse). Reader skanuje wszystkie wpisy
szukając najmniejszego `offset > this_offset` albo bierze `blob_len` dla ostatniego.

Do czasu migracji na 36 B oba readery (Swift validator, Rust loader) muszą
implementować oba warianty i dobierać po rozmiarze sekcji:
`entry_size = (section_size - 16) / entry_count ∈ {32, 36}`.

---

## 14. Sekcja `0x0021` BLENDSHAPE_DELTAS

Surowy blob delt wszystkich blendshape. Offsety w `BlendshapeEntry.delta_offset`
są liczone **od początku tego blobu** (nie od początku pliku).

**Dense** (flaga `SPARSE = 0`):
- stride 6 B (`[f16; 3]` = 3×half-float delta xyz),
- długość = `vertex_count * 6` (jeden vert = jedna delta).

**Sparse** (flaga `SPARSE = 1`):
- stride 10 B (`u16 vertex_idx + [f16; 3] delta + u16 _pad`),
- długość = `delta_count * 10`,
- `vertex_idx` to indeks w `MESH_GEOMETRY.positions[]`.

Padding blob-u do 4 B między wpisami (utrzymuje naturalne wyrównanie `f16`).

---

## 15. Sekcja `0x0022` MASKS

Lewa i prawa maska twarzy (per-vertex u8 0..255).

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u32` | `count` (= `vertex_count`) |
| 4 | `u8[12]` | `_pad` |
| 16 | `u8` × `count` | `mask_left[]` |
| 16 + count | padding do 32 B | |
| po paddingu | `u8` × `count` | `mask_right[]` |

Interpretacja: `0` = nie należy do danej strony, `255` = pełna przynależność.
Używane do mirror-blendshape (np. `mouthSmileLeft` vs `mouthSmileRight`).

---

## 16. Sekcja `0x0030` PERFORMANCE_CLIPS

Do 5 klipów × 60 s, każdy klip = timeline 52 AU + opcjonalne audio PCM16 16 kHz.

### 16.1. Nagłówek sekcji

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u16` | `clip_count` (0..5) |
| 2 | `u8[14]` | `_pad` |
| 16 | `ClipHeader` × `clip_count` | patrz §16.2 |

### 16.2. Kanoniczny header klipu — **44 bajty**

**UWAGA:** Swift writer rezerwuje **48 B** na entry z paddingiem (patrz
`SectionBuilder.swift:158` — `entrySize = 48`), ale **używane** są tylko 44 B
(zera od 44..48 traktowane jak padding). Rust reader w `face_v3_types.rs:103`
stałą `PERFORMANCE_CLIP_HEADER_SIZE = 44` — **44 B jest wartością kanoniczną**.

| Offset w headerze | Typ | Nazwa | Opis |
|---|---|---|---|
| 0 | `u8[24]` | `name` | ASCII, null-padded |
| 24 | `u8` | `fps` | 30 (typowo) |
| 25 | `u8` | `_pad` | 0 |
| 26 | `u32` | `frame_count` | liczba klatek |
| 30 | `u32` | `weights_offset` | absolutny offset w sekcji `PERFORMANCE_CLIPS` |
| 34 | `u32` | `audio_offset` | absolutny offset w sekcji (0 gdy brak audio) |
| 38 | `u32` | `audio_size` | bajty audio (0 gdy brak) |
| 42 | `u16` | `_pad_tail` | wyrównanie do 44 B (niektóre writery mogą rozciągnąć do 48 B) |

**Razem:** 44 B (lub 48 B z dodatkowym paddingiem — reader akceptuje obie formy,
ponieważ entry_size liczy z `(section_layout)`).

**Rekomendacja:** writery powinny pisać 44 B bez trailing padding. Reader MUSI
akceptować obie wersje (autodetekcja po obecności niezerowych bajtów w range 44..48).

### 16.3. Blob wag (po wszystkich headerach)

Dla każdego klipu:
- `frame_count × 52` bajtów,
- każdy bajt = quantized AU weight `u8` (0 = 0.0, 255 = 1.0 linear),
- packowane rzędami (frame-major): `[frame0: 52 u8][frame1: 52 u8]...`.

### 16.4. Blob audio (po blobie wag)

Dla klipów z audio:
- PCM signed 16-bit little-endian mono,
- 16 000 Hz,
- `audio_size` bajtów = `frame_count × (16000 / fps) × 2`.

Między klipami padding do 2 B. Cały blob audio padded do 32 B na końcu sekcji.

---

## 17. Sekcja `0x0041` EYE_SPHERES

Dwie sfery oczu + środki + kolor tęczówki.

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u32` | `vertex_count_per_eye` |
| 4 | `[f32;3]` × `vertex_count_per_eye` | `left_positions[]` |
| 4 + n*12 | `[f32;3]` × `vertex_count_per_eye` | `right_positions[]` |
| 4 + 2n*12 | `[f32;2]` × `vertex_count_per_eye` | `left_uvs[]` |
| 4 + 2n*12 + n*8 | `[f32;2]` × `vertex_count_per_eye` | `right_uvs[]` |
| ... | `[f32;3]` | `left_center` |
| ... | `[f32;3]` | `right_center` |
| ... | `f32` | `radius` |
| ... | `u16` | `iris_color_left_rgb565` |
| ... | `u16` | `iris_color_right_rgb565` |

Po tym padding do 32 B.

UV są wspólne dla obu oczu (tekstura tęczówki proceduralna).

---

## 18. Sekcja `0x0042` TEETH_ROW

Dwa rzędy zębów (górny, dolny) + wspólna topologia.

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u32` | `upper_count` |
| 4 | `[f32;3]` × `upper_count` | `upper_positions[]` |
| ... | `u32` | `lower_count` |
| ... | `[f32;3]` × `lower_count` | `lower_positions[]` |
| ... | `u32` | `tri_count` |
| ... | `[u16;3]` × `tri_count` | `triangles[]` |

Trójkąty indeksują wspólną przestrzeń `upper ∥ lower` (konkatenacja).

---

## 19. Sekcja `0x0043` TONGUE

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u32` | `vertex_count` |
| 4 | `[f32;3]` × `vertex_count` | `positions[]` |
| ... | `u32` | `tri_count` |
| ... | `[u16;3]` × `tri_count` | `triangles[]` |

---

## 20. Sekcja `0x0044` MOUTH_CAVITY

| Offset w sekcji | Typ | Nazwa |
|---|---|---|
| 0 | `u32` | `vertex_count` |
| 4 | `[f32;3]` × `vertex_count` | `positions[]` |
| ... | `u32` | `tri_count` |
| ... | `[u16;3]` × `tri_count` | `triangles[]` |
| ... | `u16` | `color_rgb565` |

Jama ustna jest jednokolorowa — używa się `color_rgb565` jako flat shading
(ciemny burgund typowo `0x4208`).

---

## 21. Estymowane rozmiary

Typowy `.face v3` dla przeciętnego użytkownika:

| Sekcja | Rozmiar | Obliczenie |
|---|---|---|
| Header + Directory | ~0.5 KB | 48 + 11 × 32 = 400 B |
| `MESH_GEOMETRY` | 24 KB | 2000 verts × 12 B |
| `MESH_NORMALS` | 24 KB | 2000 × 12 |
| `MESH_UVS` | 16 KB | 2000 × 8 |
| `MESH_TRIANGLES` | 24 KB | 4000 tri × 6 B × 2 (z UV) |
| `VERTEX_GROUPS` | 2 KB | 2000 × 1 |
| `TEXTURE_RGB565` | 512 KB | 512 × 512 × 2 |
| `BLENDSHAPE_TABLE` | 2 KB | 52 × 36 B + header |
| `BLENDSHAPE_DELTAS` | 200–500 KB | 52 × ~500 sparse delts × 10 B |
| `MASKS` | 4 KB | 2 × 2000 × 1 |
| `PERFORMANCE_CLIPS` | 1.8 MB | 5 klipów × 60 s × (52 B + 16000 × 2 B) |
| `EYE_SPHERES` | 20 KB | 2 × 640 verts × 20 B + const |
| `TEETH_ROW` | 30 KB | 2 × 500 × 12 + 1500 × 6 |
| `TONGUE` | 10 KB | 300 × 12 + 600 × 6 |
| `MOUTH_CAVITY` | 5 KB | 150 × 12 + 300 × 6 |
| **Razem** | **~2.7 MB** | |

Bez performance clips: ~900 KB. Z 30-sekundowym jednym klipem: ~1.8 MB.

---

## 22. Walidacja

Reader MUSI asertować (w kolejności):

1. `len(data) ≥ 48` → inaczej `TooShort`.
2. `magic == "FACE"` → inaczej `BadMagic`.
3. `version_major == 3` → inaczej `VersionUnsupported`.
4. `total_size > 0 && total_size ≤ len(data)` → inaczej `SizeOverflow`.
5. `48 + section_count * 32 ≤ total_size` → inaczej `SizeOverflow`.
6. CRC32 nad `data[..total_size]` z bajtami `[24..28] = 0` == `header.crc32`
   → inaczej `CrcMismatch`.
7. Dla każdego wpisu katalogu: `offset % 32 == 0` → `AlignmentViolation`.
8. Dla każdego wpisu: `offset + size ≤ total_size` → `OutOfBoundsSection`.
9. Wymagane sekcje (`MESH_GEOMETRY`, `MESH_TRIANGLES`, `BLENDSHAPE_TABLE`,
   `BLENDSHAPE_DELTAS`) muszą być obecne → inaczej `SectionNotFound`.
10. Nagłówki sekcji (pierwsze 16 B) muszą się mieścić w `section.size`
    → `UnexpectedSectionSize`.
11. Flagi globalne muszą być spójne z obecnością sekcji (reader może pominąć,
    writer MUSI).

---

## 23. Wersjonowanie

- Zwiększenie `version_major` = **breaking** (reader odrzuca).
- Zwiększenie `version_minor` = kompatybilne (reader akceptuje).
- Nowe sekcje w zakresach zarezerwowanych (§6) = `version_minor` += 1.
- Zmiana rozmiaru wpisu `BLENDSHAPE_TABLE` z 32 B na 36 B = **version_minor 3.1**
  (reader 3.0 ignoruje extra bytes — kompatybilne jeśli wpisy mają `delta_count`
  jako ostatnie pole).
