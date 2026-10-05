# Product

ANGON is a tourism- and culture-focused social platform: *a social network for places, people and stories.* It is not a booking marketplace, a Facebook/Instagram clone or a generic blog CMS.

## V1 at a glance
| Area | What a person can do |
|------|----------------------|
| Accounts | Register, sign in, sign out; set up a creator/traveller profile (display name, bio, location, creator type, avatar, cover). |
| Home | A feed of posts (Discover = everyone, Following = people you follow) with photos, tags and places. |
| Posts | Write text and attach up to 10 photos, tags and a place; delete your own posts. Like, comment, save. |
| Stories | Long-form writing with a cover, headings, quotes and inline photos; drafts, publish, unpublish; like, save, related stories; reading view. |
| Profiles | Public profiles with counts, follow/unfollow, followers/following lists, tabs for posts, stories, photos, places and saved items. |
| Explore | Categories, trending posts, featured stories, popular places; search across people, stories, posts and places. |
| Places | Curated destination pages (12 Bangladesh places in the seed) with posts, stories, photos and creators. |
| Map | Places and nearby content on a map, with a graceful fallback when no map provider is configured. |
| Notifications | In-app notifications for likes, comments and new followers; unread badge; mark one/all read. |
| Moderation | Report a post, story, comment or profile with a reason; reports go to an admin-ready review queue. |

## Content concepts
- **Post**: short social content: text, photos, location, tags.
- **Story**: long-form editorial writing with a cover, location and tags.
- **Place**: a destination page that gathers posts, stories, photos and creators.
- **Profile**: a creator/traveller identity.

## Themes
Travel, Culture, Heritage, Nature, Food, Photography, People are the explore categories (tags).

## Design principles
Warm paper-and-ink editorial design: strong typography, photography and whitespace, subtle motion, no gradients or glassmorphism. Terracotta and delta-green accents; a dark theme with the same character. Bengali and English share one type system (Newsreader/Inter with Noto Bengali fallbacks). Accessible by default: 48dp tap targets, semantic labels, large-text layouts verified down to 320dp.

## Principles V1 follows
Server state is authoritative; nothing is faked in the UI (features that do not exist, such as Share, say so); development sample content is always labelled; no ads, no recommendation AI, no engagement tricks.

## Explicitly out of scope for V1
Hotel or experience booking, payments, a marketplace, chat/messaging, dating, generic groups, ads, algorithmic recommendations, blockchain/crypto. See the [roadmap](ROADMAP.md) for what comes later.

## Long-term vision
People, Places, Stories, Culture, Communities, Experiences, Tourism.
