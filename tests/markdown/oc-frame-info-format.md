# oc-frame-info format (type.oc-frame-theme [title])

Fenced code blocks using the info string format `type.oc-frame-theme` or `type.oc-frame-theme title`.
RenderSourceView must parse these as type + theme (e.g. markdown), not as language-free text.

## Block with type.oc-frame-theme and no title

``` markdown.oc-frame-info
## Nested heading

- Item one
- Item two
```

## Block with type.oc-frame-theme and title

``` markdown.oc-frame-info Reviewing Tool Output with (model)
Executor prompt body here.

- Section one
- Section two
```

## Block with text type and title (sanity check)

``` text.oc-frame-primary You said:
User message content.
```

End of file.
