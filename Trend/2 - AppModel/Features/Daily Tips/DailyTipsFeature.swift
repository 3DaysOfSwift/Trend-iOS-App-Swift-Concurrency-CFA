// © www.3DaysOfSwiftConcurrency.com. All rights reserved.

import Foundation
import Observation

struct WellnessTip: Identifiable, Sendable, Equatable {
    let id: Int
    let text: String
}

struct WhatNextGuidance: Sendable, Equatable {
    let opening: String
    let identity: String
    let progression: String
    let closing: String

    static let standard = WhatNextGuidance(
        opening: "Eat fruits. Stop eating poison. Worship the body you live in.",
        identity: "You are the consciousness that lives inside the mind, alongside the subconscious mind. You are the soul and the spirit—those terms mean you. You live in a body; you are not the body.",
        progression: "Your thoughts become emotions. Your emotions become actions. Your actions become habits. Your habits become your personality.",
        closing: "Think about that."
    )
}

@MainActor
@Observable
final class DailyTipsFeature {
    private enum Key {
        static let remainingTipIDs = "remainingWellnessTipIDs"
        static let remainingPepTalkIDs = "remainingPepTalkIDs"
        static let remainingPoisonPointIDs = "remainingPoisonPointIDs"
        static let remainingEvolutionPointIDs = "remainingEvolutionPointIDs"
        static let remainingFastingPointIDs = "remainingFastingPointIDs"
        static let refreshCount = "dailyContentRefreshCount"
    }

    private let defaults: UserDefaults
    private let catalog: [WellnessTip]
    private let calendar: Calendar
    private let currentDate: @MainActor () -> Date
    private(set) var currentFastingSuggestion: WellnessTip?

    init(
        defaults: UserDefaults = .standard,
        catalog: [WellnessTip] = WellnessTip.catalog,
        calendar: Calendar = .current,
        currentDate: @escaping @MainActor () -> Date
    ) {
        self.defaults = defaults
        self.catalog = catalog
        self.calendar = calendar
        self.currentDate = currentDate
    }

    func nextTip() -> WellnessTip {
        draw(from: catalog, key: Key.remainingTipIDs)
    }

    func nextPepTalk() -> WellnessTip {
        draw(from: WellnessTip.pepTalkCatalog, key: Key.remainingPepTalkIDs)
    }

    func nextPoisonPoint() -> WellnessTip {
        draw(from: WellnessTip.poisonPointCatalog, key: Key.remainingPoisonPointIDs)
    }

    func nextEvolutionPoint() -> WellnessTip {
        draw(from: WellnessTip.evolutionCatalog, key: Key.remainingEvolutionPointIDs)
    }

    func whatNext(on date: Date? = nil) -> WhatNextGuidance? {
        calendar.component(.weekday, from: date ?? currentDate()) == 2 ? .standard : nil
    }

    /// Selects the optional fasting content for the current refresh cycle.
    func refresh() {
        let refreshCount = defaults.integer(forKey: Key.refreshCount) + 1
        defaults.set(refreshCount, forKey: Key.refreshCount)
        currentFastingSuggestion = refreshCount.isMultiple(of: 10)
            ? draw(from: WellnessTip.fastingCatalog, key: Key.remainingFastingPointIDs)
            : nil
    }

    private func draw(from catalog: [WellnessTip], key: String) -> WellnessTip {
        var remainingIDs = defaults.array(forKey: key) as? [Int] ?? []
        if remainingIDs.isEmpty {
            remainingIDs = catalog.map(\.id).shuffled()
        }

        let nextID = remainingIDs.removeLast()
        defaults.set(remainingIDs, forKey: key)
        return catalog.first(where: { $0.id == nextID }) ?? catalog[0]
    }

