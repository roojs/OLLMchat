<!--
  Opening HTML tag not at byte 0, with the closing tag immediately after the
  opening tag. Command:
    build/examples/oc-markdown-test tests/markdown/repro-html-empty-element.md
  Today this aborts at Parser.vala:582
    (str == "" && text_start_pos == chunk_pos)
  A file that is only an empty div does not abort.
  A span with text between the tags does not abort.
  README.md dies on the same path at its video element.
-->

Before <div></div>
