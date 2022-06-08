# Dumbo – The Dumboest markdown converter

Dumbo is a webserver that provides minimal REST API to convert various text formats to HTML or LaTeX with [Pandoc](https://pandoc.org/).

Features:

* Convert any Pandoc-supported markup format to HTML or LaTeX
* Convert embedded LaTeX and AsciiMath to SVG using [DVISVGM](https://dvisvgm.de/)

## Usage

### As local server

You can compile and run the server locally with `stack build`.

Available options:

```
Dumboest markdown converter

Usage: Dumbo.EXE [--latex STRING] [--dvisvgm STRING] --cacheDir STRING
                 --tmpDir STRING --port INT

Available options:
  -h,--help                Show this help text
  --latex STRING           Absolute path to latex binary
  --dvisvgm STRING         Absolute path to dvisvgm binary
  --cacheDir STRING        Directory for cached math
  --tmpDir STRING          Directory to store temporary files
  --port INT               Service port number
```

**Note**: The tool requires TeX and DVISVGM installed for all features to be available.

### As a Docker container

A prebuilt Docker container with all necessary dependencies is available via [timimages/dumbo](https://hub.docker.com/r/timimages/dumbo) container.

Usage example:

```bash
docker run --rm -p 5000:5000 --tmpfs /docker_cache --tmpfs /dumbo_tmp timimages/dumbo:latest
```

The command above will start the server on `localhost:5000`


## API reference

#### Input types

The main input can be defined as the following TypeScript schema:

```ts
type InputElement<T> = {
    // Main content
    content: T,

    // Format of the input content as a valid Pandoc input type
    // If not specified, assumes input is Markdown
    inputFormat: string | undefined,

    // How to process LaTex math.
    // mathjax (default) -> Let Pandoc process math and output MathJax-compatible output
    // svg -> Render math using proper LaTeX and DVISVGM
    // undefined -> defaults to mathjax
    mathOption: "svg" | "mathjax" | undefined,

    // If mathOption is set to "svg", this allows to specify a custom LaTeX preamble
    mathPreamble: string | undefined,

    // If true, applies Pandoc's smart punctuation extension (Ext_smart)
    smartPunct: bool | undefined,
};
```

#### `POST /markdown` - convert text to HTML

**Input:** JSON-encoded text paragraphs as `InputElement<string[]>`

**Output:** JSON-encoded resulting HTML snippets as `string[]` 

**Description:** Converts input text (assumes Markdown by default) to HTML.

**Examples:**

```bash
@ curl --data '{"content":["# Hello, world!"]}' localhost:5000/markdown
["<h1 id=\"hello-world\">Hello, world!</h1>"]
```

```bash
@ curl --data '{"content":["Math: $1+1$"]}' localhost:5000/markdown
["<p>Math: <span class=\"math inline\">\\(1+1\\)</span></p>"]

@ curl --data '{"content":["Math: $1+1$"], "mathOption": "svg"}' localhost:5000/markdown
["<p>Math: <span class=\"mathp inline\"><img style=\"width:2.77670em; vertical-align:-0.15963em\" src=\"data:image/svg+xml;...\" title=\"1+1\"></span></p>"]
```

#### `POST /latex` - convert text to LaTeX

**Input:** JSON-encoded text paragraphs as `InputElement<string[]>`

**Output:** JSON-encoded resulting LaTeX snippets as `string` 

**Description:** Converts input text (assumes Markdown by default) to LaTeX.

**Examples:**

```bash
@ curl --data '{"content":["# Hello, world!"]}' localhost:5000/latex
["\\hypertarget{hello-world}{%\n\\section{Hello, world!}\\label{hello-world}}"]
```

```bash
@ curl --data '{"content":["Math: $1+1$"]}' localhost:5000/latex
["Math: \\(1+1\\)"]

# Note that mathOption: svg does not have any effect on LaTeX rendering
@ curl --data '{"content":["Math: $1+1$"], "mathOption": "svg"}' localhost:5000/latex
["Math: \\(1+1\\)"]
```


#### `POST /mdkeys` - process a JSON object and convert keys to HTML selectively

**Input:** JSON-encoded data as `InputElement<T>` where `T` is any JSON-encodable object or `InputElement<T>` itself.

**Output:** `T` with specific fields converted to HTML

**Description:** Walks an aribtrary JSON-encoded object and converts any keys/values to HTML if they contain one of the following prefixes (`\n` is newline):

  * `md:` - Parses the key/value as Markdown
  * `am:` - Parse sthe key/value as AsciiMath

  **Note**: Note that `T` can be `InputElement<T>` itself. In that case, any options specified in it will be applied to the any child values. You can use this approach to override any rendering option for each possible inner object.

**Examples:**

Processes an object `{"a": "md:# Hello, world", "b": ["*foo*", "md:**bar**"]}` and converts all values prefixed with `md:` to HTML:

```bash
curl --data '{"content":[{"a": "md:# Hello, world", "b": ["*foo*", "md:**bar**"]}]}' localhost:5000/mdkeys
[{"a":"<h1 id=\"hello-world\">Hello, world</h1>","b":["*foo*","<strong>bar</strong>"]}]
```

Recursively specify the content with different input options:

```bash
curl --data '{"content": [{"content": "md:$1+1$"}, {"content": "md:$1+1$", "mathOption": "svg"}]}' localhost:5000/mdk
eys
["<span class=\"math inline\">\\(1+1\\)</span>","<span class=\"mathp inline\"><img style=\"width:2.77670em; vertical-align:-0.15963em\" src=\"data:image/svg+xml;...\" title=\"1+1\"></span>"]
```

#### `POST /latexkeys` - process a JSON object and convert keys to HTML selectively

**Input:** JSON-encoded data as `InputElement<T>` where `T` is any JSON-encodable object or `InputElement<T>` itself.

**Output:** `T` with specific fields converted to LaTeX

**Description:** Walks an aribtrary JSON-encoded object and converts any keys/values to HTML if they contain one of the following prefixes (`\n` is newline):

  * `md:` - Parses the key/value as Markdown
  * `am:` - Parse sthe key/value as AsciiMath

  **Note**: Note that `T` can be `InputElement<T>` itself. In that case, any options specified in it will be applied to the any child values. You can use this approach to override any rendering option for each possible inner object.

**Examples:**

Processes an object `{"a": "md:# Hello, world", "b": ["*foo*", "md:**bar**"]}` and converts all values prefixed with `md:` to HTML:

```bash
curl --data '{"content":[{"a": "md:# Hello, world", "b": ["*foo*", "md:**bar**"]}]}' localhost:5000/latexkeys
[{"a":"\\hypertarget{hello-world}{%\n\\section{Hello, world}\\label{hello-world}}","b":["*foo*","\\textbf{bar}"]}]
```


## Credits and license

Dumbo was created and primarily developed by Ville Tirronen (@aleator) with some minor tweaks added by Mika Lehtinen (@Smibu).

Dumbo is licensed under GPLv3.