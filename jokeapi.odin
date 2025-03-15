package jokeapi

import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:net"
import "core:encoding/json"
import httpc "shared:odin-http/client"
import http "shared:odin-http"

@(private)
BASE_URL :: "https://v2.jokeapi.dev/joke/"

JokeType :: enum {
    Any,
    Single,
    TwoPart,
}

Language :: enum {
    English,
    Czech,
    German,
    Spanish,
    French,
    Portuguese,
    Unknown = -1,
}

Category_Bits :: enum {
    Misc,
    Programming,
    Dark,
    Pun,
    Spooky,
    Christmas,
}

Category :: bit_set[Category_Bits]

@(private)
FlagsResponse :: struct {
    nsfw: bool,
    religious: bool,
    political: bool,
    racist: bool,
    sexist: bool,
    explicit: bool,
}

@(private)
JokeResponse :: struct {
    category: string,
    type: string,
    setup: Maybe(string), // Only exists if type is "twopart"
    delivery: Maybe(string), // Only exists if type is "twopart"
    joke: Maybe(string), // Only exists if type is "single"
    flags: FlagsResponse,
    safe: bool,
    id: int,
    lang: string,
}

@(private)
MultipleJokesResponse :: struct {
    amount: int,
    jokes: []JokeResponse,
}

Blacklist_Bits :: enum {
    Nsfw,
    Religious,
    Political,
    Racist,
    Sexist,
    Explicit,
}

Blacklist :: bit_set[Blacklist_Bits; u8]

SingleJoke :: string

TwoPartJoke :: struct {
    setup: string,
    delivery: string,
}

Joke :: struct {
    category: Category_Bits,
    joke: union {
        SingleJoke,
        TwoPartJoke,
    },
    flags: Blacklist,
    safe: bool,
    id: int,
    lang: Language,
}

@(private)
category_from_string :: proc(cat: string) -> (category: Category_Bits) {
    switch cat {
    case "Programming": return .Programming
    case "Pun": return .Pun
    case "Misc": return .Misc
    case "Dark": return .Dark
    case "Spooky": return .Spooky
    case "Christmas": return .Christmas
    case: return .Misc
    }
}

@(private)
language_from_string :: proc(lang: string) -> Language {
    switch lang {
    case "cs": return .Czech
    case "en": return .English
    case "de": return .German
    case "fr": return .French
    case "es": return .Spanish
    case "pt": return .Portuguese
    case: return .Unknown
    }
}

@(private)
language_to_iso := [Language]string {
    .English = "",
    .Unknown = "",
    .Portuguese = "pt",
    .Czech = "cs",
    .German = "de",
    .Spanish = "es",
    .French = "fr",
}

Range :: struct {
    min: int,
    max: int,
}

Options :: struct {
    category: Category,
    language: Language,
    blacklist: Blacklist,
    type: JokeType,
    contains: string,
    // Inclusive range of joke ids. Ignored if min is greater than max.
    // Use the same id for min and max to fetch that particular joke associated with the id.
    id_range: Maybe(Range),
    // This option overrides whatever is set in `blacklist`
    safe: bool,
}

@(private)
parse_options :: proc(options: Options, amount: int) -> (resource, query: string) {
    resource = "Any"
    queries: [dynamic]http.Query_Entry
    query_b := strings.builder_make()

    cats: [dynamic]string
    for cat in options.category {
        #partial switch cat {
        case .Programming: append(&cats, "Programming")
        case .Misc: append(&cats, "Misc")
        case .Dark: append(&cats, "Dark")
        case .Pun: append(&cats, "Pun")
        case .Spooky: append(&cats, "Spooky")
        case .Christmas: append(&cats, "Christmas")
        }
    }
    if len(cats) != 0 {
        resource = strings.join(cats[:], ",")
    }

    if options.language != .English && options.language != .Unknown {
        append(&queries, http.Query_Entry{"lang", language_to_iso[options.language]})
    }

    if card(options.blacklist) != 0 {
        blacklist: [dynamic]string
        if .Nsfw in options.blacklist do append(&blacklist, "nsfw")
        if .Religious in options.blacklist do append(&blacklist, "religious")
        if .Political in options.blacklist do append(&blacklist, "political")
        if .Racist in options.blacklist do append(&blacklist, "racist")
        if .Sexist in options.blacklist do append(&blacklist, "sexist")
        if .Explicit in options.blacklist do append(&blacklist, "explicit")

        append(&queries, http.Query_Entry{"blacklistFlags", strings.join(blacklist[:], ",")})
    }

    if options.safe {
        append(&queries, http.Query_Entry{"safe-mode", "true"})
    }

    if options.contains != "" {
        append(&queries, http.Query_Entry{"contains", net.percent_encode(options.contains, context.temp_allocator)})
    }

    switch options.type {
    case .Single:
        append(&queries, http.Query_Entry{"type", "single"})
    case .TwoPart:
        append(&queries, http.Query_Entry{"type", "twopart"})
    case .Any: fallthrough
    case: // Do Nothing
    }

    if options.id_range != nil && options.id_range.?.min <= options.id_range.?.max {
        if options.id_range.?.min == options.id_range.?.max {
            id: [64]byte = ---
            append(&queries, http.Query_Entry{"idRange", strconv.itoa(id[:], options.id_range.?.min)})
        } else {
            append(&queries, http.Query_Entry{"idRange", fmt.tprintf("%d-%d", options.id_range.?.min, options.id_range.?.max)})
        }
    }

    amount_str: [64]u8 = ---
    append(&queries, http.Query_Entry{"amount", strconv.itoa(amount_str[:], amount)})

    if len(queries) != 0 {
        strings.write_byte(&query_b, '?')
        strings.write_string(&query_b, queries[0].key)
        strings.write_byte(&query_b, '=')
        strings.write_string(&query_b, queries[0].value)

        for q, i in queries[1:] {
            strings.write_byte(&query_b, '&')

            strings.write_string(&query_b, q.key)
            strings.write_byte(&query_b, '=')
            strings.write_string(&query_b, q.value)
        }
    }

    query = strings.to_string(query_b)

    return
}

