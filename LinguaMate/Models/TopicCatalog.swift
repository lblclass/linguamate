import Foundation

/// Built-in conversation topics. Static data keeps the picker instant and
/// offline, and gives the model a well-defined role for every session.
enum TopicCatalog {
    static func topics(for language: SupportedLanguage) -> [ConversationTopic] {
        switch language {
        case .english:
            return englishTopics
        case .japanese:
            return japaneseTopics
        }
    }

    static func topic(id: String, language: SupportedLanguage) -> ConversationTopic? {
        topics(for: language).first { $0.id == id }
    }

    static func categories(for language: SupportedLanguage) -> [String] {
        var seen: [String] = []
        for topic in topics(for: language) where !seen.contains(topic.category) {
            seen.append(topic.category)
        }
        return seen
    }

    static let englishTopics: [ConversationTopic] = [
        ConversationTopic(
            id: "en-coffee",
            language: .english,
            category: "生活日常",
            title: "咖啡店点单",
            emoji: "☕️",
            summary: "在咖啡店点一杯饮料，问清甜度和杯型。",
            role: "a warm, chatty barista at an independent coffee shop in Portland",
            goal: "Order a drink, customise it (size, milk, sweetness), and handle one small surprise (a sold-out item).",
            openingLine: "Hi there! Welcome in — what can I get started for you today?",
            keyPhrases: ["Could I get…?", "for here or to go", "Could you make it less sweet?"]
        ),
        ConversationTopic(
            id: "en-intro",
            language: .english,
            category: "生活日常",
            title: "自我介绍",
            emoji: "🙋",
            summary: "第一次见面互相认识，聊聊工作和爱好。",
            role: "a friendly new colleague chatting during a coffee break",
            goal: "Introduce yourself, talk about your job, city, and hobbies, and ask the partner about theirs.",
            openingLine: "Hey, I don't think we've met yet — I'm Sam. What's your name?",
            keyPhrases: ["I work as…", "I'm really into…", "How about you?"]
        ),
        ConversationTopic(
            id: "en-interview",
            language: .english,
            category: "职场学习",
            title: "求职面试",
            emoji: "💼",
            summary: "模拟一轮英文面试，练习自我介绍与项目经历。",
            role: "a hiring manager conducting a first-round interview for a software engineering role",
            goal: "Answer typical interview questions with concrete examples, and ask one good question at the end.",
            openingLine: "Thanks for coming in today. Could you start by telling me a bit about yourself?",
            keyPhrases: ["My main responsibility was…", "One challenge I faced was…", "Could you tell me more about the team?"]
        ),
        ConversationTopic(
            id: "en-airport",
            language: .english,
            category: "出行旅行",
            title: "机场值机",
            emoji: "✈️",
            summary: "值机、托运行李、选座位，应对航班延误。",
            role: "a check-in agent at an international airport counter",
            goal: "Check in, discuss baggage and seat preference, and react to a schedule change.",
            openingLine: "Good morning! May I see your passport and booking reference, please?",
            keyPhrases: ["I'd like a window seat", "I have one bag to check", "Is the flight delayed?"]
        ),
        ConversationTopic(
            id: "en-hotel",
            language: .english,
            category: "出行旅行",
            title: "酒店入住",
            emoji: "🏨",
            summary: "办理入住，反馈房间问题，申请延迟退房。",
            role: "a front-desk receptionist at a city hotel",
            goal: "Check in, report a problem with the room, and negotiate a late checkout.",
            openingLine: "Good evening, welcome to the Riverside Hotel. Do you have a reservation with us?",
            keyPhrases: ["I have a reservation under…", "The air conditioning isn't working", "Would late checkout be possible?"]
        ),
        ConversationTopic(
            id: "en-doctor",
            language: .english,
            category: "生活日常",
            title: "看病问诊",
            emoji: "🩺",
            summary: "向医生描述症状、持续时间和用药情况。",
            role: "a patient and calm general practitioner at a clinic",
            goal: "Describe symptoms clearly (duration, severity, triggers) and understand the advice given.",
            openingLine: "Hello, please have a seat. So, what brings you in today?",
            keyPhrases: ["I've had a sore throat for three days", "It hurts when I…", "Do I need any tests?"]
        ),
        ConversationTopic(
            id: "en-smalltalk",
            language: .english,
            category: "生活日常",
            title: "天气闲聊",
            emoji: "🌤",
            summary: "电梯里、排队时的日常寒暄。",
            role: "a neighbour you keep running into in the elevator",
            goal: "Practise light small talk: weather, weekend, local news, then a graceful exit.",
            openingLine: "Morning! Bit chilly today, isn't it? Did you get any sun over the weekend?",
            keyPhrases: ["Lovely weather, isn't it?", "How was your weekend?", "Anyway, I'd better run."]
        ),
        ConversationTopic(
            id: "en-plans",
            language: .english,
            category: "休闲兴趣",
            title: "周末计划",
            emoji: "🗓",
            summary: "和朋友商量周末安排，约定时间地点。",
            role: "a close friend planning the weekend together",
            goal: "Suggest activities, negotiate time and place, and confirm the plan.",
            openingLine: "Finally Friday! Any plans for the weekend, or are you free to hang out?",
            keyPhrases: ["How about…?", "That works for me", "Shall we meet at six?"]
        ),
        ConversationTopic(
            id: "en-restaurant",
            language: .english,
            category: "出行旅行",
            title: "餐厅点餐",
            emoji: "🍽",
            summary: "点菜、问推荐、处理过敏和结账。",
            role: "an attentive server at a busy bistro",
            goal: "Order a starter and a main, ask about ingredients and allergies, and pay the bill.",
            openingLine: "Good evening! Here are your menus. Can I start you off with something to drink?",
            keyPhrases: ["What would you recommend?", "I'm allergic to…", "Could we get the bill, please?"]
        ),
        ConversationTopic(
            id: "en-shopping",
            language: .english,
            category: "生活日常",
            title: "退换货",
            emoji: "🛍",
            summary: "带小票退货，说明原因并争取换货。",
            role: "a customer service assistant at a clothing store",
            goal: "Explain the problem with the item, show the receipt, and ask for an exchange or refund.",
            openingLine: "Hi, welcome in. How can I help you today?",
            keyPhrases: ["I'd like to return this", "It doesn't fit properly", "Could I exchange it for a larger size?"]
        )
    ]

