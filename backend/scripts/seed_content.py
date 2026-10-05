"""DEVELOPMENT SEED CONTENT: creators, posts and stories about Bangladesh.

Everything here is invented sample text written for development so the app has
something to render. It is deliberately subjective and generic ("the light was
soft", "the lanes were quiet"): it states no facts, figures, dates, histories,
opening hours, prices or travel advice, and none of it is verified information
or real user content. Accounts are `seed_*` with a "[Seed]" display name and
every story ends with a disclaimer line.
"""

SEED_PASSWORD = "seed-password-123"  # development only; the seed refuses production

STORY_DISCLAIMER = "(Development sample story. Invented text, not real reporting.)"

# username, display name, creator type, location, bio
SEED_USERS = [
    ("seed_rahim", "[Seed] Rahim", "photographer", "Sylhet", "Early light and wide water."),
    ("seed_nusrat", "[Seed] নুসরাত", "storyteller", "Dhaka", "গল্প, জায়গা আর মানুষ।"),
    ("seed_tanvir", "[Seed] Tanvir", "traveler", "Rajshahi", "Slow trips, long lunches."),
    ("seed_mitu", "[Seed] মিতু", "local_storyteller", "Bandarban", "পাহাড়ের গল্প পাহাড়ের কণ্ঠে।"),
    ("seed_arif", "[Seed] Arif", "guide", "Cox's Bazar", "Notes from the coast."),
    ("seed_sadia", "[Seed] Sadia", "researcher", "Dhaka", "Curious about old walls."),
]

# (username, text, location text, place slug, hours ago, placeholder image indexes, tags)
SEED_POSTS = [
    (
        "seed_rahim",
        "Early light over the haor. The water was completely still.",
        "Tanguar Haor, Sunamganj",
        "tanguar-haor",
        1,
        [0, 1],
        ["nature", "photography"],
    ),
    (
        "seed_nusrat",
        "আজ সকালে জাফলংয়ে পাহাড়ের নিচে স্বচ্ছ জলের পাশে বসে ছিলাম। এখানকার নীরবতা ভাষায় প্রকাশ করা কঠিন।",
        "জাফলং, সিলেট",
        "jaflong",
        3,
        [2],
        ["travel", "nature"],
    ),
    (
        "seed_tanvir",
        "Terracotta details on an old temple wall. Worth the early start.",
        "Paharpur, Naogaon",
        "paharpur",
        8,
        [3, 0, 1],
        ["heritage", "photography"],
    ),
    (
        "seed_nusrat",
        "চায়ের বাগানে বিকেল। শ্রীমঙ্গলের এই সবুজ ঢেউ দেখে মন ভরে যায়।",
        "শ্রীমঙ্গল, মৌলভীবাজার",
        "sreemangal",
        20,
        [],
        ["nature", "travel"],
    ),
    (
        "seed_rahim",
        "Notes from a slow day in Sonargaon: crumbling facades, quiet lanes, good tea.",
        "Sonargaon",
        "sonargaon",
        30,
        [1],
        ["heritage", "culture"],
    ),
    ("seed_tanvir", "Ferry crossing at dusk.", None, None, 52, [0], ["travel"]),
    (
        "seed_mitu",
        "ভোরের কুয়াশা নামছে পাহাড়ের গায়ে। চা আর নীরবতা, আর কিছু লাগে না।",
        "বান্দরবান",
        "bandarban",
        5,
        [2, 3],
        ["nature", "people"],
    ),
    (
        "seed_arif",
        "Low tide, long beach, nobody in a hurry. The kind of walk that resets a week.",
        "Cox's Bazar",
        "cox-s-bazar",
        6,
        [1],
        ["travel", "nature"],
    ),
    (
        "seed_sadia",
        "Brick, moss and afternoon shade. Sat sketching the arches until the light changed.",
        "Sonargaon",
        "sonargaon",
        12,
        [3],
        ["heritage", "culture"],
    ),
    (
        "seed_rahim",
        "A boat, a paddle and a canopy of branches reflected in dark water.",
        "Ratargul, Sylhet",
        "ratargul-swamp-forest",
        14,
        [0, 2],
        ["nature", "photography"],
    ),
    (
        "seed_tanvir",
        "Rickshaw bells and mango-sellers: Rajshahi mornings are a good time to wander.",
        "Rajshahi",
        "rajshahi",
        16,
        [1],
        ["people", "food"],
    ),
    (
        "seed_nusrat",
        "ঝিরির জলে পা ডুবিয়ে বসে থাকা, পাথরের ওপর দিয়ে স্রোতের শব্দ — বিছনাকান্দির একটা সকাল।",
        "বিছনাকান্দি",
        "bichanakandi",
        18,
        [2],
        ["nature", "travel"],
    ),
    (
        "seed_mitu",
        "লেকের জলে সন্ধ্যার রং। নৌকায় বসে চুপচাপ ফিরে আসা।",
        "রাঙ্গামাটি",
        "rangamati",
        22,
        [1, 0],
        ["nature", "people"],
    ),
    (
        "seed_arif",
        "Dried fish stalls at the market, bright with the smell of the sea. Go hungry.",
        "Cox's Bazar",
        "cox-s-bazar",
        26,
        [3],
        ["food", "culture"],
    ),
    (
        "seed_sadia",
        "Quiet courtyard, steady footsteps. It is easy to forget the city outside.",
        "Paharpur",
        "paharpur",
        34,
        [0],
        ["heritage"],
    ),
    (
        "seed_rahim",
        "Fog on the tea rows, just before the pickers arrive.",
        "Sreemangal",
        "sreemangal",
        40,
        [2, 3],
        ["nature", "photography"],
    ),
    (
        "seed_tanvir",
        "Spent the evening in Sylhet chatting with a tea-stall owner about nothing in particular. Best part of the trip.",
        "Sylhet",
        "sylhet",
        44,
        [],
        ["people", "travel"],
    ),
    (
        "seed_nusrat",
        "পাহাড় আর মেঘের মাঝখানে একটা ছোট্ট ঘর। জানালা দিয়ে তাকিয়ে থাকাই সারাদিনের কাজ।",
        "বান্দরবান",
        "bandarban",
        60,
        [3],
        ["travel", "people"],
    ),
]

