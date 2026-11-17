#!/usr/bin/env node
/**
 * Algorithm cross-check for the tutor protocol.
 *
 * The Swift sources in LinguaMate/ cannot be compiled on a Windows machine
 * (no Xcode/Swift toolchain), so this script is a line-for-line port of
 * SSEDecoder, TutorReplyParser and StreamingTutorReplyExtractor into
 * JavaScript and runs the SAME assertions as the XCTest suites against the SAME
 * vectors. It proves the parsing/streaming logic is correct; it does not prove
 * the Swift compiles.
 *
 * Run: node Tools/protocol_check.js
 */
const TAGS = {
  replyOpen: "[REPLY]",
  replyClose: "[/REPLY]",
  translationOpen: "[TRANSLATION]",
  translationClose: "[/TRANSLATION]",
  correctionsOpen: "[CORRECTIONS]",
  correctionsClose: "[/CORRECTIONS]",
  followUpOpen: "[FOLLOWUP]",
  followUpClose: "[/FOLLOWUP]",
};

const BULLETS = new Set(["-", "•", "*", "–", "—"]);

const normalizeNewlines = (text) => text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
const lower = (text) => text.toLowerCase();

function containsTag(text, tag) {
  return lower(text).includes(lower(tag));
}

const ALL_TAGS = Object.values(TAGS);

function section(text, open, close) {
  const openIndex = lower(text).indexOf(lower(open));
  if (openIndex < 0) return null;
  const rest = text.slice(openIndex + open.length);
  let boundary = rest.length;
  for (const terminator of ALL_TAGS) {
    if (lower(terminator) === lower(open)) continue;
    const index = lower(rest).indexOf(lower(terminator));
    if (index >= 0 && index < boundary) boundary = index;
  }
  return rest.slice(0, boundary).length ? rest.slice(0, boundary) : null;
}

function stripKnownTags(text) {
  let result = text;
  for (const tag of Object.values(TAGS)) {
    result = result.split(tag).join("").split(tag.toLowerCase()).join("");
  }
  return result;
}

function trimQuotes(value) {
  let text = value.trim();
  const pairs = [["\"", "\""], ["“", "”"], ["'", "'"], ["「", "」"], ["『", "』"], ["`", "`"]];
  let changed = true;
  while (changed) {
    changed = false;
    for (const [open, close] of pairs) {
      if (text.length >= 2 && text[0] === open && text[text.length - 1] === close) {
        text = text.slice(1, -1);
        changed = true;
      }
    }
  }
  return text.trim();
}

function isNoneToken(value) {
  const lowered = value.trim().replace(/[。.!！]+$/g, "").toLowerCase();
  return ["none", "n/a", "无", "没有", "なし"].includes(lowered);
}

function parseBullets(block) {
  if (!block) return [];
  return block
    .split("\n")
    .map((line) => {
      let value = line.trim();
      if (value.length > 0 && BULLETS.has(value[0])) value = value.slice(1).trim();
      value = value.split("**").join("");
      return trimQuotes(value);
    })
    .filter((value) => value.length > 0 && !isNoneToken(value));
}

function parseCorrectionLine(line) {
  let body = line.trim();
  if (body.length && BULLETS.has(body[0])) body = body.slice(1).trim();
  if (!body.length || isNoneToken(body)) return null;
  let head = body;
  let note = "";
  for (const separator of ["::", "|", "："]) {
    const index = head.indexOf(separator);
    if (index >= 0) {
      note = head.slice(index + separator.length).trim();
      head = head.slice(0, index).trim();
      break;
    }
  }
  let original = "";
  let corrected = head;
  for (const arrow of ["=>", "->", "→"]) {
    const index = head.indexOf(arrow);
    if (index >= 0) {
      original = head.slice(0, index).trim();
      corrected = head.slice(index + arrow.length).trim();
      break;
    }
  }
  original = trimQuotes(original);
  corrected = trimQuotes(corrected);
  if (!original && !corrected && !note) return null;
  return { original, corrected, note };
}

function parseCorrections(block) {
  return parseBullets(block).map(parseCorrectionLine).filter(Boolean);
}

function cleanOptional(value) {
  if (value === null || value === undefined) return null;
  const text = trimQuotes(stripKnownTags(value)).trim();
  if (!text.length || isNoneToken(text)) return null;
  return text;
}

function cleanReply(value) {
  if (value === null || value === undefined) return "";
  let text = stripKnownTags(value);
  text = text.split("**").join("");
  return trimQuotes(text).trim();
}

