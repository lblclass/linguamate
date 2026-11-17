#!/usr/bin/env node
/**
 * Renders the 1024x1024 app icon as a PNG with no external dependencies.
 *
 * iOS rejects app icons that carry an alpha channel, so the writer emits
 * truecolour (colour type 2) RGB bytes. Shapes are drawn with 3x3 supersampling
 * so the edges stay clean after Xcode downsamples the asset.
 *
 * Run: node Tools/make_icon.js
 */
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const SIZE = 1024;
const SS = 3; // supersampling factor

const ACCENT = [0.36, 0.31, 0.93];
const ACCENT_2 = [0.99, 0.42, 0.52];
const WHITE = [1, 1, 1];

const mix = (a, b, t) => a.map((value, index) => value + (b[index] - value) * t);

function roundedRectContains(x, y, left, top, right, bottom, radius) {
  if (x < left || x > right || y < top || y > bottom) return false;
  const cx = Math.min(Math.max(x, left + radius), right - radius);
  const cy = Math.min(Math.max(y, top + radius), bottom - radius);
  const dx = x - cx;
  const dy = y - cy;
  return dx * dx + dy * dy <= radius * radius;
}

function triangleContains(px, py, a, b, c) {
  const sign = (p1, p2, p3) => (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1]);
  const d1 = sign([px, py], a, b);
  const d2 = sign([px, py], b, c);
  const d3 = sign([px, py], c, a);
  const hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
  const hasPos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(hasNeg && hasPos);
}

function circleContains(x, y, cx, cy, radius) {
  const dx = x - cx;
  const dy = y - cy;
  return dx * dx + dy * dy <= radius * radius;
}

// Speech bubble geometry (a rounded rectangle plus a tail).
const BUBBLE = { left: 214, top: 232, right: 810, bottom: 618, radius: 132 };
const TAIL = [[356, 600], [318, 792], [486, 606]];
const DOTS = [
  { cx: 372, cy: 425, r: 40 },
  { cx: 512, cy: 425, r: 40 },
  { cx: 652, cy: 425, r: 40 },
];

function sample(x, y) {
  // Background: diagonal gradient.
  const t = Math.min(1, Math.max(0, (x + y) / (2 * (SIZE - 1))));
  let colour = mix(ACCENT, ACCENT_2, t);

  const inBubble =
    roundedRectContains(x, y, BUBBLE.left, BUBBLE.top, BUBBLE.right, BUBBLE.bottom, BUBBLE.radius) ||
    triangleContains(x, y, TAIL[0], TAIL[1], TAIL[2]);
  if (inBubble) colour = WHITE;

  for (const dot of DOTS) {
    if (circleContains(x, y, dot.cx, dot.cy, dot.r)) {
      colour = mix(ACCENT, ACCENT_2, Math.min(1, Math.max(0, (dot.cx + dot.cy) / (2 * (SIZE - 1)))));
      break;
    }
  }
  return colour;
}

const pixels = Buffer.alloc(SIZE * SIZE * 3);
for (let y = 0; y < SIZE; y += 1) {
  for (let x = 0; x < SIZE; x += 1) {
    let r = 0;
    let g = 0;
    let b = 0;
    for (let sy = 0; sy < SS; sy += 1) {
      for (let sx = 0; sx < SS; sx += 1) {
        const colour = sample(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS);
        r += colour[0];
        g += colour[1];
        b += colour[2];
      }
    }
    const samples = SS * SS;
    const offset = (y * SIZE + x) * 3;
    pixels[offset] = Math.round((r / samples) * 255);
    pixels[offset + 1] = Math.round((g / samples) * 255);
    pixels[offset + 2] = Math.round((b / samples) * 255);
  }
}

// ------------------------------------------------------------- PNG container
const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buffer) {
  let crc = -1;
  for (const byte of buffer) crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ -1) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const typeAndData = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(typeAndData), 0);
  return Buffer.concat([length, typeAndData, crc]);
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(SIZE, 0);
ihdr.writeUInt32BE(SIZE, 4);
ihdr[8] = 8; // bit depth
ihdr[9] = 2; // colour type: truecolour, no alpha
ihdr[10] = 0; // deflate
ihdr[11] = 0; // adaptive filtering
ihdr[12] = 0; // no interlace

const raw = Buffer.alloc(SIZE * (SIZE * 3 + 1));
for (let y = 0; y < SIZE; y += 1) {
  const rowStart = y * (SIZE * 3 + 1);
  raw[rowStart] = 0; // filter type 0
  pixels.copy(raw, rowStart + 1, y * SIZE * 3, (y + 1) * SIZE * 3);
}

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk("IHDR", ihdr),
  chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
  chunk("IEND", Buffer.alloc(0)),
]);

const target = path.resolve(__dirname, "..", "LinguaMate", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png");
fs.mkdirSync(path.dirname(target), { recursive: true });
fs.writeFileSync(target, png);
console.log(`icon written: ${path.relative(path.resolve(__dirname, ".."), target)} (${Math.round(png.length / 1024)} KB, ${SIZE}x${SIZE}, RGB no alpha)`);