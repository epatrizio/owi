memory stuff:
  $ dune exec owi -- sym memory.wat --no-stop-at-failure
  All OK
  $ dune exec owi -- sym grow.wat --no-stop-at-failure
  Trap: out of bounds memory access
  Model:
    (model
      (symbol_0 (i32 1)))
  Reached 1 problems!
  [1]
  $ dune exec owi -- sym store.wat
  Trap: out of bounds memory access
  Model:
    (model
      (symbol_0 (i32 -11)))
  Reached problem!
  [1]
