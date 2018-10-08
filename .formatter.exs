locals_without_parens = [
  add: 2,
  add: 3,
  alter: 2,
  create: 1,
  create: 2,
  create_if_not_exists: 1,
  create_if_not_exists: 2,
  drop: 1,
  drop_if_exists: 1,
  execute: 1,
  execute: 2,
  modify: 2,
  modify: 3,
  remove: 1,
  remove: 2,
  remove: 3,
  rename: 2,
  rename: 3,
  timestamps: 1
]

[
  import_deps: [:ecto],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
