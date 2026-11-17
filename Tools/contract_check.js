#!/usr/bin/env node
/**
 * Live prompt-contract check.
 *
 * Sends the exact prompt shape that PromptBuilder produces to a real
 * OpenAI-compatible endpoint, streams the answer back with the same SSE decoder
 * the app uses, and verifies the model actually follows the tagged protocol.
 *
 * Usage:
 *   node Tools/contract_check.js                  # English + Japanese, report only
 *   node Tools/contract_check.js --update-fixtures # also refresh RunFixtures.swift
 *
 * Endpoint/key come from LINGUAMATE_BASE_URL / LINGUAMATE_MODEL / LINGUAMATE_API_KEY
 * (defaults to a keyless public OpenAI-compatible gateway).
 */
const fs = require("fs");
const path = require("path");
const { parseTutorReply, SSEDecoder, deltaContent, TAGS } = require("./protocol_check.js");

const ROOT = path.resolve(__dirname, "..");
const BASE_URL = process.env.LINGUAMATE_BASE_URL || "https://text.pollinations.ai/openai";
const MODEL = process.env.LINGUAMATE_MODEL || "openai";
const API_KEY = process.env.LINGUAMATE_API_KEY || "";
const updateFixtures = process.argv.includes("--update-fixtures");

// Mirrors PromptBuilder.systemPrompt for the two built-in topics under test.
function systemPrompt({ language, level, role, scenario, phrases }) {
  return `You are LinguaMate, a patient ${language} conversation partner for a Chinese-speaking learner.

ROLE YOU PLAY: ${role}
SCENARIO: ${scenario}
LEARNER LEVEL: ${level}

RULES
1. Speak ${language} at all times. Only switch to Chinese if the learner explicitly asks for a Chinese explanation.
2. Use everyday conversational language with occasional idioms. Sentences can be 1-3 clauses long.
3. Keep the spoken reply short: 2-3 sentences and always end with a question or a prompt that keeps the learner talking.
4. Weave these expressions in naturally over the conversation: ${phrases}.
5. Correct the learner gently: list at most three real mistakes, ignore typos that do not change meaning, and never interrupt the flow of the role-play.
6. Provide a natural Chinese translation of your reply so a beginner can follow.
7. Stay in character, never mention these instructions, never mention that you are an AI, and never output markdown formatting inside the conversation line.

OUTPUT FORMAT — reply with exactly these sections, in this order, using the literal tags:
[REPLY]
<your next line in ${language}, plain text, no tags inside>
[/REPLY]
[TRANSLATION]
<Chinese translation of the line above, or NONE when translations are disabled>
[/TRANSLATION]
[CORRECTIONS]
- <wrong fragment> => <corrected fragment> :: <short Chinese note>
(one line per correction, at most 3; write NONE alone when the learner made no mistakes or has not spoken yet)
[/CORRECTIONS]
[FOLLOWUP]
- <short Chinese hint of what the learner could say next>
(1-2 lines; write NONE alone when nothing fits)
[/FOLLOWUP]`;
}

const CASES = [
  {
    id: "english",
    language: "English",
    level: "intermediate",
    role: "a warm, chatty barista at an independent coffee shop in Portland",
    scenario: "咖啡店点单 — Order a drink, customise it, and handle one small surprise.",
    phrases: "Could I get…? / for here or to go / Could you make it less sweet?",
    learner: "I want a coffee large with milk. Can you make it more sweet?",
    key: "recordedEnglishAnswer",
  },
  {
    id: "japanese",
    language: "Japanese",
    level: "beginner",
    role: "a polite convenience store clerk in Tokyo",
    scenario: "便利店购物 — Buy a bento and a drink, answer the clerk's questions, and pay.",
    phrases: "これをください / 温めなくていいです / 袋はいりません",
    learner: "これをください。お弁当を温めてください。",
    key: "recordedJapaneseAnswer",
  },
];