    static let japaneseTopics: [ConversationTopic] = [
        ConversationTopic(
            id: "ja-konbini",
            language: .japanese,
            category: "生活日常",
            title: "便利店购物",
            emoji: "🏪",
            summary: "买便当、加热、要不要筷子，全靠这几句。",
            role: "a polite convenience store clerk in Tokyo",
            goal: "Buy a bento and a drink, answer the clerk's questions, and pay.",
            openingLine: "いらっしゃいませ。お弁当は温めますか。",
            keyPhrases: ["これをください", "温めなくていいです", "袋はいりません"]
        ),
        ConversationTopic(
            id: "ja-ramen",
            language: .japanese,
            category: "生活日常",
            title: "拉面店点单",
            emoji: "🍜",
            summary: "用食券机点单，选面的硬度和汤的浓度。",
            role: "a brisk ramen shop owner taking your order",
            goal: "Order ramen, choose noodle firmness and broth richness, and ask for the bill.",
            openingLine: "はい、お待たせしました。ご注文は?",
            keyPhrases: ["麺はかためでお願いします", "スープは薄めで", "お会計をお願いします"]
        ),
        ConversationTopic(
            id: "ja-jikoshoukai",
            language: .japanese,
            category: "职场学习",
            title: "自我介绍",
            emoji: "🙇",
            summary: "在日本职场/学校的第一次自我介绍。",
            role: "a colleague greeting a new team member during a morning stand-up",
            goal: "Give a short self-introduction (name, role, hobby) and answer one follow-up question.",
            openingLine: "おはようございます。今日から一緒に働く方ですね。簡単に自己紹介をお願いします。",
            keyPhrases: ["はじめまして、〜と申します", "趣味は〜です", "よろしくお願いいたします"]
        ),
        ConversationTopic(
            id: "ja-densha",
            language: .japanese,
            category: "出行旅行",
            title: "电车问路",
            emoji: "🚃",
            summary: "在车站问路、确认换乘和乘车时间。",
            role: "a station attendant helping a traveller",
            goal: "Ask which line and platform to use, whether a transfer is needed, and how long it takes.",
            openingLine: "はい、どうされましたか。",
            keyPhrases: ["すみません、〜へはどう行けばいいですか", "何番線ですか", "乗り換えは必要ですか"]
        ),
        ConversationTopic(
            id: "ja-baito",
            language: .japanese,
            category: "职场学习",
            title: "打工面试",
            emoji: "💼",
            summary: "便利店／餐厅兼职面试的常见问答。",
            role: "a store manager interviewing for a part-time position",
            goal: "Explain availability, experience and motivation, and confirm the next steps.",
            openingLine: "お待たせしました。では、簡単に自己紹介からお願いします。",
            keyPhrases: ["週に三日入れます", "接客の経験があります", "いつから働けますか"]
        ),
        ConversationTopic(
            id: "ja-byouin",
            language: .japanese,
            category: "生活日常",
            title: "医院看病",
            emoji: "🏥",
            summary: "描述症状、持续时间和过敏史。",
            role: "a gentle doctor at a small clinic",
            goal: "Describe your symptoms, duration and pain level, and understand the instructions.",
            openingLine: "おはようございます。今日はどうされましたか。",
            keyPhrases: ["三日ほど前から咳が出ます", "熱はありません", "薬にアレルギーがあります"]
        ),
        ConversationTopic(
            id: "ja-onsen",
            language: .japanese,
            category: "出行旅行",
            title: "温泉旅馆",
            emoji: "♨️",
            summary: "入住温泉旅馆，问晚餐时间和温泉规则。",
            role: "a polite okami (innkeeper) at a countryside onsen ryokan",
            goal: "Check in, ask about dinner time, the bath rules, and a late checkout.",
            openingLine: "いらっしゃいませ。本日はご宿泊ですね。お荷物をお預かりします。",
            keyPhrases: ["夕食は何時ですか", "お風呂は何時まで入れますか", "チェックアウトは何時ですか"]
        ),
        ConversationTopic(
            id: "ja-kaiwa-weather",
            language: .japanese,
            category: "生活日常",
            title: "天气寒暄",
            emoji: "🌦",
            summary: "日式寒暄：天气、季节、最近怎么样。",
            role: "a neighbour you meet at the mailbox",
            goal: "Practise seasonal greetings and light small talk, then wrap up politely.",
            openingLine: "あら、こんにちは。今日はいい天気ですね。お元気でしたか。",
            keyPhrases: ["いい天気ですね", "最近どうですか", "お先に失礼します"]
        ),
        ConversationTopic(
            id: "ja-anime",
            language: .japanese,
            category: "休闲兴趣",
            title: "聊聊动漫",
            emoji: "🎌",
            summary: "推荐作品、聊聊喜欢的角色。",
            role: "a fellow anime fan chatting in a cafe",
            goal: "Recommend and react to anime, compare favourites, and use casual forms.",
            openingLine: "最近何かアニメ見てる? おすすめあったら教えて。",
            keyPhrases: ["最近〜にはまっています", "どのキャラが好きですか", "おすすめは〜です"]
        ),
        ConversationTopic(
            id: "ja-sasoi",
            language: .japanese,
            category: "休闲兴趣",
            title: "约朋友出去玩",
            emoji: "🎉",
            summary: "约人看电影或吃饭，确认时间地点。",
            role: "a close friend figuring out weekend plans",
            goal: "Invite the friend out, agree on a time and place, and confirm politely.",
            openingLine: "今週末、何か予定ある? よかったら一緒にどうかな。",
            keyPhrases: ["よかったら一緒にどうですか", "土曜の午後はどうですか", "駅前に七時にどう?"]
        )
    ]
}