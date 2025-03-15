package main

import "core:fmt"
import jokeapi "../"

main :: proc() {
    joke, ok := jokeapi.get_jokes(5, {
        category = {.Programming},
        language = .English,
        blacklist = {.Nsfw},
        id_range = jokeapi.Range{min = 0, max = 100},
        safe = true,
    })
    if !ok {
        return
    }
    fmt.printfln("%#v", joke)
}
