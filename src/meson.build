adwvalatest_sources = [
  'main.vala',
  'application.vala',
  'file_view.vala',
  'archive.vala',
]

adwvalatest_deps = [
  dependency('gtk4'),
  dependency('libadwaita-1'),
  dependency('gee-0.8'),
  meson.get_compiler('vala').find_library('posix'),
]

executable('adwvalatest', adwvalatest_sources,
  dependencies: adwvalatest_deps,
       install: true,
)