function parseJSONFallback(text) {
  if (!text.startsWith("{") || !text.endsWith("}")) return null;
  let object;
  try {
    object = JSON.parse(text);
  } catch {
    return null;
  }
  const reply = ["reply", "response", "answer", "text"].map((key) => object[key]).find((v) => typeof v === "string");
  if (!reply) return null;
  let corrections = [];
  if (Array.isArray(object.corrections) && object.corrections.length && typeof object.corrections[0] === "object") {
    corrections = object.corrections
      .map((entry) => ({
        original: entry.original || "",
        corrected: entry.corrected || "",
        note: entry.note || entry.explanation || "",
      }))
      .filter((entry) => entry.original || entry.corrected || entry.note);
  } else if (Array.isArray(object.corrections)) {
    corrections = object.corrections.map(parseCorrectionLine).filter(Boolean);
  }
  const followUps = (object.follow_ups || object.followups || []).filter((item) => !isNoneToken(item));
  return {
    reply: cleanReply(reply),
    translation: cleanOptional(object.translation),
    corrections,
    followUps,
  };
}

function parseTutorReply(raw) {
  const text = normalizeNewlines(raw);
  const trimmed = text.trim();
  const json = parseJSONFallback(trimmed);
  if (json) return json;
  if (!containsTag(text, TAGS.replyOpen)) {
    return { reply: stripKnownTags(trimmed).trim(), translation: null, corrections: [], followUps: [] };
  }
  const reply = section(text, TAGS.replyOpen, TAGS.replyClose) ?? section(text, TAGS.replyOpen, "\u0000");
  return {
    reply: cleanReply(reply),
    translation: cleanOptional(section(text, TAGS.translationOpen, TAGS.translationClose)),
    corrections: parseCorrections(section(text, TAGS.correctionsOpen, TAGS.correctionsClose)),
    followUps: parseBullets(section(text, TAGS.followUpOpen, TAGS.followUpClose)),
  };
}

function stripLeadingSpace(text) {
  let index = 0;
  while (index < text.length && " \t\n\r".includes(text[index])) index += 1;
  return text.slice(index);
}

class StreamingExtractor {
  constructor() {
    this.raw = "";
    this.plainTextMode = false;
    this.replyBody = "";
    this.emittedCount = 0;
  }

  push(delta) {
    if (!delta) return "";
    this.raw += delta;
    return this.drain(false);
  }

  finish() {
    if (this.plainTextMode || !containsTag(this.raw, TAGS.replyOpen)) {
      this.plainTextMode = true;
      this.replyBody = this.raw.trim();
    }
    return this.drain(true);
  }

  parsedReply() {
    return parseTutorReply(this.raw);
  }

  drain(flushAll) {
    if (!this.plainTextMode && !containsTag(this.raw, TAGS.replyOpen)) {
      const trimmed = this.raw.trim();
      const isTagPrefix = loweredStartsWith(TAGS.replyOpen, trimmed) || trimmed.length === 0;
      if (!isTagPrefix || trimmed.length > TAGS.replyOpen.length) {
        this.plainTextMode = true;
        this.replyBody = trimmed;
      } else {
        return "";
      }
    } else if (!this.plainTextMode) {
      const index = lower(this.raw).indexOf(lower(TAGS.replyOpen));
      if (index < 0) return "";
      const body = stripLeadingSpace(this.raw.slice(index + TAGS.replyOpen.length));
      const closeIndex = lower(body).indexOf(lower(TAGS.replyClose));
      this.replyBody = closeIndex < 0 ? body : body.slice(0, closeIndex);
    }

    let boundary;
    if (flushAll) boundary = this.replyBody.length;
    else if (!this.plainTextMode && !containsTag(this.replyBody, TAGS.replyClose)) boundary = safeBoundary(this.replyBody);
    else boundary = this.replyBody.length;

    const safeText = this.replyBody.slice(0, boundary);
    if (safeText.length <= this.emittedCount) return "";
    const fresh = safeText.slice(this.emittedCount);
    this.emittedCount = safeText.length;
    return fresh;
  }
}

function loweredStartsWith(text, prefix) {
  return lower(text).startsWith(lower(prefix));
}

function safeBoundary(body) {
  const headroom = TAGS.replyClose.length - 1;
  let index = body.length - Math.min(headroom, body.length);
  while (index < body.length) {
    const tail = lower(body.slice(index));
    if (loweredStartsWith(TAGS.replyClose, tail)) return index;
    index += 1;
  }
  return body.length;
}

// ---------------------------------------------------------------- SSE decode
class SSEDecoder {
  constructor() {
    this.buffer = "";
  }