# Stories: (username, title, location text, place slug, hours ago, cover index, tags, paragraphs)
# Paragraph markup: plain text, "## heading", "> quote".
SEED_STORIES = [
    (
        "seed_nusrat",
        "জাফলং: নীরবতার একটা দিন",
        "জাফলং, সিলেট",
        "jaflong",
        10,
        2,
        ["travel", "nature"],
        [
            "সকালটা শুরু হয়েছিল ধীরে। নদীর ধারে বসে আমি শুধু জলের শব্দ শুনছিলাম।",
            "## পাথর আর স্রোত",
            "পাথরের ওপর দিয়ে স্রোত বয়ে যায়, আর কেউ কোনো তাড়ায় নেই। এমন জায়গায় সময়ের হিসাব হারিয়ে যায়।",
            "> কিছু জায়গা শুধু দেখার নয়, চুপ করে অনুভব করার।",
            "ফেরার পথে মনে হলো, এই নীরবতাটুকুই সঙ্গে নিয়ে যাচ্ছি।",
        ],
    ),
    (
        "seed_rahim",
        "A Slow Morning on the Haor",
        "Tanguar Haor, Sunamganj",
        "tanguar-haor",
        24,
        0,
        ["nature", "photography"],
        [
            "We left the shore before the light was fully up. The boat made the only sound.",
            "## Reading the water",
            "When the wind drops, the haor turns into a mirror. Photographs flatten it; sitting there does not.",
            "> I stopped taking pictures for a while and just watched.",
            "By the time the sun cleared the horizon, the whole boat had gone quiet too.",
        ],
    ),
    (
        "seed_sadia",
        "Walking Slowly Through Old Walls",
        "Sonargaon",
        "sonargaon",
        48,
        3,
        ["heritage", "culture"],
        [
            "Old buildings reward patience. I gave myself a whole afternoon and no itinerary.",
            "## Details first",
            "Cracked plaster, a door frame worn smooth, the way light slides across a facade. These small things tell you more than a plaque.",
            "> Slow down and the walls start to speak.",
            "I left with a notebook full of sketches and no clear answers, which felt right.",
        ],
    ),
    (
        "seed_mitu",
        "পাহাড়ের কোলে এক সকাল",
        "বান্দরবান",
        "bandarban",
        72,
        1,
        ["people", "nature"],
        [
            "পাহাড়ে সকাল আসে মেঘের সঙ্গে। আমরা চা হাতে বারান্দায় বসে ছিলাম।",
            "## গল্পের মানুষ",
            "যাঁদের সঙ্গে দেখা হলো, তাঁদের গল্পগুলো শুনতে শুনতে বেলা গড়িয়ে গেল।",
            "> সবচেয়ে সুন্দর দৃশ্যগুলো প্রায়ই মানুষের গল্পের ভেতরে থাকে।",
            "যাওয়ার সময় ওঁরা হাত নেড়ে বিদায় জানালেন, আর আমি ভাবলাম আবার আসব।",
        ],
    ),
    (
        "seed_arif",
        "Reading the Coast at Low Tide",
        "Cox's Bazar",
        "cox-s-bazar",
        96,
        1,
        ["travel", "food"],
        [
            "Low tide changes the beach completely: new textures, new paths, different birds.",
            "## Market and shoreline",
            "I split the day between the shoreline and the market, following whatever smelled best.",
            "> The coast tastes as good as it looks.",
            "Evening came with a pink sky and a very full stomach.",
        ],
    ),
    (
        "seed_tanvir",
        "Temple Brick and Early Starts",
        "Paharpur, Naogaon",
        "paharpur",
        120,
        3,
        ["heritage", "photography"],
        [
            "I set an alarm for an hour I would normally never see. It was worth it.",
            "## The first hour",
            "The early light picks out every line in the brickwork. By mid-morning it is a different place.",
            "> Some places are best met before anyone else is awake.",
            "Walking back, the quiet felt earned.",
        ],
    ),
    (
        "seed_rahim",
        "Tea Rows in the Fog",
        "Sreemangal",
        "sreemangal",
        150,
        2,
        ["nature", "photography"],
        [
            "Fog turns the tea rows into soft green lines that disappear into the white.",
            "## Before the day begins",
            "I arrived before most people and stood still while the light came up through the haze.",
            "> The quiet here has a texture.",
            "Then the first voices arrived and the day began.",
        ],
    ),
]

# A draft owned by seed_rahim so the "My drafts" tab has something to show.
SEED_DRAFT_TITLE = "Notes for a Ratargul story (draft)"
SEED_DRAFT = (
    "seed_rahim",
    SEED_DRAFT_TITLE,
    "Ratargul, Sylhet",
    "ratargul-swamp-forest",
    ["nature"],
    ["Some half-formed thoughts about the boat ride. Still to write."],
)