    var catalogCount: Int { catalog.count }
    var pepTalkCatalogCount: Int { WellnessTip.pepTalkCatalog.count }
    var poisonPointCatalogCount: Int { WellnessTip.poisonPointCatalog.count }
    var evolutionCatalogCount: Int { WellnessTip.evolutionCatalog.count }
    var fastingCatalogCount: Int { WellnessTip.fastingCatalog.count }
    var remainingCount: Int {
        (defaults.array(forKey: Key.remainingTipIDs) as? [Int])?.count ?? 0
    }
    var remainingPepTalkCount: Int {
        (defaults.array(forKey: Key.remainingPepTalkIDs) as? [Int])?.count ?? 0
    }
    var remainingPoisonPointCount: Int {
        (defaults.array(forKey: Key.remainingPoisonPointIDs) as? [Int])?.count ?? 0
    }
    var remainingEvolutionPointCount: Int {
        (defaults.array(forKey: Key.remainingEvolutionPointIDs) as? [Int])?.count ?? 0
    }
}

extension WellnessTip {
    static let catalog: [WellnessTip] = [
        "Lectins are carbohydrate-binding proteins found throughout nature, including in many plants.",
        "Plants use an astonishing range of protective compounds; lectins are only one part of that story.",
        "The Plant Paradox philosophy emphasizes noticing how particular foods make you feel.",
        "Lectin content varies widely by plant, variety, preparation method, and serving size.",
        "Raw or undercooked kidney beans can cause illness; cook them thoroughly before eating.",
        "Boiling beans reduces active lectins far more effectively than eating them raw.",
        "A slow cooker may not get raw kidney beans hot enough to make them safe—boil them properly first.",
        "Soaking dried beans, discarding the water, and cooking in fresh water is a useful preparation routine.",
        "Pressure cooking is one practical way people reduce lectins in properly prepared legumes.",
        "Fermentation changes food chemistry and has been used by cultures around the world for centuries.",
        "Peeling and deseeding certain vegetables fits the Plant Paradox approach, though individual tolerance varies.",
        "Lectin-containing foods are not automatically unhealthy; preparation and your overall diet matter.",
        "There is no strong human evidence that everyone benefits from avoiding all dietary lectins.",
        "Cooked legumes provide fibre, protein, vitamins, and minerals for many people.",
        "If a food repeatedly causes symptoms, record the pattern and discuss it with a qualified clinician.",
        "A food diary can reveal patterns that memory tends to miss.",
        "One meal never defines your health; repeated habits shape the trend.",
        "Build meals around foods you enjoy enough to eat consistently.",
        "Try filling roughly half your plate with a variety of vegetables.",
        "Protein can make a meal more satisfying and help preserve muscle during weight loss.",
        "Fibre-rich foods can support fullness and digestive health.",
        "Extra-virgin olive oil can add flavour, helping simple vegetables feel like a real meal.",
        "Leafy greens are an easy way to add colour, texture, and micronutrients.",
        "Cruciferous vegetables include broccoli, cauliflower, cabbage, and Brussels sprouts.",
        "Fresh herbs can make a simple meal vivid without relying on lots of sugar or salt.",
        "Mushrooms bring savoury flavour and work well in plant-forward meals.",
        "Avocado offers fibre and unsaturated fat; portion still matters when weight is the goal.",
        "Nuts are satisfying and nutrient-dense, so a small handful may be enough.",
        "Seeds are nutrient-dense foods; claims that all seeds are harmful oversimplify the evidence.",
        "Choose dietary rules that improve your life rather than making every meal stressful.",
        "Eat slowly enough to notice the point where hunger begins to fade.",
        "Pause halfway through a meal and check whether you are still hungry.",
        "Serve food onto a plate instead of eating from the packet when portions are hard to judge.",
        "A smaller plate can make a sensible portion look and feel more complete.",
        "Plan tomorrow’s first meal before hunger makes the decision for you.",
        "Keep one quick, nourishing meal available for days when energy is low.",
        "Frozen vegetables are convenient, nutritious, and unlikely to be forgotten at the back of the fridge.",
        "Read ingredient lists for awareness, not perfection.",
        "Minimally processed food is a helpful direction, not a moral score.",
        "Water is an excellent default drink.",
        "Thirst and hunger can feel similar; a glass of water can be a useful pause.",
        "Sugary drinks can add substantial energy without providing much fullness.",
        "Alcohol can affect sleep, appetite, and food choices as well as adding calories.",
        "Unsweetened tea can turn a snack impulse into a calming five-minute ritual.",
        "Sleep supports appetite regulation, recovery, mood, and decision-making.",
        "A consistent wake time can be as important as a consistent bedtime.",
        "Dimmer evening light can help signal that the day is winding down.",
        "A short walk after a meal can be a gentle, repeatable habit.",
        "Movement does not have to be intense to count.",
        "Strength training helps preserve and build muscle, which matters during weight change.",
        "Choose exercise you can imagine repeating next month.",
        "Five minutes of movement is infinitely more useful than a perfect workout that never happens.",
        "Attach a new habit to an existing one: walk after lunch, or prepare vegetables after making coffee.",
        "Make the helpful choice visible and the unhelpful choice slightly less convenient.",
        "A prepared kitchen makes tomorrow’s decisions easier.",
        "Shopping with a list can reduce impulse purchases and forgotten ingredients.",
        "Do not shop very hungry if that reliably changes what lands in your basket.",
        "Batch-cook one component, not necessarily seven identical meals.",
        "Leftover roasted vegetables can become tomorrow’s salad, omelette, or soup.",
        "Soup can be a comforting way to combine vegetables, protein, and fluid.",
        "Season generously with spices, citrus, vinegar, garlic, and herbs.",
        "Acid—such as lemon or vinegar—can brighten food without adding much energy.",
        "Texture matters: combine something crisp, something tender, and something creamy.",
        "Try one unfamiliar vegetable this week rather than rebuilding your entire diet overnight.",
        "Variety helps make nutritious eating sustainable and enjoyable.",
        "Corn has been eaten and selectively bred by humans for thousands of years; sweeping evolutionary claims are misleading.",
        "Oats have a long food history and can be nutritious; whether you include them is a personal dietary choice.",
        "Historical class associations do not determine whether a food is healthy.",
        "Porridge can be a satisfying whole-grain breakfast for people who tolerate and enjoy it.",
        "Traditional preparation methods often arose from practical lessons about safety, storage, and flavour.",
        "Curiosity is more useful than fear when learning about food.",
        "Be cautious when one ingredient is blamed for a very wide range of unrelated symptoms.",
        "A compelling nutrition story is not the same thing as strong clinical evidence.",
        "Personal experience matters, but it cannot prove that a rule applies to everyone.",
        "If you remove a major food group, consider professional guidance to keep your diet nutritionally complete.",
        "Weight naturally fluctuates with hydration, salt, digestion, hormones, and time of day.",
        "A single higher reading is feedback, not failure.",
        "Weighing under similar conditions makes comparisons more meaningful.",
        "Look at the direction across several readings instead of judging one number.",
        "A plateau can be information: portions, movement, sleep, and consistency are useful places to look.",
        "Very rapid weight loss is not automatically better or more sustainable.",
        "A modest, repeatable change usually beats an extreme short-lived rule.",
        "Celebrate behaviours you control, not only numbers that fluctuate.",
        "Use neutral language about food: choices are more useful than labels such as good or bad.",
        "Self-criticism rarely improves the next decision; specific plans often do.",
        "If today went off-plan, the next meal is a fresh decision—not next Monday.",
        "Set an environment goal: put fruit where you can see it or vegetables at eye level.",
        "Decide what ‘enough’ looks like before serving a favourite energy-dense food.",
        "Share your goal with someone who supports you without policing you.",
        "Social meals matter; a sustainable approach leaves room for connection and enjoyment.",
        "Eat without a screen occasionally and notice flavour, pace, and fullness.",
        "Stress can change appetite in either direction; noticing the pattern is the first step.",
        "A brief breathing pause can create space between an urge and an action.",
        "Keep your next action tiny enough that it feels almost too easy.",
        "Ask: what would make the healthy choice easier by ten percent today?",
        "Your goal is not a flawless line—it is a healthier long-term direction.",
        "Consistency is built by returning after disruption, not by avoiding disruption forever.",
        "Use Trend as a compass, not a verdict on your worth.",
        "Nutrition needs differ; pregnancy, illness, medication, and eating-disorder history deserve individual clinical advice.",
        "The most useful diet is safe, nutritionally adequate, enjoyable, and sustainable for you."
    ].enumerated().map { WellnessTip(id: $0.offset + 1, text: $0.element) }

