archivex_sources = [
  'main.vala',
  'application.vala',
  'file_view.vala',
  'archive.vala',
]

archivex_deps = [
  dependency('gtk4'),
  dependency('libadwaita-1'),
  dependency('gee-0.8'),
  meson.get_compiler('vala').find_library('posix'),
]

executable('archivex', archivex_sources,
  dependencies: archivex_deps,
       install: true,
)
