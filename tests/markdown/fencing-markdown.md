# Fencing markdown test (Plan 1.8.3)

This file exercises fenced code blocks with **empty language**, **space then description**, **language only**, and **language + description** for the GTK viewer. Frame header should show "code" when empty; when the info string is space(s) then text, that text is shown; language when no description; description when present.

## Block with empty language (no info string)

```
plain code block
no language or description
```

## Block with space then description

```  snippet with description
content after leading space and single-word description
```

## Block with language only

```markdown
## Nested heading

- Item one
- Item two

*Emphasis* and **strong**.
```

## Block with language and description

```markdown vala snippet
void main () {
    print ("Hello from nested markdown.\n");
}
```

End of file.
