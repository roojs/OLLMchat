# Test case for extra space handling (3 spaces instead of 4)
1. First ordered item
2. Second ordered item
  1. Sub-first (3 spaces - should work with extra space handling)
  2. Sub-second (3 spaces)
3. Third ordered item

- First unordered item
- Second unordered item
  1. First nested ordered item
  2. Second nested ordered item
    - Deep nested unordered item
    - Another deep nested unordered item
  3. Third nested ordered item
- Third unordered item
  1. Nested ordered in third item
  2. Another nested ordered
- Fourth unordered item

1. First ordered item
2. Second ordered item
  - Nested unordered item
  - Another nested unordered item
    1. Deep nested ordered
    2. Another deep ordered
  - Third nested unordered
3. Third ordered item
  - Nested unordered
  - More nested unordered
    1. Very deep ordered
    2. Another very deep
      - Extremely deep unordered
      - More extremely deep
4. Fourth ordered item