    static var pepTalkCatalog: [WellnessTip] {
        let reminders = [
            "You showed up. That is how change starts.",
            "A number cannot measure your courage or your worth.",
            "Today needs one useful decision, not a perfect performance.",
            "You are collecting information, not sitting an exam.",
            "Small actions become powerful when you repeat them.",
            "A difficult reading is a compass, never a character judgment.",
            "Your next choice still belongs entirely to you.",
            "Consistency means returning, especially after an imperfect day.",
            "You do not need motivation before taking one tiny step.",
            "Progress can be quiet before it becomes visible.",
            "Treat yourself like someone you are responsible for helping.",
            "You have already interrupted autopilot by checking in.",
            "One calm adjustment beats an afternoon of self-criticism.",
            "The long-term trend is built from ordinary moments like this.",
            "You can be proud of the process while still wanting change.",
            "There is no ruined day; there is only the next decision.",
            "Patience is active when it keeps you doing the basics.",
            "Your body is adapting, fluctuating, and working—not betraying you.",
            "Make today's promise small enough that you will keep it.",
            "You are allowed to learn what works instead of already knowing."
        ]
        let invitations = [
            "Now choose one kind thing to do for tomorrow's you.",
            "Take a breath, lift your head, and continue.",
            "Let this check-in make the next choice clearer.",
            "Pick the easiest helpful action and begin there.",
            "Keep the lesson and leave the drama behind."
        ]
        return reminders.flatMap { reminder in
            invitations.map { "\(reminder) \($0)" }
        }.enumerated().map { WellnessTip(id: $0.offset + 1, text: $0.element) }
    }