  static payload(line) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) return null;
    const value = trimmed.slice(5).trim();
    return value.length ? value : null;
  }

  push(chunk) {
    this.buffer += chunk;
    const payloads = [];
    let index = this.buffer.search(/[\r\n]/);
    while (index >= 0) {
      const line = this.buffer.slice(0, index);
      let end = index + 1;
      if (this.buffer[end] === "\n") end += 1;
      this.buffer = this.buffer.slice(end);
      const payload = SSEDecoder.payload(line);
      if (payload) payloads.push(payload);
      index = this.buffer.search(/[\r\n]/);
    }
    return payloads;
  }

  flush() {
    const rest = this.buffer;
    this.buffer = "";
    if (!rest) return [];
    const payload = SSEDecoder.payload(rest);
    return payload ? [payload] : [];
  }
}

const deltaContent = (payload) => {
  try {
    const object = JSON.parse(payload);
    const choice = (object.choices || [])[0];
    if (!choice) return null;
    if (choice.delta && typeof choice.delta.content === "string") return choice.delta.content;
    if (typeof choice.text === "string") return choice.text;
    return null;
  } catch {
    return null;
  }
};

module.exports = { parseTutorReply, StreamingExtractor, SSEDecoder, deltaContent, TAGS, parseCorrectionLine, isNoneToken, trimQuotes, section, cleanReply, parseBullets };

