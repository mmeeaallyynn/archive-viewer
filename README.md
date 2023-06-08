# WIP: Archive Viewer

A simple Gtk4 read-only archive viewer with support for extracting via drag-and-drop under Wayland.

All heavy lifting is done by [archivefs](https://github.com/bugnano/archivefs):  
The archive is mounted into a `tmp` folder, so that dragged files are just copied to the target location. The extraction is simply handled by archivefs itself.

The GUI just displays this folder and manages automatic mounting and unmounting.

## Plans

- Support for writing archives using an overlay folder
- Drag and drop multiple files at once (if I find a way)
- Keep parent archive alive when oping nested archives
- Create full UI
- Better mounting integration without subprocesses

##  Building

- Install [archivefs](https://github.com/bugnano/archivefs)
- Clone this repository
- `meson setup build`
- `ninja -C build all`
