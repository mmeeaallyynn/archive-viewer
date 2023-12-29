/* file_view.vala
 *
 * Copyright 2023 mealynn
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

const double PI = 3.1415926;

namespace ArchiveX {
    public class FileView : Gtk.ApplicationWindow {
        string ui = """
            <interface>
              <object class="GtkButton" id="savebutton">
                <property name="label">Save</property>
                <property name="sensitive">False</property>
              </object>
              <object class="GtkHeaderBar" id="titlebar">
                <property name="title-widget">
                  <object class="GtkLabel" id="titlelabel">
                    <property name="single-line-mode">True</property>
                    <property name="ellipsize">end</property>
                    <property name="width-chars">5</property>
                    <style>
                      <class name="title"/>
                    </style>
                  </object>
                </property>
                <child>
                  <object class="GtkButton" id="upbutton">
                    <property name="label">↑</property>
                  </object>
                </child>
              </object>
              <object class="GtkStack" id="stack">
                <child>
                  <object class="GtkScrolledWindow" id="scrolled_window">
                  </object>
                </child>
                <child>
                  <object class="GtkBox" id="spinner_view">
                    <child>
                      <object class="GtkSpinner" id="spinner"/>
                    </child>
                  </object>
                </child>
                <child>
                  <object class="GtkBox" id="drop_view">
                    <property name="orientation">horizontal</property>
                    <child>
                      <object class="GtkDrawingArea" id="drawing_area_open">
                        <property name="hexpand">True</property>
                        <property name="vexpand">True</property>
                      </object>
                    </child>
                    <child>
                      <object class="GtkDrawingArea" id="drawing_area_add">
                        <property name="hexpand">True</property>
                        <property name="vexpand">True</property>
                      </object>
                    </child>
                  </object>
                </child>
              </object>
            </interface>
        """;

        // The list cells can't have a controller added, so this removes their padding
        // and adds it to the grid inside of the cell instead
        string css = """
            columnview > listview > row > cell {
                padding-top: 0px;
                padding-bottom: 0px;
                padding-left: 0px;
                padding-right: 0px;
            }
            columnview > listview > row > cell grid {
                padding-top: 10px;
                padding-bottom: 10px;
                padding-left: 10px;
                padding-right: 10px;
            }
        """;
        ArchiveX.Archive archive = new ArchiveX.Archive ();
        bool is_modified = false;

        Gtk.Label titlelabel;
        Gtk.SelectionModel selection;

        Gtk.Stack stack;
        Gtk.ScrolledWindow file_view;
        Gtk.Box spinner_view;
        Gtk.Box drop_view;

        Gtk.DrawingArea drawing_area_open;
        Gtk.DrawingArea drawing_area_add;
        bool open_drawing_highlight = false;
        bool add_drawing_highlight = false;

        static string[] column_titles = {
            "File",
            "Size",
            "Type",
            "Modified"
        };

        public FileView (Gtk.Application app) {
            var css_provider = new Gtk.CssProvider ();
            css_provider.load_from_data ((uint8[]) this.css);

            // this is deprecated, but there seems to be no replacement
            Gtk.StyleContext.add_provider_for_display (Gdk.Display.get_default (), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

            this.archive.load_finished.connect (() => {
                var title = this.archive.name + this.archive.get_current_path ();
                this.titlelabel.set_text ((this.is_modified ? "*" : "") + title);
                this.stack.set_visible_child (this.file_view);
            });
            this.archive.load_started.connect (() => {
                this.stack.set_visible_child (this.spinner_view);
            });

            this.close_request.connect (this.on_close);
            this.set_default_size (600, 400);

            var b = new Gtk.Builder.from_string (ui, ui.length);
            this.stack = b.get_object ("stack") as Gtk.Stack;
            this.file_view = b.get_object ("scrolled_window") as Gtk.ScrolledWindow;
            this.spinner_view = b.get_object ("spinner_view") as Gtk.Box;
            this.drop_view = b.get_object ("drop_view") as Gtk.Box;

            this.drawing_area_open = b.get_object ("drawing_area_open") as Gtk.DrawingArea;
            this.drawing_area_open.set_draw_func ((area, ctx, width, height) => {
                this.draw_drop_area ("Open File", this.open_drawing_highlight, area, ctx, width, height);
            });
            this.drawing_area_add = b.get_object ("drawing_area_add") as Gtk.DrawingArea;
            this.drawing_area_add.set_draw_func ((area, ctx, width, height) => {
                this.draw_drop_area ("Add File", this.add_drawing_highlight, area, ctx, width, height);
            });

            var spinner = b.get_object ("spinner") as Gtk.Spinner;
            var titlebar = b.get_object ("titlebar") as Gtk.HeaderBar;
            this.titlelabel = b.get_object ("titlelabel") as Gtk.Label;
            var upbutton = b.get_object ("upbutton") as Gtk.Button;
            var savebutton = b.get_object ("savebutton") as Gtk.Button;
            upbutton.clicked.connect (this.navigate_up);
            titlebar.pack_end (savebutton);

            this.titlelabel.set_text ("ArchiveX");

            this.set_titlebar (titlebar);

            var list = this.create_column_view ();
            this.setup_dnd (list);
            spinner.set_spinning (true);
            spinner.set_size_request (50, 50);
            this.spinner_view.set_halign (Gtk.Align.CENTER);

            this.file_view.set_child (list);
            this.set_child (this.stack);
            this.set_application (app);
        }

        void draw_drop_area (string text, bool highlight, Gtk.DrawingArea area, Cairo.Context ctx, int width, int height) {
            var style = this.get_style_context ();
            Gdk.RGBA color;
            style.lookup_color ("theme_selected_bg_color", out color);
            double cx = width / 2.0;
            double cy = height / 2.0;

            double r = 20.0;
            double offset_x = 10;
            double offset_y = 10;
            double end_x = width - offset_x;
            double end_y = height - offset_y;

            if (!highlight) {
                color.red /= 2;
                color.green /= 2;
                color.blue /= 2;
            }
            ctx.set_source_rgba (color.red, color.green, color.blue, color.alpha);
            ctx.set_dash ({10, 5}, 0);
            ctx.set_font_size (20.0);
            Cairo.TextExtents extents;
            ctx.text_extents (text, out extents);

            double text_x = cx - extents.width / 2;
            double text_y = cy + extents.height / 2;

            ctx.move_to (text_x, text_y);
            ctx.show_text (text);

            ctx.move_to (offset_x, offset_y + r);
            ctx.arc (offset_x + r, offset_y + r, r, PI, 3 * PI / 2);
            ctx.arc (end_x - r, offset_y + r, r, 3 * PI / 2, 0);
            ctx.arc (end_x - r, end_y - r, r, 0, PI / 2);
            ctx.arc (offset_x + r, end_y - r, r, PI / 2, PI);
            ctx.close_path ();
            ctx.stroke ();
        }

        Gtk.ColumnView create_column_view () {
            this.selection  = new Gtk.MultiSelection  (this.archive.list);
            var column_view = new Gtk.ColumnView (selection);
            column_view.activate.connect (this.activate_item);

            foreach (string title in FileView.column_titles) {
                var factory = new Gtk.SignalListItemFactory ();
                factory.setup.connect ((factory, list_item_) => {
                    var list_item = list_item_ as Gtk.ListItem;
                    var grid  = new Gtk.Grid ();
                    var label = new Gtk.Label ("unknown");
                    grid.attach (label, 1, 0);
                    grid.set_valign (Gtk.Align.FILL);

                    if (title == "File") {
                        var icon = new Gtk.Image ();
                        grid.attach (icon, 0, 0);
                        grid.set_column_spacing (5);
                    }

                    list_item.set_child (grid);

                    // by default, the item is selected when the mouse button is released
                    // this selects it on mouse pressed
                    var click = new Gtk.GestureClick ();
                    click.pressed.connect ((n_press, x, y) => {
                        var control_pressed = click.get_current_event_state () & Gdk.ModifierType.CONTROL_MASK;
                        // Don't select when control is pressed, otherwise it will be unselected again on release
                        if (control_pressed == 0) {
                            this.selection.select_item (list_item.position, control_pressed == 0);
                        }
                    });
                    grid.add_controller (click);
                });

                factory.bind.connect((factory, list_item_) => {
                    var list_item = list_item_ as Gtk.ListItem;
                    var grid = list_item.get_child () as Gtk.Grid;
                    var label =  grid.get_child_at (1, 0) as Gtk.Label;
                    var entry = (list_item.get_item () as Entry).info;

                    switch (title) {
                    case "File":
                        var icon = grid.get_child_at (0, 0) as Gtk.Image;
                        icon.set_from_gicon (GLib.ContentType.get_icon (entry.get_content_type ()));
                        label.label = entry.get_name ();
                        break;
                    case "Size":
                        label.label = GLib.format_size(entry.get_size ());
                        break;
                    case "Type":
                        label.label = entry.get_content_type ();
                        break;
                    case "Modified":
                        var datetime = entry.get_modification_date_time ();
                        if (datetime != null) {
                            label.label = datetime.format ("%d %B %Y, %R");
                        }
                        break;
                    }
                });

                var column = new Gtk.ColumnViewColumn (title, factory);
                column.set_resizable (true);
                if (title == "Modified") {
                    column.set_expand (true);
                }
                column_view.append_column (column);
            }

            return column_view;
        }

        void setup_dnd (Gtk.ColumnView list) {
            var drop_target = new Gtk.DropTarget (typeof (GLib.File), Gdk.DragAction.COPY);

            drop_target.enter.connect ((x, y) => {
                this.stack.set_visible_child (this.drop_view);
                return Gdk.DragAction.COPY;
            });
            drop_target.leave.connect (() => {
                this.stack.set_visible_child (this.file_view);
            });
            drop_target.motion.connect ((x, y) => {
                var width = this.stack.get_width ();
                // highlight the the area the cursor is hovering over
                if (x < width / 2) {
                    this.open_drawing_highlight = true;
                    this.add_drawing_highlight = false;
                }
                else {
                    this.open_drawing_highlight = false;
                    this.add_drawing_highlight = true;
                }
                this.drawing_area_open.queue_draw ();
                this.drawing_area_add.queue_draw ();
                return Gdk.DragAction.COPY;
            });
            drop_target.drop.connect ((v, x, y) => {
                var width = this.stack.get_width ();
                var f = v as GLib.File;
                // dropped into the "Open File" area
                if (x < width / 2) {
                    try {
                        var info = f.query_info ("*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                        var content_type = info.get_content_type ();
                        if (content_type in Archive.content_types) {
                            this.open_archive.begin (f.get_path ());
                        }
                        return true;
                    }
                    catch (Error e) {
                        warning ("Can't query file info");
                    }
                    return false;
                }
                // dropped into the "Add File" area
                else {
                    this.is_modified = true;
                    this.archive.add_file (f.get_path ());
                    var title = this.archive.name + this.archive.get_current_path ();
                    this.titlelabel.set_text ((this.is_modified ? "*" : "") + title);
                }
                return false;
            });
            var drag_source = new Gtk.DragSource ();
            drag_source.drag_end.connect ((source, drag) => {
            });
            drag_source.drag_begin.connect ((source, drag) => {
                // TODO: set icon maybe?
            });
            drag_source.prepare.connect ((source, x, y) => {
                // TODO: make it work for multiple files somehow
                var selected = this.selection.get_selection ();

                var files = new GLib.SList<GLib.File> ();
                Gdk.ContentProvider[] content_providers = new Gdk.ContentProvider[selected.get_size ()];

                for (uint i = 0; i < selected.get_size (); i++) {
                    var entry = this.archive.list.get_item (selected.get_nth (i)) as Entry;
                    var info = entry.info;
                    var full_path = this.archive.get_path_in_fs (info.get_name ());
                    var f = GLib.File.new_for_path (full_path);
                    files.append (f);
                    var val = Value (typeof (GLib.File));
                    val.set_instance (f);
                    content_providers[i] = new Gdk.ContentProvider.for_value (val);
                }
                var file_list = new Gdk.FileList.from_list (files);

                var finalc = new Gdk.ContentProvider.union (content_providers);
                return finalc;
            });
            list.add_controller (drag_source);
            this.stack.add_controller (drop_target);
        }

        bool on_close () {
            stdout.printf ("got close request\n");
            this.archive.close ();
            return false;
        }

        public async void open_archive (string filename) {
            stdout.printf ("open archive\n");
            this.titlelabel.set_text ("Loading Archive...");
            this.stack.set_visible_child (this.spinner_view);
            try {
                this.archive.close ();
                yield this.archive.open (filename);
            }
            catch (GLib.FileError e) {
                this.archive.close ();
                this.archive.load_finished ();
                warning ("Can't create tmpdir: %s\n", e.message);
            }
            catch (ArchiveX.ArchiveFSError e) {
                this.archive.close ();
                this.archive.load_finished ();
                warning ("Can't mount archive: %s\n", e.message);
            }
            catch (GLib.Error e) {
                this.archive.close ();
                this.archive.load_finished ();
                warning ("Can't launch archivefs: %s\n", e.message);
            }
        }

        public async void activate_item (uint position) {
            var entry = this.archive.list.get_item (position) as Entry;
            var info = entry.info;

            if (info.get_file_type () == GLib.FileType.DIRECTORY) {
                try {
                    yield this.archive.chdir (info.get_name ());
                }
                catch (GLib.Error e) {
                    warning ("Can't chdir up: %s", e.message);
                }
            }
            else {
                try {
                    AppInfo.launch_default_for_uri ("file://" + entry.path, null);
                }
                catch (Error e) {
                    warning ("Can't open %s: %s", entry.path, e.message);
                }
            }

            stdout.printf ("activated %s\n", info.get_name ());
        }

        async void navigate_up () {
            try {
                yield this.archive.chdir ("..");
            }
            catch (GLib.Error e) {
                warning ("Can't cd: %s", e.message);
            }
        }
    }
}

