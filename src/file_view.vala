namespace ArchiveX {
    public class FileView : Gtk.ApplicationWindow {
        string ui = """
            <interface>
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
        public ArchiveX.Archive archive = new ArchiveX.Archive ();

        Gtk.Label titlelabel;
        Gtk.SelectionModel selection;

        Gtk.Stack stack;
        Gtk.ScrolledWindow file_view;
        Gtk.Box spinner_view;

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
                this.titlelabel.set_text (this.archive.name + this.archive.get_current_path ());
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
            var spinner = b.get_object ("spinner") as Gtk.Spinner;
            var titlebar = b.get_object ("titlebar") as Gtk.HeaderBar;
            this.titlelabel = b.get_object ("titlelabel") as Gtk.Label;
            var upbutton = b.get_object ("upbutton") as Gtk.Button;
            upbutton.clicked.connect (this.navigate_up);

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

        Gtk.ColumnView create_column_view () {
            this.selection  = new Gtk.MultiSelection  (this.archive.list);
            var column_view = new Gtk.ColumnView (selection);
            column_view.activate.connect (this.activate_item);

            foreach (string title in FileView.column_titles) {
                var factory = new Gtk.SignalListItemFactory ();
                factory.setup.connect ((factory, list_item) => {
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

                factory.bind.connect((factory, list_item) => {
                    var grid = list_item.get_child () as Gtk.Grid;
                    var label =  grid.get_child_at (1, 0) as Gtk.Label;
                    var entry = list_item.get_item () as GLib.FileInfo;

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

            drop_target.motion.connect ((x, y) => {
                return Gdk.DragAction.COPY;
            });
            drop_target.drop.connect ((v, x, y) => {
                var f = v as GLib.File;
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
                    var info = this.archive.list.get_item (selected.get_nth (i)) as GLib.FileInfo;
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
            list.add_controller (drop_target);
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
            var info = this.archive.list.get_item (position) as GLib.FileInfo;

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
                    AppInfo.launch_default_for_uri ("file://" + this.archive.get_path_in_fs (info.get_name ()), null);
                }
                catch (Error e) {
                    warning ("Can't open %s: %s", info.get_name (), e.message);
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