    static var poisonPointCatalog: [WellnessTip] {
        let actions = [
            "Never taste raw or undercooked kidney beans; proper boiling prevents lectin poisoning.",
            "Wash hands and preparation surfaces after handling raw meat, fish, or eggs.",
            "Keep raw food separate from ready-to-eat food to reduce cross-contamination.",
            "Refrigerate perishable leftovers promptly rather than leaving them at room temperature.",
            "Use safe cooking temperatures; colour alone cannot always confirm that food is safe.",
            "Discard food with unexpected mould unless authoritative guidance says that food can be trimmed safely.",
            "Do not use smell alone to decide whether stored food is safe.",
            "Avoid tobacco and nicotine products; there is no harmless level of smoking.",
            "Alcohol can affect sleep, appetite, judgment, and long-term health—less is generally safer.",
            "Check medicine and supplement combinations with a pharmacist instead of assuming natural means safe.",
            "Supplements can contain active compounds and are not substitutes for a varied diet.",
            "Ventilate rooms when using strong cleaning products and never mix bleach with ammonia or acids.",
            "Wash fruit and vegetables under running water; soap and household cleaners are not needed on produce.",
            "If drinking water safety is uncertain, follow current local public-health advice.",
            "Frequently eating foods high in salt can raise blood-pressure risk for many people.",
            "Sugary drinks deliver energy quickly and often provide little lasting fullness.",
            "Very restrictive diets can create nutritional gaps; major exclusions deserve professional guidance.",
            "Repeated vomiting, fainting, or severe weakness during weight loss needs medical attention.",
            "Online certainty is not evidence—check dramatic health claims before changing your diet.",
            "Fear is a poor nutrition plan; focus on specific, credible risks and practical safeguards."
        ]
        let prompts = [
            "Protect yourself today:",
            "A useful safety reset:",
            "Remove one avoidable risk:",
            "Evidence over fear:",
            "Your body deserves this safeguard:"
        ]
        return actions.flatMap { action in
            prompts.map { "\($0) \(action)" }
        }.enumerated().map { WellnessTip(id: $0.offset + 1, text: $0.element) }
    }

