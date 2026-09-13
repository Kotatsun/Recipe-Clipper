const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

const CRC_TABLE = (() => {
  const table = [];
  for (let value = 0; value < 256; value += 1) {
    let crc = value;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) ? (0xedb88320 ^ (crc >>> 1)) : (crc >>> 1);
    }
    table.push(crc >>> 0);
  }
  return table;
})();

export function crc32(data) {
  let crc = 0xffffffff;
  for (const byte of data) crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function u16(value) {
  return new Uint8Array([value & 0xff, (value >>> 8) & 0xff]);
}

function u32(value) {
  return new Uint8Array([
    value & 0xff,
    (value >>> 8) & 0xff,
    (value >>> 16) & 0xff,
    (value >>> 24) & 0xff,
  ]);
}

function append(chunks, value) {
  chunks.push(value instanceof Uint8Array ? value : new Uint8Array(value));
}

function concat(chunks) {
  const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}

function dosDateTime(date = new Date()) {
  return {
    time: (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2),
    date: ((date.getFullYear() - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate(),
  };
}

export function createStoreZip(entries) {
  const chunks = [];
  const central = [];
  const now = dosDateTime();
  let offset = 0;

  for (const entry of entries) {
    const name = String(entry.name).replaceAll("\\", "/");
    if (!name || name.startsWith("/") || name.split("/").includes("..")) {
      throw new Error(`Invalid ZIP entry name: ${name}`);
    }
    const nameBytes = textEncoder.encode(name);
    const data = entry.data instanceof Uint8Array ? entry.data : new Uint8Array(entry.data);
    const checksum = crc32(data);
    const header = [];
    append(header, u32(0x04034b50));
    append(header, u16(20));
    append(header, u16(0x0800)); // UTF-8; store-only compression
    append(header, u16(0));
    append(header, u16(now.time));
    append(header, u16(now.date));
    append(header, u32(checksum));
    append(header, u32(data.length));
    append(header, u32(data.length));
    append(header, u16(nameBytes.length));
    append(header, u16(0));
    append(header, nameBytes);
    append(header, data);
    const local = concat(header);
    append(chunks, local);

    const directory = [];
    append(directory, u32(0x02014b50));
    append(directory, u16(20));
    append(directory, u16(20));
    append(directory, u16(0x0800));
    append(directory, u16(0));
    append(directory, u16(now.time));
    append(directory, u16(now.date));
    append(directory, u32(checksum));
    append(directory, u32(data.length));
    append(directory, u32(data.length));
    append(directory, u16(nameBytes.length));
    append(directory, u16(0));
    append(directory, u16(0));
    append(directory, u16(0));
    append(directory, u16(0));
    append(directory, u32(0));
    append(directory, u32(offset));
    append(directory, nameBytes);
    central.push(concat(directory));
    offset += local.length;
  }

  const centralBytes = concat(central);
  append(chunks, centralBytes);
  const end = [];
  append(end, u32(0x06054b50));
  append(end, u16(0));
  append(end, u16(0));
  append(end, u16(entries.length));
  append(end, u16(entries.length));
  append(end, u32(centralBytes.length));
  append(end, u32(offset));
  append(end, u16(0));
  append(chunks, concat(end));
  return concat(chunks);
}

function readU16(bytes, offset) {
  if (offset + 2 > bytes.length) throw new Error("Invalid ZIP: truncated 16-bit field");
  return bytes[offset] | (bytes[offset + 1] << 8);
}

function readU32(bytes, offset) {
  if (offset + 4 > bytes.length) throw new Error("Invalid ZIP: truncated 32-bit field");
  return (bytes[offset]
    | (bytes[offset + 1] << 8)
    | (bytes[offset + 2] << 16)
    | (bytes[offset + 3] << 24)) >>> 0;
}

function safeEntryName(name) {
  const normalized = name.replaceAll("\\", "/");
  if (!normalized || normalized.startsWith("/") || normalized.split("/").includes("..")) {
    throw new Error("Invalid ZIP: unsafe entry path");
  }
  return normalized;
}

export function readStoreZip(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  const entries = [];
  let offset = 0;
  while (offset + 4 <= bytes.length) {
    const signature = readU32(bytes, offset);
    if (signature === 0x02014b50 || signature === 0x06054b50) break;
    if (signature !== 0x04034b50) throw new Error("Invalid ZIP: unexpected local header");
    const flags = readU16(bytes, offset + 6);
    const method = readU16(bytes, offset + 8);
    if (method !== 0) {
      throw new Error("This backup uses compressed ZIP entries. RecipeClipper backups use store-only ZIPs.");
    }
    if (flags & 0x0008) {
      throw new Error("This ZIP uses data descriptors and cannot be verified safely in the browser.");
    }
    const compressedSize = readU32(bytes, offset + 18);
    const expectedCRC = readU32(bytes, offset + 14);
    const nameLength = readU16(bytes, offset + 26);
    const extraLength = readU16(bytes, offset + 28);
    const nameStart = offset + 30;
    const dataStart = nameStart + nameLength + extraLength;
    const dataEnd = dataStart + compressedSize;
    if (dataEnd > bytes.length) throw new Error("Invalid ZIP: entry is truncated");
    const name = safeEntryName(textDecoder.decode(bytes.slice(nameStart, nameStart + nameLength)));
    const data = bytes.slice(dataStart, dataEnd);
    if (crc32(data) !== expectedCRC) throw new Error(`Invalid ZIP: CRC mismatch for ${name}`);
    entries.push({ name, data });
    offset = dataEnd;
  }
  if (!entries.length) throw new Error("The ZIP does not contain any files");
  return entries;
}