get_joke :: proc(options := Options{}) -> (Joke, bool) {
    resource, query := parse_options(options, 1)

    res, err := httpc.get(strings.concatenate({BASE_URL, resource, query}))
    if err != nil {
        fmt.eprintln("Failed to get joke:", err)
        return {}, false
    }

    body, alloc, body_err := httpc.response_body(&res)
    if body_err != nil {
        fmt.eprintln("Body err:", body_err)
        return {}, false
    }
    defer httpc.body_destroy(body, alloc)

    fmt.println(body.(httpc.Body_Plain))
    if res.status != .OK {
        // TODO: better errors
        fmt.eprintln("Got a non 200 status code:", res.status)
        return {}, false
    }

    joke_resp: JokeResponse
    json.unmarshal(transmute([]byte)(body.(httpc.Body_Plain)), &joke_resp, allocator = context.temp_allocator)

    flags: Blacklist

    if joke_resp.flags.nsfw do flags += { .Nsfw }
    if joke_resp.flags.racist do flags += { .Racist }
    if joke_resp.flags.sexist do flags += { .Sexist }
    if joke_resp.flags.explicit do flags += { .Explicit }
    if joke_resp.flags.religious do flags += { .Religious }
    if joke_resp.flags.political do flags += { .Political }

    joke := Joke{
        category = category_from_string(joke_resp.category),
        joke = SingleJoke(joke_resp.joke.?) if joke_resp.type == "single" else TwoPartJoke{setup = joke_resp.setup.?, delivery = joke_resp.delivery.?},
        flags = flags,
        safe = joke_resp.safe,
        id = joke_resp.id,
        lang = language_from_string(joke_resp.lang),
    }

    return joke, true
}

@(private)
map_joke_response :: proc(joke: JokeResponse) -> Joke {
    flags: Blacklist
    if joke.flags.nsfw do flags += { .Nsfw }
    if joke.flags.racist do flags += { .Racist }
    if joke.flags.sexist do flags += { .Sexist }
    if joke.flags.explicit do flags += { .Explicit }
    if joke.flags.religious do flags += { .Religious }
    if joke.flags.political do flags += { .Political }

    return Joke{
        category = category_from_string(joke.category),
        joke = SingleJoke(joke.joke.?) if joke.type == "single" else TwoPartJoke{setup = joke.setup.?, delivery = joke.delivery.?},
        flags = flags,
        safe = joke.safe,
        id = joke.id,
        lang = language_from_string(joke.lang),
    }
}

get_jokes :: proc(amount: int, options := Options{}) -> ([]Joke, bool) {
    if amount == 0 {
        return {}, true
    }
    if amount == 1 {
        joke, ok := get_joke(options)
        jokes := make([]Joke, 1, context.temp_allocator)
        jokes[0] = joke
        return jokes, ok
    }

    resource, query := parse_options(options, amount)

    res, err := httpc.get(strings.concatenate({BASE_URL, resource, query}))
    if err != nil {
        fmt.eprintln("Failed to get joke:", err)
        return {}, false
    }

    body, alloc, body_err := httpc.response_body(&res)
    if body_err != nil {
        fmt.eprintln("Body err:", body_err)
        return {}, false
    }
    defer httpc.body_destroy(body, alloc)

    fmt.println(body.(httpc.Body_Plain))
    if res.status != .OK {
        // TODO: better errors
        fmt.eprintln("Got a non 200 status code:", res.status)
        return {}, false
    }

    joke_resp: MultipleJokesResponse
    json.unmarshal(transmute([]byte)(body.(httpc.Body_Plain)), &joke_resp, allocator = context.temp_allocator)

    jokes := make([]Joke, joke_resp.amount, context.temp_allocator)

    for joke, i in joke_resp.jokes {
        jokes[i] = map_joke_response(joke)
    }

    return jokes, true
}