    static var evolutionCatalog: [WellnessTip] {
        let subjects: [(String, String)] = [
            ("wild fruit", "Primate and early-hominin evidence supports a long relationship with varied fruits."),
            ("leafy plants", "Leaves and other plant parts were available long before agriculture."),
            ("roots and tubers", "Underground storage organs offered seasonal energy, especially after processing or cooking."),
            ("cooked starch", "Cooking makes many starches easier to digest, and starch likely contributed useful energy."),
            ("meat", "Animal foods entered hominin diets long ago, but their importance varied across time and place."),
            ("fish and shellfish", "Aquatic foods were valuable where geography and technology made them accessible."),
            ("insects", "Insects are nutrient-dense foods eaten by humans and other primates in many environments."),
            ("nuts", "Nuts provide concentrated energy, but availability and the tools needed to open them varied."),
            ("seeds", "Humans can digest many prepared seeds; one category cannot describe every species or preparation."),
            ("eggs", "Eggs are nutrient-dense, opportunistic foods rather than evidence of one universal ancestral menu."),
            ("honey", "Honey offered rare concentrated carbohydrate and remains prized by some foraging societies."),
            ("cucumber", "Cucumber provides water and nutrients, but low energy density makes it unlikely to have fueled us alone."),
            ("tomato", "Tomatoes are fruits domesticated relatively recently; ripe tomatoes are ordinary foods, not proven memory poisons."),
            ("corn", "Maize was domesticated thousands—not millions—of years ago, and populations can still adapt culturally and biologically."),
            ("oats", "Oats became a cultivated staple recently in evolutionary time but can still be nutritious food."),
            ("fermented food", "Microbes and human food traditions can transform digestibility, flavour, and storage life."),
            ("milk", "Adult lactose tolerance evolved relatively recently in some populations and not in others."),
            ("dead cats", "There is no evidence that cats were a defining fuel of human evolution; a possibility is not proof."),
            ("one perfect food", "Human survival is better explained by dietary flexibility than dependence on one ingredient."),
            ("a varied omnivorous diet", "Evidence shows enormous ecological and cultural variation rather than one fixed ancestral menu.")
        ]
        return subjects.flatMap { food, evidence in
            [
                "Did we evolve eating \(food)? \(evidence)",
                "Could \(food) alone have powered human life? \(evidence)",
                "Does being able to digest \(food) prove it is our ideal food? No—ability, adaptation, and optimal health are different questions. \(evidence)",
                "What changed when humans encountered \(food)? \(evidence)",
                "Would every ancestral population have eaten \(food)? Geography, season, technology, and culture made diets remarkably diverse. \(evidence)"
            ]
        }.enumerated().map { WellnessTip(id: $0.offset + 1, text: $0.element) }
    }

    static let fastingCatalog: [WellnessTip] = [
        "Three meals a day is a cultural pattern, not a universal biological command. Some adults explore a shorter daily eating window, but it is optional—not a requirement.",
        "An overnight pause between dinner and breakfast is already a form of fasting. There is no need to begin with an extreme schedule.",
        "Fasting does not make digestion switch off completely, but spacing meals can give you a break from constant decisions and grazing.",
        "Meal timing is only one part of health. Food quality, total intake, sleep, movement, medication, and individual needs still matter.",
        "Feeling dizzy, faint, confused, or unwell is not a badge of discipline. Stop fasting and seek appropriate help.",
        "If you use insulin or glucose-lowering medicine, fasting can cause dangerous blood-sugar changes. Plan it only with clinical guidance.",
        "Fasting is generally unsuitable during pregnancy or breastfeeding, for children, and for people with a current or past eating disorder.",
        "Longer is not automatically better. A sustainable overnight interval may be more useful than an aggressive fast followed by overeating.",
        "There is no credible evidence that the Rockefeller family invented three meals a day. Meal patterns developed differently across cultures and history.",
        "Try asking whether you are hungry, thirsty, bored, stressed, or simply following the clock. Awareness can be valuable even if you never fast."
    ].enumerated().map { WellnessTip(id: $0.offset + 1, text: $0.element) }
}
