module AppUrl exposing
    ( AppUrl, QueryParameters
    , fromUrl
    , toString, pathToString
    )

{-| URLs for applications.


# Types

@docs AppUrl, QueryParameters


# Parse

@docs fromUrl


# Stringify

@docs toString, pathToString

-}

import Dict exposing (Dict)
import Escape
import Url exposing (Url)


{-| You might recognize this diagram from the core [Url] type documentation:

      https://example.com:8042/over/there?name=ferret#nose
      \___/   \______________/\_________/ \_________/ \__/
        |            |            |            |        |
      scheme     authority       path        query   fragment

`AppUrl` represents only path + query + fragment:

      https://example.com:8042/over/there?name=ferret#nose
                              \__________________________/
                                            |
                                         AppUrl

That’s the part you’ll work the most with in your app.

An `AppUrl` is “more parsed“ than [Url] (where everything is a string):

  - `path`: `List String`. The path, split by slash. This makes it convenient to
    pattern match on the segments.
  - `queryParameters`: [QueryParameters](#QueryParameters). A dict of the query
    parameters, with keys mapped to the values.
  - `fragment`: `Maybe String`. The fragment, without the leading hash symbol.

Each path segment, query parameter key, query parameter value and the fragment
are all percent decoded, so you never need to think about that. For example,
`%20` is turned into a space and `%2F` is turned into a slash.

You can think of [Url] as the type you get from Elm when using
[Browser.application]. From it you can create an `AppUrl`, and that’s what
you’ll use when parsing which page you’re on and when creating links.

[Browser.application]: https://package.elm-lang.org/packages/elm/browser/latest/Browser#application
[Url]: https://package.elm-lang.org/packages/elm/url/latest/Url#Url

-}
type alias AppUrl =
    { path : List String
    , queryParameters : QueryParameters
    , fragment : Maybe String
    }


{-| A dict of the query parameters, with keys mapped to the values. The same key
might be given more than once, so each key is mapped to a list of values.

Get all values of a key:

    Dict.get "myParam" url.queryParameters

Get the first value:

    Dict.get "myParam" url.queryParameters |> Maybe.andThen List.head

Get the last value:

    Dict.get "myParam" url.queryParameters |> Maybe.andThen List.Extra.last

See also [choosing a query parameter][choose] and [query parameter
parsing][parse] for extra details.

[choose]: https://package.elm-lang.org/packages/lydell/elm-app-url/latest#choosing-a-query-parameter
[parse]: https://package.elm-lang.org/packages/lydell/elm-app-url/latest#query-parameter-parsing

-}
type alias QueryParameters =
    Dict String (List String)


{-| Turn an [AppUrl](#AppUrl) into a string.

  - The string always starts with `/`.
  - It only contains a `?` if there are any query parameters.
  - Similarly, it only contains a `#` if there is a fragment.
  - Query parameters with the empty string as the value don’t get any equals
    sign: `?k`, not `?k=`.
  - Query parameters are sorted by key.

Each path segment, query parameter key, query parameter value and the fragment
are all percent encoded, but very minimally. See [escaping] and [plus and space] for details.

See also [Full and relative URLs].

[Full and relative URLs]: https://package.elm-lang.org/packages/lydell/elm-app-url/latest#full-and-relative-urls
[escaping]: https://package.elm-lang.org/packages/lydell/elm-app-url/latest#escaping
[plus and space]: https://package.elm-lang.org/packages/lydell/elm-app-url/latest#plus-and-space

-}
toString : AppUrl -> String
toString url =
    pathToString url.path ++ queryParametersToString url.queryParameters ++ fragmentToString url.fragment


{-| Convenience function for creating a URL string like `/one/two` – starting with a
slash, and without query parameters or fragment. (Use [AppUrl.toString](#toString)
if you need those.)

Here’s how it relates to [AppUrl.toString](#toString):

    pathToString : List String -> String
    pathToString path =
        AppUrl.toString
            { path = path
            , queryParameters = Dict.empty
            , fragment = Nothing
            }

-}
pathToString : List String -> String
pathToString path =
    "/" ++ String.join "/" (List.map (percentEncode Escape.Path) path)


queryParametersToString : QueryParameters -> String
queryParametersToString queryParameters =
    let
        filteredQueryParameters : QueryParameters
        filteredQueryParameters =
            queryParameters
                |> Dict.filter (\_ values -> not (List.isEmpty values))
    in
    if Dict.isEmpty filteredQueryParameters then
        ""

    else
        "?"
            ++ (filteredQueryParameters
                    |> Dict.toList
                    |> List.concatMap queryParameterToString
                    |> String.join "&"
               )


queryParameterToString : ( String, List String ) -> List String
queryParameterToString ( key, values ) =
    values
        |> List.map
            (\value ->
                -- `?=` is parsed as both the key and the value being the empty
                -- string. If we were to omit the equals sign in that case (like
                -- we normally do when the value is the empty string), we would
                -- print nothing at all which would lose this “parameter” next
                -- time we parse.
                if not (String.isEmpty key) && String.isEmpty value then
                    percentEncode Escape.QueryKey key

                else
                    percentEncode Escape.QueryKey key ++ "=" ++ percentEncode Escape.QueryValue value
            )


fragmentToString : Maybe String -> String
fragmentToString maybeFragment =
    case maybeFragment of
        Just fragment ->
            "#" ++ percentEncode Escape.Fragment fragment

        Nothing ->
            ""


percentEncode : Escape.Part -> String -> String
percentEncode part string =
    string
        |> String.toList
        |> List.map (Escape.forAll part)
        |> String.concat


{-| Turn a [Url] from [elm/url] into an [AppUrl](#AppUrl).

This removes one trailing slash from the end of the path (if any), for convenience.
For example, `/one/two` and `/one/two/` are both turned into `[ "one", "two" ]`.

Some sites use a trailing slash, some don’t. Users don’t know what to use where.
This lets you support both. It’s up to you if you want to update the URL to a
canonical version.

Note: You can add an empty string at the end of the path, like `[ "one", "two", "" ]`
if you want to create a string with a trailing slash.

[Url]: https://package.elm-lang.org/packages/elm/url/latest/Url#Url
[elm/url]: https://package.elm-lang.org/packages/elm/url/latest

-}
fromUrl : Url -> AppUrl
fromUrl url =
    { path = parsePath url.path
    , queryParameters = url.query |> Maybe.map parseQueryParameters |> Maybe.withDefault Dict.empty
    , fragment = url.fragment |> Maybe.map percentDecode
    }


parsePath : String -> List String
parsePath path =
    let
        trimmed : String
        trimmed =
            path
                |> trimLeadingSlash
                |> trimTrailingSlash
    in
    if String.isEmpty trimmed then
        []

    else
        trimmed
            |> String.split "/"
            |> List.map percentDecode


trimLeadingSlash : String -> String
trimLeadingSlash string =
    if String.startsWith "/" string then
        String.dropLeft 1 string

    else
        string


trimTrailingSlash : String -> String
trimTrailingSlash string =
    if String.endsWith "/" string then
        String.dropRight 1 string

    else
        string


percentDecode : String -> String
percentDecode string =
    Url.percentDecode string |> Maybe.withDefault string


queryParameterDecode : String -> String
queryParameterDecode =
    String.replace "+" " " >> percentDecode


parseQueryParameters : String -> QueryParameters
parseQueryParameters =
    String.split "&"
        >> List.foldr parseQueryParameter Dict.empty


parseQueryParameter : String -> QueryParameters -> QueryParameters
parseQueryParameter segment queryParameters =
    case String.split "=" segment of
        [] ->
            queryParameters

        -- `?&` or `&&` does not count as the key being empty string with the
        -- value of the empty string.
        [ "" ] ->
            queryParameters

        -- Note: The empty string is allowed as key name. Only whitespace is
        -- also allowed as key name. Missing value (no `=`) is handled as the
        -- same as `=` followed by nothing (the empty string).
        rawKey :: rest ->
            Dict.update
                (queryParameterDecode rawKey)
                (insert (queryParameterDecode (String.join "=" rest)))
                queryParameters


insert : a -> Maybe (List a) -> Maybe (List a)
insert value maybeList =
    Just (value :: Maybe.withDefault [] maybeList)