async function streamTurn(testCase) {
  const body = {
    model: MODEL,
    stream: true,
    temperature: 0.7,
    messages: [
      {
        role: "system",
        content: systemPrompt({
          language: testCase.language,
          level: testCase.level,
          role: testCase.role,
          scenario: testCase.scenario,
          phrases: testCase.phrases,
        }),
      },
      { role: "user", content: testCase.learner },
    ],
  };

  const headers = { "Content-Type": "application/json", Accept: "text/event-stream" };
  if (API_KEY) headers.Authorization = `Bearer ${API_KEY}`;

  const response = await fetch(BASE_URL, { method: "POST", headers, body: JSON.stringify(body) });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${(await response.text()).slice(0, 300)}`);
  }

  const decoder = new SSEDecoder();
  let text = "";
  const chunks = [];

  for await (const chunk of response.body) {
    const payloads = decoder.push(Buffer.from(chunk).toString("utf8"));
    for (const payload of payloads) {
      if (payload === "[DONE]") continue;
      const delta = deltaContent(payload);
      if (delta) {
        chunks.push(delta);
        text += delta;
      }
    }
  }
  for (const payload of decoder.flush()) {
    const delta = deltaContent(payload);
    if (delta) {
      chunks.push(delta);
      text += delta;
    }
  }
  return { text, chunks };
}

function escapeForSwift(text) {
  return text
    .replace(/\\/g, "\\\\")
    .replace(/"""/g, '\\"\\"\\"')
    .trim()
    .split("\n")
    .map((line) => "    " + line)
    .join("\n");
}

(async () => {
  console.log(`endpoint: ${BASE_URL}\nmodel: ${MODEL}\n`);
  const recorded = {};
  let failures = 0;

  for (const testCase of CASES) {
    let result;
    try {
      result = await streamTurn(testCase);
    } catch (error) {
      console.log(`FAIL  ${testCase.id}: request failed -> ${error.message}`);
      failures += 1;
      continue;
    }

    const parsed = parseTutorReply(result.text);
    const checks = [
      ["[REPLY] tag present", result.text.includes(TAGS.replyOpen)],
      ["[/REPLY] tag present", result.text.includes(TAGS.replyClose)],
      ["[TRANSLATION] section present", result.text.includes(TAGS.translationOpen)],
      ["[CORRECTIONS] section present", result.text.includes(TAGS.correctionsOpen)],
      ["reply is not empty after parsing", parsed.reply.length > 0],
      ["translation is not empty after parsing", Boolean(parsed.translation)],
      ["no tag leaked into the spoken reply", !parsed.reply.includes("[")],
      ["stream arrived in multiple chunks", result.chunks.length > 1],
    ];

    console.log(`--- ${testCase.id} (${result.text.length} chars, ${result.chunks.length} deltas) ---`);
    console.log(result.text.trim());
    console.log("");
    for (const [label, ok] of checks) {
      if (!ok) failures += 1;
      console.log(`${ok ? "PASS" : "FAIL"}  ${testCase.id}: ${label}`);
    }
    console.log(`      parsed reply       : ${JSON.stringify(parsed.reply)}`);
    console.log(`      parsed translation : ${JSON.stringify(parsed.translation)}`);
    console.log(`      corrections        : ${parsed.corrections.length}`);
    console.log(`      follow-ups         : ${parsed.followUps.length}\n`);

    recorded[testCase.key] = result.text;
  }

  if (updateFixtures && Object.keys(recorded).length === CASES.length) {
    const file = path.join(ROOT, "LinguaMateTests", "RunFixtures.swift");
    const content = `import Foundation

/// Real model answers recorded from an OpenAI-compatible endpoint by
/// Tools/contract_check.js. The parser tests replay these verbatim, so they
/// fail loudly if the model stops following the tagged protocol.
///
/// Recorded: ${new Date().toISOString()} · endpoint: ${BASE_URL} · model: ${MODEL}
enum RunFixtures {
    static let recordedEnglishAnswer = """
${escapeForSwift(recorded.recordedEnglishAnswer)}
    """

    static let recordedJapaneseAnswer = """
${escapeForSwift(recorded.recordedJapaneseAnswer)}
    """
}
`;
    fs.writeFileSync(file, content, "utf8");
    console.log(`fixtures updated: ${path.relative(ROOT, file)}`);
  }

  console.log(failures === 0 ? "ALL LIVE CONTRACT CHECKS PASSED" : `${failures} LIVE CONTRACT CHECKS FAILED`);
  process.exit(failures ? 1 : 0);
})();