// ------------------------------------------------------------------ checks
if (require.main === module) {
  const results = [];
  const check = (name, fn) => {
    try {
      fn();
      results.push({ name, ok: true });
    } catch (error) {
      results.push({ name, ok: false, message: error.message });
    }
  };
  const eq = (actual, expected, label = "") => {
    const a = JSON.stringify(actual);
    const b = JSON.stringify(expected);
    if (a !== b) throw new Error(`${label} expected ${b} but got ${a}`);
  };
  const ok = (value, label) => {
    if (!value) throw new Error(`${label} is falsy`);
  };

  const fullReply = [
    "[REPLY]",
    "Sure! Would you like it for here or to go?",
    "[/REPLY]",
    "[TRANSLATION]",
    "好的！您要在这里喝还是带走？",
    "[/TRANSLATION]",
    "[CORRECTIONS]",
    "- I want a coffee large => I'd like a large coffee :: 形容词顺序和点单语气",
    "- i go yesterday => I went yesterday :: 时态",
    "[/CORRECTIONS]",
    "[FOLLOWUP]",
    "- 试试这样说：Could I get a large latte?",
    "- 也可以说：for here, please.",
    "[/FOLLOWUP]",
  ].join("\n");

  check("parses all sections", () => {
    const reply = parseTutorReply(fullReply);
    eq(reply.reply, "Sure! Would you like it for here or to go?", "reply");
    eq(reply.translation, "好的！您要在这里喝还是带走？", "translation");
    eq(reply.corrections.length, 2, "corrections");
    eq(reply.corrections[0].corrected, "I'd like a large coffee", "corrected");
    eq(reply.corrections[0].note, "形容词顺序和点单语气", "note");
    eq(reply.followUps.length, 2, "followUps");
  });

  check("handles NONE tokens", () => {
    const reply = parseTutorReply("[REPLY]\nGreat job!\n[/REPLY]\n[TRANSLATION]\n做得好！\n[/TRANSLATION]\n[CORRECTIONS]\nNONE\n[/CORRECTIONS]\n[FOLLOWUP]\nNONE\n[/FOLLOWUP]");
    eq(reply.reply, "Great job!");
    eq(reply.corrections.length, 0);
    eq(reply.followUps.length, 0);
  });

  check("missing translation tag yields null", () => {
    const reply = parseTutorReply("[REPLY]\nHello there.\n[/REPLY]\n[CORRECTIONS]\nNONE\n[/CORRECTIONS]");
    eq(reply.reply, "Hello there.");
    eq(reply.translation, null);
  });

  check("unclosed tags stay readable", () => {
    const reply = parseTutorReply("[REPLY]\nこれはテストです。\n[TRANSLATION]\n这是测试。");
    eq(reply.reply, "これはテストです。");
    eq(reply.translation, "这是测试。");
  });

  check("plain answer without tags is the reply", () => {
    const reply = parseTutorReply("こんにちは、元気ですか。");
    eq(reply.reply, "こんにちは、元気ですか。");
    eq(reply.corrections.length, 0);
  });

  check("lowercase tags accepted", () => {
    const reply = parseTutorReply("[reply]\nHi!\n[/reply]\n[translation]\n你好！\n[/translation]");
    eq(reply.reply, "Hi!");
    eq(reply.translation, "你好！");
  });

  check("correction variants", () => {
    eq(parseCorrectionLine("- I has => I have :: 主谓一致").original, "I has");
    eq(parseCorrectionLine("- 私は学生を → 私は学生です :: 助词").corrected, "私は学生です");
    eq(parseCorrectionLine('- "I am agree" -> "I agree" :: 动词').corrected, "I agree");
    eq(parseCorrectionLine("- NONE"), null);
    eq(parseCorrectionLine("   "), null);
  });

  check("JSON answer fallback", () => {
    const raw = '{"reply":"How was your weekend?","translation":"你周末过得怎么样？","corrections":[{"original":"very like","corrected":"really like","note":"副词"}],"follow_ups":["试试这样说：It was fun."]}';
    const reply = parseTutorReply(raw);
    eq(reply.reply, "How was your weekend?");
    eq(reply.translation, "你周末过得怎么样？");
    eq(reply.corrections[0].corrected, "really like");
    eq(reply.followUps[0], "试试这样说：It was fun.");
  });

  check("strips stray quotes and leading noise from reply", () => {
    eq(parseTutorReply('[REPLY]\n"Hi there"\n[/REPLY]').reply, "Hi there");
    eq(parseTutorReply("### Hi there ###\n[REPLY]\nHi there\n[/REPLY]").reply, "Hi there");
  });

  check("streaming char-by-char equals final reply", () => {
    const stream = "[REPLY]\nHello! How are you today?\n[/REPLY]\n[TRANSLATION]\n你好！\n[/TRANSLATION]";
    const extractor = new StreamingExtractor();
    let spoken = "";
    for (const character of stream) spoken += extractor.push(character);
    spoken += extractor.finish();
    eq(spoken.trim(), "Hello! How are you today?");
    ok(!spoken.includes("["), "no tag leaked into speech");
  });

  check("nothing emitted before the tag is complete", () => {
    const extractor = new StreamingExtractor();
    eq(extractor.push("[REP"), "");
    eq(extractor.push("LY]\nHi"), "Hi");
  });

  check("plain-text stream falls back to whole answer", () => {
    const extractor = new StreamingExtractor();
    let spoken = "";
    for (const chunk of ["こんにちは", "、元気", "ですか。"]) spoken += extractor.push(chunk);
    spoken += extractor.finish();
    eq(spoken, "こんにちは、元気ですか。");
  });

  check("streamed parse equals whole parse", () => {
    const stream = "[REPLY]\nHi\n[/REPLY]\n[TRANSLATION]\n你好\n[/TRANSLATION]\n[CORRECTIONS]\n- a => b :: c\n[/CORRECTIONS]\n[FOLLOWUP]\n- hint\n[/FOLLOWUP]";
    const extractor = new StreamingExtractor();
    for (let i = 0; i < stream.length; i += 7) extractor.push(stream.slice(i, i + 7));
    extractor.finish();
    eq(extractor.parsedReply(), parseTutorReply(stream));
  });

  check("SSE decoder splits chunks and ignores noise", () => {
    const decoder = new SSEDecoder();
    const payloads = decoder.push(": ping\n\nevent: message\ndata: {\"a\":1}\n\ndata: [DONE]\n\n");
    eq(payloads, ['{"a":1}', "[DONE]"]);
  });

  check("SSE decoder reassembles a split line", () => {
    const decoder = new SSEDecoder();
    eq(decoder.push("da"), []);
    eq(decoder.push('ta: {"a":'), []);
    eq(decoder.push("1}\n"), ['{"a":1}']);
  });

  check("SSE decoder flush emits trailing line", () => {
    const decoder = new SSEDecoder();
    eq(decoder.push("data: tail"), []);
    eq(decoder.flush(), ["tail"]);
    eq(decoder.flush(), []);
  });

  check("delta extraction reads content and legacy text", () => {
    eq(deltaContent('{"choices":[{"delta":{"content":"你好"}}]}'), "你好");
    eq(deltaContent('{"choices":[{"text":"legacy"}]}'), "legacy");
    eq(deltaContent('{"choices":[{"delta":{"role":"assistant"}}]}'), null);
    eq(deltaContent("not json"), null);
  });

  const failed = results.filter((r) => !r.ok);
  for (const result of results) {
    console.log(`${result.ok ? "PASS" : "FAIL"}  ${result.name}${result.ok ? "" : "  -> " + result.message}`);
  }
  console.log(`\n${results.length - failed.length}/${results.length} protocol checks passed`);
  process.exit(failed.length ? 1 : 0);
}