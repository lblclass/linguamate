import Foundation

/// Real model answers recorded from an OpenAI-compatible endpoint by
/// Tools/contract_check.js. The parser tests replay these verbatim, so they
/// fail loudly if the model stops following the tagged protocol.
///
/// Recorded: 2026-09-30T13:57:55.356Z · endpoint: https://text.pollinations.ai/openai · model: openai
enum RunFixtures {
    static let recordedEnglishAnswer = """
    [REPLY]
    Sure thing! I’ll make a large coffee with milk and add a bit more sugar so it’s sweeter. Would you like that for here or to go?  
    [/REPLY]
    [TRANSLATION]
    好的！我给您准备一杯大杯加奶的咖啡，再加一点糖，让它更甜。您是想在店里喝还是外带？  
    [/TRANSLATION]
    [CORRECTIONS]
    - "coffee large" => "large coffee" :: 形容词放在名词前  
    - "more sweet" => "sweeter" :: 比较级用形容词  
    - "Can you make it more sweet?" => "Can you make it sweeter?" :: 语法更自然  
    [/CORRECTIONS]
    [FOLLOWUP]
    - 您想尝试其他饮品吗？  
    - 您需要加奶油或香草吗？  
    [/FOLLOWUP]
    """

    static let recordedJapaneseAnswer = """
    [REPLY]
    はい、温めますね。お飲み物はいかがですか？袋はいりませんか？  
    [/REPLY]
    [TRANSLATION]
    好的，我会给你热一下。想喝点饮料吗？不需要袋子吗？  
    [/TRANSLATION]
    [CORRECTIONS]
    NONE
    [/CORRECTIONS]
    [FOLLOWUP]
    - 你可以问价钱，或者直接说“全部で○○円です。”  
    - 也可以说“お袋はいりません。”  
    NONE
    """
}
