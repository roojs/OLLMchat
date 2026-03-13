# Fencing markdown test (Plan 1.8.3)

This file exercises fenced code blocks with **language only** and **language + description** for the GTK viewer. Frame header should show language when no description, and description when present.

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
