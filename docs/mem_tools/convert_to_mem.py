import sys
from pathlib import Path


def clean_hex_word(s: str) -> str:
    s = s.strip()
    s = s.replace(",", "")
    s = s.replace(";", "")
    s = s.replace("0x", "")
    s = s.replace("0X", "")
    return s.upper()


def parse_coe(path: Path):
    words = []
    in_vector = False

    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()

        if not line or line.startswith(";"):
            continue

        lower = line.lower()

        if "memory_initialization_vector" in lower:
            in_vector = True
            if "=" in line:
                line = line.split("=", 1)[1]
            else:
                continue

        if in_vector:
            line = line.replace(";", ",")
            parts = line.split(",")

            for p in parts:
                p = clean_hex_word(p)
                if p:
                    words.append(p.zfill(8)[-8:])

    return words


def parse_hex(path: Path):
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()

    # Intel HEX: starts with ':'
    if any(line.strip().startswith(":") for line in lines):
        words = []

        for line in lines:
            line = line.strip()
            if not line.startswith(":"):
                continue

            byte_count = int(line[1:3], 16)
            record_type = int(line[7:9], 16)

            if record_type != 0:
                continue

            data = line[9:9 + byte_count * 2]

            for i in range(0, len(data), 8):
                chunk = data[i:i + 8]
                if len(chunk) < 8:
                    continue

                # Intel HEX 里通常是小端字节序：
                # 93020000 -> 00000293
                word = chunk[6:8] + chunk[4:6] + chunk[2:4] + chunk[0:2]
                words.append(word.upper())

        return words

    # 普通裸 hex：每行一个 32-bit word
    words = []
    for line in lines:
        line = clean_hex_word(line)
        if not line:
            continue
        words.append(line.zfill(8)[-8:])

    return words


def write_mem(words, out_path: Path, base_addr: int = 0):
    with out_path.open("w", encoding="utf-8") as f:
        f.write(f"@{base_addr:08X}\n")
        for word in words:
            f.write(word + "\n")


def write_byte_lane_mems(words, out_paths, base_addr: int = 0):
    files = [Path(p).open("w", encoding="utf-8") for p in out_paths]
    try:
        for f in files:
            f.write(f"@{base_addr:08X}\n")

        for word in words:
            word = word.zfill(8)[-8:]
            # RISC-V data words are little-endian in memory:
            # lane0 maps to rdata[7:0], lane3 maps to rdata[31:24].
            files[0].write(word[6:8] + "\n")
            files[1].write(word[4:6] + "\n")
            files[2].write(word[2:4] + "\n")
            files[3].write(word[0:2] + "\n")
    finally:
        for f in files:
            f.close()


def write_word_chunk_mems(words, out_dir: Path, prefix: str, chunks: int = 16, chunk_words: int = 4096):
    out_dir.mkdir(parents=True, exist_ok=True)
    total_words = chunks * chunk_words
    padded_words = list(words[:total_words])
    if len(padded_words) < total_words:
        padded_words.extend(["00000000"] * (total_words - len(padded_words)))

    paths = []
    for chunk in range(chunks):
        path = out_dir / f"{prefix}_chunk{chunk:02d}.mem"
        paths.append(path)
        start = chunk * chunk_words
        end = start + chunk_words
        write_mem(padded_words[start:end], path)

    return paths


def main():
    if len(sys.argv) < 3:
        print("Usage:")
        print("  python convert_to_mem.py input.coe output.mem")
        print("  python convert_to_mem.py input.hex output.mem")
        print("  python convert_to_mem.py input.coe output.mem --byte-lanes b0.mem b1.mem b2.mem b3.mem")
        print("  python convert_to_mem.py input.coe output.mem --word-chunks out_dir prefix")
        sys.exit(1)

    in_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    byte_lane_paths = None
    word_chunk_args = None

    if len(sys.argv) > 3:
        if sys.argv[3] == "--byte-lanes":
            if len(sys.argv) != 8:
                print("ERROR: byte-lane mode must be: --byte-lanes b0.mem b1.mem b2.mem b3.mem")
                sys.exit(1)
            byte_lane_paths = [Path(p) for p in sys.argv[4:8]]
        elif sys.argv[3] == "--word-chunks":
            if len(sys.argv) != 6:
                print("ERROR: word-chunk mode must be: --word-chunks out_dir prefix")
                sys.exit(1)
            word_chunk_args = (Path(sys.argv[4]), sys.argv[5])
        else:
            print("ERROR: unknown option")
            sys.exit(1)

    if not in_path.exists():
        print(f"ERROR: input file not found: {in_path}")
        sys.exit(1)

    suffix = in_path.suffix.lower()

    if suffix == ".coe":
        words = parse_coe(in_path)
    elif suffix == ".hex":
        words = parse_hex(in_path)
    else:
        print("ERROR: only .coe and .hex are supported")
        sys.exit(1)

    if not words:
        print("ERROR: no data parsed")
        sys.exit(1)

    write_mem(words, out_path)
    if byte_lane_paths is not None:
        for p in byte_lane_paths:
            p.parent.mkdir(parents=True, exist_ok=True)
        write_byte_lane_mems(words, byte_lane_paths)
    word_chunk_paths = None
    if word_chunk_args is not None:
        word_chunk_paths = write_word_chunk_mems(words, word_chunk_args[0], word_chunk_args[1])

    print(f"OK: {in_path} -> {out_path}")
    print(f"Words: {len(words)}")
    if byte_lane_paths is not None:
        print("Byte lane MEM files:")
        for i, p in enumerate(byte_lane_paths):
            print(f"  lane{i}: {p}")
    if word_chunk_paths is not None:
        print("Word chunk MEM files:")
        for p in word_chunk_paths:
            print(f"  {p}")


if __name__ == "__main__":
    main()
